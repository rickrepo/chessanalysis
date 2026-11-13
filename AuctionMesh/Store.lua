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

function Store:Remove(key)
    local ot = self.t[key]
    if not ot then return end
    local b = bucketOf(key)
    self.h[b] = (self.h[b] - contrib(key, ot, self.p[key])) % M
    self.cnt[b] = self.cnt[b] - 1
    self.n = self.n - 1
    self.p[key], self.q[key], self.t[key] = nil, nil, nil
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
