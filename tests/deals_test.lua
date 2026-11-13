-- Deal rules, posting prices and averages. Run: lua5.1 tests/deals_test.lua
local ns = {}
assert(loadfile("AuctionMesh/Store.lua"))("AuctionMesh", ns)
assert(loadfile("AuctionMesh/Deals.lua"))("AuctionMesh", ns)
local D, S = ns.Deals, ns.Store
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
local function ev(rows, o) o.commodity = o.commodity ~= false; o.budget = o.budget or 3200; return D.evaluate(rows, o) end
local market = { { price = 78, qty = 100 }, { price = 80, qty = 300 }, { price = 85, qty = 500 } }
local function with(cheap) local r = {}; for _, x in ipairs(cheap) do r[#r + 1] = x end; for _, x in ipairs(market) do r[#r + 1] = x end; return r end

print("safe (vendor) deals")
local d = ev({ { price = 50, qty = 10 } }, { vendor = 100 })
check(d and d.kind == "VENDOR" and d.units == 10 and d.cost == 500 and d.profit == 500, "10 units at 50c that vendor for 1s: +5s, guaranteed")
check(ev({ { price = 95, qty = 10 } }, { vendor = 100 }) == nil, "5% vendor profit is under the 10% bar: skipped")
d = ev({ { price = 50, qty = 1000 } }, { vendor = 100 })
check(d and d.units == 64 and d.cost == 3200, "vendor deal buys what 32s affords (64), partial is fine because nothing is resold")
d = ev({ { price = 50, qty = 10 }, { price = 60, qty = 5 }, { price = 95, qty = 9 } }, { vendor = 100 })
check(d and d.units == 15 and d.cost == 800, "takes every row under the vendor bar, stops at the first that isn't")
d = D.evaluate({ { price = 900, qty = 1, whole = true, buyout = 900, id = 1, vendor = 2000 },
                 { price = 950, qty = 1, whole = true, buyout = 950, id = 2, vendor = 400 } }, { budget = 3200, commodity = false })
check(d and d.units == 1 and d.buys[1].id == 1, "gear: each listing judged by its own vendor price")
check(D.evaluate({ { price = 100, qty = 1, whole = true, buyout = 100, id = 1 }, { price = 5000, qty = 1, whole = true, buyout = 5000, id = 2 } },
    { budget = 3200, commodity = false }) == nil, "gear is never an AH flip")

print("flips: the rules that stop losses")
d = ev(with({ { price = 20, qty = 40 } }), {})
check(d and d.kind == "FLIP" and d.units == 40 and d.cost == 800 and d.sell == 77, "40 outlier units at 20c under a deep 78-85c market: buy all 40, relist at 77c")
check(d and d.profit == 40 * math.floor(77 * 0.95) - 800, "profit counts the 5% cut")
check(ev(with({ { price = 20, qty = 1000 } }), {}) == nil, "1000 cheap units: can't clear them, they'd undercut us -> NO deal (the old bug)")
check(ev(with({ { price = 20, qty = 300 } }), { budget = 100000 }) == nil, "cheap pile bigger than 25% of the market, even if affordable -> no deal")
check(ev(with({ { price = 20, qty = 40 } }), { budget = 700 }) == nil, "can't afford ALL the cheap units -> no deal (never a partial buy)")
check(ev(with({ { price = 20, qty = 40 } }), { budget = 900, gold = 900 }) == nil, "would take over 80% of a small purse -> no deal")
check(ev({ { price = 200, qty = 40 }, { price = 780, qty = 100 }, { price = 800, qty = 300 } }, { budget = 15000, gold = 15000 }) == nil, "above 1g: one deal may not take more than half your gold")
check(ev({ { price = 200, qty = 30 }, { price = 780, qty = 100 }, { price = 800, qty = 300 } }, { budget = 15000, gold = 15000 }) ~= nil, "above 1g: a deal under half your gold is fine")
check(ev({ { price = 20, qty = 5 }, { price = 300, qty = 50 } }, {}) == nil, "one lonely expensive listing is not a market price -> no deal")
check(ev({ { price = 20, qty = 5 }, { price = 300, qty = 3 }, { price = 310, qty = 3 } }, {}) == nil, "thin market (6 units) -> no deal")
check(ev(market, {}) == nil, "fairly priced market -> no deal")
d = ev(with({ { price = 20, qty = 10 }, { price = 60, qty = 30 } }), {})
check(d and d.units == 10 and d.sell == 59, "a 60c row we don't buy becomes the competition: resale drops to 59c")
d = ev(with({ { price = 20, qty = 40 } }), { avg = 50 })
check(d and d.sell == 49, "history says ~50c: resale capped at 49c, not the 78c wall")
check(ev(with({ { price = 20, qty = 40 } }), { avg = 28 }) == nil, "history says it's only worth 28c -> no deal")
local d0 = ev(with({ { price = 20, qty = 40 } }), {})
d = ev(with({ { price = 20, qty = 40 } }), { deposit = 10 })
check(d and d.deposit == 400 and d.profit == d0.profit - 400, "deposit is subtracted from profit")
check(ev(with({ { price = 20, qty = 40 } }), { deposit = 10, budget = 1100 }) == nil, "gold for the deposit must also be affordable")
check(ev(with({ { price = 20, qty = 40 } }), { deposit = math.huge }) == nil, "unknown deposit -> no flip")
d = ev(with({ { price = 20, qty = 40 } }), { sold = 60 })
check(d and d.sell == 59 and d.sold == 60, "buyers really paid 60c: resale capped at 59c even though listings start at 78c")
check(ev(with({ { price = 20, qty = 40 } }), { sold = 25 }) == nil, "buyers only ever paid 25c -> no deal")
D.cfg.flips = false
check(ev(with({ { price = 20, qty = 40 } }), {}) == nil and ev({ { price = 50, qty = 10 } }, { vendor = 100 }) ~= nil, "safe-only mode: no flips, vendor deals still found")
D.cfg.flips = true
local _, wall = ev(with({ { price = 20, qty = 40 } }), {})
check(wall == 78, "reports the market (wall) price for sharing")

print("posting")
check(D.postPrice({ { price = 80, qty = 5 } }, 20, 79) == 79, "undercuts the cheapest competitor by 1c")
check(D.postPrice({ { price = 120, qty = 5 } }, 20, 79) == 119, "competitor higher than planned: take the extra profit")
check(D.postPrice({}, 20, 79) == 79, "no competition: planned price")
local p, why = D.postPrice({ { price = 20, qty = 5 } }, 30, 79)
check(p == nil and why:find("below break%-even"), "market below cost: wait, never sell at a loss")
check(D.postPrice({ { price = 80, qty = 5 } }, 50, 79, nil, 20) == 79 and D.postPrice({ { price = 80, qty = 5 } }, 60, 79, nil, 20) == nil, "floor covers cost + deposit + cut")
local cfg = {}; for k, v in pairs(D.cfg) do cfg[k] = v end; cfg.step, cfg.undercut = 100, 100
check(D.postPrice({ { price = 1500, qty = 5 } }, 200, 1400, cfg) == 1400, "silver-only AH: undercut by 1s")
check(D.postPrice({ { price = 300, qty = 1 } }, 280, 300, cfg) == 300, "silver-only AH: match when undercutting would lose money")

print("history and screening")
S:Attach({})
local t = 1763000000
for i = 0, 5 do S:PutFair(1, 1000, t + i * 3600) end
S:Put(1, 1, 10, t + 6 * 3600 + 60)
check(S.a[1] == 1000 and S.an[1] == 6, "history is built from market prices only: a 1c troll listing doesn't touch it")
S:PutFair(1, 5, t + 8 * 3600)
check(S.a[1] >= 500, ("one bad market reading can move the average at most halfway (avg %d)"):format(S.a[1]))
S:PutFair(2, 80, t); S:PutFair(2, 80, t + 60); S:PutFair(2, 80, t + 120)
check(S.an[2] == 1, "three checks in two minutes count as one history sample")
check(S:PutSold(3, 80, 10, t) and S:Sold(3, t + 100, 3600) == 80, "a real sale is recorded")
S:PutSold(3, 60, 10, t + 50)
check(S.sa[3] == 70 and S.sn[3] == 20, "sales average by units sold (80 and 60 -> 70)")
check(S:Sold(3, t + 100000, 3600) == nil, "old sales are not used")
S:Attach({})
S:Put(10, 50, 20, t)
for i = 1, 5 do S:Sample(11, 1000, t - 20000 + i * 3600) end
S:Put(11, 100, 5, t)
S:Put(12, 99999, 5, t); S:Put(13, 10, 5, t - 7200)
local vend = { [10] = 100, [13] = 1000 }
local c = D.candidates(S, 3200, t, function(k) return vend[k] end)
check(#c == 2 and c[1].key == 10 and c[1].kind == "VENDOR" and c[2].key == 11, "screen: vendor candidates first; skips unaffordable and stale")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
