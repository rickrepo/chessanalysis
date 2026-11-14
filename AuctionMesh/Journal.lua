-- AuctionMesh Journal: one record per purchase, followed to its end.
--
-- Every purchase becomes a trade. What happens to its units afterwards is
-- written onto the same record: listed (at what price), sold (what the buyer
-- really paid, from the invoice), sold to a vendor, expired, or removed. The
-- detail drawer shows these records with the profit made or still expected,
-- and one recommendation per open trade.
--
--   trade = { id, key, name, kind = "VENDOR"|"FLIP", qty, cost (per unit, nil
--             if unknown), plan (resale price planned at purchase), at,
--             listed (units on the auction house now), price (listed price),
--             listedAt, sold, vend, lost, got (copper received, after the cut),
--             expired (times it came back unsold), doneAt }
--
-- Units are matched oldest trade first.
local _, ns = ...
ns = ns or {}

local Journal = {}
ns.Journal = Journal

local floor, min, max = math.floor, math.min, math.max
Journal.MAX = 200
Journal.now = function() return GetServerTime() end

function Journal:Attach(list)
    self.list = list -- oldest first
    local top = 0
    for _, t in ipairs(list) do if (t.id or 0) > top then top = t.id end end
    self.nextId = top + 1
end

-- Units of a trade that have not been sold, vendored or lost yet.
function Journal.left(t)
    return t.qty - (t.sold or 0) - (t.vend or 0) - (t.lost or 0)
end

function Journal:Trim()
    local l = self.list
    while #l > self.MAX do
        -- drop the oldest finished trade; if every trade is open, the oldest one
        local at = 1
        for i, t in ipairs(l) do if Journal.left(t) <= 0 then at = i; break end end
        table.remove(l, at)
    end
end

function Journal:Bought(key, name, kind, qty, cost, plan, note)
    if not self.list or not qty or qty <= 0 then return end
    local t = { id = self.nextId, key = key, name = name, kind = kind or "FLIP", qty = qty, cost = cost, plan = plan,
                at = self.now(), listed = 0, sold = 0, vend = 0, lost = 0, got = 0, note = note }
    self.nextId = self.nextId + 1
    self.list[#self.list + 1] = t
    self:Trim()
    return t
end

-- Runs fn(trade, unitsTaken) over open trades of one item, oldest first,
-- until `count` units have been placed. want(trade) = units it can take.
local function spread(self, key, count, want, fn)
    for _, t in ipairs(self.list or {}) do
        if count <= 0 then break end
        if t.key == key then
            local n = min(count, want(t))
            if n > 0 then
                fn(t, n)
                count = count - n
            end
        end
    end
    return count
end

function Journal:Posted(key, qty, price)
    spread(self, key, qty, function(t) return Journal.left(t) - (t.listed or 0) end, function(t, n)
        t.listed, t.price, t.listedAt = (t.listed or 0) + n, price, self.now()
    end)
end

-- net = copper received for all `qty` units, after the auction house cut.
function Journal:Sold(key, qty, unit, net)
    local each = qty > 0 and net / qty or 0
    local function take(t, n)
        t.sold = (t.sold or 0) + n
        t.listed = max(0, (t.listed or 0) - n)
        t.got = (t.got or 0) + floor(each * n + 0.5)
        t.soldAt, t.soldPrice = self.now(), unit
        if Journal.left(t) <= 0 then t.doneAt = self.now() end
    end
    -- units that are on the auction house first, then anything still open
    local rest = spread(self, key, qty, function(t) return min(Journal.left(t), t.listed or 0) end, take)
    spread(self, key, rest, Journal.left, take)
end

function Journal:Vendored(key, qty, unit)
    spread(self, key, qty, function(t) return Journal.left(t) - (t.listed or 0) end, function(t, n)
        t.vend = (t.vend or 0) + n
        t.got = (t.got or 0) + (unit or 0) * n
        t.vendPrice = unit
        if Journal.left(t) <= 0 then t.doneAt = self.now() end
    end)
end

-- An auction came back unsold: the units are in the bags again.
function Journal:Expired(key, qty)
    spread(self, key, qty, function(t) return t.listed or 0 end, function(t, n)
        t.listed = t.listed - n
        t.expired = (t.expired or 0) + 1
    end)
end

-- Units that are gone without a sale on record (removed from tracking, or not
-- found in bags or mailbox). qty = nil: everything still open for this item.
function Journal:Dropped(key, qty, why)
    spread(self, key, qty or math.huge, Journal.left, function(t, n)
        t.lost = (t.lost or 0) + n
        t.listed = min(t.listed or 0, Journal.left(t))
        t.lostWhy = why
        if Journal.left(t) <= 0 then t.doneAt = self.now() end
    end)
end

-- Holdings recorded before the journal existed (or by an older version) get a
-- trade each, so nothing you own is missing from the drawer.
function Journal:Backfill(flips, listed, nameOf)
    local open = {}
    for _, t in ipairs(self.list or {}) do open[t.key] = (open[t.key] or 0) + Journal.left(t) end
    local keys = {}
    for key in pairs(flips or {}) do keys[key] = true end
    for key in pairs(listed or {}) do keys[key] = true end
    for key in pairs(keys) do
        local f, L = flips and flips[key], listed and listed[key]
        local have = (f and f.units or 0) + (L and L.qty or 0)
        local missing = have - (open[key] or 0)
        if missing > 0 then
            local cost = f and (not f.unknownCost and f.cost or nil) or (L and L.cost) or nil
            local t = self:Bought(key, nameOf(key), f and f.kind or "FLIP", missing, cost, f and f.sell or (L and L.plan), "from before the journal")
            if t then
                t.at = (f and f.at) or (L and L.at) or t.at
                if L and not f then t.listed, t.price, t.listedAt = min(missing, L.qty), L.price, L.at end
            end
        end
    end
end

-- Backfill, then the other direction: journal units that are no longer held
-- or listed anywhere (removed by an older version, or by hand) are closed, so
-- an open trade always matches something you really have.
function Journal:Sync(flips, listed, nameOf)
    self:Backfill(flips, listed, nameOf)
    local open = {}
    for _, t in ipairs(self.list or {}) do
        local n = Journal.left(t)
        if n > 0 then open[t.key] = (open[t.key] or 0) + n end
    end
    for key, n in pairs(open) do
        local f, L = flips and flips[key], listed and listed[key]
        local have = (f and f.units or 0) + (L and L.qty or 0)
        if n > have then self:Dropped(key, n - have, "no longer in your bags, mailbox or auctions") end
    end
end

-- Profit of the units that are finished (nil while the cost is unknown).
function Journal.realized(t)
    local done = (t.sold or 0) + (t.vend or 0)
    if done <= 0 or not t.cost then return nil end
    return (t.got or 0) - t.cost * done
end

-- trades newest first, optionally for one item only
function Journal:Trades(key)
    local out = {}
    local l = self.list or {}
    for i = #l, 1, -1 do
        if not key or l[i].key == key then out[#out + 1] = l[i] end
    end
    return out
end

-- { trades, open, finished, profit (banked on finished units), spent }
function Journal:Totals()
    local s = { trades = 0, open = 0, finished = 0, profit = 0, spent = 0 }
    for _, t in ipairs(self.list or {}) do
        s.trades = s.trades + 1
        if Journal.left(t) > 0 then s.open = s.open + 1 else s.finished = s.finished + 1 end
        s.profit = s.profit + (Journal.realized(t) or 0)
        s.spent = s.spent + (t.cost or 0) * t.qty
    end
    return s
end

return Journal
