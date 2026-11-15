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
local DURATION_HOURS = 12
-- A computed post price is trusted for PRICE_TTL seconds and is checked again
-- once it is PRICE_REFRESH old, so it never runs out while the item is waiting
-- to be posted. (It used to be checked again only after it had run out: the
-- row's Post button then disappeared until the new price arrived, while the
-- "Post next" button stayed.)
local PRICE_TTL = 120
local PRICE_REFRESH = 45
Seller.PRICE_TTL = PRICE_TTL

-- True when this item has a live price that Post can use right now.
function Seller:PriceReady(key)
    local p = self.prices[key]
    return (p and p.price and GetTime() - p.at < PRICE_TTL) and true or false
end
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
        add("VENDOR", merchantOpen() and ("Press Sell all to vendor (or Sell on a row) to sell " .. n.VENDOR .. " item(s).")
            or ("Talk to any vendor to sell " .. n.VENDOR .. " item(s). Nothing is sold until you press Sell."))
    end
    if n.HOLD > 0 then add("HOLD", n.HOLD .. " item(s) waiting: the market is below what you paid. Re-checked every 10 min.") end
    if n.LISTED > 0 then
        lines[#lines + 1] = ("|cffaaaaaa%d auction(s) listed. The gold arrives by mail when they sell.|r"):format(n.LISTED)
    end
    if #lines == 0 then
        lines[1] = "|cffaaaaaaNothing to sell. Items you buy on the Trades tab appear here.|r"
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
    local all = {}
    for key in pairs(flips()) do all[key] = bagCount[key] or 0 end
    local i = 0
    local function finish()
        -- Count what actually left the bags; only that is removed from the Bags tab.
        Seller:ScanBags()
        local earned = 0
        for key, was in pairs(before) do
            local gone = was - (bagCount[key] or 0)
            if gone > 0 then
                local f = flips()[key]
                earned = earned + ((f and f.sell) or 0) * gone
                if f and not f.unknownCost then Seller.Realize(((f.sell or 0) - (f.cost or 0)) * gone) end
                if ns.Journal then ns.Journal:Vendored(key, gone, (f and f.sell) or 0) end
                Seller.ForgetUnits(key, gone)
            end
        end
        Seller.selling = false
        -- tracked items that were not in the button's queue but left the bags meanwhile: sold by hand
        local byHand = {}
        for key, was in pairs(all) do if not before[key] then byHand[key] = was end end
        Seller:CheckSoldByHand(byHand)
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

-- You sold a tracked item to a vendor yourself (not with the panel's button).
-- Seen as: the vendor window is open and tracked units left your bags. It is
-- recorded like any vendor sale, so the profit is banked and the trade closes
-- instead of being reported as "not found".
function Seller:CheckSoldByHand(before)
    if not merchantOpen() or self.selling or not before then return end
    for key, f in pairs(flips()) do
        local gone = (before[key] or 0) - (bagCount[key] or 0)
        if gone > 0 then
            local n = min(gone, f.units or 0)
            local unit = ns.Sniper and ns.Sniper.vendorOf(key) or 0
            if n > 0 and unit > 0 then
                if not f.unknownCost then Seller.Realize((unit - (f.cost or 0)) * n) end
                if ns.Journal then ns.Journal:Vendored(key, n, unit) end
                Seller.ForgetUnits(key, n)
                say(("Sold to the vendor by hand: %d x %s at %s each."):format(n, nameOf(key), money(unit)))
            end
        end
    end
end

-- Gold arrived while the mailbox is open: it is sale gold that was counted as
-- "waiting in the mailbox", so it comes off that figure at once. (The figure
-- used to be corrected only by a full reading of the mailbox at the end of
-- collecting. Walking away before that reading left the collected gold
-- counted twice: once as gold in hand, once as still waiting. A real total
-- read 92s when 77s was right.)
function Seller:MailGold(delta)
    local s = AuctionMeshDB.sales
    if s then
        local take = min(delta, s.waiting or 0)
        s.waiting, delta = (s.waiting or 0) - take, delta - take
        local now, keep = GetServerTime(), {}
        for _, p in ipairs(s.pending or {}) do
            if p.at <= now and delta > 0 then
                local t = min(delta, p.amount)
                p.amount, delta = p.amount - t, delta - t
            end
            if p.amount > 0 then keep[#keep + 1] = p end
        end
        s.pending = keep
    end
    local S = ns.Sniper
    if S and S.ownSoldPay and delta > 0 then
        local t, keep = GetTime(), {}
        for _, r in ipairs(S.ownSoldPay) do
            if r.due <= t and delta > 0 then
                local x = min(delta, r.amount)
                r.amount, delta = r.amount - x, delta - x
            end
            if r.amount > 0 then keep[#keep + 1] = r end
        end
        S.ownSoldPay = keep
    end
end

function Seller:CollectMail()
    if self.mailBusy then return end
    self.mailBusy = true
    -- read what is there BEFORE anything is taken, so the figures are current
    -- even if the mailbox is closed before collecting has finished
    if (GetInboxNumItems() or 0) > 0 then self:ScanMail() end
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
                elseif not invoice and hasItem and (moneyAmt or 0) == 0 then
                    -- a returned (expired) auction of an item we are tracking
                    local nm, id, _, cnt = GetInboxItem(i, 1)
                    local f = id and flips()[id]
                    if f and f.proof == "auction expired, returned by mail" and (bagCount[id] or 0) < (f.units or 0) then
                        AutoLootMailItem(i)
                        say(("|cff4d99ffCollected from mailbox:|r %s x %s (expired auction) is back in your bags."):format(tostring(cnt or 1), tostring(nm or "item")))
                        C_Timer.After(0.4, step); return
                    end
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
    if ns.Journal then ns.Journal:Sold(key, count, unit, bid - (cut or floor(bid * Deals.cfg.cut))) end
    if ns.Sync then ns.Sync:ObserveSold(key, unit, count) end
    local L = AuctionMeshDB.listed and AuctionMeshDB.listed[key]
    local profitText = ""
    -- DOES THE POSTING FEE COME BACK? The sale invoice says so. The first sale
    -- settles it for this realm: if no fee is returned, every profit figure
    -- from then on has the fee taken off.
    local feeLost = 0
    if L and (L.fee or 0) > 0 then
        local cfg = AuctionMeshDB.cfg
        local back = (feeBack or 0) > 0
        if cfg.feeBack ~= back then
            cfg.feeBack = back
            Deals.cfg.depositIsCost = not back
            say(back and "|cff33ff66Confirmed on this realm:|r the posting fee comes back when an auction sells. Profit figures are right as they are."
                or "|cffff8040Found out on this realm:|r the posting fee does NOT come back when an auction sells. From now on it is taken off every profit figure.")
        end
        if not back then feeLost = floor(L.fee * math.min(1, count / math.max(1, L.qty)) + 0.5) end
    end
    if L then
        if L.cost then
            local profit = bid - (cut or floor(bid * Deals.cfg.cut)) - L.cost * count - feeLost
            if feeLost > 0 then L.fee = math.max(0, L.fee - feeLost) end
            Seller.Realize(profit)
            profitText = (" Profit %s%s."):format(profit >= 0 and "+" or "-", money(math.abs(profit)))
        end
        -- score the prediction: real sale price against the price planned at purchase
        if ns.Learn and (L.plan or L.price or 0) > 0 then ns.Learn:Outcome(key, true, unit / (L.plan or L.price)) end
        L.qty = L.qty - count
        if L.qty <= 0 then AuctionMeshDB.listed[key] = nil end
    end
    say(("|cff33ff66Sold:|r %d x %s at %s each.%s"):format(count, itemName, money(unit), profitText))
end

-- Counts every item attached to mail in the inbox (nil until the mailbox is opened).
-- Sale gold as last seen at the mailbox: in the mailbox now, still on its way,
-- seconds until the next arrival, and the items those sales were for.
function Seller:SalesMoney()
    local s = AuctionMeshDB.sales
    local waiting, onway, nextAt, keys = 0, 0, nil, {}
    local now = GetServerTime()
    if s then
        waiting = s.waiting or 0
        for _, p in ipairs(s.pending or {}) do
            if p.at <= now then
                waiting = waiting + p.amount
            else
                onway = onway + p.amount
                if not nextAt or p.at < nextAt then nextAt = p.at end
            end
            if p.key then keys[p.key] = true end
        end
    end
    -- Auctions the auction house itself reports as sold and not yet paid out,
    -- for which no invoice has been seen at the mailbox yet: counted at your
    -- own listed price, after the cut.
    local S = ns.Sniper
    local pay = S and S.ownSoldPay
    if pay and #pay > 0 then
        -- The auction house's own list of sold auctions is newer and more exact
        -- than what was seen at the last mailbox visit: it replaces the
        -- invoice figures for sales that have not been paid out yet.
        onway, nextAt = 0, nil
        local t = GetTime()
        for _, r in ipairs(pay) do
            if r.due > t then
                onway = onway + r.amount
                local at = now + (r.due - t)
                if not nextAt or at < nextAt then nextAt = at end
            else
                waiting = waiting + r.amount -- its time has passed: it is in the mailbox
            end
        end
    end
    for key in pairs(S and S.ownSoldQty or {}) do
        -- everything of it sold: nothing of it is "listed" any more
        local live = 0
        for _, q in pairs(S.own and S.own[key] or {}) do live = live + q end
        if live == 0 then keys[key] = true end
    end
    return waiting, onway, nextAt and (nextAt - now) or nil, keys
end

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
    -- Sales, read from the invoices themselves (no guessing): gold that is in
    -- the mailbox now, and gold from sales the game is still holding back,
    -- with the time the game says it will arrive.
    if GetInboxInvoiceInfo then
        local sales = { waiting = 0, pending = {} }
        for i = 1, shown or 0 do
            local kind, itemName, _, bid, _, deposit, cut, _, etaHour, etaMin = GetInboxInvoiceInfo(i)
            local _, _, _, _, moneyAmt = GetInboxHeaderInfo(i)
            if kind == "seller" and (moneyAmt or 0) > 0 then
                sales.waiting = sales.waiting + moneyAmt
            elseif kind == "seller_temp_invoice" and bid and bid > 0 then
                local mins = 0
                if etaHour and etaMin and GetGameTime then
                    local h, m = GetGameTime()
                    mins = ((etaHour * 60 + etaMin) - ((h or 0) * 60 + (m or 0))) % 1440
                    if mins > 720 then mins = 0 end -- the time has already passed
                end
                sales.pending[#sales.pending + 1] = { amount = bid + (deposit or 0) - (cut or 0), at = GetServerTime() + mins * 60,
                    key = AuctionMeshDB.names and AuctionMeshDB.names[itemName] or nil }
            end
        end
        AuctionMeshDB.sales = sales
        -- sales read from the auction house whose pay-out time has passed are
        -- now in this mailbox reading (or already collected): not counted twice
        local S = ns.Sniper
        if S and S.ownSoldPay then
            local keep, t = {}, GetTime()
            for _, r in ipairs(S.ownSoldPay) do if r.due > t then keep[#keep + 1] = r end end
            S.ownSoldPay = keep
        end
    end
    do  -- kept for the snapshot: what the mailbox held when it was last read
        local s = AuctionMeshDB.sales
        local items = {}
        for id, n in pairs(counts) do items[id] = n end
        AuctionMeshDB.mailSeen = { at = GetServerTime(), mails = total or shown or 0, items = items,
                                   gold = s and s.waiting or 0, pending = s and #(s.pending or {}) or 0 }
    end
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
    -- An auction that expired comes back in the mail. It is one of ours if we
    -- have it on record as listed, it is no longer among our auctions, and the
    -- item is sitting in the mailbox. Put it back in the portfolio with its cost
    -- (so it can be reposted without selling at a loss) and score the failure.
    local S = ns.Sniper
    if S and S.ownRead then
        local returned = false
        for key, L in pairs(AuctionMeshDB.listed or {}) do
            local inMail = self.mailCount[key] or 0
            local live = 0
            for _, q in pairs(S.own[key] or {}) do live = live + q end
            if inMail > 0 and live == 0 and not flips()[key] and now - (L.at or 0) > 600 then
                local n = min(inMail, L.qty)
                flips()[key] = { kind = "FLIP", units = n, cost = L.cost or 0, unknownCost = (L.cost == nil),
                                 sell = L.price, at = now, proof = "auction expired, returned by mail" }
                AuctionMeshDB.listed[key] = nil
                -- an auction that does not sell never gets its posting fee back: that is a real loss
                if (L.fee or 0) > 0 then
                    Seller.Realize(-L.fee)
                    if ns.Journal then ns.Journal:FeeLost(key, L.fee) end
                    say(("The posting fee of %s for %s is lost (the auction did not sell)."):format(money(L.fee), nameOf(key)))
                end
                if ns.Journal then ns.Journal:Expired(key, n) end
                if ns.Learn then ns.Learn:Outcome(key, false) end
                say(("|cffff8040Expired unsold:|r %d x %s came back by mail. It is on the Bags tab again."):format(n, nameOf(key)))
                returned = true
            end
        end
        if returned then C_Timer.After(0.5, function() Seller:CollectMail() end) end
    end
    for key, f in pairs(flips()) do
        local inMail = self.mailCount[key] or 0
        local have = (bagCount[key] or 0) + inMail
        if inMail > 0 then f.mailVerified = now end
        if have >= (f.units or 0) then f.missingSince = nil end
        if self.mailComplete and have < (f.units or 0) and now - (f.at or 0) > 120 and not f.missingSince then
            -- first time it is not found: keep it, and look again at a later mailbox visit
            f.missingSince = now
            ns.Log("RECONCILE %s: expected %d, bags %d, mail %d -> not found yet, kept for now", tostring(key), f.units, bagCount[key] or 0, inMail)
        elseif self.mailComplete and have < (f.units or 0) and f.missingSince and now - f.missingSince > 300 then
            local missing = f.units - have
            ns.Log("RECONCILE %s: expected %d, bags %d, mail %d -> removing %d", tostring(key), f.units,
                bagCount[key] or 0, inMail, missing)
            say(("|cffff8040%s: %d expected but not in your bags or mailbox, removed from the Bags tab.|r")
                :format(nameOf(key), missing))
            if ns.Journal then ns.Journal:Dropped(key, missing, "not found in bags or mailbox") end
            if have <= 0 then flips()[key] = nil; self.prices[key] = nil else f.units = have end
        end
    end
    -- the journal follows what the mailbox check just established
    if ns.Journal then ns.Journal:Sync(flips(), AuctionMeshDB.listed, nameOf) end
end

---------------------------------------------------------------- AH pricing (background) and posting (click)

function Seller:NextToPrice()
    local now = GetTime()
    self.pricedAt = self.pricedAt or {}
    local last = self.pricedAt
    if self.priority then
        local k = self.priority
        self.priority = nil
        -- you pressed Post on it: checked at once (not more than one check per 1.5s, however fast you press)
        if not last[k] or now - last[k] >= 1.5 then last[k] = now; return k end
        self.priority = k -- too soon: keep it for the next turn instead of dropping it
    end
    for key, f in pairs(flips()) do
        if f.kind == "FLIP" and (bagCount[key] or 0) > 0 then
            local p = self.prices[key]
            local ttl = (p and p.hold) and HOLD_TTL or PRICE_REFRESH
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
    if self.note and self.note.key == key then self.note = nil end -- the price it was waiting for is here
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

-- WHY NOTHING HAPPENED. Every press of Post that does not post says why, on
-- the row itself (next to the button being pressed), for 4 seconds. Chat gets
-- the message once, not once per press.
function Seller:Note(key, text)
    local was = self.note
    self.note = { key = key, text = text, at = GetTime() }
    if not was or was.text ~= text or GetTime() - was.at > 4 then
        if ns.Print then ns.Print(nameOf(key) .. ": " .. text) end
    end
    if ns.UI then ns.UI:Dirty() end
end

function Seller:NoteFor(key)
    local n = self.note
    return (n and n.key == key and GetTime() - n.at < 4) and n.text or nil
end

-- Must run from a click or keypress (posting is hardware-event protected).
function Seller:Post(key)
    if self.posting then
        self:Note(self.posting.key, "Posting: waiting for the auction house to confirm.")
        return
    end
    local AH = C_AuctionHouse
    -- The price first. A press with no live price only asks for one; it must
    -- NOT quieten the background, because the price check is background work.
    -- (Pressing Post repeatedly used to push the price check back each time,
    -- so the button could be spammed for as long as you liked with no effect.)
    local p = self.prices[key]
    if not p or not p.price or GetTime() - p.at >= PRICE_TTL then
        self.priority = key
        self:Note(key, (p and p.hold) and "Not posted: the market is below what you paid."
            or "Getting the live price first. Press Post again in a second.")
        return
    end
    if not ns.Gate:ReadyForUser() then
        self.quietUntil = GetTime() + 1.0
        self:Note(key, "The auction house is busy for a moment. Keep pressing.")
        return
    end
    local bag, slot = self.FindInBags(key)
    if not bag then self:Note(key, "Not found in your bags."); self:Refresh(); return end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local qty = self:PostQty(key, p)
    if qty <= 0 then self:Note(key, "None of it is in your bags."); self:Refresh(); return end
    local deposit = (p.commodity and AH.CalculateCommodityDeposit(key, DURATION, qty)
        or AH.CalculateItemDeposit(loc, DURATION, qty)) or 0
    if deposit > GetMoney() then
        self:Note(key, "Not enough gold for the posting fee (" .. Seller.short(deposit) .. ").")
        return
    end

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
        self:Note(key, "The game refused that post. Press again.")
        return
    end
    self:Refresh()
    -- If the bags haven't changed in 5s the post didn't happen: keep the item.
    C_Timer.After(5, function()
        local q = Seller.posting
        if q and q.key == key and q.at == Seller.posting.at then
            Seller.posting = nil
            Seller:Note(key, "Not posted: the auction house did not take it. Press Post again.")
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
    if self.note and self.note.key == q.key then self.note = nil end
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
        local plan = f and f.sell or q.price -- the resale price predicted when it was bought
        if L then
            L.qty, L.price, L.cost, L.at, L.plan = L.qty + posted, q.price, cost, GetServerTime(), plan
            L.fee = (L.fee or 0) + (q.deposit or 0)
        else
            AuctionMeshDB.listed[q.key] = { qty = posted, price = q.price, cost = cost, at = GetServerTime(), plan = plan, fee = q.deposit or 0 }
        end
    end
    if ns.Journal then ns.Journal:Posted(q.key, min(gone, q.qty), q.price) end
    self.ForgetUnits(q.key, min(gone, q.qty))
    self.prices[q.key] = nil
    say(("Posted %dx %s at %s each, deposit %s (%s)."):format(min(gone, q.qty), nameOf(q.key), money(q.price), money(q.deposit), q.why))
end

function Seller:OnError(msg)
    if not self.posting then return end
    ns.Log("POST error for %s: %s", tostring(self.posting.key), tostring(msg))
    local key = self.posting.key
    self.posting = nil
    self.quietUntil = GetTime() + 1
    self:Note(key, "Not posted. The game says: " .. tostring(msg))
    self:Refresh()
end

-- Post-next for the keybind: first AH item with a ready price.
function Seller:PostNext()
    if self.posting then return self:Post(self.posting.key) end
    for _, e in ipairs(self:Entries()) do
        local p = e.action == "AH" and self.prices[e.key]
        if p and p.price and GetTime() - p.at < PRICE_TTL then return self:Post(e.key) end
    end
    for _, e in ipairs(self:Entries()) do
        if e.action == "AH" then return self:Post(e.key) end -- no live price yet: asks for it and says so on the row
    end
    say("Nothing to post.")
end

---------------------------------------------------------------- recovering / adding items

-- Every purchase is also written to a log, so the Flip Bag can be rebuilt.
function Seller.LogBuy(key, kind, units, cost, sell)
    local log = AuctionMeshDB.buys or {}
    AuctionMeshDB.buys = log
    log[#log + 1] = { key = key, kind = kind, units = units, cost = cost, sell = sell, t = GetServerTime() }
    while #log > 500 do table.remove(log, 1) end
    if ns.Journal then ns.Journal:Bought(key, nameOf(key), kind, units, cost, sell) end
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
    if ns.Journal then
        ns.Journal:Dropped(key, nil, "tracked again by hand")
        ns.Journal:Bought(key, nameOf(key), kind, have, cost, flips()[key].sell, "added by hand")
    end
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

-- Money as text: 42g 58s 88c.
local function short(c)
    if not c then return "?" end
    -- In the game: plain text with spaces, "42g 58s 88c", taking the colour of
    -- the line it is on (white = held, green = earned, orange = depends on a sale).
    if not ns.plainMoney then
        local v = math.abs(floor(c + 0.5))
        local g, sv, cp = floor(v / 10000), floor(v / 100) % 100, v % 100
        local out
        if g > 0 then out = ("%dg %02ds %02dc"):format(g, sv, cp)
        elseif sv > 0 then out = ("%ds %02dc"):format(sv, cp)
        else out = ("%dc"):format(cp) end
        return (c < 0 and "-" or "") .. out
    end
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
-- MONEY THAT IS OUT OF REACH: live auctions at their listed price, sales the
-- auction house has not paid out yet, and sale gold waiting in the mailbox.
-- Returns the total, seconds to the next pay-out, and the three parts.
function Seller:Tied()
    local waiting, onway, nextIn, soldKeys = self:SalesMoney()
    local listed = 0
    for key, L in pairs(AuctionMeshDB.listed or {}) do
        if not soldKeys[key] then listed = listed + floor((L.price or 0) * (1 - Deals.cfg.cut)) * (L.qty or 0) end
    end
    return listed + onway + waiting, nextIn, listed, onway, waiting
end

-- ONE RECOMMENDATION for a holding: what to do with it now, and why. Built
-- only from what is known for certain (live price, your cost, the cheapest
-- listing from the last radar read, measured sales per hour, mailbox invoices).
-- Returns the text and a tone: "do" (act now), "wait", or "warn".
function Seller:Advice(e)
    local key = e.key
    local St, cfg = ns.Store, Deals.cfg
    local paid, _, _, profit = self:Numbers(e)
    local rate = St.Rate and St:Rate(key, 100) or nil
    local sells = (rate and rate >= 1) and (" About %d sell an hour."):format(floor(rate + 0.5)) or ""
    local function signed(c) return (c >= 0 and "+ " or "- ") .. short(math.abs(c)) end
    if e.action == "MAIL" then
        return "Visit a mailbox to collect it.", "do"
    elseif e.action == "VENDOR" then
        return profit and ("Sell it to any vendor: %s, guaranteed."):format(signed(profit * e.count)) or "Sell it to any vendor.", "do"
    elseif e.action == "AH" then
        local p = self.prices[key]
        if p and p.price then
            if not paid then
                return ("Post at %s each (Bags tab). Your cost is not known, so check that price yourself first."):format(short(p.price)), "warn"
            end
            local each = floor(p.price * (1 - cfg.cut)) - paid
            local text = ("Post %d at %s each (Bags tab, Post): %s after the cut, in your hands about an hour after it sells.%s"):format(
                e.count, short(p.price), signed(each * e.count), sells)
            -- the quick way out, when a vendor pays more than it cost: less profit, but the gold is back at once
            local v = ns.Sniper and ns.Sniper.vendorOf(key) or 0
            if v > paid then
                text = text .. (" Or sell it to a vendor now for %s: no wait, no fee."):format(signed((v - paid) * e.count))
            end
            return text, "do"
        end
        return ahOpen() and "Its live price is being checked. Post appears on the Bags tab in a moment."
            or "Open the auction house: the live price is checked, then press Post.", "do"
    elseif e.action == "HOLD" then
        local low = St.p[key]
        local text = "Hold: do not sell now."
        if paid and low then
            local each = floor(low * (1 - cfg.cut)) - paid
            text = ("Hold: the cheapest listing is %s. Selling under it now would be %s each."):format(short(low), signed(each))
        end
        local tr = St.Trend and St:Trend(key, GetServerTime(), 24) or nil
        if tr then text = text .. (" Price moved %+d%% in 24h."):format(floor(tr * 100 + 0.5)) end
        return text .. " It is re-checked every time the auction house is open.", "wait"
    end
    -- LISTED
    local L = e.listed
    local price = L.price or 0
    do  -- sold and waiting to be paid: say so whatever else the listing looks like
        local _, _, nextIn, soldKeys = self:SalesMoney()
        if soldKeys[key] then
            return "Sold. The gold arrives by mail" .. (nextIn and (" in about %d min"):format(max(1, floor(nextIn / 60 + 0.5))) or "")
                .. " (the auction house pays out an hour after a sale). Nothing to do until then.", "wait"
        end
    end
    if e.live == 0 then
        local _, _, nextIn, soldKeys = self:SalesMoney()
        if soldKeys[key] then
            return "Sold. The gold is in the mail" .. (nextIn and (", next arrival in about %d min"):format(max(1, floor(nextIn / 60 + 0.5))) or "")
                .. ". Collect it at a mailbox.", "do"
        end
        return "No longer listed: it sold or it expired. A mailbox visit tells which.", "do"
    end
    local hoursLeft = DURATION_HOURS - (GetServerTime() - (L.at or GetServerTime())) / 3600
    local expires = hoursLeft > 0 and (" Runs out in about %s."):format(hoursLeft >= 1 and (floor(hoursLeft + 0.5) .. "h") or (max(1, floor(hoursLeft * 60)) .. " min")) or ""
    local t, low = St.t[key], St.p[key]
    local fresh = t and GetServerTime() - t < 600
    if fresh and low and low < price then
        local gap = price - low
        local repost = Deals.round(low - cfg.undercut, cfg)
        local each = paid and (floor(repost * (1 - cfg.cut)) - paid) or nil
        if gap <= max(1, price * 0.03) then
            return ("Wait. Undercut by only %s each: the cheaper units sell first, then yours.%s%s"):format(short(gap), sells, expires), "wait"
        elseif each and each * e.count >= cfg.minProfit and GetMoney() < self:DepositTotal(key, true, e.count) then
            return ("Wait. Someone lists at %s. Posting again costs a fee of %s first and you have %s.%s")
                :format(short(low), short(self:DepositTotal(key, true, e.count)), short(GetMoney()), expires), "wait"
        elseif each and each * e.count >= cfg.minProfit then
            return ("Someone lists at %s. Cancel yours (the game's Auctions tab) and post again at %s: still %s. The posting fee is paid again.")
                :format(short(low), short(repost), signed(each * e.count)), "do"
        elseif each then
            return ("Wait. Someone lists at %s; going under that would leave %s, less than your minimum.%s If it runs out it comes back by mail.")
                :format(short(low), signed(each * e.count), expires), "wait"
        end
        return ("Someone lists at %s, under your %s.%s"):format(short(low), short(price), expires), "wait"
    end
    return ("Wait. No cheaper listing%s.%s%s"):format(fresh and " in the last radar read" or " seen (no recent radar read)", sells, expires), "wait"
end

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
    if ns.Journal then ns.Journal:Dropped(key, nil, "removed from tracking by you") end
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
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "PLAYER_MONEY" }) do
        f:RegisterEvent(e)
    end
    Seller.goldSeen = GetMoney()
    f:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "PLAYER_MONEY" then
            local now = GetMoney()
            local delta = now - (Seller.goldSeen or now)
            Seller.goldSeen = now
            if delta > 0 and mailOpen() then Seller:MailGold(delta); Seller:Refresh() end
        elseif event == "MERCHANT_SHOW" then
            -- Nothing is sold by itself: the panel opens and waits for your click.
            Seller:Refresh("open")
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
            local before = bagCount
            Seller:ScanBags()
            Seller:CheckSoldByHand(before)
            Seller:CheckPosted(); Seller:Refresh()
        elseif event == "UI_ERROR_MESSAGE" then
            Seller:OnError(a2 or a1)
        else
            Seller:Refresh()
        end
    end)
    -- Remind on login if there is unfinished business.
    C_Timer.After(8, function()
        local n = #Seller:Entries()
        if n > 0 then say(n .. " item(s) to sell. Open the AuctionMesh panel (auction house tab, or the addon list by the minimap) to see what to do.") end
    end)
end

return Seller
