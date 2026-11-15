-- AuctionMesh Picks: which item, if any, is worth a stake-out.
--
-- A stake-out watches ONE item by asking the server its price with every
-- input, which is faster than the radar, but the radar is off meanwhile. So
-- the question is always: does this one item lose more than everything else
-- earns? That is answered here from the record of deals the radar has already
-- seen (Scout keeps the last 400 with what became of each):
--
--   for each item   deals seen, how many you got, how many you MISSED (you went
--                   for it and someone was faster) and what those were worth,
--                   and how many were GONE before any input
--   missed          the profit of the deals you went for and lost: the most a
--                   faster purchase on this item could add. Deals that left
--                   before any input are shown but not counted: they say you
--                   were not at the snipe box, not that you were too slow.
--   given up        what the radar's catches on all OTHER items made in the
--                   same time: what a stake-out on it gives up
--   worth a try     missed > given up
--
-- NOTHING HERE COSTS A REQUEST. It reads what is already in memory. And it
-- never runs while you are sniping: not while inputs are arriving in the
-- snipe box, not while a deal is on screen, not during a purchase. The
-- figures are worked out again at most every 30 seconds.
local _, ns = ...
ns = ns or {}

local Picks = {}
ns.Picks = Picks

local floor, min, max = math.floor, math.min, math.max

Picks.cfg = {
    window = 24 * 3600, -- deals older than this are not counted
    every = 30,         -- seconds between two calculations
    minDeals = 2,       -- an item needs this many deals in the window to be listed
    minAll = 5,         -- fewer deals than this in all: not enough to say anything
    top = 6,            -- rows shown
    termsMaxAge = 1800, -- "buys at" is shown from a listing read at most this long ago
}

Picks.now = function() return GetServerTime() end

-- True when working something out cannot get in the way of a purchase.
function Picks:Idle()
    local S = ns.Sniper
    if not S then return true end
    if S.buying or (S.SnipeMode and S:SnipeMode()) then return false end
    if S.verified and next(S.verified) ~= nil then return false end
    return true
end

-- The figures, from the record. Pure arithmetic: no requests.
function Picks:Compute()
    local Sc, S, St = ns.Scout, ns.Sniper, ns.Store
    local now = self.now()
    local log = (Sc and Sc.d and Sc.d.deals) or {}
    local c = self.cfg
    local by, order = {}, {}
    local all, gotAll, oldest = 0, 0, nil
    for i = 1, #log do
        local e = log[i]
        local age = now - (e.t or 0)
        -- a deal still on screen (seen less than a minute ago, no outcome yet) is not counted either way
        if age <= c.window and not (e.o == "seen" and age < 60) then
            local it = by[e.k]
            if not it then
                it = { key = e.k, n = 0, got = 0, gotP = 0, miss = 0, missP = 0, gone = 0, goneP = 0, lifeN = 0, lifeS = 0 }
                by[e.k] = it
                order[#order + 1] = it
            end
            local p = e.p or 0
            it.n = it.n + 1
            it.last = max(it.last or 0, e.t or 0)
            all = all + 1
            if not oldest or (e.t or now) < oldest then oldest = e.t end
            if e.o == "bought" then
                -- part of a deal bought counts for that part
                local share = (e.bu and e.u and e.u > 0) and min(1, e.bu / e.u) or 1
                it.got, it.gotP = it.got + 1, it.gotP + floor(p * share + 0.5)
                gotAll = gotAll + floor(p * share + 0.5)
            elseif e.o == "failed" then
                it.miss, it.missP = it.miss + 1, it.missP + p -- you went for it; someone was faster
            else
                it.gone, it.goneP = it.gone + 1, it.goneP + p -- it left before any input
                if e.life then it.lifeN, it.lifeS = it.lifeN + 1, it.lifeS + e.life end
            end
        end
    end
    local list = {}
    for _, it in ipairs(order) do
        if it.n >= c.minDeals and (it.miss > 0 or it.gone > 0) then
            it.givenUp = gotAll - it.gotP          -- what the radar made on everything else
            it.try = it.missP > it.givenUp          -- the most a stake-out could add is more than it gives up
            it.life = it.lifeN > 0 and (it.lifeS / it.lifeN) or nil
            list[#list + 1] = it
        end
    end
    table.sort(list, function(a, b)
        if a.missP ~= b.missP then return a.missP > b.missP end
        if a.n ~= b.n then return a.n > b.n end
        return a.key < b.key
    end)
    while #list > c.top do list[#list] = nil end
    for _, it in ipairs(list) do
        -- what a stake-out on it would buy at, from its listing as last read
        local t = S and S.TermsFor and S:TermsFor(it.key) or {}
        if t.max and t.at and GetTime() - t.at <= c.termsMaxAge then it.max, it.cap = t.max, t.cap else it.why = t.why end
        if St and St.Get then
            local low, _, at = St:Get(it.key)
            if low and at and now - at <= 600 then it.low = low end
        end
        it.record = S and S.StakeRecord and S:StakeRecord(it.key) or nil
    end
    local res = {
        at = GetTime(), list = list, all = all, gotAll = gotAll,
        hours = oldest and max(1, min(floor(c.window / 3600), math.ceil((now - oldest) / 3600))) or 0,
        enough = all >= c.minAll,
    }
    for _, it in ipairs(list) do
        if it.try then res.best = it; break end
    end
    res.top = list[1]
    self.result = res
    return res
end

-- The latest figures. They are worked out again when they are `every` seconds
-- old and nothing is being sniped; otherwise the last ones are returned, with
-- waiting = true if they are overdue.
function Picks:Get()
    local r = self.result
    local due = not r or GetTime() - r.at >= self.cfg.every
    if due and self:Idle() then return self:Compute(), false end
    if not r then return { list = {}, all = 0, gotAll = 0, hours = 0, enough = false, at = GetTime(), pending = true }, true end
    return r, due
end

-- Kept current in the background while the panel is open, so the tab's label
-- can say when there is something to look at.
function Picks:Init()
    if self.ticker or not (C_Timer and C_Timer.NewTicker) then return end
    self.ticker = C_Timer.NewTicker(self.cfg.every, function()
        local U = ns.UI
        if not (U and U.IsShown and U:IsShown()) then return end
        local was = Picks.result and Picks.result.best and Picks.result.best.key
        local r = Picks:Get()
        local is = r.best and r.best.key
        if was ~= is and U.Dirty then U:Dirty() end
    end)
end

return Picks
