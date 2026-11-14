-- The Scout: opportunity counts, prime items, laser focus, focus codes, the daily report.
-- Run: lua5.1 tests/scout_test.lua
local T = 1763000000
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
date = os.date
GetServerTime = function() return T end
local NAMES = { [1] = "Linen Cloth", [2] = "Copper Ore", [3] = "Light Leather", [4] = "Slow Gem", [5] = "Refreshing Water", [6] = "Pricey Bar" }
C_Item = { GetItemInfo = function(k) return NAMES[k] end }
AuctionMeshDB = { cfg = { minProfit = 50, margin = 20, scope = "mats" }, realized = 24 }

local ns = {}
-- a small price store: lowest price, market price, measured turnover
ns.Store = { p = {}, t = {}, fp = {}, ft = {}, vs = {}, vu = {}, hist = {} }
function ns.Store:Rate(key, minS) local s = self.vs[key]; if not s or s < (minS or 0) then return nil end return self.vu[key] / s * 3600, s end
function ns.Store:Trend() return nil end
function ns.Store:Range() return nil end
local function put(key, low, market, perHour, watchedSec)
    local S = ns.Store
    S.p[key], S.t[key], S.fp[key], S.ft[key] = low, T, market, T
    S.vs[key], S.vu[key] = watchedSec, perHour * watchedSec / 3600
end
put(1, 60, 80, 400, 1800)    -- fast, cheap
put(2, 9, 10, 2000, 1800)    -- very fast, tiny price
put(3, 28, 30, 90, 1800)     -- fast enough
put(4, 500, 600, 4, 1800)    -- slow
put(5, 20, 25, 900, 1800)    -- fast but vendors sell it
put(6, 90000, 95000, 300, 1800) -- fast but far too expensive
put(7, 40, 50, 500, 120)     -- looks fast, but watched for 2 minutes only
local margins, mins = {}, {}
ns.Do = { Margin = function(m) margins[#margins + 1] = m; AuctionMeshDB.cfg.margin = m end }
ns.UI = { SetMinProfit = function(_, c) mins[#mins + 1] = c end, Dirty = function() end }
ns.Sniper = {}
ns.Journal = assert(loadfile("AuctionMesh/Journal.lua"))("AuctionMesh", ns)
ns.Journal.now = function() return T end
ns.Journal:Attach({})
local Scout = assert(loadfile("AuctionMesh/Scout.lua"))("AuctionMesh", ns)
Scout.hour = function() return 20 end
local d = {}
Scout:Attach(d)
local vendorSold = { [5] = true }
local function classOf(key) return 7, (key == 3) and 6 or 5 end

print("counting what the radar sees")
for _ = 1, 90 do Scout:Read(1, 78, 80) end
for _ = 1, 10 do Scout:Read(1, 60, 80) end -- 25% under market: a dip
Scout:Read(1, 60, nil)
check(d.items[1].r == 100 and d.items[1].d == 10, "100 reads with a known market, 10 of them dips (a read with no market price is not counted)")
check(d.hours[20].r == 100 and d.hours[20].d == 10, "and by hour of the day")
Scout:Deal(1, { kind = "FLIP", units = 6, cost = 360, sell = 79, profit = 90, rate = 400 })
Scout:NoDeal(2, "cheapest is $9, market $10: needs $8 or less")
Scout:NoDeal(3, "cheapest is $28, market $30: needs $24 or less")
check(d.items[1].n == 1 and d.items[1].p == 90 and #d.deals == 1 and d.deals[1].o == "seen", "a confirmed deal is logged with its profit")
check(d.reasons["cheapest is #, market #: needs # or less"] == 2, "the same reason with different numbers counts as one reason")
Scout:Gone(1, 42)
check(d.items[1].g == 1 and d.deals[1].o == "gone" and d.deals[1].life == 42, "a deal that vanished before a buy: counted, with how long it lasted (42s)")
Scout:Deal(1, { kind = "FLIP", units = 6, cost = 360, sell = 79, profit = 90, rate = 400 })
Scout:Bought(1, 6, 360)
check(d.deals[2].o == "bought", "a deal that was bought is marked bought")
Scout:Deal(3, { kind = "FLIP", units = 2, cost = 40, sell = 29, profit = 15 })
Scout:Fail(3, "price changed")
check(d.deals[3].o == "failed" and d.deals[3].why == "price changed", "a purchase that failed is marked with the reason")
Scout:Online(0.25); Scout:Online(0.25); Scout:Online(900)
local day = Scout:Day()
check(day.secs == 0.5, "working time adds up (a gap of 15 minutes is not working time)")
check(day.reads == 100 and day.checks == 5 and day.deals == 3 and day.bought == 1 and day.gone == 1 and day.fails == 1, "the day's totals")

print("prime items")
local prime = Scout:Prime(1000, vendorSold)
local order = {}
for i, f in ipairs(prime) do order[i] = f.key; print(("     %s  score %d  (%s)"):format(NAMES[f.key], f.score, Scout:Why(f, tostring))) end
check(#prime == 3, "3 items are prime: fast, measured long enough, affordable, not sold by vendors")
check(order[1] == 1, "the item that dips under market and has deals on record ranks first")
local function why(key, budget) local _, w = Scout:Score(Scout:Facts(key), budget or 1000, vendorSold[key]); return w end
check(why(4) == "sells only 4 an hour", "slow item: not prime, with the reason")
check(why(5) == "vendors sell it, so its price cannot rise", "vendor-sold item: not prime")
check(why(6) == "costs more than you have", "too expensive: not prime")
check(why(7) == "not watched long enough to know how fast it sells", "watched for 2 minutes: not prime yet")

print("laser focus")
local set, list, text = Scout:Focus(1000, vendorSold, classOf)
check(set == nil and text == "Focus is off: every material is watched.", "off: no limit")
check(Scout:SetMode() == "prime", "one click: prime items")
set, list, text = Scout:Focus(1000, vendorSold, classOf)
print("     " .. text)
check(set and set[1] and set[2] and set[3] and not set[4] and #list == 3, "focus is exactly the 3 prime items")
Scout.cfg.primeMin = 5; Scout:Changed()
set, list, text = Scout:Focus(1000, vendorSold, classOf)
print("     " .. text)
check(set == nil and text:find("^Focus is waiting: 3 prime items so far, 5 needed"), "too few prime items measured yet: no limit, and it says so")
Scout.cfg.primeMin = 3
check(Scout:SetMode() == "list", "next click: my own list")
set, list, text = Scout:Focus(1000, vendorSold, classOf)
check(set == nil and text:find("^Your focus list is empty"), "an empty list does not limit anything, and says how to fill it")
check(Scout:Toggle(4) == true and Scout:InList(4), "an item can be added to the list")
set, list = Scout:Focus(1000, vendorSold, classOf)
check(set and set[4] and #list == 1, "focus is that one item")
check(Scout:Toggle(4) == false and not Scout:InList(4), "and removed again")
check(Scout:SetMode() == "off", "next click: off")

print("focus codes")
local ok, msg = Scout:ApplyCode("please use AMF1:1, 3, c7.5, m25, p150 today")
print("     " .. msg)
check(ok and AuctionMeshDB.cfg.focusMode == "list" and #AuctionMeshDB.cfg.focusItems == 2 and AuctionMeshDB.cfg.focusCats[1] == "7.5", "a code sets the items, the categories and switches focus to the list")
check(margins[1] == 25 and mins[1] == 150, "and can set the flip profit and the smallest deal")
set, list = Scout:Focus(1000, vendorSold, classOf)
check(set[1] and set[3] and set[2] and not set[4] and #list == 3, "the category brings in its prime items (Copper Ore), not its slow ones")
check(Scout:Code() == "AMF1:1,3,c7.5", "the current focus can be read back as a code")
ok, msg = Scout:ApplyCode("hello")
check(not ok and msg:find("not a focus code"), "anything else is refused with a plain sentence")

print("the daily report")
local a = ns.Journal:Bought(1, "Linen Cloth", "FLIP", 6, 60, 79)
ns.Journal:Posted(1, 6, 79); T = T + 1800; ns.Journal:Sold(1, 6, 79, 450); T = T + 60
local rep = Scout:Report({ version = "9.9.9", realm = "Test Realm", gold = 1000, vendorOf = function(k) return k == 2 and 5 or nil end,
    vendorSold = vendorSold, classOf = classOf, sharing = "nobody", errors = 2 })
print(rep)
local function has(s) return rep:find(s, 1, true) ~= nil end
check(has("=== AUCTIONMESH DAILY REPORT v1 ===") and has("=== END OF REPORT ==="), "one block with a clear start and end")
check(has("addon 9.9.9 | realm Test Realm") and has("gold 1000c") and has("focus code: AMF1:1,3,c7.5"), "header: version, realm, gold, settings and the focus code")
check(has("today | 0 | 100 | 5 | 3 | 195 | 1 | 360 | 1 | 1"), "the day's line")
check(has("Linen Cloth(1) | 6 | 60 | 79 | 0@79 | 6@79 | 0 | 450 | 90 | 0 | 0.5 |"), "a trade: cost, plan, sold price, what came back, profit, hours to sell")
check(has("Linen Cloth(1) | FLIP | 6 | 360 | 79 | 90 | 400 | bought") and has("| gone after 42s") and has("| failed (price changed)"), "deals seen with what became of each")
check(has("2 x cheapest is #, market #: needs # or less"), "why checks were not deals")
check(has("20: 100/10/3"), "reads, dips and deals by hour")
check(has("Copper Ore(2) | 9 | 10 | 5 | 2000 | 30 | 20000 |") and has("| PRIME"), "market table: prices, vendor price, sells per hour, copper traded per hour, prime or not")
check(has("no: sells only 4 an hour") and has("no: costs more than you have"), "and for the others, the reason they are not prime")
check(#rep < 12000, ("small enough to paste: %d characters"):format(#rep))

print("old days are dropped")
T = T + 9 * 86400
Scout:Day()
local n = 0
for _ in pairs(d.days) do n = n + 1 end
check(n == 1 and next(d.reasons) == nil, "after 9 days only today is kept, and the reasons start again")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
