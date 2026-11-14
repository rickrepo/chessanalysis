-- AuctionMesh Deals: pure profit math (no WoW API calls, so it is unit-tested).
--
-- Two kinds of deal, checked against the item's LIVE listings:
--
--   SAFE (vendor)  Listed below what an NPC vendor pays. Guaranteed profit,
--                  no AH cut, no deposit, no waiting for a buyer.
--
--   FLIP (resale)  A few units listed far below the real market. Rules, all
--                  of which must hold (each one exists because breaking it
--                  loses money):
--     1. Stackable goods only. Gear varies by item level and can't be compared.
--     2. There is a "wall": at least `depthUnits` units, in at least 2 price
--        rows, listed within 25% of each other. That is the real market price.
--        One lonely expensive listing is NOT a market price.
--     3. We buy EVERY unit below our resale price. If cheap units would
--        remain, they undercut us and ours never sell. Exception: when the
--        whole cheap pile is at most 10% of the market, a small purse may buy
--        part of it; the few leftovers get bought up quickly.
--     4. What we buy is at most `share` (50%) of the wall's size: outliers
--        only, never a market that simply is cheap.
--     5. One item never takes more than `maxSpend` (50%) of our gold (all of it while under 1g).
--     6. Profit after the 5% AH cut and the deposit is at least `margin` (20%).
--     9. Never goods that NPC vendors sell in unlimited supply.
--    12. Learned: finished flips (ours and friends') scale the planned price
--        and put an item that failed to sell on hold (see Learn.lua).
--    11. Trend: the price history database must not show the market price in
--        free fall (10% or more in ~6h); a slower decline lowers the planned
--        resale price by the same amount.
--    10. Liquidity: the item must have been SEEN selling (units leaving the
--        cheap end of the listing between two readings), fast enough that
--        what we buy sells within `maxSellMinutes`.
--     7. If we have market-price history, the resale price is capped by its average.
--     8. If real sales are on record (sale invoices, ours or friends'), the
--        resale price is capped by what buyers actually paid.
--
-- All amounts are copper.
local _, ns = ...
ns = ns or {}

local Deals = {}
ns.Deals = Deals

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

Deals.cfg = {
    margin = 0.20,        -- FLIP: profit must be >= 20% of what we pay (after cut and deposit)
    vendorMargin = 0.10,  -- SAFE: guaranteed, so 10% is enough
    minProfit = 50,       -- ignore deals that make less than this in total (set in the window)
    cut = 0.05,           -- auction house cut on sales
    undercut = 1,         -- we list this far under the competition
    step = 1,             -- smallest price unit the AH accepts (Core sets 100 if copper is rejected)
    band = 1.25,          -- wall = listings within 25% of each other
    depthUnits = 10,      -- wall needs at least this many units...
    depthRows = 2,        -- ...in at least this many price rows
    share = 0.50,         -- we buy at most half of the wall's size
    partialShare = 0.10,  -- a pile this small vs the market may be bought in part
    maxSpend = 0.5,       -- at most half our gold on one flip
    minSamples = 4,       -- average needs this many samples before we trust it
    fairMaxAge = 20 * 60, -- a wall price older than this is re-checked
    maxAge = 30 * 60,     -- only consider lowest prices seen in the last 30 min
    screenRatio = 0.6,    -- screening: lowest price must be <= 60% of the reference
    flips = true,         -- false = SAFE deals only
    depositIsCost = false,-- true = count the posting fee as lost (pessimistic)
    requireTurnover = true, -- flips only on items we have SEEN selling
    maxSellMinutes = 60,  -- what we buy must sell within this time at the measured rate
    trendSkip = 0.10,     -- market price fell this much in ~6h: no flips on that item
}

-- Round down to a price the auction house accepts.
function Deals.round(p, cfg)
    local s = (cfg or Deals.cfg).step
    return floor(p / s) * s
end

-- Lowest unit price that still makes 1c after the AH cut (pass cost + deposit).
function Deals.breakEven(cost, cfg)
    cfg = cfg or Deals.cfg
    local s = cfg.step
    local p = ceil((cost + 1) / (1 - cfg.cut))
    return ceil(p / s) * s
end

-- Finds the wall: first row i >= 2 where rows i.. within `band` hold enough depth.
-- Returns index, price, units in the wall band (or nil).
function Deals.wall(rows, cfg)
    cfg = cfg or Deals.cfg
    for i = 2, #rows do
        local limit, units, nrows = rows[i].price * cfg.band, 0, 0
        for j = i, #rows do
            if rows[j].price > limit then break end
            units, nrows = units + rows[j].qty, nrows + 1
        end
        if units >= cfg.depthUnits and nrows >= cfg.depthRows then return i, rows[i].price, units end
    end
end

local function vendorDeal(rows, o, cfg)
    local left, units, cost, profit = o.budget, 0, 0, 0
    local buys, counts, sell = {}, {}, 0
    for i = 1, #rows do
        local r = rows[i]
        local v = r.vendor or o.vendor or 0
        local ok = v > 0 and r.price <= floor(v / (1 + cfg.vendorMargin))
        if ok then
            local n, spend
            if r.whole then
                spend = r.buyout or r.qty * r.price
                n = (spend <= left) and r.qty or 0
            else
                n = min(r.qty, floor(left / r.price))
                spend = n * r.price
            end
            if n > 0 then
                units, cost, profit, left = units + n, cost + spend, profit + n * v - spend, left - spend
                buys[#buys + 1], counts[#counts + 1] = r, n
                sell = v
            end
            if not r.whole and n < r.qty then break end -- out of gold
        elseif not r.whole then
            break -- commodity rows are sorted and share one vendor price
        end
    end
    if units == 0 then return nil end
    if profit < cfg.minProfit then
        return nil, ("vendor profit $%d is under your $%d minimum"):format(profit, cfg.minProfit)
    end
    return { kind = "VENDOR", units = units, cost = cost, deposit = 0, profit = profit, sell = sell,
             buys = buys, counts = counts }
end

-- Returns deal, wall, reason (reason = plain words when there is no deal).
--
-- The posting fee (deposit): the game takes it when you list and gives it back
-- when the item sells; it is lost only if the auction expires or is cancelled.
-- So it is not subtracted from profit, but you must HAVE it: it is kept back
-- from what you can spend. o.deposit is the fee per unit (may be a fraction),
-- o.depositMin the smallest fee for one posting. cfg.depositIsCost = true
-- switches to the pessimistic view (fee counted as lost).
local function flipDeal(rows, o, cfg)
    local wi, wall, depth = Deals.wall(rows, cfg)
    if not wi then return nil, nil, "too few listings to know the real price" end
    local per, dmin = o.deposit or 0, o.depositMin or 0
    if per == math.huge then return nil, wall, "posting fee not known yet" end
    if o.noFlip then return nil, wall, "sold by NPC vendors, so it can't be resold for more" end
    local function depFor(u) return u > 0 and max(dmin, ceil(per * u)) or 0 end
    local asCost = cfg.depositIsCost
    local ref = wall
    if o.avg and o.avg > 0 and o.avg < ref then ref = o.avg end -- rule 7
    if o.sold and o.sold > 0 and o.sold < ref then ref = o.sold end -- rule 8
    -- Rule 11, trend (from the price history database). o.trend is the market
    -- price change over the last ~6 hours. A price in free fall is not a flip:
    -- by the time ours sells, "market" is lower. A slow decline is priced in by
    -- assuming it continues: we plan to sell at today's price minus the same drop.
    -- Rule 12, learned from finished flips (ours and friends'): an item that
    -- just failed to sell is left alone for a while, and planned prices are
    -- scaled by how sales have really come in against plan.
    if o.blockedHours then
        return nil, wall, ("did not sell last time (yours or a friend's): skipped for %d more hour(s)"):format(math.ceil(o.blockedHours))
    end
    if o.learn and o.learn < 1 then ref = floor(ref * o.learn) end
    if o.trend and o.trend <= -cfg.trendSkip then
        return nil, wall, ("price is falling fast (%d%% in 6h): not buying into a drop"):format(floor(o.trend * 100 + 0.5))
    end
    if o.trend and o.trend < 0 then ref = floor(ref * (1 + o.trend)) end
    -- Rule 3: the resale price is set by the first row we do NOT buy.
    local k, sell, gross, maxBuy
    for _ = 1, wi do
        sell = Deals.round(ref - cfg.undercut, cfg)
        gross = floor(sell * (1 - cfg.cut))
        maxBuy = floor((gross - (asCost and ceil(per) or 0)) / (1 + cfg.margin))
        k = 0
        while k + 1 < wi and rows[k + 1].price <= maxBuy do k = k + 1 end
        if k + 1 < wi and rows[k + 1].price < ref then
            ref = rows[k + 1].price -- an unbought cheap row becomes our competition; try again
        else
            break
        end
    end
    if not k or k == 0 or sell <= 0 then
        return nil, wall, ("cheapest is $%d, market $%d: needs $%d or less"):format(rows[1].price, wall, math.max(maxBuy or 0, 0))
    end
    local units, cost = 0, 0
    for i = 1, k do units, cost = units + rows[i].qty, cost + rows[i].qty * rows[i].price end
    if units > floor(depth * cfg.share) then
        return nil, wall, ("%d cheap units is too many to clear (market has %d)"):format(units, depth)
    end
    local need = cost + depFor(units)
    local partial
    local cap = (o.gold < 10000) and 1 or cfg.maxSpend -- under 1g you may go all in on one deal
    local limit = min(o.budget, floor(o.gold * cap))
    if need > limit then
        -- Small purse: buy part of the pile, but only when the whole pile is tiny
        -- next to the market (<= partialShare), so the leftovers sell out quickly.
        if units > floor(depth * cfg.partialShare) then
            return nil, wall, ("good deal but needs $%d (with the posting fee), more than you can spend"):format(need)
        end
        local u, c = 0, 0
        for i = 1, k do
            local p = rows[i].price
            local n = min(rows[i].qty, floor((limit - c) / p))
            while n > 0 and c + n * p + depFor(u + n) > limit do n = n - 1 end
            if n <= 0 then break end
            u, c = u + n, c + n * p
            if n < rows[i].qty then break end
        end
        if u == 0 then
            return nil, wall, ("good deal but one costs $%d plus $%d posting fee, more than you have"):format(rows[1].price, depFor(1))
        end
        partial, units, cost = units - u, u, c
    end
    -- Rule 10, liquidity: only items that are actually trading. o.rate is the
    -- measured units sold per hour (nil = not watched long enough yet).
    local eta
    if cfg.requireTurnover then
        if not o.rate then return nil, wall, "price gap found; measuring how fast it sells first" end
        if o.rate <= 0 then return nil, wall, "price gap, but none have sold while watching: not a popular item" end
        eta = units / o.rate * 60
        if eta > cfg.maxSellMinutes then
            -- buy fewer if a smaller lot would sell in time (only for tiny piles, like any part-buy)
            local fit = floor(o.rate * cfg.maxSellMinutes / 60)
            if fit < 1 or (units + (partial or 0)) > floor(depth * cfg.partialShare) then
                return nil, wall, ("sells too slowly (about %d an hour): %d would take %d min"):format(floor(o.rate), units, floor(eta))
            end
            local u, c = 0, 0
            for i = 1, k do
                local n = min(rows[i].qty, fit - u)
                if n <= 0 then break end
                u, c = u + n, c + n * rows[i].price
            end
            partial, units, cost = (partial or 0) + units - u, u, c
            eta = units / o.rate * 60
        end
    end
    local dep = depFor(units)
    local profit = units * gross - cost - (asCost and dep or 0)
    if profit < cfg.minProfit then
        return nil, wall, ("profit $%d is under your $%d minimum"):format(profit, cfg.minProfit)
    end
    return { kind = "FLIP", units = units, cost = cost, deposit = dep, profit = profit, sell = sell,
             wall = wall, depth = depth, sold = o.sold, partial = partial, rate = o.rate, eta = eta, trend = o.trend,
             buys = {}, counts = {} }, wall
end

-- Full evaluation of one item's live listings (ascending by unit price, own
-- listings removed). Row: { price, qty } and for non-stackables also
-- { whole = true, buyout, id, vendor }.
--   o.budget     copper we may spend now
--   o.gold       total copper we own (defaults to budget)
--   o.vendor     vendor price per unit (nil if none)
--   o.avg        trusted average market price (nil if no history)
--   o.sold       average real sale price from recent invoices (nil if none)
--   o.deposit    posting fee per unit (math.huge = unknown); o.depositMin = smallest fee per posting
--   o.commodity  true for stackable goods
-- Returns deal or nil, and the wall price (market price) if one was found.
--   deal = { kind = "VENDOR"|"FLIP", units, cost, deposit, profit, sell, buys, counts }
function Deals.evaluate(rows, o, cfg)
    cfg = cfg or Deals.cfg
    if #rows == 0 or not o.budget or o.budget <= 0 then return nil, nil end
    o.gold = o.gold or o.budget
    local wall
    if o.commodity then wall = select(2, Deals.wall(rows, cfg)) end
    local deal, vreason = vendorDeal(rows, o, cfg)
    if deal then return deal, wall end
    if o.commodity and cfg.flips then
        local d, w, r = flipDeal(rows, o, cfg)
        return d, w, (not d) and (vreason or r) or nil
    end
    local v = o.vendor or 0
    if vreason then return nil, wall, vreason end
    return nil, wall, v > 0 and ("cheapest is $%d, vendor pays $%d"):format(rows[1].price, v) or "can't be sold to a vendor"
end

-- Cheap screen over everything the mesh knows, to decide what is worth a live
-- check. Nothing from here is ever shown as a deal. Returns { key, kind, score }.
function Deals.candidates(store, budget, now, vendorOf, cfg, limit)
    cfg = cfg or Deals.cfg
    local out, n = {}, 0
    local pp, qq = store.p, store.q
    for key, t in pairs(store.t) do
        local p = pp[key]
        if key > 0 and p <= budget and now - t <= cfg.maxAge then
            local v = vendorOf(key)
            if v and v > 0 and p <= floor(v / (1 + cfg.vendorMargin)) then
                n = n + 1
                out[n] = { key = key, kind = "VENDOR", score = (v - p) * min(qq[key], floor(budget / p)) }
            elseif cfg.flips then
                local ref = store:Reference(key, now, cfg.fairMaxAge, cfg.minSamples)
                if ref and p <= ref * cfg.screenRatio then
                    n = n + 1
                    out[n] = { key = key, kind = "FLIP", score = ref - p }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "VENDOR" end
        return a.score > b.score
    end)
    if limit and n > limit then for i = n, limit + 1, -1 do out[i] = nil end end
    return out
end

-- Posting price for an item we flipped.
--   rows     others' current listings, ascending (own listings excluded)
--   cost     what we paid per unit
--   target   resale price we planned when buying
--   deposit  deposit per unit for posting it now
-- Returns price, reason. price nil = wait (market is below our break-even).
function Deals.postPrice(rows, cost, target, cfg, deposit)
    cfg = cfg or Deals.cfg
    local floorP = Deals.breakEven(cost + (deposit or 0), cfg)
    local lowest = rows[1] and rows[1].price
    if not lowest then
        return max(Deals.round(target, cfg), floorP), "no competition"
    end
    local p = Deals.round(lowest - cfg.undercut, cfg)
    if p >= floorP then return p, "undercut" end
    if lowest >= floorP then return lowest, "match" end
    return nil, ("market %d is below break-even %d (cost + deposit + cut)"):format(lowest, floorP)
end

return Deals
