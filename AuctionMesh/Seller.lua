-- AuctionMesh Seller: everything after a purchase. No window of its own (see UI.lua).
--
-- Each item you bought is in one of four states:
--   MAIL    still in your mailbox. Opening the mailbox collects it.
--   VENDOR  sell to any NPC vendor. Opening a vendor sells these automatically.
--   AH      post on the auction house: priced 1 step under the cheapest
--           competitor, never below cost + deposit + 5% cut. One click or key
--           press per auction (a game rule). Macro: /click AuctionMeshPostButton
--   HOLD    the market is below your break-even; wait instead of losing money.
--
-- An item only leaves the list when your bags show it really went.
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

local COLORS = {
    VENDOR = { 0.2, 1, 0.4, "|cff33ff66" },
    AH = { 1, 0.82, 0, "|cffffd100" },
    MAIL = { 0.3, 0.6, 1, "|cff4d99ff" },
    HOLD = { 1, 0.25, 0.25, "|cffff4040" },
}

Seller.prices = {}  -- key -> { price, qty, commodity, why, at } or { hold = reason, at }

local function say(m)
    if ns.Print then ns.Print(m) end
    if ns.UI then ns.UI:Notice(m) end
end
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
        if inMail > 0 then
            local seen = self.mailCount and (self.mailCount[key] or 0) >= inMail
            out[#out + 1] = { key = key, action = "MAIL", count = inMail, f = f, seen = seen }
        end
    end
    -- Auctions you have posted stay in the portfolio until they sell.
    local own = ns.Sniper and ns.Sniper.ownRead and ns.Sniper.own or nil
    for key, L in pairs(AuctionMeshDB.listed or {}) do
        local live = nil
        if own then
            live = 0
            for _, q in pairs(own[key] or {}) do live = live + q end
        end
        if GetServerTime() - (L.at or 0) > 48 * 3600 then
            AuctionMeshDB.listed[key] = nil -- auctions last 12h at most; this record is stale
        else
            out[#out + 1] = { key = key, action = "LISTED", count = (live and live > 0) and live or L.qty, live = live,
                              f = { kind = "FLIP", cost = L.cost, sell = L.price }, listed = L }
        end
    end
    local order = { AH = 1, VENDOR = 2, MAIL = 3, HOLD = 4, LISTED = 5 }
    table.sort(out, function(a, b)
        if a.action ~= b.action then return order[a.action] < order[b.action] end
        return a.key < b.key
    end)
    return out
end

function Seller:Instructions(entries)
    local n = { AH = 0, VENDOR = 0, MAIL = 0, HOLD = 0, LISTED = 0 }
    for _, e in ipairs(entries) do n[e.action] = (n[e.action] or 0) + 1 end
    local lines = {}
    local function add(action, text) lines[#lines + 1] = COLORS[action][4] .. text .. "|r" end
    if n.MAIL > 0 then
        add("MAIL", mailOpen() and ("Collecting " .. n.MAIL .. " item(s) from the mailbox...")
            or ("Go to a mailbox: " .. n.MAIL .. " purchase(s) to collect."))
    end
    if n.AH > 0 then
        if ahOpen() then
            local ready = 0
            for _, e in ipairs(entries) do
                local p = e.action == "AH" and self.prices[e.key]
                if p and p.price and GetTime() - p.at < PRICE_TTL then ready = ready + 1 end
            end
            add("AH", ("Press Post on each item, or Post next (%d of %d priced and ready)."):format(ready, n.AH))
        else
            add("AH", "Open the Auction House to post " .. n.AH .. " item(s).")
        end
    end
    if n.VENDOR > 0 then
        add("VENDOR", merchantOpen() and "Selling vendor items..."
            or ("Talk to any vendor: " .. n.VENDOR .. " item(s) sell automatically."))
    end
    if n.HOLD > 0 then add("HOLD", n.HOLD .. " item(s) waiting: the market is below what you paid. Re-checked every 10 min.") end
    if n.LISTED > 0 then
        lines[#lines + 1] = ("|cffaaaaaa%d auction(s) listed. The gold arrives by mail when they sell.|r"):format(n.LISTED)
    end
    if #lines == 0 then
        lines[1] = "|cffaaaaaaNothing to sell. Items you buy on the BUY tab appear here.|r"
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
        -- Count what actually left the bags; only that is removed from your SELL list.
        Seller:ScanBags()
        local earned = 0
        for key, was in pairs(before) do
            local gone = was - (bagCount[key] or 0)
            if gone > 0 then
                local f = flips()[key]
                earned = earned + ((f and f.sell) or 0) * gone
                if f and not f.unknownCost then Seller.Realize(((f.sell or 0) - (f.cost or 0)) * gone) end
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
                    -- Say what is being taken, so an empty-looking mailbox is never a mystery.
                    local nm, _, _, cnt = GetInboxItem(i, 1)
                    AutoLootMailItem(i)
                    say(("|cff4d99ffCollected from mailbox:|r %s x %s is now in your bags."):format(tostring(cnt or 1), tostring(nm or "item")))
                    C_Timer.After(0.4, step); return
                elseif invoice == "seller" and (moneyAmt or 0) > 0 then
                    TakeInboxMoney(i); C_Timer.After(0.4, step); return
                end
            end
        end
        Seller.mailBusy = false
        -- Collection done: look at what is really in the mailbox and bags now.
        Seller:ScanBags()
        Seller:ScanMail()
        Seller:Reconcile()
        Seller:Refresh()
    end
    step()
end

-- Reads a "your auction sold" invoice: the price a buyer really paid.
-- Called whenever sale gold is taken from the mailbox (by us or by you).
function Seller:RecordSale(i)
    if not GetInboxInvoiceInfo then return end
    local kind, itemName, _, bid, buyout, feeBack, cut, _, _, _, count = GetInboxInvoiceInfo(i)
    if kind == "seller" then
        -- Shows in the log whether the posting fee really came back with the sale.
        ns.Log("INVOICE %s: sold for %s, posting fee returned %s, auction house cut %s, count %s",
            tostring(itemName), tostring(bid), tostring(feeBack), tostring(cut), tostring(count))
    end
    if kind ~= "seller" or not itemName or not bid or bid <= 0 then return end
    local key = AuctionMeshDB.names and AuctionMeshDB.names[itemName]
    if not key then return end
    count = (count and count > 0) and count or 1
    local sig, now = itemName .. ":" .. bid .. ":" .. count .. ":" .. i, GetTime()
    if self.lastSale == sig and now - (self.lastSaleAt or -100) < 5 then return end -- same mail, taken twice
    self.lastSale, self.lastSaleAt = sig, now
    local unit = floor(bid / count)
    ns.Log("SOLD %s x%d for %d each (invoice)", tostring(key), count, unit)
    if ns.Sync then ns.Sync:ObserveSold(key, unit, count) end
    local L = AuctionMeshDB.listed and AuctionMeshDB.listed[key]
    local profitText = ""
    if L then
        if L.cost then
            local profit = bid - (cut or floor(bid * Deals.cfg.cut)) - L.cost * count
            Seller.Realize(profit)
            profitText = (" Profit %s%s."):format(profit >= 0 and "+" or "-", money(math.abs(profit)))
        end
        L.qty = L.qty - count
        if L.qty <= 0 then AuctionMeshDB.listed[key] = nil end
    end
    say(("|cff33ff66Sold:|r %d x %s at %s each.%s"):format(count, itemName, money(unit), profitText))
end

-- Counts every item attached to mail in the inbox (nil until the mailbox is opened).
function Seller:ScanMail()
    local shown, total = GetInboxNumItems()
    local counts = {}
    for i = 1, shown or 0 do
        local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem then
            for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local _, itemID, _, count = GetInboxItem(i, j)
                if itemID then counts[itemID] = (counts[itemID] or 0) + (count or 1) end
            end
        end
    end
    self.mailCount = counts
    -- More than ~50 mails: the client only shows part of the inbox, so we can't be sure.
    self.mailComplete = (total or shown or 0) <= (shown or 0)
end

-- With the real bag + mailbox contents known, fix anything the Flip Bag got wrong:
-- units that are in neither place (a purchase that never happened, or items you
-- moved elsewhere) are removed, with a message. Purchases younger than 2 min are
-- left alone in case the mail is still on its way.
function Seller:Reconcile()
    if not self.mailCount then return end
    local now = GetServerTime()
    for key, f in pairs(flips()) do
        local inMail = self.mailCount[key] or 0
        local have = (bagCount[key] or 0) + inMail
        if inMail > 0 then f.mailVerified = now end
        if self.mailComplete and have < (f.units or 0) and now - (f.at or 0) > 120 then
            local missing = f.units - have
            ns.Log("RECONCILE %s: expected %d, bags %d, mail %d -> removing %d", tostring(key), f.units,
                bagCount[key] or 0, inMail, missing)
            say(("|cffff8040%s: %d expected but not in your bags or mailbox, removed from your SELL list.|r")
                :format(nameOf(key), missing))
            if have <= 0 then flips()[key] = nil; self.prices[key] = nil else f.units = have end
        end
    end
end

---------------------------------------------------------------- AH pricing (background) and posting (click)

function Seller:NextToPrice()
    local now = GetTime()
    self.pricedAt = self.pricedAt or {}
    local last = self.pricedAt
    if self.priority then
        local k = self.priority
        self.priority = nil
        if not last[k] or now - last[k] >= 5 then last[k] = now; return k end
    end
    for key, f in pairs(flips()) do
        if f.kind == "FLIP" and (bagCount[key] or 0) > 0 then
            local p = self.prices[key]
            local ttl = (p and p.hold) and HOLD_TTL or PRICE_TTL
            -- at most one price check per item every 20s, whatever else happens
            if (not p or now - p.at >= ttl) and (not last[key] or now - last[key] >= 20) then
                last[key] = now
                return key
            end
        end
    end
end

function Seller:Tick()
    if not ahOpen() then return end
    -- Pricing searches are sent by the sniper (Sniper:NextCheck gives them the
    -- first turn); here we only clear a check that never came back.
    if self.pending and GetTime() - self.pending.at > PRICE_TIMEOUT then
        self.pending = nil
        self:Refresh()
    end
end

-- Real deposit per unit for posting `qty` of this item now (12h).
function Seller:DepositTotal(key, commodity, qty)
    local AH, d = C_AuctionHouse, nil
    if commodity then
        d = AH.CalculateCommodityDeposit(key, DURATION, qty)
    else
        local bag, slot = self.FindInBags(key)
        if bag then d = AH.CalculateItemDeposit(ItemLocation:CreateFromBagAndSlot(bag, slot), DURATION, 1) end
    end
    if d and d >= 0 then return d end
    local per, dmin = ns.Sniper.depositInfo(key, commodity)
    if per == math.huge then return 0 end
    return max(dmin, math.ceil(per * qty))
end

-- Called by the sniper for every item search result (ours or anyone's).
function Seller:OnResults(key, rows, commodity)
    local f = flips()[key]
    if not f or f.kind ~= "FLIP" then return end
    if self.pending and self.pending.key == key then self.pending = nil end
    -- The posting fee comes back when the item sells, so the lowest acceptable
    -- price only has to cover what you paid plus the 5% cut.
    local feeEach = 0
    if Deals.cfg.depositIsCost then
        local qty = max(commodity and min(bagCount[key] or 0, f.units or 0) or 1, 1)
        feeEach = math.ceil(self:DepositTotal(key, commodity, qty) / qty)
    end
    local price, why = Deals.postPrice(rows, f.cost or 0, f.sell or 0, nil, feeEach)
    ns.Log("PRICE %s: lowest=%s cost=%s -> %s (%s)", tostring(key), tostring(rows[1] and rows[1].price),
        tostring(f.cost), tostring(price), tostring(why))
    if price then
        self.prices[key] = { price = price, commodity = commodity, why = why, at = GetTime() }
    else
        self.prices[key] = { hold = why, at = GetTime() }
    end
    self:Refresh()
end

-- How many units one post puts up: everything of this flip that is in your bags
-- right now (stackables), or one item (gear). Counted at post time, not earlier.
function Seller:PostQty(key, p)
    if not p.commodity then return 1 end
    local f = flips()[key]
    return min(bagCount[key] or 0, f and f.units or 0)
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
    if not ns.Gate:ReadyForUser() then
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
    local qty = self:PostQty(key, p)
    if qty <= 0 then self:Refresh(); return end
    local deposit = (p.commodity and AH.CalculateCommodityDeposit(key, DURATION, qty)
        or AH.CalculateItemDeposit(loc, DURATION, qty)) or 0
    if deposit > GetMoney() then say("Not enough gold for the deposit (" .. money(deposit) .. ")."); return end

    ns.Gate:Use(("post %dx %s @%d (deposit %d, commodity=%s, step=%d)"):format(qty, tostring(key), p.price, deposit, tostring(p.commodity), Deals.cfg.step))
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
        ns.Log("POST refused by client for %s", tostring(key))
        self.posting = nil
        say("The game refused that post. " .. nameOf(key) .. " stays in your SELL list.")
        return
    end
    self:Refresh()
    -- If the bags haven't changed in 5s the post didn't happen: keep the item.
    C_Timer.After(5, function()
        local q = Seller.posting
        if q and q.key == key and q.at == Seller.posting.at then
            Seller.posting = nil
            say(nameOf(key) .. " wasn't posted (no change in your bags); it's still in your SELL list.")
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
    ns.Log("POST confirmed by bags: %s -%d", tostring(q.key), gone)
    -- Sale invoices only carry the item's name: remember which item it is.
    AuctionMeshDB.names = AuctionMeshDB.names or {}
    AuctionMeshDB.names[nameOf(q.key)] = q.key
    do  -- keep the position: quantity, your price and what it cost you
        local f = flips()[q.key]
        local posted = min(gone, q.qty)
        AuctionMeshDB.listed = AuctionMeshDB.listed or {}
        local L = AuctionMeshDB.listed[q.key]
        local cost = f and not f.unknownCost and f.cost or (L and L.cost) or nil
        if L then
            L.qty, L.price, L.cost, L.at = L.qty + posted, q.price, cost, GetServerTime()
        else
            AuctionMeshDB.listed[q.key] = { qty = posted, price = q.price, cost = cost, at = GetServerTime() }
        end
    end
    self.ForgetUnits(q.key, min(gone, q.qty))
    self.prices[q.key] = nil
    say(("Posted %dx %s at %s each, deposit %s (%s)."):format(min(gone, q.qty), nameOf(q.key), money(q.price), money(q.deposit), q.why))
end

function Seller:OnError(msg)
    if not self.posting then return end
    ns.Log("POST error for %s: %s", tostring(self.posting.key), tostring(msg))
    self.posting = nil
    self.quietUntil = GetTime() + 2
    say("Post failed: " .. tostring(msg) .. ". Item kept in your SELL list; press again in a moment.")
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
        or "Nothing to restore from the purchase log. Drag items onto the AuctionMesh window to add them.")
    self:Refresh("open")
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
    self:Refresh("open")
end

local function acceptDrop()
    local what, itemID = GetCursorInfo()
    if what == "item" and itemID then
        ClearCursor()
        Seller:Track(itemID)
    end
end
Seller.AcceptDrop = acceptDrop

---------------------------------------------------------------- the numbers per item

-- Short money text: 1g20s, 35s40c, 79c (colored like coins).
local function short(c)
    if not c then return "?" end
    local neg = c < 0
    c = math.abs(floor(c + 0.5))
    local g, sv, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out
    if g > 0 then out = ("|cffffd700%dg|r|cffc7c7cf%02ds|r"):format(g, sv)
    elseif sv > 0 then out = ("|cffc7c7cf%ds|r|cffeda55f%02dc|r"):format(sv, cp)
    else out = ("|cffeda55f%dc|r"):format(cp) end
    return (neg and "-" or "") .. out
end
Seller.short = short

-- paid (per unit, nil if unknown), sell (per unit), net (what one unit puts in
-- your pocket after the AH cut and deposit), profit (net - paid), live (true
-- when sell comes from the current AH listings rather than the buy-time plan).
function Seller:Numbers(e)
    local f = e.f
    local paid = (not f.unknownCost) and f.cost or nil
    if f.kind == "VENDOR" then
        return paid, f.sell or 0, f.sell or 0, paid and ((f.sell or 0) - paid), true
    end
    local p = self.prices[e.key]
    local live = p and p.price and true or false
    local sell = live and p.price or (f.sell or 0)
    local net = floor(sell * (1 - Deals.cfg.cut)) -- the posting fee is returned on sale
    return paid, sell, net, paid and (net - paid), live
end

---------------------------------------------------------------- window hooks (the window lives in UI.lua)

-- Re-render; with show=true also open the window on the SELL tab if there is something to do.
function Seller:Refresh(show)
    local UI = ns.UI
    if not UI then return end
    if show == "open" and #self:Entries() > 0 then UI:Open("SELL") end
    UI:Dirty()
end

-- Profit actually banked (vendor sales and collected auction sales).
function Seller.Realize(copper)
    AuctionMeshDB.realized = (AuctionMeshDB.realized or 0) + copper
    ns.Log("REALIZED %+d (total %d)", copper, AuctionMeshDB.realized)
end

function Seller:Untrack(key)
    flips()[key] = nil
    if AuctionMeshDB.listed then AuctionMeshDB.listed[key] = nil end
    self.prices[key] = nil
    say("Stopped tracking " .. nameOf(key) .. ".")
    self:Refresh()
end

---------------------------------------------------------------- events

function Seller:Init()
    self:ScanBags()
    if hooksecurefunc and TakeInboxMoney then
        hooksecurefunc("TakeInboxMoney", function(i) Seller:RecordSale(i) end)
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED",
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "MERCHANT_SHOW" then
            Seller:Refresh("open")
            C_Timer.After(0.3, function() Seller:SellVendor() end)
        elseif event == "MAIL_SHOW" then
            Seller:Refresh("open"); Seller:CollectMail()
        elseif event == "MAIL_INBOX_UPDATE" then
            Seller:CollectMail()
        elseif event == "AUCTION_HOUSE_SHOW" then
            for k, p in pairs(Seller.prices) do if p.price then Seller.prices[k] = nil end end
            Seller:Refresh()
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
        if n > 0 then say(n .. " item(s) to sell. Type /amesh to see what to do.") end
    end)
end

return Seller
