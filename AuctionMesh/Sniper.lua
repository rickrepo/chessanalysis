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

local Store, Book, Deals = ns.Store, ns.Book, ns.Deals
local Sniper = {}
ns.Sniper = Sniper

local floor, min = math.floor, math.min
local VERIFIED_TTL = 45           -- a verified deal is trusted this long, then re-checked
local MISS_COOL = 4               -- after a miss, units at that price are ignored this long (the listing lags behind sales)
local HOLD = 6                    -- seconds the radar stays silent when a deal appears, so your click is never queued behind it
Sniper.hold = HOLD
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
local FOCUS_MIN = 60              -- with laser focus on: each focus item gets a full look this often (settings code: every=)
-- It was 30. A real day's figures: 2859 item checks against 2054 radar reads.
-- Twelve focus items re-read every 30 seconds took more requests than the
-- radar, which then came round every 1.3 seconds instead of every 0.65.
function Sniper.FocusEvery()
    local v = AuctionMeshDB and AuctionMeshDB.cfg and AuctionMeshDB.cfg.focusEvery
    return math.max(20, math.min(300, v or FOCUS_MIN))
end
local TRIGGER_MIN = 20            -- never fully re-read the same item sooner than this on a trigger
local JUDGED_TTL = 300            -- a listing judged "no deal" is not checked again this long while the radar shows nothing new on it
local FOCUS_KEEP = 300            -- a listing the radar saw no change in is still re-read at this age
local ARMED_KEEP = 780            -- while armed: only a listing about to become too old for a flip straight from the radar
local LADDER_MAX = 900            -- a listing older than this is never used for a flip straight from the radar
local LADDER_ROWS = 20            -- rows of a listing that are remembered for it
-- UPKEEP BUDGET: of every N+1 requests, N are radar reads (see Sniper:UpkeepTurn)
-- (bagsNew: on the Sell tab while selling still has something to read: a
-- price for what you want to post, the listing of an undercut auction. 0:
-- every request goes to that until it is all in.)
Sniper.upkeep = { every = 8, bags = 3, bagsNew = 0 }
local ALERT_SRC = { vendor = true, market = true, drop = true }
local SEARCH_TIMEOUT = 3 -- default; the Tuner replaces it with a figure from the measured pace
local PROFESSION = { [0] = true, [3] = true, [5] = true, [7] = true, [8] = true } -- stackable goods only

Sniper.verified = {}   -- key -> deal (+ key, at, commodity)
Sniper.isItem = {}     -- key -> true for non-stackable items (never deal candidates)
Sniper.own = {}        -- key -> { [unitPrice] = qty } of your own active auctions (from the server)
Sniper.ownIds = {}     -- key -> list of those auctions one by one: { id, qty, price, ends }
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
-- money as plain text (42g 58s 88c) for messages shown on the panel and on screen
local function plain(c) return ns.Seller and ns.Seller.short and ns.Seller.short(c) or tostring(c) end
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
function Sniper:Search(key, src, waited, from)
    SORTS = SORTS or { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    -- The client silently refuses to send a search for an item whose details it
    -- has not loaded yet (seen in real logs: the request never leaves, and the
    -- queue then sat waiting for an answer). Ask for the details and move on;
    -- the item is retried a little later.
    if C_Item.GetItemInfo(key) == nil then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key) end
        self.checkedAt[key] = GetTime() - TRIGGER_MIN + 4 -- retry in ~4s
        local Se = ns.Seller
        if Se and Se.pending and Se.pending.key == key then
            Se.pending = nil
            if Se.pricedAt then Se.pricedAt[key] = nil end -- not sent: do not make it wait 20s for another try
        end
        return false
    end
    -- booked by the throttle watch: an alert's check, a re-check of a deal, or upkeep
    local purpose = ALERT_SRC[src or ""] and "alert" or ((src == nil or src == "recheck") and "buy") or (src == "price" and ns.Seller and ns.Seller.pressedAt and GetTime() - ns.Seller.pressedAt < 3 and "sell") or "upkeep"
    ns.Gate:Use(("search %s (%s)"):format(tostring(key), src or "re-check"), "search", purpose)
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(key), SORTS, true)
    -- src: what asked for this check (scored by the Tuner when the answer is in)
    self.searching = { key = key, at = GetTime(), sent = ns.Gate.sentCount, src = src, waited = waited, from = from }
    self.checkedAt[key] = GetTime()
    self.stats.checks = self.stats.checks + 1
    ns.lastQuery = "sniper"
end

-- A deal has just been put on the panel: what the inputs are doing goes to
-- the log (after the redraw, so the bindings are the ones in force), and the
-- input count is kept so that, if it leaves unbought, the log can say how
-- many inputs arrived while it was up.
function Sniper:TraceInputs(key)
    local U = ns.UI
    if not (U and U.InputTrace) then return end
    self.inputsAt = self.inputsAt or {}
    self.inputsAt[key] = U.inputCount or 0
    ns.Log("INPUTS as the deal appeared (%s): %s", tostring(key), U.InputTrace())
end

function Sniper:TraceGone(key)
    if not (ns.UI and ns.UI.InputTrace) then return end
    local at = self.inputsAt and self.inputsAt[key]
    ns.Log("INPUTS for the deal that went (%s): %s", tostring(key), ns.UI.InputTrace(at or 0))
    if self.inputsAt then self.inputsAt[key] = nil end
end

-- THE RADAR ITSELF SHOWS THAT A DEAL IS GONE. A deal used to stay on the panel
-- until its own re-check: 8 seconds at the earliest, 10 to 21 in a real log,
-- and then one request (0.75s with no radar read) to learn what the radar had
-- been showing all along. Meanwhile it was the target of your inputs: a press
-- on it cost a price request and a miss, with a live deal waiting behind it.
-- Now: a radar read that was SENT after the deal was read, and shows the
-- item's lowest price too high for the deal's units to cost what the deal
-- says, takes it off at once. No request is spent. (Only the price going up
-- counts: the listing can lag behind sales and show units that are gone, never
-- the other way round.)
function Sniper:RadarGone(key, d, price)
    local now = GetTime()
    self.verified[key] = nil
    if self.react and self.react.key == key then self.react = nil end
    if self.priority == key then self.priority = nil end -- nothing left to re-check
    ns.Log("GONE %s by the radar: the cheapest is now %d each; the deal was %d for %d. Off the panel, no re-check.", tostring(key), price, d.cost, d.units)
    local seen = self.dealSeen and self.dealSeen[key]
    if not seen then dirty(); return end
    self.dealSeen[key] = nil
    if ns.Scout then ns.Scout:Gone(key, now - seen) end
    local hold = ns.Gate.holdUntil
    self:Result("gone", key, ("GONE  %s: someone else bought it, %d seconds after it appeared."):format(nameOf(key), floor(now - seen + 0.5)), now - seen)
    -- another deal is still up (it may have appeared in this same read): the radar's hold for it stands
    if hold and next(self.verified) then ns.Gate.holdUntil = hold end
    self:TraceGone(key)
end

-- PER-ITEM SETTINGS (from an imported settings code). An item can have its own
-- smallest profit, and an item can be ignored altogether.
local itemCfg = {}
function Sniper:CfgFor(key)
    local im = AuctionMeshDB.cfg.itemMin
    local v = im and im[key]
    if not v then return Deals.cfg end
    local c = itemCfg[key]
    if not c then c = setmetatable({}, { __index = Deals.cfg }); itemCfg[key] = c end
    c.minProfit = v
    return c
end
function Sniper:Ignored(key)
    local ig = AuctionMeshDB.cfg.ignore
    return (ig and ig[key]) and true or false
end

-- Everything the deal rules need to know about one item, apart from its listing.
function Sniper:DealOptions(key, commodity)
    local avg, n = Store.a[key], Store.an[key]
    local feePer, feeMin = self.depositInfo(key, commodity)
    -- at risk: auctions that have not sold. coming: sold, gold on its way (certain).
    local atRisk, coming = 0, 0
    if ns.Seller and ns.Seller.Tied then
        local _, _, listed, onway, waiting = ns.Seller:Tied()
        atRisk, coming = listed or 0, (onway or 0) + (waiting or 0)
    end
    return {
        budget = self:Budget(), gold = GetMoney(), commodity = commodity,
        tied = atRisk, coming = coming,
        vendor = self.vendorOf(key),
        avg = (avg and n and n >= Deals.cfg.minSamples) and avg or nil,
        deposit = feePer, depositMin = feeMin,
        sold = (Store:Sold(key, GetServerTime(), 48 * 3600)),
        noFlip = VENDOR_SOLD[key],
        rate = (Store:Rate(key, 300)), -- 5 minutes of watching before a selling speed is believed
        trend = Store:Trend(key, GetServerTime(), 6),
        learn = ns.Learn and ns.Learn:Factor() or nil,
        blockedHours = ns.Learn and ns.Learn:Blocked(key) or nil,
    }
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
    if commodity and #rows > 0 then
        -- the listing as last read in full (first rows): what a flip straight from the radar is judged against
        local keep = {}
        for i = 1, min(LADDER_ROWS, #rows) do keep[i] = { price = rows[i].price, qty = rows[i].qty } end
        self.lastRows = self.lastRows or {}
        -- p0, q0: what the radar showed for the item when this listing was
        -- read. gone: units the radar has seen leave the item since.
        -- broken: the radar did not watch the item without a gap since.
        local own, now = self.ownSweep and self.ownSweep[key], GetTime()
        local seen = own and now - own.at <= 10
        self.lastRows[key] = { rows = keep, at = now, gone = 0, p0 = seen and own.p or nil, q0 = seen and own.q or nil, broken = not seen or nil }
    end
    if not commodity then
        -- Non-stackable items are priced for selling only; they are not offered as deals.
        self.verified[key] = nil
        if self.searching and self.searching.key == key then self.searching = nil end
        return dirty()
    end
    self:Turnover(key, rows)
    local deal, wall, reason = Deals.evaluate(rows, self:DealOptions(key, commodity), self:CfgFor(key))
    local hidden -- a deal that exists but is not shown (ignored, muted): not a verdict on the listing
    if deal and self:Ignored(key) then deal, reason, hidden = nil, "on your ignore list (settings code)", true end
    do  -- deals that exist but are hidden by your own minimum: counted, so the panel can say so
        local p = not deal and reason and tonumber(tostring(reason):match("profit %$(%d+) is under your"))
        if p and p >= 50 then
            local m = self.underMin
            if not m or GetTime() - m.at > 600 then m = { n = 0, best = 0 }; self.underMin = m end
            m.n, m.best, m.at = m.n + 1, math.max(m.best, p), GetTime()
        end
    end
    if wall then Book:ObserveFair(key, wall) end
    if deal and self:Muted(key) then
        deal, reason, hidden = nil, "its deals were missed five times in a row: not shown for 3 minutes", true
    end
    if self.buying and self.buying.key == key then
        -- never replace a deal while its purchase is in flight
    elseif deal then
        deal.at, deal.commodity, deal.key = GetTime(), commodity, key
        do  -- who spotted it. A deal already on screen keeps its label.
            local sr = self.searching
            local had = self.verified[key]
            deal.from = (had and had.from) or (sr and sr.key == key and sr.from) or "me"
        end
        deal.rowsText = self.RowsText(rows)
        deal.rows = rows
        deal.hi = wall -- where the ordinary supply sits: the price of a unit that is not part of the deal
        if not self.verified[key] then
            self.stats.deals = self.stats.deals + 1
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
        end
        self.dealSeen = self.dealSeen or {}
        local fresh = not self.dealSeen[key]
        if fresh then
            self.dealSeen[key] = GetTime()
            if ns.Scout then ns.Scout:Deal(key, deal) end
            if ns.Auto then ns.Auto:Shown(key, deal) end
        end
        deal.born = GetTime() -- when the listing it rests on was read
        self.verified[key] = deal
        if fresh then
            -- SPEED. Deals last seconds. The radar goes silent so the auction
            -- house is free the instant you click, and the price is locked in
            -- right away so that your first click is the purchase itself.
            if Sniper.hold > 0 then ns.Gate.holdUntil = GetTime() + Sniper:HoldFor() end
            if ns.UI and ns.UI.Now then ns.UI:Now() end
            self:TraceInputs(key)
        end
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
            if seen then ns.Scout:Gone(key, GetTime() - seen) end
        end
        do  -- a deal that was on screen is gone: say so instead of letting it vanish
            local seen = self.dealSeen and self.dealSeen[key]
            if seen then
                self.dealSeen[key] = nil
                self:Result("gone", key, ("GONE  %s: someone else bought it, %d seconds after it appeared."):format(nameOf(key), floor(GetTime() - seen + 0.5)), GetTime() - seen)
                self:TraceGone(key)
            end
        end
        ns.Log("NO DEAL %s: %s (rows: %s)", tostring(key), tostring(reason), self.RowsText(rows))
    end
    do  -- score the check for whatever asked for it
        local sr = self.searching
        if ns.Tuner and sr and sr.key == key and sr.src then
            ns.Tuner:Checked(sr.src, deal ~= nil, deal and deal.profit or 0, sr.waited)
        end
    end
    do  -- what was just judged, as the radar sees it: the same standing listing is not checked over and over
        self.judged = self.judged or {}
        if deal or hidden or not commodity then
            self.judged[key] = nil
        else
            local own = self.ownSweep and self.ownSweep[key]
            local r = tostring(reason or "")
            self.judged[key] = { p = (own and own.p) or (rows[1] and rows[1].price) or 0, q = (own and own.q) or math.huge, at = GetTime(), gold = GetMoney(),
                                 sig = self:RuleSig(key),
                                 -- "cheapest is $50, market $68: needs $41 or less": the price it needs, and the market that was judged against
                                 need = tonumber(r:match("^cheapest is %$%d+, market %$%d+: needs %$(%d+) or less")),
                                 mkt = tonumber(r:match("^cheapest is %$%d+, market %$(%d+): needs")),
                                 pile = (r:find("too many to clear", 1, true) or r:find("more than you can spend", 1, true)) and true or nil }
        end
    end
    do
        local sr = self.searching
        local src = sr and sr.key == key and sr.src or nil
        self.last = { key = key, deal = deal ~= nil, reason = reason, at = GetTime(), src = src }
        -- the last answer to something the radar asked about (shown on the Buy tab)
        if deal or ALERT_SRC[src or ""] then self.lastAlert = self.last end
    end
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
-- A VENDOR DEAL STRAIGHT FROM THE RADAR, without the usual full look at the
-- item first. That look costs 0.65 seconds, which is most of a deal's life
-- here. The radar reads every item's cheapest price and total quantity about
-- once a second, so when a price drops under what a vendor pays and the total
-- quantity went up by N since the last read, N units were just listed at that
-- price. The deal is shown at once for N units. It is still the server's
-- quote that decides: your first click asks what N units cost, and the Buy is
-- only offered if that is exactly N x the price seen. Nothing is bought on an
-- estimate.
function Sniper:InstantVendor(key, price, qty, v, prev)
    if self.verified[key] or self.buying or not prev then return false end
    local now = GetTime()
    if now - prev.at > 5 or not prev.p or prev.p <= price then return false end
    local cl = self.cool and self.cool[key]
    if cl and now < cl.till and price <= cl.price then return false end
    -- The cheapest price fell under vendor price, so at least one new unit is
    -- there. How many is the rise in the item's total quantity; on a busy item
    -- that total moves for other reasons too (a real log: 16 Silk Cloth
    -- appeared at 99c while the total went down, so the deal waited for an
    -- item check and 1.1 seconds). When the count is not clear, ask for four:
    -- the server's price for them decides, and what is left is found after.
    local n = qty - prev.q
    local unsure = n <= 0
    if unsure then n = 4 end
    n = min(n, floor(self:Budget() / price))
    if n <= 0 then return false end
    local profit = n * (v - price)
    local need = self:CfgFor(key).minProfit
    local gold = GetMoney()
    if gold < 500 then need = min(need, math.max(10, floor(gold * 0.10))) end
    if profit < need then return false end
    local deal = { kind = "VENDOR", units = n, cost = n * price, deposit = 0, profit = profit, sell = v, buys = {}, counts = {},
                   -- more: cheap units may be left after this purchase (the count was not clear, or your gold ran out first)
                   more = (unsure or n < qty - prev.q) and true or nil,
                   commodity = true, key = key, instant = true, from = "me", next = prev.p, rowsText = unsure and ("radar: price fell to %d, count not known, asking for %d"):format(price, n) or ("radar: %d new at %d"):format(n, price),
                   -- trusted for 8 seconds only; then the item gets its full look like any other
                   at = now - VERIFIED_TTL + 8, born = now }
    self.verified[key] = deal
    self.dealSeen = self.dealSeen or {}
    self.dealSeen[key] = now
    self.stats.deals = self.stats.deals + 1
    if ns.Scout then ns.Scout:Deal(key, deal) end
    if ns.Auto then ns.Auto:Shown(key, deal) end
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
    ns.Log("DEAL VENDOR %s straight from the radar: %d new units at %d, vendor pays %d, profit %d (no item check; the quote decides)",
        tostring(key), n, price, v, profit)
    if Sniper.hold > 0 then ns.Gate.holdUntil = now + Sniper:HoldFor() end
    if ns.UI and ns.UI.Now then ns.UI:Now() end
    self:TraceInputs(key)
    return true
end

-- A FLIP STRAIGHT FROM THE RADAR. The radar shows an item's cheapest price
-- and total quantity. When the cheapest price falls and N units appeared
-- since the radar's last read (under 5 seconds ago), those N units are the
-- new cheap listing. The deal rules are then run on "N units at the new
-- price, on top of the item's listing as last read in full", and a deal is
-- shown at once, without the item check that used to come first (0.65
-- seconds, plus half a second before the click's own request may be sent).
-- Your click asks the server what N units cost; it buys only if that is
-- N x the price seen, exactly as for every other deal.
--
-- WHICH LISTING IS GOOD ENOUGH. It used to be "read in the last 2 minutes".
-- While you are armed no listing is re-read, so two minutes into a session
-- every flip was back to waiting for an item check. Now:
--   * The bottom of the market is never taken from the old listing. It is the
--     radar's own cheapest price just before the drop (under 5 seconds old):
--     rows the listing showed below it have sold, and the planned resale
--     price can never be above it. (The old listing alone could plan a resale
--     at 1s65c with 200 units sitting at 1s20c.)
--   * A listing up to 2 minutes old is used as before.
--   * An older one, up to 15 minutes, is used only if the radar has watched
--     the item without a gap since it was read, and the market it showed is
--     still deep enough after taking off EVERY unit the radar has seen leave
--     the item since then (sold or cancelled, wherever it was).
-- Anything else goes to an item check, as before.
function Sniper:InstantFlip(key, price, qty, prev)
    if self.verified[key] or self.buying or not prev then return false end
    local now = GetTime()
    if now - prev.at > 5 or not prev.p or prev.p <= price then return false end
    local n = qty - prev.q
    if n <= 0 then return false end
    local last = self.lastRows and self.lastRows[key]
    if not last then return false end
    local age = now - last.at
    local old = age > 120
    if old and (age > LADDER_MAX or last.broken) then return false end
    local cl = self.cool and self.cool[key]
    if cl and now < cl.till and price <= cl.price then return false end
    -- the ladder: the new units, then the radar's bottom, then the listing above it
    local rows = { { price = price, qty = n } }
    local bottom
    for _, r in ipairs(last.rows) do
        if r.price == prev.p then bottom = r.qty end
    end
    rows[2] = { price = prev.p, qty = bottom or 1 }
    for _, r in ipairs(last.rows) do
        if r.price > prev.p then rows[#rows + 1] = { price = r.price, qty = r.qty } end
    end
    local cfg = self:CfgFor(key)
    -- Only the new units are bought. Whatever sits above them, the radar's
    -- bottom included, is competition: the resale is planned under it.
    local opts = self:DealOptions(key, true)
    opts.maxRows = 1
    local deal, wall = Deals.evaluate(rows, opts, cfg)
    if not deal or deal.kind ~= "FLIP" or deal.units > n then return false end
    if old then
        -- an older listing: the market must still be deep enough without the units that left since
        local left = (deal.depth or 0) - (last.gone or 0)
        if left < cfg.depthUnits or deal.units > floor(left * cfg.share) then return false end
    end
    deal.commodity, deal.key, deal.from = true, key, "me"
    deal.instant, deal.next, deal.hi = true, rows[2].price, wall
    do  -- more: the row above the new units is itself cheap enough to buy at the market's price, so the item is checked again after this purchase
        local top = wall and floor(floor(Deals.round(wall - cfg.undercut, cfg) * (1 - cfg.cut)) / (1 + cfg.margin)) or 0
        deal.more = (deal.partial or rows[2].price <= top) and true or nil
    end
    deal.rowsText = ("radar: %d new at %d"):format(n, price)
    deal.rows = nil
    deal.at = now - VERIFIED_TTL + 8 -- trusted for 8 seconds only; then the item gets its full look
    deal.born = now
    self.verified[key] = deal
    self.dealSeen = self.dealSeen or {}
    self.dealSeen[key] = now
    self.stats.deals = self.stats.deals + 1
    self.stats.instantFlips = (self.stats.instantFlips or 0) + 1
    if old then self.stats.instantOld = (self.stats.instantOld or 0) + 1 end
    if ns.Scout then ns.Scout:Deal(key, deal) end
    if ns.Auto then ns.Auto:Shown(key, deal) end
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN) end
    ns.Log("DEAL FLIP %s straight from the radar: %d new units at %d, bottom was %d, market %s, sell %d each, profit %d (listing read %.0fs ago, %d units left the item since; the quote decides)",
        tostring(key), deal.units, price, prev.p, tostring(wall), deal.sell, deal.profit, age, last.gone or 0)
    if Sniper.hold > 0 then ns.Gate.holdUntil = now + Sniper:HoldFor() end
    if ns.UI and ns.UI.Now then ns.UI:Now() end
    self:TraceInputs(key)
    return true
end

-- Is this item's listing good enough for a flip straight from the radar right
-- now? (For the panel: how many of the watched items are "ready".)
function Sniper:ListingReady(key)
    local last = self.lastRows and self.lastRows[key]
    if not last then return false end
    local age = GetTime() - last.at
    if age <= 120 then return true end
    return age <= LADDER_MAX and not last.broken
end

-- How long the radar stays quiet when a deal appears: 6 seconds, unless the
-- auto-adjust has something better (1 second while the wheel is rolling,
-- otherwise how fast your inputs really come).
function Sniper:HoldFor()
    if ns.Auto then return ns.Auto:Hold(self:SnipeMode(), Sniper.hold) end
    return Sniper.hold
end

---------------------------------------------------------------- stake-out
-- ONE ITEM, WATCHED BY ASKING ITS PRICE. For every other deal the path is:
-- radar read -> (item check) -> price request -> purchase, and the game makes
-- each request wait about half a second for the one before it. With the wheel
-- rolling and a reaction time of zero, a real session still lost 12 of 23
-- deals in that chain. For one chosen item the chain can lose its first
-- links: every notch of the wheel sends the price request itself ("what does
-- one unit cost now?"), and when the answer is low enough the purchase
-- follows at once. A cheap listing is then bought about a second sooner.
--
-- The price it buys at is not a guess: it is the dearest price at which one
-- unit is still a deal by the normal rules (margin, smallest profit, your
-- capital limits), worked out from the item's full listing, which is re-read
-- once a minute while the stake-out runs. After a purchase it asks for two
-- units, then four, up to eight, and buys them only if every one is at the
-- price just paid; any other answer puts it back to one.
--
-- The radar is off while a stake-out runs: every request is a price request.
local STAKE_FRESH, STAKE_CAP = 60, 8

function Sniper:StakeKey()
    local k = AuctionMeshDB.cfg.stake
    return (type(k) == "number" and k > 0) and k or nil
end

-- key = nil ends the stake-out
function Sniper:SetStake(key)
    local b = self.buying
    if b and b.stake and b.phase == "quote" then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        self.buying = nil
    end
    key = (type(key) == "number" and key > 0) and key or nil
    AuctionMeshDB.cfg.stake = key
    self.stake = key and { key = key, asked = 0, bought = 0, q = 1 } or nil
    if key then self.priority = key end -- read its market now
    dirty()
end

-- What a stake-out on ANY item would buy at, from that item's listing as it
-- was last read (no request is sent for this). Returns a table
-- { max, why, kind, sell, each, cap, at } ; max = nil means no price would be
-- a deal, and why says so. Kept until the listing is read again or your gold
-- changes, so asking twice costs nothing.
function Sniper:TermsFor(key)
    local last = self.lastRows and self.lastRows[key]
    if not last or #last.rows == 0 then return { why = "reading its market first" } end
    local gold = GetMoney()
    self.termsCache = self.termsCache or {}
    local c = self.termsCache[key]
    if c and c.at == last.at and c.gold == gold then return c end
    c = { at = last.at, gold = gold }
    self.termsCache[key] = c
    local opts, cfg = self:DealOptions(key, true), self:CfgFor(key)
    local why
    local function dealAt(p, n)
        local rows = { { price = p, qty = n } }
        for _, r in ipairs(last.rows) do
            if r.price > p then rows[#rows + 1] = { price = r.price, qty = r.qty } end
        end
        if #rows < 2 then return nil end
        local d, _, w = Deals.evaluate(rows, opts, cfg)
        if d and d.units >= n and d.cost == p * n then return d end
        why = w or why
        return nil
    end
    -- The smallest-profit setting is judged on a lot of up to eight units, not
    -- on one: you chose this item, and a single unit of a cheap material never
    -- clears it (with a 1s20c minimum, Silk Cloth at 99c against a 1s50c vendor
    -- price would never have been bought one at a time).
    local best, bestDeal, lot
    for _, n in ipairs({ STAKE_CAP, 4, 2, 1 }) do
        local lo, hi = 1, last.rows[#last.rows].price
        while lo <= hi do
            local mid = floor((lo + hi) / 2)
            local d = dealAt(mid, n)
            if d then best, bestDeal, lo = mid, d, mid + 1 else hi = mid - 1 end
        end
        if best then lot = n; break end
    end
    if not best then
        c.why = why and (tostring(why):gsub("%$(%d+)", function(n) return plain(tonumber(n)) end)) or "no price would be a deal right now"
        return c
    end
    c.max, c.kind, c.sell = best, bestDeal.kind, bestDeal.sell
    c.each = bestDeal.kind == "VENDOR" and (bestDeal.sell - best) or (floor(bestDeal.sell * (1 - Deals.cfg.cut)) - best)
    c.cap = lot
    return c
end

-- The dearest price at which one unit of the staked item is still a deal, or
-- nil and the reason.
function Sniper:StakeTerms()
    local key = self:StakeKey()
    if not key then self.stake = nil; return nil end
    local st = self.stake
    if not st or st.key ~= key then st = { key = key, asked = 0, bought = 0, q = 1 }; self.stake = st end
    local c = self:TermsFor(key)
    if st.terms ~= c then
        st.terms = c
        st.max, st.why, st.kind, st.sell, st.each, st.cap = c.max, c.why, c.kind, c.sell, c.each, c.cap
        if c.max then
            ns.Log("STAKE-OUT terms for %s: buys at %d or less (%s, sells at %d), up to %d at a time; listing read %.0fs ago",
                tostring(key), c.max, tostring(c.kind), c.sell, c.cap, GetTime() - c.at)
        end
    end
    return st.max, st.why
end

-- What stake-outs have done so far, per item, kept across sessions:
-- { asked = price requests sent, bought = units bought }.
function Sniper:StakeRecord(key, asked, bought)
    AuctionMeshDB.stakeLog = AuctionMeshDB.stakeLog or {}
    local r = AuctionMeshDB.stakeLog[key]
    if not r then
        if not asked and not bought then return { asked = 0, bought = 0 } end
        r = { asked = 0, bought = 0 }
        AuctionMeshDB.stakeLog[key] = r
    end
    r.asked, r.bought = r.asked + (asked or 0), r.bought + (bought or 0)
    return r
end

-- True while the stake-out is the thing running: an item is chosen, its terms
-- are known and the wheel is rolling in the snipe box.
function Sniper:Staking()
    local st = self.stake
    return st ~= nil and st.max ~= nil and self:StakeKey() == st.key and self:SnipeMode()
end

-- One notch of the wheel in the snipe box, with no deal on it. Returns true
-- when the stake-out used it.
function Sniper:StakeNotch()
    if not self:StakeKey() then return false end
    local max = self:StakeTerms()
    local st = self.stake
    if not max then
        if st and not (self.lastRows and self.lastRows[st.key]) then self.priority = self.priority or st.key end
        return false
    end
    local b = self.buying
    if b then
        if b.stake and b.phase == "confirm" then self:Confirm() end -- one-click buying is blocked on this client: this notch is the purchase
        return true
    end
    if self.searching then return true end -- its listing is being re-read
    local now = GetTime()
    if now - self.lastRows[st.key].at > STAKE_FRESH then return true end -- due for a re-read: the next free request is that
    local gold = GetMoney()
    if gold < max then st.why = "not enough gold for one unit"; return true end
    local q = max == 0 and 1 or math.max(1, min(st.q or 1, st.cap or 1, floor(gold / max)))
    local deal = { key = st.key, kind = st.kind, units = q, cost = q * max, sell = st.sell, profit = q * (st.each or 0), deposit = 0,
                   buys = {}, counts = {}, commodity = true, instant = true, stake = true, from = "me", at = now,
                   rowsText = "stake-out: price asked directly" }
    self.buying = { key = st.key, units = q, max = q * max, phase = "quote", deal = deal, at = now, stake = true }
    self.react = { key = st.key, secs = 0, via = "stake-out" }
    st.asked = st.asked + 1
    self:StakeRecord(st.key, 1, 0)
    ns.Gate:Use(("stake-out price request %dx %s (buys at %d or less each)"):format(q, tostring(st.key), max), nil, "buy")
    ns.Gate.ignoreErrorUntil = math.max(ns.Gate.ignoreErrorUntil or 0, now + 2) -- an error now answers this price request, not the pace
    self.inputCallAt = now
    C_AuctionHouse.StartCommoditiesPurchase(st.key, q)
    self:ArmPurchaseTimeout(4)
    return true
end

-- GOLD FOR POSTING. Every auction costs a posting fee up front (it comes back
-- when the item sells). What you have bought and not listed yet still needs
-- its fee, so that much gold is spoken for. When the gold in hand no longer
-- covers it, more flips only add to what cannot be listed: the addon then
-- switches itself to VENDOR DEALS ONLY (gold back at the next vendor, no
-- fee), says so, and switches flips back on by itself the moment the gold in
-- hand covers the fees again. Your own setting is not touched.
-- Returns the fees owed and how many items they are for.
function Sniper:FeesOwed()
    local now = GetTime()
    local c = self.feesCache
    if c and now - c.at < 2 then return c.fees, c.items end
    local fees, items = 0, 0
    local Se = ns.Seller
    for key, f in pairs((AuctionMeshDB and AuctionMeshDB.flips) or {}) do
        local units = f.units or 0
        -- to be posted: a flip, or something bought under vendor price that the auction house pays more for
        if units > 0 and (f.kind == "FLIP" or (f.kind == "VENDOR" and Se and Se.BestExit and Se:BestExit(key, f) == "AH")) then
            local per, dmin = self.depositInfo(key, not self.isItem[key])
            if per ~= math.huge then
                fees = fees + math.max(dmin or 0, math.ceil(per * units))
                items = items + 1
            end
        end
    end
    self.feesCache = { at = now, fees = fees, items = items }
    return fees, items
end

-- Once a second while the auction house is open.
function Sniper:GoldWatch()
    local now = GetTime()
    if self.goldAt and now - self.goldAt < 1 then return end
    self.goldAt = now
    local cfg = AuctionMeshDB.cfg
    local fees, items = self:FeesOwed()
    local gold = GetMoney()
    local low = self.lowGold
    if not low then
        if cfg.flips ~= false and items > 0 and gold < fees then
            self.lowGold = { at = now, fees = fees, items = items }
            Deals.cfg.flips = false
            for k, d in pairs(self.verified) do
                if d.kind == "FLIP" and not (self.buying and self.buying.key == k) then self.verified[k] = nil end
            end
            self.background, self.lastBg, self.lastScreen = nil, 0, 0
            local msg = ("|cffff8040Gold is low:|r %s in hand, and posting the %d item%s you have bought and not listed takes %s. Vendor deals only from now; flips come back by themselves when you have the gold.")
                :format(plain(gold), items, items == 1 and "" or "s", plain(fees))
            say(msg)
            ns.Log("LOW GOLD: %d in hand, %d owed in posting fees for %d item(s): flips off until it is covered", gold, fees, items)
            if PlaySound then pcall(PlaySound, 847) end
            dirty()
        end
    else
        low.fees, low.items = fees, items
        -- back on when the fees are covered with a little to spare (so it does not flip back and forth on a few copper)
        if cfg.flips == false or items == 0 or gold >= fees + math.max(100, floor(fees * 0.2)) then
            self.lowGold = nil
            Deals.cfg.flips = cfg.flips ~= false
            self.background, self.lastBg, self.lastScreen = nil, 0, 0
            if cfg.flips ~= false then
                say(("|cff33ff66Gold is back:|r %s in hand covers the posting fees (%s). Flips are on again."):format(plain(gold), plain(fees)))
                ns.Log("LOW GOLD over: %d in hand, %d owed: flips on again", gold, fees)
            end
            dirty()
        elseif Deals.cfg.flips then
            Deals.cfg.flips = false -- (something set it back, a settings code for example: still low)
        end
    end
end

-- SNIPE MODE: you are rolling the wheel in the snipe box (a notch in the last
-- 3 seconds). Every request then goes to the radar and to alerts: no routine
-- item checks, no side classes, no housekeeping. A routine check costs one
-- request, and a deal that appears during it is seen 0.65 seconds later.
function Sniper:SnipeMode()
    local U = ns.UI
    return (U and U.wheelSeen and GetTime() - U.wheelSeen < 3) and true or false
end

-- THE UPKEEP BUDGET. Sniping is the radar, the checks its alerts ask for, and
-- your purchases: those never wait for anything else. Everything else is
-- UPKEEP (a listing kept ready, a side class, the price of something you
-- hold, the list of your own auctions) and gets one request only after the
-- radar has had N reads in a row:
--   * 8 on every tab but Bags: at least 8 of every 9 requests are radar reads;
--   * 3 on the Sell tab, where you are posting and want current prices.
-- It used to be one for one: every item check took the turn of a radar read,
-- so twelve focus items a minute meant sixteen seconds of every minute with
-- the radar at half speed.
-- WHILE YOU ARE ARMED the only upkeep is a listing that a flip straight from
-- the radar needs and does not have (see ListingDue): each one read makes a
-- flip on that item buyable one request, 0.65 seconds, sooner. Nothing else:
-- no prices of what you hold, no side class, no list of your auctions, no
-- re-read of a listing that is still good.
-- With no radar running there is nothing to protect and upkeep is free.
function Sniper:UpkeepEvery()
    local c = self.upkeep
    local U = ns.UI
    if U and U.tab == "SELL" and not self:SnipeMode() then
        -- REQUESTS FOLLOW THE TAB. You are on the Sell tab to sell: while
        -- selling has anything to read (a price for something to post, the
        -- listing of an undercut auction) EVERY request goes to that. Once
        -- it is all in, the radar has three of every four again, so deals
        -- still show on the Buy tab's label. On the Buy tab it is the
        -- other way round: nothing is read for selling there at all.
        local Se = ns.Seller
        if Se and Se.Unpriced and Se:Unpriced() then return c.bagsNew end
        return c.bags
    end
    return c.every
end
function Sniper:UpkeepTurn()
    local Sw = ns.Swarm
    if not (Sw and Sw.active) or Sw.idle then return true end
    return (ns.radarSince or 0) >= self:UpkeepEvery()
end
function Sniper:UpkeepUsed() ns.radarSince = 0; ns.upkeepLast = "item" end

-- How far under the market the cheapest listing must be before a full check
-- is worth a request: the same bar a flip has to clear (profit margin after
-- the cut), with 3% to spare. At 20% margin that is 77% of market. The old
-- fixed 80% sent 66 checks for 3 deals in the first real report.
function Sniper.TriggerRatio()
    return (1 - Deals.cfg.cut) / (1 + Deals.cfg.margin) * 0.97
end

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
-- A fast seller outside the focus set (laser focus on "prime" only).
function Sniper:InWide(key)
    if not ns.Scout or not ns.Scout.d or not ns.Scout.Wide then return false end
    local w = ns.Scout:Wide(self:Budget(), VENDOR_SOLD, classSub)
    return w ~= nil and w[key] == true
end

function Sniper:OnSweep(key, price, qty)
    local shared = false
    if not self.active or key <= 0 or self.isItem[key] then return end
    local now = GetTime()
    do  -- a deal on the panel whose cheap units this read shows to be gone (see RadarGone)
        local d = self.verified[key]
        if d and d.commodity and d.born and d.units and d.cost and price * d.units > d.cost
            and not (self.buying and self.buying.key == key) then
            local cur = ns.Swarm and ns.Swarm.current
            if cur and cur.phase == "query" and cur.at and cur.at > d.born then self:RadarGone(key, d, price) end
        end
    end
    self.sweep = self.sweep or {}
    local prev = self.sweep[key]
    self.sweep[key] = { p = price, q = qty, at = now }
    -- Quantity leaving the whole listing is CHURN (sales + cancelled auctions),
    -- measured on our own reads only: a friend's read arrives late and out of
    -- order, which made every new posting look like a sale. Real sales are
    -- measured from full listings (Turnover below).
    local prevOwn
    if not shared then
        local own = self.ownSweep and self.ownSweep[key]
        prevOwn = own
        self.ownSweep = self.ownSweep or {}
        self.ownSweep[key] = { q = qty, p = price, at = now }
        -- (the minimum was 1 second: with radar reads 0.73s apart that dropped eight intervals in nine)
        if own and now - own.at >= 0.3 and now - own.at <= 900 then
            local gone = own.q - qty
            Store:AddChurn(key, gone > 0 and gone or 0, now - own.at)
        end
        -- THE LISTING AS LAST READ, FOLLOWED BY THE RADAR. Units that leave
        -- the item are taken off what that listing may still be trusted for;
        -- a gap in the watching ends the trust (see InstantFlip).
        local lr = self.lastRows and self.lastRows[key]
        if lr then
            if own and now - own.at <= 10 then
                if own.q > qty then lr.gone = (lr.gone or 0) + (own.q - qty) end
            elseif now - lr.at > 10 then
                lr.broken = true
            end
            if lr.p0 == nil then lr.p0, lr.q0 = price, qty end
            if price ~= lr.p0 or qty ~= lr.q0 then lr.changed = true end
        end
    end
    local ft = Store.ft[key]
    local market = (ft and GetServerTime() - ft <= 1800) and Store.fp[key] or nil
    if ns.Scout then ns.Scout:Read(key, price, market) end -- counted for every item, affordable or not
    if self:Muted(key) or self:Ignored(key) then return end -- missed five times running, or on your ignore list
    -- Is the price worth a look at all? Decided before your gold is, so that a
    -- cheap listing you cannot pay for is COUNTED (the panel says so) instead
    -- of silently passed over. (A real log: 5 copper in hand, 115 radar reads
    -- with not one alert, and nothing on the panel to say why.)
    local why, flip, wide
    local v = self.vendorOf(key)
    if v and price <= floor(v / (1 + Deals.cfg.vendorMargin)) then
        why = "at or under vendor price"
    elseif VENDOR_SOLD[key] or not Deals.cfg.flips then return
    else
        -- LASER FOCUS. The focus items get the radar's alerts at once and
        -- flips straight from the radar. Every other item measured to sell
        -- fast used to be passed over for flips altogether, however cheap it
        -- was listed (15 items looked at, of some 50 fast sellers). Those
        -- are now looked at too: see AddWide.
        if not self:InFocus(key) then
            if not self:InWide(key) then return end
            wide = true
        end
        if market and price <= market * self.TriggerRatio() then
            why, flip = "under market", true
        elseif prev and price <= prev.p * 0.85 then
            why, flip = "price just dropped", true
        end
    end
    if not why then return end
    do  -- YOUR GOLD. One unit must be payable; for a flip, with its posting fee on top (the deal rules keep it back).
        local need, have = price, self:Budget()
        if flip then
            local _, feeMin = self.depositInfo(key, true)
            need = price + (feeMin or 0)
            -- and one flip may take only a share of the gold in hand (your "spend" setting), as the deal rules will say
            local gold = GetMoney()
            if gold >= Deals.cfg.smallPurse then have = min(have, floor(gold * Deals.cfg.maxSpend)) end
        end
        if need > have then
            self.poor = self.poor or {}
            self.poor[key] = now
            return
        end
    end
    if why == "at or under vendor price" then
        if not shared and self:InstantVendor(key, price, qty, v, prevOwn) then return end
    elseif wide then
        return self:AddWide(key, why, price, market, qty)
    elseif not shared and self:InstantFlip(key, price, qty, prevOwn) then return end
    self:AddTrigger(key, why, price, market, nil, qty)
end

-- A FLIP ALERT ON A FAST SELLER OUTSIDE THE FOCUS SET. It must not cost the
-- focus items anything, so it does not take a radar read's place:
--   * listed at half the market price or less: an ordinary alert, checked at
--     once (that is the big flip, and it will not last);
--   * otherwise it waits for the upkeep turn (one request in nine), ahead of
--     the routine listing re-reads that turn used to go to (under 1% of
--     those ever found a deal), best first, and only if the radar's latest
--     read still shows the price.
Sniper.WIDE_NOW = 0.5
function Sniper:AddWide(key, why, price, market, qty)
    if market and market > 0 and price <= market * Sniper.WIDE_NOW then
        return self:AddTrigger(key, why, price, market, nil, qty)
    end
    if not self.active or key <= 0 or self.isItem[key] or self.verified[key] then return end
    if not self:AlertDue(key, price, qty, market) then return end
    self.wide = self.wide or {}
    local w = self.wide[key]
    if not w then
        ns.Log("WIDE ALERT %s: %s (lowest %s, market %s): outside the focus set, checked in the upkeep turn", tostring(key), tostring(why), tostring(price), tostring(market))
    end
    self.wide[key] = { price = price, market = market, at = w and w.at or GetTime(),
                       src = (why and why:find("market", 1, true)) and "market" or "drop",
                       -- what one unit could bring: the copper between this price and the market
                       score = (market or 0) - price }
end

-- How many cheap listings the radar passed over in the last minute because
-- one unit (with the posting fee, for a flip) costs more than the gold you hold.
function Sniper:PoorCount()
    local n, now = 0, GetTime()
    for key, at in pairs(self.poor or {}) do
        if now - at <= 60 then n = n + 1 else self.poor[key] = nil end
    end
    return n
end

-- May the radar ask for a check of this item now? Second value: true when it
-- should go ahead of the usual 20 seconds between two checks of one item.
--   * Cheaper than what was last judged: at once. That is a new listing.
--   * Checked under 20 seconds ago: no.
--   * Judged "no deal" and the radar shows the same price and no more units
--     than it did then: not again for 5 minutes. (A standing listing that is
--     not a deal, say a vendor profit under your minimum, was checked every 20
--     seconds without end, while you were armed too, and the radar waited
--     for each of those checks.)
--   * Exceptions: you have more gold than when it was judged, or it was
--     refused for being too big a pile and the pile has shrunk.
function Sniper:AlertDue(key, price, qty, market)
    local since = self:Since(key)
    local j = self.judged and self.judged[key]
    -- THE LAST CHECK SAID WHAT PRICE IT NEEDS. Until the radar shows that
    -- price (or the market it was judged against has risen, or your settings
    -- have changed), another check can only say the same again: a lower
    -- price that is still too high, or more units at it, change nothing. In
    -- the real logs about one alert check in five was such a repeat, each
    -- one a request the radar did not get.
    if j and j.need and j.mkt and price and price > j.need and GetTime() - j.at < JUDGED_TTL
        and (market or 0) <= j.mkt and j.sig == self:RuleSig(key) then
        return false
    end
    if j and price and price < j.p then return since >= 1.5, true end
    if since < TRIGGER_MIN then return false end
    if j and GetTime() - j.at < JUDGED_TTL and qty and qty <= j.q then
        if GetMoney() > (j.gold or 0) then return true end
        if j.pile and qty < j.q then return true end
        if j.sig ~= self:RuleSig(key) then return true end -- your settings have changed since: judged by the old ones
        return false
    end
    return true
end

-- The settings a verdict depends on, as one string (a verdict made under
-- other settings is not held against a listing).
function Sniper:RuleSig(key)
    local c = self:CfgFor(key)
    return table.concat({ tostring(c.minProfit), tostring(c.margin), tostring(c.flips), tostring(c.maxSpend), tostring(c.maxTied),
        tostring(c.smallFlip), tostring(c.vendorMargin), tostring(c.requireTurnover), tostring(c.maxSellMinutes) }, "|")
end

-- Queues one full look at an item that the radar saw something in.
function Sniper:AddTrigger(key, why, price, market, from, qty)
    if not self.active or key <= 0 or self.isItem[key] or self.verified[key] then return end
    local due, fast = self:AlertDue(key, price, qty, market)
    if not due then return end
    self.triggers = self.triggers or {}
    if not self.triggers[key] then
        -- Score = how much there is to gain. Each confirmation costs one of our
        -- ~1.6 requests a second, so the most valuable look always goes first:
        -- vendor-price hits (guaranteed) ahead of everything, then the biggest gap.
        local score = 0
        if market and price and market > 0 then score = (market - price) / market end
        local src = "drop"
        if why and why:find("vendor", 1, true) then src = "vendor"
        elseif why and why:find("market", 1, true) then src = "market" end
        -- Learned: alerts of a kind that keeps turning out real go first.
        -- (0.5 + hit rate) is 1.0 for a kind with no record yet.
        if ns.Tuner then score = (score + 0.05) * (0.5 + ns.Tuner:HitRate(src)) end
        if src == "vendor" then score = score + 10 end
        self.trigInfo = self.trigInfo or {}
        self.trigInfo[key] = { src = src, at = GetTime(), from = from or "me", fast = fast }
        self.triggers[key] = score
        self.triggers[#self.triggers + 1] = key
        ns.Log("TRIGGER %s: %s (lowest %s, market %s, score %.2f)", tostring(key), tostring(why), tostring(price), tostring(market), score)
    end
end

-- What the panel says about item checks: the alert waiting, if any.
function Sniper:PeekNext()
    if self.priority then return self.priority end
    if self.triggers and self.triggers[1] then return self.triggers[1] end
end

-- How many of the watched items have a listing that allows a flip straight
-- from the radar right now: ready, watched.
function Sniper:ReadyCount()
    local q, n = self.background, 0
    if not q then return 0, 0 end
    for i = 1, #q do if self:ListingReady(q[i]) then n = n + 1 end end
    return n, #q
end

-- Trading volume. Between two readings of the same listing, units that
-- disappeared from the cheap end (at or below the 3rd price level) were bought
-- by someone. New cheap listings hide some sales, so this never overstates.
-- REAL SALES, from two full listings of the same item. Commodities are always
-- bought cheapest first, so a sale eats the listing from the bottom:
--   * walk the OLD price levels from the cheapest up;
--   * units missing from a level count as sold;
--   * stop at the first level that is intact (buyers never got past it);
--   * a level that vanished entirely while at least as much NEW stock now sits
--     below it is treated as a cancelled-and-relisted auction, not a sale, and
--     counting stops there.
-- Anything that disappears higher up while cheaper stock remains is a
-- cancellation and is never counted. This under-counts rather than over-counts.
function Sniper.SoldBetween(old, rows)
    local now = {}
    for i = 1, #rows do now[rows[i].price] = (now[rows[i].price] or 0) + rows[i].qty end
    local was = {}
    for i = 1, #old do was[old[i].price] = (was[old[i].price] or 0) + old[i].qty end
    local sold = 0
    for i = 1, #old do
        local p, q = old[i].price, old[i].qty
        local q2 = now[p] or 0
        if q2 >= q then break end
        local gone = q - q2
        if q2 == 0 then
            local newBelow = 0
            for price, qty in pairs(now) do
                if price < p then newBelow = newBelow + math.max(0, qty - (was[price] or 0)) end
            end
            if newBelow >= gone then break end
        end
        sold = sold + gone
        if q2 > 0 then break end
    end
    return sold
end

function Sniper:Turnover(key, rows)
    if #rows == 0 then return end
    local now = GetTime()
    local prev = self.book[key]
    if prev then
        local dt = now - prev.at
        if dt < 20 then return end -- same reading (the game sends results twice)
        if dt <= 900 and prev.rows then
            local gone = self.SoldBetween(prev.rows, rows) - (self.bought[key] or 0)
            Store:AddTurnover(key, gone > 0 and gone or 0, dt)
        end
    end
    self.bought[key] = nil
    local keep = {}
    for i = 1, math.min(8, #rows) do keep[i] = { price = rows[i].price, qty = rows[i].qty } end
    self.book[key] = { rows = keep, at = now }
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
    local partial = s and s.key == itemID and AH.HasFullCommoditySearchResults and not AH.HasFullCommoditySearchResults(itemID)
        and (s.more or 0) < 8
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
            if fl and GetTime() - fl.at < 600 and r.unitPrice < fl.price then q = 0 end
            -- just missed at this price: the listing may still show units that are gone
            local cl = self.cool and self.cool[itemID]
            if cl and GetTime() < cl.till and r.unitPrice <= cl.price then q = 0 end
            if q > 0 then rows[#rows + 1] = { price = r.unitPrice, qty = q } end
        end
    end
    if partial then
        -- The server sent the cheapest part of the listing first. If that part
        -- already proves a deal, act on it now: every further page costs 0.6s
        -- and can only add dearer units, which make the market deeper, never
        -- the deal worse. Otherwise ask for the rest before judging.
        table.sort(rows, function(a, b) return a.price < b.price end)
        local deal = Deals.evaluate(rows, self:DealOptions(itemID, true), self:CfgFor(itemID))
        if not deal then
            s.needMore, s.at = "commodity", GetTime()
            return
        end
        ns.Log("FAST %s: the first page already shows a deal; not waiting for the rest of the listing", tostring(itemID))
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

-- Is this watched item's listing due for a re-read (upkeep)?
--   * Never sooner than the item's own interval (60s for a focus item, the
--     "every=" setting; 5 minutes for the wider watch list).
--   * From then on: when the radar shows the item has changed since the
--     listing was read (or lost sight of it), or at 5 minutes whatever the
--     radar shows. A listing the radar sees no change in is not re-read just
--     because a minute has passed.
--   * While you are armed: only a listing that a flip straight from the radar
--     cannot use (none read yet this visit, or the radar lost sight of the
--     item), or one about to become too old for it (13 of its 15 minutes).
function Sniper:ListingDue(key, snipe)
    local since = self:Since(key)
    if snipe then
        if since >= ARMED_KEEP then return true end
        return since >= 60 and not self:ListingReady(key)
    end
    if since < (self.watchMin or WATCH_MIN) then return false end
    if since >= FOCUS_KEEP then return true end
    local lr = self.lastRows and self.lastRows[key]
    return (not lr or lr.changed or lr.broken) and true or false
end

-- What to check next. Returns key, source, seconds the alert waited, who saw
-- it, and true when the check is upkeep (it then uses up the upkeep turn).
--   1. a deal on screen that needs its re-check, and the item you pressed Post on
--   2. the radar's alerts, best first
--   3. only when `upkeep` (the upkeep turn is free): prices of what you hold,
--      the price table's candidates when no radar runs, watched listings
function Sniper:NextCheck(upkeep)
    if self.priority then local k = self.priority; self.priority = nil; return k, "recheck" end
    local Se = ns.Seller
    if Se and Se.priority and Se.NextToPrice then
        local want = Se:NextToPrice(true)
        if want then Se.pending = { key = want, at = GetTime() }; return want, "price" end
    end
    -- Radar hits: the sweep saw a price worth a full look.
    local tr = self.triggers
    while tr and #tr > 0 do
        local bi = 1
        for i = 2, #tr do if (tr[tr[i]] or 0) > (tr[tr[bi]] or 0) then bi = i end end
        local k = table.remove(tr, bi)
        tr[k] = nil
        local info = self.trigInfo and self.trigInfo[k]
        if self.trigInfo then self.trigInfo[k] = nil end
        -- (a check that was lost is asked again whatever the time since it was "last checked": it never was)
        if not self.verified[k] and ((info and info.retry) or self:Since(k) >= ((info and info.fast) and 1.5 or TRIGGER_MIN)) then
            return k, info and info.src or "drop", info and (GetTime() - info.at) or 0, info and info.from or "me"
        end
    end
    if not upkeep then return nil end
    do  -- flip alerts on fast sellers outside the focus set: the upkeep turn goes to the best of them first
        local wide, now = self.wide, GetTime()
        if wide then
            local bk, bs
            for k, w in pairs(wide) do
                local sw = self.sweep and self.sweep[k]
                -- gone from the radar's latest read, too old, or already a deal: dropped without a request
                if now - w.at > 30 or not sw or sw.p > w.price or self.verified[k] then
                    wide[k] = nil
                elseif self:Since(k) >= TRIGGER_MIN and (not bs or w.score > bs) then
                    bk, bs = k, w.score
                end
            end
            if bk then
                local w = wide[bk]
                wide[bk] = nil
                return bk, w.src, now - w.at, "me", true
            end
        end
    end
    local snipe = self:SnipeMode()
    if not snipe then
        -- what you hold, priced for posting (every 45s on the Sell tab, every 10 minutes elsewhere)
        local want = Se and Se.NextToPrice and Se:NextToPrice()
        if want then Se.pending = { key = want, at = GetTime() }; return want, "price", nil, nil, true end
        -- The price table's candidates: prices the radar has read that look
        -- low against what is known of the item. One that was judged "no
        -- deal" is left alone while its price and quantity stay as they were
        -- (it was looked at again every 30 seconds).
        for _, c in ipairs(self.candidates or {}) do
            if not self.verified[c.key] and not self.isItem[c.key] and self:Since(c.key) > CHECK_AGAIN
                and self:AlertDue(c.key, Store.p[c.key], Store.q[c.key]) then
                return c.key, "list", nil, nil, true
            end
        end
    end
    -- Watched listings: what a flip straight from the radar is judged against,
    -- and what keeps market price and selling speed current.
    local q = self.background
    if not q or #q == 0 then return nil end
    for _ = 1, #q do
        if q.i > #q then q.i = 1; q.rounds = (q.rounds or 0) + 1 end
        local k = q[q.i]
        q.i = q.i + 1
        if not self.isItem[k] and self:ListingDue(k, snipe) then return k, "routine", nil, nil, true end
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
                self.background, self.watchMin = list, Sniper.FocusEvery()
                return
            end
        end
        self.watchMin = WATCH_MIN
    end
    local scope = ns.Swarm and ns.Swarm.ScopeClasses and ns.Swarm:ScopeClasses() or PROFESSION
    local list, seen = {}, {}
    -- Items that have really been seen under market come first (most dips
    -- first): that is where a full look pays. Up to 20 of them.
    if ns.Scout and ns.Scout.d and Deals.cfg.flips then
        local dippy = {}
        for key, it in pairs(ns.Scout.d.items) do
            local p = Store.p[key]
            if (it.d or 0) >= 3 and key > 0 and not self.isItem[key] and not VENDOR_SOLD[key] and p and p <= budget then
                dippy[#dippy + 1] = key
            end
        end
        table.sort(dippy, function(a, b) return ns.Scout.d.items[a].d > ns.Scout.d.items[b].d end)
        for i = 1, math.min(20, #dippy) do list[#list + 1] = dippy[i]; seen[dippy[i]] = true end
    end
    -- Then the staples. Ones whose known lowest price is above your gold are skipped.
    for _, key in ipairs(STAPLES) do
        local p = Store.p[key]
        if not seen[key] and not self.isItem[key] and (not p or p <= budget) then list[#list + 1] = key; seen[key] = true end
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

function Sniper:Busy() return self.searching ~= nil or self.buying ~= nil end

-- Called by the radar before each of its reads. It waits only for a request
-- of the sniper's that is in flight, for your purchase or post, and for an
-- alert. Upkeep never makes it wait: that is sent in its own turn (see
-- UpkeepTurn), and the radar has the next one.
function Sniper:YieldTo()
    if self:Busy() then return false end
    if self:Staking() then return false end -- a stake-out is running: every request is a price request
    if ns.Seller and ns.Seller:Busy() then return false end
    if self.priority then return false end
    if self.triggers and #self.triggers > 0 then return false end -- an alert is waiting: the radar waits
    -- the upkeep turn is free: the one upkeep request that is due, if any, goes before this read
    if self.active and self:UpkeepTurn() then
        local before = ns.Gate.uses
        self:Tick()
        if ns.Gate.uses ~= before then return false end
    end
    return true
end

function Sniper:Tick()
    if not self.active then return end
    local now = GetTime()
    local sr = self.searching
    if sr then
        -- A request the client never transmitted: free the queue after 0.4s, not 3.
        local unsent = ns.Gate.sawSent and sr.sent == ns.Gate.sentCount and now - sr.at > 0.4 and not sr.needMore
        local timeout = ns.Tuner and ns.Tuner:Timeout() or SEARCH_TIMEOUT
        if unsent or now - sr.at > timeout then
            -- AN ALERT WHOSE CHECK WAS LOST IS ASKED AGAIN, once. (A real log: the
            -- radar saw an item at vendor price, its check went out right after a
            -- refused purchase, came back as an error with no data, and was
            -- "skipped": that price was never looked at.) Once in ten seconds
            -- per item, so a check that can never be sent does not go round.
            local again = false
            if ALERT_SRC[sr.src or ""] and not self.verified[sr.key] then
                self.lostOnce = self.lostOnce or {}
                local was = self.lostOnce[sr.key]
                if not was or now - was > 10 then
                    self.lostOnce[sr.key] = now
                    self.triggers = self.triggers or {}
                    if not self.triggers[sr.key] then
                        self.triggers[sr.key] = (sr.src == "vendor") and 11 or 1 -- (ahead of what is waiting: it was already at the front once)
                        self.triggers[#self.triggers + 1] = sr.key
                        self.trigInfo = self.trigInfo or {}
                        self.trigInfo[sr.key] = { src = sr.src, at = now - (sr.waited or 0), from = sr.from or "me", retry = true }
                    end
                    again = true
                end
            end
            local what = again and "asked again" or "skipped"
            if unsent then ns.Log("SEARCH %s was not transmitted by the client; %s", tostring(sr.key), what) end
            if ns.Tuner then ns.Tuner:Wasted(unsent and "unsent" or "timeout") end
            if ns.Watch then
                ns.Watch:Add("NO-ANSWER", now - sr.at, unsent and ("the item check of %s was never transmitted by the game; %s"):format(tostring(sr.key), what)
                    or ("the item check of %s was not answered in %.1fs; %s"):format(tostring(sr.key), now - sr.at, again and "asked again" or "given up"))
            end
            local Se = ns.Seller
            if Se and Se.pending and Se.pending.key == sr.key then
                Se.pending = nil
                if Se.pricedAt then Se.pricedAt[sr.key] = nil end -- the answer never came: ask again at once
            end
            self.searching = nil
        end
    end
    self.queued, self.arming = nil, nil -- clicks are never held back any more (see Buy)
    -- The radar finds new deals; this pass over the whole price table only has
    -- to expire old ones and catch what the radar could not see, so it runs rarely.
    self:GoldWatch()
    if now - (self.lastScreen or 0) > 15 then self:Screen(); self.lastScreen = now end
    -- Re-pick the watch list every 5 minutes (or right away while it is still empty).
    local bg = self.background
    if now - (self.lastBg or 0) > ((bg and #bg > 0) and 300 or 5) then self:RebuildBackground(); self.lastBg = now end
    local urgent = self.priority ~= nil or (self.triggers and #self.triggers > 0)
    local s = self.searching
    if s and s.needMore then
        -- A check that is upkeep does not go on to further pages while an
        -- alert waits or while you are armed: each page is another 0.65s with
        -- the radar and the alert standing still.
        if not ALERT_SRC[s.src or ""] and s.src ~= "recheck" and s.src ~= "price" and (urgent or self:SnipeMode()) then
            ns.Log("SEARCH %s: the rest of its listing is not fetched (%s)", tostring(s.key), urgent and "an alert is waiting" or "you are armed")
            self.searching, s = nil, nil
        elseif ns.Gate:Ready() and not self.buying then
            local kind = s.needMore
            s.needMore, s.more, s.at = nil, (s.more or 0) + 1, now
            ns.Gate:Use(("more results for %s (page %d)"):format(tostring(s.key), s.more + 1), "more", ALERT_SRC[s.src or ""] and "alert" or "upkeep")
            if kind == "commodity" then C_AuctionHouse.RequestMoreCommoditySearchResults(s.key)
            else C_AuctionHouse.RequestMoreItemSearchResults(s.itemKey) end
            return
        end
    end
    if ns.Scout then
        -- time the engine is actually working (auction house and panel open), for the daily report
        if self.tickAt and not ns.Gate:UserBusy() and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            ns.Scout:Online(now - self.tickAt)
            if ns.Auto then ns.Auto:Worked(now - self.tickAt) end
        end
        self.tickAt = now
    end
    if self:Busy() or not ns.Gate:Ready() then return end
    if ns.Seller and ns.Seller:Busy() then return end
    if self:Staking() then
        -- only one other request is made while a stake-out runs: its listing, once a minute, to keep the buying price current
        local st = self.stake
        local last = self.lastRows and self.lastRows[st.key]
        if not last or now - last.at > STAKE_FRESH then self:Search(st.key, "list") end
        return
    end
    local Sw = ns.Swarm
    -- a radar answer that has not been read yet: nothing of ours goes out before it is
    if Sw and Sw.active and Sw.current and Sw.current.phase == "query" then return end
    -- AN ALERT NEVER WAITS. A real log showed alerts sitting 3 to 5 seconds
    -- behind a radar read, a housekeeping query and a re-check, on a realm
    -- where deals last 2. With an alert pending, nothing else gets a turn.
    -- EVERYTHING ELSE IS UPKEEP and is sent only in the upkeep turn, after
    -- the radar has had its reads (see UpkeepTurn).
    local Se = ns.Seller
    if Se and Se.priority ~= nil then urgent = true end -- you pressed Post: its price is asked at once
    local upkeep = not urgent and self:UpkeepTurn()
    -- side classes and item upkeep take the upkeep turn in turns: a side class
    -- that is due is not kept waiting by item after item
    if upkeep and ns.upkeepLast == "item" and Sw and Sw.active and Sw.SideDue and Sw:SideDue() and not self:SnipeMode() then upkeep = false end
    -- (on the Sell tab your own auctions are what you are working on: after a
    -- cancel they are read again at once, also with a deal on screen and
    -- without waiting for the upkeep turn; elsewhere a deal comes first)
    local selling = ns.UI and ns.UI.tab == "SELL"
    local ownNow = selling and self.needOwnedNow and self.needOwned and not self:SnipeMode()
    if not urgent and not upkeep and not ownNow then return end
    if (upkeep or ownNow) and self.needOwned and C_AuctionHouse.QueryOwnedAuctions
        and (next(self.verified) == nil or selling) and not self:SnipeMode() then
        self.needOwnedNow = nil
        self.ownAskedAt = GetTime()
        self.needOwned = false
        ns.Gate:Use("list my own auctions", nil, "upkeep")
        C_AuctionHouse.QueryOwnedAuctions({})
        self:UpkeepUsed()
        return
    end
    -- an item whose details aren't loaded is skipped at no cost; try the next one
    if ns.Tuner then ns.Tuner:Balance(self.triggers and #self.triggers or 0) end
    for _ = 1, 3 do
        local key, src, waited, from, isUpkeep = self:NextCheck(upkeep)
        if not key then return end
        if self:Search(key, src, waited, from) ~= false then
            if isUpkeep then self:UpkeepUsed() end
            return
        end
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
    if f then
        -- ONE ITEM, ONE RECORD, whatever kind of deal each purchase was. (A
        -- purchase of another kind used to REPLACE the record: you hold 7 Thick
        -- Leather bought under vendor price, buy 1 as a flip, and the 7 were
        -- gone from the Sell tab: in your bags, with nothing offering to sell them.)
        local total = (f.units or 0) + units
        f.cost = floor(((f.cost or unitCost) * (f.units or 0) + spent) / total + 0.5)
        if f.kind == deal.kind then
            f.sell = deal.sell
        elseif deal.kind == "FLIP" then
            -- some of it was bought above vendor price: all of it goes to the auction house
            f.kind, f.sell = "FLIP", deal.sell
        end -- (a vendor deal added to a flip: it stays a flip, with the flip's planned price)
        f.units, f.at = total, GetServerTime()
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

-- Where your money is: gold in hand, money out of reach (auctions, unpaid
-- sales), what flips may still use, and seconds to the next pay-out.
function Sniper:Capital()
    local gold = GetMoney()
    local tied, nextIn, listed, onway, waiting = 0, nil, 0, 0, 0
    if ns.Seller and ns.Seller.Tied then tied, nextIn, listed, onway, waiting = ns.Seller:Tied() end
    -- only auctions that have not sold count against the limit: sold gold is certain
    local room = floor((gold + tied) * Deals.cfg.maxTied) - listed
    if gold + tied < Deals.cfg.smallPurse then room = gold end -- a tiny purse is not split
    return { gold = gold, tied = tied, worth = gold + tied, room = math.max(0, room), paused = Deals.cfg.flips and room <= 0,
             nextIn = nextIn, listed = listed, onway = onway, waiting = waiting }
end

-- THE BEST DEAL RIGHT NOW: the one the big Buy button acts on. It stays on a
-- purchase that has started until that purchase has an outcome.
function Sniper:Target()
    if self.buying then return self.buying.key end
    local best
    for _, d in pairs(self.verified) do
        if not best or (d.kind == "VENDOR" and best.kind ~= "VENDOR") or (d.kind == best.kind and d.profit > best.profit) then best = d end
    end
    return best and best.key
end

-- What became of the last deal you went for, shown on the panel for a few seconds.
--   kind: "won" (bought), "lost" (you clicked, it was not bought), "gone" (it left before a click)
-- It is shown three ways so there is never any doubt: on the big button, in
-- large text in the middle of the screen (the game's own message area), and
-- as a line that stays on the panel until the next outcome, with a running
-- count for the session. A different sound plays for a win and for a miss.
Sniper.tally = { won = 0, lost = 0, gone = 0 }

-- SESSION, TODAY, THIS YEAR: what you bought and what it is worth when sold
-- (the "Worth + X when sold" of each purchase, added up).
--   A session is one stretch of pressing: it starts with your first input
--   after a break of 10 minutes or more (or after logging in).
--   Today and the year are kept across reloads and log-outs.
local SESSION_GAP = 600
function Sniper:SessionTouch()
    local now = GetTime()
    local se = self.session
    if not se or now - (se.last or 0) > SESSION_GAP then
        se = { at = now, won = 0, lost = 0, gone = 0, profit = 0 }
        self.session = se
        ns.Log("SESSION started (first input after a break)")
    elseif se.last then
        -- TODAY'S CLOCK: the time of all of today's sessions, kept across
        -- reloads and log-outs. Each input adds the time since the one before.
        local t = AuctionMeshDB and AuctionMeshDB.totals
        if t and t.day then t.day.secs = (t.day.secs or 0) + (now - se.last) end
    end
    se.last = now
    return se
end
local function dayId() return tonumber(date("%Y%m%d", GetServerTime())) or 0 end
local function yearId() return tonumber(date("%Y", GetServerTime())) or 0 end
-- The two kept totals, made new when the day or the year turns. The first
-- time, they are filled from the journal of your trades.
function Sniper:Totals()
    local db = AuctionMeshDB
    local t = db.totals
    local d, y = dayId(), yearId()
    if not t then
        t = { day = { id = d, n = 0, profit = 0 }, year = { id = y, n = 0, profit = 0 } }
        db.totals = t
        local cut = 1 - Deals.cfg.cut
        for _, tr in ipairs((ns.Journal and ns.Journal.list) or {}) do
            if tr.at and tr.cost and tr.plan and (tr.qty or 0) > 0 then
                local each = (tr.kind == "VENDOR") and (tr.plan - tr.cost) or (floor(tr.plan * cut) - tr.cost)
                local p = math.max(0, each) * tr.qty
                if tonumber(date("%Y", tr.at)) == y then t.year.n, t.year.profit = t.year.n + 1, t.year.profit + p end
                if tonumber(date("%Y%m%d", tr.at)) == d then t.day.n, t.day.profit = t.day.n + 1, t.day.profit + p end
            end
        end
    end
    if t.day.id ~= d then t.day = { id = d, n = 0, profit = 0 } end
    if t.year.id ~= y then t.year = { id = y, n = 0, profit = 0 } end
    return t
end
-- A purchase went through: its worth is added to the session, the day and the year.
function Sniper:CountPurchase(profit)
    profit = math.max(0, profit or 0)
    local t = self:Totals()
    t.day.n, t.day.profit = t.day.n + 1, t.day.profit + profit
    t.year.n, t.year.profit = t.year.n + 1, t.year.profit + profit
    local se = self.session
    if se then se.profit = se.profit + profit end
end

local FLASH = { won = { 0.2, 1, 0.4 }, lost = { 1, 0.25, 0.25 }, gone = { 1, 0.6, 0.25 } }
function Sniper:Result(kind, key, text, lasted)
    self.result = { kind = kind, key = key, text = text, at = GetTime() }
    self.tally[kind] = (self.tally[kind] or 0) + 1
    if self.session and self.session[kind] then self.session[kind] = self.session[kind] + 1 end
    local rec
    do  -- kept for the snapshot: the last outcomes, how fast the input came and what it was
        local list = AuctionMeshDB.outcomes or {}
        AuctionMeshDB.outcomes = list
        local r = self.react
        local mine = r and r.key == key and kind ~= "gone"
        rec = { t = GetServerTime(), k = kind, r = mine and r.secs or nil, v = mine and r.via or nil, key = key,
                g = kind == "gone" and lasted or nil, -- how long a deal nobody pressed for was there
                m = (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) }
        list[#list + 1] = rec
        while #list > 40 do table.remove(list, 1) end
        if mine then self.react = nil end
    end
    ns.Log("RESULT %s: %s", kind, text)
    do  -- how this try went, in time (kept with the outcome, for the snapshot)
        local ti = self.tryInfo
        if ti and ti.key == key and kind ~= "gone" then
            -- the same, kept with the outcome. All in seconds: i = the deal
            -- showing to your input, h = the game holding the price request
            -- for its lock, q = your input to the price answer, e = the deal
            -- showing to the end (bought, or the server saying it is gone).
            rec.i, rec.h, rec.q, rec.e = ti.input or 0, ti.held, ti.quote, (ti.input or 0) + (GetTime() - ti.t0)
            -- IN TIME: the game held the price request for its lock (it could not
            -- have left sooner), or the input came inside the window anyway.
            -- LATE: the lock was already open when the input came.
            local window = (ns.UI and ns.UI.PaceWindow and ns.UI.PaceWindow()) or 0.49
            local late = (not ti.held) and (ti.input or 0) > window
            self.tally.inTime = (self.tally.inTime or 0) + (late and 0 or 1)
            self.tally.late = (self.tally.late or 0) + (late and 1 or 0)
            self.lastTry = { key = key, kind = kind, input = ti.input, held = ti.held, quote = ti.quote, total = GetTime() - ti.t0, at = GetTime(), via = ti.via, late = late }
            self.tryInfo = nil
            ns.Log("TRY %s %s: input %s after the deal, price request held %s for the lock, price back after %s, over after %.2fs", tostring(key), kind,
                ti.input and ("%.2fs"):format(ti.input) or "?", ti.held and ("%.2fs"):format(ti.held) or "0s",
                ti.quote and ("%.2fs"):format(ti.quote) or "never", GetTime() - ti.t0)
        end
    end
    if PlaySound then pcall(PlaySound, kind == "won" and 120 or 847) end
    -- A purchase is announced in the middle of the screen. A miss is not any
    -- more: the whole panel flashes red instead (green for a purchase), and
    -- the line under the snipe box keeps what happened.
    if kind == "won" and UIErrorsFrame and UIErrorsFrame.AddMessage then
        local c = FLASH[kind] or FLASH.gone
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "AuctionMesh: " .. text, c[1], c[2], c[3])
    end
    if ns.UI and ns.UI.Flash then ns.UI:Flash(kind, key, text) end
    ns.Gate.holdUntil = nil
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
end

-- The game refused a purchase that was not sent from a click: back to two inputs.
function Sniper:AutoBlocked()
    AuctionMeshDB.cfg.autoConfirm = false
    local b = self.buying
    if b and b.auto and b.phase == "wait" then b.phase, b.auto = "confirm", nil end -- your next click or wheel notch confirms
    ns.Log("AUTO confirm is blocked by the game: switched off; a second click (or a wheel flick) confirms")
    if ns.UI then
        ns.UI:Notice("The game requires a second input to buy. Flick the mouse wheel or click again: BUY NOW.", true)
        if ns.UI.Now then ns.UI:Now() end
    end
end

-- The game blocked the price request or the purchase that an input just
-- sent (it does not count that input as a real one). Nothing left the
-- client, so the purchase is dropped at once and the deal stays where it
-- is: the next input that works buys it. (A real log: with "hold a key"
-- each blocked request left the deal frozen for four seconds, until the
-- wait for a price that was never asked ran out.)
function Sniper:InputRefused()
    local b = self.buying
    if not b or GetTime() - (b.at or 0) > 0.5 then return end
    if b.phase == "quote" then
        self.buying = nil
        if b.stake and self.stake then self.stake.asked = math.max(0, (self.stake.asked or 1) - 1) end
        ns.Log("PURCHASE of %s dropped: the game blocked the input that sent it; the deal stays on screen", tostring(b.key))
    elseif b.phase == "wait" and not b.auto then
        b.phase = "confirm" -- the price is still locked in: the next input buys
    else
        return
    end
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
end

-- EVERY click on a deal's Buy button comes here. It is safe to spam: a click
-- always does the next useful thing, and a click that has nothing to do yet
-- (the price is on its way, the purchase is being confirmed) is simply ignored.
function Sniper:Press(key)
    key = key or self:Target()
    if not key then return end
    local b = self.buying
    if b then
        -- the price is in: this click is the purchase. If the auction house is
        -- inside its half-second lock, the game itself holds the message and
        -- sends it the moment the lock opens.
        if b.key == key and b.phase == "confirm" then self:Confirm() end
        return
    end
    return self:Buy(key)
end

-- True when the next click on this deal buys it (price locked in, server ready).
function Sniper:OneClick(key)
    local b = self.buying
    return b ~= nil and b.key == key and b.phase == "confirm"
end

function Sniper:Buy(key)
    local deal = self.verified[key]
    if not deal or self.buying then return end
    if GetTime() - deal.at > VERIFIED_TTL then
        self.priority, self.verified[key] = key, nil
        say("That deal is being re-checked; it will reappear if it is still good.")
        return dirty()
    end
    -- THE CLICK GOES STRAIGHT TO THE SERVER. This game only accepts a price
    -- request that comes directly from a click; holding the click and sending
    -- it a moment later (which this addon used to do when the auction house
    -- was busy) is blocked by the game, so those clicks were lost. If the
    -- auction house is busy the game queues the message itself.
    do  -- how long after the deal appeared this input came, and what it was (wheel, key, hold, click)
        local seen = self.dealSeen and self.dealSeen[key]
        local via = self.inputVia or "click"
        if via ~= "click" and not (self.inputAt and GetTime() - self.inputAt < 0.05) then via = "click" end
        if not (self.react and self.react.key == key) then -- a retry for the units left keeps the first reaction time
            self.react = { key = key, secs = seen and (GetTime() - seen) or nil, via = via }
        end
        if via ~= "click" then self.tally.wheel = (self.tally.wheel or 0) + 1 end
        -- THE TIMING OF THIS TRY, for the panel: when the input came, how long
        -- the game held the price request for its lock, when the price was
        -- back, when it was over.
        self.tryInfo = { key = key, t0 = GetTime(), input = seen and (GetTime() - seen) or nil, via = via }
    end
    if deal.commodity then
        self.buying = { key = key, units = deal.units, max = deal.cost, phase = "quote", deal = deal, at = GetTime() }
        ns.Gate:Use(("buy start %dx %s, verified total %d"):format(deal.units, tostring(key), deal.cost), nil, "buy")
        -- an error in the next seconds answers this price request: it is not the server pushing back on the pace
        ns.Gate.ignoreErrorUntil = math.max(ns.Gate.ignoreErrorUntil or 0, GetTime() + 2)
        self.inputCallAt = GetTime()
        C_AuctionHouse.StartCommoditiesPurchase(key, deal.units)
    else
        local row, n = deal.buys[1], deal.counts[1]
        if not row or not row.id then self.verified[key] = nil; return dirty() end
        if row.buyout > GetMoney() then say("Not enough gold for that listing."); return end
        table.remove(deal.buys, 1); table.remove(deal.counts, 1)
        ns.Gate:Use(("buyout auction %s of %s for %d"):format(tostring(row.id), tostring(key), row.buyout), nil, "buy")
        self.buying = { key = key, units = n, total = row.buyout, phase = "wait", deal = deal, at = GetTime(),
                        auctionID = row.id, moneyBefore = GetMoney(), item = true, vendor = row.vendor }
        C_AuctionHouse.PlaceBid(row.id, row.buyout)
    end
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
    -- A price that has not come back in 4 seconds is not coming (an answer
    -- takes 0.15s once the request has left): the deal is checked again
    -- instead of everything standing still for 10 seconds.
    self:ArmPurchaseTimeout(deal.commodity and 4 or nil)
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
            ns.Gate.holdUntil = nil
            dirty()
        end
    end)
end

function Sniper:Confirm()
    local b = self.buying
    if not b or b.phase ~= "confirm" then return end
    b.phase, b.moneyBefore, b.at = "wait", GetMoney(), GetTime()
    self:ArmPurchaseTimeout()
    if not b.auto then self.inputCallAt = GetTime() end -- sent from your input (a blocked one is traced to it)
    ns.Gate:Use(("buy confirm %dx %s total %s"):format(b.units, tostring(b.key), tostring(b.total)), nil, "buy")
    -- An error in the next seconds belongs to this purchase (someone else got
    -- the units first), not to the pace of requests. A real log showed it being
    -- read as "the server refused a request": the radar stopped for 5 seconds
    -- after each of two failed purchases, and the pause between all requests
    -- was raised from 0 to 0.5 seconds, so the radar read every 1.13 seconds
    -- instead of every 0.70 from then on.
    ns.Gate.ignoreErrorUntil = GetTime() + 4
    C_AuctionHouse.ConfirmCommoditiesPurchase(b.key, b.units)
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
end

-- WHAT IS LEFT. The server's quote is higher than the deal expected, so some
-- of the cheap units are gone. They are always taken cheapest first, so the
-- quote says exactly how many: it is the cost of the same number of units
-- with the first j units of the price ladder removed. Find that j, and the
-- deal becomes "the cheap units that are still there" instead of a miss.
-- (In a real log 24 Wool Cloth at 1s were on offer, the quote for 16 came back
-- as 6 x 1s00c + 10 x 1s48c, and the addon reported MISSED with 6 still there.)
-- Returns units left, their cost, and the ladder without the units that went.
function Sniper.Remaining(deal, units, total)
    local rows = deal.rows
    if not rows and deal.instant and deal.next and units > 0 then
        -- a radar deal has no listing: its ladder is "N at the new price, then the old cheapest price"
        rows = { { price = floor(deal.cost / units), qty = units }, { price = deal.next, qty = 1e6 } }
    end
    if not rows or units <= 0 then return nil end
    -- cost of `n` units after skipping the `j` cheapest; nil if the ladder is too short
    local function costFrom(j, n)
        local c = 0
        for i = 1, #rows do
            local q = rows[i].qty
            if j >= q then j = j - q else
                local take = min(q - j, n)
                c, n, j = c + take * rows[i].price, n - take, 0
                if n == 0 then return c end
            end
        end
        return nil
    end
    -- the dearest unit the deal meant to buy
    local pmax, seen = rows[1].price, 0
    for i = 1, #rows do
        seen = seen + rows[i].qty
        pmax = rows[i].price
        if seen >= units then break end
    end
    -- as many as all the cheap units may have gone (the cheap pile can be bigger than what the deal meant to buy)
    local cheap = 0
    for i = 1, #rows do if rows[i].price <= pmax then cheap = cheap + rows[i].qty end end
    for j = 1, min(cheap, 100000) do
        local c = costFrom(j, units)
        if not c then return nil end
        if c == total then
            local left, cost, skip, ladder = 0, 0, j, {}
            for i = 1, #rows do
                local q = rows[i].qty
                if skip >= q then skip = skip - q else
                    q = q - skip; skip = 0
                    ladder[#ladder + 1] = { price = rows[i].price, qty = q }
                    if rows[i].price <= pmax and left < units then
                        local take = min(q, units - left)
                        left, cost = left + take, cost + take * rows[i].price
                    end
                end
            end
            return left, cost, ladder
        elseif c > total then
            return nil -- the quote fits no number of missing units: the listing changed in some other way
        end
    end
    return nil
end

-- ABOUT HOW MANY ARE LEFT. When the quote fits no exact number of missing
-- units (the listing changed in other ways too: new auctions appeared), the
-- quote still says roughly how many cheap units remain: every cheap unit in
-- it saves (dear price - cheap price). The deal is offered again for that
-- many, priced at the dearest cheap unit; the server's quote for THAT request
-- is what decides, so a wrong estimate costs one request and nothing else.
-- A second miss on an estimated deal halves it.
-- (A real log: 31 Silk Cloth at 1s00c-1s07c, clicked 6 seconds late; the quote
-- came back at 1s64c each, i.e. about 10 were still there. It was reported
-- MISSED, the next two tries missed the same way and the item was muted.)
-- Returns units to try, the most they may cost, and a two-step ladder.
function Sniper.Estimate(deal, units, total)
    if units <= 1 then return nil end
    if deal.guess then
        local n = floor(units / 2)
        if n < 1 then return nil end
        local p = deal.rows and deal.rows[1] and deal.rows[1].price or floor(deal.cost / units)
        return n, n * p, { { price = p, qty = n }, deal.rows and deal.rows[2] or nil }
    end
    local rows = deal.rows
    if not rows and deal.instant and deal.next then
        rows = { { price = floor(deal.cost / units), qty = units }, { price = deal.next, qty = 1e6 } }
    end
    if not rows then return nil end
    local pmax, seen, hi = rows[1].price, 0, nil
    for i = 1, #rows do
        if seen >= units then hi = rows[i].price; break end
        seen = seen + rows[i].qty
        pmax = rows[i].price
    end
    if not hi or hi <= pmax then hi = deal.hi end -- the ladder ends at the cheap units: use the market's wall
    if not hi or hi <= pmax then
        -- nothing says what a dear unit costs: try half, the server decides
        local n = floor(units / 2)
        if n < 1 then return nil end
        return n, n * pmax, { { price = pmax, qty = n } }
    end
    local avg = deal.cost / units
    local n = floor((units * hi - total) / (hi - avg))
    n = min(n, units - 1)
    if n < 1 then return nil end
    return n, n * pmax, { { price = pmax, qty = n }, { price = hi, qty = 1e6 } }
end

-- Deals of an item that keep being taken before a click can land are not
-- worth the attention (or the seconds the radar stays quiet for them).
-- Five misses in a row mutes the item for 3 minutes. (It was three misses and
-- ten minutes, which shut out the item that paid best in a real session.)
function Sniper:Muted(key)
    local m = self.muted and self.muted[key]
    return m ~= nil and GetTime() < m
end

function Sniper:OnPriceQuote(unitPrice, total)
    local b = self.buying
    if not b or b.phase ~= "quote" then return end
    ns.Log("QUOTE %s: %s total vs verified %s", tostring(b.key), tostring(total), tostring(b.max))
    do
        local ti = self.tryInfo
        if ti and ti.key == b.key and not ti.quote then ti.quote = GetTime() - ti.t0 end
    end
    if b.stake then
        -- a stake-out's price request: buy if it is low enough, otherwise ask again on the next notch
        local st = self.stake
        if st then st.lastPrice, st.lastAt = (b.units > 0 and floor(total / b.units + 0.5)) or unitPrice, GetTime() end
        local cheap = total <= b.max and total <= GetMoney()
        -- more than one unit asked for: every one must be at the price just paid, so no dear unit is bought with them
        if cheap and b.units > 1 and not (st and st.cheap and total <= b.units * st.cheap) then cheap = false end
        if not cheap then
            if st then st.q, st.cheap = 1, nil end
            self.buying = nil
            return dirty()
        end
    end
    if total <= b.max and total <= GetMoney() then
        b.phase, b.total, b.at = "confirm", total, GetTime()
        self:ArmPurchaseTimeout(25) -- time to press Buy again before the price is dropped
        -- ONE CLICK, IF THE GAME ALLOWS IT. You clicked Buy on this deal and the
        -- server's price is what the deal showed (or less), so the purchase is
        -- sent straight away instead of waiting for a second click. Whether the
        -- game accepts a purchase that is not sent from a click is not known
        -- for this client: it is tried once. If the game blocks it, this is
        -- switched off for good and the second click (or a flick of the mouse
        -- wheel) confirms, as before.
        if AuctionMeshDB.cfg.autoConfirm ~= false then
            self.autoAt = GetTime()
            b.auto = true
            AuctionMeshDB.cfg.autoTried = true
            ns.Log("AUTO confirm: the quote matches the deal you clicked; sending the purchase without waiting for a second click")
            self:Confirm()
        end
    else
        ns.Log("QUOTE MISMATCH %s: wanted %d units; deal was built at %s", tostring(b.key), b.units, tostring(b.deal.rowsText))
        -- Are some of the cheap units still there? Then that is the deal now.
        local left, leftCost, ladder = Sniper.Remaining(b.deal, b.units, total)
        local guess = false
        if not (left and left > 0 and left < b.units) then
            left, leftCost, ladder = Sniper.Estimate(b.deal, b.units, total)
            guess = left ~= nil
        end
        if left and left > 0 and left < b.units then
            local d = {}
            for k2, v2 in pairs(b.deal) do d[k2] = v2 end
            d.units, d.cost, d.rows, d.at, d.leftOf = left, leftCost, ladder, GetTime(), b.deal.leftOf or b.units
            d.guess = guess or nil
            d.rowsText = ladder and self.RowsText(ladder) or d.rowsText
            if d.kind == "VENDOR" then
                d.profit = left * d.sell - leftCost
            else
                d.profit = left * floor(d.sell * (1 - Deals.cfg.cut)) - leftCost - (Deals.cfg.depositIsCost and (d.deposit or 0) or 0)
            end
            if d.instant then d.at = GetTime() - VERIFIED_TTL + 8 end
            local need = d.kind == "VENDOR" and 10 or self:CfgFor(b.key).minProfit
            if d.profit >= need and leftCost <= GetMoney() then
                ns.Log("QUOTE says %s%d of the %d cheap units are still there (cost %s%d, profit %d): offered again at once",
                    guess and "about " or "", left, b.units, guess and "at most " or "", leftCost, d.profit)
                ns.Gate.ignoreErrorUntil = GetTime() + 2
                C_Timer.After(0.4, function() if not Sniper.buying then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end end)
                d.born = GetTime()
                self.verified[b.key] = d
                self.buying = nil
                if Sniper.hold > 0 then ns.Gate.holdUntil = GetTime() + Sniper:HoldFor() end
                if ns.UI then ns.UI:Notice(("Someone took some of them. %s%s%d are still there: keep rolling, or click Buy again.|r"):format("|cff33ff66", guess and "About " or "", left), true) end
                if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
                return
            end
        end
        -- The quote is higher than the listing showed: someone else bought the
        -- cheap units first. The listing itself can go on showing them for a
        -- moment after they are gone (a real log showed 26, then 6, units
        -- "listed" at a price the server would no longer sell at), so the same
        -- deal must not pop up again straight away, and nothing is concluded
        -- about your own auctions: those are known from the server's own list.
        local low = b.deal.rows and b.deal.rows[1] and b.deal.rows[1].price or (b.deal.units > 0 and floor(b.deal.cost / b.deal.units)) or 0
        self.cool = self.cool or {}
        -- Missing the same units again and again means they really cannot be
        -- bought by you: each repeat waits four times longer (4s, 16s, 64s, ... 10 min).
        local was = self.cool[b.key]
        local n = (was and was.price == low and GetTime() - was.at < 900) and (was.n + 1) or 1
        local wait = min(600, MISS_COOL * 4 ^ (n - 1))
        self.cool[b.key] = { price = low, till = GetTime() + wait, at = GetTime(), n = n }
        ns.Log("QUOTE says real total %d; units at %d or less are ignored for %ds (miss %d at this price)", total, low, wait, n)
        ns.Gate.ignoreErrorUntil = GetTime() + 2 -- our own cancel is not a server problem
        -- Cancel a moment later: cancelling inside the quote event makes the game show "Internal Auction Error".
        C_Timer.After(0.4, function() if not Sniper.buying then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end end)
        say(("|cffff8040Nothing bought, nothing spent.|r Someone was faster: %d x %s now costs %s (the listing showed %s).")
            :format(b.units, nameOf(b.key), plain(total), plain(b.deal.cost)))
        self.verified[b.key] = nil
        self.checkedAt[b.key] = GetTime() - TRIGGER_MIN + min(TRIGGER_MIN, self.cool[b.key].till - GetTime()) -- the radar may raise it again once the cooldown is over
        if self.judged then self.judged[b.key] = nil end -- and it is then looked at afresh
        self.buying = nil
        if self.dealSeen then self.dealSeen[b.key] = nil end
        self.streak = self.streak or {}
        self.streak[b.key] = (self.streak[b.key] or 0) + 1
        local muted = ""
        if self.streak[b.key] >= 5 then
            self.muted = self.muted or {}
            self.muted[b.key] = GetTime() + 180
            self.streak[b.key] = 0
            muted = " Fifth miss in a row on this item: it is not shown for 3 minutes."
            ns.Log("MUTED %s for 3 minutes: five misses in a row", tostring(b.key))
        end
        self:Result("lost", b.key, ("MISSED  %s: someone was faster. It now costs %s for %d. Nothing spent.%s"):format(nameOf(b.key), plain(total), b.units, muted))
    end
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
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
        if ns.Gold then ns.Gold:Cause(("Bought %d x %s"):format(b.units, nameOf(b.key)), -1) end -- (for the Chart tab's swings)
        if self.dealSeen then self.dealSeen[b.key] = nil end
        if self.streak then self.streak[b.key] = 0 end
        if b.stake then
            -- the profit at the price really paid, and the next request asks for twice as many at that price
            b.deal.profit = b.deal.kind == "VENDOR" and (b.units * b.deal.sell - spent) or (b.units * floor(b.deal.sell * (1 - Deals.cfg.cut)) - spent)
            b.deal.units = b.units
            local st = self.stake
            if st then
                st.bought = st.bought + b.units
                self:StakeRecord(b.key, 0, b.units)
                st.cheap = floor(spent / math.max(1, b.units) + 0.5)
                st.q = min((st.q or 1) * 2, STAKE_CAP)
            end
        end
        local worth = math.max(0, floor((b.deal.profit or 0) * b.units / math.max(1, b.deal.units or b.units)))
        self:CountPurchase(worth)
        self:Result("won", b.key, ("GOT IT  %d x %s for %s. Worth + %s when sold."):format(b.units, nameOf(b.key), plain(spent), plain(worth)))
        self.bought[b.key] = (self.bought[b.key] or 0) + b.units
        if b.item then
            b.deal.units, b.deal.cost = b.deal.units - b.units, b.deal.cost - (b.total or 0)
            if #b.deal.buys > 0 then self.buying = nil; return dirty() end -- more listings in this deal
        end
    else
        ns.Log("PURCHASE FAILED %s: %s", tostring(b.key), tostring(why))
        ns.Gate.ignoreErrorUntil = GetTime() + 3 -- the game's error message for it follows; it is not about pace
        if ns.Scout then ns.Scout:Fail(b.key, why) end
        if self.dealSeen then self.dealSeen[b.key] = nil end
        say(("|cffff4040Purchase NOT completed:|r %s (%s). Nothing was recorded."):format(nameOf(b.key), why or "refused"))
        self:Result("lost", b.key, ("MISSED  %s: %s. Nothing spent."):format(nameOf(b.key),
            (why == "price no longer available" or why == "server refused the purchase") and "someone was faster" or tostring(why or "refused")))
    end
    self.verified[b.key] = nil
    if self.judged then self.judged[b.key] = nil end -- the radar may raise this item again at once
    if b.stake then
        if not ok and self.stake then self.stake.q, self.stake.cheap = 1, nil end
    elseif ok and (b.item or b.deal.more or b.deal.partial or b.deal.leftOf or b.deal.guess) then
        self.priority = b.key -- re-check: cheap units may be left
    elseif ok then
        -- Everything the deal showed was bought. The re-check that used to
        -- follow cost a request (0.65s with the radar standing still after
        -- every purchase); the radar's next read sees the item anyway and
        -- raises it again at once if it is still cheap.
        self.checkedAt[b.key] = nil
    else
        -- Refused: someone else got the units. The listing can go on showing
        -- them for a moment, so they are left alone for a few seconds (as
        -- after a missed price) instead of being checked and offered again.
        local d = b.deal
        local low = d.rows and d.rows[1] and d.rows[1].price or (d.units and d.units > 0 and floor(d.cost / d.units)) or 0
        self.cool = self.cool or {}
        local was = self.cool[b.key]
        local n = (was and was.price == low and GetTime() - was.at < 900) and (was.n + 1) or 1
        local wait = min(600, MISS_COOL * 4 ^ (n - 1))
        self.cool[b.key] = { price = low, till = GetTime() + wait, at = GetTime(), n = n }
        self.checkedAt[b.key] = GetTime() - TRIGGER_MIN + min(TRIGGER_MIN, wait)
    end
    self.buying = nil
    ns.Gate.holdUntil = nil
    if ns.UI and ns.UI.Now then ns.UI:Now() else dirty() end
end

-- Your own active auctions, straight from the server. Used so your own
-- listings are never mistaken for deals.
function Sniper:ReadOwned()
    local AH, own, n = C_AuctionHouse, {}, 0
    local ids = {} -- key -> { { id, qty, price, ends } }: each active auction, so one can be cancelled
    local total = AH.GetNumOwnedAuctions and AH.GetNumOwnedAuctions() or 0
    -- A LIST THAT CANNOT BE RIGHT IS NOT BELIEVED. Right after a cancel the game
    -- says "your auctions changed" while its own list is empty or half loaded.
    -- Believing that made every other auction look ended: on the Sell tab they
    -- left UNDERCUT, lost their Cancel buttons and showed up under "ended,
    -- check a mailbox". So: a list the game says is not complete, or an empty
    -- one that is not the answer to our own request while auctions were known
    -- a moment ago, is left unread and asked for again.
    do
        local partial = AH.HasFullOwnedAuctionResults and AH.HasFullOwnedAuctionResults() == false
        local known = 0
        for _, list in pairs(self.ownIds or {}) do
            for _, a in ipairs(list) do if not a.gone then known = known + 1 end end -- (one you have just cancelled is not expected back)
        end
        -- (the answer to our own request is always believed, whatever it says: a
        -- list is doubted once, never in a loop)
        local answer = self.ownAskedAt and GetTime() - self.ownAskedAt < 5
        if not answer and (partial or (total == 0 and known > 0)) then
            ns.Log("OWNED: a %s list of your auctions is not believed (%d listed by the game, %d known a moment ago): asked for again",
                partial and "partial" or "sudden empty", total, known)
            self.needOwned, self.needOwnedNow = true, true
            return
        end
    end
    local soldRows, soldQty, rowsLog = 0, {}, {}
    local soldPay = {}
    for i = 1, total do
        local a = AH.GetOwnedAuctionInfo(i)
        if a and #rowsLog < 8 then
            rowsLog[#rowsLog + 1] = ("[item=%s status=%s qty=%s buyout=%s bid=%s left=%s]"):format(tostring(a.itemKey and a.itemKey.itemID), tostring(a.status),
                tostring(a.quantity), tostring(a.buyoutAmount), tostring(a.bidAmount), tostring(a.timeLeftSeconds))
        end
        local sold = a and Enum.AuctionStatus and a.status == Enum.AuctionStatus.Sold
        if sold then
            soldRows = soldRows + 1
            -- SOLD, WAITING TO BE PAID: the game lists these itself (its Auctions
            -- tab shows them as gold coming in). Read here so the panel's total
            -- agrees with the game without a trip to the mailbox.
            -- For a sold row the server gives the whole amount paid (seen in a
            -- real log: 10 sold at 172 each is listed as 1720) and the seconds
            -- until it is paid out.
            if a.itemKey then soldQty[a.itemKey.itemID] = (soldQty[a.itemKey.itemID] or 0) + (a.quantity or 1) end
            soldPay[#soldPay + 1] = { amount = floor((a.buyoutAmount or 0) * (1 - Deals.cfg.cut)), due = GetTime() + (a.timeLeftSeconds or 3600),
                                      key = a.itemKey and a.itemKey.itemID or nil }
        end
        if a and a.itemKey and not sold then
            local id = a.itemKey.itemID
            local price = a.buyoutAmount or a.bidAmount or 0
            own[id] = own[id] or {}
            own[id][price] = (own[id][price] or 0) + (a.quantity or 1)
            ids[id] = ids[id] or {}
            ids[id][#ids[id] + 1] = { id = a.auctionID, qty = a.quantity or 1, price = price,
                                      ends = a.timeLeftSeconds and (GetTime() + a.timeLeftSeconds) or nil }
            n = n + 1
        end
    end
    do  -- for the Chart tab: what has newly sold is cash from this moment, and is named on the chart
        local prev, names, more = self.ownSoldQty or {}, {}, 0
        for key, q in pairs(soldQty) do
            if q > (prev[key] or 0) then
                if #names < 3 then names[#names + 1] = ("Sold %d x %s (auction)"):format(q - (prev[key] or 0), nameOf(key)) else more = more + 1 end
            end
        end
        if ns.Gold and #names > 0 then
            for _, w in ipairs(names) do ns.Gold:Cause(w, 1) end
        end
    end
    self.ownSold, self.ownSoldQty = soldRows, soldQty
    self.ownSoldPay = soldPay -- { amount after the cut, due = when it is paid out }
    if ns.Gold then ns.Gold:OnMoney() end -- (what has sold is part of your cash: the record follows)
    ns.Log("OWNED: the server lists %d of your auctions (%d active, %d sold and waiting to be paid) %s", total, n, soldRows, table.concat(rowsLog, " "))
    self.own, self.ownRead = own, true
    self.ownIds, self.ownAt = ids, GetTime()
    -- Deals built before we knew about them are re-checked.
    for k in pairs(self.verified) do if own[k] then self.verified[k] = nil; self.checkedAt[k] = nil end end
    dirty()
end

---------------------------------------------------------------- lifecycle

function Sniper:Start()
    if ns.Dormant and ns.Dormant() then return end -- switched off on this character (it is not the bank alt)
    self.active = true
    self.checkedAt = {} -- new AH visit: everything may have changed
    self.ownRead = false
    self.sweep, self.triggers = {}, {}
    self.wide = {}
    self.ownSweep, self.judged = {}, {}
    -- listings remembered from the last visit: the radar has not been watching them since
    for _, lr in pairs(self.lastRows or {}) do lr.broken = true end
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
