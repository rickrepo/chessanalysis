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
    for _, f in ipairs({ "Codec", "Store", "Comm", "Sync", "Swarm" }) do
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
    for _ = 1, 40 do step(0.05) end -- let the last "done" notes reach everyone
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
check(dup4 <= 4 and dup8 <= 8, ("almost no duplicated queries (4p: %d, 8p: %d)"):format(dup4, dup8))
-- every peer knows the coverage, not just the one who scanned
local fresh = list4[1].ns.Swarm:Coverage()
check(fresh == 100, "every peer sees all 100 categories as fresh")

-- Focus: player 1 focuses class-7 subclasses 1..10; they should take those first.
local _, _, flist = swarmRun(3, { "7:1 7:2 7:3 7:4 7:5 7:6 7:7 7:8 7:9 7:10" })
check(flist[1].ns.Swarm.stats.units > 0, "focused player participates")

------------------------------------------------------------------ 7. deals / sniper math
print("deals")
do
    local ns = {}
    assert(loadfile("AuctionMesh/Store.lua"))("AuctionMesh", ns)
    assert(loadfile("AuctionMesh/Deals.lua"))("AuctionMesh", ns)
    local D, S = ns.Deals, ns.Store
    local budget = 3200 -- 32 silver

    -- Commodity: 40 cheap units at 20c, then the real market around 80c.
    local rows = { { price = 20, qty = 40 }, { price = 78, qty = 100 }, { price = 80, qty = 300 }, { price = 85, qty = 500 } }
    local deal = D.evaluate(rows, nil, nil, budget)
    check(deal and deal.kind == "FLIP" and deal.units == 40 and deal.cost == 800,
        ("flip: buys the 40 underpriced units for 8s (got %s units, cost %s)"):format(deal and deal.units, deal and deal.cost))
    check(deal and deal.sell == 79, "flip: relists 1c under the fair price (80c -> 79c)")
    check(deal and deal.profit == 40 * (math.floor(79 * 0.95) - 20), "flip: profit counts the 5% AH cut")

    -- Budget caps the buy.
    local d2 = D.evaluate({ { price = 20, qty = 1000 }, { price = 80, qty = 5000 } }, nil, nil, budget)
    check(d2 and d2.units == 160 and d2.cost <= budget, "flip: never spends more than the 32s budget")

    -- Vendor flip: listed under vendor price, no AH history needed.
    local d3 = D.evaluate({ { price = 50, qty = 10 } }, nil, 100, budget)
    check(d3 and d3.kind == "VENDOR" and d3.units == 10 and d3.profit == 500, "vendor: 10 units at 50c that vendor for 1s = +5s")
    check(D.evaluate({ { price = 95, qty = 10 } }, nil, 100, budget) == nil, "vendor: 5% profit is below the 10% bar, skipped")

    -- Fairly priced market: nothing to buy.
    check(D.evaluate({ { price = 78, qty = 100 }, { price = 80, qty = 300 } }, nil, nil, budget) == nil, "no deal in a fairly priced market")

    -- Average below fair: the lower one is used (prices fall fast on a new realm).
    local d4 = D.evaluate(rows, 50, nil, budget)
    check(d4 and d4.sell == 49, "uses the lower of fair price and average as resale price")

    -- Gear: whole listings only; skip a stack we can't afford, take a cheaper single after it.
    local gear = { { price = 1000, qty = 1, whole = true, buyout = 1000 }, { price = 1100, qty = 5, whole = true, buyout = 5500 },
                   { price = 1150, qty = 1, whole = true, buyout = 1150 } }
    local d5 = D.evaluate(gear, nil, 2000, budget)
    check(d5 and d5.units == 2 and d5.cost == 2150, "gear: buys whole listings it can afford, skips the 5-stack it can't")

    -- Moving average resists one troll / snipe listing.
    S:Attach({})
    local t = 1763000000
    for i = 0, 5 do S:Put(1, 1000, 10, t + i * 3600) end
    S:Put(1, 1, 10, t + 6 * 3600 + 60)
    check(S.a[1] >= 500, ("average survives a 1c listing (avg now %d)"):format(S.a[1]))

    -- Screening: vendor first, budget-aware, ignores stale data.
    S:Attach({})
    local now = t
    S:Put(10, 50, 20, now)        -- vendors for 100: vendor deal
    for i = 1, 5 do S:Sample(11, 1000, now - 20000 + i * 3600) end
    S:Put(11, 100, 5, now)        -- average ~1000, listed at 1s: flip
    S:Put(12, 99999, 5, now)      -- unaffordable
    S:Put(13, 10, 5, now - 7200)  -- stale
    local vend = { [10] = 100, [13] = 1000 }
    local c = D.candidates(S, budget, now, function(k) return vend[k] end)
    check(#c == 2 and c[1].key == 10 and c[1].kind == "VENDOR" and c[2].key == 11 and c[2].kind == "FLIP",
        "screen: vendor deal first, then flip; skips unaffordable and stale")
end

------------------------------------------------------------------ 8. posting prices
print("posting")
do
    local ns = {}
    assert(loadfile("AuctionMesh/Store.lua"))("AuctionMesh", ns)
    assert(loadfile("AuctionMesh/Deals.lua"))("AuctionMesh", ns)
    local D = ns.Deals
    -- copper allowed
    check(D.postPrice({ { price = 80, qty = 5 } }, 20, 79) == 79, "undercuts the cheapest competitor by 1c")
    check(D.postPrice({ { price = 120, qty = 5 } }, 20, 79) == 119, "competitor higher than planned: take the extra profit")
    check(D.postPrice({}, 20, 79) == 79, "no competition: post at planned price")
    local p, why = D.postPrice({ { price = 20, qty = 5 } }, 30, 79)
    check(p == nil and why:find("below break%-even"), "market below what we paid: hold, never sell at a loss")
    check(D.breakEven(100) == 107, "break-even covers the 5% cut and 1c profit")
    -- silver-only auction house
    local cfg = {}
    for k, v in pairs(D.cfg) do cfg[k] = v end
    cfg.step, cfg.undercut = 100, 100
    check(D.postPrice({ { price = 1500, qty = 5 } }, 200, 1400, cfg) == 1400, "silver-only AH: undercut by 1s")
    check(D.postPrice({ { price = 300, qty = 1 } }, 280, 300, cfg) == 300, "silver-only AH: match when undercutting would lose money")
    check(D.round(1999, cfg) == 1900, "prices round down to whole silver")
    local deal = D.evaluate({ { price = 200, qty = 10 }, { price = 1000, qty = 50 }, { price = 1050, qty = 100 } }, nil, nil, 3200, cfg)
    check(deal and deal.sell == 900 and deal.sell % 100 == 0, "flip resale price is a valid silver amount")
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
