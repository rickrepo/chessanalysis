-- AuctionMesh Deals: pure profit math (no WoW API calls, so it is unit-tested).
--
-- Two kinds of profit:
--   VENDOR  buy below what a vendor pays for the item. Risk-free, instant, no
--           5% AH cut, works on day one with zero price history.
--   FLIP    buy far below what the item resells for on the AH. The resale price
--           is the lower of (a) the "fair" price found by looking past the
--           cheapest listings and (b) the item's moving average.
--
-- All amounts are copper.
local _, ns = ...
ns = ns or {}

local Deals = {}
ns.Deals = Deals

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

-- Round down to a price the auction house accepts.
function Deals.round(p, cfg)
    local s = (cfg or Deals.cfg).step
    return floor(p / s) * s
end

-- Lowest unit price that still makes 1c profit after the AH cut, rounded up to a valid price.
-- Pass cost + deposit to cover the deposit too.
function Deals.breakEven(cost, cfg)
    cfg = cfg or Deals.cfg
    local s = cfg.step
    local p = ceil((cost + 1) / (1 - cfg.cut))
    return ceil(p / s) * s
end

Deals.cfg = {
    margin = 0.30,        -- FLIP: profit must be >= 30% of what we pay (after the AH cut)
    vendorMargin = 0.10,  -- VENDOR: risk-free, so 10% is enough
    minProfit = 20,       -- ignore deals that make less than this in total
    cut = 0.05,           -- auction house cut on sales
    undercut = 1,         -- we relist this far under the competition (100 if the AH has no copper)
    step = 1,             -- smallest price unit the AH accepts (Core sets 100 if copper is rejected)
    fairDepth = 0.15,     -- fair price = price once 15% of supply is bought out
    fairMaxAge = 20 * 60, -- a fair price older than this is re-checked
    minSamples = 4,       -- average needs this many samples before we trust it
    maxAge = 30 * 60,     -- only consider lowest prices seen in the last 30 min
}

-- rows: ascending by unit price, each { price = unitCopper, qty = n }.
-- Fair price = unit price at the point where max(cheapest row + 1 unit, 15% of
-- all units) has been bought. For gear (1 per listing) that is the 2nd listing;
-- for a commodity with a few cheap units it looks past them.
function Deals.fairPrice(rows, cfg)
    cfg = cfg or Deals.cfg
    if #rows < 2 then return nil end
    local total = 0
    for i = 1, #rows do total = total + rows[i].qty end
    local target = max(rows[1].qty + 1, ceil(total * cfg.fairDepth))
    local cum = 0
    for i = 1, #rows do
        cum = cum + rows[i].qty
        if cum >= target then return rows[i].price end
    end
    return rows[#rows].price
end

-- Full evaluation of one item's live listings.
--   rows     ascending listings (own listings already removed)
--   ref      outside reference price (moving average) or nil
--   vendor   vendor sell price per unit (0/nil if it can't be vendored)
--   budget   copper we can spend
--   deposit  AH deposit per unit to relist it (12h). It is counted as a cost
--            (it's lost if the item doesn't sell) and kept back from the budget,
--            so we never buy something we can't afford to post.
-- Returns a deal table or nil:
--   { kind = "VENDOR"|"FLIP", units, cost, deposit, profit, sell, maxUnit, fair, buys, counts }
function Deals.evaluate(rows, ref, vendor, budget, cfg, deposit)
    cfg = cfg or Deals.cfg
    deposit = deposit or 0
    if #rows == 0 or budget <= 0 then return nil, nil end
    local fair = Deals.fairPrice(rows, cfg)
    local sell = fair
    if ref and ref > 0 then sell = sell and min(sell, ref) or ref end

    if sell then sell = Deals.round(sell - cfg.undercut, cfg) end
    -- What one unit returns: AH = sale minus 5% cut minus deposit; vendor = vendor price.
    local ahNet = (sell and sell > 0) and (floor(sell * (1 - cfg.cut)) - deposit) or 0
    local vendorNet = vendor or 0
    local ahMax = floor(ahNet / (1 + cfg.margin))
    local vMax = floor(vendorNet / (1 + cfg.vendorMargin))

    local left, units, cost, deps, profit, maxUnit = budget, 0, 0, 0, 0, 0
    local buys, counts, kinds = {}, {}, { VENDOR = 0, FLIP = 0 }
    for i = 1, #rows do
        local r = rows[i]
        local value, kind
        if r.price <= vMax then value, kind = vendorNet, "VENDOR" end
        if r.price <= ahMax and (not value or ahNet > value) then value, kind = ahNet, "FLIP" end
        if not value then break end -- rows are sorted: nothing further qualifies
        local dep = (kind == "FLIP") and deposit or 0
        local n, spend
        if r.whole then -- non-commodity listing: whole stack or nothing
            spend = r.buyout or r.qty * r.price
            n = (spend + dep * r.qty <= left) and r.qty or 0
        else
            n = min(r.qty, floor(left / (r.price + dep)))
            spend = n * r.price
        end
        if n > 0 then
            units, cost, deps = units + n, cost + spend, deps + n * dep
            -- value already has the deposit taken off for FLIP units
            profit = profit + n * value - spend
            left = left - spend - n * dep
            maxUnit = r.price
            buys[#buys + 1], counts[#counts + 1] = r, n
            kinds[kind] = kinds[kind] + n
        elseif not r.whole then
            break -- out of gold
        end
    end
    if units == 0 or profit < cfg.minProfit then return nil, fair end
    return {
        kind = kinds.VENDOR >= kinds.FLIP and "VENDOR" or "FLIP",
        units = units, cost = cost, deposit = deps, profit = profit, maxUnit = maxUnit,
        sell = (kinds.VENDOR >= kinds.FLIP) and vendorNet or sell,
        fair = fair, buys = buys, counts = counts,
    }, fair
end

-- Quick screen of everything the mesh knows, using only the lowest price.
-- store: the Store module; vendorOf(key) -> vendor price or nil;
-- depositOf(key) -> estimated AH deposit per unit (optional).
-- Returns up to `limit` estimated deals sorted by estimated profit:
--   { key, price, qty, sell, kind, units, profit, margin }
function Deals.candidates(store, budget, now, vendorOf, cfg, limit, depositOf)
    cfg = cfg or Deals.cfg
    local out, n = {}, 0
    local pp, qq = store.p, store.q
    for key, t in pairs(store.t) do
        local p = pp[key]
        if key > 0 and p <= budget and now - t <= cfg.maxAge then
            local best, kind, sell, each
            local v = vendorOf(key)
            if v and v > 0 and p <= floor(v / (1 + cfg.vendorMargin)) then
                best, kind, sell, each = v - p, "VENDOR", v, p
            end
            local ref = store:Reference(key, now, cfg.fairMaxAge, cfg.minSamples)
            if ref then
                local dep = depositOf and depositOf(key) or 0
                local s = Deals.round(ref - cfg.undercut, cfg)
                local net = floor(s * (1 - cfg.cut)) - dep
                if s > 0 and p <= floor(net / (1 + cfg.margin)) and (not best or net - p > best) then
                    best, kind, sell, each = net - p, "FLIP", s, p + dep
                end
            end
            if best then
                local units = min(qq[key], floor(budget / each))
                if units > 0 and best * units >= cfg.minProfit then
                    n = n + 1
                    out[n] = { key = key, price = p, qty = qq[key], sell = sell, kind = kind,
                               units = units, profit = best * units, margin = best / p }
                end
            end
        end
    end
    -- Vendor deals first (risk-free), then by total profit.
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "VENDOR" end
        return a.profit > b.profit
    end)
    if limit and n > limit then for i = n, limit + 1, -1 do out[i] = nil end end
    return out
end

-- Posting price for an item we flipped.
--   rows     others' current listings, ascending (own listings excluded)
--   cost     what we paid per unit
--   target   resale price we planned when buying
--   deposit  deposit per unit for posting it now
-- Returns price, reason. price nil = hold (market is below our break-even).
function Deals.postPrice(rows, cost, target, cfg, deposit)
    cfg = cfg or Deals.cfg
    local floorP = Deals.breakEven(cost + (deposit or 0), cfg)
    local lowest = rows[1] and rows[1].price
    if not lowest then
        return max(Deals.round(target, cfg), floorP), "no competition"
    end
    local p = Deals.round(lowest - cfg.undercut, cfg)
    if p >= floorP then return p, "undercut" end
    if lowest >= floorP then return lowest, "match" end -- can't undercut further, match instead
    return nil, ("market %d is below break-even %d (cost + deposit + cut)"):format(lowest, floorP)
end

return Deals
