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

-- What a vendor pays for one unit of a holding. A vendor deal's record carries
-- it; a flip's record carries the planned resale price, so the game is asked.
function Seller.VendorOf(key, f)
    if f and f.kind == "VENDOR" then return f.sell or 0 end
    local S = ns.Sniper
    return (S and S.vendorOf and S.vendorOf(key)) or 0
end

function Seller.ForgetUnits(key, n)
    local f = flips()[key]
    if not f then return end
    f.units = (f.units or 0) - n
    if f.units <= 0 then flips()[key] = nil; Seller.prices[key] = nil end
end

---------------------------------------------------------------- what to do with each item

-- Returns a list of { key, action, count, f } entries for the bag window.
-- THE BETTER WAY OUT for something bought under vendor price. A vendor pays
-- at once, with no cut and no fee. The auction house often pays more (Silk
-- Cloth: 1s50c at a vendor, about 1s88c after the cut on the auction house),
-- and then that is what is recommended. The auction house price is the live
-- one when it has been checked, otherwise the market price from the item's
-- last full listing (up to 6 hours old). It has to beat the vendor by 10% to
-- be worth the hour's wait for the gold.
-- Returns "AH" or "VENDOR", and what one unit brings on the auction house.
Seller.AH_EDGE = 1.10
function Seller:BestExit(key, f)
    local vendor = f.sell or 0
    local p = self.prices[key]
    local net
    -- on a realm where the posting fee does not come back, it comes off what the auction house pays
    local fee = 0
    if Deals.cfg.depositIsCost then
        local qty = max(min(bagCount[key] or 0, f.units or 0), 1)
        local ok, total = pcall(self.DepositTotal, self, key, not (p and p.commodity == false), qty)
        if ok and total then fee = math.ceil(total / qty) end
    end
    if p and p.at and GetTime() - p.at < HOLD_TTL then
        if p.hold then return "VENDOR" end -- checked: the auction house does not beat the vendor
        if p.price then net = floor(p.price * (1 - Deals.cfg.cut)) - fee end
    end
    if not net then
        local St = ns.Store
        local fair, ft = St and St.fp and St.fp[key], St and St.ft and St.ft[key]
        if fair and ft and GetServerTime() - ft <= 6 * 3600 then
            net = floor((fair - Deals.cfg.undercut) * (1 - Deals.cfg.cut)) - fee
        elseif St and St.Get then
            -- no full listing on record: the cheapest price in the radar's last read (at most 10 minutes old)
            local low, _, t = St:Get(key)
            if low and t and GetServerTime() - t <= 600 then net = floor((low - Deals.cfg.undercut) * (1 - Deals.cfg.cut)) - fee end
        end
    end
    if net and net >= vendor * self.AH_EDGE then return "AH", net end
    return "VENDOR", net
end

function Seller:Entries()
    local out, now = {}, GetTime()
    for key, f in pairs(flips()) do
        local units = f.units or 0
        local inBags = min(bagCount[key] or 0, units)
        local inMail = units - inBags
        if inBags > 0 then
            local action = f.kind == "VENDOR" and "VENDOR" or "AH"
            local p = self.prices[key]
            local vendorAlt
            if action == "VENDOR" then
                -- bought under vendor price, but worth more on the auction house: that is the recommendation
                if self:BestExit(key, f) == "AH" then action, vendorAlt = "AH", f.sell end
            elseif p and p.hold and now - p.at < HOLD_TTL then
                action = "HOLD"
            elseif not f.unknownCost then
                -- held as a flip, but a vendor pays more than it cost (some of it was
                -- bought under vendor price): the vendor is a second way out here too
                local v = Seller.VendorOf(key, f)
                if v > (f.cost or 0) then vendorAlt = v end
            end
            out[#out + 1] = { key = key, action = action, count = inBags, f = f, vendorAlt = vendorAlt }
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
            or ("Go to a mailbox: " .. n.MAIL .. " item(s) to collect."))
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
            -- "Sell all" leaves what is worth more on the auction house; the row's own Sell button still sells it
            local keep = f and f.kind == "VENDOR" and not onlyKey and self:BestExit(info.itemID, f) == "AH"
            -- a vendor deal; or, with the row's own Sell button only, a flip that a vendor pays more for than it cost
            local can = f and (f.kind == "VENDOR"
                or (onlyKey == info.itemID and not f.unknownCost and Seller.VendorOf(info.itemID, f) > (f.cost or 0)))
            if can and not keep and (not onlyKey or onlyKey == info.itemID)
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
                local unit = f and Seller.VendorOf(key, f) or 0
                earned = earned + unit * gone
                if f and not f.unknownCost then Seller.Realize((unit - (f.cost or 0)) * gone) end
                if ns.Journal then ns.Journal:Vendored(key, gone, unit) end
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
    if self.mailBusy or self.mailFull then return end
    self.mailBusy = true
    -- read what is there BEFORE anything is taken, so the figures are current
    -- even if the mailbox is closed before collecting has finished
    if (GetInboxNumItems() or 0) > 0 then self:ScanMail() end
    -- BAGS FULL. A mail that does not come out is tried again, and again: the
    -- same mail, unchanged, four times in a row means it cannot be taken. Then
    -- it stops (it used to go on for as long as the mailbox was open, saying
    -- "is now in your bags" each time, and what the mailbox and bags really
    -- held was never looked at afterwards).
    local function stuck(i, id, cnt, hasItem)
        local sig = table.concat({ i, tostring(id), tostring(cnt), tostring(hasItem), GetInboxNumItems() or 0 }, ":")
        local m = Seller.mailTry
        if m and m.sig == sig then
            m.n = m.n + 1
        else
            m = { sig = sig, n = 1 }
            Seller.mailTry = m
        end
        return m.n > 4, m.n == 1
    end
    local function step()
        if not mailOpen() then Seller.mailBusy = false; return end
        for i = GetInboxNumItems(), 1, -1 do
            local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
            local _, _, _, _, moneyAmt, cod, _, hasItem = GetInboxHeaderInfo(i)
            if (cod or 0) == 0 then
                if invoice == "buyer" and hasItem then
                    -- Say what is being taken, so an empty-looking mailbox is never a mystery.
                    local nm, id, _, cnt = GetInboxItem(i, 1)
                    local full, first = stuck(i, id, cnt, hasItem)
                    if full then
                        Seller.mailFull = true
                        say(("|cffff8040Your bags are full:|r %s and anything after it stay in the mailbox. Make room (post or sell something), then open the mailbox again."):format(tostring(nm or "an item")))
                        break
                    end
                    AutoLootMailItem(i)
                    if first then say(("|cff4d99ffCollecting from mailbox:|r %s x %s."):format(tostring(cnt or 1), tostring(nm or "item"))) end
                    C_Timer.After(0.4, step); return
                elseif invoice == "seller" and (moneyAmt or 0) > 0 then
                    TakeInboxMoney(i); C_Timer.After(0.4, step); return
                elseif not invoice and hasItem and (moneyAmt or 0) == 0 then
                    -- a returned (expired) auction of an item we are tracking
                    -- an auction of ours that came back (it ran out, or you cancelled it)
                    local nm, id, _, cnt = GetInboxItem(i, 1)
                    local f = id and flips()[id]
                    if f and (f.retPending or 0) > 0 and (bagCount[id] or 0) < (f.units or 0) then
                        AutoLootMailItem(i) -- (the hook on it takes the units off "still in the mailbox")
                        say(("|cff4d99ffCollected from mailbox:|r %s x %s (your auction, returned) is back in your bags. Post it again on the Bags tab."):format(tostring(cnt or 1), tostring(nm or "item")))
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
        Seller:Recover()
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
    if ns.Book then ns.Book:ObserveSold(key, unit, count) end
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
-- Sale gold still to come, as a list of { amount, secs = seconds from now },
-- soonest first (the same sources, in the same order of trust, as SalesMoney).
function Seller:PayOuts()
    local out = {}
    local S = ns.Sniper
    local pay = S and S.ownSoldPay
    if pay and #pay > 0 then
        local t = GetTime()
        for _, r in ipairs(pay) do
            if r.due > t then out[#out + 1] = { amount = r.amount, secs = r.due - t } end
        end
    else
        local s, now = AuctionMeshDB.sales, GetServerTime()
        for _, p in ipairs(s and s.pending or {}) do
            if p.at > now then out[#out + 1] = { amount = p.amount, secs = p.at - now } end
        end
    end
    table.sort(out, function(a, b) return a.secs < b.secs end)
    return out
end

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
    -- Items in mail that carries no invoice, no gold and no charge: that is how
    -- an auction of yours comes back (expired or cancelled). Something you
    -- bought arrives with a "buyer" invoice and is not counted here.
    local back = {}
    for i = 1, shown or 0 do
        local _, _, _, _, moneyAmt, cod, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem then
            local plain = (moneyAmt or 0) == 0 and (cod or 0) == 0 and not (GetInboxInvoiceInfo and GetInboxInvoiceInfo(i))
            for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local _, itemID, _, count = GetInboxItem(i, j)
                if itemID then
                    counts[itemID] = (counts[itemID] or 0) + (count or 1)
                    if plain then back[itemID] = (back[itemID] or 0) + (count or 1) end
                end
            end
        end
    end
    self.mailCount, self.mailReturned = counts, back
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

-- How many units of your listing of this item can have ended without a sale:
-- what is on record as listed, less what the auction house still shows as
-- running (an auction whose time has passed since that list was read is not
-- running any more) and less what it shows as sold and waiting to be paid.
-- With no list from this session, everything on record can have.
function Seller:EndedQty(key)
    local L = AuctionMeshDB.listed and AuctionMeshDB.listed[key]
    if not L then return 0 end
    local S = ns.Sniper
    if not (S and S.ownRead) then return L.qty or 0 end
    local live, t = 0, GetTime()
    for _, a in ipairs(S.ownIds and S.ownIds[key] or {}) do
        if not a.gone and (not a.ends or a.ends > t) then live = live + (a.qty or 0) end
    end
    return max(0, (L.qty or 0) - live - ((S.ownSoldQty and S.ownSoldQty[key]) or 0))
end

-- AN AUCTION OF YOURS CAME BACK UNSOLD: it ran out ("expired") or you
-- cancelled it ("cancelled"). The units go back among what you hold, with what
-- they cost you, so the Bags tab offers them for posting again. If you already
-- hold more of the item they are added to it. Returns the units moved.
function Seller:Returned(key, n, why)
    local L = AuctionMeshDB.listed and AuctionMeshDB.listed[key]
    if not L then return 0 end
    n = min(n or 0, L.qty or 0)
    if n <= 0 then return 0 end
    local now = GetServerTime()
    do  -- A cancel YOU sent with the Cancel button in the last hour: what comes
        -- back is that auction, whatever the game's confirmation looked like.
        -- (A real log: the confirmation carried another number than the
        -- auction's, the cancel was not recognised, and the units coming back
        -- were booked as an auction that ran out: Wool Cloth, sold 26 times
        -- out of 26, was then not flipped for 12 hours.)
        local cs = AuctionMeshDB.cancelSent
        if cs and cs[key] then
            if why ~= "cancelled" and now - cs[key] < 3600 then why = "cancelled" end
            cs[key] = nil
        end
    end
    local cancelled = why == "cancelled"
    local f = flips()[key]
    if f then
        local have = f.units or 0
        if L.cost and not f.unknownCost then f.cost = floor(((f.cost or 0) * have + L.cost * n) / (have + n) + 0.5) end
        f.units = have + n
    else
        f = { kind = "FLIP", units = n, cost = L.cost or 0, unknownCost = (L.cost == nil), sell = L.plan or L.price }
        flips()[key] = f
    end
    f.at, f.missingSince = now, nil
    f.proof = cancelled and "auction cancelled, returned by mail" or "auction expired, returned by mail"
    f.retPending = (f.retPending or 0) + n -- still to come out of the mailbox
    -- the posting fee of an auction that did not sell does not come back: a real loss
    local fee = 0
    if (L.fee or 0) > 0 then
        fee = floor(L.fee * n / max(1, L.qty) + 0.5)
        L.fee = L.fee - fee
    end
    if fee > 0 then
        Seller.Realize(-fee)
        if ns.Journal then ns.Journal:FeeLost(key, fee) end
    end
    if ns.Journal then
        if cancelled then ns.Journal:Cancelled(key, n) else ns.Journal:Expired(key, n) end
    end
    L.qty = L.qty - n
    if L.qty <= 0 then AuctionMeshDB.listed[key] = nil end
    -- an auction that ran out is a flip that did not sell; one you cancelled to post again is not
    if not cancelled and ns.Learn then ns.Learn:Outcome(key, false) end
    self.prices[key] = nil -- priced afresh before it is posted again
    ns.Log("RETURNED %s x%d (%s): back among your holdings at cost %s, posting fee lost %d", tostring(key), n, tostring(why), tostring(L.cost), fee)
    say(("%s %d x %s. %sIt is on the Bags tab: collect it at a mailbox, then press Post.")
        :format(cancelled and "|cffff8040Cancelled:|r" or "|cffff8040Expired unsold:|r", n, nameOf(key),
            fee > 0 and ("The posting fee of " .. money(fee) .. " is lost. ") or ""))
    self:Refresh()
    return n
end

-- A mail's item is being taken (by this addon or by you). If it is one of
-- your auctions coming back, it is matched here, so taking it by hand before
-- the addon got to it still puts it on the Bags tab.
function Seller:OnTakeItem(i)
    if (GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)) then return end
    local _, _, _, _, moneyAmt, cod, _, hasItem = GetInboxHeaderInfo(i)
    if not hasItem or (cod or 0) > 0 or (moneyAmt or 0) > 0 then return end
    local _, id, _, cnt = GetInboxItem(i, 1)
    if not id then return end
    cnt = cnt or 1
    local sig, t = id .. ":" .. cnt .. ":" .. i, GetTime()
    if self.lastTake == sig and t - (self.lastTakeAt or -100) < 2 then return end -- the same mail, clicked twice
    self.lastTake, self.lastTakeAt = sig, t
    local f = flips()[id]
    if not (f and (f.retPending or 0) > 0) and AuctionMeshDB.listed and AuctionMeshDB.listed[id] then
        self:Returned(id, min(cnt, self:EndedQty(id)), "expired")
        f = flips()[id]
    end
    if f and (f.retPending or 0) > 0 then
        f.retPending = f.retPending - cnt
        if f.retPending <= 0 then f.retPending = nil end
    end
end

---------------------------------------------------------------- cancelling an undercut auction

-- Your own running auctions of this item that someone is cheaper than,
-- dearest first. Empty when the auction house's list has not been read.
function Seller:Cancellable(key)
    local S, out = ns.Sniper, {}
    if not (S and S.ownRead and S.ownIds and S.ownIds[key]) then return out end
    local low, _, t = nil, nil, nil
    if ns.Store and ns.Store.Get then low, _, t = ns.Store:Get(key) end
    if not (low and t and GetServerTime() - t < 600) then return out end
    local now = GetTime()
    for _, a in ipairs(S.ownIds[key]) do
        if a.id and not a.gone and (not a.ends or a.ends > now) and (a.price or 0) > low then out[#out + 1] = a end
    end
    table.sort(out, function(x, y) return (x.price or 0) > (y.price or 0) end)
    return out
end

-- The Cancel button on an undercut auction. Two clicks on the same button: the
-- first says what it costs, the second cancels. Rows move when a deal appears,
-- and a cancel cannot be taken back, so one stray click must not do it.
-- Must run from a click (the game wants a real input for a cancel).
function Seller:CancelClick(key)
    if not ahOpen() then return end
    local c = self.cancelling
    if c then self:Note(c.key, "Cancelling: waiting for the auction house to confirm.", "cancel"); return end
    local a = self:Cancellable(key)[1]
    if not a then self:Note(key, "Nothing to cancel: none of your auctions of it is undercut right now.", "cancel"); return end
    local AH = C_AuctionHouse
    if AH.CanCancelAuction and AH.CanCancelAuction(a.id) == false then
        self:Note(key, "The game does not allow this auction to be cancelled.", "cancel")
        return
    end
    local arm = self.cancelArm
    if not (arm and arm.id == a.id and GetTime() - arm.at < 5) then
        self.cancelArm = { id = a.id, key = key, at = GetTime() }
        -- The radar reads back to back, so the auction house is locked nearly
        -- all the time: the second click would find it busy (a real log: four
        -- clicks for one cancel). Nothing else is sent for 3 seconds, so the
        -- next click goes straight through.
        self.quietUntil = math.max(self.quietUntil or 0, GetTime() + 3)
        local L = AuctionMeshDB.listed and AuctionMeshDB.listed[key]
        local fee = (L and (L.fee or 0) > 0) and floor(L.fee * min(1, a.qty / max(1, L.qty)) + 0.5) or 0
        self:Note(key, ("Click again to cancel %d at %s each.%s It comes back by mail; then post it again on the Bags tab.")
            :format(a.qty, Seller.short(a.price), fee > 0 and (" The posting fee of " .. Seller.short(fee) .. " is not returned.") or " The posting fee is not returned."), "cancel")
        C_Timer.After(5.1, function() if ns.UI then ns.UI:Dirty() end end)
        return
    end
    if not ns.Gate:ReadyForUser() then
        arm.at = GetTime() -- stays armed: the next click cancels
        self.quietUntil = GetTime() + 3
        self:Note(key, "The auction house is busy for a moment. Click again.", "cancel")
        return
    end
    self.cancelArm = nil
    ns.Gate:Use(("cancel auction %s: %dx %s @%d"):format(tostring(a.id), a.qty, tostring(key), a.price or 0))
    ns.Gate.ignoreErrorUntil = math.max(ns.Gate.ignoreErrorUntil or 0, GetTime() + 3) -- a refused cancel is not the server pushing back
    self.cancelling = { key = key, id = a.id, qty = a.qty, price = a.price, at = GetTime(), a = a }
    AuctionMeshDB.cancelSent = AuctionMeshDB.cancelSent or {}
    AuctionMeshDB.cancelSent[key] = GetServerTime() -- remembered: what the mail brings back is a cancelled auction, not one that ran out
    self.note = nil -- the row now says "Cancelling..."
    self.quietUntil = GetTime() + 2
    if not pcall(AH.CancelAuction, a.id) then
        self.cancelling = nil
        AuctionMeshDB.cancelSent[key] = nil
        self:Note(key, "The game refused the cancel.", "cancel")
    end
    self:Refresh()
end

-- The auction house reports an auction of yours removed (event AUCTION_CANCELED).
-- Two things seen in real logs decide how it is read:
--   * The game fires it for a SALE as well, right after its "sold" notice
--     (notice 4, the item's name, the auction's number).
--   * For a cancel the notice is 1 and the number is NOT the auction's (113
--     for auction 93521571), so the number cannot be used to recognise our
--     own cancel. It used to be, and the cancel then went unrecognised.
-- So: while a cancel of ours is waiting for its answer, this event is that
-- answer unless a "sold" notice came with it or its number is another of your
-- auctions.
function Seller:OnCancelled(auctionID)
    local c = self.cancelling
    local S = ns.Sniper
    local n = self.lastNotice
    local SOLD = (Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold) or 4
    local sale = n ~= nil and GetTime() - n.at < 0.5 and n.kind == SOLD
    local other = false
    if c and auctionID and auctionID ~= c.id and S and S.ownIds then
        for _, list in pairs(S.ownIds) do
            for _, a in ipairs(list) do if a.id == auctionID then other = true end end
        end
    end
    if not c or sale or other then
        -- a sale, or a cancel made in the game's own Auctions tab: read your auctions again; the mailbox does the rest
        if S then S.needOwned = true end
        return
    end
    self.cancelling = nil
    ns.Log("CANCEL confirmed for %s (the event's number was %s, the auction's %s)", tostring(c.key), tostring(auctionID), tostring(c.id))
    if S then
        c.a.gone = true -- until the auction house's list is read again
        local o = S.own and S.own[c.key]
        if o and o[c.price] then
            o[c.price] = o[c.price] - c.qty
            if o[c.price] <= 0 then o[c.price] = nil end
            if next(o) == nil then S.own[c.key] = nil end
        end
        S.needOwned = true
    end
    self:Returned(c.key, c.qty, "cancelled")
    self.note = nil
    self:Refresh()
end

-- ONE-TIME REPAIR (first login with 3.33.1). Up to 3.33.0 an auction
-- cancelled with the Cancel button could be booked as one that ran out
-- unsold, which stops flips of that item for 12 hours. If the ONLY "ran out"
-- on record is a recent one, it is that booking, and it is taken back. With
-- more than one on record nothing is touched: a block ends by itself.
-- Returns the item it corrected, or nil.
function Seller.RepairCancelRecord()
    local L = ns.Learn and ns.Learn.d
    if not L or (L.fail or 0) ~= 1 then return nil end
    for key, it in pairs(L.items or {}) do
        if (it.fail or 0) == 1 and (it.streak or 0) == 1 and it.last and GetServerTime() - it.last < 48 * 3600 then
            it.fail, it.streak = 0, 0
            L.fail, L.n, L.mine = 0, max(0, (L.n or 1) - 1), max(0, (L.mine or 1) - 1)
            for i = #(L.recent or {}), 1, -1 do
                if L.recent[i] == 0 then table.remove(L.recent, i); break end
            end
            for _, t in ipairs(ns.Journal and ns.Journal.list or {}) do
                if t.key == key and (t.expired or 0) > 0 then
                    t.expired, t.cancelled = t.expired - 1, (t.cancelled or 0) + 1
                    break
                end
            end
            say(("%s: a cancel had been recorded as an auction that ran out unsold. Corrected: it is flipped again."):format(nameOf(key)))
            ns.Log("REPAIR: the one 'expired' outcome on record (%s) was a cancel; taken back", tostring(key))
            return key
        end
    end
    return nil
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
    -- THE MAIL ITSELF IS THE EVIDENCE: an item you have listed, in a mail with
    -- no invoice. (This used to need the auction house's list of your auctions
    -- from the same session, every auction of the item to be gone, and nothing
    -- else of the item in your hands. After a night's sleep you log in and walk
    -- to the mailbox first, or you hold more of the same item, and the expired
    -- auction was left in the mailbox for you to sort out by hand.)
    do
        local returned = false
        for key in pairs(AuctionMeshDB.listed or {}) do
            local f = flips()[key]
            local back = ((self.mailReturned and self.mailReturned[key]) or 0) - ((f and f.retPending) or 0)
            local n = min(back, self:EndedQty(key))
            if n > 0 and self:Returned(key, n, "expired") > 0 then returned = true end
        end
        if returned then C_Timer.After(0.5, function() Seller:CollectMail() end) end
    end
    for key, f in pairs(flips()) do
        local inMail = self.mailCount[key] or 0
        local have = (bagCount[key] or 0) + inMail
        if inMail > 0 then f.mailVerified = now end
        if have >= (f.units or 0) then f.missingSince = nil end
        if (bagCount[key] or 0) >= (f.units or 0) then f.retPending = nil end -- all of it is in the bags
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

-- onlyPressed: only the item you pressed Post on (asked at once, ahead of
-- everything). Without it: the periodic re-pricing of what you hold, which
-- is upkeep and waits for the upkeep turn (Sniper:UpkeepTurn).
function Seller:NextToPrice(onlyPressed)
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
    if onlyPressed then return nil end
    for key, f in pairs(flips()) do
        -- Everything held is priced live: a flip so it can be posted, and what
        -- was bought under vendor price so the better of the two ways out is
        -- known (re-checked every 10 minutes while the vendor is the better one).
        if (f.kind == "FLIP" or f.kind == "VENDOR") and (bagCount[key] or 0) > 0 then
            local p = self.prices[key]
            -- A fresh price is only needed for posting, and posting is done on
            -- the Bags tab: there it is re-read every 45 seconds. On every
            -- other tab once in 10 minutes is enough, and the requests go to
            -- the radar. (It was every 45 seconds on every tab: with five
            -- items held, one request in six was a price check.) Pressing Post
            -- still asks for the price at once.
            local posting = ns.UI and ns.UI.tab == "SELL"
            local ttl = ((p and p.hold) or not posting) and HOLD_TTL or PRICE_REFRESH
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
    if self.cancelling and GetTime() - self.cancelling.at > 6 then
        local key = self.cancelling.key
        self.cancelling = nil
        if ns.Sniper then ns.Sniper.needOwned = true end
        self:Note(key, "The auction house did not confirm the cancel. Try again.", "cancel")
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
    if not f then return end
    if self.pending and self.pending.key == key then self.pending = nil end
    if self.note and self.note.key == key then self.note = nil end -- the price it was waiting for is here
    -- The posting fee comes back when the item sells, so the lowest acceptable
    -- price only has to cover what you paid plus the 5% cut.
    local feeEach = 0
    if Deals.cfg.depositIsCost then
        local qty = max(commodity and min(bagCount[key] or 0, f.units or 0) or 1, 1)
        feeEach = math.ceil(self:DepositTotal(key, commodity, qty) / qty)
    end
    -- LISTINGS UNDER VENDOR PRICE ARE NOT THE MARKET. Anyone can buy them and
    -- sell them to a vendor at once, so they are gone within seconds; they are
    -- exactly the deals this addon buys. Pricing against them is wrong twice:
    -- a post would undercut a pile that is about to vanish, and something you
    -- hold would be sent to a vendor because "the auction house pays no more".
    -- (A real Snapshot: Mageweave Cloth, market about 4s40c, a vendor pays
    -- 2s50c. Piles at 2s00c kept appearing; a price check that caught one said
    -- "sell to a vendor", and that stood for ten minutes: 25s at a vendor for
    -- ten cloth that the auction house would pay about 41s for.)
    -- So the rows at or under what a vendor deal is (vendor price less its
    -- margin) are left out before the price is worked out, unless they are
    -- the whole listing.
    local priced, skipped = rows, 0
    do
        local v = ns.Sniper and ns.Sniper.vendorOf and ns.Sniper.vendorOf(key)
        local bar = (v and v > 0) and floor(v / (1 + Deals.cfg.vendorMargin)) or nil
        if bar then
            local i = 1
            while rows[i] and rows[i].price <= bar do skipped = skipped + (rows[i].qty or 0); i = i + 1 end
            if i > 1 and rows[i] then
                priced = {}
                for j = i, #rows do priced[#priced + 1] = rows[j] end
            else
                skipped = 0
            end
        end
    end
    local price, why = Deals.postPrice(priced, f.cost or 0, f.sell or 0, nil, feeEach)
    ns.Log("PRICE %s: lowest=%s cost=%s -> %s (%s)%s", tostring(key), tostring(rows[1] and rows[1].price),
        tostring(f.cost), tostring(price), tostring(why),
        skipped > 0 and (" [%d unit(s) listed under vendor price left out: they are bought at once]"):format(skipped) or "")
    if price and f.kind == "VENDOR" and floor(price * (1 - Deals.cfg.cut)) - feeEach < (f.sell or 0) * self.AH_EDGE then
        -- bought under vendor price, and the auction house does not beat the vendor by enough: sell it to a vendor
        price, why = nil, "a vendor pays as much"
    end
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
-- what = nil for the Post button's notes, "cancel" for the Cancel button's
-- (both on the Bags tab): each row shows only its own.
function Seller:Note(key, text, what)
    local was = self.note
    self.note = { key = key, text = text, at = GetTime(), what = what }
    -- the same, for the snipe box and the top of the Bags tab: what a post is doing right now
    if what == nil then self.activity = { text = "Posting " .. nameOf(key) .. ": " .. text, at = GetTime() } end
    if self.quietNotes then -- the one key is being spammed: the row shows it, chat is left alone
    elseif not was or was.text ~= text or GetTime() - was.at > 4 then
        if ns.Print then ns.Print(nameOf(key) .. ": " .. text) end
    end
    if ns.UI then ns.UI:Dirty() end
end

function Seller:NoteFor(key, what)
    local n = self.note
    return (n and n.key == key and n.what == what and GetTime() - n.at < (what == "cancel" and 5 or 4)) and n.text or nil
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
        self.pressedAt = GetTime() -- (the price check that follows is booked as "posting", not upkeep)
        self:Note(key, (p and p.hold) and "Not posted: the market is below what you paid."
            or "Getting the live price first. Press Post again in a second.")
        return
    end
    if not ns.Gate:ReadyForUser() then
        -- The radar keeps the auction house locked nearly all the time. Nothing
        -- else is sent for 3 seconds now, so the next press finds it free and
        -- posts. (It was 1 second: pressing once a second, every press found
        -- it busy again, and the post looked stuck.)
        self.quietUntil = GetTime() + 3
        self:Note(key, "the auction house is busy for a moment. Press again: the next press posts.")
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
    -- If the game refuses this post it says so with an error message. That is
    -- an answer to your click, not the server pushing back: it must not stop
    -- the radar for 5 seconds or lengthen the pause between requests. (It did.)
    ns.Gate.ignoreErrorUntil = math.max(ns.Gate.ignoreErrorUntil or 0, GetTime() + 3)
    self.posting = { key = key, qty = qty, before = bagCount[key] or 0, price = p.price,
                     deposit = deposit, why = p.why, at = GetTime() }
    self.activity = { text = ("Posting %d x %s at %s each: sent, waiting for the auction house to confirm..."):format(qty, nameOf(key), Seller.short(p.price)), at = GetTime() }
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
            Seller.refusedAt = Seller.refusedAt or {}
            Seller.refusedAt[key] = GetTime()
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
    -- confirmed: the radar goes on at once (it waited out a fixed 2 seconds after every post)
    self.quietUntil = math.min(self.quietUntil or 0, GetTime() + 0.3)
    do  -- say so where you are looking, with what is left to post
        local left = 0
        for _, e in ipairs(self:Entries()) do if e.action == "AH" then left = left + 1 end end
        self.activity = { text = ("POSTED %d x %s at %s each. %s"):format(min(gone, q.qty), nameOf(q.key), Seller.short(q.price),
            left > 0 and (left .. " more item" .. (left == 1 and "" or "s") .. " to post: keep pressing.") or "Nothing left to post."), at = GetTime() }
    end
end

function Seller:OnError(msg)
    if self.cancelling and not self.posting then
        local key = self.cancelling.key
        ns.Log("CANCEL error for %s: %s", tostring(key), tostring(msg))
        self.cancelling = nil
        if AuctionMeshDB.cancelSent then AuctionMeshDB.cancelSent[key] = nil end
        self:Note(key, "Not cancelled. The game says: " .. tostring(msg), "cancel")
        return self:Refresh()
    end
    if not self.posting then return end
    ns.Log("POST error for %s: %s", tostring(self.posting.key), tostring(msg))
    self.refusedAt = self.refusedAt or {}
    self.refusedAt[self.posting.key] = GetTime() -- the one key leaves it alone for half a minute (see PostNext)
    local key = self.posting.key
    self.posting = nil
    self.quietUntil = GetTime() + 1
    self:Note(key, "Not posted. The game says: " .. tostring(msg))
    self:Refresh()
end

-- Post-next for the keybind: first AH item with a ready price.
-- quiet (the one key, which may be pressed many times a second): nothing is
-- written to chat for a press that posts nothing, and it returns true only
-- when there was something to post.
function Seller:PostNext(quiet)
    if self.posting then
        if quiet then return true end -- one is on its way: this press has nothing to add
        return self:Post(self.posting.key)
    end
    local entries = self:Entries()
    local target
    -- The one key is pressed again and again: an item the game has just
    -- refused to post is left alone for 30 seconds, or the same post would be
    -- tried over and over with the radar waiting each time. (The Post button
    -- tries whenever you press it.)
    local function ok(e)
        if e.action ~= "AH" then return false end
        local r = quiet and self.refusedAt and self.refusedAt[e.key]
        return not (r and GetTime() - r < 30)
    end
    for _, e in ipairs(entries) do
        local p = ok(e) and self.prices[e.key]
        if p and p.price and GetTime() - p.at < PRICE_TTL then target = e.key; break end
    end
    if not target then
        for _, e in ipairs(entries) do
            if ok(e) then target = e.key; break end -- no live price yet: asks for it and says so on the row
        end
    end
    if not target then
        if not quiet then say("Nothing to post.") end
        return false
    end
    self.quietNotes = quiet or nil
    self:Post(target)
    self.quietNotes = nil
    return true
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

-- UNITS AN OLDER VERSION LOST TRACK OF, PICKED UP AGAIN. Before 3.41 a
-- purchase of another kind (a flip, when the item was held from a vendor
-- deal) replaced the record of what you held; the journal then marked the
-- dropped units "lost". Once, at the update, those units are noted (trades of
-- the last 48 hours only). When your bags hold more of such an item than the
-- record says, that many go back on the Bags tab with what they cost. Never
-- more than was marked lost, and nothing that is lost after the update:
-- what you own apart from the addon's purchases is not taken for its own.
local LOST_WHY = { ["no longer in your bags, mailbox or auctions"] = true, ["not found in bags or mailbox"] = true }
function Seller:Recover()
    local rec = AuctionMeshDB.recover
    local J = ns.Journal
    if not rec or not (J and J.list) then return 0 end
    local now = GetServerTime()
    if now - (rec.at or 0) > 48 * 3600 then AuctionMeshDB.recover = nil; return 0 end
    if not rec.items then
        -- the first look after the update: what is marked lost, per item
        rec.items = {}
        for _, t in ipairs(J.list) do
            if (t.lost or 0) > 0 and LOST_WHY[t.lostWhy or ""] and rec.at - (t.at or 0) < 48 * 3600 then
                rec.items[t.key] = (rec.items[t.key] or 0) + t.lost
            end
        end
    end
    local total = 0
    for key, owed in pairs(rec.items) do
        local f = flips()[key]
        local n = min(owed, (bagCount[key] or 0) - (f and f.units or 0))
        if n > 0 then
            -- the trades they belong to are open again, oldest first
            local left, spent, kind, plan, known = n, 0, nil, nil, true
            for _, t in ipairs(J.list) do
                if left <= 0 then break end
                if t.key == key and (t.lost or 0) > 0 and LOST_WHY[t.lostWhy or ""] then
                    local m = min(left, t.lost)
                    t.lost = t.lost - m
                    if t.lost <= 0 then t.lost, t.lostWhy = 0, nil end
                    t.doneAt = nil
                    left = left - m
                    if t.cost then spent = spent + t.cost * m else known = false end
                    kind, plan = kind or t.kind, plan or t.plan
                end
            end
            local each = known and floor(spent / n + 0.5) or nil
            if f then
                if each and not f.unknownCost then f.cost = floor(((f.cost or 0) * (f.units or 0) + each * n) / ((f.units or 0) + n) + 0.5) end
                f.units = (f.units or 0) + n
            else
                flips()[key] = { kind = kind or "FLIP", sell = plan or 0, units = n, cost = each or 0, unknownCost = (each == nil),
                                 at = now, proof = "found in your bags again" }
            end
            rec.items[key] = owed - n
            if rec.items[key] <= 0 then rec.items[key] = nil end
            total = total + n
            self.prices[key] = nil
            ns.Log("RECOVER %s: %d unit(s) an older version dropped are in the bags: tracked again", tostring(key), n)
            say(("|cff33ff66%s: %d that the addon had lost track of are in your bags. They are back on the Bags tab.|r"):format(nameOf(key), n))
        end
    end
    if not next(rec.items) then AuctionMeshDB.recover = nil end
    if total > 0 then self:Refresh() end
    return total
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
    if f.kind == "VENDOR" and e.action ~= "AH" then
        return paid, f.sell or 0, f.sell or 0, paid and ((f.sell or 0) - paid), true
    end
    local p = self.prices[e.key]
    local live = p and p.price and true or false
    local sell = live and p.price or (f.sell or 0)
    if f.kind == "VENDOR" and not live then
        -- worth more on the auction house, live price not checked yet: the market price from its last full listing
        local _, net = self:BestExit(e.key, f)
        if net then return paid, floor(net / (1 - Deals.cfg.cut) + 0.5), net, paid and (net - paid), false end
    end
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

-- VENDOR NOW, OR WAIT AND LIST IT? For a holding that a vendor pays more for
-- than it cost you, both ways out as numbers, so the choice is yours:
--   vendor = profit on all of it at a vendor, now (no cut, no fee, no wait)
--   ah     = profit on all of it on the auction house after the cut: from the
--            live price when it has been checked (live = true), else from the
--            item's last full listing or the radar's last read. nil = no
--            price is known; held = the live check found the auction house
--            does not beat the vendor.
--   diff   = ah - vendor: what waiting and listing brings on top (or loses)
--   fee    = the posting fee it takes first; short = you do not have it now;
--            nextIn = seconds to your next sale gold, if any is on its way
--   rate   = measured sales an hour
function Seller:Choice(e)
    if e.action ~= "VENDOR" and e.action ~= "AH" then return nil end
    local f, key, S = e.f, e.key, ns.Sniper
    local paid = (not f.unknownCost) and f.cost or nil
    local v = Seller.VendorOf(key, f)
    if not paid or v <= paid then return nil end -- a vendor is no way out for this one
    local n = e.count
    local c = { count = n, vendor = (v - paid) * n }
    local p = self.prices[key]
    local fresh = p and p.at and GetTime() - p.at < HOLD_TTL
    c.live = (fresh and p.price) and true or false
    c.held = (fresh and p.hold) and true or false
    local net
    if f.kind == "VENDOR" or c.live or c.held then
        local _, est = self:BestExit(key, { sell = v, units = f.units })
        net = est
    else
        -- held as a flip, live price not checked yet: the price planned when it was bought (the row's own figure)
        net = floor((f.sell or 0) * (1 - Deals.cfg.cut))
    end
    if net then c.ah = (net - paid) * n; c.diff = c.ah - c.vendor end
    if S and S.depositInfo then
        local per, dmin = S.depositInfo(key, not (S.isItem and S.isItem[key]))
        if per and per ~= math.huge then c.fee = max(dmin or 0, math.ceil(per * n)) end
    end
    if c.fee and c.fee > GetMoney() then
        c.short = true
        local _, nextIn = self:Tied()
        c.nextIn = nextIn
    end
    local St = ns.Store
    local rate = St and St.Rate and St:Rate(key, 100) or nil
    c.rate = (rate and rate >= 1) and rate or nil
    return c
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
        local text = profit and ("Sell it to any vendor: %s, guaranteed."):format(signed(profit * e.count)) or "Sell it to any vendor."
        -- and what waiting and listing it would bring instead
        local c = self:Choice(e)
        if c and c.ah then
            if c.diff > 0 then
                text = text .. (" Or wait and list it: %s%s after the cut, %s more.%s The gold comes about an hour after it sells.%s"):format(
                    c.live and "" or "about ", signed(c.ah), short(c.diff),
                    c.fee and (" That takes a posting fee of %s first%s."):format(short(c.fee),
                        c.short and ((": you have %s%s"):format(short(GetMoney()), c.nextIn and (", sale gold arrives in about %d min"):format(max(1, floor(c.nextIn / 60 + 0.5))) or "")) or "") or "",
                    sells)
            else
                text = text .. (" Listing it instead would bring %s%s after the cut: %s less."):format(c.live and "" or "about ", signed(c.ah), short(-c.diff))
            end
        elseif c and c.held then
            text = text .. " The auction house pays less than the vendor right now."
        end
        return text, "do"
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
        if e.vendorAlt and paid then
            local _, _, net = self:Numbers(e)
            return ("Worth more on the auction house: about %s each after the cut, against %s at a vendor. %s Or sell it to a vendor now for %s: no wait, no fee.")
                :format(short(net or 0), short(e.vendorAlt), ahOpen() and "The live price is being checked; then press Post." or "Open the auction house and press Post.",
                    signed((e.vendorAlt - paid) * e.count)), "do"
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
            return ("Someone lists at %s. Press Cancel on its row (Bags tab), collect it at a mailbox and post again at %s: still %s. The posting fee is paid again.")
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
    if hooksecurefunc then
        if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) Seller:OnTakeItem(i) end) end
        if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(i) Seller:OnTakeItem(i) end) end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED",
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "PLAYER_MONEY" }) do
        f:RegisterEvent(e)
    end
    pcall(f.RegisterEvent, f, "AUCTION_CANCELED")
    pcall(f.RegisterEvent, f, "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
    pcall(f.RegisterEvent, f, "AUCTION_HOUSE_SHOW_NOTIFICATION")
    Seller.goldSeen = GetMoney()
    f:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "PLAYER_MONEY" then
            local now = GetMoney()
            local delta = now - (Seller.goldSeen or now)
            Seller.goldSeen = now
            if delta > 0 and mailOpen() then Seller:MailGold(delta); Seller:Refresh() end
        elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_NOTIFICATION" then
            Seller.lastNotice = { kind = a1, at = GetTime() } -- 4 = sold, 1 = removed: tells a sale from a cancel (see OnCancelled)
        elseif event == "AUCTION_CANCELED" then
            Seller:OnCancelled(a1)
        elseif event == "MERCHANT_SHOW" then
            -- Nothing is sold by itself: the panel opens and waits for your click.
            Seller:Refresh("open")
        elseif event == "MAIL_SHOW" then
            Seller.mailFull, Seller.mailTry = nil, nil
            Seller:Refresh("open"); Seller:CollectMail()
        elseif event == "MAIL_CLOSED" then
            Seller.mailFull, Seller.mailTry = nil, nil
            Seller:Refresh()
        elseif event == "MAIL_INBOX_UPDATE" then
            Seller:CollectMail()
        elseif event == "AUCTION_HOUSE_SHOW" then
            for k, p in pairs(Seller.prices) do if p.price then Seller.prices[k] = nil end end
            Seller:Recover()
            Seller:Refresh()
            if not Seller.ticker then Seller.ticker = C_Timer.NewTicker(0.3, function() Seller:Tick() end) end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if Seller.ticker then Seller.ticker:Cancel(); Seller.ticker = nil end
            Seller.pending, Seller.posting, Seller.cancelling, Seller.cancelArm = nil, nil, nil, nil
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
        Seller:ScanBags()
        Seller:Recover()
        local n = #Seller:Entries()
        if n > 0 then say(n .. " item(s) to sell. Open the AuctionMesh panel (auction house tab, or the addon list by the minimap) to see what to do.") end
    end)
end

return Seller
