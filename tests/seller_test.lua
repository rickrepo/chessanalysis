-- Flip Bag posting/vendor regression test (stubbed WoW API). Run: lua5.1 tests/seller_test.lua
local T = 100
local timers = {}
AuctionMeshDB = { flips = {
  [2770] = { kind = "FLIP", sell = 7900, units = 20, cost = 2000 },
  [2589] = { kind = "VENDOR", sell = 13, units = 10, cost = 5 },
} }
local bags = { [0] = { { itemID = 2770, stackCount = 20 }, { itemID = 2589, stackCount = 10 }, { itemID = 2589, stackCount = 20 } } }
C_Container = { GetContainerNumSlots = function(b) return bags[b] and 3 or 0 end,
  GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] end,
  UseContainerItem = function(b, s) bags[b][s] = nil end }
C_Item = { GetItemInfo = function(k) return "Item" .. k end }
GetTime = function() return T end
GetServerTime = function() return 1763000000 end
GetMoney = function() return 100000 end
C_Timer = { After = function(s, fn) timers[#timers + 1] = { T + s, fn } end }
local function advance(s) T = T + s; local due = timers; timers = {}; for _, t in ipairs(due) do if t[1] <= T then t[2]() else timers[#timers+1] = t end end end
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "c" end }
ItemLocation = { CreateFromBagAndSlot = function() return {} end }
local ready, postWorks = true, false
C_AuctionHouse = { IsThrottledMessageSystemReady = function() return ready end,
  CalculateCommodityDeposit = function(k, d, q) return 3 * q end,
  PostCommodity = function() if postWorks then bags[0][1] = nil end end }
AuctionHouseFrame = { IsShown = function() return true end }
MerchantFrame = { IsShown = function() return true end }
local printed = {}
local ns = { Print = function(m) printed[#printed + 1] = m; print("  > " .. m) end, Sniper = { depositOf = function() return 3 end } }
for _, f in ipairs({ "Deals", "Seller" }) do assert(loadfile("AuctionMesh/" .. f .. ".lua"))("AuctionMesh", ns) end
local S = ns.Seller
local function ok(c, l) print((c and "ok   " or "FAIL ") .. l) end
S:ScanBags()
S:OnResults(2770, { { price = 9000, qty = 50 } }, true)

print("-- AH busy")
ready = false; S:Post(2770); ok(S.posting == nil and AuctionMeshDB.flips[2770], "busy AH: nothing sent, item kept")
ready = true; T = T + 3
print("-- post rejected (bags unchanged)")
S:Post(2770); ok(S.posting ~= nil, "post in flight")
S:Post(2770); ok(#printed > 0 and printed[#printed]:find("Still posting"), "second press while posting is ignored")
S:ScanBags(); S:CheckPosted(); advance(5)
ok(S.posting == nil and AuctionMeshDB.flips[2770] and AuctionMeshDB.flips[2770].units == 20, "rejected post: item stays in Flip Bag")
print("-- error message")
S:OnResults(2770, { { price = 9000, qty = 50 } }, true); T = T + 3
S:Post(2770); S:OnError("You're doing that too fast"); ok(S.posting == nil and AuctionMeshDB.flips[2770], "error: item kept")
print("-- post works")
T = T + 3; S:OnResults(2770, { { price = 9000, qty = 50 } }, true)
postWorks = true; S:Post(2770); S:ScanBags(); S:CheckPosted()
ok(AuctionMeshDB.flips[2770] == nil, "successful post: removed only after it left the bags")
print("-- vendor")
S:ScanBags(); S:SellVendor(); for i = 1, 20 do advance(0.2) end
ok(AuctionMeshDB.flips[2589] == nil, "vendor flip sold and removed")
ok(bags[0][3] and bags[0][3].stackCount == 20, "your own 20-stack of the same item was NOT sold")
