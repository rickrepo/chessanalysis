-- AuctionMesh Store
-- Per-realm price table stored as three parallel arrays keyed by item key
-- (p = min unit buyout in copper, q = quantity listed, t = server time seen).
-- Parallel numeric arrays are far cheaper in memory and SavedVariables I/O
-- than a table per record.
--
-- Conflict rule (last-writer-wins): newer t wins; on equal t the lower price
-- wins. Every peer applies the same rule, so all peers converge.
--
-- Each of NB buckets keeps an additive hash of (key, t, price) for its records,
-- updated in O(1) on every write. Peers compare the 32 bucket hashes to find
-- which slices of the table differ without sending the table.
--
-- Item key: itemID for normal items, -speciesID for caged battle pets.
local _, ns = ...
ns = ns or {}

local Store = {}
ns.Store = Store

local floor = math.floor
local NB = 32
local M = 1073741824 -- 2^30
Store.NB = NB

local function bucketOf(key)
    local z = key >= 0 and key * 2 or -key * 2 - 1
    return z % NB + 1
end
Store.bucketOf = bucketOf

local function contrib(key, t, p)
    -- Every product stays below 2^53, so double arithmetic is exact.
    local a = (key * 2654435761) % M
    local b = (t * 40503 + 977) % M
    local c = (p % M) * 7
    return (a * 31 + b * 17 + c + key) % M
end

function Store:Attach(realmTable)
    self.r = realmTable
    realmTable.p = realmTable.p or {}
    realmTable.q = realmTable.q or {}
    realmTable.t = realmTable.t or {}
    self.p, self.q, self.t = realmTable.p, realmTable.q, realmTable.t
    -- Market history: a = time-weighted average of the market price, an = samples,
    -- at = time of last sample. fp/ft = "fair" price from a depth check (what
    -- the item really sells for once the cheap outliers are gone) and its time.
    for _, k in ipairs({ "a", "an", "at", "fp", "ft", "sa", "sn", "st", "vu", "vs" }) do realmTable[k] = realmTable[k] or {} end
    self.a, self.an, self.at = realmTable.a, realmTable.an, realmTable.at
    self.fp, self.ft = realmTable.fp, realmTable.ft
    -- Real sales (from sale invoices, ours and friends'): sa = average unit price
    -- actually paid by buyers, sn = units sold, st = time of the last sale.
    self.sa, self.sn, self.st = realmTable.sa, realmTable.sn, realmTable.st
    -- Turnover (trading volume): vu = units seen leaving the cheap end of the
    -- listing, vs = seconds we watched. Rate = vu / vs.
    self.vu, self.vs = realmTable.vu, realmTable.vs
    self:Rehash()
end

function Store:Rehash()
    local h, cnt = {}, {}
    for i = 1, NB do h[i] = 0; cnt[i] = 0 end
    local n = 0
    for key, t in pairs(self.t) do
        local b = bucketOf(key)
        h[b] = (h[b] + contrib(key, t, self.p[key])) % M
        cnt[b] = cnt[b] + 1
        n = n + 1
    end
    self.h, self.cnt, self.n = h, cnt, n
end

function Store:Get(key)
    local t = self.t[key]
    if not t then return nil end
    return self.p[key], self.q[key], t
end

-- Returns true if the write changed stored data.
function Store:Put(key, price, qty, t)
    local ot = self.t[key]
    if ot then
        if t < ot then return false end
        if t == ot then
            local op = self.p[key]
            if price > op or (price == op and qty <= self.q[key]) then
                return false
            end
        end
        local b = bucketOf(key)
        self.h[b] = (self.h[b] - contrib(key, ot, self.p[key]) + contrib(key, t, price)) % M
    else
        local b = bucketOf(key)
        self.h[b] = (self.h[b] + contrib(key, t, price)) % M
        self.cnt[b] = self.cnt[b] + 1
        self.n = self.n + 1
    end
    self.p[key], self.q[key], self.t[key] = price, qty, t
    return true
end

-- Time-weighted moving average of the lowest price (half-life ~2.8h).
-- One sample can move it at most toward 0.5x..2x of the current average, so a
-- single snipe-priced listing or a troll listing can't wreck the average.
local TAU = 4 * 3600
function Store:Sample(key, price, t)
    -- Prefer the real market price (from a live check) over the lowest listing,
    -- which may be the very outlier we want to snipe.
    local a = self.a[key]
    if not a then
        self.a[key], self.an[key], self.at[key] = price, 1, t
        return
    end
    local dt = t - self.at[key]
    -- At most one sample per 30 minutes, so "4 samples" means real history, not
    -- four searches in a row.
    if dt < 1800 then return end
    local w = 1 - math.exp(-dt / TAU)
    if w < 0.05 then w = 0.05 end
    local x = price
    if x < a * 0.5 then x = a * 0.5 elseif x > a * 2 then x = a * 2 end
    self.a[key] = floor(a + w * (x - a) + 0.5)
    self.an[key] = self.an[key] + 1
    self.at[key] = t
end

function Store:PutFair(key, fair, t)
    local ot = self.ft[key]
    if ot and ot >= t then return false end
    self.fp[key], self.ft[key] = fair, t
    self:Sample(key, fair, t) -- history is built only from market prices read off full live listings
    return true
end

-- A real sale: `qty` units sold for `unit` copper each at time t.
function Store:PutSold(key, unit, qty, t)
    local ot = self.st[key]
    if ot and t <= ot then return false end
    local a, n = self.sa[key], self.sn[key] or 0
    if a then
        local w = qty / (qty + math.min(n, 3 * qty)) -- recent sales weigh more
        self.sa[key] = floor(a + w * (unit - a) + 0.5)
    else
        self.sa[key] = unit
    end
    self.sn[key], self.st[key] = n + qty, t
    return true
end

-- Adds one observation: `units` left the cheap end of the listing in `seconds`.
function Store:AddTurnover(key, units, seconds)
    local u, s = (self.vu[key] or 0) + units, (self.vs[key] or 0) + seconds
    if s > 3600 then u, s = u * 0.5, s * 0.5 end -- recent hours weigh more
    self.vu[key], self.vs[key] = u, s
end

-- Units sold per hour, or nil until the item has been watched for minSeconds.
function Store:Rate(key, minSeconds)
    local s = self.vs[key]
    if not s or s < (minSeconds or 0) then return nil end
    return self.vu[key] / s * 3600, s
end

-- Average real sale price if there was a sale within maxAge seconds, else nil.
function Store:Sold(key, now, maxAge)
    local t = self.st[key]
    if t and now - t <= maxAge then return self.sa[key], self.sn[key], t end
end

-- The price we expect to resell at: the lower of a fresh fair price and a
-- trusted average (in a brand-new game prices fall fast, so lower is safer).
-- Returns ref, source ("fair" | "avg" | "both") or nil when nothing is known.
function Store:Reference(key, now, fairMaxAge, minSamples)
    local ref, src
    local ft = self.ft[key]
    if ft and now - ft <= fairMaxAge then ref, src = self.fp[key], "fair" end
    local a, n = self.a[key], self.an[key]
    if a and n and n >= minSamples then
        if not ref or a < ref then ref = a end
        src = src and "both" or "avg"
    end
    return ref, src
end

function Store:Remove(key)
    local ot = self.t[key]
    if not ot then return end
    local b = bucketOf(key)
    self.h[b] = (self.h[b] - contrib(key, ot, self.p[key])) % M
    self.cnt[b] = self.cnt[b] - 1
    self.n = self.n - 1
    self.p[key], self.q[key], self.t[key] = nil, nil, nil
    self.a[key], self.an[key], self.at[key], self.fp[key], self.ft[key] = nil, nil, nil, nil, nil
    self.sa[key], self.sn[key], self.st[key] = nil, nil, nil
    self.vu[key], self.vs[key] = nil, nil
end

-- Drops records older than cutoff. Returns number removed.
function Store:Prune(cutoff)
    local dead, n = {}, 0
    for key, t in pairs(self.t) do
        if t < cutoff then n = n + 1; dead[n] = key end
    end
    for i = 1, n do self:Remove(dead[i]) end
    return n
end

-- Returns the list of 1-based bucket indices whose hash differs from `other`.
function Store:DiffBuckets(other)
    local out, n = {}, 0
    for i = 1, NB do
        if other[i] ~= self.h[i] then n = n + 1; out[n] = i end
    end
    return out, n
end

-- Collects keys in the given bucket set with t > since, newest first.
function Store:Collect(bucketSet, since)
    local keys, n, tt = {}, 0, self.t
    for key, t in pairs(tt) do
        if t > since and bucketSet[bucketOf(key)] then
            n = n + 1; keys[n] = key
        end
    end
    table.sort(keys, function(a, b) return tt[a] > tt[b] end)
    return keys, n
end

return Store
