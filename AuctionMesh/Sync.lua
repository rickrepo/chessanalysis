-- AuctionMesh Sync: the mesh protocol.
--
-- Opcodes (first byte of every message; all fields are Codec varints):
--
--   D <base> {zig(key) price qty age}*      price records (live or catch-up)
--   H <ver> <since> <h1..h32>               hello: "I'm online, here are my
--                                            32 bucket hashes, I have nothing
--                                            newer than <since> from you"
--   S <mask> <requester>                    claim: "I'll stream these buckets
--                                            (bitmask) to <requester>"
--   C <kind> <time>                         full-scan coordination
--                                            kind 1 = starting, 2 = finished
--   F <base> {zig(key) fair 0 age}*          fair resale prices from depth checks
--
-- Live path: scans -> Observe() -> only net-new data is queued -> coalesced
-- for 150 ms -> packed ~18 records per 255-byte message -> LIVE lane. If an
-- identical-or-newer record from someone else arrives first, ours is dropped.
--
-- Catch-up path: on login a peer sends H. Every peer compares bucket hashes;
-- peers with differences wait a short random delay (sooner if they hold more
-- data), then claim up to 8 unclaimed buckets with S and stream only those
-- buckets' records newer than <since>. Others see the claim and take the
-- remaining buckets, so catch-up is split across peers, each using its own
-- send budget. Records broadcast by anyone during a stream are skipped.
local _, ns = ...
ns = ns or {}

local Codec, Store, Comm = ns.Codec, ns.Store, ns.Comm
local Sync = {}
ns.Sync = Sync

local floor, random, min, max = math.floor, math.random, math.min, math.max
local PROTO = 1
local NB = Store.NB

Sync.cfg = {
    maxAge = 72 * 3600,     -- forget prices older than this
    refresh = 30 * 60,      -- re-broadcast an unchanged price if our copy is older than this
    qtyDelta = 0.25,        -- re-broadcast if quantity moved by more than this fraction
    flushDelay = 0.15,      -- coalescing window for live deltas
    bulkThreshold = 300,    -- batches larger than this go to the BULK lane
    claimMax = 8,           -- buckets claimed per catch-up stream
    jobTTL = 120,           -- seconds before an unfinished catch-up job is forgotten
    fullScanCooldown = 15 * 60,
}

-- Platform hooks (overridden in tests)
Sync.serverTime = function() return GetServerTime() end
Sync.clock = function() return GetTime() end
Sync.after = function(s, fn) C_Timer.After(s, fn) end

Sync.fairPending = {} -- key -> true (fair prices from our depth checks awaiting flush)
Sync.pending = {}     -- key -> true (our net-new records awaiting flush)
Sync.npending = 0
Sync.heardAt = {}     -- key -> clock() when someone else broadcast its current version
Sync.jobs = {}        -- requester -> { unclaimed = {[b]=true}, n, since, started, timerArmed }
Sync.streams = {}     -- active outgoing streams
Sync.lastFullScan = { time = 0, by = nil }
Sync.stats = { observed = 0, netNew = 0, applied = 0, ignored = 0, rejected = 0 }

---------------------------------------------------------------- helpers

local function bit(mask, b) return floor(mask / 2 ^ (b - 1)) % 2 == 1 end

local function maskOf(set)
    local m = 0
    for b in pairs(set) do m = m + 2 ^ (b - 1) end
    return m
end

local function valid(key, p, q, t, now)
    return p > 0 and p < 1e13 and q >= 0 and q < 1e7 and key ~= 0
        and t <= now + 300 and t >= now - Sync.cfg.maxAge
end

---------------------------------------------------------------- live path

-- Records one observation from our own scanning. Returns true if net-new.
function Sync:Observe(key, price, qty, t)
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
    if not self.pending[key] then
        self.pending[key] = true
        self.npending = self.npending + 1
    end
    self:ScheduleFlush()
    return true
end

-- Batch form for full scans: map[key] = {price, qty}. Returns count of net-new records.
function Sync:ObserveBatch(map)
    local t, n = self.serverTime(), 0
    for key, v in pairs(map) do
        if self:Observe(key, v[1], v[2], t) then n = n + 1 end
    end
    return n
end

function Sync:ScheduleFlush()
    if self.flushArmed then return end
    self.flushArmed = true
    self.after(self.cfg.flushDelay, function() Sync:Flush() end)
end

-- A lazy message source over a key list: encodes at send time with current data.
local Source = {}
Source.__index = Source

function Source:Next()
    if self.cancelled then return nil end
    local keys, i, n = self.keys, self.i, self.n
    local tt, pp, qq = Store.t, Store.p, Store.q
    local b
    while i <= n do
        local key = keys[i]
        local t = tt[key]
        if t and self:Want(key, t) then
            if not b then b = Codec.newDelta(Sync.serverTime()) end
            if not b:add(key, pp[key], qq[key], t) then break end
            if self.pendingOnly then
                Sync.pending[key] = nil
                Sync.npending = Sync.npending - 1
            end
        end
        i = i + 1
    end
    self.i = i
    if b then
        self.sentRecords = (self.sentRecords or 0) + b.count
        return b:finish()
    end
    if self.onDone then self.onDone(self) end
    return nil
end

function Source:Want(key, t)
    if self.pendingOnly then return Sync.pending[key] == true end
    if self.buckets and not self.buckets[Store.bucketOf(key)] then return false end
    local h = Sync.heardAt[key]
    if h and h > self.started then return false end
    return t > self.since
end

local function newSource(keys, n, opts)
    local s = setmetatable(opts or {}, Source)
    s.keys, s.n, s.i = keys, n, 1
    s.started = s.started or Sync.clock()
    s.since = s.since or 0
    return s
end
Sync._newSource = newSource

-- A depth check (full search of one item) found what the item really sells for.
function Sync:ObserveFair(key, fair)
    if not fair or fair <= 0 then return end
    if Store:PutFair(key, fair, self.serverTime()) then
        self.fairPending[key] = true
        self:ScheduleFlush()
    end
end

function Sync:FlushFair()
    if not next(self.fairPending) then return end
    local b = Codec.newDelta(self.serverTime(), "F")
    for key in pairs(self.fairPending) do
        local f, t = Store.fp[key], Store.ft[key]
        if f and not b:add(key, f, 0, t) then
            Comm:Enqueue(Comm.LIVE, b:finish())
            b = Codec.newDelta(self.serverTime(), "F")
            b:add(key, f, 0, t)
        end
    end
    local m = b:finish()
    if m then Comm:Enqueue(Comm.LIVE, m) end
    self.fairPending = {}
end

function Sync:OnFair(msg, sender)
    local now = self.serverTime()
    Codec.decodeDelta(msg, function(key, f, _, t)
        if f > 0 and f < 1e13 and t <= now + 300 and t >= now - self.cfg.maxAge then
            Store:PutFair(key, f, t)
            self.fairPending[key] = nil
        end
    end)
end

function Sync:Flush()
    self.flushArmed = false
    self:FlushFair()
    if self.npending <= 0 then return end
    local keys, n = {}, 0
    for key in pairs(self.pending) do n = n + 1; keys[n] = key end
    -- Most significant first: brand-new items, then biggest relative moves are
    -- already in the order a scan produced them; keep it simple and cheap.
    local lane = (n > self.cfg.bulkThreshold) and Comm.BULK or Comm.LIVE
    Comm:Enqueue(lane, newSource(keys, n, { pendingOnly = true }))
end

---------------------------------------------------------------- receiving

function Sync:OnDelta(msg, sender)
    local now = self.serverTime()
    local clock = self.clock()
    local stats, pending, heardAt = self.stats, self.pending, self.heardAt
    local ok = Codec.decodeDelta(msg, function(key, p, q, t)
        if not valid(key, p, q, t, now) then
            stats.rejected = stats.rejected + 1
            return
        end
        if Store:Put(key, p, q, t) then
            stats.applied = stats.applied + 1
        else
            stats.ignored = stats.ignored + 1
        end
        local _, _, st = Store:Get(key)
        if st and st <= t then
            -- The mesh now carries our current version: don't send it again.
            heardAt[key] = clock
            if pending[key] then
                pending[key] = nil
                self.npending = self.npending - 1
            end
        end
    end)
    if not ok then stats.rejected = stats.rejected + 1 end
end

---------------------------------------------------------------- catch-up

function Sync:Hello()
    local buf, n = { "H" }, 1
    n = Codec.putUInt(buf, n, PROTO)
    n = Codec.putUInt(buf, n, self.lastSeen or 0)
    for i = 1, NB do n = Codec.putUInt(buf, n, Store.h[i]) end
    Comm:Enqueue(Comm.CONTROL, table.concat(buf, "", 1, n))
end

function Sync:OnHello(msg, sender)
    local ver, pos = Codec.readUInt(msg, 2)
    if not ver or ver ~= PROTO then return end
    local since
    since, pos = Codec.readUInt(msg, pos)
    if not since then return end
    local theirs = {}
    for i = 1, NB do
        theirs[i], pos = Codec.readUInt(msg, pos)
        if not theirs[i] then return end
    end
    local now = self.serverTime()
    since = max(since, now - self.cfg.maxAge)

    local diff, nd = Store:DiffBuckets(theirs)
    if nd == 0 then return end
    local unclaimed = {}
    for i = 1, nd do
        local b = diff[i]
        -- Only buckets where we actually hold something newer than `since` matter.
        if Store.cnt[b] > 0 then unclaimed[b] = true end
    end
    if not next(unclaimed) then return end

    local job = self.jobs[sender]
    if job then
        for b in pairs(unclaimed) do job.unclaimed[b] = true end
        job.since = min(job.since, since)
    else
        job = { unclaimed = unclaimed, since = since, created = self.clock() }
        self.jobs[sender] = job
    end
    self:ArmClaim(sender, job)
end

function Sync:ArmClaim(requester, job)
    if job.armed then return end
    job.armed = true
    -- Peers holding more data answer sooner; jitter breaks ties.
    local richness = min(Store.n, 50000) / 50000
    local delay = 0.2 + (1 - richness) * 1.5 + random() * 1.0
    self.after(delay, function() Sync:Claim(requester) end)
end

function Sync:Claim(requester)
    local job = self.jobs[requester]
    if not job then return end
    job.armed = false
    if self.clock() - job.created > self.cfg.jobTTL then self.jobs[requester] = nil; return end
    if job.streaming then return end

    local list, n = {}, 0
    for b in pairs(job.unclaimed) do n = n + 1; list[n] = b end
    if n == 0 then self.jobs[requester] = nil; return end
    -- Random subset so simultaneous claimers tend not to overlap.
    local take = {}
    for i = 1, min(n, self.cfg.claimMax) do
        local j = random(i, n)
        list[i], list[j] = list[j], list[i]
        take[list[i]] = true
        job.unclaimed[list[i]] = nil
    end

    local buf, bn = { "S" }, 1
    bn = Codec.putUInt(buf, bn, maskOf(take))
    Comm:Enqueue(Comm.CONTROL, table.concat(buf, "", 1, bn) .. requester)

    local keys, kn = Store:Collect(take, job.since)
    job.streaming = true
    local src = newSource(keys, kn, {
        since = job.since,
        buckets = take,
        requester = requester,
        onDone = function()
            job.streaming = false
            if next(job.unclaimed) then Sync:ArmClaim(requester, job) else Sync.jobs[requester] = nil end
        end,
    })
    self.streams[#self.streams + 1] = src
    Comm:Enqueue(Comm.BULK, src)
end

function Sync:OnClaim(msg, sender)
    local mask, pos = Codec.readUInt(msg, 2)
    if not mask then return end
    local requester = msg:sub(pos)
    local job = self.jobs[requester]
    if job then
        for b = 1, NB do
            if bit(mask, b) then job.unclaimed[b] = nil end
        end
    end
    -- Resolve races: if we are streaming the same bucket, the lower name keeps it.
    if sender < (Comm.me or "") then
        for _, src in ipairs(self.streams) do
            if src.requester == requester and src.buckets and not src.cancelled then
                for b = 1, NB do
                    if bit(mask, b) then src.buckets[b] = nil end
                end
            end
        end
    end
end

---------------------------------------------------------------- scan coordination

function Sync:AnnounceScan(kind)
    local now = self.serverTime()
    if kind == 2 then self.lastFullScan = { time = now, by = Comm.me } end
    local buf, n = { "C" }, 1
    n = Codec.putUInt(buf, n, kind)
    n = Codec.putUInt(buf, n, now)
    Comm:Enqueue(Comm.CONTROL, table.concat(buf, "", 1, n))
end

function Sync:OnScanNote(msg, sender)
    local kind, pos = Codec.readUInt(msg, 2)
    local t = Codec.readUInt(msg, pos)
    if not kind or not t then return end
    if kind == 1 then
        self.scanInProgress = { by = sender, at = self.clock() }
    elseif kind == 2 and t > (self.lastFullScan.time or 0) then
        self.lastFullScan = { time = t, by = sender }
        self.scanInProgress = nil
    end
end

-- Returns secondsAgo, by — the freshest full scan anyone on the mesh did.
function Sync:FreshestScan()
    local t = self.lastFullScan.time or 0
    if t == 0 then return nil end
    return self.serverTime() - t, self.lastFullScan.by
end

---------------------------------------------------------------- dispatch

local OPS = {
    [68] = Sync.OnDelta,    -- D
    [72] = Sync.OnHello,    -- H
    [83] = Sync.OnClaim,    -- S
    [67] = Sync.OnScanNote, -- C
    [70] = Sync.OnFair,     -- F
}

Sync.OPS = OPS -- other modules (Swarm) register their opcodes here

function Sync.Dispatch(msg, sender)
    local f = OPS[msg:byte(1) or 0]
    if f then f(Sync, msg, sender) end
end

-- Housekeeping: drop finished streams and stale jobs.
function Sync:Tidy()
    local live = {}
    for _, s in ipairs(self.streams) do
        if not s.cancelled and s.i <= s.n then live[#live + 1] = s end
    end
    self.streams = live
    local now = self.clock()
    for r, job in pairs(self.jobs) do
        if now - job.created > self.cfg.jobTTL and not job.streaming then self.jobs[r] = nil end
    end
    -- heardAt only matters while streams run; keep it from growing forever
    if #live == 0 then self.heardAt = {} end
end

return Sync
