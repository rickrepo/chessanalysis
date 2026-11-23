-- AuctionMesh Diag: shareable debug log + one gate for every auction house request.
--
-- Log
--   Every C_AuctionHouse call (ours AND the Blizzard AH window's), every AH
--   error / throttle event, and what AuctionMesh was trying to do, with
--   millisecond timestamps. Starts empty on every /reload or login (last 800
--   lines kept; the previous session is available with /amesh log old).
--   /amesh log  opens a window: Ctrl+A, Ctrl+C, paste it to Claude.
--
-- Gate
--   The AH server handles one request at a time. All AuctionMesh requests
--   (searches, browse pages, posts, purchases) go through Gate:Ready()/Use():
--     * waits until the client says the AH is ready AND the server has answered
--       our previous request (THROTTLED_MESSAGE_SENT / RESPONSE_RECEIVED)
--     * keeps a minimum spacing between requests (0.6s to start)
--     * on "Internal auction error" or a dropped message: pause 5s and widen
--       the spacing (up to 3s); it relaxes again after a minute without errors.
local ADDON, ns = ...
ns = ns or {}

local Diag = {}
ns.Diag = Diag

local MAX_LINES = 800
local buf, n = {}, 0 -- in-memory ring, flushed to SavedVariables on logout

local function stamp()
    local t = GetTime and GetTime() or 0
    return ("%s %.3f"):format(date and date("%H:%M:%S") or "", t)
end

function ns.Log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    n = n + 1
    buf[n] = stamp() .. "  " .. line
    if n > MAX_LINES * 1.25 then
        local keep = {}
        for i = n - MAX_LINES + 1, n do keep[#keep + 1] = buf[i] end
        buf, n = keep, #keep
    end
end
local Log = ns.Log

-- Compact description of API arguments (itemKeys, item locations, query tables).
local function describe(v, depth)
    local t = type(v)
    if t == "table" then
        if v.itemID then
            return ("key{%s/%s/%s/%s}"):format(v.itemID, v.itemLevel or 0, v.itemSuffix or 0, v.battlePetSpeciesID or 0)
        end
        if v.GetBagAndSlot then
            local ok, b, s = pcall(v.GetBagAndSlot, v)
            return ok and ("loc{%s:%s}"):format(tostring(b), tostring(s)) or "loc{?}"
        end
        if (depth or 0) > 1 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. describe(x, (depth or 0) + 1)
            if #parts >= 6 then parts[#parts + 1] = "..."; break end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function args(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = describe((select(i, ...))) end
    return table.concat(out, ", ")
end

---------------------------------------------------------------- the throttle watch

-- EVERYTHING THAT MADE A REQUEST WAIT, written down with what caused it.
-- The log only holds the last few minutes, so this is kept separately for the
-- whole session and printed in the Snapshot. Every incident is also one log
-- line that starts with THROTTLE.
--
--   QUEUED     a request was sent while the auction house was still locked by
--              the one before it: the game held it back. Says which request
--              waited, how long, and which one held the lock.
--   SLOW       the lock stayed shut much longer than usual after a request.
--   BACKOFF    the game refused or dropped a request, or showed an auction
--              house error: the addon stops for 5 seconds.
--   NO-ANSWER  a request was never answered (or never transmitted).
--   GAME-UI    one of the game's own screens made a request: the addon stays
--              silent for a moment so it does not get in its way.
--   PACE       the pause the addon keeps between requests changed.
--   STALL      nothing at all was sent for more than 3 seconds while the
--              panel was open, with the reason. (A deal on screen holds the
--              radar on purpose: those are counted, not listed.)
--
-- Cost: a few table writes per request. Nothing here sends anything.
local Watch = { calls = {}, times = {}, list = {}, count = {}, lost = {}, worst = {}, byCall = {}, hist = {}, sends = 0, slowest = 0 }
ns.Watch = Watch
Watch.BUCKETS = { { 0.5, "under 0.5s" }, { 0.6, "0.5-0.6s" }, { 0.7, "0.6-0.7s" }, { 0.8, "0.7-0.8s" }, { 1.0, "0.8-1s" }, { 2.0, "1-2s" }, { math.huge, "over 2s" } }
Watch.KINDS = { "QUEUED", "SLOW", "BACKOFF", "NO-ANSWER", "GAME-UI", "PACE", "STALL" }
local WATCH_KEEP = 40

function Watch:Reset()
    self.calls, self.times, self.list, self.count, self.lost, self.worst, self.byCall, self.hist = {}, {}, {}, {}, {}, {}, {}, {}
    self.sends, self.slowest, self.firstAt, self.lastCallAt, self.stall, self.queued, self.lastGameUI = 0, 0, nil, nil, nil, nil, nil
    self.total, self.recent, self.radarAt, self.between = {}, {}, nil, nil
    self.gapN, self.gapSum, self.gapWorst, self.gapLate, self.gapBy = 0, 0, 0, 0, {}
    self.lostAt, self.idleAt, self.readyAt, self.holdSeen, self.pauseSeen, self.speedLogAt = {}, {}, nil, nil, nil, nil
end

-- WHAT THE REQUESTS WENT TO. Every request the addon sends is booked under
-- one purpose, so the panel and the Snapshot can show how many went to the
-- radar and how many to anything else:
--   radar    a read of the materials class (the main radar)
--   alert    an item check the radar asked for (a price worth a look)
--   buy      your purchases: price request, purchase, re-check of a deal
--   upkeep   everything else: listings kept ready, side classes, prices of
--            what you hold, the list of your own auctions
--   sell     posting and cancelling (your clicks)
Watch.PURPOSES = { "radar", "alert", "buy", "upkeep", "sell" }
Watch.PURPOSE_NAMES = { radar = "radar reads", alert = "alert checks", buy = "buying", upkeep = "upkeep", sell = "posting" }
function Watch:Book(purpose)
    purpose = purpose or "upkeep"
    local now = GetTime()
    self.total = self.total or {}
    self.total[purpose] = (self.total[purpose] or 0) + 1
    local r = self.recent or {}
    self.recent = r
    r[#r + 1] = { t = now, p = purpose }
    while r[1] and now - r[1].t > 60 do table.remove(r, 1) end
    if purpose == "radar" then
        -- seconds between two radar reads in a row, and what came between them
        local last = self.radarAt
        self.radarAt = now
        if last and now - last < 30 then
            local g = now - last
            self.gapN, self.gapSum = (self.gapN or 0) + 1, (self.gapSum or 0) + g
            if g > (self.gapWorst or 0) then self.gapWorst = g end
            local usual = (ns.Gate and ns.Gate.cycle) or 0.65
            if g > usual * 1.35 + 0.1 then
                self.gapLate = (self.gapLate or 0) + 1
                self.gapBy = self.gapBy or {}
                local why = self.between or "nothing (the radar itself was late)"
                self.gapBy[why] = (self.gapBy[why] or 0) + 1
            end
        end
        self.between = nil
    else
        self.between = self.between and (self.between == purpose and purpose or "several") or purpose
    end
end
-- The last 60 seconds: requests by purpose, and seconds between radar reads.
function Watch:LastMinute()
    local now, out = GetTime(), { n = 0 }
    local r = self.recent or {}
    while r[1] and now - r[1].t > 60 do table.remove(r, 1) end
    local first, last, reads = nil, nil, 0
    for _, e in ipairs(r) do
        out[e.p] = (out[e.p] or 0) + 1
        out.n = out.n + 1
        if e.p == "radar" then
            first = first or e.t
            last, reads = e.t, reads + 1
        end
    end
    out.every = (reads >= 2) and (last - first) / (reads - 1) or nil
    out.other = out.n - (out.radar or 0)
    return out
end

-- SPEED, IN NUMBERS (the Buy tab's status line, and one log line a minute).
-- The game takes one request at a time and keeps its lock shut for a fixed
-- time after each answer; nothing the addon does can shorten that. What the
-- addon CAN lose is measured here, over the last 60 seconds on the Buy tab:
--   idle   seconds the lock was open and the addon had not sent the next
--          request yet (measured from the game's "ready" to the next "sent")
--   lost   radar reads that got no answer, and the seconds they cost
--   held   seconds the lock was left open on purpose: a deal was on screen
--          (so that your press goes first) or a purchase was in progress.
--          Not counted against the speed.
-- SPEED = the share of the time (without what was held) that was not idle
-- and not spent on a lost read. 100% = every request left the moment the
-- game allowed it and every one was answered.
function Watch:Ready()
    local U = ns.UI
    local open = U and U.IsShown and U:IsShown() and U.tab == "BUY"
    self.readyAt = open and GetTime() or nil
end
function Watch:Idle()
    local at = self.readyAt
    self.readyAt = nil
    if not at then return end
    local U = ns.UI
    if not (U and U.IsShown and U:IsShown() and U.tab == "BUY") then return end
    local now = GetTime()
    local secs = now - at
    if secs <= 0 or secs > 30 then return end
    if (self.pauseSeen or -1) >= at then return end -- (the panel was shut or one of the game's screens was up: not the addon's time)
    local S = ns.Sniper
    local held = ((self.holdSeen or -1) >= at) or (S and S.buying ~= nil) or false
    local l = self.idleAt or {}
    self.idleAt = l
    l[#l + 1] = { t = now, secs = secs, held = held }
end
function Watch:Speed()
    local now = GetTime()
    local m = self:LastMinute()
    local function sum(list, f)
        list = list or {}
        while list[1] and now - list[1].t > 60 do table.remove(list, 1) end
        for _, e in ipairs(list) do f(e) end
    end
    m.idle, m.held, m.lost, m.lostSecs = 0, 0, 0, 0
    sum(self.idleAt, function(e) if e.held then m.held = m.held + e.secs else m.idle = m.idle + e.secs end end)
    sum(self.lostAt, function(e) m.lost, m.lostSecs = m.lost + 1, m.lostSecs + e.secs end)
    local r = self.recent or {}
    m.span = r[1] and math.min(60, now - r[1].t) or 0
    m.lock = ns.Gate and ns.Gate.cycle or nil
    m.tail = ns.Gate and ns.Gate.tail or nil
    local worked = m.span - m.held
    if m.n >= 10 and worked > 5 then
        m.pct = math.max(0, math.min(1, 1 - (m.idle + m.lostSecs) / worked))
    end
    return m
end
function Watch:SpeedText()
    local m = self:Speed()
    return ("%s | lock unused %.1fs | reads lost %d (%.1fs) | held for a deal %.1fs | %d requests in %.0fs: radar %d, alerts %d, buying %d, upkeep %d, posting %d | lock %s a request%s")
        :format(m.pct and ("%d%%"):format(math.floor(m.pct * 100 + 0.5)) or "not measured yet", m.idle, m.lost, m.lostSecs, m.held, m.n, m.span,
            m.radar or 0, m.alert or 0, m.buy or 0, m.upkeep or 0, m.sell or 0, m.lock and ("%.2fs"):format(m.lock) or "?",
            m.tail and (" (%.2fs after an answer)"):format(m.tail) or ""), m
end

-- Every auction house call, ours or the game's. desc = what it was for.
function Watch:Call(name, desc, ours)
    local now = GetTime()
    local c = self.calls
    c[#c + 1] = { t = now, name = name, desc = desc, ours = ours }
    if #c > 8 then table.remove(c, 1) end
    local ts = self.times
    ts[#ts + 1] = now
    if #ts > 64 then table.remove(ts, 1) end
    self.sends = self.sends + 1
    if not self.firstAt then self.firstAt = now end
    -- the end of a stall
    local st = self.stall
    if st then
        self.stall = nil
        self:Add(st.hold and "HOLD" or "STALL", now - st.since, ("nothing was sent for %.1fs: %s"):format(now - st.since, st.why), st.hold)
    end
    self.lastCallAt = now
end

-- The last requests before now, newest first, and how busy the last seconds were.
function Watch:Context(skip)
    local now, parts = GetTime(), {}
    local c = self.calls
    for i = #c - (skip or 0), math.max(1, #c - (skip or 0) - 2), -1 do
        local e = c[i]
        parts[#parts + 1] = ("%s %.2fs ago%s"):format(tostring(e.desc or e.name), now - e.t, e.ours and "" or " (the game's own)")
    end
    local n2, n10 = 0, 0
    for i = #self.times, 1, -1 do
        local age = now - self.times[i]
        if age <= 2 then n2 = n2 + 1 end
        if age <= 10 then n10 = n10 + 1 else break end
    end
    return (#parts > 0 and table.concat(parts, "; ") or "nothing") .. (" | %d requests in the last 2s, %d in the last 10s"):format(n2, n10)
end

-- One incident. secs = the time it cost (nil if none). quiet = counted only.
function Watch:Add(kind, secs, text, quiet)
    if kind == "NO-ANSWER" then -- (with its time, for the SPEED figures of the last minute)
        self.lostAt = self.lostAt or {}
        self.lostAt[#self.lostAt + 1] = { t = GetTime(), secs = secs or 0 }
    end
    self.count[kind] = (self.count[kind] or 0) + 1
    self.lost[kind] = (self.lost[kind] or 0) + (secs or 0)
    if secs and secs > (self.worst[kind] or 0) then self.worst[kind] = secs end
    if quiet then return end
    local ctx = self:Context()
    local l = self.list
    l[#l + 1] = { clock = date and date("%H:%M:%S") or "", kind = kind, secs = secs, text = text, ctx = ctx }
    if #l > WATCH_KEEP then table.remove(l, 1) end
    ns.Log("THROTTLE %s%s: %s | before it: %s", kind, secs and (" %.2fs"):format(secs) or "", tostring(text), ctx)
end

-- The game held a request back (QUEUED) and has now sent it.
function Watch:Queued()
    self.queued = { at = GetTime() }
end
function Watch:Sent()
    local q = self.queued
    if not q then return end
    self.queued = nil
    -- which request was it? The one made at the moment the game said "queued"
    -- (the game's event and the call can arrive in either order).
    do
        local c, best = self.calls, nil
        for i = #c, 1, -1 do
            local d = math.abs(c[i].t - q.at)
            if d < 0.1 and (not best or d < math.abs(c[best].t - q.at)) then best = i end
        end
        best = best or #c
        q.call, q.holder = c[best], c[best - 1]
    end
    local wait = GetTime() - q.at
    local name = q.call and q.call.name or "?"
    local b = self.byCall[name] or { n = 0, total = 0, worst = 0 }
    self.byCall[name] = b
    b.n, b.total = b.n + 1, b.total + wait
    if wait > b.worst then b.worst = wait end
    do  -- the price request of the try in progress: how long the game held it (for the timing line on the panel)
        local ti = ns.Sniper and ns.Sniper.tryInfo
        if ti and name == "StartCommoditiesPurchase" and not ti.held then ti.held = wait end
    end
    -- A stake-out asks the price with every input, so its requests are queued
    -- all the time: those are counted, and listed only when the wait is long.
    local stake = q.call and tostring(q.call.desc or ""):find("^stake%-out") ~= nil
    local quiet = wait < 0.05 or (stake and wait < 0.75)
    self:Add("QUEUED", wait, ("'%s' waited %.2fs: the auction house was still locked by '%s', sent %.2fs before it")
        :format(tostring(q.call and (q.call.desc or q.call.name) or "?"), wait,
            tostring(q.holder and (q.holder.desc or q.holder.name) or "an earlier request"), (q.call and q.holder) and (q.call.t - q.holder.t) or 0), quiet)
end

-- Seconds from a request being sent to the lock opening again.
function Watch:Cycle(dt, usual)
    for i, b in ipairs(self.BUCKETS) do
        if dt < b[1] then self.hist[i] = (self.hist[i] or 0) + 1; break end
    end
    if dt > self.slowest then self.slowest = dt end
    local limit = math.max(1.0, (usual or 0.65) * 1.6)
    if dt >= limit then
        local c = self.calls[#self.calls]
        self:Add("SLOW", dt - (usual or 0.65), ("the lock stayed shut %.2fs after '%s' (usual: %.2fs)")
            :format(dt, tostring(c and (c.desc or c.name) or "?"), usual or 0.65))
    end
end

-- Why nothing is being sent right now (for a stall). Second value: true when
-- it is the hold the addon keeps on purpose while a deal is on screen.
function Watch:WhyIdle()
    local G, now = ns.Gate, GetTime()
    local S, Sw = ns.Sniper, ns.Swarm
    if now < (G.holdUntil or 0) then return "a deal is on screen: the radar holds so that your purchase goes first", true end
    if S and S.buying then return "a purchase is in progress (" .. tostring(S.buying.phase) .. ")", true end
    if now < (G.userUntil or 0) then return "one of the game's own screens made a request; the addon is staying silent" end
    if now < (G.nextAt or 0) and now - (G.lastError or -100) < 6 then return "5-second stop after an error or a refused request" end
    if (G.outstanding or 0) > 0 then return "a request has not been answered yet" end
    if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return "the auction house reports it is not ready (its lock is shut)"
    end
    if Sw and Sw.blocked and Sw.blocked >= 3 then return "the game blocked the radar's reads" end
    if Sw and not Sw.active then return "the radar is not running" end
    if S and S.Staking and S:Staking() then return "a stake-out is running and no input arrived" end
    return "no reason found by the addon"
end

-- Once a second while the panel is open: has anything been sent lately?
function Watch:Tick()
    local U = ns.UI
    local open = AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() and U and U.IsShown and U:IsShown()
    if not open then self.stall, self.lastCallAt = nil, nil; return end
    local now = GetTime()
    if U.tab == "BUY" and now - (self.speedLogAt or 0) >= 60 then -- the figures of the last minute, once a minute
        if self.speedLogAt then ns.Log("SPEED %s", (self:SpeedText())) end
        self.speedLogAt = now
    end
    if not self.lastCallAt then self.lastCallAt = now; return end
    if now - self.lastCallAt < 3 then return end
    local why, hold = self:WhyIdle()
    local st = self.stall
    if not st then
        self.stall = { since = self.lastCallAt, why = why, hold = hold }
    elseif st.hold and not hold then
        st.why, st.hold = why, false -- it started as a deal hold and went on for another reason
    end
end

-- The block for the Snapshot.
function Watch:Lines()
    local out = {}
    local function add(...) out[#out + 1] = table.concat({ ... }) end
    local mins = self.firstAt and (GetTime() - self.firstAt) / 60 or 0
    local usual = ns.Gate and ns.Gate.cycle
    add("THROTTLE WATCH this session: ", self.sends, " auction house requests in ", ("%.0f"):format(mins), " min | lock time per request: usual ",
        usual and ("%.2fs"):format(usual) or "not measured yet", ", slowest ", ("%.2fs"):format(self.slowest))
    do
        local parts = {}
        for i, b in ipairs(self.BUCKETS) do if (self.hist[i] or 0) > 0 then parts[#parts + 1] = b[2] .. ": " .. self.hist[i] end end
        add("lock time, how many requests: ", #parts > 0 and table.concat(parts, " | ") or "none measured")
    end
    do  -- where the requests went, and whether the radar read back to back
        local parts, all = {}, 0
        for _, p in ipairs(self.PURPOSES) do all = all + ((self.total and self.total[p]) or 0) end
        for _, p in ipairs(self.PURPOSES) do
            local n = (self.total and self.total[p]) or 0
            parts[#parts + 1] = ("%s %d (%d%%)"):format(self.PURPOSE_NAMES[p], n, all > 0 and math.floor(n * 100 / all + 0.5) or 0)
        end
        add("what the addon's requests went to: ", table.concat(parts, " | "))
        local m = self:LastMinute()
        -- (one line: the speed figures hold the last minute's requests by purpose as well)
        add("speed, last 60 seconds: ", (self:SpeedText()), m.every and (" | a radar read every %.2fs"):format(m.every) or "")
        local n = self.gapN or 0
        local late = {}
        for why, c in pairs(self.gapBy or {}) do late[#late + 1] = ("%s: %d"):format(self.PURPOSE_NAMES[why] or why, c) end
        table.sort(late)
        add("time between radar reads: ", n > 0 and ("average %.2fs over %d reads, longest %.2fs"):format(self.gapSum / n, n, self.gapWorst or 0) or "not measured yet",
            " | reads that left late: ", self.gapLate or 0, #late > 0 and (" (what was sent in between: " .. table.concat(late, ", ") .. ")") or "")
    end
    do
        local parts = {}
        for _, k in ipairs(self.KINDS) do
            local n = self.count[k] or 0
            parts[#parts + 1] = k .. " " .. n .. ((n > 0 and (self.lost[k] or 0) > 0) and (" (%.1fs in all, worst %.2fs)"):format(self.lost[k], self.worst[k] or 0) or "")
        end
        add("what made requests wait: ", table.concat(parts, " | "))
        add("held on purpose (a deal on screen or a purchase in progress): ", self.count.HOLD or 0, " time(s), ", ("%.0fs"):format(self.lost.HOLD or 0), " in all",
            " | errors that answered your own purchase, post or cancel (no stop, not counted against the pace): ", self.count["PURCHASE-ERROR"] or 0)
    end
    do
        local parts = {}
        for name, b in pairs(self.byCall) do
            parts[#parts + 1] = ("%s %d (average %.2fs, worst %.2fs)"):format(name, b.n, b.total / math.max(1, b.n), b.worst)
        end
        table.sort(parts)
        add("requests the game held back, by kind: ", #parts > 0 and table.concat(parts, " | ") or "none")
    end
    local l = self.list
    if #l == 0 then
        add("incidents: none")
    else
        -- newest first: up to 6 held-back requests and up to 12 of everything
        -- else, so that the common kind does not push the rare ones out
        add("incidents, newest first:")
        local nq, no = 0, 0
        for i = #l, 1, -1 do
            local e = l[i]
            local show
            if e.kind == "QUEUED" then nq = nq + 1; show = nq <= 6 else no = no + 1; show = no <= 12 end
            if show then
                add("  ", e.clock, " ", e.kind, e.secs and (" %.2fs"):format(e.secs) or "", ": ", tostring(e.text), " | before it: ", tostring(e.ctx))
            end
        end
    end
    return out
end

---------------------------------------------------------------- the gate

-- MEASURED LIMIT (from real logs of this client): the auction house takes one
-- request at a time. The server answers in ~0.15s, then the client stays locked
-- for ~0.5s more and fires AUCTION_HOUSE_THROTTLED_SYSTEM_READY. Floor: one
-- request per ~0.62s (about 1.6 a second), whatever the request is (category
-- sweep, item search, next page, price quote, post).
-- So: no extra spacing of our own (it only wastes budget), and the next
-- request is sent from the READY event itself instead of from a polling timer.
local Gate = { interval = 0.05, nextAt = 0, outstanding = 0, changedAt = 0, lastError = 0, errors = 0, sentCount = 0 }
ns.Gate = Gate

-- True when background work must stay silent: the AuctionMesh panel is not
-- open, or the game's own UI sent
-- an auction request in the last 8s. Moving the mouse over the auction house
-- window does NOT pause anything.
local BLIZZ = { "ItemSellFrame", "CommoditiesSellFrame", "ItemBuyFrame", "CommoditiesBuyFrame", "WoWTokenSellFrame" }
function Gate:UserBusy()
    if GetTime() < (self.userUntil or 0) then Watch.pauseSeen = GetTime(); return true end
    -- A deal has just appeared: nothing else is sent, so the auction house is
    -- free the instant you click Buy.
    if GetTime() < (self.holdUntil or 0) then Watch.holdSeen = GetTime(); return true end
    -- The mouse resting on a button pauses nothing. (It used to: with the
    -- mouse on Post, the price check that Post was waiting for could not run;
    -- with the mouse on Buy, the radar stood still.)
    local ah = AuctionHouseFrame
    if type(ah) ~= "table" or not (ah.IsShown and ah:IsShown()) then return false end
    -- AuctionMesh only works while its own panel is open. On the game's own
    -- auction screens it sends nothing, so it never changes what the game shows you.
    if not (ns.UI and ns.UI:IsShown()) then Watch.pauseSeen = GetTime(); return true end
    if ns.UI.docked then return false end
    -- Separate-window mode: stay quiet while one of the game's sell/buy dialogs is up.
    for _, name in ipairs(BLIZZ) do
        local f = rawget(ah, name)
        if type(f) == "table" and f.IsShown and f:IsShown() then Watch.pauseSeen = GetTime(); return true end
    end
    return false
end

function Gate:Ready()
    local now = GetTime()
    if self:UserBusy() then return false end
    -- Safety: if the server never confirmed, don't wait forever.
    if self.outstanding > 0 and now - self.changedAt > 5 then self.outstanding = 0 end
    -- AFTER AN ERROR THE GAME SAYS "READY" AT ONCE, AND THE NEXT REQUEST IS LOST.
    -- After a normal answer the game keeps its lock shut for a fixed time (0.40s
    -- in a real log: Gate.tail, measured). After an answer that is an error (a
    -- refused purchase, the error that answers a cancelled price request) it
    -- reports ready straight away. A radar read sent then came back as an
    -- error with no data, both times in that log (sent 0.13s and 0.25s after
    -- the request before it), and each cost half a second with no radar. So
    -- background requests wait out the usual time after an error as well.
    -- (That the server refuses them for coming too soon is an inference from
    -- those two reads; "radar reads lost" in the SPEED line shows whether it holds.)
    -- Your own purchases are not held by this: see ReadyForUser.
    local tail = self.tail
    if tail and self.errAt and now < self.errAt + tail * 0.9 then
        if not self.wake then
            self.wake = true
            C_Timer.After(self.errAt + tail * 0.9 - now + 0.005, function()
                Gate.wake = nil
                if ns.OnAHReady then ns.OnAHReady() end
            end)
        end
        return false
    end
    return now >= self.nextAt and self.outstanding <= 0 and C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- Your own clicks (Buy, Confirm, Post) don't wait for the background spacing:
-- they only need the server to be ready and no error back-off in progress.
-- Background scanning then waits its turn behind the click.
function Gate:ReadyForUser()
    local now = GetTime()
    if self.outstanding > 0 and now - self.changedAt > 5 then self.outstanding = 0 end
    return now >= (self.penaltyUntil or 0) and C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- Call right before sending a request.
-- kind ("browse", "page", "search", "more") marks a background request the
-- Tuner learns from; your own clicks pass no kind.
-- purpose: what the request is for, booked by the throttle watch ("radar",
-- "alert", "buy", "upkeep", "sell"; see Watch:Book).
function Gate:Use(what, kind, purpose)
    self.nextAt = GetTime() + self.interval
    self.usedAt = GetTime()
    self.uses = (self.uses or 0) + 1 -- a count, for "did that call send something?" (two sends can share one clock reading)
    self.lastWhat = what
    if ns.Tuner then ns.Tuner:Sent(kind) end
    Watch:Book(purpose)
    Log("SEND %s", what)
end

function Gate:Penalize(why)
    local now = GetTime()
    self.errors, self.lastError = self.errors + 1, now
    self.nextAt = now + 5
    self.penaltyUntil = now + 2
    -- The Tuner decides whether the pace itself has to change (and remembers it).
    local counted = ns.Tuner and ns.Tuner:Failed(why)
    Log("GATE backoff (%s): pause 5s%s", why, counted and "; counted against the current pace" or "")
    Watch:Add("BACKOFF", 5, ("%s: the addon stops for 5 seconds%s"):format(tostring(why), counted and " (counted against the current pace)" or ""))
end

---------------------------------------------------------------- hooks & events

local HOOKED = {
    "SendSearchQuery", "SendSellSearchQuery", "SendBrowseQuery", "RequestMoreBrowseResults",
    "RefreshCommoditySearchResults", "RefreshItemSearchResults", "RequestMoreItemSearchResults",
    "RequestMoreCommoditySearchResults", "ReplicateItems", "PostItem", "PostCommodity",
    "ConfirmPostItem", "ConfirmPostCommodity", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase",
    "CancelCommoditiesPurchase", "PlaceBid", "CancelAuction", "QueryOwnedAuctions", "QueryBids",
}

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "UI_ERROR_MESSAGE", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_SHOW_NOTIFICATION", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "REPLICATE_ITEM_LIST_UPDATE", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN", "AUCTION_HOUSE_PURCHASE_COMPLETED", "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "PLAYER_MONEY", "BIDS_UPDATED",
}

local function isAHError(msg)
    if not msg then return false end
    msg = tostring(msg)
    return (ERR_AUCTION_DATABASE_ERROR and msg == ERR_AUCTION_DATABASE_ERROR)
        or msg:lower():find("auction") ~= nil
end

local function onEvent(_, event, ...)
    if event == "AUCTION_HOUSE_SHOW_ERROR" or event == "COMMODITY_PURCHASE_FAILED" then
        Gate.errAt = GetTime() -- (see Gate:Ready: background requests wait out the usual lock after an error too)
    end
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        do  -- MEASURE how long the lock stays shut after an answer (errors, which open it at once, are left out)
            local ra, now = Gate.respAt, GetTime()
            Gate.respAt = nil
            if ra and not (Gate.errAt and Gate.errAt >= ra) then
                local dt = now - ra
                if dt > 0.2 and dt < 3 then
                    Gate.tailN = (Gate.tailN or 0) + 1
                    Gate.tailRaw = Gate.tailRaw and (Gate.tailRaw * 0.9 + dt * 0.1) or dt
                    if Gate.tailN >= 5 then Gate.tail = Gate.tailRaw end
                end
            end
        end
        Watch:Ready()
        -- MEASURE the limit itself: seconds from a request being sent to the lock
        -- opening again, smoothed. The sweep interval is computed from this live
        -- figure, so if the server slows down at busy times the addon follows.
        if Gate.sentAt then
            local dt = GetTime() - Gate.sentAt
            Gate.sentAt = nil
            if dt < 10 then Watch:Cycle(dt, Gate.cycle) end -- (longer than that is the auction house having been closed, not a slow lock)
            if ns.Tuner then ns.Tuner:Answered(dt) end
            if dt > 0.2 and dt < 10 then
                local old = Gate.cycle
                Gate.cycle = old and (old * 0.9 + dt * 0.1) or dt
                Gate.cycleN = (Gate.cycleN or 0) + 1
                if ns.Swarm and Gate.cycleN >= 5 and not (ns.Tuner and ns.Tuner.d) then
                    ns.Swarm.cfg.perRequest = math.max(0.4, math.min(3, Gate.cycle))
                end
                local shown = Gate.cycleShown
                if Gate.cycleN >= 10 and (not shown or math.abs(Gate.cycle - shown) > shown * 0.2) then
                    Gate.cycleShown = Gate.cycle
                    Log("LIMIT measured: %.2fs per request (%.1f a second) over %d requests", Gate.cycle, 1 / Gate.cycle, Gate.cycleN)
                end
            end
        end
        -- "Ready" is the game saying nothing of ours is in flight any more. (A
        -- kind of request the game never sends an answer event for would
        -- otherwise have held everything back for 5 seconds.)
        Gate.outstanding = 0
        -- The lock just opened: send the next request this very frame, unless
        -- the Tuner has learned that this server needs a short pause first.
        local gap = ns.Tuner and ns.Tuner:Gap() or 0
        if gap > 0 then
            Gate.nextAt = math.max(Gate.nextAt, GetTime() + gap)
            C_Timer.After(gap + 0.01, function() if ns.OnAHReady then ns.OnAHReady() end end)
        elseif ns.OnAHReady then
            ns.OnAHReady()
        end
        return -- too frequent to be worth a log line each
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
        Gate.sentCount, Gate.sawSent = Gate.sentCount + 1, true
        Gate.sentAt = GetTime()
        Gate.outstanding, Gate.changedAt = Gate.outstanding + 1, GetTime()
        Watch:Idle()
        Watch:Sent()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
        Gate.respAt = GetTime()
        Gate.outstanding, Gate.changedAt = math.max(0, Gate.outstanding - 1), GetTime()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        Gate.outstanding, Gate.changedAt = math.max(0, Gate.outstanding - 1), GetTime()
        Gate:Penalize("message dropped")
    elseif event == "UI_ERROR_MESSAGE" then
        local _, msg = ...
        if not isAHError(msg) and not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
        if isAHError(msg) and GetTime() >= (Gate.ignoreErrorUntil or 0) then
            Gate:Penalize(tostring(msg))
        elseif isAHError(msg) then
            -- it answers your own purchase, post or cancel: not the server pushing back, so no 5-second stop
            Watch:Add("PURCHASE-ERROR", nil, tostring(msg), true)
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" then
        Watch:Queued()
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and GetTime() < (Gate.ignoreErrorUntil or 0) then
        -- follows our own cancelled purchase: log it, no back-off
        Watch:Add("PURCHASE-ERROR", nil, "error " .. tostring((...)) .. " after a refused purchase", true)
    elseif event == "PLAYER_MONEY" then
        if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
        Log("MONEY now %d", GetMoney())
        return
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        Gate:Penalize("show error " .. tostring((...)))
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and (...) ~= ADDON then
        return
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- ours. If it follows the one-click purchase attempt, that feature is switched off.
        local S = ns.Sniper
        -- One blocked action has one cause, and the input is only blamed when
        -- it really sent a price request or a purchase just now. (While you
        -- roll the wheel an input is always recent: a blocked automatic
        -- purchase or radar read was then also blamed on the wheel, and wheel
        -- buying was switched off with it.)
        if S and S.autoAt and GetTime() - S.autoAt < 0.5 then S.autoAt = nil; S:AutoBlocked()
        elseif S and S.inputAt and GetTime() - S.inputAt < 0.5 and S.inputCallAt and GetTime() - S.inputCallAt < 0.5 then
            -- the wheel, the key or a held key was not accepted as a real
            -- input: stop using that one and fall back to one that works
            local via = S.inputVia
            S.inputAt = nil
            Log("INPUT %s was refused by the game for buying", tostring(via))
            if S.InputRefused then S:InputRefused() end -- nothing left the client: do not wait for a price that was never asked
            if ns.UI and ns.UI.InputBlocked then ns.UI:InputBlocked(via) end
        end
    end
    -- Search result events are frequent: log them briefly.
    Log("EVENT %s(%s) outstanding=%d", event, args(...), Gate.outstanding)
end

function Diag:Init()
    AuctionMeshDB.log = AuctionMeshDB.log or {}
    -- Every /reload or login starts an empty log. The previous session is kept
    -- aside (not shown) and can be opened with /amesh log old.
    AuctionMeshDB.logPrev = AuctionMeshDB.log
    AuctionMeshDB.log = {}
    buf, n = {}, 0
    local _, build, _, toc = GetBuildInfo()
    Log("==== session start: AuctionMesh %s, build %s, interface %s, realm %s, copperValues=%s, step=%s",
        C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
        tostring(build), tostring(toc), tostring(GetRealmName and GetRealmName()),
        tostring(C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues()),
        tostring(ns.Deals and ns.Deals.cfg.step))
    if ns.historyNote then Log(ns.historyNote) end
    for _, name in ipairs(HOOKED) do
        if C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, function(...)
                local ours = (Gate.usedAt == GetTime()) or name:find("^Cancel") or name:find("^Confirm")
                -- Reading lists (the game's Auctions tab does this by itself) only
                -- needs a short pause; buying, selling and cancelling get 8 seconds.
                -- (It was 2 seconds: in a real log the game refreshed its own list
                -- of your auctions and a vendor-price alert waited 3 seconds for it.)
                local pause = (name:find("^Query") or name:find("Browse") or name:find("^Refresh")) and 1 or 8
                if not ours then Gate.userUntil = math.max(Gate.userUntil or 0, GetTime() + pause) end
                local ready = C_AuctionHouse.IsThrottledMessageSystemReady()
                Log("CALL %s(%s) ready=%s%s", name, args(...), tostring(ready),
                    ours and "" or ("  [you / game UI: background paused %ds]"):format(pause))
                Watch:Call(name, (ours and Gate.usedAt == GetTime() and Gate.lastWhat) or name, ours and true or false)
                if not ours then
                    -- listed at most once every 10 seconds (browsing the game's own screens makes many)
                    local now = GetTime()
                    local quiet = now - (Watch.lastGameUI or -100) < 10
                    if not quiet then Watch.lastGameUI = now end
                    Watch:Add("GAME-UI", pause, ("the game's own screen called %s: the addon stays silent for %ds"):format(name, pause), quiet)
                end
            end)
        end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", onEvent)
    if C_Timer and C_Timer.NewTicker and not Watch.ticker then
        Watch.ticker = C_Timer.NewTicker(1, function() Watch:Tick() end)
    end
end

function Diag:Save()
    local out = {}
    for i = math.max(1, n - MAX_LINES + 1), n do out[#out + 1] = buf[i] end
    AuctionMeshDB.log = out
end

function Diag:Text(previous)
    if previous then return table.concat(AuctionMeshDB.logPrev or {}, "\n") end
    local from = math.max(1, n - MAX_LINES + 1)
    return table.concat(buf, "\n", from, n)
end

function Diag:Clear()
    buf, n = {}, 0
    Log("==== log cleared")
end

---------------------------------------------------------------- copy window

local win
local LOG_TITLE = "AuctionMesh log: click in the box, Ctrl+A then Ctrl+C, and paste it to Claude"
function Diag:Show(previous)
    self.showingPrev = previous and true or false
    self:ShowText(previous and "AuctionMesh log of the session BEFORE the last reload or login" or LOG_TITLE, self:Text(previous), true)
end

-- A window with one block of text to copy (the log, or the daily report).
function Diag:ShowText(titleText, text, isLog)
    if not win then
        win = CreateFrame("Frame", "AuctionMeshLogFrame", UIParent, "BackdropTemplate")
        win:SetSize(720, 460)
        win:SetPoint("CENTER")
        win:SetFrameStrata("DIALOG")
        win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        win:SetBackdropColor(0, 0, 0, 0.95)
        win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -10)
        win.title = title
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", "AuctionMeshLogScroll", win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -32)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
        edit:SetWidth(670)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() win:Hide() end)
        scroll:SetScrollChild(edit)
        win.edit = edit
        local sel = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        sel:SetSize(110, 22); sel:SetPoint("BOTTOMLEFT", 10, 10); sel:SetText("Select all")
        sel:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
        local clr = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        clr:SetSize(110, 22); clr:SetPoint("LEFT", sel, "RIGHT", 8, 0); clr:SetText("Clear log")
        clr:SetScript("OnClick", function() Diag:Clear(); edit:SetText(Diag:Text()) end)
        win.clr = clr
        -- the log from before the last reload or login is one click away, here
        -- (it used to be a button of its own on the More tab)
        local prev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        prev:SetSize(150, 22); prev:SetPoint("LEFT", clr, "RIGHT", 8, 0)
        prev:SetScript("OnClick", function() Diag:Show(not Diag.showingPrev) end)
        win.prev = prev
    end
    if not isLog then self.showingPrev = false end
    win.prev:SetShown(isLog == true)
    win.prev:SetText(self.showingPrev and "This session's log" or "Last session's log")
    win.title:SetText(titleText or LOG_TITLE)
    win.clr:SetShown(isLog == true and not self.showingPrev)
    win.edit:SetText(text or "")
    win:Show()
    win.edit:SetFocus()
    win.edit:HighlightText()
end

return Diag
