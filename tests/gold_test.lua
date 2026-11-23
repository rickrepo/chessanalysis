-- The gold recorder (AuctionMesh/Gold.lua): hours, days, swings and their causes.
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "  ok   " or "  FAIL ") .. what)
end
local T = 1700000000 -- a fixed clock
T = T - T % 86400 + 12 * 3600 -- noon, so that hours added stay inside the day
local gold = 10000
GetServerTime = function() return T end
GetMoney = function() return gold end
date = os.date
local ns = {}
local G = assert(loadfile("AuctionMesh/Gold.lua"))("AuctionMesh", ns)
G.dayId = function(t) return tonumber(os.date("!%Y%m%d", t)) end
local db = {}
G:Attach(db, "Tester-Realm")
local d = db.gold["Tester-Realm"]

print("recording")
check(d and #d.h == 1 and #d.d == 1 and d.d[1].o == 10000 and d.d[1].c == 10000 and #d.ev == 0, "at login: one hour and one day record at the gold in hand, no swing")
-- a purchase: the cause is declared after the gold has moved
T = T + 60; gold = 8800; G:OnMoney()
G:Cause("Bought 60 x Runecloth", -1)
check(#d.ev == 1 and d.ev[1].d == -1200 and d.ev[1].why[1] == "Bought 60 x Runecloth", "gold out, then the purchase is declared: the swing carries it")
check(d.d[1].o == 10000 and d.d[1].l == 8800 and d.d[1].c == 8800 and d.d[1].h == 10000, "the day: began at 1g, least 88s, now 88s")
-- a mailbox emptied: three sales within seconds, each declared just before its gold
T = T + 600
G:Cause("Sold 20 x Runecloth (auction)", 1); T = T + 1; gold = gold + 500; G:OnMoney()
G:Cause("Sold 40 x Runecloth (auction)", 1); T = T + 1; gold = gold + 1000; G:OnMoney()
G:Cause("Sold 5 x Thick Leather (auction)", 1); T = T + 1; gold = gold + 900; G:OnMoney()
check(#d.ev == 2 and d.ev[2].d == 2400 and d.ev[2].n == 3 and #d.ev[2].why == 3, "three sales collected within seconds are ONE swing of + 24s, with its three causes")
check(G.Why(d.ev[2]) == "Sold 20 x Runecloth (auction), Sold 40 x Runecloth (auction), Sold 5 x Thick Leather (auction)", "and it reads as the three sales")
-- something the addon knows nothing about
T = T + 120; gold = gold - 300; G:OnMoney()
check(#d.ev == 3 and d.ev[3].why == nil and G.Why(d.ev[3]) == "gold went out: not through the addon", "a change with no cause declared says so: not through the addon")
-- a cause for gold coming in is not put on gold going out
G:Cause("Sold 1 x Thing (auction)", 1)
check(d.ev[3].why == nil, "a sale declared right after gold went OUT is not put on that swing")
-- no change: nothing recorded
local n = #d.ev
G:OnMoney()
check(#d.ev == n, "the game saying 'gold changed' with the same amount records nothing")

print("hours and days")
-- the next hour
T = T + 3600; gold = gold + 100; G:OnMoney()
check(#d.h == 2 and d.h[2].o == 10900 and d.h[2].c == 11000 and d.h[1].c == 10900, "a new hour opens at what the gold was before the change (10900) and closes at 11000")
-- three days on: a day with no change in between
T = T + 3 * 86400; gold = 15000; G:OnMoney()
check(#d.d == 2 and d.d[2].o == 11000 and d.d[2].c == 15000, "three days later: a new day record, opened at the last amount")
local s = G:Series("days")
check(#s.slots == 30 and s.slots[30].c == 15000 and s.slots[30].o == 11000 and not s.slots[30].flat, "the 30-day series ends with today's candle")
check(s.slots[29].flat and s.slots[29].c == 11000 and s.slots[28].flat and s.slots[27].c == 11000 and not s.slots[27].flat,
    "days with no change are flat at the last amount; the day it all happened is a real candle")
check(s.slots[26].none == true and s.slots[1].none == true, "days before the first record are empty")
check(s.lo == 8800 and s.hi == 15000 and s.first == 10000 and s.last == 15000, "its range: least 88s, most 1g50s")
local h = G:Series("hours")
check(#h.slots == 24 and h.slots[24].c == 15000 and h.slots[23].flat and h.slots[1].flat and h.slots[1].c == 11000,
    "the 24-hour series carries the last amount through the hours with no change")

print("swings")
local sw = G:Swings("days", 6)
check(#sw == 5 and sw[1].d == 4000 and sw[2].d == 2400 and sw[3].d == -1200 and sw[1].slot == 30 and sw[2].slot == 27,
    "the biggest swings of the 30 days, largest first, each with the candle it belongs to")
local hs = G:Swings("hours", 6)
check(#hs == 1 and hs[1].d == 4000 and hs[1].slot == 24, "the 24-hour view has only the swing of the last day")
local c, base = G:Today()
check(c == 4000 and base == 11000, "today: + 40s on the 1g10s the day began with")
local c7 = G:Change(7 * 86400)
check(c7 == 5000, "seven days: + 50s against the first amount on record (there is no record from seven days ago)")

print("limits")
for i = 1, 400 do
    T = T + 20; gold = gold + ((i % 2 == 0) and (i * 3) or -(i * 2)); G:OnMoney()
end
check(#d.ev <= G.cfg.swings, ("no more than %d swings are kept (%d)"):format(G.cfg.swings, #d.ev))
local big = 0
for _, e in ipairs(d.ev) do if e.d == 4000 then big = big + 1 end end
check(big == 1, "the big one is still among them: the small old ones went first")
for i = 1, 100 do T = T + 3600; gold = gold + 1; G:OnMoney() end
check(#d.h == G.cfg.hours, ("no more than %d hourly records"):format(G.cfg.hours))
-- another character has its own record
gold = 500
G:Attach(db, "Banker-Realm")
check(db.gold["Banker-Realm"] ~= d and #db.gold["Banker-Realm"].d == 1 and db.gold["Banker-Realm"].d[1].c == 500, "each character has its own gold record")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
