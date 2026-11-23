-- AuctionMesh Gold: your gold over time, kept the way a stock chart needs it.
--
-- Every time the gold on this character changes, three things are updated:
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
Gold.dayId = function(t) return tonumber(date("%Y%m%d", t)) end

function Gold:Attach(db, charKey)
    if not (db and charKey) then return end
    db.gold = db.gold or {}
    local d = db.gold[charKey] or {}
    db.gold[charKey] = d
    d.h, d.d, d.ev = d.h or {}, d.d or {}, d.ev or {}
    self.d = d
    self.last = self.money()
    self:Sample(self.last, self.last, self.now())
    if not self.frame and CreateFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_MONEY")
        f:SetScript("OnEvent", function() Gold:OnMoney() end)
        self.frame = f
    end
end

-- one record of a list (hours or days) takes a new value
local function bump(list, id, prev, g, keep, t)
    local b = list[#list]
    if not b or b.id ~= id then
        -- a new hour (or day) opens at what the gold was before this change
        b = { id = id, t = t, o = prev, h = max(prev, g), l = min(prev, g), c = g }
        list[#list + 1] = b
        while #list > keep do table.remove(list, 1) end
    else
        if g > b.h then b.h = g end
        if g < b.l then b.l = g end
        b.c = g
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

-- The game says the gold changed.
function Gold:OnMoney()
    local d = self.d
    if not d then return end
    local g = self.money()
    local prev = self.last or g
    local delta = g - prev
    if delta == 0 then return end
    self.last = g
    local t = self.now()
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

-- THE CHART'S DATA. view = "hours" (the last 24 hours, one candle an hour) or
-- "days" (the last 30 days, one candle a day). Returns
--   { slots = { { id, t, label, o, h, l, c, flat (no change in it), none (before any record) } ... },
--     lo, hi (the range drawn), first, last (gold at the two ends), from, to (times) }
Gold.VIEWS = { hours = { n = 24, step = 3600 }, days = { n = 30, step = 86400 } }
function Gold:Series(view)
    local v = self.VIEWS[view] or self.VIEWS.days
    local d = self.d or { h = {}, d = {}, ev = {} }
    local list = (view == "hours") and d.h or d.d
    local now = self.now()
    local by = {}
    for _, b in ipairs(list) do by[b.id] = b end
    local function idOf(t) if view == "hours" then return floor(t / 3600) end return self.dayId(t) end
    local res = { slots = {}, view = view, from = now - (v.n - 1) * v.step, to = now }
    -- what the gold was before the first slot: the close of the last record before it
    local carry
    local firstId = idOf(res.from)
    for _, b in ipairs(list) do if b.id < firstId then carry = b.c end end
    for i = 1, v.n do
        local t = now - (v.n - i) * v.step
        local id = idOf(t)
        local b = by[id]
        local s = { id = id, t = t }
        if b then
            s.o, s.h, s.l, s.c = b.o, b.h, b.l, b.c
            carry = b.c
        elseif carry then
            s.o, s.h, s.l, s.c, s.flat = carry, carry, carry, carry, true
        else
            s.none = true
        end
        if not s.none then
            res.lo = res.lo and min(res.lo, s.l) or s.l
            res.hi = res.hi and max(res.hi, s.h) or s.h
            res.first = res.first or s.o
            res.last = s.c
        end
        res.slots[i] = s
    end
    return res
end

-- The biggest swings between two times, largest first, at most n. Each is
-- { t, d, g, why = { ... }, more, n } with slot = the index of its candle.
function Gold:Swings(view, n)
    local v = self.VIEWS[view] or self.VIEWS.days
    local d = self.d or { ev = {} }
    local now = self.now()
    local from = now - (v.n - 1) * v.step
    local function idOf(t) if view == "hours" then return floor(t / 3600) end return self.dayId(t) end
    local slotOf = {}
    for i = 1, v.n do slotOf[idOf(now - (v.n - i) * v.step)] = i end
    local out = {}
    for _, e in ipairs(d.ev) do
        local slot = slotOf[idOf(e.t)]
        if slot and e.t >= from - v.step then out[#out + 1] = { t = e.t, d = e.d, g = e.g, why = e.why, more = e.more, n = e.n, slot = slot } end
    end
    table.sort(out, function(a, b)
        if abs(a.d) ~= abs(b.d) then return abs(a.d) > abs(b.d) end
        return a.t > b.t
    end)
    while #out > (n or 6) do out[#out] = nil end
    return out
end

-- What a swing was, in words.
function Gold.Why(e)
    if not e.why or #e.why == 0 then
        return (e.d > 0) and "gold came in: not through the addon" or "gold went out: not through the addon"
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
    return self.money() - base, base
end

-- Today's change: now against what the day opened at.
function Gold:Today()
    local d = self.d
    if not d then return nil end
    local id = self.dayId(self.now())
    local b = d.d[#d.d]
    if b and b.id == id then return self.money() - b.o, b.o end
    return 0, self.money()
end

return Gold
