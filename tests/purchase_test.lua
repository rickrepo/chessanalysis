-- Purchase confirmation + mailbox reconcile tests (stubbed WoW API). Run: lua5.1 tests/purchase_test.lua
local T, money, timers, handlers, printed = 100, 10000, {}, {}, {}
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
local function advance(s) T = T + s; local due = timers; timers = {}; for _, t in ipairs(due) do if t[1] <= T then t[2]() else timers[#timers + 1] = t end end end
GetTime = function() return T end
GetServerTime = function() return 1763000000 + math.floor(T) end
GetMoney = function() return money end
date = os.date
C_Timer = { After = function(s, fn) timers[#timers + 1] = { T + s, fn } end, NewTicker = function() return { Cancel = function() end } end }
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function(_, k, fn) if k == "OnEvent" then handlers[#handlers + 1] = fn end end } end
local function fire(event, ...) for _, h in ipairs(handlers) do h(nil, event, ...) end end
C_Item = { GetItemInfo = function(k) return "Item" .. k end }
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "c" end }
local sent = {}
C_AuctionHouse = {
    PlaceBid = function(id, amt) sent[#sent + 1] = "bid" end,
    StartCommoditiesPurchase = function() sent[#sent + 1] = "start" end,
    ConfirmCommoditiesPurchase = function() sent[#sent + 1] = "confirm" end,
    CancelCommoditiesPurchase = function() end,
}
AuctionMeshDB = {}
local ns = {
    Print = function(m) printed[#printed + 1] = m end, Log = function() end,
    Gate = { Ready = function() return true end, Use = function() end },
    Store = { a = {}, an = {} }, Sync = { ObserveFair = function() end },
    Seller = { LogBuy = function() end, Refresh = function() end, OnResults = function() end },
}
for _, f in ipairs({ "Deals", "Sniper" }) do assert(loadfile("AuctionMesh/" .. f .. ".lua"))("AuctionMesh", ns) end
local S = ns.Sniper
S:Init(function() return false end)

local function itemDeal(key)
    S.verified[key] = { key = key, kind = "FLIP", units = 1, cost = 500, profit = 300, sell = 900, at = T, commodity = false,
        buys = { { id = 77, buyout = 500, qty = 1, price = 500 } }, counts = { 1 } }
end
local function commodityDeal(key)
    S.verified[key] = { key = key, kind = "FLIP", units = 10, cost = 200, profit = 400, sell = 70, at = T, commodity = true,
        buys = {}, counts = {} }
end
local function flips() return AuctionMeshDB.flips or {} end

print("item buyouts")
itemDeal(1); S:Buy(1)
check(flips()[1] == nil, "nothing recorded when the buy is only sent")
advance(10)
check(flips()[1] == nil and S.buying == nil and printed[#printed]:find("NOT completed"), "no confirmation in 10s: not recorded, you're told")

itemDeal(2); S:Buy(2); money = money - 500; fire("PLAYER_MONEY")
check(flips()[2] and flips()[2].units == 1 and flips()[2].proof == "gold left your bags", "gold left your bags: recorded with proof")

itemDeal(3); S:Buy(3); fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
check(flips()[3] and flips()[3].proof == "server confirmed", "server event: recorded")

itemDeal(4); S:Buy(4); fire("UI_ERROR_MESSAGE", 0, "Internal auction error")
check(flips()[4] == nil and printed[#printed]:find("NOT completed"), "AH error during buy: not recorded")

print("commodities")
commodityDeal(5); S:Buy(5); fire("COMMODITY_PRICE_UPDATED", 20, 200); S:Confirm(); fire("COMMODITY_PURCHASE_FAILED")
check(flips()[5] == nil, "server refused: not recorded")
commodityDeal(6); S:Buy(6); fire("COMMODITY_PURCHASE_SUCCEEDED")
check(flips()[6] == nil, "success event before you confirmed is ignored")
S.buying = nil
commodityDeal(7); S:Buy(7); fire("COMMODITY_PRICE_UPDATED", 20, 200); S:Confirm(); money = money - 200; fire("COMMODITY_PURCHASE_SUCCEEDED")
check(flips()[7] and flips()[7].units == 10 and flips()[7].cost == 20, "confirmed commodity buy: recorded at real cost")
commodityDeal(8); S:Buy(8); fire("COMMODITY_PRICE_UPDATED", 30, 300)
check(S.buying == nil and flips()[8] == nil, "quote above checked price: cancelled, not recorded")

print("mailbox check")
do
    AuctionMeshDB.flips = {
        [10] = { kind = "FLIP", units = 5, cost = 20, sell = 80, at = GetServerTime() - 600 },  -- 2 in bags, 3 in mail
        [11] = { kind = "FLIP", units = 4, cost = 20, sell = 80, at = GetServerTime() - 600 },  -- nowhere: phantom
        [12] = { kind = "FLIP", units = 2, cost = 20, sell = 80, at = GetServerTime() - 30 },   -- just bought: wait
    }
    local bags = { [0] = { { itemID = 10, stackCount = 2 } } }
    C_Container = { GetContainerNumSlots = function(b) return bags[b] and 1 or 0 end, GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] end }
    local inbox = { { items = { { 10, 3 } } } }
    GetInboxNumItems = function() return #inbox, #inbox end
    GetInboxHeaderInfo = function(i) return nil, nil, nil, nil, 0, 0, nil, inbox[i] and true end
    GetInboxItem = function(i, j) local it = inbox[i].items[j]; if it then return "x", it[1], nil, it[2] end end
    local sns = { Print = function(m) printed[#printed + 1] = m end, Log = function() end, Sniper = {}, Deals = ns.Deals }
    assert(loadfile("AuctionMesh/Seller.lua"))("AuctionMesh", sns)
    local Se = sns.Seller
    Se:ScanBags(); Se:ScanMail(); Se:Reconcile()
    local e = {}
    for _, x in ipairs(Se:Entries()) do e[x.key .. x.action] = x end
    check(e["10AH"] and e["10MAIL"] and e["10MAIL"].seen, "item split between bags and mailbox, mailbox part marked seen")
    check(AuctionMeshDB.flips[11] == nil, "purchase found in neither bags nor mailbox: removed with a message")
    check(AuctionMeshDB.flips[12] and e["12MAIL"] and not e["12MAIL"].seen, "very recent purchase kept (mail may be on its way), shown as unchecked")
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
