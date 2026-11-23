-- AuctionMesh Gold: your gold over time, kept the way a stock chart needs it.
--
-- WHAT IS CHARTED: YOUR CASH = the gold in your hand PLUS what has SOLD and is
-- not in your hand yet (sale gold on its way, or waiting in the mailbox). An
-- auction that has sold is as good as cash; only what is listed and has not
-- sold is tied up. So buying a flip takes the line down by what you paid, its
-- sale brings it up by what the buyer paid, and collecting the gold from the
-- mailbox changes nothing: it only moves from "sold" to "in hand". (The first
-- version charted gold in hand alone. A real session read "- 62%" with over
-- ten gold of sales on their way.)
--
-- Every time that amount changes, three things are updated:
--
--   the hour   one record per hour in which it changed: what it was when the
--              hour began (open), the most and the least it was (high, low)
--              and what it was at the end (close). The last 72 hours.
--   the day    the same per day. The last 120 days.
--   swings     each change, with what caused it when the addon knows: a
--              purchase, a sale collected from the mailbox, a sale to a
--              vendor, a posting fee. Changes of the same direction within
--              10 seconds are one swing (a mailbox being emptied is one swing,
--              not thirty). The 300 largest of the recent ones are kept.
--
-- Kept per character (gold is the character's), in AuctionMeshDB.gold.
-- Nothing here sends a request, and nothing runs on a timer: it is a few
-- additions when the game says the gold changed.
local _, ns = ...
ns = ns or {}

local Gold = {}
ns.Gold = Gold

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

Gold.cfg = {
    hours = 72,   -- hourly records kept
    days = 120,   -- daily records kept
    swings = 300, -- swings kept
    merge = 10,   -- seconds: changes of the same direction this close together are one swing
    causeFor = 3, -- seconds a declared cause applies to the changes around it
    whys = 4,     -- causes named on one swing (the rest are counted)
}

Gold.now = function() return GetServerTime() end
Gold.money = function() return GetMoney() end
-- What has sold and is not in hand yet, in copper; nil while that is not
-- known (the list of your own auctions has not been read this session). Set
-- by Core. Until it is known the last known amount is carried.
Gold.sold = function() return nil end
Gold.atMail = function() return false end -- the mailbox is open (sale gold being collected)
Gold.START_WAIT = 300 -- a new record waits this long, at most, for the sold amount before it begins
Gold.dayId = function(t) return tonumber(date("%Y%m%d", t)) end

function Gold:Attach(db, charKey)
    if not (db and charKey) then return end
    db.gold = db.gold or {}
    local d = db.gold[charKey] or {}
    db.gold[charKey] = d
    if d.kind ~= "cash" then
        -- a record of gold in hand alone (3.52 to 3.56) is not the same thing: it starts again
        d.h, d.d, d.ev = {}, {}, {}
        d.kind, d.sold, d.wait, d.waitAt = "cash", nil, true, self.now()
    end
    d.h, d.d, d.ev = d.h or {}, d.d or {}, d.ev or {}
    self.d = d
    self.lastMoney = self.money()
    self.last = nil
    self:OnMoney()
    if not self.frame and CreateFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_MONEY")
        -- a frame later: everything else that reacts to the gold changing (the
        -- mailbox taking sale gold off "sold") has then done so
        f:SetScript("OnEvent", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, function() Gold:OnMoney() end) else Gold:OnMoney() end
        end)
        self.frame = f
    end
end

-- Your cash now: gold in hand plus what has sold. Returns cash, in hand, sold.
function Gold:Cash()
    local d = self.d
    local m = self.money()
    if not d then return m, m, 0 end
    local live = self.sold()
    if live then d.sold = live end
    return m + (d.sold or 0), m, d.sold or 0
end

-- one record of a list (hours or days) takes a new value
local function bump(list, id, prev, g, keep, t)
    local b = list[#list]
    if not b or b.id ~= id then
        -- a new hour (or day) opens at what the gold was before this change
        b = { id = id, t = t, tc = t, o = prev, h = max(prev, g), l = min(prev, g), c = g }
        list[#list + 1] = b
        while #list > keep do table.remove(list, 1) end
    else
        if g > b.h then b.h = g end
        if g < b.l then b.l = g end
        b.c, b.tc = g, t
    end
end

function Gold:Sample(g, prev, t)
    local d = self.d
    if not d then return end
    bump(d.h, floor(t / 3600), prev, g, self.cfg.hours, t)
    bump(d.d, self.dayId(t), prev, g, self.cfg.days, t)
end

local function addWhy(e, text, limit)
    if not text then return end
    e.why = e.why or {}
    for _, w in ipairs(e.why) do if w == text then return end end
    if #e.why < limit then e.why[#e.why + 1] = text else e.more = (e.more or 0) + 1 end
end

-- The gold in hand changed, or what has sold did (the list of your auctions
-- was read, the mailbox was read). Called from each of those.
function Gold:OnMoney()
    local d = self.d
    if not d then return end
    local m = self.money()
    local live = self.sold()
    if live then
        d.sold = live
    elseif self.lastMoney and m > self.lastMoney and self.atMail() then
        -- sale gold collected while the sold amount is not known afresh: it comes off the carried amount
        d.sold = max(0, (d.sold or 0) - (m - self.lastMoney))
    end
    self.lastMoney = m
    local g = m + (d.sold or 0)
    local t = self.now()
    if d.wait then
        -- a new record begins once the sold amount is known (or after a few minutes without it)
        if not live and t - (d.waitAt or t) < self.START_WAIT then self.last = nil; return end
        d.wait, d.waitAt = nil, nil
        self.last = g
        self:Sample(g, g, t)
        return
    end
    if not self.last then
        -- the first reading of a session: what changed while the addon was not looking is one step
        local b = d.d[#d.d]
        self.last = b and b.c or g
    end
    local prev = self.last
    local delta = g - prev
    if delta == 0 then return end
    self.last = g
    self:Sample(g, prev, t)
    local c = self.cfg
    -- a cause declared just before this change, for this direction
    local p = self.pending
    local why = (p and t - p.t <= c.causeFor and (p.sign > 0) == (delta > 0)) and p.text or nil
    local ev = d.ev
    local e = ev[#ev]
    if e and (e.d > 0) == (delta > 0) and t - e.t2 <= c.merge then
        e.d, e.g, e.t2, e.n = e.d + delta, g, t, (e.n or 1) + 1
    else
        e = { t = t, t2 = t, d = delta, g = g, n = 1 }
        ev[#ev + 1] = e
        if #ev > c.swings then
            -- the smallest of the older half goes: the big ones are what the chart marks
            local at, small = 1, nil
            for i = 1, floor(#ev / 2) do
                if not small or abs(ev[i].d) < small then at, small = i, abs(ev[i].d) end
            end
            table.remove(ev, at)
        end
    end
    addWhy(e, why, c.whys)
    if ns.UI and ns.UI.tab == "GOLD" and ns.UI.Dirty then ns.UI:Dirty() end
end

-- A module says what the gold change around now is. sign: 1 = gold coming
-- in, -1 = gold going out. The game reports the change itself a moment
-- before or after, so the cause is put on a swing that has just been
-- recorded, and kept for the ones about to be.
function Gold:Cause(text, sign)
    local d = self.d
    if not d or not text then return end
    local t = self.now()
    self.pending = { text = text, sign = sign or 1, t = t }
    local e = d.ev[#d.ev]
    if e and t - e.t2 <= self.cfg.causeFor and (e.d > 0) == ((sign or 1) > 0) then addWhy(e, text, self.cfg.whys) end
end

-- THE CHART'S DATA: your gold as a line over the last 2, 7 or 30 days.
--
-- Gold only changes at moments, and stays where it is in between. What is on
-- record gives a list of "at this time it was this much": the amount before
-- and after each swing, and the open and close of every hour and day. The
-- line is that list, read at `cols` evenly spaced times.
--
-- THE CHART BEGINS WHERE THE RECORD BEGINS. Asked for 2 days with half an
-- hour on record, it shows that half hour across its whole width (a real
-- screenshot: two days of empty chart with everything in the last sliver).
-- `short` says so, and from / span are what is really drawn.
--
-- Returns { cols = { { t, v, lo, hi } or { t, none = true } ... }, lo, hi,
--           first, last (the amounts at the two ends), from, to, span, short,
--           days = { { col, t } ... } (where each day begins) }
Gold.MIN_SPAN = 600 -- never less than ten minutes across
Gold.LINES = { d2 = { span = 2 * 86400, name = "2 days" }, d7 = { span = 7 * 86400, name = "7 days" }, d30 = { span = 30 * 86400, name = "30 days" } }
function Gold:Line(view, cols)
    local v = self.LINES[view] or self.LINES.d2
    local d = self.d or { h = {}, d = {}, ev = {} }
    local now = self.now()
    local from = now - v.span
    local pts, n = {}, 0
    local function add(t, g) n = n + 1; pts[n] = { t, g, n } end
    for _, b in ipairs(d.d) do add((b.t or 0) - 1, b.o); add(b.tc or b.t or 0, b.c) end
    for _, b in ipairs(d.h) do add((b.t or 0) - 1, b.o); add(b.tc or b.t or 0, b.c) end
    for _, e in ipairs(d.ev) do add(e.t - 1, e.g - e.d); add(e.t2 or e.t, e.g) end
    if not d.wait then add(now, (self:Cash())) end
    table.sort(pts, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[3] < b[3]
    end)
    -- the record's first moment: the range does not begin before it
    local span, short = v.span, false
    if pts[1] and pts[1][1] > from then
        from = min(pts[1][1], now - self.MIN_SPAN)
        span, short = now - from, true
    end
    local res = { cols = {}, view = view, from = from, to = now, span = span, short = short, days = {} }
    local at, cur = 1, nil
    while pts[at] and pts[at][1] <= from do cur = pts[at][2]; at = at + 1 end -- what it was when the range begins
    -- the amount the range began with: what it was at its start, or the first amount on record after it
    res.first = cur or (pts[at] and pts[at][2]) or nil
    local lastDay
    for i = 1, cols do
        local t = from + span * i / cols
        local lo, hi = cur, cur
        while pts[at] and pts[at][1] <= t do
            cur = pts[at][2]
            lo = lo and min(lo, cur) or cur
            hi = hi and max(hi, cur) or cur
            at = at + 1
        end
        local day = self.dayId(t)
        if day ~= lastDay then
            if lastDay then res.days[#res.days + 1] = { col = i, t = t } end
            lastDay = day
        end
        if cur then
            res.cols[i] = { t = t, v = cur, lo = lo, hi = hi }
            res.lo = res.lo and min(res.lo, lo) or lo
            res.hi = res.hi and max(res.hi, hi) or hi
            res.last = cur
        else
            res.cols[i] = { t = t, none = true }
        end
    end
    return res
end

-- The biggest swings in the same range, largest first, at most n. Each is
-- { t, d, g, why, more, n } with col = the column of the line it sits on.
function Gold:Swings(view, n, cols, from)
    local v = self.LINES[view] or self.LINES.d2
    local d = self.d or { ev = {} }
    local now = self.now()
    from = from or (now - v.span) -- (the chart passes where it really begins)
    local span = max(1, now - from)
    local out = {}
    for _, e in ipairs(d.ev) do
        if e.t >= from and e.t <= now then
            local col = max(1, min(cols or 1, math.ceil(((e.t2 or e.t) - from) / span * (cols or 1))))
            out[#out + 1] = { t = e.t, d = e.d, g = e.g, why = e.why, more = e.more, n = e.n, col = col }
        end
    end
    table.sort(out, function(a, b)
        if abs(a.d) ~= abs(b.d) then return abs(a.d) > abs(b.d) end
        return a.t > b.t
    end)
    while #out > (n or 6) do out[#out] = nil end
    return out
end

-- Round steps for the value axis: 1, 2 or 5 times a power of ten (in copper),
-- so that about `want` lines fit between lo and hi.
function Gold.AxisStep(lo, hi, want)
    local raw = max(1, (hi - lo) / max(1, want or 4))
    local p = 1
    while p * 10 <= raw do p = p * 10 end
    for _, m in ipairs({ 1, 2, 5, 10 }) do
        if p * m >= raw then return p * m end
    end
    return p * 10
end

-- What a swing was, in words.
function Gold.Why(e)
    if not e.why or #e.why == 0 then
        return (e.d > 0) and "gold came in, or something sold: not seen by the addon as it happened" or "gold went out: not through the addon"
    end
    local s = table.concat(e.why, ", ")
    if (e.more or 0) > 0 then s = s .. (", and %d more"):format(e.more) end
    return s
end

-- Change over the last `secs` seconds: now against the close of the last record before then.
function Gold:Change(secs)
    local d = self.d
    if not d then return nil end
    local now = self.now()
    local cut = self.dayId(now - secs)
    local base
    for _, b in ipairs(d.d) do
        if b.id <= cut then base = b.c elseif not base then base = b.o end
    end
    if not base then return nil end
    return (self:Cash()) - base, base
end

-- Today's change: now against what the day opened at.
function Gold:Today()
    local d = self.d
    if not d then return nil end
    local id = self.dayId(self.now())
    local b = d.d[#d.d]
    local cash = (self:Cash())
    if b and b.id == id then return cash - b.o, b.o end
    return 0, cash
end

return Gold
