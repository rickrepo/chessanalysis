-- Offline simulator for the AuctionMesh protocol. Run from repo root:
--   lua5.1 tests/sim.lua
-- Loads the real addon files once per simulated player (each gets its own
-- module state), connects them through a fake broadcast channel, and drives
-- a shared fake clock. The WoW API surface used by Codec/Store/Comm/Sync is
-- stubbed; Scanner/Core are client-only and not loaded here.
math.randomseed(12345)

local NOW = 0              -- fake GetTime()
local SERVER0 = 1763000000 -- fake GetServerTime() at NOW = 0
local timers = {}

local function after(s, fn) timers[#timers + 1] = { at = NOW + s, fn = fn } end

local function runTimers()
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.at <= NOW then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
end

C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }

local bus = {}       -- in-flight messages: {from, prefix, msg}
local peers = {}
local sentLog = {}   -- per peer: list of send times (for throttle checks)

local function newPeer(name)
    local ns = {}
    for _, f in ipairs({ "Codec", "Store", "Comm", "Sync", "Swarm", "Deals", "Learn" }) do
        assert(loadfile("AuctionMesh/" .. f .. ".lua"))("AuctionMesh", ns)
    end
    local P = { name = name, ns = ns }
    local Comm, Sync, Store = ns.Comm, ns.Sync, ns.Store
    Store:Attach({})
    Comm.me = name
    Comm.now = function() return NOW end
    Comm.last = NOW
    Sync.clock = function() return NOW end
    Sync.serverTime = function() return SERVER0 + math.floor(NOW) end
    Sync.after = after
    ns.Learn.serverTime = function() return SERVER0 + math.floor(NOW) end
    ns.Learn:Attach({})
    ns.Swarm.clock = function() return NOW end
    ns.Swarm.serverTime = Sync.serverTime
    sentLog[name] = {}
    Comm.RawSend = function(self, prefix, msg)
        assert(#msg <= 255, "message too long: " .. #msg)
        assert(not msg:find("%z"), "NUL byte in message")
        bus[#bus + 1] = { from = name, prefix = prefix, msg = msg }
        table.insert(sentLog[name], { t = NOW, prefix = prefix })
        self.stats.sent = self.stats.sent + 1
        self.stats.bytes = self.stats.bytes + #msg
        return "ok"
    end
    peers[#peers + 1] = P
    return P
end

local function deliver()
    local inflight = bus
    bus = {}
    for _, m in ipairs(inflight) do
        for _, p in ipairs(peers) do
            if p.name ~= m.from then
                p.ns.Comm.stats.recv = p.ns.Comm.stats.recv + 1
                p.ns.Sync.Dispatch(m.msg, m.from)
            end
        end
    end
end

local function step(dt)
    NOW = NOW + dt
    runTimers()
    for _, p in ipairs(peers) do p.ns.Comm:Pump() end
    deliver()
end

local function run(seconds, dt)
    dt = dt or 0.05
    local stop = NOW + seconds
    while NOW < stop do step(dt) end
end

local function count(store) local n = 0; for _ in pairs(store.t) do n = n + 1 end; return n end

local function sameStore(a, b)
    for k, t in pairs(a.t) do
        if b.t[k] ~= t or b.p[k] ~= a.p[k] or b.q[k] ~= a.q[k] then return false, k end
    end
    for k in pairs(b.t) do if not a.t[k] then return false, k end end
    return true
end

local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end

------------------------------------------------------------------ 1. codec
print("codec")
do
    local ns = {}
    assert(loadfile("AuctionMesh/Codec.lua"))("AuctionMesh", ns)
    local C = ns.Codec
    local okAll = true
    for _ = 1, 20000 do
        local v = math.floor(math.random() * 2 ^ math.random(0, 50))
        local s = C.uint(v)
        local back = C.readUInt(s, 1)
        if back ~= v then okAll = false; print("mismatch", v, back) break end
    end
    check(okAll, "varint round-trips 20k random values up to 2^50")
    check(C.unzig(C.zig(-1234)) == -1234 and C.unzig(C.zig(98765)) == 98765, "zigzag signed keys")

    local b = C.newDelta(1763000000)
    local recs = {}
    while true do
        local r = { math.random(1, 250000) * (math.random() < 0.05 and -1 or 1), math.random(1, 5e9), math.random(0, 20000), 1763000000 - math.random(0, 7200) }
        if not b:add(r[1], r[2], r[3], r[4]) then break end
        recs[#recs + 1] = r
    end
    local msg = b:finish()
    local got = {}
    C.decodeDelta(msg, function(k, p, q, t) got[#got + 1] = { k, p, q, t } end)
    local same = #got == #recs
    for i = 1, #recs do
        for j = 1, 4 do if not got[i] or got[i][j] ~= recs[i][j] then same = false end end
    end
    check(same and #msg <= 255, ("delta packs %d realistic records into %d bytes, decodes exactly"):format(#recs, #msg))
    check(msg:match("^[%w%+/]+$") ~= nil, "wire bytes are all chat-safe")
end

------------------------------------------------------------------ 2. store hashes
print("store")
do
    local ns = {}
    assert(loadfile("AuctionMesh/Store.lua"))("AuctionMesh", ns)
    local S = ns.Store
    S:Attach({})
    for _ = 1, 5000 do
        local k = math.random(1, 3000)
        if math.random() < 0.1 then S:Remove(k) else S:Put(k, math.random(1, 1e8), math.random(0, 500), SERVER0 + math.random(0, 1000)) end
    end
    local inc = {}
    for i = 1, S.NB do inc[i] = S.h[i] end
    local n = S.n
    S:Rehash()
    local same = n == S.n
    for i = 1, S.NB do if inc[i] ~= S.h[i] then same = false end end
    check(same, "incremental bucket hashes equal a full rehash after 5k random writes")
    S:Attach({})
    S:Put(5, 100, 1, 10)
    check(not S:Put(5, 50, 1, 9), "older record loses")
    check(S:Put(5, 90, 1, 10) and S.p[5] == 90, "same time: lower price wins")
    check(not S:Put(5, 95, 1, 10), "same time: higher price loses")
    check(S:Put(5, 200, 1, 11), "newer record wins")
end

------------------------------------------------------------------ 3. live mesh
print("live mesh")
local A, B, C = newPeer("Alice-Realm"), newPeer("Bob-Realm"), newPeer("Cara-Realm")
do
    for i = 1, 60 do A.ns.Sync:Observe(1000 + i, 10000 * i, i) end
    run(3)
    check(count(B.ns.Store) == 60 and count(C.ns.Store) == 60, "60 observations by Alice reach Bob and Cara")
    local sent = A.ns.Comm.stats.sent
    check(sent <= 5, ("...in %d messages (~%d records/msg)"):format(sent, math.floor(60 / sent)))

    for i = 1, 60 do A.ns.Sync:Observe(1000 + i, 10000 * i, i) end
    run(2)
    check(A.ns.Comm.stats.sent == sent, "re-observing unchanged prices sends nothing")

    A.ns.Sync:Observe(1001, 7777, 3)
    run(1)
    check(B.ns.Store.p[1001] == 7777 and C.ns.Store.p[1001] == 7777, "a price change propagates")

    -- Simultaneous scans of the same item: second sender is suppressed.
    local before = B.ns.Comm.stats.sent
    A.ns.Sync:Observe(5000, 123, 1)
    run(0.12)  -- Alice flushes first
    B.ns.Sync:Observe(5000, 123, 1) -- Bob sees the same listing a moment later (same second)
    run(1)
    check(B.ns.Comm.stats.sent == before, "duplicate observation already on the mesh is not re-sent")
    check(sameStore(A.ns.Store, B.ns.Store) and sameStore(A.ns.Store, C.ns.Store), "all three stores identical")
end

------------------------------------------------------------------ 4. catch-up split across peers
print("catch-up")
do
    -- Give the mesh a big table: 3,000 items observed by Bob.
    for i = 1, 3000 do B.ns.Sync:Observe(20000 + i, 500 + i * 3, i % 40) end
    run(400)
    check(count(A.ns.Store) == count(B.ns.Store), "bulk live broadcast of 3,000 items completes")

    local D = newPeer("Dave-Realm")
    local t0 = NOW
    D.ns.Sync:Hello()
    local done
    while NOW - t0 < 600 do
        step(0.05)
        if sameStore(D.ns.Store, A.ns.Store) then done = NOW - t0; break end
    end
    check(done ~= nil, ("new peer fully caught up (%d records) in %.0fs of simulated time"):format(count(D.ns.Store), done or -1))
    local contrib = {}
    for _, p in ipairs({ A, B, C }) do
        local n = 0
        for _, e in ipairs(sentLog[p.name]) do if e.t >= t0 and e.prefix == "AMsb" then n = n + 1 end end
        contrib[#contrib + 1] = p.name:match("^%a+") .. "=" .. n
    end
    print("     bulk messages sent per peer during catch-up: " .. table.concat(contrib, " "))
    local helpers = 0
    for _, p in ipairs({ A, B, C }) do
        for _, e in ipairs(sentLog[p.name]) do if e.t >= t0 and e.prefix == "AMsb" then helpers = helpers + 1; break end end
    end
    check(helpers >= 2, "catch-up work was shared by multiple peers")
end

------------------------------------------------------------------ 5. throttle
print("throttle")
do
    local worst = 0
    for name, log in pairs(sentLog) do
        for _, prefix in ipairs({ "AMsh", "AMsb" }) do
            local ts = {}
            for _, e in ipairs(log) do if e.prefix == prefix then ts[#ts + 1] = e.t end end
            -- Any 20s window may hold at most burst(10) + 20 * rate(0.95) = 29 messages.
            local j = 1
            for i = 1, #ts do
                while ts[i] - ts[j] > 20 do j = j + 1 end
                if i - j + 1 > worst then worst = i - j + 1 end
            end
        end
    end
    check(worst <= 29, ("per-prefix rate respected (worst 20s window: %d msgs, limit 29)"):format(worst))
end


------------------------------------------------------------------ 5b. presence and history catch-up
print("presence and price history for a newcomer")
do
    peers, bus, timers = {}, {}, {}
    local V, N = newPeer("Vet-Realm"), newPeer("Newbie-Realm")
    local now = SERVER0 + math.floor(NOW)
    local hour0 = now - (now % 3600)
    for i = 0, 200 do V.ns.Store:PutFair(2589, 1000 - i, hour0 - (200 - i) * 3600) end -- 200 hours of history
    check(N.ns.Sync:PeerCount() == 0, "newcomer starts with nobody connected")
    N.ns.Sync:Hello()
    run(30)
    check(V.ns.Sync:PeerCount() == 1 and N.ns.Sync:PeerCount() == 1, "both sides now show 1 other player connected")
    local h = N.ns.Store.hist[2589]
    check(h and #h / 3 >= 3, ("newcomer received price history points from the veteran (%d points)"):format(h and #h / 3 or 0))
    local p24 = N.ns.Store:PriceAt(2589, now, 24)
    check(p24 and math.abs(p24 - V.ns.Store:PriceAt(2589, now, 24)) <= 2, "the newcomer's price from 24h ago matches the veteran's")
    V.ns.Sync:Hint(4306); V.ns.Sync:Hint(4306)
    local got = 0
    N.ns.Sniper = { AddTrigger = function(_, key, why) if key == 4306 then got = got + 1 end end }
    run(3)
    check(got == 1, "a deal hint reaches the friend once (repeat hints are held back)")
    V.ns.Learn:Outcome(2589, true, 0.95); V.ns.Learn:Outcome(2770, false)
    run(3)
    local nd = N.ns.Learn.d
    check(nd.n == 2 and nd.ok == 1 and nd.fail == 1 and nd.mine == 0 and N.ns.Learn:Blocked(2770) ~= nil,
        "flip outcomes reach the friend: one sale, one expiry, and the expired item is on hold there too")
end

------------------------------------------------------------------ 6. swarm scanning
print("swarm")
local function swarmRun(nPeers, focusFor)
    peers, bus, timers = {}, {}, {}
    local units = {}
    for i = 1, 100 do units[i] = 7 * 256 + i end
    local scans = {} -- unit -> times scanned
    local list = {}
    for i = 1, nPeers do
        local P = newPeer("P" .. i .. "-Realm")
        local S = P.ns.Swarm
        S.units = units
        S.active = true
        S.cfg.fresh, S.cfg.adaptive = 300, false -- one full pass is what this test measures
        P.ns.peerAt = NOW          -- friends are online, so work-sharing notes are sent
        if focusFor and focusFor[i] then S:SetFocus(focusFor[i]) end
        -- Fake AH: 1 query per second per player, 1-3 pages per category,
        -- results arrive 0.3s after each query.
        local st = { nextReady = 0, resultsAt = math.huge, pages = 0, done = 0 }
        S.exec = {
            ready = function() return NOW >= st.nextReady end,
            start = function(u)
                scans[u] = (scans[u] or 0) + 1
                st.nextReady, st.resultsAt = NOW + 1, NOW + 0.3
                st.pages, st.done = math.random(1, 3), 1
            end,
            more = function() st.nextReady, st.resultsAt = NOW + 1, NOW + 0.3; st.done = st.done + 1 end,
            full = function() return st.done >= st.pages end,
            gotResults = function() return NOW >= st.resultsAt end,
        }
        list[i] = P
    end
    local t0 = NOW
    local finished
    while NOW - t0 < 2000 do
        step(0.05)
        for _, P in ipairs(list) do P.ns.Swarm:Step() end
        local all = true
        for _, u in ipairs(units) do
            local ok = false
            for _, P in ipairs(list) do if P.ns.Swarm.doneAt[u] then ok = true end end
            if not ok then all = false; break end
        end
        if all then finished = NOW - t0; break end
    end
    for _ = 1, 600 do step(0.05) end -- let queued "done" notes drain (they are rate-limited to ~1 a second)
    local dup = 0
    for _, n in pairs(scans) do if n > 1 then dup = dup + (n - 1) end end
    return finished, dup, list
end

local t1 = swarmRun(1)
local t4, dup4, list4 = swarmRun(4)
local t8, dup8 = swarmRun(8)
print(("     100 categories: 1 player %.0fs | 4 players %.0fs | 8 players %.0fs"):format(t1, t4, t8))
check(t4 and t4 < t1 / 3, ("4 players are %.1fx faster than 1"):format(t1 / t4))
check(t8 and t8 < t1 / 6, ("8 players are %.1fx faster than 1"):format(t1 / t8))
check(dup4 <= 8 and dup8 <= 16, ("few duplicated queries out of 100+ (4p: %d, 8p: %d)"):format(dup4, dup8))
-- every peer knows the coverage, not just the one who scanned
local fresh = list4[1].ns.Swarm:Coverage()
check(fresh == 100, "every peer sees all 100 categories as fresh")

-- Focus: player 1 focuses class-7 subclasses 1..10; they should take those first.
local _, _, flist = swarmRun(3, { "7:1 7:2 7:3 7:4 7:5 7:6 7:7 7:8 7:9 7:10" })
check(flist[1].ns.Swarm.stats.units > 0, "focused player participates")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
