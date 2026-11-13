-- AuctionMesh Sniper: finds deals and buys them. No window of its own (see UI.lua).
--
--   1. Screen   every few seconds the mesh's price table is screened for items
--               that might be underpriced. These are only "things to check".
--   2. Verify   each one is searched (all live listings, cheapest first) and
--               run through Deals.evaluate. Only what passes becomes a deal,
--               with the exact quantity and exact total cost. Nothing is ever
--               shown as a deal from an estimate.
--   3. Buy      stackables: Buy -> the server quotes the real total -> Confirm.
--               If the quote is higher than the verified total, it is cancelled.
--               Gear: one click buys one listing.
--   4. Record   a purchase is recorded only when the server confirms it or the
--               gold has left your bags.
local _, ns = ...
ns = ns or {}

local Store, Sync, Deals = ns.Store, ns.Sync, ns.Deals
local Sniper = {}
ns.Sniper = Sniper

local floor, min = math.floor, math.min
local VERIFIED_TTL = 45           -- a verified deal is trusted this long, then re-checked
local CHECK_AGAIN = 60            -- don't re-check the same candidate sooner
local SEARCH_TIMEOUT = 6
local PROFESSION = { [0] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [19] = true }

Sniper.verified = {}   -- key -> deal (+ key, at, commodity)
Sniper.checkedAt = {}  -- key -> GetTime() of our last live check
Sniper.vendor = {}     -- key -> vendor sell price (false = cannot be vendored)
Sniper.stats = { checks = 0, deals = 0, bought = 0, spent = 0, expected = 0 }

local function say(m) if ns.Print then ns.Print(m) end end
local function dirty() if ns.UI then ns.UI:Dirty() end end
local function money(c)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(c) end
    return GetCoinTextureString(c)
end

---------------------------------------------------------------- item info

function Sniper.vendorOf(key)
    local v = Sniper.vendor[key]
    if v ~= nil then return v or nil end
    local sell = select(11, C_Item.GetItemInfo(key))
    if sell == nil then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key) end
        return nil
    end
    Sniper.vendor[key] = (sell > 0) and sell or false
    return sell > 0 and sell or nil
end

-- AH deposit per unit for a 12h listing: what we actually paid last time,
-- else the game's own calculation, else 15% of vendor price. math.huge = unknown.
local depCache = {}
function Sniper.depositOf(key, commodity)
    local learned = AuctionMeshDB and AuctionMeshDB.deposits and AuctionMeshDB.deposits[key]
    if learned then return learned end
    if depCache[key] then return depCache[key] end
    local AH = C_AuctionHouse
    if commodity ~= false and AH and AH.CalculateCommodityDeposit then
        local ok, d = pcall(AH.CalculateCommodityDeposit, key, 1, 100)
        if ok and d and d > 0 then
            depCache[key] = math.ceil(d / 100)
            return depCache[key]
        end
    end
    local v = Sniper.vendorOf(key)
    if v == nil and Sniper.vendor[key] == nil then return math.huge end
    return math.ceil((v or 0) * 0.15)
end

local function classOf(key)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(key)
    return classID
end

local function nameOf(key)
    local name, _, quality = C_Item.GetItemInfo(key)
    if not name then return "item:" .. key end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return c and (c.hex .. name .. "|r") or name
end
Sniper.nameOf = nameOf

function Sniper:Budget() return math.max(0, GetMoney()) end

---------------------------------------------------------------- live checks

local SORTS
function Sniper:Search(key)
    SORTS = SORTS or { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    ns.Gate:Use("search " .. tostring(key))
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(key), SORTS, true)
    self.searching = { key = key, at = GetTime() }
    self.checkedAt[key] = GetTime()
    self.stats.checks = self.stats.checks + 1
    ns.lastQuery = "sniper"
end

function Sniper:Evaluate(key, rows, commodity)
    table.sort(rows, function(a, b) return a.price < b.price end)
    if ns.Seller then ns.Seller:OnResults(key, rows, commodity) end
    local avg, n = Store.a[key], Store.an[key]
    local deal, wall = Deals.evaluate(rows, {
        budget = self:Budget(), gold = GetMoney(), commodity = commodity,
        vendor = self.vendorOf(key),
        avg = (avg and n and n >= Deals.cfg.minSamples) and avg or nil,
        deposit = self.depositOf(key, commodity),
    })
    if wall then Sync:ObserveFair(key, wall) end
    if self.buying and self.buying.key == key then
        -- never replace a deal while its purchase is in flight
    elseif deal then
        deal.at, deal.commodity, deal.key = GetTime(), commodity, key
        if not self.verified[key] then
            self.stats.deals = self.stats.deals + 1
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
        end
        self.verified[key] = deal
        ns.Log("DEAL %s %s: buy %d for %d, sell %d each, profit %d (rows: %s)", deal.kind, tostring(key), deal.units,
            deal.cost, deal.sell, deal.profit, self.RowsText(rows))
    else
        self.verified[key] = nil
    end
    if self.searching and self.searching.key == key then self.searching = nil end
    dirty()
end

function Sniper.RowsText(rows)
    local t = {}
    for i = 1, min(#rows, 6) do t[i] = rows[i].qty .. "@" .. rows[i].price end
    return table.concat(t, " ")
end

function Sniper:OnCommodityResults(itemID)
    local AH = C_AuctionHouse
    local rows = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 then
            local q = (r.quantity or 0) - (r.numOwnerItems or 0)
            if q > 0 then rows[#rows + 1] = { price = r.unitPrice, qty = q } end
        end
    end
    self:Evaluate(itemID, rows, true)
end

function Sniper:OnItemResults(itemKey)
    if not itemKey or (itemKey.battlePetSpeciesID or 0) > 0 then return end
    local AH = C_AuctionHouse
    local rows = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
            local q = (r.quantity and r.quantity > 0) and r.quantity or 1
            -- Vendor price of this exact listing (item level variants differ).
            local v = r.itemLink and select(11, C_Item.GetItemInfo(r.itemLink)) or nil
            rows[#rows + 1] = { price = floor(r.buyoutAmount / q), qty = q, whole = true,
                                id = r.auctionID, buyout = r.buyoutAmount, vendor = (v and v > 0) and v or 0 }
        end
    end
    self:Evaluate(itemKey.itemID, rows, false)
end

-- Seconds since we last checked an item live (never = infinity; GetTime() can be small after a reboot).
function Sniper:Since(key)
    local at = self.checkedAt[key]
    return at and (GetTime() - at) or math.huge
end

-- What to check next: expired deals, screened candidates, then affordable
-- profession goods whose market price we haven't looked at recently.
function Sniper:NextCheck()
    if self.priority then local k = self.priority; self.priority = nil; return k end
    local now = GetTime()
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and self:Since(c.key) > CHECK_AGAIN then return c.key end
    end
    local q = self.background
    while q and q.i <= #q do
        local k = q[q.i]
        q.i = q.i + 1
        if self:Since(k) > Deals.cfg.fairMaxAge then return k end
    end
    return nil
end

function Sniper:RebuildBackground()
    if not Deals.cfg.flips then self.background = nil; return end
    local budget, now = self:Budget(), GetServerTime()
    local list = {}
    for key, t in pairs(Store.t) do
        if key > 0 and Store.p[key] <= budget and now - t <= Deals.cfg.maxAge
            and now - (Store.ft[key] or 0) > Deals.cfg.fairMaxAge and PROFESSION[classOf(key) or -1] then
            list[#list + 1] = key
        end
    end
    table.sort(list, function(a, b) return Store.q[a] > Store.q[b] end) -- liquid markets first
    list.i = 1
    self.background = list
end

function Sniper:Pending()
    local n, now = 0, GetTime()
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and self:Since(c.key) > CHECK_AGAIN then n = n + 1 end
    end
    return n
end

function Sniper:HasWork()
    local q = self.background
    return self.priority ~= nil or self:Pending() > 0 or (q ~= nil and q.i <= #q)
end

function Sniper:Busy() return self.searching ~= nil or self.buying ~= nil end

function Sniper:YieldTo() -- called by the scanner before each of its queries
    if self:Busy() then return false end
    if ns.Seller and ns.Seller:Busy() then return false end
    if self.priority then return false end
    if self.active and ns.lastQuery == "swarm" and self:HasWork() then return false end -- take turns
    return true
end

function Sniper:Tick()
    if not self.active then return end
    local now = GetTime()
    if self.searching and now - self.searching.at > SEARCH_TIMEOUT then self.searching = nil end
    if now - (self.lastScreen or 0) > 5 then self:Screen(); self.lastScreen = now end
    if now - (self.lastBg or 0) > 20 then self:RebuildBackground(); self.lastBg = now end
    if self:Busy() or not ns.Gate:Ready() then return end
    if ns.Seller and ns.Seller:Busy() then return end
    local S = ns.Swarm
    if S and S.active and S.current and S.current.phase == "query" then return end
    if not self.priority and S and S.active and not S.idle and ns.lastQuery == "sniper" then return end
    local key = self:NextCheck()
    if key then self:Search(key) end
end

function Sniper:Screen()
    local now = GetTime()
    for k, d in pairs(self.verified) do
        if now - d.at > VERIFIED_TTL and not (self.buying and self.buying.key == k) then
            self.verified[k] = nil
            self.checkedAt[k] = nil -- re-verify soon
            self.priority = self.priority or k
        end
    end
    self.candidates = Deals.candidates(Store, self:Budget(), GetServerTime(), self.vendorOf, nil, 40)
    dirty()
end

---------------------------------------------------------------- buying

-- What one click on Buy will purchase: units, total copper.
function Sniper.NextBuy(deal)
    if deal.commodity then return deal.units, deal.cost end
    local row = deal.buys[1]
    if not row then return 0, 0 end
    return deal.counts[1], row.buyout
end

local function recordFlip(deal, units, spent, proof)
    local db = AuctionMeshDB
    db.flips = db.flips or {}
    local f = db.flips[deal.key]
    local unitCost = units > 0 and spent / units or 0
    if f and f.kind == deal.kind then
        local total = (f.units or 0) + units
        f.cost = floor(((f.cost or unitCost) * (f.units or 0) + spent) / total + 0.5)
        f.units, f.sell, f.at = total, deal.sell, GetServerTime()
        f.proof, f.mailVerified = proof, nil
    else
        db.flips[deal.key] = { kind = deal.kind, sell = deal.sell, units = units,
                               cost = floor(unitCost + 0.5), at = GetServerTime(), proof = proof }
    end
    ns.Log("BOUGHT (confirmed by %s) %dx %s for %d", tostring(proof), units, tostring(deal.key), spent)
    if ns.Seller then
        ns.Seller.LogBuy(deal.key, deal.kind, units, floor(unitCost + 0.5), deal.sell)
        ns.Seller:Refresh(true)
    end
    local s = Sniper.stats
    s.bought, s.spent = s.bought + units, s.spent + spent
    s.expected = s.expected + (deal.units > 0 and floor(deal.profit / deal.units) or 0) * units
    say(("|cff33ff66Purchase confirmed:|r %d x %s for %s. Collect it from the mailbox; the SELL tab shows what to do.")
        :format(units, nameOf(deal.key), money(spent)))
end

function Sniper:Buy(key)
    local deal = self.verified[key]
    if not deal or self.buying then return end
    if GetTime() - deal.at > VERIFIED_TTL then
        self.priority, self.verified[key] = key, nil
        say("That deal is being re-checked; it will reappear if it is still good.")
        return dirty()
    end
    if not ns.Gate:ReadyForUser() then say("The Auction House is busy, click again in a second."); return end
    if deal.commodity then
        self.buying = { key = key, units = deal.units, max = deal.cost, phase = "quote", deal = deal, at = GetTime() }
        ns.Gate:Use(("buy start %dx %s, verified total %d"):format(deal.units, tostring(key), deal.cost))
        C_AuctionHouse.StartCommoditiesPurchase(key, deal.units)
    else
        local row, n = deal.buys[1], deal.counts[1]
        if not row or not row.id then self.verified[key] = nil; return dirty() end
        if row.buyout > GetMoney() then say("Not enough gold for that listing."); return end
        table.remove(deal.buys, 1); table.remove(deal.counts, 1)
        ns.Gate:Use(("buyout auction %s of %s for %d"):format(tostring(row.id), tostring(key), row.buyout))
        self.buying = { key = key, units = n, total = row.buyout, phase = "wait", deal = deal, at = GetTime(),
                        auctionID = row.id, moneyBefore = GetMoney(), item = true, vendor = row.vendor }
        C_AuctionHouse.PlaceBid(row.id, row.buyout)
    end
    dirty()
    self:ArmPurchaseTimeout()
end

-- A purchase that is neither confirmed nor refused within 10s is treated as failed.
function Sniper:ArmPurchaseTimeout(secs)
    local b = self.buying
    if not b then return end
    local at = b.at
    C_Timer.After(secs or 10, function()
        local cur = Sniper.buying
        if not cur or cur.at ~= at then return end
        if cur.phase == "wait" then
            if cur.moneyBefore and GetMoney() <= cur.moneyBefore - cur.total + 1 then
                Sniper:OnPurchase(true, "gold left your bags")
            else
                Sniper:OnPurchase(false, "no confirmation from the server within 10s")
            end
        else -- never got a quote, or you didn't confirm: drop it
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            Sniper.buying = nil
            Sniper.priority = cur.key
            dirty()
        end
    end)
end

function Sniper:Confirm()
    local b = self.buying
    if not b or b.phase ~= "confirm" then return end
    b.phase, b.moneyBefore, b.at = "wait", GetMoney(), GetTime()
    self:ArmPurchaseTimeout()
    ns.Gate:Use(("buy confirm %dx %s total %s"):format(b.units, tostring(b.key), tostring(b.total)))
    C_AuctionHouse.ConfirmCommoditiesPurchase(b.key, b.units)
    dirty()
end

function Sniper:OnPriceQuote(unitPrice, total)
    local b = self.buying
    if not b or b.phase ~= "quote" then return end
    ns.Log("QUOTE %s: %s total vs verified %s", tostring(b.key), tostring(total), tostring(b.max))
    if total <= b.max and total <= GetMoney() then
        b.phase, b.total, b.at = "confirm", total, GetTime()
        self:ArmPurchaseTimeout(25) -- you have 25s to press Confirm
    else
        C_AuctionHouse.CancelCommoditiesPurchase()
        say(("|cffff8040Not bought:|r the price changed (%s now, %s when checked). Re-checking."):format(money(total), money(b.deal.cost)))
        self.verified[b.key] = nil
        self.priority = b.key
        self.buying = nil
    end
    dirty()
end

function Sniper:OnPurchase(ok, why)
    local b = self.buying
    if not b then return end
    if b.phase ~= "wait" and ok then return end -- success only counts after we actually sent the buy
    local spent = b.total or b.deal.cost
    if ok and b.moneyBefore then
        local drop = b.moneyBefore - GetMoney()
        ns.Log("PURCHASE %s: gold before %d, now %d (dropped %d, expected %d) via %s",
            tostring(b.key), b.moneyBefore, GetMoney(), drop, spent, tostring(why))
        if drop > 0 and drop < spent then spent = drop end
    end
    if ok then
        local d = b.deal
        if b.item and b.vendor and b.vendor > 0 then d = setmetatable({ sell = b.vendor }, { __index = b.deal }) end
        recordFlip(d, b.units, spent, why)
        if b.item then
            b.deal.units, b.deal.cost = b.deal.units - b.units, b.deal.cost - (b.total or 0)
            if #b.deal.buys > 0 then self.buying = nil; return dirty() end -- more listings in this deal
        end
    else
        ns.Log("PURCHASE FAILED %s: %s", tostring(b.key), tostring(why))
        say(("|cffff4040Purchase NOT completed:|r %s (%s). Nothing was recorded."):format(nameOf(b.key), why or "refused"))
    end
    self.verified[b.key] = nil
    self.priority = b.key -- re-check: there may be more
    self.buying = nil
    dirty()
end

---------------------------------------------------------------- lifecycle

function Sniper:Start()
    self.active = true
    self.checkedAt = {} -- new AH visit: everything may have changed
    self.lastScreen, self.lastBg = 0, 0
    if not self.ticker then self.ticker = C_Timer.NewTicker(0.25, function() Sniper:Tick() end) end
    dirty()
end

function Sniper:Stop()
    self.active = false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.buying and self.buying.phase ~= "wait" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    self.buying, self.searching = nil, nil
    self.verified = {}
    dirty()
end

-- Tooltip helper for items we flipped.
function Sniper.FlipNote(key)
    local f = AuctionMeshDB and AuctionMeshDB.flips and AuctionMeshDB.flips[key]
    if not f then return nil end
    if f.kind == "VENDOR" then return "|cff33ff99AuctionMesh:|r sell to a vendor (" .. money(f.sell) .. " each)" end
    return "|cffffd100AuctionMesh:|r post at about " .. money(f.sell) .. " each (paid " .. money(f.cost or 0) .. ")"
end

function Sniper:Init(auto)
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
        "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
        "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "PLAYER_MONEY",
        "AUCTION_HOUSE_PURCHASE_COMPLETED", "UI_ERROR_MESSAGE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then Sniper:OnCommodityResults(a1)
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then Sniper:OnItemResults(a1)
        elseif event == "COMMODITY_PRICE_UPDATED" then Sniper:OnPriceQuote(a1, a2)
        elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
            if Sniper.buying then Sniper.buying.phase = "wait" end
            Sniper:OnPurchase(false, "price no longer available")
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then Sniper:OnPurchase(true, "server confirmed")
        elseif event == "COMMODITY_PURCHASE_FAILED" then
            if Sniper.buying then Sniper.buying.phase = "wait" end
            Sniper:OnPurchase(false, "server refused the purchase")
        elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
            local b = Sniper.buying
            if b and b.item and (not a1 or a1 == b.auctionID) then Sniper:OnPurchase(true, "server confirmed") end
        elseif event == "UI_ERROR_MESSAGE" then
            local b = Sniper.buying
            if b and b.phase == "wait" and a2 and tostring(a2):lower():find("auction") then
                Sniper:OnPurchase(false, tostring(a2))
            end
        elseif event == "PLAYER_MONEY" then
            Sniper.lastScreen = 0
            local b = Sniper.buying
            if b and b.item and b.phase == "wait" and GetMoney() <= b.moneyBefore - b.total + 1 then
                Sniper:OnPurchase(true, "gold left your bags")
            end
        elseif event == "AUCTION_HOUSE_SHOW" then if auto() then Sniper:Start() end
        elseif event == "AUCTION_HOUSE_CLOSED" then Sniper:Stop()
        end
    end)
end

return Sniper
