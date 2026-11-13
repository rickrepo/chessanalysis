-- AuctionMesh Sniper: one small window next to the Auction House that lists
-- only deals you can afford right now, best first.
--
--   [icon] Item name        VENDOR  buy 12 @ 3s   -> 5s each   +18s (60%)   [Buy]
--
-- How it finds deals:
--   1. Screen: every lowest price the mesh knows is compared with the item's
--      vendor price and its resale reference (moving average / fair price).
--      Anything that looks underpriced and fits your gold is listed as "Check".
--   2. Verify: the item is searched (all listings, cheapest first) and run
--      through Deals.evaluate to work out exactly how many units to buy, total
--      cost and profit. The row turns into "Buy". Profession goods you can
--      afford are also checked in the background, cheapest-liquid first, and
--      the fair prices found are shared with the mesh so friends don't redo them.
--   3. Buy: commodities are bought in two clicks: Buy (the server quotes the
--      real total), then Confirm. If the quote is more than 2% above the
--      checked cost, the purchase is cancelled. Gear and other non-stackables
--      are bought per listing with one click.
-- Bought items get a tooltip line telling you to vendor them or post them at X.
local _, ns = ...
ns = ns or {}

local Store, Sync, Deals = ns.Store, ns.Sync, ns.Deals
local Sniper = {}
ns.Sniper = Sniper

local floor, min = math.floor, math.min
local ROWS = 12
local VERIFIED_TTL = 90           -- a verified deal is trusted for this long
local CHECK_AGAIN = 60            -- don't re-check the same unverified candidate sooner
local SEARCH_TIMEOUT = 6
local PROFESSION = { [0] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [19] = true }

Sniper.verified = {}   -- key -> deal (+ at, commodity)
Sniper.checkedAt = {}  -- key -> GetTime() of our last depth check
Sniper.vendor = {}     -- key -> vendor sell price (false = cannot be vendored)
Sniper.stats = { checks = 0, deals = 0, bought = 0, spent = 0, expected = 0 }

local function say(m) if ns.Print then ns.Print(m) end end
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

-- AH deposit per unit for a 12h listing. Order of preference:
--   1. what we actually paid last time we posted this item (learned)
--   2. the game's own calculation (commodities, AH open)
--   3. estimate: 15% of the vendor price (corrected by 1 after the first post)
local DEPOSIT_RATE = 0.15
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
    if v == nil and Sniper.vendor[key] == nil then return math.huge end -- item info not loaded yet: don't guess
    return math.ceil((v or 0) * DEPOSIT_RATE)
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

function Sniper:Budget()
    return math.max(0, GetMoney() - (self.reserve or 0))
end

---------------------------------------------------------------- depth checks

local SORTS
function Sniper:Search(key)
    SORTS = SORTS or { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    ns.Gate:Use("search " .. tostring(key) .. (self.priority == key and " (clicked)" or ""))
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(key), SORTS, true)
    self.searching = { key = key, at = GetTime() }
    self.checkedAt[key] = GetTime()
    self.stats.checks = self.stats.checks + 1
    ns.lastQuery = "sniper"
end

local function sortRows(rows) table.sort(rows, function(a, b) return a.price < b.price end) end

function Sniper:Evaluate(key, rows, commodity)
    sortRows(rows)
    if ns.Seller then ns.Seller:OnResults(key, rows, commodity) end
    -- Average only (not fair): the fair price is recomputed from these very rows.
    local avg, n = Store.a[key], Store.an[key]
    local ref = (avg and n and n >= Deals.cfg.minSamples) and avg or nil
    -- Unknown deposit (item info not loaded) = math.huge: rules out AH flips, vendor flips still work.
    local dep = self.depositOf(key, commodity)
    local deal, fair = Deals.evaluate(rows, ref, self.vendorOf(key), self:Budget(), nil, dep)
    if fair then Sync:ObserveFair(key, fair) end
    if deal then
        deal.at, deal.commodity, deal.key = GetTime(), commodity, key
        if not self.verified[key] then
            self.stats.deals = self.stats.deals + 1
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
        end
        self.verified[key] = deal
    else
        self.verified[key] = nil
    end
    if self.searching and self.searching.key == key then self.searching = nil end
    self.dirty = true
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
            rows[#rows + 1] = { price = floor(r.buyoutAmount / q), qty = q, whole = true,
                                id = r.auctionID, buyout = r.buyoutAmount }
        end
    end
    self:Evaluate(itemKey.itemID, rows, false)
end

-- What to check next: the user's click, then screened candidates, then
-- affordable, liquid profession goods whose fair price is stale.
function Sniper:NextCheck()
    if self.priority then local k = self.priority; self.priority = nil; return k end
    local now = GetTime()
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and now - (self.checkedAt[c.key] or 0) > CHECK_AGAIN then return c.key end
    end
    local q = self.background
    while q and q.i <= #q do
        local k = q[q.i]
        q.i = q.i + 1
        if now - (self.checkedAt[k] or 0) > Deals.cfg.fairMaxAge then return k end
    end
    return nil
end

function Sniper:RebuildBackground()
    local budget, now = self:Budget(), GetServerTime()
    local list = {}
    for key, t in pairs(Store.t) do
        if key > 0 and Store.p[key] <= budget and now - t <= Deals.cfg.maxAge
            and now - (Store.ft[key] or 0) > Deals.cfg.fairMaxAge and PROFESSION[classOf(key) or -1] then
            list[#list + 1] = key
        end
    end
    -- Most units listed first: liquid markets resell fastest.
    table.sort(list, function(a, b) return Store.q[a] > Store.q[b] end)
    list.i = 1
    self.background = list
end

-- Shared query budget with the swarm: never interrupt a swarm unit mid-page,
-- and alternate when both want to search.
function Sniper:Wants() return self.priority ~= nil or (self.candidates and #self.candidates > 0) or false end

function Sniper:Busy() return self.searching ~= nil or self.buying ~= nil end

function Sniper:YieldTo(who) -- called by Swarm before each query
    if self:Busy() then return false end
    if ns.Seller and ns.Seller:Busy() then return false end
    if self.priority then return false end
    if self.active and self:Wants() and ns.lastQuery == "swarm" then return false end
    return true
end

function Sniper:Tick()
    if not self.active then return end
    local now = GetTime()
    if self.searching and now - self.searching.at > SEARCH_TIMEOUT then self.searching = nil end
    if now - (self.lastScreen or 0) > 2 then self:Screen(); self.lastScreen = now end
    if now - (self.lastBg or 0) > 15 then self:RebuildBackground(); self.lastBg = now end
    if self.dirty then self:Render() end
    if self:Busy() or not ns.Gate:Ready() then return end
    if ns.Seller and ns.Seller:Busy() then return end -- never search while you're posting
    local S = ns.Swarm
    if S and S.active and S.current and S.current.phase == "query" then return end
    if not self.priority and S and S.active and not S.idle and ns.lastQuery == "sniper" then return end
    local key = self:NextCheck()
    if key then self:Search(key) end
end

function Sniper:Screen()
    local now, t = GetTime(), GetServerTime()
    for k, d in pairs(self.verified) do
        if now - d.at > VERIFIED_TTL then self.verified[k] = nil end
    end
    self.candidates = Deals.candidates(Store, self:Budget(), t, self.vendorOf, nil, 40,
        function(k) return self.depositOf(k) end)
    self.dirty = true
end

---------------------------------------------------------------- buying

local function recordFlip(deal, units, spent, proof)
    local db = AuctionMeshDB
    db.flips = db.flips or {}
    -- Merge with earlier buys of the same item: units add up, cost is the weighted average.
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
    local each = deal.units > 0 and floor(deal.profit / deal.units) or 0
    s.expected = s.expected + each * units
    say(("|cff33ff66Purchase confirmed:|r %d x %s for %s. It goes to your mailbox; the Flip Bag shows what to do.")
        :format(units, nameOf(deal.key), money(spent)))
end

function Sniper:Buy(key)
    local deal = self.verified[key]
    if not deal or self.buying then return end
    if GetTime() - deal.at > VERIFIED_TTL then self.priority = key; self.verified[key] = nil; self.dirty = true; return end
    if deal.commodity then
        self.buying = { key = key, units = deal.units, max = floor(deal.cost * 1.02) + 1, phase = "quote", deal = deal, at = GetTime() }
        if not ns.Gate:Ready() then self.buying = nil; say("The Auction House is busy, click again in a second."); return end
        ns.Gate:Use(("buy start %dx %s, checked cost %d"):format(deal.units, tostring(key), deal.cost))
        C_AuctionHouse.StartCommoditiesPurchase(key, deal.units)
    else
        local row = table.remove(deal.buys, 1)
        local n = table.remove(deal.counts, 1)
        if not row or not row.id then self.verified[key] = nil; self.dirty = true; return end
        if row.buyout > GetMoney() then say("Not enough gold for that listing."); return end
        if not ns.Gate:Ready() then
            table.insert(deal.buys, 1, row); table.insert(deal.counts, 1, n)
            say("The Auction House is busy, click again in a second."); return
        end
        ns.Gate:Use(("buyout auction %s of %s for %d"):format(tostring(row.id), tostring(key), row.buyout))
        -- Not recorded yet: only once the server confirms (event) or the gold leaves your bags.
        self.buying = { key = key, units = n, total = row.buyout, phase = "wait", deal = deal, at = GetTime(),
                        auctionID = row.id, moneyBefore = GetMoney(), item = true }
        C_AuctionHouse.PlaceBid(row.id, row.buyout)
    end
    self.dirty = true
    self:ArmPurchaseTimeout()
end

-- A purchase that is neither confirmed nor refused within 10s is treated as failed.
function Sniper:ArmPurchaseTimeout()
    local b = self.buying
    if not b then return end
    local at = b.at
    C_Timer.After(10, function()
        local cur = Sniper.buying
        if cur and cur.at == at and cur.phase == "wait" then
            -- Last check: did the gold actually leave?
            if cur.moneyBefore and GetMoney() <= cur.moneyBefore - cur.total + 1 then
                Sniper:OnPurchase(true, "gold left your bags")
            else
                Sniper:OnPurchase(false, "no confirmation from the server within 10s")
            end
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
    self.dirty = true
end

function Sniper:OnPriceQuote(unitPrice, total)
    local b = self.buying
    if not b or b.phase ~= "quote" then return end
    ns.Log("QUOTE %s: %s total vs max %s", tostring(b.key), tostring(total), tostring(b.max))
    if total <= b.max and total <= GetMoney() then
        b.phase, b.total = "confirm", total
    else
        C_AuctionHouse.CancelCommoditiesPurchase()
        say(("Price moved (%s quoted vs %s checked); skipped."):format(money(total), money(b.deal.cost)))
        self.verified[b.key] = nil
        self.priority = b.key
        self.buying = nil
    end
    self.dirty = true
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
        if drop > 0 and drop < spent then spent = drop end -- trust what actually left your bags
    end
    if ok then
        recordFlip(b.deal, b.units, spent, why)
        if b.item then
            local d = b.deal
            d.units, d.cost = d.units - b.units, d.cost - (b.total or 0)
            if #d.buys > 0 then self.buying = nil; self.dirty = true; return end -- more listings in this deal
        end
    else
        ns.Log("PURCHASE FAILED %s: %s", tostring(b.key), tostring(why))
        say(("|cffff4040Purchase NOT completed:|r %s (%s). Nothing was added to the Flip Bag."):format(nameOf(b.key), why or "refused"))
    end
    self.verified[b.key] = nil
    self.priority = b.key -- re-check: there may be more cheap units
    self.buying = nil
    self.dirty = true
end

---------------------------------------------------------------- window

local frame, rows = nil, {}

local function rowEntries()
    -- Verified deals first (vendor, then profit), then unverified candidates.
    local out, seen = {}, {}
    local v = {}
    for _, d in pairs(Sniper.verified) do v[#v + 1] = d end
    table.sort(v, function(a, b)
        if a.kind ~= b.kind then return a.kind == "VENDOR" end
        return a.profit > b.profit
    end)
    for _, d in ipairs(v) do out[#out + 1] = { key = d.key, deal = d }; seen[d.key] = true end
    for _, c in ipairs(Sniper.candidates or {}) do
        if not seen[c.key] then out[#out + 1] = { key = c.key, est = c } end
    end
    return out
end

function Sniper:Render()
    self.dirty = false
    if not frame or not frame:IsShown() then return end
    frame.title:SetText(("AuctionMesh Snipes   budget %s   margin %d%%"):format(
        money(self:Budget()), floor(Deals.cfg.margin * 100)))
    local list = rowEntries()
    for i = 1, ROWS do
        local r, e = rows[i], list[i]
        r.entry = e
        if not e then r:Hide() else
            r:Show()
            r.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.key) or 134400)
            r.name:SetText(nameOf(e.key))
            local d = e.deal or e.est
            local tag = d.kind == "VENDOR" and "|cff33ff99VENDOR|r" or "|cffffd100FLIP|r"
            local buyAt = e.deal and e.deal.maxUnit or d.price
            r.info:SetText(("%s %dx @%s > %s  |cff33ff99+%s|r"):format(
                tag, d.units, money(buyAt), money(d.sell), money(d.profit)))
            local b = self.buying
            if b and b.key == e.key then
                r.btn:SetText(b.phase == "confirm" and "Confirm" or "...")
                r.btn:SetEnabled(b.phase == "confirm")
            elseif e.deal then
                r.btn:SetText("Buy"); r.btn:SetEnabled(not self.buying)
            else
                local checking = self.searching and self.searching.key == e.key
                r.btn:SetText(checking and "..." or "Check"); r.btn:SetEnabled(not checking)
            end
        end
    end
    local s = self.stats
    frame.status:SetText(("checked %d  deals %d  bought %d for %s  expected profit %s"):format(
        s.checks, s.deals, s.bought, money(s.spent), money(s.expected)))
end

local function onRowButton(self)
    local e = self:GetParent().entry
    if not e then return end
    local b = Sniper.buying
    if b and b.key == e.key and b.phase == "confirm" then Sniper:Confirm()
    elseif e.deal then Sniper:Buy(e.key)
    else Sniper.priority = e.key; Sniper.dirty = true end
end

function Sniper:CreateWindow()
    if frame then return end
    frame = CreateFrame("Frame", "AuctionMeshSniperFrame", UIParent, "BackdropTemplate")
    frame:SetSize(470, 52 + ROWS * 24)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -10)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() Sniper:Stop() end)
    local bagBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bagBtn:SetSize(72, 18)
    bagBtn:SetPoint("TOPRIGHT", -30, -7)
    bagBtn:SetText("Flip Bag")
    bagBtn:SetScript("OnClick", function() if ns.Seller then ns.Seller:Toggle() end end)
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetSize(450, 22)
        r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 24)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT")
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 24, 0); r.name:SetWidth(130); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", 158, 0); r.info:SetWidth(222); r.info:SetJustifyH("LEFT"); r.info:SetWordWrap(false)
        r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.btn:SetSize(64, 20); r.btn:SetPoint("RIGHT")
        r.btn:SetScript("OnClick", onRowButton)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self.entry.key)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        rows[i] = r
    end
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 8)
    frame:Hide()
end

function Sniper:Start()
    self:CreateWindow()
    frame:ClearAllPoints()
    if AuctionHouseFrame then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    self.active = true
    self.lastScreen, self.lastBg = 0, 0
    if not self.ticker then self.ticker = C_Timer.NewTicker(0.25, function() Sniper:Tick() end) end
    self.dirty = true
end

function Sniper:Stop()
    self.active = false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.buying and self.buying.phase ~= "wait" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    self.buying, self.searching = nil, nil
    if frame then frame:Hide() end
end

-- Tooltip helper for items we flipped.
function Sniper.FlipNote(key)
    local f = AuctionMeshDB and AuctionMeshDB.flips and AuctionMeshDB.flips[key]
    if not f then return nil end
    if f.kind == "VENDOR" then return "|cff33ff99Flip:|r sell to a vendor (" .. money(f.sell) .. " each)" end
    return "|cffffd100Flip:|r post at " .. money(f.sell) .. " each"
end

---------------------------------------------------------------- events

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
        elseif event == "COMMODITY_PURCHASE_FAILED" then Sniper:OnPurchase(false, "server refused the purchase")
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
