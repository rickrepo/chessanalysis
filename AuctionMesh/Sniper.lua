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
local CHECK_AGAIN = 30            -- don't re-check the same candidate sooner
local WATCH_SIZE = 50             -- how many items are watched continuously

-- Staple low-level profession materials (what players levelling 1-40 and their
-- professions 1-150 burn through, per current WoW Forever gold guides: cloth,
-- ore, herbs, leather, then iron and silk). Always watched first.
local STAPLES = {
    2589, 2592, 4306, 2996, 2997,              -- Linen, Wool, Silk Cloth; Bolts of Linen / Woolen
    2770, 2771, 2772, 2840, 3576, 2841,        -- Copper, Tin, Iron Ore; Copper, Tin, Bronze Bar
    2835, 2836, 2838,                          -- Rough, Coarse, Heavy Stone
    2318, 2319, 4234, 783, 4232,               -- Light, Medium, Heavy Leather; Light, Medium Hide
    2447, 765, 2449, 785, 2450, 2453, 3820,    -- Peacebloom, Silverleaf, Earthroot, Mageroyal, Briarthorn, Bruiseweed, Stranglekelp
    2452, 3355, 3356, 3357,                    -- Swiftthistle, Wild Steelbloom, Kingsblood, Liferoot
    10940, 10938, 10939, 10978,                -- Strange Dust, Lesser / Greater Magic Essence, Small Glimmering Shard
    774, 818, 1210,                            -- Malachite, Tigerseye, Shadowgem
    2775, 2934,                                -- Silver Ore, Ruined Leather Scraps
    2672, 769, 6889, 12223, 5465, 2673, 3173, 2924, -- cooking meats: wolf, boar, egg, bat wing, spider leg, coyote, bear, crocolisk
}

-- Materials new in WoW Forever that guides report as in demand. Their item
-- numbers are new, so they are recognised by name once the price scan has seen them.
local HOT_NAMES = {
    ["Frilled Lichen"] = true, ["Cerulean Dye"] = true,       -- 100+ Tailoring recipes need the dye
    ["Pitchblende"] = true, ["Azerothium Bar"] = true,        -- new ore and its bar
    ["Commonplace Herb Seeds"] = true,
}
Sniper.HOT_NAMES = HOT_NAMES

-- Goods NPC vendors sell in unlimited supply (food, drink, thread, dyes, flux,
-- vials, spices...). Their auction price can never hold above the vendor's
-- price, so they are never flipped. (Buying them BELOW what a vendor pays is still fine.)
local VENDOR_SOLD = {}
for _, id in ipairs({
    117, 2287, 3770, 3771, 4599, 8952,           -- meats: Tough Jerky ... Roasted Quail
    4540, 4541, 4542, 4544, 4601, 8950,          -- breads
    2070, 414, 422, 1707, 3927, 8932,            -- cheeses
    4536, 4537, 4538, 4539, 4602, 8953,          -- fruit
    4604, 4605, 4606, 4607, 4608, 8948,          -- mushrooms
    787, 4592, 4593, 4594, 21552, 8957,          -- fish
    159, 1179, 1205, 1708, 1645, 8766,           -- drinks
    2320, 2321, 4291, 8343, 14341,               -- threads
    2324, 2604, 2605, 6260, 4340, 4341, 4342, 6261, 10290, -- bleach and dyes
    2880, 3466, 3371, 3372, 8925, 18256,         -- flux, vials
    2678, 2692, 3713, 159, 4289, 2665,           -- spices, salt
    4470, 4471, 6217, 5956, 2901, 7005, 6256, 6530, 4399, 4400, -- tools and parts
    2928, 2930, 3777, 5173, 8923, 8924,          -- rogue poison reagents
    17020, 17021, 17026, 17028, 17029, 17030, 17031, 17032, 17033, 17034, 17035, 17036, 17037, 17038, 5565, 16583, 21177, -- class reagents
}) do VENDOR_SOLD[id] = true end
Sniper.VENDOR_SOLD = VENDOR_SOLD
Sniper.STAPLES = STAPLES
local WATCH_MIN = 300             -- routine full look at a watched item (keeps its market price current)
local FOCUS_MIN = 30              -- with laser focus on: each focus item gets a full look this often
local TRIGGER_MIN = 20            -- never fully re-read the same item sooner than this on a trigger
local SEARCH_TIMEOUT = 3 -- default; the Tuner replaces it with a figure from the measured pace
local PROFESSION = { [0] = true, [3] = true, [5] = true, [7] = true, [8] = true } -- stackable goods only

Sniper.verified = {}   -- key -> deal (+ key, at, commodity)
Sniper.isItem = {}     -- key -> true for non-stackable items (never deal candidates)
Sniper.own = {}        -- key -> { [unitPrice] = qty } of your own active auctions (from the server)
Sniper.floor = {}      -- key -> { price, at }: the server refused to sell below this price
Sniper.book = {}       -- key -> { x = price level, cum = units at or below x, at } from the last reading
Sniper.bought = {}     -- key -> units we bought since the last reading (not counted as demand)
Sniper.checkedAt = {}  -- key -> GetTime() of our last live check
Sniper.vendor = {}     -- key -> vendor sell price (false = cannot be vendored)
Sniper.stats = { checks = 0, deals = 0, bought = 0, spent = 0, expected = 0 }

-- Every message goes to chat AND to the top of the window, so a click always gets a visible answer.
local function say(m)
    if ns.Print then ns.Print(m) end
    if ns.UI then ns.UI:Notice(m) end
end
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

-- Posting fee for a 12h listing, from the game's own calculation:
-- returns feePerUnit (may be a fraction), smallestFeePerPosting.
-- (math.huge, 0) = unknown. Asking for 1 unit and for 100 units shows both
-- the per-unit rate and any minimum the realm charges per posting.
local depCache = {}
function Sniper.ClearFees() depCache = {} end
function Sniper.depositInfo(key, commodity)
    local c = depCache[key]
    if c then return c[1], c[2] end
    local AH = C_AuctionHouse
    if commodity ~= false and AH and AH.CalculateCommodityDeposit then
        local ok1, d1 = pcall(AH.CalculateCommodityDeposit, key, 1, 1)
        local ok2, d100 = pcall(AH.CalculateCommodityDeposit, key, 1, 100)
        if ok1 and ok2 and d1 and d100 and d100 > 0 then
            depCache[key] = { d100 / 100, d1 }
            ns.Log("FEE %s: %d for 1 unit, %d for 100 units", tostring(key), d1, d100)
            return d100 / 100, d1
        end
    end
    local v = Sniper.vendorOf(key)
    if v == nil and Sniper.vendor[key] == nil then return math.huge, 0 end
    -- Guide (ForeverDB, from the client): 5% of the vendor price, minimum 1 copper.
    return (v or 0) * 0.05, 1
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
function Sniper:Search(key, src, waited)
    SORTS = SORTS or { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    -- The client silently refuses to send a search for an item whose details it
    -- has not loaded yet (seen in real logs: the request never leaves, and the
    -- queue then sat waiting for an answer). Ask for the details and move on;
    -- the item is retried a little later.
    if C_Item.GetItemInfo(key) == nil then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key) end
        self.checkedAt[key] = GetTime() - TRIGGER_MIN + 4 -- retry in ~4s
        local Se = ns.Seller
        if Se and Se.pending and Se.pending.key == key then Se.pending = nil end
        return false
    end
    ns.Gate:Use("search " .. tostring(key), "search")
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(key), SORTS, true)
    -- src: what asked for this check (scored by the Tuner when the answer is in)
    self.searching = { key = key, at = GetTime(), sent = ns.Gate.sentCount, src = src, waited = waited }
    self.checkedAt[key] = GetTime()
    self.stats.checks = self.stats.checks + 1
    ns.lastQuery = "sniper"
end

function Sniper:Evaluate(key, rows, commodity)
    table.sort(rows, function(a, b) return a.price < b.price end)
    do  -- the game sends the same results twice per search: judge them once
        local parts = { #rows }
        for i = 1, min(#rows, 8) do parts[#parts + 1] = rows[i].price .. "x" .. rows[i].qty end
        local sig, now = table.concat(parts, ","), GetTime()
        local last = self.lastEval
        if last and last.key == key and last.sig == sig and now - last.at < 2 then
            if self.searching and self.searching.key == key then self.searching = nil end
            return
        end
        self.lastEval = { key = key, sig = sig, at = now }
    end
    if ns.Seller then ns.Seller:OnResults(key, rows, commodity) end
    if not commodity then
        -- Non-stackable items are priced for selling only; they are not offered as deals.
        self.verified[key] = nil
        if self.searching and self.searching.key == key then self.searching = nil end
        return dirty()
    end
    local avg, n = Store.a[key], Store.an[key]
    self:Turnover(key, rows)
    local feePer, feeMin = self.depositInfo(key, commodity)
    local deal, wall, reason = Deals.evaluate(rows, {
        budget = self:Budget(), gold = GetMoney(), commodity = commodity,
        vendor = self.vendorOf(key),
        avg = (avg and n and n >= Deals.cfg.minSamples) and avg or nil,
        deposit = feePer, depositMin = feeMin,
        sold = (Store:Sold(key, GetServerTime(), 48 * 3600)),
        noFlip = VENDOR_SOLD[key],
        rate = (Store:Rate(key, 100)),
        trend = Store:Trend(key, GetServerTime(), 6),
        learn = ns.Learn and ns.Learn:Factor() or nil,
        blockedHours = ns.Learn and ns.Learn:Blocked(key) or nil,
    })
    if wall then Sync:ObserveFair(key, wall) end
    if self.buying and self.buying.key == key then
        -- never replace a deal while its purchase is in flight
    elseif deal then
        deal.at, deal.commodity, deal.key = GetTime(), commodity, key
        deal.rowsText = self.RowsText(rows)
        deal.rows = rows
        if not self.verified[key] then
            self.stats.deals = self.stats.deals + 1
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
        end
        self.dealSeen = self.dealSeen or {}
        if not self.dealSeen[key] then
            self.dealSeen[key] = GetTime()
            if ns.Scout then ns.Scout:Deal(key, deal) end
        end
        self.verified[key] = deal
        ns.Log("DEAL %s %s: buy %d for %d, sell %d each, profit %d, sells %s/h, eta %s min (rows: %s)", deal.kind, tostring(key),
            deal.units, deal.cost, deal.sell, deal.profit, tostring(deal.rate and floor(deal.rate)), tostring(deal.eta and floor(deal.eta)),
            self.RowsText(rows))
    else
        self.verified[key] = nil
        if #rows == 0 then reason = "none listed" end
        if ns.Scout then
            ns.Scout:NoDeal(key, reason)
            -- a deal we had on screen is gone without us buying it: how long did it last?
            local seen = self.dealSeen and self.dealSeen[key]
            if seen then ns.Scout:Gone(key, GetTime() - seen); self.dealSeen[key] = nil end
        end
        ns.Log("NO DEAL %s: %s (rows: %s)", tostring(key), tostring(reason), self.RowsText(rows))
        -- A real deal that is only too big for our purse: tell friends, one of them may afford it.
        if reason and (reason:find("more than you can spend", 1, true) or reason:find("more than you have", 1, true)) then
            Sync:Hint(key)
        end
    end
    do  -- score the check for whatever asked for it
        local sr = self.searching
        if ns.Tuner and sr and sr.key == key and sr.src then
            ns.Tuner:Checked(sr.src, deal ~= nil, deal and deal.profit or 0, sr.waited)
        end
    end
    self.last = { key = key, deal = deal ~= nil, reason = reason, at = GetTime() }
    self.reasons = self.reasons or {}
    self.reasons[key] = deal and "DEAL FOUND" or reason -- why this item was or was not a deal, by item
    if self.searching and self.searching.key == key then self.searching = nil end
    dirty()
end

-- THE RADAR. Called for every item of every category sweep (a handful of
-- requests covers every crafting material on the auction house). A full
-- single-item search, the expensive request, is only queued when the sweep
-- shows something worth it:
--   * lowest price at or below what a vendor pays, or
--   * lowest price 20% or more under the known market price, or
--   * lowest price fell 15% or more since the previous sweep.
-- The same sweep also measures volume: a drop in the listed quantity between
-- two sweeps means units were bought.
-- (class, subclass) of an item, for category focus
local function classSub(key)
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(key)
    return classID, subID
end
Sniper.classSub = classSub
Sniper.VENDOR_SOLD = VENDOR_SOLD

-- The focus items right now (nil = no limit) and the sentence that says so.
function Sniper:FocusSet()
    if not ns.Scout or not ns.Scout.d then return nil, {}, "" end
    return ns.Scout:Focus(self:Budget(), VENDOR_SOLD, classSub)
end
function Sniper:InFocus(key)
    local set = self:FocusSet()
    return set == nil or set[key] == true
end

function Sniper:OnSweep(key, price, qty)
    if not self.active or key <= 0 or self.isItem[key] then return end
    local now = GetTime()
    self.sweep = self.sweep or {}
    local prev = self.sweep[key]
    self.sweep[key] = { p = price, q = qty, at = now }
    if prev then
        local dt = now - prev.at
        if dt >= 10 and dt <= 900 then
            local gone = prev.q - qty - (self.bought[key] or 0)
            Store:AddTurnover(key, gone > 0 and gone or 0, dt)
        end
    end
    local ft = Store.ft[key]
    local market = (ft and GetServerTime() - ft <= 1800) and Store.fp[key] or nil
    if ns.Scout then ns.Scout:Read(key, price, market) end -- counted for every item, affordable or not
    if price > self:Budget() then return end
    local why
    local v = self.vendorOf(key)
    if v and price <= floor(v / (1 + Deals.cfg.vendorMargin)) then why = "at or under vendor price"
    elseif VENDOR_SOLD[key] or not Deals.cfg.flips then return
    elseif not self:InFocus(key) then return -- laser focus: flips only on the focus items
    elseif market and price <= market * 0.8 then why = "20% under market"
    elseif prev and price <= prev.p * 0.85 then why = "price just dropped"
    end
    if not why then return end
    self:AddTrigger(key, why, price, market)
end

-- Queues one full look at an item (from our sweep, a friend's sweep or a friend's hint).
function Sniper:AddTrigger(key, why, price, market)
    if not self.active or key <= 0 or self.isItem[key] or self.verified[key] or self:Since(key) < TRIGGER_MIN then return end
    self.triggers = self.triggers or {}
    if not self.triggers[key] then
        -- Score = how much there is to gain. Each confirmation costs one of our
        -- ~1.6 requests a second, so the most valuable look always goes first:
        -- vendor-price hits (guaranteed) ahead of everything, then the biggest gap.
        local score = 0
        if market and price and market > 0 then score = (market - price) / market end
        local src = "drop"
        if why and why:find("vendor", 1, true) then src = "vendor"
        elseif why and why:find("friend", 1, true) then src = "friend"
        elseif why and why:find("market", 1, true) then src = "market" end
        -- Learned: alerts of a kind that keeps turning out real go first.
        -- (0.5 + hit rate) is 1.0 for a kind with no record yet.
        if ns.Tuner then score = (score + 0.05) * (0.5 + ns.Tuner:HitRate(src)) end
        if src == "vendor" then score = score + 10 end
        if src == "friend" then score = score + 1 end
        self.trigInfo = self.trigInfo or {}
        self.trigInfo[key] = { src = src, at = GetTime() }
        self.triggers[key] = score
        self.triggers[#self.triggers + 1] = key
        ns.Log("TRIGGER %s: %s (lowest %s, market %s, score %.2f)", tostring(key), tostring(why), tostring(price), tostring(market), score)
    end
end

-- What will be checked next, without taking it (for the timer in the window).
function Sniper:PeekNext()
    if self.priority then return self.priority end
    if self.triggers and self.triggers[1] then return self.triggers[1] end
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and not self.isItem[c.key] and self:Since(c.key) > CHECK_AGAIN then return c.key end
    end
    local q = self.background
    if not q or #q == 0 then return nil end
    local i = q.i
    for _ = 1, #q do
        if i > #q then i = 1 end
        if not self.isItem[q[i]] and self:Since(q[i]) > (self.watchMin or WATCH_MIN) then return q[i], i end
        i = i + 1
    end
end

-- Trading volume. Between two readings of the same listing, units that
-- disappeared from the cheap end (at or below the 3rd price level) were bought
-- by someone. New cheap listings hide some sales, so this never overstates.
function Sniper:Turnover(key, rows)
    if #rows == 0 then return end
    local now = GetTime()
    local function cumAt(x)
        local c = 0
        for i = 1, #rows do
            if rows[i].price > x then break end
            c = c + rows[i].qty
        end
        return c
    end
    local prev = self.book[key]
    if prev then
        local dt = now - prev.at
        if dt < 20 then return end -- same reading (the game sends results twice)
        if dt <= 900 then
            local gone = prev.cum - cumAt(prev.x) - (self.bought[key] or 0)
            Store:AddTurnover(key, gone > 0 and gone or 0, dt)
        end
    end
    self.bought[key] = nil
    local x = rows[math.min(3, #rows)].price
    self.book[key] = { x = x, cum = cumAt(x), at = now }
end

function Sniper.RowsText(rows)
    local t = {}
    for i = 1, min(#rows, 6) do t[i] = rows[i].qty .. "@" .. rows[i].price end
    return table.concat(t, " ")
end

function Sniper:OnCommodityResults(itemID)
    local AH = C_AuctionHouse
    -- Judge only on the complete listing: if the server sent a partial page, ask for the rest.
    local s = self.searching
    if s and s.key == itemID and AH.HasFullCommoditySearchResults and not AH.HasFullCommoditySearchResults(itemID)
        and (s.more or 0) < 8 then
        s.needMore, s.at = "commodity", GetTime()
        return
    end
    local rows = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 then
            local q = (r.quantity or 0) - (r.numOwnerItems or 0)
            -- Your own (or your other characters') auctions can't be bought: never count them as a deal.
            if (r.containsOwnerItem or r.containsAccountItem) and (r.numOwnerItems or 0) == 0 then q = 0 end
            -- Your own auctions, as listed by the server's "my auctions" query.
            local mine = self.own[itemID] and self.own[itemID][r.unitPrice]
            if mine and (r.numOwnerItems or 0) == 0 then q = q - mine end
            -- The server itself quoted a higher price than this row: it is not buyable by you.
            local fl = self.floor[itemID]
            if fl and GetTime() - fl.at < 1800 and r.unitPrice < fl.price then q = 0 end
            if q > 0 then rows[#rows + 1] = { price = r.unitPrice, qty = q } end
        end
    end
    self:Evaluate(itemID, rows, true)
end

function Sniper:OnItemResults(itemKey)
    if not itemKey or (itemKey.battlePetSpeciesID or 0) > 0 then return end
    local AH = C_AuctionHouse
    local s = self.searching
    if s and s.key == itemKey.itemID and AH.HasFullItemSearchResults and not AH.HasFullItemSearchResults(itemKey)
        and (s.more or 0) < 8 then
        s.needMore, s.itemKey, s.at = "item", itemKey, GetTime()
        return
    end
    local rows = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        -- buyoutAmount is the price of ONE item; quantity is how many identical
        -- auctions are grouped in this row. (Dividing one by the other was a bug
        -- that made 3s45c items look like 12c items.)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem and not r.containsAccountItem then
            local q = (r.quantity and r.quantity > 0) and r.quantity or 1
            rows[#rows + 1] = { price = r.buyoutAmount, qty = q }
        end
    end
    self.isItem[itemKey.itemID] = true
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
    -- Items you are waiting to post come before everything else.
    local Se = ns.Seller
    local want = Se and Se.NextToPrice and Se:NextToPrice()
    if want then Se.pending = { key = want, at = GetTime() }; return want end
    -- Radar hits: the sweep saw a price worth a full look.
    local tr = self.triggers
    while tr and #tr > 0 do
        local bi = 1
        for i = 2, #tr do if (tr[tr[i]] or 0) > (tr[tr[bi]] or 0) then bi = i end end
        local k = table.remove(tr, bi)
        tr[k] = nil
        local info = self.trigInfo and self.trigInfo[k]
        if self.trigInfo then self.trigInfo[k] = nil end
        if not self.verified[k] and self:Since(k) >= TRIGGER_MIN then
            return k, info and info.src or "drop", info and (GetTime() - info.at) or 0
        end
    end
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and not self.isItem[c.key] and self:Since(c.key) > CHECK_AGAIN then return c.key, "list" end
    end
    -- Routine: each watched item gets a full look every few minutes, which keeps
    -- its market price and volume current. Everything faster comes from the radar.
    local q = self.background
    if not q or #q == 0 then return nil end
    for _ = 1, #q do
        if q.i > #q then q.i = 1; q.rounds = (q.rounds or 0) + 1 end
        local k = q[q.i]
        q.i = q.i + 1
        if not self.isItem[k] and self:Since(k) > (self.watchMin or WATCH_MIN) then return k, "routine" end
    end
    return nil
end

-- The watch list: the WATCH_SIZE most-listed materials you can afford. The
-- busiest markets get the most new listings, so that is where mistakes appear.
function Sniper:RebuildBackground()
    local budget, now = self:Budget(), GetServerTime()
    do  -- LASER FOCUS: only the focus items, each fully checked every FOCUS_MIN seconds
        local set, flist = self:FocusSet()
        if set and Deals.cfg.flips then
            local list = {}
            for _, key in ipairs(flist) do
                local p = Store.p[key]
                if not self.isItem[key] and (not p or p <= budget) then list[#list + 1] = key end
            end
            if #list > 0 then
                list.i, list.staples, list.focus = 1, #list, true
                self.background, self.watchMin = list, FOCUS_MIN
                return
            end
        end
        self.watchMin = WATCH_MIN
    end
    local scope = ns.Swarm and ns.Swarm.ScopeClasses and ns.Swarm:ScopeClasses() or PROFESSION
    local list, seen = {}, {}
    -- Staples first. Ones whose known lowest price is above your gold are skipped.
    for _, key in ipairs(STAPLES) do
        local p = Store.p[key]
        if not self.isItem[key] and (not p or p <= budget) then list[#list + 1] = key; seen[key] = true end
    end
    -- New Forever materials, found by name among what the scan has seen.
    for key in pairs(Store.t) do
        if key > 0 and not seen[key] and not self.isItem[key] and Store.p[key] <= budget then
            local name = C_Item.GetItemInfo(key)
            if name and HOT_NAMES[name] then list[#list + 1] = key; seen[key] = true end
        end
    end
    list.staples = #list
    -- Then the most-listed other materials you can afford.
    local rest = {}
    for key, t in pairs(Store.t) do
        if key > 0 and not seen[key] and Store.p[key] <= budget and now - t <= 2 * 3600 and not self.isItem[key]
            and not VENDOR_SOLD[key] and scope[classOf(key) or -1] then
            rest[#rest + 1] = key
        end
    end
    table.sort(rest, function(a, b) return Store.q[a] > Store.q[b] end)
    for i = 1, #rest do
        if #list >= WATCH_SIZE then break end
        list[#list + 1] = rest[i]
    end
    list.i = 1
    self.background = list
end

function Sniper:Pending()
    local n, now = 0, GetTime()
    for _, c in ipairs(self.candidates or {}) do
        if not self.verified[c.key] and not self.isItem[c.key] and self:Since(c.key) > CHECK_AGAIN then n = n + 1 end
    end
    return n
end

function Sniper:HasWork()
    if self.priority ~= nil or (self.triggers and #self.triggers > 0) or self:Pending() > 0 then return true end
    local q = self.background
    if q then
        for i = 1, #q do
            if not self.isItem[q[i]] and self:Since(q[i]) > (self.watchMin or WATCH_MIN) then return true end
        end
    end
    return false
end

function Sniper:Busy() return self.searching ~= nil or self.buying ~= nil or self.queued ~= nil end

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
    local sr = self.searching
    if sr then
        -- A request the client never transmitted: free the queue after 0.4s, not 3.
        local unsent = ns.Gate.sawSent and sr.sent == ns.Gate.sentCount and now - sr.at > 0.4 and not sr.needMore
        if unsent then ns.Log("SEARCH %s was not transmitted by the client; skipped", tostring(sr.key)) end
        local timeout = ns.Tuner and ns.Tuner:Timeout() or SEARCH_TIMEOUT
        if unsent or now - sr.at > timeout then
            if ns.Tuner then ns.Tuner:Wasted(unsent and "unsent" or "timeout") end
            local Se = ns.Seller
            if Se and Se.pending and Se.pending.key == sr.key then Se.pending = nil end
            self.searching = nil
        end
    end
    local qd = self.queued
    if qd then
        if now - qd.at > 5 then
            self.queued = nil
            say("The auction house did not answer in time; press Buy again.")
        elseif ns.Gate:ReadyForUser() then
            self.queued = nil
            ns.deferredBuyAt = now
            self:Buy(qd.key)
        end
        return dirty()
    end
    -- The radar finds new deals; this pass over the whole price table only has
    -- to expire old ones and catch what the radar could not see, so it runs rarely.
    if now - (self.lastScreen or 0) > 15 then self:Screen(); self.lastScreen = now end
    -- Re-pick the watch list every 5 minutes (or right away while it is still empty).
    local bg = self.background
    if now - (self.lastBg or 0) > ((bg and #bg > 0) and 300 or 5) then self:RebuildBackground(); self.lastBg = now end
    local s = self.searching
    if s and s.needMore and ns.Gate:Ready() then
        local kind = s.needMore
        s.needMore, s.more, s.at = nil, (s.more or 0) + 1, now
        ns.Gate:Use(("more results for %s (page %d)"):format(tostring(s.key), s.more + 1), "more")
        if kind == "commodity" then C_AuctionHouse.RequestMoreCommoditySearchResults(s.key)
        else C_AuctionHouse.RequestMoreItemSearchResults(s.itemKey) end
        return
    end
    if ns.Scout then
        -- time the engine is actually working (auction house and panel open), for the daily report
        if self.tickAt and not ns.Gate:UserBusy() and AuctionHouseFrame and AuctionHouseFrame:IsShown() then ns.Scout:Online(now - self.tickAt) end
        self.tickAt = now
    end
    if self:Busy() or not ns.Gate:Ready() then return end
    if ns.Seller and ns.Seller:Busy() then return end
    if self.needOwned and C_AuctionHouse.QueryOwnedAuctions then
        self.needOwned = false
        ns.Gate:Use("list my own auctions")
        C_AuctionHouse.QueryOwnedAuctions({})
        return
    end
    local S = ns.Swarm
    if S and S.active and S.current and S.current.phase == "query" then return end
    if not self.priority and S and S.active and not S.idle and ns.lastQuery == "sniper" then return end
    -- an item whose details aren't loaded is skipped at no cost; try the next one
    if ns.Tuner then ns.Tuner:Balance(self.triggers and #self.triggers or 0) end
    for _ = 1, 3 do
        local key, src, waited = self:NextCheck()
        if not key then return end
        if self:Search(key, src, waited) ~= false then return end
    end
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
    local cands = Deals.candidates(Store, self:Budget(), GetServerTime(), self.vendorOf, nil, 40)
    for i = #cands, 1, -1 do
        if cands[i].kind == "FLIP" and (VENDOR_SOLD[cands[i].key] or not self:InFocus(cands[i].key)) then table.remove(cands, i) end
    end
    self.candidates = cands
    dirty()
end

---------------------------------------------------------------- buying

-- rows: the listing a deal was built on. If skipping the cheapest j rows makes
-- `units` cost exactly `total`, returns the price of the first buyable row.
function Sniper.PhantomFloor(rows, units, total)
    if not rows then return nil end
    for j = 1, #rows - 1 do
        local need, cost = units, 0
        for i = j + 1, #rows do
            local n = min(need, rows[i].qty)
            cost, need = cost + n * rows[i].price, need - n
            if need == 0 then break end
        end
        if need == 0 and cost == total then return rows[j + 1].price end
    end
end

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
    say(("|cff33ff66Bought:|r %d x %s for %s. It is in your mailbox; opening a mailbox moves it to your bags.")
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
    if not ns.Gate:ReadyForUser() then
        -- The server is answering another request. Don't make you click again:
        -- hold the click and send it the moment the server is free.
        if deal.commodity and not self.noDefer then
            self.queued = { key = key, at = GetTime() }
            if ns.UI then ns.UI:Notice("Buying as soon as the auction house answers...", true) end
            return dirty()
        end
        say("The Auction House is busy, click again in a second.")
        return
    end
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
        ns.Log("QUOTE MISMATCH %s: wanted %d units; deal was built at %s", tostring(b.key), b.units, tostring(b.deal.rowsText))
        -- The server's quote is the truth. Remember it: listings below this price
        -- are not buyable by you (your own or your other characters' auctions, or already gone).
        -- If the quote is exactly what the units would cost with the cheapest
        -- rows skipped, those rows are not buyable by you; otherwise the listing just changed.
        local phantom = Sniper.PhantomFloor(b.deal.rows, b.units, total)
        if phantom then self.floor[b.key] = { price = phantom, at = GetTime() } end
        ns.Log("QUOTE says real total %d; phantom floor %s", total, tostring(phantom))
        ns.Gate.ignoreErrorUntil = GetTime() + 2 -- our own cancel is not a server problem
        -- Cancel a moment later: cancelling inside the quote event makes the game show "Internal Auction Error".
        C_Timer.After(0.4, function() if not Sniper.buying then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end end)
        say(("|cffff8040Nothing bought, nothing spent.|r The server's real price is %s for %d (listing showed %s). %s")
            :format(money(total), b.units, money(b.deal.cost),
                phantom and "The cheaper listings can't be bought by you (your own auctions?), so this deal is removed."
                or "The listing changed; re-checking."))
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
        if ns.Scout then ns.Scout:Bought(b.key, b.units, spent) end
        if self.dealSeen then self.dealSeen[b.key] = nil end
        self.bought[b.key] = (self.bought[b.key] or 0) + b.units
        if b.item then
            b.deal.units, b.deal.cost = b.deal.units - b.units, b.deal.cost - (b.total or 0)
            if #b.deal.buys > 0 then self.buying = nil; return dirty() end -- more listings in this deal
        end
    else
        ns.Log("PURCHASE FAILED %s: %s", tostring(b.key), tostring(why))
        if ns.Scout then ns.Scout:Fail(b.key, why) end
        if self.dealSeen then self.dealSeen[b.key] = nil end
        say(("|cffff4040Purchase NOT completed:|r %s (%s). Nothing was recorded."):format(nameOf(b.key), why or "refused"))
    end
    self.verified[b.key] = nil
    self.priority = b.key -- re-check: there may be more
    self.buying = nil
    dirty()
end

-- Your own active auctions, straight from the server. Used so your own
-- listings are never mistaken for deals.
function Sniper:ReadOwned()
    local AH, own, n = C_AuctionHouse, {}, 0
    for i = 1, AH.GetNumOwnedAuctions and AH.GetNumOwnedAuctions() or 0 do
        local a = AH.GetOwnedAuctionInfo(i)
        local sold = a and Enum.AuctionStatus and a.status == Enum.AuctionStatus.Sold
        if a and a.itemKey and a.buyoutAmount and not sold then
            local id = a.itemKey.itemID
            own[id] = own[id] or {}
            own[id][a.buyoutAmount] = (own[id][a.buyoutAmount] or 0) + (a.quantity or 1)
            n = n + 1
        end
    end
    self.own, self.ownRead = own, true
    ns.Log("OWNED %d active auctions read", n)
    -- Deals built before we knew about them are re-checked.
    for k in pairs(self.verified) do if own[k] then self.verified[k] = nil; self.checkedAt[k] = nil end end
    dirty()
end

---------------------------------------------------------------- lifecycle

function Sniper:Start()
    self.active = true
    self.checkedAt = {} -- new AH visit: everything may have changed
    self.ownRead = false
    self.sweep, self.triggers = {}, {}
    depCache = {}       -- fees are asked again each visit
    self.needOwned = true
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
        "AUCTION_HOUSE_PURCHASE_COMPLETED", "UI_ERROR_MESSAGE", "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED" }) do
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
        elseif event == "OWNED_AUCTIONS_UPDATED" then Sniper:ReadOwned()
        elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then Sniper.needOwned = true
        elseif event == "AUCTION_HOUSE_SHOW" then if auto() then Sniper:Start() end
        elseif event == "AUCTION_HOUSE_CLOSED" then Sniper:Stop()
        end
    end)
end

return Sniper
