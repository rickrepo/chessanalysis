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
local sold, atMail = 0, false -- what has sold and is not in hand yet (nil = not known); is the mailbox open
G.sold = function() return sold end
G.atMail = function() return atMail end
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

print("sold counts as cash")
do
    local n0, cash0 = #d.ev, (G:Cash())
    -- an auction sells: 5s on its way. Cash is up by 5s at once, and the swing says what sold.
    T = T + 100; sold = 500
    G:Cause("Sold 5 x Thick Leather (auction)", 1); G:OnMoney()
    check(#d.ev == n0 + 1 and d.ev[#d.ev].d == 500 and d.ev[#d.ev].why[1] == "Sold 5 x Thick Leather (auction)" and (G:Cash()) == cash0 + 500,
        "an auction sells: cash is up by what the buyer paid at once, with what sold")
    -- an hour later the gold is collected: in hand + 5s, sold - 5s. Nothing changes.
    T = T + 100; gold = gold + 500; sold = 0; G:OnMoney()
    check(#d.ev == n0 + 1 and (G:Cash()) == cash0 + 500, "collecting it from the mailbox changes nothing: it moves from sold to in hand")
    -- the sold amount is not known (a new session, the auction house not opened yet): the last known amount is carried
    sold = 300; G:OnMoney(); T = T + 20
    local n1, cash1 = #d.ev, (G:Cash())
    sold = nil
    T = T + 100; gold = gold - 200; G:OnMoney()
    check((G:Cash()) == cash1 - 200 and d.sold == 300, "while the sold amount is not known afresh the last known one is carried: a purchase still takes cash down by what it cost")
    atMail = true
    T = T + 100; gold = gold + 300; G:OnMoney()
    atMail = false
    check((G:Cash()) == cash1 - 200 and d.sold == 0, "sale gold collected at the mailbox meanwhile comes off the carried amount: cash is unchanged")
    sold = 0; G:OnMoney()
    -- the amounts back to what the next sections expect
    gold = 10900; G.last, G.lastMoney = nil, gold; d.d[#d.d].c = 10900; d.h[#d.h].c = 10900
    for i = #d.ev, 4, -1 do table.remove(d.ev, i) end
end

print("hours and days")
-- the next hour
T = T + 3600; gold = gold + 100; G:OnMoney()
check(#d.h == 2 and d.h[2].o == 10900 and d.h[2].c == 11000 and d.h[1].c == 10900, "a new hour opens at what the gold was before the change (10900) and closes at 11000")
-- three days on: a day with no change in between
T = T + 3 * 86400; gold = 15000; G:OnMoney()
check(#d.d == 2 and d.d[2].o == 11000 and d.d[2].c == 15000, "three days later: a new day record, opened at the last amount")
-- the line: the amount at evenly spaced times over the range
local L = G:Line("d7", 168) -- one column an hour
check(#L.cols == 168 and L.cols[168].v == 15000 and L.last == 15000, "the 7-day line ends at the amount now")
check(L.lo == 8800 and L.hi == 15000 and L.first == 10000, "its range: least 88s, most 1g50s; it begins at the first amount on record")
check(L.short == true and L.cols[1].none ~= true and L.first == 10000 and L.span < 7 * 86400 and L.span > 3 * 86400,
    "with less than 7 days on record the chart begins where the record begins: no empty stretch, and it says so")
check(L.cols[167].v == 11000 and L.cols[168].lo == 11000 and L.cols[168].hi == 15000, "it stays where it was for three days, then steps up in the last column (which spans 1g10s to 1g50s)")
check(#L.days >= 3 and #L.days <= 4 and L.days[1].col > 1, "it says where each day begins")
local L2 = G:Line("d2", 48)
check(L2.first == 11000 and L2.cols[1].v == 11000 and L2.cols[48].v == 15000 and not L2.cols[1].none, "the 2-day line begins at what the gold was two days ago (carried from before the range)")

print("swings")
local sw = G:Swings("d7", 6, 168)
check(#sw == 5 and sw[1].d == 4000 and sw[2].d == 2400 and sw[3].d == -1200 and sw[1].col == 168 and sw[2].col < 168,
    "the biggest swings of the 7 days, largest first, each with its place on the line")
local hs = G:Swings("d2", 6, 48)
check(#hs == 1 and hs[1].d == 4000 and hs[1].col == 48, "the 2-day view has only the swing of the last two days")
check(G.AxisStep(8800, 15000, 4) == 2000 and G.AxisStep(0, 90, 4) == 50 and G.AxisStep(1000000, 1400000, 4) == 100000, "the value axis steps in round amounts: 1, 2 or 5 times a power of ten")
local c, base = G:Today()
check(c == 4000 and base == 11000, "today: + 40s on the 1g10s the day began with")
local c7 = G:Change(7 * 86400)
check(c7 == 5000, "seven days: + 50s against the first amount on record (there is no record from seven days ago)")

-- a record of a few minutes: the chart is those minutes, never less than ten
do
    local db2, was = {}, { T = T, gold = gold, d = G.d, last = G.last }
    gold = 10000
    G:Attach(db2, "New-Realm")
    T = T + 120; gold = 9000; G:OnMoney()
    T = T + 60; gold = 9500; G:OnMoney()
    local Ls = G:Line("d2", 60)
    check(Ls.short == true and Ls.span == 600 and Ls.cols[60].v == 9500 and Ls.first == 10000,
        "three minutes on record, asked for 2 days: the chart is the last ten minutes, beginning at the first amount")
    local ss = G:Swings("d2", 6, 60, Ls.from)
    check(#ss == 2 and ss[1].d == -1000 and ss[1].col == 54 and ss[2].col == 60, "and its swings sit where they happened on that short chart (one a minute ago, one now)")
    T, gold, G.d, G.last = was.T, was.gold, was.d, was.last
end

-- a new record waits for the sold amount: with it unknown nothing is kept, so the chart cannot begin too low
do
    local keep = { T = T, gold = gold, d = G.d, last = G.last, lm = G.lastMoney, sold = sold }
    local db3 = {}
    sold = nil; gold = 4000
    G:Attach(db3, "Fresh-Realm")
    local f = db3.gold["Fresh-Realm"]
    check(f.wait == true and #f.d == 0, "a new record does not begin while the sold amount is not known")
    T = T + 30; gold = 3000; G:OnMoney()
    check(f.wait == true and #f.d == 0, "(a purchase meanwhile is not recorded either)")
    sold = 10000; G:OnMoney()
    check(f.wait == nil and #f.d == 1 and f.d[1].o == 13000 and #f.ev == 0, "it begins the moment the sold amount is known: 30s in hand + 1g sold = 1g30s, with no false jump")
    local db4 = {}
    sold = nil; gold = 700
    G:Attach(db4, "Alt-Realm")
    T = T + 400; G:OnMoney()
    check(db4.gold["Alt-Realm"].wait == nil and db4.gold["Alt-Realm"].d[1].o == 700, "on a character that never opens the auction house it begins after five minutes, with the gold in hand")
    T, gold, G.d, G.last, G.lastMoney, sold = keep.T, keep.gold, keep.d, keep.last, keep.lm, keep.sold
end

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
