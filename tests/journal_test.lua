-- The trade journal: one record per purchase, followed to its end.
-- Run: lua5.1 tests/journal_test.lua
local T = 5000
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
local ns = {}
local J = assert(loadfile("AuctionMesh/Journal.lua"))("AuctionMesh", ns)
J.now = function() return T end
local list = {}
J:Attach(list)

print("a flip from purchase to sale")
local a = J:Bought(2589, "Linen Cloth", "FLIP", 6, 20, 77)
check(#list == 1 and J.left(a) == 6 and J.realized(a) == nil, "bought 6: open, no profit yet")
J:Posted(2589, 6, 77)
check(a.listed == 6 and a.price == 77, "posted: 6 on the auction house at 77c")
J:Sold(2589, 2, 77, 146)
check(a.sold == 2 and a.listed == 4 and a.got == 146 and J.left(a) == 4 and J.realized(a) == 146 - 40, "2 of 6 sold: profit so far is on those 2 only (+ 1s06c)")
J:Sold(2589, 4, 77, 293)
check(J.left(a) == 0 and a.doneAt == T and J.realized(a) == 146 + 293 - 120, "the rest sold: finished, profit + 3s19c")

print("two purchases of the same item: oldest first")
local b = J:Bought(2770, "Copper Ore", "VENDOR", 12, 3, 5)
T = T + 60
local c = J:Bought(2770, "Copper Ore", "VENDOR", 5, 4, 5)
J:Vendored(2770, 14, 5)
check(J.left(b) == 0 and J.realized(b) == 24 and c.vend == 2 and J.left(c) == 3 and J.realized(c) == 2, "14 sold to a vendor: the first purchase is finished (+ 24c), 2 units of the second (+ 2c)")

print("an auction that expires")
local d = J:Bought(2592, "Wool Cloth", "FLIP", 5, 30, 90)
J:Posted(2592, 5, 90)
J:Expired(2592, 5)
check(d.listed == 0 and d.expired == 1 and J.left(d) == 5, "came back unsold: still open, not listed, counted as expired once")
J:Posted(2592, 5, 80); J:Sold(2592, 5, 80, 380)
check(J.left(d) == 0 and J.realized(d) == 380 - 150, "reposted lower and sold: profit from the real sale price")

print("removed, and totals")
local e = J:Bought(774, "Malachite", "FLIP", 3, 10, 40)
J:Dropped(774, nil, "removed from tracking by you")
check(J.left(e) == 0 and e.lost == 3 and J.realized(e) == nil, "removed by hand: closed, no profit claimed")
local s = J:Totals()
check(s.trades == 5 and s.open == 1 and s.finished == 4 and s.profit == (146 + 293 - 120) + 24 + 2 + (380 - 150), "totals: 5 trades, 4 finished, 1 open, profit is the sum of finished units")
check(J:Trades()[1] == e and #J:Trades(2770) == 2 and J:Trades(2770)[1] == c, "newest first, and by item")

print("holdings from before the journal")
local list2 = {}
J:Attach(list2)
local flips = { [100] = { kind = "FLIP", units = 4, cost = 50, sell = 90, at = 1234 } }
local listed = { [200] = { qty = 3, price = 70, cost = 40, at = 2345, plan = 75 } }
J:Sync(flips, listed, function(k) return "Item" .. k end)
check(#list2 == 2, "one trade is created for each holding")
local byKey = {}
for _, t in ipairs(list2) do byKey[t.key] = t end
check(byKey[100].qty == 4 and byKey[100].cost == 50 and byKey[100].at == 1234 and byKey[100].listed == 0, "bag item: quantity, cost and time carried over")
check(byKey[200].qty == 3 and byKey[200].listed == 3 and byKey[200].price == 70, "auction: carried over as listed at its price")
J:Sync(flips, listed, function(k) return "Item" .. k end)
check(#list2 == 2, "running it again adds nothing")
flips[100] = nil
J:Sync(flips, listed, function(k) return "Item" .. k end)
check(J.left(byKey[100]) == 0 and byKey[100].lost == 4, "a holding that is gone closes its trade instead of staying open for ever")

print("size limit")
local list3 = {}
J:Attach(list3)
J.MAX = 5
local keep = J:Bought(1, "Open one", "FLIP", 1, 1, 2)
for i = 2, 8 do local t = J:Bought(i, "T" .. i, "FLIP", 1, 1, 2); J:Sold(i, 1, 2, 2) end
check(#list3 == 5 and list3[1] == keep, "at most 5 kept; finished trades are dropped before open ones")
J.MAX = 200

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
