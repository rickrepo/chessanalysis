-- End-to-end smoke test: loads the whole addon in TOC order against a fake WoW
-- client, opens the AH, feeds listings, and drives the window like a player.
-- Run: lua5.1 tests/ui_smoke.lua
local T, gold, timers, frames, chat = 100, 3200, {}, {}, {}
local pass, fail = 0, 0
local function check(c, l) if c then pass = pass + 1; print("  ok   " .. l) else fail = fail + 1; print("  FAIL " .. l) end end
local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function widget(parent, name)
    local w = { _shown = true, _scripts = {}, _events = {}, _parent = parent, _enabled = true }
    local M = {
        SetText = function(s, x) s._text = x end, GetText = function(s) return s._text end,
        SetScript = function(s, n, f) s._scripts[n] = f end,
        RegisterEvent = function(s, e) s._events[e] = true end,
        Show = function(s) s._shown = true end, Hide = function(s) s._shown = false end,
        SetShown = function(s, v) s._shown = v and true or false end, IsShown = function(s) return s._shown end,
        IsVisible = function(s) return s._shown end,
        Enable = function(s) s._enabled = true end, Disable = function(s) s._enabled = false end,
        SetEnabled = function(s, v) s._enabled = v and true or false end,
        GetParent = function(s) return s._parent end,
        CreateFontString = function(s) return widget(s) end, CreateTexture = function(s) return widget(s) end,
        GetStringHeight = function() return 12 end, GetFont = function() return "font", 10 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    }
    setmetatable(w, { __index = function(_, k) return M[k] or function() end end })
    frames[#frames + 1] = w
    if name then _G[name] = w end
    return w
end
CreateFrame = function(_, name, parent) return widget(parent, name) end
local function fire(event, ...)
    for i = 1, #frames do
        local f = frames[i]
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end
local function advance(s)
    local stop = T + s
    while T < stop do
        T = T + 0.05
        local due = timers; timers = {}
        for _, t in ipairs(due) do
            if t.at <= T then
                if not t.cancelled then t.fn(); if t.every and not t.cancelled then t.at = T + t.every; timers[#timers + 1] = t end end
            else timers[#timers + 1] = t end
        end
        for i = 1, #frames do local f = frames[i]; if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 0.05) end end
    end
end
C_Timer = {
    After = function(s, fn) timers[#timers + 1] = { at = T + s, fn = fn } end,
    NewTicker = function(s, fn) local t = { at = T + s, fn = fn, every = s }; t.Cancel = function() t.cancelled = true end; timers[#timers + 1] = t; return t end,
}
GetTime = function() return T end
GetServerTime = function() return 1763000000 + math.floor(T) end
GetMoney = function() return gold end
date = os.date
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
GetBuildInfo = function() return "12.1.7", "69913", "", 16001 end
InCombatLockdown = function() return false end
IsInGuild = function() return false end
GetChannelName = function() return 0 end
hooksecurefunc = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = strip(m) end }
SlashCmdList = {}
UIParent = widget()
GameTooltip = widget()
AuctionHouseFrame = widget(); AuctionHouseFrame:Hide()
MerchantFrame = widget(); MerchantFrame:Hide()
MailFrame = widget(); MailFrame:Hide()
Enum = { AuctionHouseSortOrder = { Price = 1 }, SendAddonMessageResult = { Success = 0 } }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() return 0 end }
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "c" end }
ItemLocation = { CreateFromBagAndSlot = function() return {} end }
GetCursorInfo = function() end

-- Fake world: items, bags, mailbox and auction house.
local ITEMS = { [2770] = { "Copper Ore", 5 }, [2589] = { "Linen Cloth", 2 }, [2447] = { "Peacebloom", 2 } }
C_Item = {
    GetItemInfo = function(k) local it = ITEMS[k]; if it then return it[1], nil, 1, 1, 1, "", "", 200, "", 1, it[2], 7, 1 end end,
    GetItemInfoInstant = function(k) return k, "", "", "", 1, 7, 1 end,
    GetItemIconByID = function() return 1 end,
}
local bags = {}
C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerItemInfo = function(b, s) return b == 0 and bags[s] or nil end,
    UseContainerItem = function(b, s) local it = bags[s]; gold = gold + ITEMS[it.itemID][2] * it.stackCount; bags[s] = nil; fire("BAG_UPDATE_DELAYED") end,
}
local inbox = {}
GetInboxNumItems = function() return #inbox, #inbox end
GetInboxHeaderInfo = function(i) return nil, nil, nil, nil, 0, 0, nil, inbox[i] and true end
GetInboxInvoiceInfo = function() return "buyer" end
GetInboxItem = function(i, j) local m = inbox[i]; if m and j == 1 then return "x", m.itemID, nil, m.stackCount end end
AutoLootMailItem = function(i) local m = table.remove(inbox, i); for s = 1, 16 do if not bags[s] then bags[s] = m; break end end; fire("BAG_UPDATE_DELAYED") end
TakeInboxMoney = function() end

local LIST = {}   -- itemID -> rows {price, qty}
local full, morePages = {}, 0
local sent, pendingBuy, posted = {}, nil, {}
C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    SupportsCopperValues = function() return true end,
    MakeItemKey = function(id) return { itemID = id } end,
    GetAuctionItemSubClasses = function() return {} end,
    SendBrowseQuery = function() sent[#sent + 1] = "browse"
        C_Timer.After(0.2, function() fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end) end,
    HasFullBrowseResults = function() return true end,
    GetBrowseResults = function() return {} end,
    HasFullCommoditySearchResults = function(id) return full[id] end,
    RequestMoreCommoditySearchResults = function(id) morePages = morePages + 1; full[id] = true
        C_Timer.After(0.2, function() fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end) end,
    SendSearchQuery = function(key) sent[#sent + 1] = "search" .. key.itemID; full[key.itemID] = false
        C_Timer.After(0.2, function() fire("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) end) end,
    GetNumCommoditySearchResults = function(id) local n = LIST[id] and #LIST[id] or 0; return full[id] and n or math.min(n, 2) end,
    GetCommoditySearchResultInfo = function(id, i) local r = LIST[id][i]; return { unitPrice = r[1], quantity = r[2], numOwnerItems = 0 } end,
    CalculateCommodityDeposit = function(id, d, q) return 1 * q end,
    StartCommoditiesPurchase = function(id, q)
        local total, need = 0, q
        for _, r in ipairs(LIST[id]) do local n = math.min(need, r[2]); total = total + n * r[1]; need = need - n end
        pendingBuy = { id = id, q = q, total = total }
        C_Timer.After(0.2, function() fire("COMMODITY_PRICE_UPDATED", total / q, total) end)
    end,
    ConfirmCommoditiesPurchase = function(id, q)
        local need = q
        while need > 0 do local r = LIST[id][1]; local n = math.min(need, r[2]); r[2] = r[2] - n; need = need - n; if r[2] == 0 then table.remove(LIST[id], 1) end end
        gold = gold - pendingBuy.total
        inbox[#inbox + 1] = { itemID = id, stackCount = q }
        C_Timer.After(0.2, function() fire("PLAYER_MONEY"); fire("COMMODITY_PURCHASE_SUCCEEDED") end)
    end,
    CancelCommoditiesPurchase = function() pendingBuy = nil end,
    PostCommodity = function(loc, dur, qty, price)
        posted[#posted + 1] = { qty = qty, price = price }
        for s = 1, 16 do if bags[s] then bags[s].stackCount = bags[s].stackCount - qty; if bags[s].stackCount <= 0 then bags[s] = nil end break end end
        C_Timer.After(0.2, function() fire("BAG_UPDATE_DELAYED") end)
    end,
}

-- Load the addon exactly as the client would.
local ns = {}
for line in io.lines("AuctionMesh/AuctionMesh.toc") do
    if line:match("%.lua$") then assert(loadfile("AuctionMesh/" .. line))("AuctionMesh", ns) end
end
fire("ADDON_LOADED", "AuctionMesh")
fire("PLAYER_LOGIN")
local UI, S, Se = ns.UI, ns.Sniper, ns.Seller
AuctionMeshDB.cfg.minProfit, ns.Deals.cfg.minProfit = 20, 20 -- the walkthrough uses small deals
ns.Deals.cfg.requireTurnover = false -- the fake auction house has no other buyers until the "volume" section
local function rowsText()
    local out = {}
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "detail") and f._shown and rawget(f, "item") then out[#out + 1] = strip(f.name._text) .. " | " .. strip(f.state._text) .. " | " .. strip(f.c[1]._text) .. " / " .. strip(f.c[2]._text) .. " / " .. strip(f.c[3]._text) .. " / " .. strip(f.c[4]._text) .. " | " .. strip(f.detail._text) .. " | " .. strip(f.profit._text) .. " | [" .. (f.btn._shown and f.btn._text or "") .. "]" end
    end
    return out
end
local function click(n) for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._shown and rawget(f, "item") then n = n - 1; if n == 0 then f.btn._scripts.OnClick(f.btn) return end end end end
local W = AuctionMeshFrame
check(W == nil, "no window until it is needed")

print("at the auction house")
-- Copper Ore: listed under vendor price (5c). Linen: 6 outliers under a deep market. Peacebloom: 500 cheap units (trap).
LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }
LIST[2447] = { { 20, 500 }, { 78, 100 }, { 80, 300 } }
for id, rows in pairs(LIST) do ns.Store:Put(id, rows[1][1], 500, GetServerTime()) end
AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW")
advance(12)
W = AuctionMeshFrame
check(W and W:IsShown() and UI.tab == "BUY", "window opens by itself on the BUY tab")
local r = rowsText()
for _, l in ipairs(r) do print("     " .. l) end
check(#r == 2, "exactly the 2 real deals are listed (the 500-unit trap is not)")
check(r[1] and r[1]:find("Copper Ore") and r[1]:find("SAFE  Buy 12 for 36c, vendor pays 60c | +24c", 1, true), "vendor deal first, exact quantity, total and profit")
check(r[2] and r[2]:find("Linen Cloth") and r[2]:find("FLIP  Buy 6 for 1s20c, relist at 77c", 1, true) and r[2]:find("| +3s18c |", 1, true), "flip shows exact buy and resale price")
check(S.verified[2447] == nil, "Peacebloom (500 cheap units) correctly rejected")
check(strip(AuctionMeshFrame.headline._text):find("MAKE NOW: +3s42c  (2 deals)", 1, true), "big headline: MAKE NOW: +3s42c (2 deals)")
check(morePages >= 3, "partial results: the rest of each listing was requested before judging")

print("buying")
click(1); advance(0.5)
check(rowsText()[1]:find("%[Confirm%]"), "Buy asks the server for the real total, then shows Confirm")
click(1); advance(1)
check(gold == 3200 - 36 and AuctionMeshDB.flips[2770] and AuctionMeshDB.flips[2770].units == 12 and AuctionMeshDB.flips[2770].cost == 3, "confirmed: 12 bought for exactly 36c and recorded")
check(chat[#chat]:find("Bought: 12 x"), "chat says Bought: 12 x ...")
-- price changes under us: someone buys the cheap linen first
LIST[2589][1][2] = 2
click(1); advance(0.5)
check(S.buying == nil and AuctionMeshDB.flips[2589] == nil and gold == 3200 - 36, "listing changed before the buy: cancelled, nothing spent")
advance(3)

print("selling")
UI.tab = "SELL"; UI:Render()
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(#r == 1 and r[1]:find("Copper Ore x12 | In your mailbox") and r[1]:find("Paid 3c  >  Sell 5c  >  %+2c each"), "SELL tab: paid, sell, profit, and where the item is")
AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
MailFrame:Show(); fire("MAIL_SHOW"); advance(2)
check(bags[1] and bags[1].itemID == 2770 and rowsText()[1]:find("Sell to any vendor"), "mailbox collected automatically; now says Sell to any vendor")
MailFrame:Hide(); fire("MAIL_CLOSED")
MerchantFrame:Show(); fire("MERCHANT_SHOW"); advance(3)
check(gold == 3200 - 36 + 60 and AuctionMeshDB.flips[2770] == nil, "vendor sold them automatically: +24c real profit, list cleared")
MerchantFrame:Hide(); fire("MERCHANT_CLOSED")

print("posting a flip")
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }
ns.Store:Put(2589, 20, 906, GetServerTime())
AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(12)
UI.tab = "BUY"; UI:Render()
check(rowsText()[1] and rowsText()[1]:find("Linen Cloth"), "linen flip found again")
click(1); advance(0.5); click(1); advance(1)
check(AuctionMeshDB.flips[2589] and AuctionMeshDB.flips[2589].units == 6, "flip bought and recorded")
MailFrame:Show(); fire("MAIL_SHOW"); advance(2); MailFrame:Hide(); fire("MAIL_CLOSED")
UI.tab = "SELL"; UI:Render(); advance(6)
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(r[1] and r[1]:find("Ready to post") and r[1]:find("Paid 20c  >  Sell 77c  >  %+53c each") and r[1]:find("%[Post%]"), "ready to post with live price and profit after the cut")
click(1); advance(1)
check(posted[1] and posted[1].qty == 6 and posted[1].price == 77 and AuctionMeshDB.flips[2589] == nil, "one click posted all 6 at 77c; removed after bags confirmed")

print("listings you can't buy (the Zesty Clam case from the real log)")
ITEMS[500] = { "Zesty Clam Meat", 500 }
LIST[500] = { { 450, 3 }, { 500, 913 }, { 750, 6 } }
ns.Store:Put(500, 450, 922, GetServerTime())
local realStart = C_AuctionHouse.StartCommoditiesPurchase
C_AuctionHouse.StartCommoditiesPurchase = function(id, q) -- server refuses the 3 cheap ones (they are yours)
    if id == 500 then C_Timer.After(0.2, function() fire("COMMODITY_PRICE_UPDATED", 500, 500 * q) end) else realStart(id, q) end
end
gold = 900; fire("PLAYER_MONEY"); UI.tab = "BUY"; advance(8)
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(r[1] and r[1]:find("Zesty Clam Meat") and r[1]:find("Buy 2 for 9s00c"), "listing looks like a deal at first")
local before = gold
click(1); advance(1)
check(gold == before and S.buying == nil, "server quoted 5s each: nothing bought, nothing spent")
check(strip(AuctionMeshFrame.status._text):find("Nothing bought, nothing spent"), "the window itself says what happened")
advance(15)
check(#rowsText() == 0 and S.verified[500] == nil, "the fake deal does not come back")

print("vendor-only mode")
UI:SetVendorOnly(true)
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }
LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
ns.Store:Put(2770, 3, 512, GetServerTime()); ns.Store:Put(2589, 20, 906, GetServerTime())
S.checkedAt = {}; advance(10)
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(#r == 1 and r[1]:find("Copper Ore") and r[1]:find("SAFE"), "vendor-only: the guaranteed deal is shown, the flip is not")
S.priority = 2589; advance(3)
check(S.verified[2589] == nil, "vendor-only: a flip is rejected even when checked")
UI:SetVendorOnly(false)

print("real sale")
GetInboxInvoiceInfo = function() return "seller", "Linen Cloth", "Buyer", 462, 0, 6, 23, nil, nil, nil, 6 end
Se:RecordSale(1); Se:RecordSale(1)
check(ns.Store.sa[2589] == 77 and ns.Store.sn[2589] == 6, "sale invoice read once: buyers paid 77c each for 6")
check(chat[#chat]:find("Sold: 6 x Linen Cloth at 77c each"), "chat reports the real sale")

print("minimum profit control")
UI:SetVendorOnly(false)
S.verified, S.checkedAt, S.floor = {}, {}, {}
LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }; ns.Store:Put(2770, 3, 512, GetServerTime())
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }; ns.Store:Put(2589, 20, 906, GetServerTime())
gold = 900; S.priority = 2770; advance(4); S.priority = 2589; advance(4)
check(S.verified[2770] ~= nil and S.verified[2589] ~= nil, "with a 20c minimum both the +24c and the +3s12c deal show")
AuctionMeshFrame.minS:SetText("1"); AuctionMeshFrame.minC:SetText("0"); UI:ApplyMinProfit()
check(S.verified[2770] == nil and S.verified[2589] ~= nil and ns.Deals.cfg.minProfit == 100, "typing 1s 0c hides the +24c deal at once, keeps the +3s12c one")
S:Evaluate(2770, { { price = 3, qty = 12 }, { price = 9, qty = 200 }, { price = 10, qty = 300 } }, true)
check(S.verified[2770] == nil and tostring(S.last.reason):find("under your"), "the small deal stays hidden; reason says it is under your minimum (" .. tostring(S.last.reason) .. ")")
UI:SetMinProfit(20)

print("real log: busy click, SELL pricing, 1s minimum posting fee")
-- a click while the server is busy is held and sent when it is free
UI:SetVendorOnly(false); UI.notice = nil; S.verified, S.checkedAt, S.floor = {}, {}, {}
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }; ns.Store:Put(2589, 20, 906, GetServerTime())
gold = 900; S.priority = 2589; advance(4)
check(S.verified[2589] ~= nil, "deal is up")
local realReady = C_AuctionHouse.IsThrottledMessageSystemReady
C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
S:Buy(2589)
check(S.queued ~= nil and S.buying == nil, "server busy at the click: the click is held, not thrown away")
C_AuctionHouse.IsThrottledMessageSystemReady = realReady
advance(1.2)
check(S.queued == nil and S.buying and S.buying.phase == "confirm", "sent by itself once the server is free: now waiting for Confirm")
S:Confirm(); advance(1.5)
check(AuctionMeshDB.flips[2589] and AuctionMeshDB.flips[2589].units == 6, "bought")
-- items waiting to be posted get priced even while the watch list is busy
GetInboxInvoiceInfo = function() return "buyer" end
MailFrame:Show(); fire("MAIL_SHOW"); advance(2); MailFrame:Hide(); fire("MAIL_CLOSED")
Se.prices = {}; advance(6)
check(Se.prices[2589] and Se.prices[2589].price == 77, "SELL tab item is priced within seconds (was stuck on 'Waiting for price check')")
-- a realm that charges at least 1s per posting
local realDep = C_AuctionHouse.CalculateCommodityDeposit
C_AuctionHouse.CalculateCommodityDeposit = function(id, d, q) return math.max(100, q) end
S.ClearFees()
ITEMS[2592] = { "Wool Cloth", 33 }
LIST[2592] = { { 34, 8 }, { 134, 11 }, { 158, 237 }, { 159, 150 }, { 160, 24 }, { 161, 126 } }
gold = 189; fire("PLAYER_MONEY"); S.priority = 2592; advance(4)
local wd = S.verified[2592]
check(wd and wd.units == 2 and wd.cost == 68 and wd.deposit == 100, "Wool 8@34c under 1s34c with 1s89c: buy 2 (68c) and keep 1s aside for the posting fee")
check(wd and wd.profit == 2 * math.floor(133 * 0.95) - 68, "profit does not subtract the fee, because it is returned on sale (+" .. tostring(wd and wd.profit) .. "c)")
C_AuctionHouse.CalculateCommodityDeposit = realDep; S.ClearFees()
S.verified[2592] = nil; UI:SetMinProfit(20); AuctionMeshDB.flips[2589] = nil

print("volume: only items that are actually selling")
ns.Deals.cfg.requireTurnover = true
UI:SetVendorOnly(false); UI.notice = nil; S.verified, S.checkedAt, S.floor, S.book = {}, {}, {}, {}
ns.Store.vu, ns.Store.vs = {}, {}
ITEMS[2318] = { "Light Leather", 2 }
LIST[2318] = { { 10, 4 }, { 30, 200 }, { 31, 300 }, { 32, 400 } }
ns.Store:Put(2318, 10, 904, GetServerTime()); gold = 900
S.priority = 2318; advance(3)
check(S.verified[2318] == nil and tostring(S.last.reason):find("measuring how fast"), "first reading: price gap seen, but no deal until volume is measured")
-- nobody buys for two minutes
advance(60); S.checkedAt = {}; S.priority = 2318; advance(3); advance(60); S.checkedAt = {}; S.priority = 2318; advance(3)
check(S.verified[2318] == nil and tostring(S.last.reason):find("not a popular item"), "nothing sold while watching: rejected as not a popular item")
-- now other players buy 150 from the market price level over the next minutes
LIST[2318][2][2] = 50
advance(60); S.checkedAt = {}; S.priority = 2318; advance(3)
local vd = S.verified[2318]
check(vd and vd.rate and vd.rate > 100 and vd.eta and vd.eta < 60, ("units are leaving the listing: deal accepted, about %d/h, sells in ~%d min"):format(vd and vd.rate or 0, vd and vd.eta or 0))
UI.tab = "BUY"; UI.notice = nil; UI:Render()
r = rowsText(); for _, l in ipairs(r) do if l:find("Light Leather") then print("     " .. l) end end
S.verified[2318] = nil; ns.Deals.cfg.requireTurnover = false

print("log resets on reload")
local before = select(2, ns.Diag:Text():gsub("\n", "")) + 1
ns.Diag:Save(); ns.Diag:Init()
local after = ns.Diag:Text()
check(before > 50 and select(2, after:gsub("\n", "")) == 0 and after:find("session start"), ("log had %d lines; after a reload it holds only the new session line"):format(before))
check(#ns.Diag:Text(true) > 1000, "the previous session is still available with /amesh log old")

print("history")
UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
local hist, seen = AuctionMeshDB.history or {}, {}
for _, h in ipairs(hist) do local m = strip(h.m); for _, w in ipairs({ "Bought:", "Collected from mailbox:", "Posted", "Sold vendor flips", "Nothing bought, nothing spent" }) do if m:find(w, 1, true) then seen[w] = true end end end
check(seen["Bought:"] and seen["Collected from mailbox:"] and seen["Posted"] and seen["Sold vendor flips"] and seen["Nothing bought, nothing spent"],
    "HISTORY lists purchases, mailbox pick-ups, posts, vendor sales and cancelled buys")
local hr = rowsTextHist and rowsTextHist() or nil
for i = 1, math.min(4, #hist) do print("     " .. strip(hist[i].m)) end
UI.tab = "BUY"

print("timers")
S:RebuildBackground(); UI.tab = "BUY"; S.searching = nil; S.last = nil; S:Evaluate(2447, { { price = 20, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI:Render()
local st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Next check: .+ in %d+%.%ds") ~= nil, "shows what is checked next and in how many seconds")
check(st:find("Last: Peacebloom: 500 cheap units is too many to clear", 1, true) ~= nil, "shows the last item checked and why it was not a deal")
check(st:find("Next price scan in") ~= nil or st:find("Price scan running") ~= nil, "shows the price scan timer")

print("watch list")
S:RebuildBackground()
check(S.background[1] == 2589 and S.background.staples >= 30, "staple low-level materials (Linen Cloth first) are always on the watch list")
local n0 = #sent
advance(130)
local c200 = 0
for i = n0 + 1, #sent do if sent[i] == "search2589" then c200 = c200 + 1 end end
check(c200 >= 2, ("the same material is re-read continuously (%d times in about 2 minutes, was once per 20 min)"):format(c200))
check(strip(AuctionMeshFrame.status._text or ""):find("Watching %d+ materials") ~= nil or UI.tab ~= "BUY", "status says what is being watched")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
