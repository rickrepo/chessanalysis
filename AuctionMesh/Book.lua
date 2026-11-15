-- AuctionMesh Book: what your own reads of the auction house found, written
-- into the price table.
--
-- Nothing here talks to anyone. The addon sends no addon messages, joins no
-- chat channel and reads nothing from other players. (It used to: prices,
-- deals and purchases could be shared with friends over a hidden channel or
-- the guild. All of that has been removed.)
local _, ns = ...
ns = ns or {}

local Book = {}
ns.Book = Book

local Store = ns.Store
local max = math.max

Book.cfg = {
    maxAge = 72 * 3600,          -- forget prices older than this
    refresh = 30 * 60,           -- an unchanged price is written again once the record is this old
    qtyDelta = 0.25,             -- or when the quantity moved by more than this fraction
    fullScanCooldown = 15 * 60,
}
Book.serverTime = function() return GetServerTime() end
Book.stats = { observed = 0, netNew = 0 }
Book.lastFullScan = 0

-- One reading of an item: lowest price and quantity. Returns true if it changed what is on record.
function Book:Observe(key, price, qty, t)
    self.stats.observed = self.stats.observed + 1
    t = t or self.serverTime()
    local op, oq, ot = Store:Get(key)
    if op then
        local changed = op ~= price
            or math.abs(qty - oq) > max(1, oq * self.cfg.qtyDelta)
            or (t - ot) >= self.cfg.refresh
        if not changed then return false end
    end
    if not Store:Put(key, price, qty, t) then return false end
    self.stats.netNew = self.stats.netNew + 1
    return true
end

-- map[key] = { price, qty }. Returns how many records changed.
function Book:ObserveBatch(map)
    local t, n = self.serverTime(), 0
    for key, v in pairs(map) do
        if self:Observe(key, v[1], v[2], t) then n = n + 1 end
    end
    return n
end

-- A full listing of one item showed what it really sells for.
function Book:ObserveFair(key, fair)
    if not fair or fair <= 0 then return end
    Store:PutFair(key, fair, self.serverTime())
end

-- A sale invoice: what a buyer really paid.
function Book:ObserveSold(key, unit, qty)
    Store:PutSold(key, unit, qty, self.serverTime())
end

function Book:FullScanDone() self.lastFullScan = self.serverTime() end

-- Seconds since your last full scan, or nil.
function Book:FreshestScan()
    if (self.lastFullScan or 0) == 0 then return nil end
    return self.serverTime() - self.lastFullScan
end

return Book
