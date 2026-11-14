-- Deal rules, posting prices and averages. Run: lua5.1 tests/deals_test.lua
local ns = {}
assert(loadfile("AuctionMesh/Store.lua"))("AuctionMesh", ns)
assert(loadfile("AuctionMesh/Deals.lua"))("AuctionMesh", ns)
local D, S = ns.Deals, ns.Store
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
local function ev(rows, o)
    o.commodity = o.commodity ~= false; o.budget = o.budget or 3200
    if o.rate == nil then o.rate = 100000 elseif o.rate == false then o.rate = nil end -- liquid unless the test says otherwise
    return D.evaluate(rows, o)
end
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
check(ev(with({ { price = 20, qty = 500 } }), { budget = 100000 }) == nil, "cheap pile bigger than half the market, even if affordable -> no deal")
check(ev(with({ { price = 20, qty = 300 } }), { budget = 100000 }) ~= nil, "cheap pile under half the market and affordable -> deal")
d = ev(with({ { price = 20, qty = 40 } }), { budget = 700 })
check(d and d.units == 35 and d.partial == 5, "can't afford all 40 of a pile that is tiny next to a 900-unit market -> buy 35, 5 left")
check(ev(with({ { price = 20, qty = 200 } }), { budget = 700 }) == nil, "can't afford all of a pile that is NOT tiny (200 vs 900) -> no deal")
check(ev(with({ { price = 20, qty = 40 } }), { budget = 900, gold = 900 }) ~= nil, "under 1g you may put nearly all your gold into one deal")
d = ev({ { price = 200, qty = 40 }, { price = 780, qty = 100 }, { price = 800, qty = 300 } }, { budget = 15000, gold = 15000 })
check(d and d.cost + d.deposit <= 7500, "above 1g: one deal never takes more than half your gold (buys " .. tostring(d and d.units) .. " of 40)")
check(ev({ { price = 200, qty = 30 }, { price = 780, qty = 100 }, { price = 800, qty = 300 } }, { budget = 15000, gold = 15000 }) ~= nil, "above 1g: a deal under half your gold is fine")
check(ev({ { price = 20, qty = 5 }, { price = 300, qty = 50 } }, {}) == nil, "one lonely expensive listing is not a market price -> no deal")
check(ev({ { price = 20, qty = 5 }, { price = 300, qty = 3 }, { price = 310, qty = 3 } }, {}) == nil, "thin market (6 units) -> no deal")
check(ev(market, {}) == nil, "fairly priced market -> no deal")
d = ev(with({ { price = 20, qty = 10 }, { price = 70, qty = 30 } }), {})
check(d and d.units == 10 and d.sell == 69, "a 70c row we don't buy becomes the competition: resale drops to 69c")
d = ev(with({ { price = 20, qty = 10 }, { price = 60, qty = 30 } }), {})
check(d and d.units == 40 and d.sell == 77, "a 60c row still clears the 20% bar, so it is bought too")
d = ev(with({ { price = 20, qty = 40 } }), { avg = 50 })
check(d and d.sell == 49, "history says ~50c: resale capped at 49c, not the 78c wall")
check(ev(with({ { price = 20, qty = 40 } }), { avg = 22 }) == nil, "history says it's only worth 22c -> no deal")
local d0 = ev(with({ { price = 20, qty = 40 } }), {})
d = ev(with({ { price = 20, qty = 40 } }), { deposit = 10 })
check(d and d.deposit == 400 and d.profit == d0.profit, "posting fee is kept aside (4s) but not subtracted: it comes back on sale")
D.cfg.depositIsCost = true
d = ev(with({ { price = 20, qty = 40 } }), { deposit = 10 })
check(d and d.profit == d0.profit - 400, "pessimistic setting: fee counted as lost")
D.cfg.depositIsCost = false
d = ev({ { price = 115, qty = 5 }, { price = 184, qty = 26 }, { price = 185, qty = 9 }, { price = 187, qty = 16 }, { price = 188, qty = 86 } }, { budget = 200, deposit = 0.05, depositMin = 100 })
check(d == nil, "2s purse with a 1s minimum fee: 1s15c + 1s fee is more than you have -> no deal")
d = ev({ { price = 34, qty = 8 }, { price = 134, qty = 11 }, { price = 158, qty = 237 }, { price = 159, qty = 150 } }, { budget = 189, deposit = 0.02, depositMin = 100 })
check(d and d.units == 2 and d.cost == 68 and d.deposit == 100, "real log: Wool 8@34c, 1s89c purse, 1s minimum fee -> buy 2, keep 1s for the fee")
d = ev(with({ { price = 20, qty = 40 } }), { deposit = 10, budget = 1100 })
check(d and d.units == 36 and d.cost + d.deposit <= 1100, "gold for the deposit is kept back (buys 36, not 40)")
check(ev(with({ { price = 20, qty = 40 } }), { deposit = math.huge }) == nil, "unknown deposit -> no flip")
d = ev(with({ { price = 20, qty = 40 } }), { sold = 60 })
check(d and d.sell == 59 and d.sold == 60, "buyers really paid 60c: resale capped at 59c even though listings start at 78c")
check(ev(with({ { price = 20, qty = 40 } }), { sold = 25 }) == nil, "buyers only ever paid 25c -> no deal")
local _, _, why = ev(with({ { price = 20, qty = 40 } }), { noFlip = true })
check(why and why:find("NPC vendors"), "goods that vendors sell are never flipped")
-- cases from a real auction house log
d = ev({ { price = 20, qty = 5 }, { price = 35, qty = 8 }, { price = 40, qty = 11 }, { price = 47, qty = 15 }, { price = 48, qty = 1 }, { price = 50, qty = 35 } }, { budget = 300, deposit = 1 })
check(d and d.units == 5 and d.cost == 100 and d.sell == 34, "real log: 5@20 under a 35c market -> buy 5 for 1s, relist at 34c (+" .. tostring(d and d.profit) .. "c)")
d = ev({ { price = 30, qty = 11 }, { price = 42, qty = 335 }, { price = 44, qty = 120 }, { price = 45, qty = 1114 } }, { budget = 400, deposit = 1 })
check(d and d.units == 11 and d.sell == 41, "real log: Coarse Stone 11@30 under 42c -> deal (+" .. tostring(d and d.profit) .. "c)")
check(ev({ { price = 23, qty = 316 }, { price = 24, qty = 314 }, { price = 25, qty = 1853 } }, { budget = 400, deposit = 1 }) == nil, "real log: Linen 23c vs 24c market -> no deal")
check(ev({ { price = 5, qty = 1985 }, { price = 22, qty = 29 }, { price = 25, qty = 18 } }, { budget = 400, deposit = 1 }) == nil, "real log: 1985 units at 5c is the real price, not a deal")
-- trend, from the price history database
local _, _, wt = ev(with({ { price = 20, qty = 40 } }), { trend = -0.18 })
check(wt and wt:find("falling fast %(%-18%% in 6h%)"), "market fell 18% in 6h -> no flip into a falling price")
d = ev(with({ { price = 20, qty = 40 } }), { trend = -0.05 })
check(d and d.sell == math.floor(78 * 0.95) - 1, "market drifting down 5% -> planned resale lowered by the same 5% (" .. tostring(d and d.sell) .. "c)")
d = ev(with({ { price = 20, qty = 40 } }), { trend = 0.20 })
check(d and d.sell == 77, "rising market -> resale stays at today's price, no optimism added")
-- liquidity
local _, _, w1 = ev(with({ { price = 20, qty = 40 } }), { rate = false })
check(w1 and w1:find("measuring how fast"), "no volume data yet -> no deal, keeps watching")
local _, _, w2 = ev(with({ { price = 20, qty = 40 } }), { rate = 0 })
check(w2 and w2:find("not a popular item"), "nothing sold while watching -> not a popular item, no deal")
d = ev(with({ { price = 20, qty = 40 } }), { rate = 60 })
check(d and d.units == 40 and math.floor(d.eta) == 40, "sells 60 an hour: 40 units clear in 40 min -> deal")
d = ev(with({ { price = 20, qty = 40 } }), { rate = 20 })
check(d and d.units == 20 and d.partial == 20, "sells 20 an hour: buy only the 20 that sell within the hour")
local _, _, w3 = ev(with({ { price = 20, qty = 200 } }), { rate = 20, budget = 100000 })
check(w3 and w3:find("sells too slowly"), "big pile on a slow item -> no deal")
-- with 2 silver
d = ev({ { price = 115, qty = 5 }, { price = 184, qty = 26 }, { price = 185, qty = 9 }, { price = 187, qty = 16 }, { price = 188, qty = 86 }, { price = 189, qty = 75 } }, { budget = 200, deposit = 1 })
check(d and d.units == 1 and d.cost == 115 and d.partial == 4 and d.profit >= 50, "2s purse, real log: Liferoot 5@1s15c under 1s84c -> buy the 1 you can afford (+" .. tostring(d and d.profit) .. "c)")
d = ev({ { price = 20, qty = 5 }, { price = 35, qty = 8 }, { price = 40, qty = 11 }, { price = 47, qty = 15 }, { price = 48, qty = 1 }, { price = 50, qty = 35 } }, { budget = 200, deposit = 1 })
check(d and d.units == 5 and not d.partial, "2s purse: the 5@20c deal is fully affordable (+55c)")
check(ev(with({ { price = 20, qty = 300 } }), { budget = 200 }) == nil, "2s purse: a big cheap pile is still never bought in part")
check(ev({ { price = 300, qty = 2 }, { price = 900, qty = 50 }, { price = 910, qty = 50 } }, { budget = 200 }) == nil, "2s purse: can't afford even one -> no deal")
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

print("learning from outcomes")
do
    local sentMsgs = {}
    local ln = { Deals = D, Codec = nil, Sync = { OPS = {} }, Comm = { LIVE = 2, Enqueue = function(_, lane, m) sentMsgs[#sentMsgs + 1] = m end } }
    assert(loadfile("AuctionMesh/Codec.lua"))("AuctionMesh", ln)
    assert(loadfile("AuctionMesh/Learn.lua"))("AuctionMesh", ln)
    local L = ln.Learn
    local clockNow = 1763000000
    L.serverTime = function() return clockNow end
    L:Attach({})
    local margin0 = D.cfg.margin
    check(L:Factor() == 1 and L:Blocked(7) == nil, "nothing learned yet: prices and items are untouched")
    for _ = 1, 4 do L:Outcome(7, true, 0.90) end
    check(L:Factor() == 1, "four sales are not enough to change anything")
    L:Outcome(7, true, 0.90)
    check(math.abs(L:Factor() - 0.90) < 0.001, "after 5 sales at 90% of plan, planned prices are scaled to 90%")
    for _ = 1, 30 do L:Outcome(7, true, 1.40) end
    check(L:Factor() == 1, "sales above plan never raise the plan above 100%")
    for _ = 1, 60 do L:Outcome(7, true, 0.50) end
    check(L:Factor() == 0.80, "the price factor never goes below 80%")
    -- item record
    L:Attach({})
    L:Outcome(9, false)
    check(L:Blocked(9) and L:Blocked(9) > 11.9, "an item that expired is not flipped again for 12 hours")
    L:Outcome(9, false)
    check(L:Blocked(9) > 23.9, "two failures in a row: 24 hours")
    clockNow = clockNow + 25 * 3600
    check(L:Blocked(9) == nil, "the hold ends by itself")
    L:Outcome(9, false); L:Outcome(9, true, 1)
    check(L:Blocked(9) == nil, "a sale clears the hold")
    -- deal rules use both
    local dl = ev(with({ { price = 20, qty = 40 } }), { learn = 0.9 })
    check(dl and dl.sell == math.floor(78 * 0.9) - 1, "deal rule: planned resale scaled by the learned factor (" .. tostring(dl and dl.sell) .. "c)")
    local _, _, wb = ev(with({ { price = 20, qty = 40 } }), { blockedHours = 7.2 })
    check(wb and wb:find("did not sell last time") and wb:find("8 more hour"), "deal rule: a held item is refused with the reason")
    -- margin tuning, slow and bounded
    L:Attach({}); D.cfg.margin = 0.20
    for i = 1, 10 do L:Outcome(100 + i, i <= 5, 1) end
    check(math.abs(D.cfg.margin - 0.25) < 1e-9, "only half of 10 flips sold: profit bar raised from 20% to 25%")
    for i = 1, 20 do L:Outcome(200 + i, true, 1) end
    check(math.abs(D.cfg.margin - 0.23) < 1e-9, "then 20 in a row sold: unchanged at 75% sold, then lowered 2 points once the last 20 all sold (23%)")
    L.cfg.autoTune = false
    for i = 1, 20 do L:Outcome(300 + i, false) end
    check(math.abs(D.cfg.margin - 0.23) < 1e-9, "with self-adjustment off, the bar stays where it is")
    L.cfg.autoTune = true
    -- shared with the channel
    L:Attach({}); sentMsgs = {}
    L:Outcome(4306, true, 0.93)
    local L2ns = { Deals = D, Sync = { OPS = {} }, Comm = ln.Comm }
    assert(loadfile("AuctionMesh/Codec.lua"))("AuctionMesh", L2ns)
    assert(loadfile("AuctionMesh/Learn.lua"))("AuctionMesh", L2ns)
    L2ns.Learn.serverTime = L.serverTime
    L2ns.Learn:Attach({})
    L2ns.Sync.OPS[90](nil, sentMsgs[1], "Friend")
    local d2 = L2ns.Learn.d
    check(#sentMsgs == 1 and d2.n == 1 and d2.ok == 1 and d2.mine == 0 and math.abs(d2.ratio - 0.93) < 0.001, "an outcome is broadcast and a friend's addon records it (as a friend's)")
    print("     " .. L2ns.Learn:Summary())
    D.cfg.margin = margin0
end

print("price history database")
S:Attach({})
local H = 3600
local t0 = 1763000000 - (1763000000 % H)
for i = 0, 30 do S:PutFair(50, 1000 - i * 10, t0 + i * H) end       -- falls 10c an hour for 30 hours
local now = t0 + 30 * H
check(#S.hist[50] == 31 * 3, "one record per item per hour (31 hours -> 31 records)")
S:PutFair(50, 695, now + 600)
check(#S.hist[50] == 31 * 3 and S.hist[50][#S.hist[50] - 1] == 695, "a second reading in the same hour replaces that hour's record")
check(S:PriceAt(50, now, 6) == 760 and S:PriceAt(50, now, 24) == 940, "can look up the price 6h and 24h ago")
local t6, t24 = S:Trend(50, now + 600, 6), S:Trend(50, now + 600, 24)
check(t6 and math.abs(t6 - (695 - 760) / 760) < 1e-9 and t24 < t6, ("trend: %d%% over 6h, %d%% over 24h"):format(t6 * 100, t24 * 100))
local lo, hi, n = S:Range(50, now, 24)
check(lo == 695 and hi == 940 and n == 25, "24h range and record count")
check(S:Trend(51, now, 6) == nil, "no history -> no trend claimed")
for i = 0, 400 do S:PutFair(52, 500, t0 + i * H) end
check(#S.hist[52] == 168 * 3, "history is capped at 7 days of hourly records per item")
local items, records = S:TrimHistory(t0 + 400 * H + 10 * 24 * H)
check(S.hist[52] == nil and S.hist[50] == nil and items == 0, "records older than 7 days are dropped at login")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
