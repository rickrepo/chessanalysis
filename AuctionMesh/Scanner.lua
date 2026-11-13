-- AuctionMesh Scanner: turns auction house activity into price observations.
--
-- Passive (free, no extra server queries): every browse page, commodity
-- search and item search you do anyway is captured and shared.
-- Active: /amesh scan runs a full ReplicateItems scan, which the server allows
-- once per 15 minutes. The mesh announces full scans so a guildmate who
-- scanned 3 minutes ago saves everyone else the scan.
--
-- The replicate list arrives in pieces and can hold 150k+ auctions. We wait
-- until it stops growing, then process it with a per-frame time budget so the
-- client never hitches.
local _, ns = ...
ns = ns or {}

local Sync = ns.Sync
local Scanner = {}
ns.Scanner = Scanner

local min, floor = math.min, math.floor
local SETTLE = 10          -- seconds with no growth before the list counts as complete
local WAIT_TIMEOUT = 900
local FRAME_BUDGET_MS = 6  -- CPU per frame for processing replicate rows

local function say(...) if ns.Print then ns.Print(...) end end

local function keyOf(itemKey)
    local sp = itemKey.battlePetSpeciesID
    if sp and sp > 0 then return -sp end
    return itemKey.itemID
end

-- Per-query minimum so several item-level variants of one item collapse to
-- the cheapest listing instead of overwriting each other.
local browseMin = {}

local function observeMin(map, key, price, qty)
    if not key or not price or price <= 0 then return end
    local cur = map[key]
    if cur then
        cur[2] = cur[2] + (qty or 0)
        if price < cur[1] then cur[1] = price end
    else
        map[key] = { price, qty or 0 }
    end
end

function Scanner:OnBrowse(results, reset)
    if reset then browseMin = {} end
    if not results then return end
    local batch = {}
    for i = 1, #results do
        local r = results[i]
        if r.itemKey then observeMin(batch, keyOf(r.itemKey), r.minPrice, r.totalQuantity) end
    end
    for key, v in pairs(batch) do
        local prev = browseMin[key]
        if prev then
            v[1] = min(v[1], prev[1]); v[2] = v[2] + prev[2]
        end
        browseMin[key] = v
        -- One category query just told us the lowest price and quantity of this
        -- item. The sniper decides from that whether a full look is worth a request.
        if ns.Sniper and ns.Sniper.OnSweep then ns.Sniper:OnSweep(key, v[1], v[2]) end
        Sync:Observe(key, v[1], v[2])
    end
end

function Scanner:OnCommodity(itemID)
    local AH = C_AuctionHouse
    if not itemID or (AH.GetNumCommoditySearchResults(itemID) or 0) == 0 then return end
    local first = AH.GetCommoditySearchResultInfo(itemID, 1)
    if not first or not first.unitPrice then return end
    local qty = AH.GetCommoditySearchResultsQuantity and AH.GetCommoditySearchResultsQuantity(itemID) or first.quantity or 0
    Sync:Observe(itemID, first.unitPrice, qty)
end

function Scanner:OnItemSearch(itemKey)
    local AH = C_AuctionHouse
    if not itemKey then return end
    local n = AH.GetNumItemSearchResults(itemKey) or 0
    local best, qty = nil, 0
    for i = 1, n do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local q = r.quantity or 1
            local unit = r.buyoutAmount -- price of one item (quantity = identical auctions in the row)
            if not best or unit < best then best = unit end
            qty = qty + q
        end
    end
    if best then Sync:Observe(keyOf(itemKey), best, qty) end
end

---------------------------------------------------------------- full scan

local scan -- active scan state

function Scanner:FullScan(force)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        say("Open the Auction House first."); return
    end
    if scan then say("A full scan is already running."); return end
    local ago, by = Sync:FreshestScan()
    if not force and ago and ago < Sync.cfg.fullScanCooldown then
        say(("%s did a full scan %d min ago and the mesh already has it. Use '/amesh scan force' to scan anyway.")
            :format(by or "Someone", floor(ago / 60)))
        return
    end
    if not force and Sync.scanInProgress and GetTime() - Sync.scanInProgress.at < 300 then
        say(("%s is running a full scan right now; results will arrive over the mesh."):format(Sync.scanInProgress.by))
        return
    end
    scan = { phase = "wait", started = GetTime(), lastGrowth = GetTime(), count = 0 }
    Sync:AnnounceScan(1)
    if ns.Gate then ns.Gate:Use("full scan ReplicateItems") end
    C_AuctionHouse.ReplicateItems()
    say("Full scan requested; waiting for the server's auction list...")
    scan.ticker = C_Timer.NewTicker(0.5, function() Scanner:PollReplicate() end)
end

function Scanner:Abort(reason)
    if not scan then return end
    if scan.ticker then scan.ticker:Cancel() end
    if scan.worker then scan.worker:SetScript("OnUpdate", nil) end
    scan = nil
    if reason then say(reason) end
end

function Scanner:PollReplicate()
    if not scan or scan.phase ~= "wait" then return end
    local now = GetTime()
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n > scan.count then scan.count = n; scan.lastGrowth = now end
    if scan.count > 0 and now - scan.lastGrowth >= SETTLE then
        scan.ticker:Cancel()
        self:ProcessReplicate(scan.count)
    elseif now - scan.started > WAIT_TIMEOUT then
        self:Abort("Full scan timed out (the server may be throttling: one full scan per 15 minutes).")
    end
end

function Scanner:ProcessReplicate(n)
    scan.phase = "process"
    local AH = C_AuctionHouse
    local agg, i, last = {}, 0, n -- tolerate 0- or 1-based indexing: scan 0..n
    local clock = debugprofilestop
    local worker = CreateFrame("Frame")
    scan.worker = worker
    worker:SetScript("OnUpdate", function()
        local deadline = clock() + FRAME_BUDGET_MS
        while i <= last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 then
                local key = itemID
                if itemID == 82800 then -- caged battle pet: key by species
                    local link = AH.GetReplicateItemLink(i)
                    local sp = link and tonumber(link:match("battlepet:(%d+)"))
                    if sp then key = -sp end
                end
                local c = (count and count > 0) and count or 1
                observeMin(agg, key, floor(buyout / c), c)
            end
            i = i + 1
            if (i % 256) == 0 and clock() > deadline then return end
        end
        worker:SetScript("OnUpdate", nil)
        local items = 0
        for _ in pairs(agg) do items = items + 1 end
        local fresh = Sync:ObserveBatch(agg)
        Sync:AnnounceScan(2)
        scan = nil
        say(("Full scan done: %d auctions, %d items, %d net-new prices shared with the mesh."):format(n, items, fresh))
    end)
end

---------------------------------------------------------------- events

function Scanner:Init()
    local f = CreateFrame("Frame")
    for _, e in ipairs({
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
        "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
        "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
            Scanner:OnBrowse(C_AuctionHouse.GetBrowseResults(), true)
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            Scanner:OnBrowse(arg1, false)
        elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
            Scanner:OnCommodity(arg1)
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
            Scanner:OnItemSearch(arg1)
        elseif event == "AUCTION_HOUSE_SHOW" then
            browseMin = {}
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if scan and scan.phase == "wait" then Scanner:Abort("Auction House closed; full scan cancelled.") end
        end
    end)
end

return Scanner
