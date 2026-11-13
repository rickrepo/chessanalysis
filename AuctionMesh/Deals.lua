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
--     3. We can afford to buy EVERY unit below our resale price. If cheap
--        units would remain, they undercut us and ours never sell.
--     4. What we buy is at most `share` (25%) of the wall's size: small
--        outliers only, never a market that simply is cheap.
--     5. One item never takes more than `maxSpend` (50%) of our gold.
--     6. Profit after the 5% AH cut and the deposit is at least `margin` (40%).
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
    margin = 0.40,        -- FLIP: profit must be >= 40% of what we pay
    vendorMargin = 0.10,  -- SAFE: guaranteed, so 10% is enough
    minProfit = 20,       -- ignore deals that make less than this in total
    cut = 0.05,           -- auction house cut on sales
    undercut = 1,         -- we list this far under the competition
    step = 1,             -- smallest price unit the AH accepts (Core sets 100 if copper is rejected)
    band = 1.25,          -- wall = listings within 25% of each other
    depthUnits = 10,      -- wall needs at least this many units...
    depthRows = 2,        -- ...in at least this many price rows
    share = 0.25,         -- we buy at most 25% of the wall's size
    maxSpend = 0.5,       -- at most half our gold on one flip
    minSamples = 4,       -- average needs this many samples before we trust it
    fairMaxAge = 20 * 60, -- a wall price older than this is re-checked
    maxAge = 30 * 60,     -- only consider lowest prices seen in the last 30 min
    screenRatio = 0.6,    -- screening: lowest price must be <= 60% of the reference
    flips = true,         -- false = SAFE deals only
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
    if units == 0 or profit < cfg.minProfit then return nil end
    return { kind = "VENDOR", units = units, cost = cost, deposit = 0, profit = profit, sell = sell,
             buys = buys, counts = counts }
end

local function flipDeal(rows, o, cfg)
    local wi, wall, depth = Deals.wall(rows, cfg)
    if not wi then return nil, nil end
    local dep = o.deposit or 0
    if dep == math.huge then return nil, wall end
    local ref = wall
    if o.avg and o.avg > 0 and o.avg < ref then ref = o.avg end -- rule 7
    if o.sold and o.sold > 0 and o.sold < ref then ref = o.sold end -- rule 8
    -- Rule 3: the resale price is set by the first row we do NOT buy.
    local k, sell, net
    for _ = 1, wi do
        sell = Deals.round(ref - cfg.undercut, cfg)
        net = floor(sell * (1 - cfg.cut)) - dep
        local maxBuy = floor(net / (1 + cfg.margin))
        k = 0
        while k + 1 < wi and rows[k + 1].price <= maxBuy do k = k + 1 end
        if k + 1 < wi and rows[k + 1].price < ref then
            ref = rows[k + 1].price -- an unbought cheap row becomes our competition; try again
        else
            break
        end
    end
    if not k or k == 0 or sell <= 0 then return nil, wall end
    local units, cost = 0, 0
    for i = 1, k do units, cost = units + rows[i].qty, cost + rows[i].qty * rows[i].price end
    if units > floor(depth * cfg.share) then return nil, wall end                 -- rule 4
    local need = cost + units * dep
    if need > o.budget or need > floor(o.gold * cfg.maxSpend) then return nil, wall end -- rules 3, 5
    local profit = units * net - cost
    if profit < cfg.minProfit then return nil, wall end
    return { kind = "FLIP", units = units, cost = cost, deposit = units * dep, profit = profit, sell = sell,
             wall = wall, depth = depth, sold = o.sold, buys = {}, counts = {} }, wall
end

-- Full evaluation of one item's live listings (ascending by unit price, own
-- listings removed). Row: { price, qty } and for non-stackables also
-- { whole = true, buyout, id, vendor }.
--   o.budget     copper we may spend now
--   o.gold       total copper we own (defaults to budget)
--   o.vendor     vendor price per unit (nil if none)
--   o.avg        trusted average market price (nil if no history)
--   o.sold       average real sale price from recent invoices (nil if none)
--   o.deposit    AH deposit per unit to relist (math.huge = unknown)
--   o.commodity  true for stackable goods
-- Returns deal or nil, and the wall price (market price) if one was found.
--   deal = { kind = "VENDOR"|"FLIP", units, cost, deposit, profit, sell, buys, counts }
function Deals.evaluate(rows, o, cfg)
    cfg = cfg or Deals.cfg
    if #rows == 0 or not o.budget or o.budget <= 0 then return nil, nil end
    o.gold = o.gold or o.budget
    local wall
    if o.commodity then wall = select(2, Deals.wall(rows, cfg)) end
    local deal = vendorDeal(rows, o, cfg)
    if deal then return deal, wall end
    if o.commodity and cfg.flips then return flipDeal(rows, o, cfg) end
    return nil, wall
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
