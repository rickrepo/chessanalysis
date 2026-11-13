-- AuctionMesh Seller + Flip Bag.
--
-- The Flip Bag is a bag-style window showing every item you bought to flip,
-- with a badge saying what to do with it:
--
--   VENDOR (green)  sell to any NPC vendor. Opening a vendor sells these
--                   automatically, or click the item while the vendor is open.
--   AH (gold)       post on the auction house. Open the AH: prices are worked out
--                   in the background (1 step under the cheapest competitor,
--                   never below what you paid + the 5% cut), then click an
--                   item to post it. One click per auction is a game rule
--                   (posting is hardware-event protected). For speed, bind a
--                   key to  /click AuctionMeshPostButton  and tap it.
--   MAIL (blue)     still in your mailbox (AH purchases arrive by mail).
--                   Opening the mailbox collects them automatically.
--   HOLD (red)      the market is currently below your break-even, so we wait
--                   instead of selling at a loss. Re-checked every 10 minutes.
--
-- The text at the top always says the next thing to do. Right-click an item to
-- stop tracking it.
local _, ns = ...
ns = ns or {}

local Deals = ns.Deals
local Seller = {}
ns.Seller = Seller

local floor, min, max = math.floor, math.min, math.max
local DURATION = 1          -- 12h: cheapest deposit
local PRICE_TTL = 90        -- a computed post price is trusted this long
local HOLD_TTL = 600        -- re-check held items after this
local PRICE_TIMEOUT = 6
local LAST_BAG = 5          -- 0-4 bags + reagent bag
local COLS, SLOT, PAD, MAXSLOTS = 6, 40, 4, 30

local COLORS = {
    VENDOR = { 0.2, 1, 0.4, "|cff33ff66" },
    AH = { 1, 0.82, 0, "|cffffd100" },
    MAIL = { 0.3, 0.6, 1, "|cff4d99ff" },
    HOLD = { 1, 0.25, 0.25, "|cffff4040" },
}

Seller.prices = {}  -- key -> { price, qty, commodity, why, at } or { hold = reason, at }

local function say(m) if ns.Print then ns.Print(m) end end
local function money(c)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(c) end
    return GetCoinTextureString(c)
end
local function flips()
    AuctionMeshDB.flips = AuctionMeshDB.flips or {}
    return AuctionMeshDB.flips
end
local function nameOf(key) return C_Item.GetItemInfo(key) or ("item:" .. key) end
local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function mailOpen() return MailFrame and MailFrame:IsShown() end

---------------------------------------------------------------- bags

local bagCount = {} -- key -> total in bags (rebuilt on BAG_UPDATE_DELAYED)

function Seller:ScanBags()
    local counts = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    bagCount = counts
end

function Seller.FindInBags(key)
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == key and not info.isBound and not info.isLocked then
                return bag, slot, info.stackCount or 1
            end
        end
    end
end

function Seller.ForgetUnits(key, n)
    local f = flips()[key]
    if not f then return end
    f.units = (f.units or 0) - n
    if f.units <= 0 then flips()[key] = nil; Seller.prices[key] = nil end
end

---------------------------------------------------------------- what to do with each item

-- Returns a list of { key, action, count, f } entries for the bag window.
function Seller:Entries()
    local out, now = {}, GetTime()
    for key, f in pairs(flips()) do
        local units = f.units or 0
        local inBags = min(bagCount[key] or 0, units)
        local inMail = units - inBags
        if inBags > 0 then
            local action = f.kind == "VENDOR" and "VENDOR" or "AH"
            local p = self.prices[key]
            if action == "AH" and p and p.hold and now - p.at < HOLD_TTL then action = "HOLD" end
            out[#out + 1] = { key = key, action = action, count = inBags, f = f }
        end
        if inMail > 0 then out[#out + 1] = { key = key, action = "MAIL", count = inMail, f = f } end
    end
    local order = { AH = 1, VENDOR = 2, MAIL = 3, HOLD = 4 }
    table.sort(out, function(a, b)
        if a.action ~= b.action then return order[a.action] < order[b.action] end
        return a.key < b.key
    end)
    return out
end

function Seller:Instructions(entries)
    local n = { AH = 0, VENDOR = 0, MAIL = 0, HOLD = 0 }
    for _, e in ipairs(entries) do n[e.action] = n[e.action] + 1 end
    local lines = {}
    local function add(action, text) lines[#lines + 1] = COLORS[action][4] .. text .. "|r" end
    if n.MAIL > 0 then
        add("MAIL", mailOpen() and ("Collecting " .. n.MAIL .. " item(s) from the mailbox...")
            or ("Go to a mailbox: " .. n.MAIL .. " purchase(s) are waiting there."))
    end
    if n.AH > 0 then
        if ahOpen() then
            local ready = 0
            for _, e in ipairs(entries) do
                local p = e.action == "AH" and self.prices[e.key]
                if p and p.price and GetTime() - p.at < PRICE_TTL then ready = ready + 1 end
            end
            add("AH", ("Click an AH item to post it (%d of %d priced and ready)."):format(ready, n.AH))
        else
            add("AH", "Open the Auction House to post " .. n.AH .. " item(s).")
        end
    end
    if n.VENDOR > 0 then
        add("VENDOR", merchantOpen() and "Selling vendor items..."
            or ("Talk to any vendor: " .. n.VENDOR .. " item(s) sell automatically."))
    end
    if n.HOLD > 0 then add("HOLD", n.HOLD .. " item(s) on hold: market is below what you paid. Will re-check.") end
    if #lines == 0 then lines[1] = "|cffaaaaaaNothing to do. Go snipe some deals!|r" end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------- vendor (automatic at merchants)

function Seller:SellVendor(onlyKey)
    local queue = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local f = info and flips()[info.itemID]
            if f and f.kind == "VENDOR" and (not onlyKey or onlyKey == info.itemID)
                and not info.isLocked and not info.hasNoValue then
                queue[#queue + 1] = { bag = bag, slot = slot, key = info.itemID, n = info.stackCount or 1 }
            end
        end
    end
    if #queue == 0 then return end
    local earned, i = 0, 0
    local function nextSale()
        if not merchantOpen() then return end
        i = i + 1
        local q = queue[i]
        if not q then
            if earned > 0 then say("Sold vendor flips for " .. money(earned) .. ".") end
            return
        end
        local f = flips()[q.key]
        if f then
            local n = min(q.n, f.units or q.n)
            C_Container.UseContainerItem(q.bag, q.slot)
            earned = earned + (f.sell or 0) * n
            Seller.ForgetUnits(q.key, n)
        end
        C_Timer.After(0.15, nextSale)
    end
    nextSale()
end

---------------------------------------------------------------- mailbox (automatic)

function Seller:CollectMail()
    if self.mailBusy then return end
    self.mailBusy = true
    local function step()
        if not mailOpen() then Seller.mailBusy = false; return end
        for i = GetInboxNumItems(), 1, -1 do
            local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
            local _, _, _, _, moneyAmt, cod, _, hasItem = GetInboxHeaderInfo(i)
            if (cod or 0) == 0 then
                if invoice == "buyer" and hasItem then
                    AutoLootMailItem(i); C_Timer.After(0.4, step); return
                elseif invoice == "seller" and (moneyAmt or 0) > 0 then
                    TakeInboxMoney(i); C_Timer.After(0.4, step); return
                end
            end
        end
        Seller.mailBusy = false
    end
    step()
end

---------------------------------------------------------------- AH pricing (background) and posting (click)

function Seller:NextToPrice()
    local now = GetTime()
    if self.priority then local k = self.priority; self.priority = nil; return k end
    for key, f in pairs(flips()) do
        if f.kind == "FLIP" and (bagCount[key] or 0) > 0 then
            local p = self.prices[key]
            local ttl = (p and p.hold) and HOLD_TTL or PRICE_TTL
            if not p or now - p.at >= ttl then return key end
        end
    end
end

function Seller:Tick()
    if not ahOpen() then return end
    local S = ns.Sniper
    local now = GetTime()
    if self.pending and now - self.pending.at > PRICE_TIMEOUT then
        if S.searching and S.searching.key == self.pending.key then S.searching = nil end
        self.pending = nil
    end
    if self.pending or S.searching or S.buying or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local Sw = ns.Swarm
    if Sw and Sw.active and Sw.current and Sw.current.phase == "query" then return end
    local key = self:NextToPrice()
    if not key then return end
    self.pending = { key = key, at = now }
    S:Search(key)
    self:Refresh()
end

-- Called by the sniper for every item search result (ours or anyone's).
function Seller:OnResults(key, rows, commodity)
    local f = flips()[key]
    if not f or f.kind ~= "FLIP" then return end
    if self.pending and self.pending.key == key then self.pending = nil end
    local price, why = Deals.postPrice(rows, f.cost or 0, f.sell or 0)
    if price then
        local qty = commodity and min(bagCount[key] or 0, f.units or 0) or 1
        self.prices[key] = { price = price, qty = max(qty, 1), commodity = commodity, why = why, at = GetTime() }
    else
        self.prices[key] = { hold = why, at = GetTime() }
    end
    self:Refresh()
end

-- Must run from a click or keypress (posting is hardware-event protected).
function Seller:Post(key)
    local p = self.prices[key]
    if not p or not p.price or GetTime() - p.at >= PRICE_TTL then
        self.priority = key
        say(nameOf(key) .. ": checking current price, click again in a moment.")
        return
    end
    local bag, slot = self.FindInBags(key)
    if not bag then self:Refresh(); return end
    local AH = C_AuctionHouse
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local qty = p.commodity and min(p.qty, bagCount[key] or p.qty) or 1
    local deposit = (p.commodity and AH.CalculateCommodityDeposit(key, DURATION, qty)
        or AH.CalculateItemDeposit(loc, DURATION, qty)) or 0
    if deposit > GetMoney() then say("Not enough gold for the deposit (" .. money(deposit) .. ")."); return end
    if p.commodity then
        if AH.PostCommodity(loc, DURATION, qty, p.price) and AH.ConfirmPostCommodity then
            AH.ConfirmPostCommodity(loc, DURATION, qty, p.price)
        end
    else
        if AH.PostItem(loc, DURATION, 1, nil, p.price) and AH.ConfirmPostItem then
            AH.ConfirmPostItem(loc, DURATION, 1, nil, p.price)
        end
    end
    say(("Posted %dx %s at %s each (%s)."):format(qty, nameOf(key), money(p.price), p.why))
    self.ForgetUnits(key, qty)
    self.prices[key] = nil
    self:Refresh()
end

-- Post-next for the keybind: first AH item with a ready price.
function Seller:PostNext()
    for _, e in ipairs(self:Entries()) do
        local p = e.action == "AH" and self.prices[e.key]
        if p and p.price and GetTime() - p.at < PRICE_TTL then return self:Post(e.key) end
    end
    for _, e in ipairs(self:Entries()) do
        if e.action == "AH" then self.priority = e.key; say("Pricing items, press again in a moment."); return end
    end
    say("Nothing ready to post.")
end

---------------------------------------------------------------- Flip Bag window

local frame, slots = nil, {}

local function slotTooltip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(e.key)
    local c = COLORS[e.action]
    local p = Seller.prices[e.key]
    if e.action == "VENDOR" then
        GameTooltip:AddLine(c[4] .. "Sell to any vendor: " .. money(e.f.sell or 0) .. " each|r")
    elseif e.action == "AH" then
        if p and p.price then
            GameTooltip:AddLine(c[4] .. ("Post %dx at %s each (%s)|r"):format(p.commodity and p.qty or 1, money(p.price), p.why))
        else
            GameTooltip:AddLine(c[4] .. (ahOpen() and "Checking price..." or "Open the Auction House to post") .. "|r")
        end
    elseif e.action == "MAIL" then
        GameTooltip:AddLine(c[4] .. "In your mailbox: open it to collect|r")
    else
        GameTooltip:AddLine(c[4] .. "On hold: " .. (p and p.hold or "") .. "|r")
    end
    GameTooltip:AddLine(("|cffaaaaaaPaid %s each. Right-click: stop tracking.|r"):format(money(e.f.cost or 0)))
    GameTooltip:Show()
end

local function slotClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
        flips()[e.key] = nil; Seller.prices[e.key] = nil
        say("Stopped tracking " .. nameOf(e.key) .. ".")
        return Seller:Refresh()
    end
    if e.action == "AH" then
        if ahOpen() then Seller:Post(e.key) else say("Open the Auction House first.") end
    elseif e.action == "VENDOR" then
        if merchantOpen() then Seller:SellVendor(e.key) else say("Talk to any vendor; it sells automatically.") end
    elseif e.action == "MAIL" then
        if mailOpen() then Seller:CollectMail() else say("Go to a mailbox to collect it.") end
    else
        Seller.prices[e.key] = nil; Seller.priority = e.key
        say("Re-checking the price of " .. nameOf(e.key) .. ".")
    end
end

function Seller:CreateWindow()
    if frame then return end
    frame = CreateFrame("Frame", "AuctionMeshFlipBag", UIParent, "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 140)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -9)
    frame.title:SetText("Flip Bag")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.help:SetPoint("TOPLEFT", 10, -28)
    frame.help:SetJustifyH("LEFT")
    frame.help:SetWidth(COLS * (SLOT + PAD) + 4)
    frame.help:SetSpacing(2)

    for i = 1, MAXSLOTS do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(SLOT, SLOT)
        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.badge:SetPoint("TOP", 0, -1)
        b.badge:SetFont(b.badge:GetFont(), 9, "OUTLINE")
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", slotClick)
        b:SetScript("OnEnter", slotTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        slots[i] = b
    end

    local post = CreateFrame("Button", "AuctionMeshPostButton", frame, "UIPanelButtonTemplate")
    post:SetSize(110, 22)
    post:SetText("Post next")
    post:SetScript("OnClick", function() Seller:PostNext() end)
    frame.post = post
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetJustifyH("LEFT")
    frame:Hide()
end

function Seller:Render()
    if not frame or not frame:IsShown() then return end
    local entries = self:Entries()
    frame.help:SetText(self:Instructions(entries))
    local top = 32 + frame.help:GetStringHeight()
    local shown = min(#entries, MAXSLOTS)
    for i = 1, MAXSLOTS do
        local b, e = slots[i], entries[i]
        b.entry = e
        if i > shown then b:Hide() else
            local c = COLORS[e.action]
            local col, row = (i - 1) % COLS, floor((i - 1) / COLS)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + col * (SLOT + PAD), -top - row * (SLOT + PAD))
            b.border:SetColorTexture(c[1], c[2], c[3], 1)
            b.icon:SetTexture(C_Item.GetItemIconByID(e.key) or 134400)
            local p = self.prices[e.key]
            local busy = e.action == "AH" and self.pending and self.pending.key == e.key
            b.badge:SetText(c[4] .. (busy and "..." or e.action) .. "|r")
            b.count:SetText(e.count > 1 and e.count or "")
            -- Dim AH items whose price isn't ready yet.
            local ready = e.action ~= "AH" or (p and p.price and GetTime() - p.at < PRICE_TTL)
            b.icon:SetDesaturated(e.action == "MAIL" or e.action == "HOLD" or (ahOpen() and not ready))
            b:Show()
        end
    end
    local rows = math.max(1, math.ceil(shown / COLS))
    local h = top + rows * (SLOT + PAD) + 34
    frame:SetSize(COLS * (SLOT + PAD) + 16, h)
    frame.post:ClearAllPoints()
    frame.post:SetPoint("BOTTOMRIGHT", -8, 7)
    frame.post:SetShown(ahOpen())
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("BOTTOMLEFT", 10, 12)
    local extra = #entries > MAXSLOTS and ("+" .. (#entries - MAXSLOTS) .. " more  ") or ""
    frame.footer:SetText(extra .. (ahOpen() and "" or "/amesh bag to toggle"))
end

function Seller:Toggle()
    self:CreateWindow()
    if frame:IsShown() then frame:Hide() else self:ScanBags(); frame:Show(); self:Render() end
end

-- Re-render; with show=true also open the window if there is something to do.
function Seller:Refresh(show)
    if show and #self:Entries() > 0 then
        self:CreateWindow()
        if not frame:IsShown() then self:ScanBags(); frame:Show() end
    end
    self:Render()
end

---------------------------------------------------------------- events

function Seller:Init()
    self:ScanBags()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED",
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            Seller:Refresh(true)
            C_Timer.After(0.3, function() Seller:SellVendor() end)
        elseif event == "MAIL_SHOW" then
            Seller:Refresh(true); Seller:CollectMail()
        elseif event == "MAIL_INBOX_UPDATE" then
            Seller:CollectMail()
        elseif event == "AUCTION_HOUSE_SHOW" then
            for k, p in pairs(Seller.prices) do if p.price then Seller.prices[k] = nil end end
            Seller:Refresh(true)
            if not Seller.ticker then Seller.ticker = C_Timer.NewTicker(0.3, function() Seller:Tick() end) end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if Seller.ticker then Seller.ticker:Cancel(); Seller.ticker = nil end
            Seller.pending = nil
            Seller:Refresh()
        elseif event == "BAG_UPDATE_DELAYED" then
            Seller:ScanBags(); Seller:Refresh()
        else
            Seller:Refresh()
        end
    end)
    -- Remind on login if there is unfinished business.
    C_Timer.After(8, function()
        local n = #Seller:Entries()
        if n > 0 then say(n .. " flip(s) waiting. Type /amesh bag to see what to do.") end
    end)
end

return Seller
