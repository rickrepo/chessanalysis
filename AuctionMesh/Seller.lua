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
    if #lines == 0 then
        lines[1] = "|cffaaaaaaNothing to do. Drag an item from your bags onto this window to track it,\nor type /amesh bag restore to rebuild from your purchase log.|r"
    end
    if self.posting then table.insert(lines, 1, "|cffffffffPosting " .. nameOf(self.posting.key) .. "...|r") end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------- vendor (automatic at merchants)

function Seller:SellVendor(onlyKey)
    if self.selling then return end
    local queue, remaining, before = {}, {}, {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local f = info and flips()[info.itemID]
            if f and f.kind == "VENDOR" and (not onlyKey or onlyKey == info.itemID)
                and not info.isLocked and not info.hasNoValue then
                local key, n = info.itemID, info.stackCount or 1
                remaining[key] = remaining[key] or (f.units or 0)
                -- Never sell copies you owned before the flip: only stacks that fit
                -- inside the number of units we actually bought.
                if n <= remaining[key] then
                    remaining[key] = remaining[key] - n
                    before[key] = bagCount[key] or 0
                    queue[#queue + 1] = { bag = bag, slot = slot, key = key }
                end
            end
        end
    end
    if #queue == 0 then return end
    self.selling = true
    local i = 0
    local function finish()
        -- Count what actually left the bags; only that is removed from the Flip Bag.
        Seller:ScanBags()
        local earned = 0
        for key, was in pairs(before) do
            local gone = was - (bagCount[key] or 0)
            if gone > 0 then
                local f = flips()[key]
                earned = earned + ((f and f.sell) or 0) * gone
                Seller.ForgetUnits(key, gone)
            end
        end
        Seller.selling = false
        if earned > 0 then say("Sold vendor flips for " .. money(earned) .. ".") end
        Seller:Refresh()
    end
    local function nextSale()
        i = i + 1
        local q = queue[i]
        if not q or not merchantOpen() then return C_Timer.After(0.6, finish) end
        C_Container.UseContainerItem(q.bag, q.slot)
        C_Timer.After(0.2, nextSale)
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
    if self:Busy() or self.pending or S.searching or S.buying or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local Sw = ns.Swarm
    if Sw and Sw.active and Sw.current and Sw.current.phase == "query" then return end
    local key = self:NextToPrice()
    if not key then return end
    self.pending = { key = key, at = now }
    S:Search(key)
    self:Refresh()
end

-- Real deposit per unit for posting `qty` of this item now (12h).
function Seller:DepositEach(key, commodity, qty)
    local AH, d = C_AuctionHouse, nil
    if commodity then
        d = AH.CalculateCommodityDeposit(key, DURATION, qty)
    else
        local bag, slot = self.FindInBags(key)
        if bag then d = AH.CalculateItemDeposit(ItemLocation:CreateFromBagAndSlot(bag, slot), DURATION, 1) end
    end
    if d and d >= 0 then
        local each = math.ceil(d / qty)
        AuctionMeshDB.deposits = AuctionMeshDB.deposits or {}
        AuctionMeshDB.deposits[key] = each -- the sniper uses this for future buys
        return each
    end
    return ns.Sniper.depositOf(key, commodity)
end

-- Called by the sniper for every item search result (ours or anyone's).
function Seller:OnResults(key, rows, commodity)
    local f = flips()[key]
    if not f or f.kind ~= "FLIP" then return end
    if self.pending and self.pending.key == key then self.pending = nil end
    local qty = max(commodity and min(bagCount[key] or 0, f.units or 0) or 1, 1)
    local depEach = self:DepositEach(key, commodity, qty)
    local price, why = Deals.postPrice(rows, f.cost or 0, f.sell or 0, nil, depEach)
    if price then
        self.prices[key] = { price = price, qty = qty, commodity = commodity, why = why, at = GetTime(),
                             deposit = depEach * qty }
    else
        self.prices[key] = { hold = why, at = GetTime() }
    end
    self:Refresh()
end

-- True while a post is in flight or just finished: background searches wait,
-- so they never collide with your post ("doing that too fast").
function Seller:Busy()
    return self.posting ~= nil or GetTime() < (self.quietUntil or 0)
end

-- Must run from a click or keypress (posting is hardware-event protected).
function Seller:Post(key)
    if self.posting then say("Still posting the last item, one moment..."); return end
    local AH = C_AuctionHouse
    if not AH.IsThrottledMessageSystemReady() then
        say("The Auction House is busy, press again in a second.")
        self.quietUntil = GetTime() + 1.5
        return
    end
    local p = self.prices[key]
    if not p or not p.price or GetTime() - p.at >= PRICE_TTL then
        self.priority = key
        say(nameOf(key) .. ": checking current price, click again in a moment.")
        return
    end
    local bag, slot = self.FindInBags(key)
    if not bag then self:Refresh(); return end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local qty = p.commodity and min(p.qty, bagCount[key] or p.qty) or 1
    local deposit = (p.commodity and AH.CalculateCommodityDeposit(key, DURATION, qty)
        or AH.CalculateItemDeposit(loc, DURATION, qty)) or 0
    if deposit > GetMoney() then say("Not enough gold for the deposit (" .. money(deposit) .. ")."); return end

    self.posting = { key = key, qty = qty, before = bagCount[key] or 0, price = p.price,
                     deposit = deposit, why = p.why, at = GetTime() }
    self.quietUntil = GetTime() + 2
    local ok
    if p.commodity then
        ok = pcall(AH.PostCommodity, loc, DURATION, qty, p.price)
    else
        ok = pcall(AH.PostItem, loc, DURATION, 1, nil, p.price)
    end
    if not ok then
        self.posting = nil
        say("The game refused that post. " .. nameOf(key) .. " stays in your Flip Bag.")
        return
    end
    self:Refresh()
    -- If the bags haven't changed in 5s the post didn't happen: keep the item.
    C_Timer.After(5, function()
        local q = Seller.posting
        if q and q.key == key and q.at == Seller.posting.at then
            Seller.posting = nil
            say(nameOf(key) .. " wasn't posted (no change in your bags); it's still in the Flip Bag.")
            Seller:Refresh()
        end
    end)
end

-- Bags changed: if a post is in flight and the item left the bags, it worked.
function Seller:CheckPosted()
    local q = self.posting
    if not q then return end
    local gone = q.before - (bagCount[q.key] or 0)
    if gone <= 0 then return end
    self.posting = nil
    self.ForgetUnits(q.key, min(gone, q.qty))
    self.prices[q.key] = nil
    say(("Posted %dx %s at %s each, deposit %s (%s)."):format(min(gone, q.qty), nameOf(q.key), money(q.price), money(q.deposit), q.why))
end

function Seller:OnError(msg)
    if not self.posting then return end
    self.posting = nil
    self.quietUntil = GetTime() + 2
    say("Post failed: " .. tostring(msg) .. ". Item kept in the Flip Bag; press again in a moment.")
    self:Refresh()
end

-- Post-next for the keybind: first AH item with a ready price.
function Seller:PostNext()
    if self.posting then say("Still posting the last item, one moment..."); return end
    for _, e in ipairs(self:Entries()) do
        local p = e.action == "AH" and self.prices[e.key]
        if p and p.price and GetTime() - p.at < PRICE_TTL then return self:Post(e.key) end
    end
    for _, e in ipairs(self:Entries()) do
        if e.action == "AH" then self.priority = e.key; say("Pricing items, press again in a moment."); return end
    end
    say("Nothing ready to post.")
end

---------------------------------------------------------------- recovering / adding items

-- Every purchase is also written to a log, so the Flip Bag can be rebuilt.
function Seller.LogBuy(key, kind, units, cost, sell)
    local log = AuctionMeshDB.buys or {}
    AuctionMeshDB.buys = log
    log[#log + 1] = { key = key, kind = kind, units = units, cost = cost, sell = sell, t = GetServerTime() }
    while #log > 500 do table.remove(log, 1) end
end

-- Rebuilds missing Flip Bag entries from the last 3 days of purchases still in your bags.
function Seller:Restore()
    self:ScanBags()
    local since, agg = GetServerTime() - 3 * 86400, {}
    for _, b in ipairs(AuctionMeshDB.buys or {}) do
        if b.t >= since then
            local a = agg[b.key] or { units = 0, spent = 0 }
            a.units, a.spent = a.units + b.units, a.spent + b.cost * b.units
            a.kind, a.sell = b.kind, b.sell
            agg[b.key] = a
        end
    end
    local n = 0
    for key, a in pairs(agg) do
        local have = bagCount[key] or 0
        if not flips()[key] and have > 0 then
            flips()[key] = { kind = a.kind, sell = a.sell, units = min(have, a.units),
                             cost = floor(a.spent / a.units + 0.5), at = GetServerTime() }
            n = n + 1
        end
    end
    say(n > 0 and ("Restored " .. n .. " item(s) from your purchase log.")
        or "Nothing to restore from the purchase log. Drag items onto the Flip Bag to add them.")
    self:Refresh(true)
end

-- Adds an item from your bags by hand (drag it onto the Flip Bag, or /amesh track).
-- cost = what you paid per unit in copper, if you know it.
function Seller:Track(key, cost)
    self:ScanBags()
    local have = bagCount[key] or 0
    if have == 0 then say("That item isn't in your bags."); return end
    local Store = ns.Store
    local vendor = ns.Sniper.vendorOf(key)
    local market = Store.a[key] or Store.p[key]
    local kind = (vendor and (not market or vendor >= floor(market * 0.95))) and "VENDOR" or "FLIP"
    flips()[key] = { kind = kind, sell = (kind == "VENDOR") and vendor or (market or 0), units = have,
                     cost = cost or 0, unknownCost = (cost == nil), at = GetServerTime() }
    say(("Tracking %dx %s as %s%s."):format(have, nameOf(key), kind,
        cost and "" or " (cost unknown, so it posts at market: check the price before you click)"))
    self.prices[key] = nil
    self:Refresh(true)
end

local function acceptDrop()
    local what, itemID = GetCursorInfo()
    if what == "item" and itemID then
        ClearCursor()
        Seller:Track(itemID)
    end
end
Seller.AcceptDrop = acceptDrop

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
            GameTooltip:AddLine(("|cffaaaaaaDeposit %s (included: price covers cost + deposit + 5%% cut)|r"):format(money(p.deposit or 0)))
        else
            GameTooltip:AddLine(c[4] .. (ahOpen() and "Checking price..." or "Open the Auction House to post") .. "|r")
        end
    elseif e.action == "MAIL" then
        GameTooltip:AddLine(c[4] .. "In your mailbox: open it to collect|r")
    else
        GameTooltip:AddLine(c[4] .. "On hold: " .. (p and p.hold or "") .. "|r")
    end
    if e.f.unknownCost then
        GameTooltip:AddLine("|cffff8040Cost unknown (added by hand): it posts at market price, so check it first.|r")
    else
        GameTooltip:AddLine(("|cffaaaaaaPaid %s each.|r"):format(money(e.f.cost or 0)))
    end
    GameTooltip:AddLine("|cffaaaaaaRight-click: stop tracking.|r")
    GameTooltip:Show()
end

local function slotClick(self, button)
    if GetCursorInfo() then return Seller.AcceptDrop() end
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
    -- Drop an item from your bags onto the window to start tracking it.
    frame:SetScript("OnReceiveDrag", function() Seller.AcceptDrop() end)
    frame:SetScript("OnMouseUp", function() if GetCursorInfo() then Seller.AcceptDrop() end end)

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
        b:SetScript("OnReceiveDrag", function() Seller.AcceptDrop() end)
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
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, a1, a2)
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
            Seller.pending, Seller.posting = nil, nil
            Seller:Refresh()
        elseif event == "BAG_UPDATE_DELAYED" then
            Seller:ScanBags(); Seller:CheckPosted(); Seller:Refresh()
        elseif event == "UI_ERROR_MESSAGE" then
            Seller:OnError(a2 or a1)
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
