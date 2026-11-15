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
        GetParent = function(s) return s._parent end, SetParent = function(s, p) s._parent = p end,
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
sentAddon = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(_, msg) sentAddon[#sentAddon + 1] = msg; return 0 end }
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
local ns = { plainMoney = true } -- tests read plain "1s20c" text; the game shows coin icons
for line in io.lines("AuctionMesh/AuctionMesh.toc") do
    if line:match("%.lua$") then assert(loadfile("AuctionMesh/" .. line))("AuctionMesh", ns) end
end
fire("ADDON_LOADED", "AuctionMesh")
fire("PLAYER_LOGIN")
local UI, S, Se = ns.UI, ns.Sniper, ns.Seller
AuctionMeshDB.cfg.minProfit, ns.Deals.cfg.minProfit = 20, 20 -- the walkthrough uses small deals
-- The walkthrough below drives the two-click path (first click asks for the price, second buys),
-- which is what happens when the game does not allow a price request without a click.
-- One-click buying and holding fire have their own section at the end.
AuctionMeshDB.cfg.prearm = false; S.hold = 0
ns.Deals.cfg.requireTurnover = false -- the fake auction house has no other buyers until the "volume" section
local function rowsText()
    local out = {}
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "detail") and f._shown and rawget(f, "item") then out[#out + 1] = strip(f.name._text) .. " | " .. strip(f.state._text) .. " | " .. strip(f.c[1]._text) .. " / " .. strip(f.c[2]._text) .. " / " .. strip(f.c[3]._text) .. " / " .. strip(f.c[4]._text) .. " | " .. strip(f.detail._text) .. " | " .. strip(f.profit._text) .. " | [" .. (f.btn._shown and f.btn._text or "") .. "]" end
    end
    return out
end
-- only the rows that offer something to buy (your own auctions are listed on the same tab)
local function dealRows()
    local out = {}
    for _, l in ipairs(rowsText()) do if l:find("| SAFE", 1, true) or l:find("| FLIP", 1, true) then out[#out + 1] = l end end
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
check(UI.docked == true and W._parent == AuctionHouseFrame, "it opens INSIDE the auction house window")
check(AuctionMeshAHTab ~= nil, "an AuctionMesh tab is added under the auction house window")
AuctionHouseFrame.IsMouseOver = function() return true end
check(ns.Gate:UserBusy() == false, "mouse over the auction house window does not pause anything")
UI:Close()
check(ns.Gate:UserBusy() == true and ns.Gate:Ready() == false, "panel closed (you are on the game's own screens): the addon sends nothing")
UI:Open("BUY")
check(ns.Gate:UserBusy() == false, "panel open again: it works again")
local r = rowsText()
for _, l in ipairs(r) do print("     " .. l) end
check(#r == 2, "exactly the 2 real deals are listed (the 500-unit trap is not)")
check(r[1] and r[1]:find("Copper Ore") and r[1]:find("SAFE  Buy 12 for 36c, vendor pays 60c | +24c", 1, true), "vendor deal first, exact quantity, total and profit")
check(r[2] and r[2]:find("Linen Cloth") and r[2]:find("FLIP  Buy 6 for 1s20c, relist at 77c", 1, true) and r[2]:find("| +3s18c |", 1, true), "flip shows exact buy and resale price")
check(S.verified[2447] == nil, "Peacebloom (500 cheap units) correctly rejected")
check(strip(AuctionMeshFrame.footer._text):find("Make now  + 3s42c  (2 deals)", 1, true), "footer: Make now + 3s42c (2 deals)")
check(morePages >= 1 and morePages < 3, ("first page already proves a deal: acted on at once; only the item that was NOT a deal had the rest of its listing fetched (%d extra page)"):format(morePages))

print("buying")
click(1); advance(0.5)
check(rowsText()[1]:find("%[BUY NOW%]"), "Buy asks the server for the real total, then shows BUY NOW")
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
check(gold == 3200 - 36 and AuctionMeshDB.flips[2770] ~= nil, "opening a vendor sells NOTHING by itself")
check(AuctionMeshFrame.vend._shown and strip(AuctionMeshFrame.vend._text) == "Sell all to vendor  +60c", "the panel offers one button: Sell all to vendor +60c")
AuctionMeshFrame.vend._scripts.OnClick(AuctionMeshFrame.vend); advance(3)
check(gold == 3200 - 36 + 60 and AuctionMeshDB.flips[2770] == nil, "after your click: sold, +24c real profit, list cleared")
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
UI.tab = "SELL"; UI.notice = nil; UI:Render()
check(#rowsText() == 0, "Bags tab is empty once everything is posted")
UI.tab = "BUY"; UI:Render()
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(r[1] and r[1]:find("Linen Cloth x6") and r[1]:find("LISTED") and r[1]:find("+3s18c", 1, true), "the posted auction is on the Trades tab as LISTED with its expected profit")
check(AuctionMeshDB.realized == 24, "banked profit so far: +24c from the vendor sale")
local function heads()
    local out = {}
    for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._shown and rawget(f, "sect") then out[#out + 1] = strip(f.head._text) end end
    return out
end
do  -- the MONEY section on the Trades tab: label on the left, amount on the right, ruled total
    local lg = AuctionMeshFrame.ledger
    local function val(row) return strip(row.value._text) end
    for i = 1, 5 do print("     " .. lg.rows[i].label._text .. " | " .. val(lg.rows[i])) end
    print("     " .. lg.total.label._text .. " | " .. val(lg.total))
    print("     " .. strip(lg.note._text))
    local hd = heads()
    print("     sections: " .. table.concat(hd, " / "))
    check(lg:IsShown(), "Trades tab opens with the MONEY section")
    check(hd[1] == "DEALS TO BUY NOW (0)" and hd[2]:find("^None right now") and hd[3] == "LISTED (1)", "below it: deals to buy, then your auctions, each under a grey heading")
    check(val(lg.rows[1]) == strip(ns.Seller.short(GetMoney())), "MONEY: gold on this character now")
    check(val(lg.rows[4]) == "+ 4s38c", "MONEY: 6 listed at 77c = + 4s38c after the 5% cut")
    check(val(lg.rows[2]) == "-" and val(lg.rows[3]) == "-" and val(lg.rows[5]) == "-", "MONEY: nothing sold yet, nothing waiting to be listed")
    check(val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)), "MONEY: total when it has all sold = gold + listings")
    -- someone lists cheaper: the auction moves to STUCK LISTINGS
    ns.Store:Put(2589, 70, 900, GetServerTime()); UI:Render()
    check(heads()[3] == "STUCK LISTINGS (1)", "a cheaper listing appears: the auction moves under STUCK LISTINGS")
    -- recommendations for that auction, and the drawer's one-item view
    local listedEntry
    for _, e in ipairs(Se:Entries()) do if e.action == "LISTED" and e.key == 2589 then listedEntry = e end end
    local adv, tone = Se:Advice(listedEntry)
    print("     " .. strip(adv))
    check(tone == "do" and strip(adv):find("Someone lists at 70c. Cancel yours", 1, true) and strip(adv):find("post again at 69c: still + 2s70c", 1, true),
        "undercut with profit left: recommends cancel and repost at 69c, and says what is left (+ 2s70c)")
    ns.Deals.cfg.minProfit = 500
    adv, tone = Se:Advice(listedEntry)
    check(tone == "wait" and strip(adv):find("^Wait. Someone lists at 70c; going under that would leave %+ 2s70c, less than your minimum"), "undercut, repost not worth it: recommends waiting")
    ns.Deals.cfg.minProfit = 20
    ns.Store.p[2589] = 78 -- the cheaper listing is gone again
    adv, tone = Se:Advice(listedEntry)
    print("     " .. strip(adv))
    check(tone == "wait" and strip(adv):find("^Wait. No cheaper listing in the last radar read") and strip(adv):find("Runs out in about 12h"), "cheapest on the market: wait, with the time the auction has left")
    do
        local row
        for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._shown and rawget(f, "item") and f.item.key == 2589 then row = f end end
        row._scripts.OnMouseUp(row, "LeftButton")
        check(AuctionMeshDrawer:IsShown() and UI.sel == 2589, "clicking an item row opens the drawer on that item")
        local dl = UI.drawerLines
        for _, l in ipairs(dl) do print("     " .. (l.rule and "----" or strip((l.head or l.l or "")) .. (l.r and ("  |  " .. strip(l.r)) or ""))) end
        local function has(pat) for _, l in ipairs(dl) do if strip((l.head or l.l or "") .. " | " .. (l.r or "")):find(pat) then return true end end return false end
        check(has("^MARKET") and has("^Cheapest listing | 78c") and has("^A vendor pays"), "one item: the market as last read")
        check(has("^YOUR TRADES IN THIS ITEM %\(1%\)") and has("^Bought at 20c each | %- 1s20c") and has("^On the auction house: 6 at 77c each | %+ 4s38c") and has("^Profit if this sells | %+ 3s18c"),
            "one item: the trade with what was paid, where it is now and the profit if it sells")
        check(has("^WAIT  No cheaper listing"), "one item: the recommendation, marked WAIT")
        AuctionMeshDrawer.views.trades._scripts.OnClick(AuctionMeshDrawer.views.trades)
        check(UI.sel == nil, "'Trades' goes back to the full list")
        UI:ToggleDrawer(false)
    end
    -- a sale the game is still holding back, read from the mailbox invoice
    AuctionMeshDB.sales = { waiting = 150, pending = { { amount = 438, at = GetServerTime() + 16 * 60, key = 2589 }, { amount = 90, at = GetServerTime() - 5 } } }
    UI:Render()
    print("     " .. lg.rows[2].label._text .. " | " .. val(lg.rows[2]))
    print("     " .. lg.rows[3].label._text .. " | " .. val(lg.rows[3]))
    check(val(lg.rows[2]) == "+ 2s40c", "MONEY: sale gold in the mailbox now (150c there + 90c that has arrived since)")
    check(val(lg.rows[3]) == "+ 4s38c  next 16 min", "MONEY: sale gold still on its way, with the time of the next arrival")
    AuctionMeshDB.sales = nil
    -- the auction house no longer shows the auction (it sold, or the read is wrong): its value is still counted
    local ownWas, readWas = S.own, S.ownRead
    S.own, S.ownRead = {}, true
    UI.tab = "BUY"; UI:Render()
    print("     " .. lg.rows[4].label._text .. " | " .. val(lg.rows[4]))
    print("     " .. strip(lg.note._text))
    check(val(lg.rows[4]) == "+ 4s38c" and val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)), "an auction the auction house no longer shows is still counted in the total")
    check(strip(lg.note._text):find("1 of your auctions is no longer seen on the auction house", 1, true), "and the note says so")
    -- the auction house itself reports the auction as sold and waiting to be paid
    Enum.AuctionStatus = { Active = 0, Sold = 1 }
    C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
    C_AuctionHouse.GetOwnedAuctionInfo = function() return { itemKey = { itemID = 2589 }, status = 1, quantity = 6, buyoutAmount = 77 } end
    S:ReadOwned(); UI:Render()
    print("     " .. lg.rows[3].label._text .. " | " .. val(lg.rows[3]))
    check(val(lg.rows[3]) == "+ 4s38c" and val(lg.rows[4]) == "-" and val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)),
        "an auction the game lists as sold moves to 'Sold: still on its way' without a mailbox visit; the total stays the same")
    C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
    S.ownSoldQty = {}
    S.own, S.ownRead = ownWas, readWas
    UI.tab = "SELL"; UI:Render()
    check(not lg:IsShown(), "the Bags tab has no MONEY section")
    UI.tab = "HISTORY"; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp:IsShown() and sp.rows[1].label._text == "Server limit, measured", "Setup tab: settings and what the request engine has learned")
    for i = 1, 7 do print("     " .. tostring(sp.rows[i].label._text) .. " | " .. strip(sp.rows[i].value._text)) end
    local st = UI.barState
    print("     bar: " .. st.mode .. " " .. ("%.2f"):format(st.fill) .. " " .. st.text)
    check(st and st.text ~= "" and strip(AuctionMeshFrame.barText._text):find(st.text, 1, true) == 1, "the engine bar is on every tab and says what the engine is doing")
    UI.tab = "BUY"; UI:Render()
end

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
check(#dealRows() == 0 and S.verified[500] == nil, "the fake deal does not come back")

print("vendor-only mode")
UI:SetVendorOnly(true)
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }
LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
ns.Store:Put(2770, 3, 512, GetServerTime()); ns.Store:Put(2589, 20, 906, GetServerTime())
S.checkedAt = {}; advance(10)
r = dealRows(); for _, l in ipairs(r) do print("     " .. l) end
check(#r == 1 and r[1]:find("Copper Ore") and r[1]:find("SAFE"), "vendor-only: the guaranteed deal is shown, the flip is not")
S.priority = 2589; advance(3)
check(S.verified[2589] == nil, "vendor-only: a flip is rejected even when checked")
UI:SetVendorOnly(false)

print("real sale")
GetInboxInvoiceInfo = function() return "seller", "Linen Cloth", "Buyer", 462, 0, 6, 23, nil, nil, nil, 6 end
Se:RecordSale(1); Se:RecordSale(1)
check(ns.Store.sa[2589] == 77 and ns.Store.sn[2589] == 6, "sale invoice read once: buyers paid 77c each for 6")
check(AuctionMeshDB.realized == 24 + (462 - 23 - 120) and (AuctionMeshDB.listed or {})[2589] == nil,
    ("sale collected: banked profit is now %dc and the listing leaves the portfolio"):format(AuctionMeshDB.realized or 0))
check(chat[#chat]:find("Sold: 6 x Linen Cloth at 77c each. Profit +319c", 1, true), "chat reports the sale and the profit made")
check(AuctionMeshDB.cfg.feeBack == true and ns.Deals.cfg.depositIsCost == false and chat[#chat - 1]:find("the posting fee comes back when an auction sells", 1, true),
    "the invoice shows the posting fee came back: confirmed for this realm, profits stay as they are")
check(ns.Learn.d.n == 1 and ns.Learn.d.ok == 1 and math.abs(ns.Learn.d.ratio - 1) < 0.01, "the sale is scored against its prediction: sold at 100% of plan")

print("an auction that expires")
do
    -- we listed 5 Wool Cloth an hour ago; it is no longer among our auctions and sits in the mailbox
    ITEMS[2592] = { "Wool Cloth", 33 }
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, at = GetServerTime() - 3600 } }
    S.own, S.ownRead = {}, true
    for s2 = 1, 16 do bags[s2] = nil end
    inbox = { { itemID = 2592, stackCount = 5 } }
    GetInboxInvoiceInfo = function() return nil end
    AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
    local f = AuctionMeshDB.flips[2592]
    check(f and f.units == 5 and f.cost == 34 and AuctionMeshDB.listed[2592] == nil, "expired auction is back in the portfolio with what it cost you")
    check(bags[1] and bags[1].itemID == 2592 and #inbox == 0, "and it was collected from the mailbox")
    check(ns.Learn.d.fail == 1 and ns.Learn:Blocked(2592) ~= nil, "the failure is scored: that item is on hold for new flips")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    AuctionMeshDB.flips[2592] = nil; bags[1] = nil
    GetInboxInvoiceInfo = function() return "buyer" end
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(2)
    ns.Learn.d.items[2592] = nil
end

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
-- a click while the server is busy goes out inside the click (the game queues it itself)
UI:SetVendorOnly(false); UI.notice = nil; S.verified, S.checkedAt, S.floor = {}, {}, {}
LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }; ns.Store:Put(2589, 20, 906, GetServerTime())
gold = 900; S.priority = 2589; advance(4)
check(S.verified[2589] ~= nil, "deal is up")
local realReady = C_AuctionHouse.IsThrottledMessageSystemReady
C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
S:Buy(2589)
check(S.buying and S.buying.phase == "quote", "server busy at the click: the request is sent at once, inside the click (not held back)")
C_AuctionHouse.IsThrottledMessageSystemReady = realReady
advance(1.2)
check(S.buying and S.buying.phase == "confirm", "the price comes back: now waiting for the second click")
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
check(S.verified[2318] == nil and tostring(S.reasons[2318]):find("measuring how fast"), "first reading: price gap seen, but no deal until volume is measured")
-- nobody buys for six minutes (a selling speed is only believed after 5 minutes of watching)
advance(180); S.checkedAt = {}; S.priority = 2318; advance(3); advance(180); S.checkedAt = {}; S.priority = 2318; advance(3)
check(S.verified[2318] == nil and tostring(S.reasons[2318]):find("not a popular item"), "nothing sold while watching: rejected as not a popular item")
-- now other players buy 150: the 4 cheap ones first (buyers always get the cheapest), then 146 at the market price
LIST[2318] = { { 30, 54 }, { 31, 300 }, { 32, 400 } }
advance(60); S.checkedAt = {}; S.priority = 2318; advance(3)
check(ns.Store:Rate(2318, 0) and ns.Store:Rate(2318, 0) > 100, "units eaten from the cheap end of the listing are counted as sold")
-- and someone lists 4 cheap ones again
LIST[2318] = { { 10, 4 }, { 30, 54 }, { 31, 300 }, { 32, 400 } }
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
check(before > 50 and select(2, after:gsub("\n", "")) <= 1 and after:find("session start"), ("log had %d lines; after a reload it holds only the new session header"):format(before))
check(#ns.Diag:Text(true) > 1000, "the previous session is still available (Setup tab, Last session's log)")

print("history")
UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
local hist, seen = AuctionMeshDB.history or {}, {}
for _, h in ipairs(hist) do local m = strip(h.m); for _, w in ipairs({ "Bought:", "Collected from mailbox:", "Posted", "Sold vendor flips", "Nothing bought, nothing spent" }) do if m:find(w, 1, true) then seen[w] = true end end end
check(seen["Bought:"] and seen["Collected from mailbox:"] and seen["Posted"] and seen["Sold vendor flips"] and seen["Nothing bought, nothing spent"],
    "HISTORY lists purchases, mailbox pick-ups, posts, vendor sales and cancelled buys")
for i = 1, math.min(4, #hist) do print("     " .. strip(hist[i].m)) end
UI.tab = "BUY"
UI:ToggleDrawer(true)
AuctionMeshDrawer.views.activity._scripts.OnClick(AuctionMeshDrawer.views.activity)
check(UI.drawerLines[1].head == ("RECENT ACTIVITY (%d)"):format(#hist) and strip(UI.drawerLines[2].l):find(strip(hist[1].m):sub(1, 20), 1, true),
    "the drawer's Activity view lists it, newest first")
AuctionMeshDrawer.views.market._scripts.OnClick(AuctionMeshDrawer.views.market)
do
    local hs = {}
    for _, l in ipairs(UI.drawerLines) do if l.head then hs[#hs + 1] = l.head end end
    check(hs[1]:find("^PRIME ITEMS") and hs[2] == "BIGGEST PRICE MOVES, 24 HOURS" and hs[3] == "WHAT SELLS FASTEST, MEASURED",
        "the drawer's Market view shows prime items, price moves and what sells fastest")
end
for _, l in ipairs(UI.drawerLines) do print("     " .. strip((l.head or l.l or "")) .. (l.r and ("  |  " .. strip(l.r)) or "")) end
UI.dview = "trades"; UI:ToggleDrawer(false)

print("setup: a control for everything, no commands")
do
    UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
    local sp, cfg = AuctionMeshFrame.setup, AuctionMeshDB.cfg
    local function press(b) b._scripts.OnClick(b) end
    print("     " .. sp.flips._text .. " | " .. sp.scope._text .. " | " .. sp.dock._text .. " | " .. sp.auto._text .. " | " .. sp.tune._text)
    print("     " .. strip(sp.share._text))
    check(sp.scope._text == "Crafting materials", "the radar button shows what is being read")
    press(sp.scope); UI:Render()
    check(cfg.scope == "money" and ns.Swarm.scope == "money" and sp.scope._text == "All money-makers", "one click moves to the next choice and applies it")
    press(sp.scope); press(sp.scope); UI:Render()
    check(cfg.scope == "mats" and sp.scope._text == "Crafting materials", "and round again to crafting materials")
    sp.margin:SetText("35"); sp.margin._scripts.OnEditFocusLost(sp.margin)
    check(cfg.margin == 35 and math.abs(ns.Deals.cfg.margin - 0.35) < 1e-9, "the flip profit box sets the margin (35%)")
    sp.margin:SetText("20"); sp.margin._scripts.OnEditFocusLost(sp.margin)
    press(sp.auto); UI:Render()
    check(cfg.autoOpen == false and sp.auto._text == "Opens by itself: off", "opens-by-itself switch")
    press(sp.auto)
    press(sp.tune); UI:Render()
    check(ns.Tuner.cfg.enabled == false and ns.Learn.cfg.autoTune == false and sp.tune._text == "Self-tuning: off", "one switch for all self-tuning")
    press(sp.tune)
    local n0 = ns.Tuner.d.n
    press(sp.forget); UI:Render()
    check(ns.Tuner.d.n == n0 and sp.forget._text == "Click again to forget", "forgetting what was learned asks for a second click")
    press(sp.forget); UI:Render()
    check(ns.Tuner.d.n == 0 and sp.forget._text == "Forget what was learned", "the second click clears it")
    sp.chan:SetText("mesh"); sp.pass:SetText("secret"); press(sp.join)
    check(cfg.channel == "mesh" and cfg.password == "secret" and cfg.route == "channel", "channel name and password are typed into two boxes, then Join")
    check(type(AuctionMesh_OnAddonCompartmentClick) == "function", "the game's addon list can open the panel")
    for _, f in ipairs({ "AuctionMesh/UI.lua", "AuctionMesh/Seller.lua", "AuctionMesh/Sniper.lua", "AuctionMesh/Swarm.lua", "AuctionMesh/Scanner.lua", "AuctionMesh/Sync.lua" }) do
        local bad
        for line in io.lines(f) do if line:find("/amesh", 1, true) and not line:match("^%s*%-%-") then bad = line end end
        check(not bad, f:match("[^/]+$") .. ": no message tells the player to type a command")
    end
    UI.tab = "BUY"; UI:Render()
end

print("sharing: a friend's sweep triggers a check here; next-step line")
ns.Deals.cfg.requireTurnover = false
S.verified, S.checkedAt, S.floor, S.sweep, S.triggers = {}, {}, {}, {}, {}
LIST[2592], LIST[2589], LIST[2770], LIST[500], LIST[2318], LIST[2319] = nil, nil, nil, nil, nil, nil -- leftovers from earlier sections
ITEMS[4234] = { "Heavy Leather", 2 }
LIST[4234] = { { 60, 4 }, { 190, 300 }, { 191, 300 } }
ns.Store:PutFair(4234, 190, GetServerTime()); gold = 900
check(ns.Sync:PeerCount() == 0, "nobody connected yet")
-- a friend's addon broadcasts the lowest price it just saw (a normal "D" message)
local bld = ns.Codec.newDelta(GetServerTime()); bld:add(4234, 60, 604, GetServerTime())
local n1 = #sent
ns.Sync.Dispatch(bld:finish(), "Friend-Realm"); advance(3)
local c = 0; for i = n1 + 1, #sent do if sent[i] == "search4234" then c = c + 1 end end
check(ns.Sync:PeerCount() == 1, "the friend shows up as connected")
check(c == 1 and S.verified[4234] and S.verified[4234].units == 4, "the friend's price update triggered one check here and the deal is confirmed")
UI.tab = "BUY"; UI.notice = nil; UI:Render()
local nx = strip(AuctionMeshFrame.next._text)
print("     " .. nx)
check(nx:find("NEXT  Press Buy on Heavy Leather: pay 2s40c, make +", 1, true), "NEXT line says exactly what to press and what it makes")
S.verified[4234] = nil

print("request budget (limits measured from real logs)")
do
    -- a search for an item whose details are not loaded is never sent, and costs nothing
    local n2 = #sent
    S.searching = nil
    check(S:Search(987654) == false and #sent == n2 and S.searching == nil, "item details not loaded: no request is spent and the queue is not blocked")
    -- the best trigger is confirmed first
    S.triggers, S.verified, S.checkedAt = {}, {}, {}
    ITEMS[11] = { "A", 2 }; ITEMS[12] = { "B", 2 }; ITEMS[13] = { "C", 2 }
    S:AddTrigger(11, "20% under market", 80, 100)
    S:AddTrigger(12, "at or under vendor price", 5, 100)
    S:AddTrigger(13, "20% under market", 40, 100)
    S.priority = nil; ns.Seller.pending = nil
    local a, b, c3 = S:NextCheck(), S:NextCheck(), S:NextCheck()
    check(a == 12 and b == 13 and c3 == 11, "triggers are confirmed best-first: vendor hit, then the biggest gap, then the smaller one")
    -- one request sweeps the whole class; the radar interval follows the measured cost
    local Sw = ns.Swarm
    check(#Sw.units == 1, "the sweep asks for the whole materials class in one request (was one per sub-category)")
    Sw.cfg.adaptive = true
    Sw.cfg.sweepShare, Sw.cfg.perRequest = 0.30, 0.65 -- the figures the Tuner starts from
    Sw:Tune(Sw.units[1], 1); local f1 = Sw.cfg.fresh
    Sw:Tune(Sw.units[1], 6); local f6 = Sw.cfg.fresh
    check(f1 == 3 and f6 == 13, ("radar interval follows the sweep's real cost: 1 request -> every %ds, 6 requests -> every %ds"):format(f1, f6))
    Sw:Tune(Sw.units[1], 1)
    -- the addon measures what one request returns and how fast requests go, instead of assuming
    local function page(n, first)
        local res = {}
        for i = 1, n do res[i] = { itemKey = { itemID = 900000 + i + (first and 0 or 1000) }, minPrice = 100, totalQuantity = 5 } end
        ns.Scanner:OnBrowse(res, first)
    end
    ns.measure.pages, ns.measure.items, ns.measure.pageMax = 0, 0, 0
    page(50, true); page(50, false); page(23, false)
    Sw:Tune(Sw.units[1], 3)
    local ML = ns.measure.last
    check(ML and ML.items == 123 and ML.requests == 3 and ML.pageMax == 50, "sweep measured: 123 items in 3 requests, largest page 50")
    local T0 = ns.Tuner.d.n
    for _ = 1, 12 do
        ns.Gate:Use("test request", "search")
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT"); advance(0.15)
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"); advance(0.5)
        fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    end
    local G = ns.Gate
    local TD = ns.Tuner.d
    check(G.cycle and G.cycle > 0.6 and G.cycle < 0.8 and TD.n == T0 + 12 and math.abs(Sw.cfg.perRequest - ns.Tuner:Expected()) < 1e-9,
        ("request limit measured live: %.2fs per request, learned per kind and hour, and the sweep interval uses it"):format(G.cycle or 0))
    check(TD.kinds.search.n >= 1 and TD.kinds.search.cycle > 0.6 and TD.kinds.search.cycle < 0.8, "the Tuner learned what an item check costs from the live events")
    ns.Gate.userUntil = GetTime() + 5 -- nothing in the background while your own action is in flight
    ns.Gate:Use("post something"); fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT"); advance(0.15)
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"); advance(0.5); fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(TD.n == T0 + 12, "your own clicks are not used for learning")
    ns.Gate.userUntil = 0
    G.sawSent = false; Sw:Tune(Sw.units[1], 1)
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
    for l in strip(AuctionMeshFrame.status._text):gmatch("[^\n]+") do if l:find("Radar") then print("     " .. l) end end
    -- the queue moves the instant the auction house unlocks
    S.triggers, S.verified, S.checkedAt = {}, {}, {}
    LIST[2589] = { { 100, 300 }, { 101, 300 } }
    S:AddTrigger(2589, "price just dropped", 90, 100)
    local n3 = #sent; S.searching = nil; ns.Gate.nextAt = 0; ns.Gate.outstanding = 0
    ns.lastQuery = "swarm" -- the radar has just had its turn
    ns.OnAHReady()
    check(#sent == n3 + 1 and sent[#sent] == "search2589", "the next request goes out in the same frame the auction house unlocks")
    advance(1); S.verified[2589] = nil; LIST[2589] = nil
end

print("timers")
S:RebuildBackground(); UI.tab = "BUY"; S.searching = nil; S.last = nil; S.lastEval = nil; S:Evaluate(2447, { { price = 20, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI:Render()
local st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Next check: .+ in %d+%.%ds") ~= nil, "shows what is checked next and in how many seconds")
check(st:find("Last: Peacebloom: 500 cheap units is too many to clear", 1, true) ~= nil, "shows the last item checked and why it was not a deal")
check(st:find("Radar:.- re%-read every %d+s") ~= nil, "shows the radar line")

print("radar: category sweeps find the drop, one full search confirms it")
ns.Deals.cfg.requireTurnover = false
UI:SetVendorOnly(false); UI.notice = nil
S.verified, S.checkedAt, S.floor, S.sweep, S.triggers, S.candidates = {}, {}, {}, {}, {}, {}
S.background = { i = 1 }; S.lastBg = GetTime() + 1e6; S.lastScreen = GetTime() + 1e6 -- radar only
ITEMS[2319] = { "Medium Leather", 2 }
LIST[2319] = { { 100, 300 }, { 101, 300 } }
ns.Store:PutFair(2319, 100, GetServerTime()); gold = 900
local function sweep(minPrice, qty) ns.Scanner:OnBrowse({ { itemKey = { itemID = 2319 }, minPrice = minPrice, totalQuantity = qty } }, true) end
local n0 = #sent
sweep(100, 600); advance(3)
local function searches() local c = 0; for i = n0 + 1, #sent do if sent[i] == "search2319" then c = c + 1 end end; return c end
check(searches() == 0, "normal price in the sweep: no single-item search is spent on it")
LIST[2319] = { { 40, 5 }, { 100, 300 }, { 101, 300 } }
advance(30); sweep(40, 605); advance(3)
check(searches() == 1 and S.verified[2319] and S.verified[2319].units == 5, "someone lists 5 at 40c: the next sweep spots it and ONE search confirms the deal")
advance(30); sweep(40, 505); advance(30); sweep(40, 455)
local churn = ns.Store:Churn(2319)
check(churn and churn > 1000, ("the sweeps measure churn: 150 units left the listing in a minute (about %d an hour)"):format(churn or 0))
check((ns.Store:Rate(2319, 0) or 0) < 1000, "but churn is not counted as sales: it includes cancelled auctions")
check(searches() == 1, "no further searches while the deal is already confirmed")
S.verified[2319] = nil

print("mailbox: sale gold is read from the invoices")
do
    local oN, oH, oI = GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo
    GetInboxNumItems = function() return 2, 2 end
    GetInboxHeaderInfo = function(i) return nil, nil, nil, nil, (i == 1 and 437 or 0), 0, nil, false end
    GetInboxInvoiceInfo = function(i)
        if i == 1 then return "seller", "Linen Cloth", "Buyer", 462, 0, 0, 25 end
        return "seller_temp_invoice", "Linen Cloth", "Buyer", 500, 0, 100, 25, 60, 21, 30
    end
    GetGameTime = function() return 21, 14 end
    Se:ScanMail()
    local w, o, nx, keys = Se:SalesMoney()
    check(w == 437 and o == 575 and nx == 16 * 60, "gold in the mailbox now (437c) and a sale still held back (500 + 100 fee back - 25 cut = 575c, arriving in 16 min)")
    check(keys[2589] == true, "the pending sale is matched to the item, so its ended auction is not reported as unknown")
    T = T + 17 * 60
    w, o = Se:SalesMoney()
    check(w == 437 + 575 and o == 0, "17 minutes later it counts as waiting in the mailbox")
    GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = oN, oH, oI
    AuctionMeshDB.sales = nil
end

print("the Tuner inside the running addon")
do
    local Tu, G = ns.Tuner, ns.Gate
    local d = Tu.d
    -- two refusals close together right after background requests: a pause is learned
    d.gap.sinceFail = 1000
    G:Use("test", "search"); G:Penalize("internal auction error")
    check(Tu:Gap() == 0, "one refusal: no change of pace")
    G:Use("test", "search"); G:Penalize("internal auction error")
    check(Tu:Gap() == 0.10, "a second refusal soon after: requests now wait 0.10s after the server is ready")
    G.outstanding, G.nextAt, G.penaltyUntil = 0, 0, 0
    S.triggers, S.verified, S.checkedAt, S.searching, S.queued = {}, {}, {}, nil, nil
    LIST[2589] = { { 100, 300 }, { 101, 300 } }
    S:AddTrigger(2589, "price just dropped", 90, 100)
    local n4 = #sent
    G.sentAt = nil; fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(#sent == n4, "server ready: nothing is sent in that frame while the pause applies")
    advance(0.3)
    check(#sent > n4, "0.1s later the request goes out")
    G:Use("you click Post"); T = T + 3; G:Penalize("you are doing that too fast")
    check(d.gap.stats[2] == nil or d.gap.stats[2].fail == 0, "an error after your own click is not counted against the pace")
    d.gap.i = 1
    -- checks are scored by what asked for them
    local before = d.src.drop.n
    S.searching = { key = 2589, at = T, src = "drop", waited = 2 }; S.lastEval = nil
    S:Evaluate(2589, { { price = 100, qty = 300 }, { price = 101, qty = 300 } }, true)
    check(d.src.drop.n == before + 1, "a check asked for by a price-drop alert is scored against price-drop alerts")
end

print("detail drawer: every trade from purchase to sale")
do
    local J = ns.Journal
    local function dump(lines) for _, l in ipairs(lines) do print("     " .. (l.rule and "----" or strip((l.head or l.l or "")) .. (l.r and ("  |  " .. strip(l.r)) or ""))) end end
    local function has(lines, pat) for _, l in ipairs(lines) do if strip((l.head or l.l or "") .. " | " .. (l.r or "")):find(pat) then return true end end return false end
    UI.tab = "BUY"; UI.sel = nil; UI:ToggleDrawer(true)
    check(AuctionMeshDrawer:IsShown() and AuctionMeshDB.cfg.drawer == true, "the handle on the right edge opens the drawer")
    local lines = UI.drawerLines
    dump(lines)
    check(has(lines, "^ALL TRADES") and has(lines, "^OPEN %(") and has(lines, "^FINISHED %("), "drawer lists totals, open trades and finished trades")
    check(has(lines, "Copper Ore x12") and has(lines, "Bought at 3c each | %- 36c") and has(lines, "Sold 12 to a vendor at 5c each | %+ 60c") and has(lines, "Profit made | %+ 24c"),
        "vendor trade: bought 12 at 3c, sold to a vendor at 5c, profit + 24c")
    check(has(lines, "Sold 6 at 77c each, after the cut | %+ 4s39c") and has(lines, "Profit made | %+ 3s19c"),
        "auction trade: what the buyer really paid (from the invoice) and the profit made")
    local s = J:Totals()
    check(s.trades >= 3 and s.finished >= 2, ("journal totals: %d trades, %d finished, %d open"):format(s.trades, s.finished, s.open))
    UI:ToggleDrawer(false)
    check(not AuctionMeshDrawer:IsShown() and AuctionMeshDB.cfg.drawer == false, "the handle closes it again")
end

print("laser focus and the daily report, inside the running addon")
do
    local Sc, cfg = ns.Scout, AuctionMeshDB.cfg
    UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp.focus._text == "Off: watch everything", "Setup shows laser focus is off")
    -- the scan counted what it saw
    local day = Sc:Day()
    print(("     today: %d reads, %d checks, %d deals, %d bought, %d gone, %d failed, %.0f s working"):format(day.reads, day.checks, day.deals, day.bought, day.gone, day.fails, day.secs))
    check(day.checks > 0 and day.deals >= 3 and day.bought >= 2 and day.secs > 5, "the day's counts were kept while the addon ran (checks, deals, purchases, working time)")
    -- own list from a focus code
    sp.code:SetText("AMF1:2589"); sp.apply._scripts.OnClick(sp.apply); UI:Render()
    check(cfg.focusMode == "list" and cfg.focusItems[1] == 2589 and sp.focus._text == "My own list (1)" and sp.code._text == "", "pasting a focus code and pressing Apply focuses on that item")
    S.verified, S.checkedAt, S.triggers, S.sweep = {}, {}, {}, {}
    S:RebuildBackground()
    check(#S.background == 1 and S.background[1] == 2589 and S.background.focus and S.watchMin == 30, "the watch list is now only the focus item, checked every 30s instead of every 5 minutes")
    ITEMS[4306] = { "Silk Cloth", 150 }
    ns.Store.fp[4306], ns.Store.ft[4306] = 400, GetServerTime()
    ns.Store.fp[2589], ns.Store.ft[2589] = 80, GetServerTime()
    S:OnSweep(4306, 200, 50)
    check(S.triggers[4306] == nil, "an item outside the focus: a 50%-under-market listing is not chased as a flip")
    S:OnSweep(2589, 40, 50)
    check(S.triggers[2589] ~= nil, "the focus item: the same kind of listing is checked at once")
    S:OnSweep(4306, 100, 50)
    check(S.triggers[4306] ~= nil, "outside the focus but under vendor price: still checked (guaranteed profit is never filtered)")
    check(Sc.d.items[4306].r == 2 and Sc.d.items[4306].d == 2, "everything the radar reads is still counted, focus or not")
    S.triggers = {}
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
    check(strip(AuctionMeshFrame.status._text):find("Focus on 1 item.", 1, true), "the Trades tab says what the focus is")
    -- the drawer: add / remove from the focus list
    UI.sel = 4306; UI:ToggleDrawer(true)
    local fb = AuctionMeshDrawer.focus
    check(fb:IsShown() and fb._text == "Add to my focus list", "one item in the drawer: a button to add it to your focus list")
    fb._scripts.OnClick(fb)
    check(Sc:InList(4306) and fb._text == "Remove from my focus", "one click adds it")
    fb._scripts.OnClick(fb)
    check(not Sc:InList(4306), "one click removes it")
    UI.sel = nil; UI:ToggleDrawer(false)
    -- the report button
    UI.tab = "HISTORY"; UI:Render()
    sp.report._scripts.OnClick(sp.report)
    local text = AuctionMeshLogFrame.edit._text
    check(AuctionMeshLogFrame:IsShown() and text:find("=== AUCTIONMESH DAILY REPORT v2 ===", 1, true) and text:find("=== END OF REPORT ===", 1, true), "Daily report opens one block of text to copy")
    check(text:find("focus code: AMF1:2589", 1, true) and text:find("-- TRADES", 1, true) and text:find("Linen Cloth(2589)", 1, true) and text:find("-- ENGINE", 1, true),
        "it has the focus, the trades, the market table and the engine's figures")
    print(("     report: %d characters, %d lines"):format(#text, select(2, text:gsub("\n", "\n")) + 1))
    AuctionMeshLogFrame:Hide()
    sp.focus._scripts.OnClick(sp.focus); UI:Render() -- list -> off
    check(cfg.focusMode == "off" and sp.focus._text == "Off: watch everything", "the focus button cycles back to off")
    S:RebuildBackground()
    check(not S.background.focus and S.watchMin == 300, "focus off: the normal watch list is back")
    UI.tab = "BUY"; UI:Render()
end

print("fixes from the first real report")
do
    local SB = S.SoldBetween
    local function rows(t) local r = {}; for i, x in ipairs(t) do r[i] = { price = x[1], qty = x[2] } end return r end
    check(SB(rows({ { 10, 50 }, { 12, 200 } }), rows({ { 10, 20 }, { 12, 200 } })) == 30, "real sales: 30 units gone from the cheapest level = 30 sold")
    check(SB(rows({ { 10, 50 }, { 12, 200 } }), rows({ { 12, 150 } })) == 100, "the cheapest level gone and 50 off the next = 100 sold")
    check(SB(rows({ { 10, 50 }, { 12, 200 } }), rows({ { 10, 50 }, { 12, 20 } })) == 0, "180 gone from a higher level while cheaper stock is untouched = a cancelled auction, not a sale")
    check(SB(rows({ { 10, 50 }, { 12, 200 } }), rows({ { 9, 50 }, { 12, 200 } })) == 0, "the cheapest level vanished and the same amount reappeared 1c lower = cancelled and relisted, not a sale")
    check(SB(rows({ { 10, 50 }, { 12, 200 } }), rows({ { 9, 5 }, { 10, 30 }, { 12, 200 } })) == 20, "a small undercut appeared but the old cheapest level still lost 20: counted")
    -- one request reads the whole class: the radar keeps its own clock
    local Sw = ns.Swarm
    Sw.unitReq = { [Sw.units[1]] = 1 }
    check(Sw:Solo() == true, "a radar read that costs 1 request is not shared out")
    Sw.claims[Sw.units[1]] = { by = "Friend-Realm", at = Sw.clock() }
    Sw.doneAt[Sw.units[1]] = Sw.serverTime()
    Sw.myDone = { [Sw.units[1]] = Sw.serverTime() - 10 }
    check(Sw:PickUnit() == Sw.units[1], "a friend's claim and a friend's fresh read no longer hold our own radar back")
    Sw.unitReq[Sw.units[1]] = 6
    check(Sw:Solo() == false and Sw:PickUnit() == nil, "an expensive read (6 requests) is still shared out as before")
    Sw.unitReq[Sw.units[1]] = 1; Sw.claims = {}
    -- the under-market alert uses the same bar as the deal rule
    check(math.abs(S.TriggerRatio() - 0.95 / 1.20 * 0.97) < 1e-9, ("alert when the cheapest listing is under %d%% of market (was a fixed 80%%)"):format(S.TriggerRatio() * 100))
    -- small guaranteed vendor profits count while the purse is small
    local vrows = { { price = 20, qty = 2 } }
    local d1 = ns.Deals.evaluate(rows({ { 20, 2 } }), { budget = 54, gold = 54, commodity = true, vendor = 30 })
    local d2, _, why2 = ns.Deals.evaluate(rows({ { 20, 2 } }), { budget = 5000, gold = 5000, commodity = true, vendor = 30 })
    check(d1 and d1.kind == "VENDOR" and d1.profit == 20, "with 54c: a guaranteed +20c vendor deal is shown (minimum is 20c in settings)")
    ns.Deals.cfg.minProfit = 50
    d1 = ns.Deals.evaluate(rows({ { 20, 2 } }), { budget = 54, gold = 54, commodity = true, vendor = 30 })
    d2, _, why2 = ns.Deals.evaluate(rows({ { 20, 2 } }), { budget = 5000, gold = 5000, commodity = true, vendor = 30 })
    check(d1 and d1.profit == 20 and d2 == nil, "minimum 50c: still shown while you hold under 5 silver, hidden once you hold more")
    ns.Deals.cfg.minProfit = 20
    -- a vendor sale made by hand is recorded
    local realized = AuctionMeshDB.realized or 0
    AuctionMeshDB.flips[1210] = { kind = "VENDOR", sell = 250, units = 1, cost = 164, at = GetServerTime() }
    ITEMS[1210] = { "Shadowgem", 250 }
    ns.Journal:Bought(1210, "Shadowgem", "VENDOR", 1, 164, 250)
    MerchantFrame:Show()
    Se:CheckSoldByHand({ [1210] = 1 })
    MerchantFrame:Hide()
    local tr = ns.Journal:Trades(1210)[1]
    check(AuctionMeshDB.flips[1210] == nil and AuctionMeshDB.realized == realized + 86 and tr.vend == 1 and ns.Journal.left(tr) == 0,
        "selling a tracked item to a vendor yourself banks the profit (+86c) and closes the trade")
    -- repost advice checks that the posting fee can be paid
    AuctionMeshDB.listed = { [2838] = { qty = 1, price = 318, cost = 105, at = GetServerTime(), plan = 319 } }
    ITEMS[2838] = { "Heavy Stone", 60 }
    ns.Store.p[2838], ns.Store.t[2838] = 300, GetServerTime()
    S.own, S.ownRead = { [2838] = { 1 } }, true
    local le
    for _, e in ipairs(Se:Entries()) do if e.key == 2838 and e.action == "LISTED" then le = e end end
    gold = 54
    local dep0 = C_AuctionHouse.CalculateCommodityDeposit
    C_AuctionHouse.CalculateCommodityDeposit = function(id, d, q) return math.max(100, q) end -- this realm: 1s minimum fee
    ns.Sniper.ClearFees()
    local adv, tone = Se:Advice(le)
    print("     " .. strip(adv))
    check(tone == "wait" and strip(adv):find("Posting again costs a fee of", 1, true) and strip(adv):find("you have 54c", 1, true), "undercut but the posting fee is more than your gold: the advice is to wait, and says why")
    gold = 900
    adv, tone = Se:Advice(le)
    check(tone == "do" and strip(adv):find("post again at 2s99c", 1, true), "with enough gold for the fee the advice is to repost")
    C_AuctionHouse.CalculateCommodityDeposit = dep0
    ns.Sniper.ClearFees()
    AuctionMeshDB.listed = {}
end

print("sniping: clicks go straight to the server, safe to spam, clear outcome")
do
    local G, cfg = ns.Gate, AuctionMeshDB.cfg
    local btn = AuctionMeshSnipeButton
    local function label() return strip(btn.label._text) end
    local function press() btn._scripts.OnClick(btn) end
    local function reset()
        S.verified, S.checkedAt, S.triggers, S.sweep, S.dealSeen, S.floor, S.missed = {}, {}, {}, {}, {}, {}, {}
        S.buying, S.searching, S.result, S.lastEval, S.priority = nil, nil, nil, nil, nil
        G.holdUntil, G.outstanding, G.nextAt, G.penaltyUntil, G.userUntil = nil, 0, 0, 0, 0
    end
    S.hold = 6
    cfg.focusMode = "off"; ns.Scout:Changed()
    local flashes = {}
    UIErrorsFrame = { AddMessage = function(_, text, r, g, b) flashes[#flashes + 1] = { strip(text), r, g, b } end }
    S.tally = { won = 0, lost = 0, gone = 0 }
    UI.tab = "BUY"; UI.notice = nil; gold = 900
    reset()
    ITEMS[2770] = { "Copper Ore", 5 }
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(0.6)
    check(S.verified[2770] ~= nil, "a deal appears")
    check(G.holdUntil and G:UserBusy() == true and G:Ready() == false, "the radar goes silent at once, so the auction house is free for your click")
    check(S.buying == nil and gold == 900, "nothing is asked of the server without a click (this game blocks that)")
    print("     " .. label())
    check(label():find("^BUY    Copper Ore x12    pay 36c    make %+ 24c"), "the big button shows the deal")
    -- the auction house is busy when you click: the click still goes out at once (it used to be held back, and the game then blocked it)
    local starts = 0
    local realStart = C_AuctionHouse.StartCommoditiesPurchase
    C_AuctionHouse.StartCommoditiesPurchase = function(id, q) starts = starts + 1; return realStart(id, q) end
    local readyWas = C_AuctionHouse.IsThrottledMessageSystemReady
    C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    press()
    check(starts == 1 and S.buying and S.buying.phase == "quote", "first click, auction house busy: the price request is sent inside that click")
    check(label():find("^ASKING THE PRICE %(keep clicking%)"), "the button says keep clicking")
    press(); press()
    check(starts == 1 and gold == 900, "more clicks while the price is on its way do nothing and cause no error")
    advance(0.3)
    check(S.buying.phase == "confirm" and label():find("^BUY NOW    Copper Ore x12    pay 36c"), "the price is in: the button says BUY NOW")
    check(rowsText()[1]:find("%[BUY NOW%]"), "and so does the row")
    press()
    check(S.buying and S.buying.phase == "wait", "the next click sends the purchase, again without waiting for the lock")
    C_AuctionHouse.IsThrottledMessageSystemReady = readyWas
    press(); press(); press()
    advance(0.5)
    C_AuctionHouse.StartCommoditiesPurchase = realStart
    check(gold == 900 - 36 and AuctionMeshDB.flips[2770] and AuctionMeshDB.flips[2770].units == 12, "bought once; the extra clicks did nothing (safe to spam)")
    print("     " .. label())
    check(S.result and S.result.kind == "won" and label():find("^GOT IT  12 x Copper Ore for 36c"), "the panel says GOT IT")
    check(G.holdUntil == nil, "and the radar runs again")
    check(flashes[#flashes][1]:find("^AuctionMesh: GOT IT  12 x Copper Ore for 36c") and flashes[#flashes][3] == 1, "the same message flashes in green in the middle of the screen")
    check(strip(btn.result._text) == "This session: 1 got, 0 missed, 0 gone before a click", "the line under the button keeps count")
    AuctionMeshDB.flips[2770] = nil
    ns.Journal:Dropped(2770, nil, "test")

    -- someone else is faster (the case from the real log: 18 Silk Cloth gone 0.85s after it appeared)
    reset(); gold = 900
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(1)
    LIST[2770] = { { 9, 200 }, { 10, 300 } } -- bought by someone else
    press(); advance(0.3)
    print("     " .. label())
    check(gold == 900 and S.result and S.result.kind == "lost" and label():find("^MISSED  Copper Ore: someone was faster. It now costs 1s08c for 12. Nothing spent."),
        "the listing was bought by someone else: the panel says MISSED with the real price, nothing spent")
    check(flashes[#flashes][1]:find("^AuctionMesh: MISSED  Copper Ore") and flashes[#flashes][2] == 1, "MISSED flashes in red in the middle of the screen")
    advance(1.5)
    check(S.floor[2770] == nil and not (S.result.text or ""):find("NOT BUYABLE"), "it is NOT called 'not buyable' and the item is not ignored afterwards (it used to be, for 30 minutes)")
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.checkedAt = {}; S.priority = 2770; G.holdUntil = nil; advance(1)
    check(S.verified[2770] ~= nil, "a new cheap listing of the same item is offered again straight away")

    -- your own auction really is in the way: the cheap units are still listed after the server refused to sell them
    reset(); gold = 900
    ITEMS[500] = { "Zesty Clam Meat", 500 }
    LIST[500] = { { 450, 2 }, { 500, 913 }, { 750, 6 } }
    local startWas = C_AuctionHouse.StartCommoditiesPurchase
    C_AuctionHouse.StartCommoditiesPurchase = function(id, q) C_Timer.After(0.2, function() fire("COMMODITY_PRICE_UPDATED", 500, 500 * q) end) end
    S.priority = 500; advance(1)
    check(S.verified[500] ~= nil, "a deal whose cheap units are your own auctions")
    press(); advance(0.3)
    check(S.result.kind == "lost", "the server quotes the dearer price: first reported as missed")
    G.holdUntil = nil; advance(1.5)
    C_AuctionHouse.StartCommoditiesPurchase = startWas
    print("     " .. strip(S.result.text))
    check(S.floor[500] and S.floor[500].price == 500 and S.result.text:find("^NOT BUYABLE"), "the re-read still shows the cheap units: only now is it called NOT BUYABLE")
    check(S.verified[500] == nil, "and that deal is not offered again")
    LIST[500] = nil

    -- it disappears before you click at all
    reset(); gold = 900
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(1)
    LIST[2770] = { { 9, 200 }, { 10, 300 } }
    S.checkedAt = {}; S.priority = 2770; G.holdUntil = nil; advance(1)
    print("     " .. label())
    check(S.verified[2770] == nil and S.result and S.result.kind == "gone" and label():find("^GONE  Copper Ore: someone else bought it"), "it was bought by someone else before any click: the panel says GONE")
    advance(7); UI:Render()
    check(not label():find("^GONE"), "after 6 seconds the button shows the next thing to do")
    print("     " .. strip(btn.result._text))
    check(strip(btn.result._text):find("^Last: GONE  Copper Ore: someone else bought it, %d+ seconds after it appeared. %(%d+s ago%)"),
        "but the outcome stays on the line underneath, with its age and the session's count")

    -- a blocked click must not switch the radar off (it did: the radar was dead for a whole real session)
    local Sw = ns.Swarm
    Sw.manual = nil
    if not Sw.active then Sw:Start(true) end
    Sw.browseSentAt = GetTime() - 30
    fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()")
    check(Sw.active and not Sw.manual, "the game blocking some other action no longer switches the radar off")
    for _ = 1, 3 do Sw.browseSentAt = GetTime(); fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()") end
    check(Sw.manual == true, "only radar reads blocked three times in a row do")
    Sw.manual, Sw.blocked = nil, 0
    Sw:Start(true)

    -- the category list re-sent by the game after an item search is not a fresh radar read
    local reads0 = ns.Scout:Day().reads
    Sw.current = nil
    ns.Store.fp[2319], ns.Store.ft[2319] = 100, GetServerTime()
    C_AuctionHouse.GetBrowseResults = function() return { { itemKey = { itemID = 2319 }, minPrice = 40, totalQuantity = 5 } } end
    S.triggers = {}
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(ns.Scout:Day().reads == reads0 and S.triggers[2319] == nil, "a category list that is not the answer to our own radar request is ignored (no alerts for prices that are long gone)")
    Sw.current = { unit = Sw.units[1], phase = "query", at = Sw.clock(), requests = 1 }
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(ns.Scout:Day().reads == reads0 + 1 and S.triggers[2319] ~= nil, "the answer to our own radar request is read")
    Sw.current = nil; S.triggers = {}
    S.hold = 0; reset()
    LIST[2770] = nil
end

print("sharing: joining says plainly whether it worked and who is there")
do
    local Do, Comm, Sync, cfg = ns.Do, ns.Comm, ns.Sync, AuctionMeshDB.cfg
    UI.tab = "HISTORY"; UI.notice = nil
    local sp = AuctionMeshFrame.setup
    local joined, guild = {}, true
    local oldGet = GetChannelName
    GetChannelName = function(name) return joined[name:lower()] and 5 or 0 end
    JoinTemporaryChannel = function(name, pw) if pw == "secret" then joined[name:lower()] = true else fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "", "", "", 0, 0, name) end end
    LeaveChannelByName = function(name) joined[name:lower()] = nil end
    IsInGuild = function() return guild end
    Sync.peers, Sync.peerInfo = {}, {}
    -- wrong password
    sp.chan:SetText("GoldCrew7"); sp.pass:SetText("oops"); sp.join._scripts.OnClick(sp.join)
    advance(2.5); UI:Render()
    print("     " .. strip(sp.share._text))
    check(strip(sp.share._text) == "NOT connected: wrong password for channel 'GoldCrew7'.", "wrong password: the panel says so")
    check(Comm:Route() == nil, "and nothing is sent anywhere (it used to fall back to the guild without saying)")
    -- right password, nobody there yet
    local before = #sentAddon
    sp.pass:SetText("secret"); sp.join._scripts.OnClick(sp.join)
    advance(2.5); UI:Render()
    print("     " .. strip(sp.share._text))
    check(strip(sp.share._text):find("^Joined channel 'GoldCrew7'. Nobody else has answered %(asked %d+s ago%)"), "joined, nobody there: says joined, and that nobody has answered")
    advance(1)
    local rollCall
    for i = before + 1, #sentAddon do if sentAddon[i]:sub(1, 1) == "P" then rollCall = sentAddon[i] end end
    check(rollCall ~= nil, "joining sends a roll call on the channel")
    -- a friend answers
    local friendP = "P" .. ns.Codec.uint(1) .. ns.Codec.uint(31500) .. ns.Codec.uint(0)
    local chatBefore = #chat
    fire("CHAT_MSG_ADDON", Comm.PREFIX_LIVE, friendP, "CHANNEL", "Bob-Realm")
    UI.notice = nil; UI:Render()
    print("     " .. strip(sp.share._text))
    check(strip(sp.share._text):find("^Connected on channel 'GoldCrew7' with 1 player: Bob %(v3.15.0, heard %d+s ago%)."), "a friend answers: named, with their version and when they were last heard")
    check(chat[chatBefore + 1] and chat[chatBefore + 1]:find("Connected: Bob-Realm is sharing prices with you.", 1, true), "and chat says so the moment they connect")
    check(strip(AuctionMeshFrame.barText._text):find("1 friend connected", 1, true), "the bar at the top shows 1 friend connected on every tab")
    -- our addon answers someone else's roll call
    before = #sentAddon
    Sync.answeredAt = nil
    fire("CHAT_MSG_ADDON", Comm.PREFIX_LIVE, "P" .. ns.Codec.uint(1) .. ns.Codec.uint(31500) .. ns.Codec.uint(1), "CHANNEL", "Bob-Realm")
    advance(3)
    local answered
    for i = before + 1, #sentAddon do if sentAddon[i]:sub(1, 1) == "P" then answered = true end end
    check(answered, "when a friend asks who is there, this addon answers")
    -- an old version's presence (no version in it) still counts
    fire("CHAT_MSG_ADDON", Comm.PREFIX_LIVE, "P" .. ns.Codec.uint(1), "CHANNEL", "Old-Realm")
    UI:Render()
    check(strip(sp.share._text):find("with 2 players", 1, true) and strip(sp.share._text):find("Old (older version", 1, true), "a friend on an older version is listed as such")
    GetChannelName = oldGet; IsInGuild = function() return false end
    Sync.peers, Sync.peerInfo = {}, {}
    cfg.channel, cfg.route = "", "channel"; Comm.channelName = nil
    UI.tab = "BUY"; UI:Render()
end

print("moving the panel")
do
    check(UI.docked == true and AuctionMeshFrame.pop:IsShown() and AuctionMeshFrame.pop._text == "Pop out", "inside the auction house there is a Pop out button")
    AuctionMeshFrame.pop._scripts.OnClick(AuctionMeshFrame.pop)
    check(UI.docked == false and AuctionMeshDB.cfg.dock == false and AuctionMeshFrame:IsShown() and AuctionMeshFrame._parent == UIParent, "one click makes it a separate window")
    check(AuctionMeshFrame.pop._text == "Dock", "the button now says Dock")
    local moved = 0
    AuctionMeshFrame.StartMoving = function() moved = moved + 1 end
    local row
    for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._scripts.OnDragStart then row = f; break end end
    row._scripts.OnDragStart(row)
    AuctionMeshDrawer._scripts.OnDragStart(AuctionMeshDrawer)
    AuctionMeshFrame._scripts.OnDragStart(AuctionMeshFrame)
    check(moved == 3, "the separate window is dragged by its background, its rows or the drawer")
    AuctionMeshFrame.pop._scripts.OnClick(AuctionMeshFrame.pop)
    check(UI.docked == true and AuctionMeshDB.cfg.dock == true, "Dock puts it back inside the auction house")
    moved = 0
    AuctionMeshFrame._scripts.OnDragStart(AuctionMeshFrame)
    check(moved == 0, "docked, it does not move on its own (it is part of the auction house window)")
end

print("the 5% cut and the posting fee")
do
    local cfg = AuctionMeshDB.cfg
    ITEMS[2592] = { "Wool Cloth", 33 }
    AuctionMeshDB.names["Wool Cloth"] = 2592
    -- an auction that sells, on a realm where the fee does NOT come back
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, at = GetServerTime() - 600, fee = 100 } }
    local before = AuctionMeshDB.realized
    GetInboxInvoiceInfo = function() return "seller", "Wool Cloth", "Buyer", 800, 0, 0, 40, nil, nil, nil, 5 end
    Se.lastSale = nil
    Se:RecordSale(2)
    check(cfg.feeBack == false and ns.Deals.cfg.depositIsCost == true, "a sale invoice with no fee returned: the addon now counts the posting fee as a cost")
    check(AuctionMeshDB.realized == before + (800 - 40 - 5 * 34 - 100), ("and that sale's profit has the fee taken off: + %dc (800 - 40 cut - 170 cost - 100 fee)"):format(AuctionMeshDB.realized - before))
    -- with the fee as a cost, a flip must clear it
    local function rows(t) local r = {}; for i, x in ipairs(t) do r[i] = { price = x[1], qty = x[2] } end return r end
    local book = rows({ { 100, 2 }, { 200, 100 }, { 201, 100 } })
    local o = { budget = 5000, gold = 5000, commodity = true, deposit = 1, depositMin = 100 }
    ns.Deals.cfg.requireTurnover = false
    local d1 = ns.Deals.evaluate(book, o)
    ns.Deals.cfg.depositIsCost = false
    local d2 = ns.Deals.evaluate(book, o)
    print(("     2 units bought at 1s00c, resold at 1s99c: profit + %dc with the fee as a cost, + %dc when the fee comes back"):format(d1 and d1.profit or -1, d2 and d2.profit or -1))
    check(d2 and d1 and d2.profit - d1.profit == 100, "the same deal shows 1s less profit once the fee is known not to come back")
    cfg.feeBack = true; ns.Deals.cfg.depositIsCost = false
    AuctionMeshDB.listed = {}
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
