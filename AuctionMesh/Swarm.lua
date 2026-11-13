-- AuctionMesh Swarm: distributed auction house scanning between friends.
--
-- Instead of one person waiting on the 15-minute ReplicateItems scan, everyone
-- standing at an auction house with the swarm on shares the work:
--
--   * The AH is cut into work units, one per item class/subclass
--     (Herbs, Ore, Cloth armor, Potions, ...).
--   * Each peer claims the stalest unit nobody has claimed (W 1 <unit>),
--     browses it with SendBrowseQuery (one query returns the lowest price and
--     total quantity of every item in that category, page after page), and
--     marks it done (W 2 <unit>). Prices travel over the normal D messages.
--   * Every player has their own query throttle, so N friends scan about N
--     times faster. Faster peers simply claim more units (dynamic load balance).
--   * Units scanned by anyone within `fresh` seconds are skipped. When the whole
--     AH is fresh, peers idle until the oldest unit goes stale again, which
--     gives a continuous rolling scan.
--   * /amesh focus lets each person own certain categories: focused units are
--     claimed first, so "you do herbs/ore, I do gear" works naturally.
--
-- Wire: W <kind> <unit> <time>   kind 1 = claim, 2 = done
-- unit = classID * 256 + subClassID (255 = whole class); identical on all clients.
local _, ns = ...
ns = ns or {}

local Codec, Comm, Sync = ns.Codec, ns.Comm, ns.Sync
local Swarm = {}
ns.Swarm = Swarm

local floor, random = math.floor, math.random

Swarm.cfg = {
    fresh = 15 * 60,      -- a unit scanned within this window is skipped
    claimTTL = 90,        -- a claim with no "done" expires after this
    unitTimeout = 60,     -- give up on a unit whose results never complete
    tick = 0.2,
    claimWait = 0.4,      -- pause after claiming so a competing claim can arrive
}

Swarm.units = {}        -- list of unit ids
Swarm.doneAt = {}       -- unit -> server time last completed (by anyone)
Swarm.claims = {}       -- unit -> { by = name, at = clock }
Swarm.focus = {}        -- unit or class*256+255 -> true
Swarm.stats = { units = 0, queries = 0, pages = 0 }

-- Platform hooks (tests override these)
Swarm.clock = function() return GetTime() end
Swarm.serverTime = function() return GetServerTime() end

-- What gets scanned. "money" (default) = only stackable goods that players burn
-- through on a new realm: trade goods (cloth, ore, herbs, leather, cooking,
-- enchanting...), reagents, consumables, gems and enhancements. Gear, recipes,
-- pets and the rest can't be deals here, so scanning them is wasted queries.
local SCOPES = {
    mats = { 7 },                 -- crafting materials only: the highest-volume market on a new realm
    money = { 7, 5, 0, 3, 8 },
    all = { 0, 1, 2, 3, 4, 5, 7, 8, 9, 12, 15, 16, 17, 19, 20 }, -- skips WoW Token (18)
}
Swarm.scope = "mats"

-- Set of item classes in the current scope (used by the sniper's watch list).
function Swarm:ScopeClasses()
    local set = {}
    for _, c in ipairs(SCOPES[self.scope] or SCOPES.mats) do set[c] = true end
    return set
end

function Swarm.unitId(classID, subClassID) return classID * 256 + (subClassID or 255) end
function Swarm.unitParts(u)
    local c, s = floor(u / 256), u % 256
    return c, (s ~= 255) and s or nil
end

function Swarm:BuildUnits()
    local list, AH = {}, C_AuctionHouse
    for _, c in ipairs(SCOPES[self.scope] or SCOPES.mats) do
        local subs = AH.GetAuctionItemSubClasses and AH.GetAuctionItemSubClasses(c)
        if subs and #subs > 0 then
            for _, s in ipairs(subs) do list[#list + 1] = self.unitId(c, s) end
        else
            list[#list + 1] = self.unitId(c, nil)
        end
    end
    table.sort(list)
    self.units = list
end

---------------------------------------------------------------- choosing work

local function focused(u)
    return Swarm.focus[u] or Swarm.focus[floor(u / 256) * 256 + 255]
end

-- Returns the unit this peer should scan next, or nil if everything is fresh/claimed.
function Swarm:PickUnit()
    local now, clock = self.serverTime(), self.clock()
    local best, bestScore
    for _, u in ipairs(self.units) do
        local age = now - (self.doneAt[u] or 0)
        local c = self.claims[u]
        local claimed = c and (clock - c.at) < self.cfg.claimTTL and c.by ~= Comm.me
        if age >= self.cfg.fresh and not claimed then
            -- Focus wins outright; otherwise stalest first; jitter splits ties.
            local score = (focused(u) and 1e12 or 0) + age + random()
            if not bestScore or score > bestScore then best, bestScore = u, score end
        end
    end
    return best
end

local function note(kind, u)
    local buf, n = { "W" }, 1
    n = Codec.putUInt(buf, n, kind)
    n = Codec.putUInt(buf, n, u)
    n = Codec.putUInt(buf, n, Swarm.serverTime())
    Comm:Enqueue(Comm.CONTROL, table.concat(buf, "", 1, n))
end

function Swarm:OnNote(msg, sender)
    local kind, pos = Codec.readUInt(msg, 2)
    local u, t
    u, pos = Codec.readUInt(msg, pos)
    t = Codec.readUInt(msg, pos)
    if not kind or not u or not t then return end
    if kind == 1 then
        local mine = self.current and self.current.unit == u
        -- Race: both claimed the same unit. Lower name keeps it.
        if mine and sender < (Comm.me or "") and self.current.phase == "claimed" then
            self.current = nil
        end
        self.claims[u] = { by = sender, at = self.clock() }
    elseif kind == 2 then
        if t > (self.doneAt[u] or 0) then self.doneAt[u] = t end
        self.claims[u] = nil
    end
end
Sync.OPS[87] = function(_, msg, sender) Swarm:OnNote(msg, sender) end -- 'W'

---------------------------------------------------------------- running a unit

-- Default executor: browse one class/subclass with the real AH API.
-- Tests replace Swarm.exec with a fake.
Swarm.exec = {
    ready = function() return ns.Gate:Ready() end,
    start = function(u)
        local c, s = Swarm.unitParts(u)
        ns.Gate:Use(("swarm browse class %d sub %s"):format(c, tostring(s)))
        C_AuctionHouse.SendBrowseQuery({
            searchString = "",
            sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
            filters = {},
            itemClassFilters = { { classID = c, subClassID = s } },
        })
    end,
    full = function() return C_AuctionHouse.HasFullBrowseResults() end,
    more = function() ns.Gate:Use("swarm next page"); C_AuctionHouse.RequestMoreBrowseResults() end,
    gotResults = function() return Swarm.resultsSeen end,
}

function Swarm:Step()
    if not self.active then return end
    local ex, clock = self.exec, self.clock()
    local cur = self.current

    if not cur then
        local u = self:PickUnit()
        self.idle = (u == nil)
        if not u then return end
        self.claims[u] = { by = Comm.me, at = clock }
        note(1, u)
        -- Wait one beat so a competing claim can arrive before we spend a query.
        self.current = { unit = u, phase = "claimed", at = clock }
        return
    end

    if cur.phase == "claimed" then
        if clock - cur.at < self.cfg.claimWait or not ex.ready() then return end
        if ns.Sniper and not ns.Sniper:YieldTo("swarm") then return end
        self.resultsSeen = false
        ex.start(cur.unit)
        ns.lastQuery = "swarm"
        self.stats.queries = self.stats.queries + 1
        cur.phase, cur.at = "query", clock
    elseif cur.phase == "query" then
        if clock - cur.at > self.cfg.unitTimeout then
            self.current = nil -- give up; claim expires and someone retries later
            return
        end
        if not ex.gotResults() then return end
        if ex.full() then
            self.doneAt[cur.unit] = self.serverTime()
            self.claims[cur.unit] = nil
            note(2, cur.unit)
            self.stats.units = self.stats.units + 1
            self.current = nil
        elseif ex.ready() and not (ns.Sniper and ns.Sniper:Busy()) and not (ns.Seller and ns.Seller:Busy()) then
            self.resultsSeen = false
            ex.more()
            self.stats.pages = self.stats.pages + 1
            cur.at = clock
        end
    end
end

---------------------------------------------------------------- control

function Swarm:Start(quiet)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        if ns.Print and not quiet then ns.Print("Open the Auction House first.") end
        return
    end
    if #self.units == 0 then self:BuildUnits() end
    self.active = true
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(self.cfg.tick, function() Swarm:Step() end)
    end
    if ns.Print and not quiet then ns.Print(("Scanning on: %d categories, shared with everyone scanning."):format(#self.units)) end
end

function Swarm:Stop(reason)
    self.active = false
    self.current = nil
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if reason and ns.Print then ns.Print(reason) end
end

-- Summary for /amesh status: fresh units / total, who is working on what.
function Swarm:Coverage()
    local now, fresh = self.serverTime(), 0
    for _, u in ipairs(self.units) do
        if now - (self.doneAt[u] or 0) < self.cfg.fresh then fresh = fresh + 1 end
    end
    local workers, clock = {}, self.clock()
    for _, c in pairs(self.claims) do
        if clock - c.at < self.cfg.claimTTL then workers[c.by] = true end
    end
    local n = 0
    for _ in pairs(workers) do n = n + 1 end
    return fresh, #self.units, n
end

-- "/amesh focus herbs" style shortcuts, plus raw class or class:subclass ids.
local NAMED = {
    consumables = { 0 }, containers = { 1 }, weapons = { 2 }, gems = { 3 }, armor = { 4 },
    reagents = { 5 }, tradegoods = { 7 }, enhancements = { 8 }, recipes = { 9 },
    misc = { 15 }, glyphs = { 16 }, pets = { 17 }, professions = { 19 }, housing = { 20 },
    herbs = { 7, 9 }, ore = { 7, 7 }, metal = { 7, 7 }, cloth = { 7, 5 }, leather = { 7, 6 },
    cooking = { 7, 8 }, elemental = { 7, 10 }, enchanting = { 7, 12 }, inscription = { 7, 16 },
    jewelcrafting = { 7, 4 }, parts = { 7, 1 },
}

function Swarm:SetFocus(text)
    self.focus = {}
    local added = {}
    for word in (text or ""):lower():gmatch("[^%s,]+") do
        local c, s
        local named = NAMED[word]
        if named then c, s = named[1], named[2]
        else
            c, s = word:match("^(%d+):?(%d*)$")
            c, s = tonumber(c), tonumber(s)
        end
        if c then
            self.focus[self.unitId(c, s)] = true
            added[#added + 1] = word
        end
    end
    return added
end

---------------------------------------------------------------- events

function Swarm:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
    f:RegisterEvent("AUCTION_HOUSE_CLOSED")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "AUCTION_HOUSE_CLOSED" then
            if Swarm.active then Swarm:Stop() end
        elseif event == "ADDON_ACTION_BLOCKED" then
            if arg1 == "AuctionMesh" and Swarm.active then
                Swarm:Stop("The game blocked automatic scanning. Prices will come from your own AH searches and from friends instead.")
                Swarm.manual = true
            end
        else
            Swarm.resultsSeen = true
        end
    end)
end

-- Manual mode: one keypress = one step (for clients that require a hardware event).
function Swarm:ManualStep()
    if #self.units == 0 then self:BuildUnits() end
    local was, wait = self.active, self.cfg.claimWait
    self.active, self.cfg.claimWait = true, 0
    self:Step()
    if self.current and self.current.phase == "claimed" then self:Step() end
    self.active, self.cfg.claimWait = was, wait
end

return Swarm
