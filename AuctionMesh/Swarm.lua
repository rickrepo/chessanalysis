-- AuctionMesh Swarm: the radar. Reads the auction house one category at a time.
--
--   * The auction house is cut into work units, one per item class
--     (crafting materials, consumables, gems, ...).
--   * One category search (SendBrowseQuery) returns the lowest price and total
--     quantity of every item in the category, page after page.
--   * Crafting materials are the main unit, read back to back. The other
--     classes of the chosen scope are side reads, each every `sideEvery` seconds.
--   * Only your own client does this. Nothing is shared with other players.
--
-- unit = classID * 256 + subClassID (255 = whole class).
local _, ns = ...
ns = ns or {}

local Swarm = {}
ns.Swarm = Swarm

local floor, random, max = math.floor, math.random, math.max

Swarm.cfg = {
    fresh = 20,           -- seconds between sweeps of a category; re-tuned from the sweep's measured cost
    sideEvery = 30,       -- each other class of the chosen scope is read this often
    soloEvery = 0,        -- a one-request radar reads again at once: the game's own lock is the pace
    adaptive = true,      -- keep sweeps at about `sweepShare` of the request budget
    sweepShare = 0.30,    -- the rest goes to confirming triggers and routine readings
    perRequest = 0.65,    -- measured seconds per auction house request on this client
    unitTimeout = 6,      -- give up on a read whose answer never comes (an answer takes 0.15s; it was 60s of no radar)
    tick = 0.2,
}

Swarm.units = {}        -- list of unit ids
Swarm.doneAt = {}       -- unit -> server time last completed (by anyone)
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
    local scope = SCOPES[self.scope] or SCOPES.mats
    -- THE MAIN RADAR IS ALWAYS CRAFTING MATERIALS, read back to back (one
    -- request, 0.65s). Every other class in the chosen scope is a SIDE read,
    -- taken once every `sideEvery` seconds. (With the wider scope a real log
    -- showed materials being read only every 6 seconds, with the radar idle
    -- half of the time waiting for a friend's share of the work: deals there
    -- last 1 to 3 seconds.)
    local mainSet = {}
    for _, c in ipairs(SCOPES.mats) do mainSet[c] = true end
    local inScope = {}
    for _, c in ipairs(scope) do inScope[c] = true end
    for _, c in ipairs(scope) do
      if mainSet[c] then
        -- One query for the whole class returns every item in it; asking per
        -- sub-category returns the same items for more requests. (Per
        -- sub-category remains available: Swarm.cfg.bySubclass = true.)
        local subs = self.cfg.bySubclass and AH.GetAuctionItemSubClasses and AH.GetAuctionItemSubClasses(c)
        if subs and #subs > 0 then
            for _, s in ipairs(subs) do list[#list + 1] = self.unitId(c, s) end
        else
            list[#list + 1] = self.unitId(c, nil)
        end
      end
    end
    table.sort(list)
    self.units = list
    -- SIDE READS: the other classes of the chosen scope, each read once every
    -- `sideEvery` seconds. The main radar keeps running back to back.
    self.side, self.sideSet, self.sideOwn = {}, {}, {}
    for _, c in ipairs(scope) do
        if not mainSet[c] then
            local u = self.unitId(c, nil)
            self.side[#self.side + 1] = u
            self.sideSet[u], self.sideOwn[u] = true, true
        end
    end
end

-- Seconds between two reads of one side class: `sideEvery`, or longer when
-- there are so many of them (the whole auction house) that they would take
-- more than a quarter of the requests.
function Swarm:SideGap()
    local req = 0
    for _, u in ipairs(self.side or {}) do
        req = req + ((self.sideReq and self.sideReq[u]) or 1)
    end
    return max(self.cfg.sideEvery, floor(req * self.cfg.perRequest / 0.25 + 0.5))
end

---------------------------------------------------------------- choosing work

local function focused(u)
    return Swarm.focus[u] or Swarm.focus[floor(u / 256) * 256 + 255]
end

-- Returns the unit this peer should scan next, or nil if everything is fresh/claimed.
-- SOLO RADAR. The first real report showed that one request returns the whole
-- materials class (395 items). Sharing out a job that costs one request only
-- adds waiting: with a friend online the radar came round every 8 seconds and
-- more than half the request budget sat idle, while deals lasted 7 to 36
-- seconds. When a full read costs 2 requests or fewer it is read back to back.
function Swarm:Solo()
    if #self.units == 0 then return false end
    local total = 0
    for _, u in ipairs(self.units) do total = total + ((self.unitReq and self.unitReq[u]) or 1) end
    return total <= 2
end

-- Is a side class due for a read (by its own interval)?
function Swarm:SideDue()
    if not self.side or #self.side == 0 then return false end
    local now, gap = self.serverTime(), self:SideGap()
    for _, u in ipairs(self.side) do
        local g = (self.sideItems and self.sideItems[u] and self.sideItems[u] <= 1) and max(gap, 600) or gap
        if now - (self.doneAt[u] or 0) >= g then return true end
    end
    return false
end

function Swarm:PickUnit()
    local now, clock = self.serverTime(), self.clock()
    local best, bestScore
    -- A side class that is due. Side classes come out of the same small budget
    -- as item upkeep (Sniper:UpkeepTurn): never while you are armed, never
    -- before the main radar has had its reads, never two in a row.
    local Sn = ns.Sniper
    if self.side and #self.side > 0 and not (Sn and Sn.SnipeMode and Sn:SnipeMode()) and not (Sn and Sn.UpkeepTurn and not Sn:UpkeepTurn()) then
        local gap = self:SideGap()
        for _, u in ipairs(self.side) do
            -- a class with nothing (or one item) in it is looked at every 10 minutes, not every 30 seconds
            local g = (self.sideItems and self.sideItems[u] and self.sideItems[u] <= 1) and max(gap, 600) or gap
            if now - (self.doneAt[u] or 0) >= g then
                local score = now - (self.doneAt[u] or 0) + random()
                if not bestScore or score > bestScore then best, bestScore = u, score end
            end
        end
        if best then return best end
    end
    local solo = self:Solo()
    self.myDone = self.myDone or {}
    self.myDoneClock = self.myDoneClock or {}
    for _, u in ipairs(self.units) do
        -- SOLO: the radar reads again the moment its last read is in, i.e.
        -- back to back, one read per lock of the auction house (0.65s). It
        -- waited 0.4s of its own on top, counted from a 0.2s timer: about
        -- every second read then missed the instant the lock opened and left
        -- 0.3s late (0.80s between reads on average instead of 0.65s).
        local age = solo and (clock - (self.myDoneClock[u] or -1e9)) or (now - (self.doneAt[u] or 0))
        local due = solo and self.cfg.soloEvery or self.cfg.fresh
        if age >= due then
            -- Focus wins outright; otherwise stalest first; jitter splits ties.
            local score = (focused(u) and 1e12 or 0) + age + random()
            if not bestScore or score > bestScore then best, bestScore = u, score end
        end
    end
    return best
end

---------------------------------------------------------------- running a unit

-- Default executor: browse one class/subclass with the real AH API.
-- Tests replace Swarm.exec with a fake.
Swarm.exec = {
    ready = function() return ns.Gate:Ready() end,
    start = function(u)
        local c, s = Swarm.unitParts(u)
        ns.Gate:Use(("swarm browse class %d sub %s"):format(c, tostring(s)), "browse", (Swarm.sideSet and Swarm.sideSet[u]) and "upkeep" or "radar")
        Swarm.browseSentAt = GetTime()
        C_AuctionHouse.SendBrowseQuery({
            searchString = "",
            sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
            filters = {},
            itemClassFilters = { { classID = c, subClassID = s } },
        })
    end,
    full = function() return C_AuctionHouse.HasFullBrowseResults() end,
    more = function()
        local cur = Swarm.current
        ns.Gate:Use("swarm next page", "page", (cur and Swarm.sideSet and Swarm.sideSet[cur.unit]) and "upkeep" or "radar")
        Swarm.browseSentAt = GetTime()
        C_AuctionHouse.RequestMoreBrowseResults()
    end,
    gotResults = function() return Swarm.resultsSeen end,
}

-- One call does everything that can be done right now: finish the read whose
-- answer is in, pick the next one and send it if the auction house is open.
-- (It used to take one call per stage, from a 0.2s timer, so the next read
-- left up to 0.4s after the lock had opened.)
function Swarm:Step()
    if not self.active then return end
    local ex = self.exec
    for _ = 1, 4 do
        local clock = self.clock()
        local cur = self.current
        if not cur then
            local u = self:PickUnit()
            self.idle = (u == nil)
            if not u then return end
            self.current = { unit = u, phase = "claimed", at = clock }
        elseif cur.phase == "claimed" then
            local side = self.sideSet and self.sideSet[cur.unit]
            local Sn = ns.Sniper
            if side and Sn and ((Sn.SnipeMode and Sn:SnipeMode()) or (Sn.UpkeepTurn and not Sn:UpkeepTurn())) then
                -- armed since it was picked, or the upkeep turn has been used: the main radar goes instead
                self.current = nil
            else
                if not ex.ready() then return end
                if Sn and not Sn:YieldTo("swarm") then return end
                self.resultsSeen = false
                self.sideMark = ns.measure and ns.measure.items or 0 -- items counted so far, to tell how many this read adds
                ex.start(cur.unit)
                cur.requests = 1
                ns.lastQuery = "swarm"
                -- main radar reads since the last request that was not one (the upkeep budget counts these)
                if side then ns.radarSince, ns.upkeepLast = 0, "side" else ns.radarSince = (ns.radarSince or 0) + 1 end
                if not side then
                    local last = self.mainSentAt
                    self.mainSentAt = clock
                    if last and clock - last < 30 then self.mainGap = clock - last end -- seconds between the last two main reads
                end
                self.stats.queries = self.stats.queries + 1
                cur.phase, cur.at = "query", clock
                cur.sentCount = ns.Gate and ns.Gate.sentCount -- to tell later whether the game transmitted it
                return
            end
        elseif cur.phase == "query" then
            -- An answer takes 0.2 to 0.4 seconds. One that has not come in the
            -- time an item check is given (2 to 4 seconds, from the measured
            -- pace) is not coming. (A real log: one radar read in 800 went
            -- unanswered, right after a refused purchase, and 6 seconds passed.)
            local limit = math.min(self.cfg.unitTimeout, math.max(2.5, ns.Tuner and ns.Tuner.Timeout and ns.Tuner:Timeout() or 3))
            if clock - cur.at > limit then
                if ns.Watch then ns.Watch:Add("NO-ANSWER", clock - cur.at, ("a radar read was not answered in %.1fs; given up and sent again"):format(clock - cur.at)) end
                self.current = nil -- give up; it is read again at once
                return
            end
            if not ex.gotResults() then
                -- THE AUCTION HOUSE IS FREE AGAIN AND THERE IS NO ANSWER: the read was
                -- lost. While a request is really on its way the lock is shut, and
                -- it only opens after the answer; so "open, and nothing came" needs
                -- no waiting out. (A real Snapshot: four radar reads lost in four
                -- minutes, each right after a purchase the server refused, each
                -- costing 2.7 to 3 seconds with no radar.)
                if clock - cur.at >= 0.4 and ex.ready() then
                    local G = ns.Gate
                    local sent = G and cur.sentCount and G.sentCount ~= cur.sentCount
                    if ns.Watch then
                        ns.Watch:Add("NO-ANSWER", clock - cur.at, ("a radar read got no answer and the auction house is free again after %.2fs (%s); sent again at once")
                            :format(clock - cur.at, sent and "the game did transmit it" or "the game never transmitted it"))
                    end
                    self.current = nil
                else
                    return
                end
            elseif ex.full() then
                self.doneAt[cur.unit] = self.serverTime()
                self.myDone = self.myDone or {}
                self.myDone[cur.unit] = self.serverTime()
                self.myDoneClock = self.myDoneClock or {}
                self.myDoneClock[cur.unit] = clock
                if ns.Scout then ns.Scout:Sweep() end
                local side = self.sideSet and self.sideSet[cur.unit]
                if side then
                    -- a side class: counted and shared, but it does not set the radar's pace
                    self.sideReq = self.sideReq or {}
                    self.sideReq[cur.unit] = cur.requests or 1
                    do  -- how many items this class holds (three of four were empty in a real log, and were read every 30s all the same)
                        local M = ns.measure
                        local seen = M and M.items or nil
                        if M and self.sideMark then seen = (M.items or 0) - self.sideMark end
                        self.sideItems = self.sideItems or {}
                        if seen then self.sideItems[cur.unit] = seen end
                    end
                    if ns.Log then ns.Log("SIDE read of class %d: %d request(s); each side class is read every %ds", floor(cur.unit / 256), cur.requests or 1, self:SideGap()) end
                    self.stats.units = self.stats.units + 1
                else
                    self.stats.units = self.stats.units + 1
                    self.mainReads = (self.mainReads or 0) + 1
                    self:Tune(cur.unit, cur.requests or 1)
                end
                self.current = nil -- and straight on to the next read
            elseif ex.ready() and not (ns.Sniper and ns.Sniper:Busy()) and not (ns.Seller and ns.Seller:Busy()) then
                self.resultsSeen = false
                ex.more()
                cur.requests = (cur.requests or 1) + 1
                self.stats.pages = self.stats.pages + 1
                cur.at = clock
                return
            else
                return
            end
        end
    end
end

---------------------------------------------------------------- control

function Swarm:Start(quiet)
    if ns.BankAlt and ns.BankAlt() then
        if ns.Print and not quiet then ns.Print("This character is your bank alt: the addon reads no prices here (Setup tab to change).") end
        return
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        if ns.Print and not quiet then ns.Print("Open the Auction House first.") end
        return
    end
    if #self.units == 0 then self:BuildUnits() end
    self.active = true
    ns.radarSince = 0 -- a visit starts with radar reads: upkeep waits its turn
    self.mainSentAt, self.mainGap, self.mainReads = nil, nil, 0
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
    return fresh, #self.units, 1
end

-- BUDGET. A full sweep of everything in scope costs R requests (measured, not
-- assumed: it depends on how many items are listed). At ~0.65s per request the
-- sweep interval that spends `sweepShare` of the budget is R * 0.65 / share.
-- Fewer requests per sweep -> faster radar, automatically.
function Swarm:Tune(unit, requests)
    self.unitReq = self.unitReq or {}
    self.unitReq[unit] = requests
    if not self.cfg.adaptive then return end
    local total = 0
    for _, u in ipairs(self.units) do total = total + (self.unitReq[u] or 1) end
    local fresh = total * self.cfg.perRequest / self.cfg.sweepShare
    fresh = math.max(3, math.min(90, floor(fresh + 0.5)))
    if self:Solo() then fresh = 1 end -- one request reads everything: back to back
    local M = ns.measure
    if M then
        -- what this sweep actually was: items seen, requests used, largest page
        M.last = { items = M.items or 0, requests = total, pageMax = M.pageMax or 0 }
        if ns.Log then
            ns.Log("SWEEP measured: %d item(s) in %d request(s); largest page %d; %.2fs per request; radar every %ds",
                M.last.items, total, M.last.pageMax, self.cfg.perRequest, fresh)
        end
        M.pages, M.items = 0, 0
    end
    if self:Solo() then fresh = 1 end -- shown as "about every second"
    self.cfg.fresh = fresh
end

-- Seconds until the stalest category is due for a rescan (0 = scanning now).
-- The Tuner moved the split or the measured cost: recompute the radar interval.
function Swarm:Retune()
    if not self.cfg.adaptive or not self.unitReq or #self.units == 0 then return end
    local total = 0
    for _, u in ipairs(self.units) do total = total + (self.unitReq[u] or 1) end
    self.cfg.fresh = self:Solo() and 1 or math.max(3, math.min(90, floor(total * self.cfg.perRequest / self.cfg.sweepShare + 0.5)))
end

function Swarm:NextRescan()
    if #self.units == 0 then return nil end
    local now, soonest = self.serverTime(), math.huge
    for _, u in ipairs(self.units) do
        local left = self.cfg.fresh - (now - (self.doneAt[u] or 0))
        if left < soonest then soonest = left end
    end
    return math.max(0, soonest)
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
            -- Only a blocked RADAR READ may switch the radar off: the block must
            -- follow one of our own category requests within half a second.
            -- (Any blocked action used to do it. One blocked Buy click turned
            -- the radar off for the rest of the session, and deals then only
            -- arrived second-hand from friends, after they had seen them.)
            -- ...and not one of the sniper's purchase calls made in that same
            -- half second (a blocked buy input was counted as a blocked radar read).
            local Sn = ns.Sniper
            local buy = Sn and ((Sn.inputCallAt and GetTime() - Sn.inputCallAt < 0.5) or (Sn.autoAt and GetTime() - Sn.autoAt < 0.5))
            if arg1 == "AuctionMesh" and not buy and Swarm.active and Swarm.browseSentAt and GetTime() - Swarm.browseSentAt < 0.5 then
                Swarm.blocked = (Swarm.blocked or 0) + 1
                if ns.Log then ns.Log("RADAR read blocked by the game (%d in a row)", Swarm.blocked) end
                if Swarm.blocked >= 3 then
                    Swarm:Stop("The game blocked automatic scanning three times. Prices will come from item checks instead.")
                    Swarm.manual = true
                end
            end
        else
            Swarm.resultsSeen = true
            Swarm.blocked = 0 -- a radar read came back: reads are allowed
            -- Finish the read on the next frame (the price scanner has read
            -- the answer by then) instead of at the next 0.2s timer tick, so
            -- that the next read is picked and ready before the lock opens.
            if Swarm.active and Swarm.current and Swarm.current.phase == "query" and not Swarm.stepQueued then
                Swarm.stepQueued = true
                C_Timer.After(0, function() Swarm.stepQueued = nil; Swarm:Step() end)
            end
        end
    end)
end

-- Manual mode: one keypress = one step (for clients that require a hardware event).
function Swarm:ManualStep()
    if #self.units == 0 then self:BuildUnits() end
    local was = self.active
    self.active = true
    self:Step()
    self.active = was
end

return Swarm
