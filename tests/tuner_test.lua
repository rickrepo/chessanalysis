-- The request-budget learner, driven with a fake clock.
-- Run: lua5.1 tests/tuner_test.lua
local T, hour = 1000, 20
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end

local sent, logs = {}, {}
local ns = { Log = function(f, ...) logs[#logs + 1] = f:format(...) end }
ns.Comm = { CONTROL = 1, Enqueue = function(_, lane, msg) sent[#sent + 1] = msg end }
ns.Sync = { OPS = {} }
ns.Swarm = { cfg = { sweepShare = 0.30, perRequest = 0.65 } }
ns.Codec = assert(loadfile("AuctionMesh/Codec.lua"))("AuctionMesh", ns)
local Tuner = assert(loadfile("AuctionMesh/Tuner.lua"))("AuctionMesh", ns)
Tuner.now = function() return T end
Tuner.hour = function() return hour end

local d = {}
Tuner:Attach(d)
-- one background request: sent, answered `dt` later
local function request(kind, dt)
    Tuner:Sent(kind)
    T = T + dt
    Tuner:Answered(dt)
end
local function lastLog(pat) for i = #logs, 1, -1 do if logs[i]:find(pat) then return logs[i] end end end

print("measuring the limit")
local st = Tuner:State()
check(st.mode == "try" and st.text == "Measuring the server's limit: 0 of 20 requests" and st.fill == 0, "bar starts in measuring mode: 0 of 20")
for _ = 1, 10 do request("search", 0.62) end
st = Tuner:State()
check(st.mode == "try" and st.text:find("10 of 20") and st.fill == 0.5, "bar shows progress: 10 of 20, half full")
for _ = 1, 10 do request("browse", 0.80) end
st = Tuner:State()
print("     " .. st.text)
check(st.mode == "ok" and st.text:find("^Tuned: 1%.%d requests a second"), "after 20 requests the bar says Tuned with the measured rate")
check(math.abs(Tuner:Cycle("search") - 0.62) < 0.001 and math.abs(Tuner:Cycle("browse") - 0.80) < 0.001, "cost is kept per kind of request: item check 0.62s, category read 0.80s")
check(Tuner:Cycle("more") == d.cycle, "a kind with no measurements uses the overall figure")
check(d.hours[20].n == 20 and d.hours[3] == nil, "cost is kept per hour of the day")
check(math.abs(ns.Swarm.cfg.perRequest - d.hours[20].cycle) < 0.001, "the radar plans with this hour's measured cost")
hour = 3
check(Tuner:Expected() == d.cycle, "an hour not measured yet uses the overall figure")
hour = 20
Tuner:Sent(nil); T = T + 0.6; Tuner:Answered(0.6)
check(d.n == 20, "your own clicks (no kind) are never used for learning")

print("the safe pace")
check(Tuner:Gap() == 0, "no pause after 'ready' while nothing fails")
Tuner:Sent("search"); T = T + 0.3
check(Tuner:Failed("internal auction error") == true and Tuner:Gap() == 0, "one isolated failure is recorded but changes nothing")
for _ = 1, 10 do request("search", 0.62) end
Tuner:Sent("search"); T = T + 0.3; Tuner:Failed("message dropped")
print("     " .. lastLog("TUNER pace"))
check(Tuner:Gap() == 0.10, "second failure within 50 requests: a 0.10s pause is added")
check(Tuner:State().mode == "try" and Tuner:State().text:find("pause now 0.10s"), "the bar says so")
T = T + 5
check(Tuner:Failed("some error") == false, "an error with no background request in the last 2s is not counted")
for _ = 1, 299 do request("search", 0.62) end
check(d.gap.trial == nil and Tuner:Gap() == 0.10, "299 clean requests: still the safe pause")
request("search", 0.62)
check(d.gap.trial ~= nil and Tuner:Gap() == 0, "300 clean requests: a shorter pause is tried")
for _ = 1, 12 do request("search", 0.62) end
st = Tuner:State()
print("     " .. st.text)
check(st.mode == "try" and st.text == "Trying a shorter pause (0.00s): 12 of 30 requests" and math.abs(st.fill - 0.4) < 0.001, "the bar shows the trial: 12 of 30")
Tuner:Sent("search"); T = T + 0.3; Tuner:Failed("message dropped")
check(d.gap.trial == nil and Tuner:Gap() == 0.10 and d.gap.probeAfter == 600, "the trial failed: back to 0.10s, next try only after 600 clean requests")
for _ = 1, 600 do request("search", 0.62) end
check(d.gap.trial ~= nil, "600 clean requests later it tries again")
for _ = 1, 30 do request("search", 0.62) end
check(d.gap.trial == nil and Tuner:Gap() == 0 and d.gap.probeAfter == 300, "30 clean requests: the shorter pause is kept")

print("where requests pay")
check(Tuner:HitRate("vendor") == 0.5 and Tuner:HitRate("drop") == 0.5, "no record yet: every kind of alert counts the same")
for i = 1, 10 do Tuner:Checked("vendor", i <= 8, 50, 0.5) end
for i = 1, 20 do Tuner:Checked("drop", false, 0, 0.5) end
check(Tuner:HitRate("vendor") == 9 / 12 and Tuner:HitRate("drop") == 1 / 22, "vendor alerts 8 of 10 real, price-drop alerts 0 of 20")
check(d.src.vendor.profit == 400, "profit found is recorded per kind of alert")

print("the split between radar and item checks")
Tuner.win = { at = T, routine = 0, trig = 0, wait = 0 }
for _ = 1, 8 do Tuner:Checked("routine", false, 0) end
Tuner:Balance(0)
check(d.share == 0.30, "nothing changes before a minute has passed")
T = T + 61; Tuner:Balance(0)
print("     " .. lastLog("TUNER split"))
check(math.abs(d.share - 0.35) < 1e-9 and math.abs(ns.Swarm.cfg.sweepShare - 0.35) < 1e-9, "only routine checks and nothing waiting: radar gets 5 points more (30% -> 35%)")
for _ = 1, 6 do Tuner:Checked("market", false, 0, 9) end
T = T + 61; Tuner:Balance(2)
check(math.abs(d.share - 0.30) < 1e-9, "alerts waited 9s for a check: 5 points go back to item checks")
for _ = 1, 20 do
    for _ = 1, 5 do Tuner:Checked("market", false, 0, 9) end
    T = T + 61; Tuner:Balance(8)
end
check(math.abs(d.share - 0.15) < 1e-9, "the radar share never goes below 15%")
for _ = 1, 20 do
    for _ = 1, 5 do Tuner:Checked("routine", false, 0) end
    T = T + 61; Tuner:Balance(0)
end
check(math.abs(d.share - 0.70) < 1e-9, "and never above 70%")

print("waste and timeouts")
Tuner:Wasted("unsent"); Tuner:Wasted("timeout"); Tuner:Wasted("timeout")
check(d.unsent == 1 and d.timeout == 2, "requests never sent and never answered are counted")
check(math.abs(Tuner:Timeout() - d.hours[20].cycle * 4) < 0.001, "a lost answer is given up after 4x the measured cost (not a fixed 3s)")

print("what the Setup tab shows")
for _, l in ipairs(Tuner:Lines()) do print("     " .. l[1] .. ": " .. l[2]) end
check(#Tuner:Lines() == 7, "seven plain lines")

print("sharing with a friend who has just installed")
Tuner.sharedAt = nil
check(Tuner:Share() == true and sent[1] and sent[1]:sub(1, 1) == "L", "measured figures are sent on the channel")
check(Tuner:Share() == false, "at most once every 10 minutes")
local mine = d
local fresh = {}
Tuner:Attach(fresh)
ns.Sync.OPS[76](nil, sent[1], "Friend-Realm")
check(fresh.from == "Friend-Realm" and math.abs(fresh.kinds.search.cycle - mine.kinds.search.cycle) < 0.001 and math.abs(fresh.share - 0.70) < 1e-9,
    "a new client starts from the friend's measured cost and split")
check(fresh.n == 0 and Tuner:State().mode == "try", "but still measures for itself")
Tuner:Attach(mine)
local before = mine.share
ns.Sync.OPS[76](nil, sent[1], "Friend-Realm")
check(mine.from == nil and mine.share == before, "a client with its own measurements keeps them")

print("turned off (/amesh limits off)")
Tuner.cfg.enabled = false
mine.gap.i, mine.gap.clean, mine.gap.sinceFail = 2, 0, 1000
for _ = 1, 400 do request("search", 0.62) end
check(mine.gap.trial == nil and Tuner:Gap() == 0.10, "frozen: nothing is tried")
Tuner.cfg.enabled = true

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
