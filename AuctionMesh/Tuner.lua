-- AuctionMesh Tuner: learns how to spend the auction house request budget.
--
-- The server answers about 1.6 requests a second and no addon can go faster
-- than that. What CAN be optimised is measured and adjusted here, per realm,
-- remembered across sessions and shared with friends on the channel:
--
--   1. THE LIMIT, PER SCENARIO. Seconds from "sent" to "server ready again",
--      separately for each kind of request (category read, next page, item
--      check, more results) and for each hour of the day, so the plan at 8 pm
--      uses what 8 pm really costs.
--   2. THE SAFE PACE. Requests go out the moment the server is ready. If that
--      produces failures (two within 50 requests) a short pause is added
--      after "ready". After 300 clean requests a shorter pause is TRIED for 30
--      requests; it is kept if nothing fails, and tried less often if it does.
--   3. WHERE REQUESTS PAY. Every item check is scored by what asked for it
--      (vendor-price alert, under-market alert, price-drop alert, a friend's
--      hint, the watch list): how many were real deals. Alerts of a kind that
--      keeps being right are checked first.
--   4. THE SPLIT. Requests are divided between the radar (category reads that
--      find new prices) and item checks (which confirm a deal). Once a minute:
--      alerts had to wait -> more checks; nothing waited and the checks were
--      routine -> more radar.
--   5. WASTE. Requests that were never transmitted or never answered are
--      counted, and the time waited for a lost answer follows the measured pace.
--
-- This is measurement and calibration with fixed, bounded rules. Everything it
-- has learned is shown on the Setup tab and by /amesh limits.
--
-- Wire: L <requests measured> <pace step> <radar share %> <ms per kind x4>
local _, ns = ...
ns = ns or {}

local Codec, Comm, Sync = ns.Codec, ns.Comm, ns.Sync
local Tuner = {}
ns.Tuner = Tuner

local floor, min, max = math.floor, math.min, math.max

Tuner.cfg = {
    enabled = true,
    gaps = { 0, 0.10, 0.25, 0.50, 1.00 }, -- pause after "server ready", by step
    measure = 20,       -- requests before the measured limit is trusted
    failWindow = 50,    -- two failures within this many requests: pace is too fast
    trial = 30,         -- clean requests that prove a shorter pause works
    probeAfter = 300,   -- clean requests before a shorter pause is tried
    probeMax = 4800,
    shareMin = 0.15, shareMax = 0.70, shareStep = 0.05,
    balanceEvery = 60,  -- seconds between looks at the split
}
Tuner.KINDS = { "browse", "page", "search", "more" }
Tuner.KIND_NAMES = { browse = "category read", page = "next page", search = "item check", more = "more results" }
Tuner.SOURCES = { "vendor", "market", "drop", "friend", "list", "routine" }
Tuner.SOURCE_NAMES = { vendor = "vendor price", market = "under market", drop = "price drop", friend = "friend's hint",
    list = "price table", routine = "watch list" }

Tuner.now = function() return GetTime() end
Tuner.hour = function()
    local h = GetGameTime and GetGameTime()
    return type(h) == "number" and h or tonumber(date("%H")) or 0
end
local function log(...) if ns.Log then ns.Log(...) end end

function Tuner:Attach(t)
    local c = self.cfg
    t.kinds = t.kinds or {}
    for _, k in ipairs(self.KINDS) do t.kinds[k] = t.kinds[k] or { n = 0, fail = 0 } end
    t.hours = t.hours or {}
    t.gap = t.gap or { i = 1, clean = 0, sinceFail = 1000, probeAfter = c.probeAfter, stats = {} }
    t.gap.trial = nil -- a trial never survives a reload: it restarts from the proven pace
    if t.gap.i > #c.gaps then t.gap.i = #c.gaps end
    t.src = t.src or {}
    for _, s in ipairs(self.SOURCES) do t.src[s] = t.src[s] or { n = 0, hit = 0, profit = 0 } end
    t.share = t.share or 0.30
    t.n, t.unsent, t.timeout = t.n or 0, t.unsent or 0, t.timeout or 0
    self.d = t
    self.win = { at = self.now(), routine = 0, trig = 0, wait = 0 }
    self.recent = {}
    self.pending, self.lastSent, self.lastMove = nil, nil, nil
    self:Apply()
end

-- Pushes what has been learned into the parts that act on it.
function Tuner:Apply()
    local d, Sw = self.d, ns.Swarm
    if not d or not Sw then return end
    Sw.cfg.sweepShare = d.share
    local c = self:Expected()
    if c then Sw.cfg.perRequest = max(0.4, min(3, c + self:Gap())) end
end

---------------------------------------------------------------- the limit and the pace

-- A background request is about to be sent. kind = nil for your own clicks
-- (buying, posting): those are never used for learning.
function Tuner:Sent(kind)
    if not self.d or not kind or not self.d.kinds[kind] then self.pending = nil; return end
    self.pending = { kind = kind, at = self.now() }
    self.lastSent = self.pending
end

-- The server is ready again, dt seconds after the request went out.
function Tuner:Answered(dt)
    local d, p, c = self.d, self.pending, self.cfg
    self.pending = nil
    if not d or not p or not dt or dt < 0.05 or dt > 10 then return end
    local k = d.kinds[p.kind]
    k.n = k.n + 1
    k.cycle = k.cycle and (k.cycle * 0.9 + dt * 0.1) or dt
    d.n = d.n + 1
    d.cycle = d.cycle and (d.cycle * 0.9 + dt * 0.1) or dt
    local hr = self.hour()
    local h = d.hours[hr] or { n = 0 }
    d.hours[hr] = h
    h.n = h.n + 1
    h.cycle = h.cycle and (h.cycle * 0.9 + dt * 0.1) or dt
    local r = self.recent
    r[#r + 1] = self.now()
    if d.n == c.measure then
        log("TUNER limit measured: %.2fs per request (%.1f a second) over the first %d requests", d.cycle, 1 / d.cycle, d.n)
    end

    local g = d.gap
    local st = g.stats[g.i] or { n = 0, fail = 0 }
    g.stats[g.i] = st
    st.n = st.n + 1
    g.clean, g.sinceFail = g.clean + 1, g.sinceFail + 1
    if g.trial then
        g.trial.n = g.trial.n + 1
        if g.trial.n >= c.trial then
            log("TUNER pace: %.2fs pause held for %d requests without a failure; kept (was %.2fs)", c.gaps[g.i], c.trial, c.gaps[g.trial.from])
            g.trial, g.clean, g.probeAfter = nil, 0, c.probeAfter
            self.lastMove = { text = ("Faster pace kept: %.2fs pause"):format(c.gaps[g.i]), at = self.now() }
        end
    elseif c.enabled and g.i > 1 and g.clean >= g.probeAfter then
        g.trial = { from = g.i, n = 0 }
        g.i, g.clean = g.i - 1, 0
        log("TUNER pace: %d clean requests; trying a shorter pause (%.2fs instead of %.2fs) for %d requests",
            g.probeAfter, c.gaps[g.i], c.gaps[g.trial.from], c.trial)
    end
    self:Apply()
end

-- The server refused or dropped something. Counts against the pace only when a
-- background request of ours went out in the last 2 seconds.
function Tuner:Failed(why)
    local d, c = self.d, self.cfg
    local p = self.lastSent
    if not d or not p or self.now() - p.at > 2 then return false end
    self.lastSent = nil -- one failure per request
    local k = d.kinds[p.kind]
    k.fail = k.fail + 1
    local g = d.gap
    local st = g.stats[g.i] or { n = 0, fail = 0 }
    g.stats[g.i] = st
    st.fail = st.fail + 1
    local second = g.sinceFail < c.failWindow
    g.sinceFail = 0
    if g.trial then
        g.i, g.trial, g.clean = g.trial.from, nil, 0
        g.probeAfter = min(c.probeMax, g.probeAfter * 2)
        log("TUNER pace: the shorter pause failed (%s); back to %.2fs, next try after %d clean requests", tostring(why), c.gaps[g.i], g.probeAfter)
        self.lastMove = { text = ("Shorter pause failed: back to %.2fs"):format(c.gaps[g.i]), at = self.now() }
    elseif c.enabled and second and g.i < #c.gaps then
        g.i, g.clean = g.i + 1, 0
        log("TUNER pace: second failure within %d requests (%s); pause after 'ready' is now %.2fs", c.failWindow, tostring(why), c.gaps[g.i])
        self.lastMove = { text = ("Server refused requests: pause now %.2fs"):format(c.gaps[g.i]), at = self.now() }
    end
    self:Apply()
    return true
end

-- Seconds to wait after the server says "ready" before the next request.
function Tuner:Gap()
    local d = self.d
    return d and self.cfg.gaps[d.gap.i] or 0
end

-- Measured seconds per request of one kind (falls back to the overall figure).
function Tuner:Cycle(kind)
    local d = self.d
    if not d then return nil end
    local k = kind and d.kinds[kind]
    if k and k.n >= 5 then return k.cycle end
    return d.cycle
end

-- What a request is expected to cost right now: this hour's figure once this
-- hour has been measured, the overall figure otherwise.
function Tuner:Expected()
    local d = self.d
    if not d then return nil end
    local h = d.hours[self.hour()]
    if h and h.n >= 10 then return h.cycle end
    return d.cycle
end

-- How long to wait for an answer before a request is given up as lost.
function Tuner:Timeout()
    local c = self:Expected()
    return c and max(2, min(4, c * 4)) or 3
end

function Tuner:Wasted(what)
    local d = self.d
    if not d then return end
    if what == "unsent" then d.unsent = d.unsent + 1 else d.timeout = d.timeout + 1 end
    self.pending = nil
end

-- Share of the available request budget used in the last 20 seconds (0..1).
function Tuner:Usage()
    local r, now = self.recent, self.now()
    while r[1] and now - r[1] > 20 do table.remove(r, 1) end
    local c = (self:Expected() or 0.65) + self:Gap()
    return min(1, #r * c / 20)
end

---------------------------------------------------------------- where requests pay

-- One item check came back. src = what asked for it; waited = seconds the
-- alert sat in the queue before it was checked.
function Tuner:Checked(src, deal, profit, waited)
    local d = self.d
    local s = d and src and d.src[src]
    if not s then return end
    s.n = s.n + 1
    if deal then s.hit, s.profit = s.hit + 1, s.profit + (profit or 0) end
    local w = self.win
    if src == "routine" or src == "list" then
        w.routine = w.routine + 1
    else
        w.trig, w.wait = w.trig + 1, w.wait + (waited or 0)
    end
end

-- Chance that a check asked for by this source is a real deal. With no data
-- yet it is 0.5 for every source, so nothing is favoured before it has earned it.
function Tuner:HitRate(src)
    local s = self.d and self.d.src[src]
    if not s then return 0.5 end
    return (s.hit + 1) / (s.n + 2)
end

-- Once a minute: move the split between radar and item checks one step.
function Tuner:Balance(backlog)
    local d, c, w = self.d, self.cfg, self.win
    local now = self.now()
    if not d or not w or now - w.at < c.balanceEvery then return end
    local checks = w.routine + w.trig
    local share, why = d.share, nil
    if c.enabled and checks >= 3 then
        local wait = w.trig > 0 and w.wait / w.trig or 0
        if wait > 4 or (backlog or 0) > 5 then
            share, why = max(c.shareMin, share - c.shareStep), ("alerts waited %.1fs for a check"):format(wait)
        elseif wait < 1.5 and (backlog or 0) == 0 and w.routine / checks > 0.5 then
            share, why = min(c.shareMax, share + c.shareStep), "no alert had to wait"
        end
    end
    self.win = { at = now, routine = 0, trig = 0, wait = 0 }
    if share ~= d.share then
        log("TUNER split: radar %d%% -> %d%% of requests (%s)", floor(d.share * 100 + 0.5), floor(share * 100 + 0.5), why)
        self.lastMove = { text = ("Radar share %d%% > %d%%"):format(floor(d.share * 100 + 0.5), floor(share * 100 + 0.5)), at = now }
        d.share = share
        self:Apply()
        if ns.Swarm and ns.Swarm.Retune then ns.Swarm:Retune() end
    end
end

---------------------------------------------------------------- what the panel shows

-- For the bar at the top of the panel: { mode, text, fill 0..1 }.
--   "try"  something is being measured or tried (orange bar = progress)
--   "ok"   tuned (teal bar = share of the request budget in use)
--   "idle" nothing is being sent
function Tuner:State(paused)
    local d, c = self.d, self.cfg
    if not d then return { mode = "idle", text = "", fill = 0 } end
    if paused then return { mode = "idle", text = paused, fill = 0 } end
    if d.n < c.measure then
        return { mode = "try", fill = d.n / c.measure,
            text = ("Measuring the server's limit: %d of %d requests"):format(d.n, c.measure) }
    end
    local g = d.gap
    if g.trial then
        return { mode = "try", fill = g.trial.n / c.trial,
            text = ("Trying a shorter pause (%.2fs): %d of %d requests"):format(c.gaps[g.i], g.trial.n, c.trial) }
    end
    local m = self.lastMove
    if m and self.now() - m.at < 15 then return { mode = "try", fill = 1, text = m.text } end
    local cycle = (self:Expected() or 0.65) + self:Gap()
    local use = self:Usage()
    return { mode = "ok", fill = use,
        text = ("Tuned: %.1f requests a second, %d%% in use"):format(1 / cycle, floor(use * 100 + 0.5)) }
end

-- Plain "label, value" lines for the Setup tab and /amesh limits.
function Tuner:Lines()
    local d, c = self.d, self.cfg
    local out = {}
    if not d then return out end
    local function add(l, v) out[#out + 1] = { l, v } end
    if d.cycle then
        add("Server limit, measured", ("one request every %.2fs (%.1f a second), from %d requests"):format(d.cycle, 1 / d.cycle, d.n))
    else
        add("Server limit, measured", "not yet: open the auction house with this panel open")
    end
    do
        local parts = {}
        for _, k in ipairs(self.KINDS) do
            local s = d.kinds[k]
            if s.n >= 5 then parts[#parts + 1] = ("%s %.2fs"):format(self.KIND_NAMES[k], s.cycle) end
        end
        add("Cost by kind of request", #parts > 0 and table.concat(parts, ", ") or "not enough requests yet")
    end
    do
        local hr = self.hour()
        local h, slow, slowAt = d.hours[hr], nil, nil
        for at, s in pairs(d.hours) do
            if s.n >= 10 and (not slow or s.cycle > slow) then slow, slowAt = s.cycle, at end
        end
        local now = (h and h.n >= 10) and ("%.2fs at this hour"):format(h.cycle) or "this hour not measured yet"
        add("Cost by time of day", slow and ("%s, slowest %.2fs at %d:00"):format(now, slow, slowAt) or now)
    end
    do
        local g = d.gap
        local st = g.stats[g.i] or { n = 0, fail = 0 }
        local text = g.i == 1 and "none needed" or ("%.2fs"):format(c.gaps[g.i])
        text = text .. (" (%d failure%s in %d requests at this pace)"):format(st.fail, st.fail == 1 and "" or "s", st.n)
        if g.trial then
            text = ("trying %.2fs: %d of %d requests"):format(c.gaps[g.i], g.trial.n, c.trial)
        elseif g.i > 1 then
            text = text .. (", shorter pause tried in %d requests"):format(max(0, g.probeAfter - g.clean))
        end
        add("Pause after the server is ready", text)
    end
    add("Split of requests", ("radar %d%%, item checks %d%% (adjusts itself each minute)"):format(
        floor(d.share * 100 + 0.5), 100 - floor(d.share * 100 + 0.5)))
    do
        local parts = {}
        for _, s in ipairs(self.SOURCES) do
            local x = d.src[s]
            if x.n > 0 then parts[#parts + 1] = ("%s %d of %d"):format(self.SOURCE_NAMES[s], x.hit, x.n) end
        end
        add("Checks that were real deals", #parts > 0 and table.concat(parts, ", ") or "no item checks scored yet")
    end
    add("Wasted requests", ("%d never sent by the client, %d never answered"):format(d.unsent, d.timeout))
    if d.from then add("Starting values", "taken from " .. tostring(d.from) .. " (same realm), then measured here") end
    return out
end

---------------------------------------------------------------- sharing

-- Tells the channel what this client has measured, so a friend who has just
-- installed the addon starts from real figures instead of defaults.
function Tuner:Share()
    local d, c = self.d, self.cfg
    if not d or d.n < c.measure or not Comm then return false end
    local now = self.now()
    if self.sharedAt and now - self.sharedAt < 600 then return false end
    self.sharedAt = now
    local msg = "L" .. Codec.uint(min(d.n, 100000)) .. Codec.uint(d.gap.i) .. Codec.uint(floor(d.share * 100 + 0.5))
    for _, k in ipairs(self.KINDS) do
        local s = d.kinds[k]
        msg = msg .. Codec.uint((s.n >= 5 and s.cycle) and floor(s.cycle * 1000 + 0.5) or 0)
    end
    Comm:Enqueue(Comm.CONTROL, msg)
    return true
end

function Tuner:OnShare(msg, sender)
    local d, c = self.d, self.cfg
    if not d then return end
    local n, gi, share, pos
    n, pos = Codec.readUInt(msg, 2)
    if not n then return end
    gi, pos = Codec.readUInt(msg, pos)
    share, pos = Codec.readUInt(msg, pos)
    if not gi or not share then return end
    local cycles = {}
    for i = 1, #self.KINDS do
        local ms
        ms, pos = Codec.readUInt(msg, pos)
        if not ms then return end
        cycles[i] = ms
    end
    -- Only a client that has not measured for itself yet takes a friend's figures.
    if d.n >= c.measure or n < c.measure then return end
    local sum, cnt = 0, 0
    for i, k in ipairs(self.KINDS) do
        local ms = cycles[i]
        if ms >= 200 and ms <= 5000 and d.kinds[k].n < 5 then
            d.kinds[k].cycle = ms / 1000
            sum, cnt = sum + ms / 1000, cnt + 1
        end
    end
    if cnt > 0 and not d.cycle then d.cycle = sum / cnt end
    if gi >= 1 and gi <= #c.gaps and gi > d.gap.i then d.gap.i = gi end
    if share >= c.shareMin * 100 and share <= c.shareMax * 100 then d.share = share / 100 end
    d.from = sender
    log("TUNER starting values from %s: %s per request, pause step %d, radar %d%%", tostring(sender),
        d.cycle and ("%.2fs"):format(d.cycle) or "?", d.gap.i, floor(d.share * 100 + 0.5))
    self:Apply()
    if ns.UI then ns.UI:Dirty() end
end
if Sync and Sync.OPS then Sync.OPS[76] = function(_, msg, sender) Tuner:OnShare(msg, sender) end end -- 'L'

return Tuner
