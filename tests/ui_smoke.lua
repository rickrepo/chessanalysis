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
hooksecurefunc = function(name, fn)
    -- Only the two "take an item out of a mail" functions are really hooked. In
    -- the game the mail can still be read right after the call (the inbox only
    -- changes when the server answers), so the hook runs before the fake take.
    if name == "AutoLootMailItem" or name == "TakeInboxItem" then
        local orig = _G[name]
        _G[name] = function(...) fn(...); return orig(...) end
    end
end
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
TakeInboxItem = function(i) return AutoLootMailItem(i) end

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
-- An install from before sharing was removed: it had joined a channel.
AuctionMeshDB = { cfg = { v = 10, channel = "GoldCrew7", password = "secret", route = "channel", share = true } }
local leftChannel
GetChannelName = function(name) return (name == "GoldCrew7" and not leftChannel) and 5 or 0 end
LeaveChannelByName = function(name) leftChannel = name end
fire("ADDON_LOADED", "AuctionMesh")
fire("PLAYER_LOGIN")
local UI, S, Se = ns.UI, ns.Sniper, ns.Seller
-- what a view of the Details drawer says, as plain text (the drawer is left as it was)
local function drawerText(view)
    local was, wasView, wasSel = AuctionMeshDB.cfg.drawer, UI.dview, UI.sel
    UI.sel, UI.dview, UI.chartAt, UI.itemsCache = nil, view, nil, nil
    UI:ToggleDrawer(true)
    local t = {}
    for _, ln in ipairs(UI.drawerLines or {}) do t[#t + 1] = strip((ln.head or ln.l or "") .. (ln.r and ("  |  " .. ln.r) or "")) end
    local lines = UI.drawerLines
    UI.dview, UI.sel = wasView, wasSel
    UI:ToggleDrawer(was == true)
    return table.concat(t, "\n"), lines
end
AuctionMeshDB.cfg.minProfit, ns.Deals.cfg.minProfit = 20, 20 -- the walkthrough uses small deals
-- The walkthrough below drives the two-click path (first click asks for the price, second buys),
-- which is what happens when the game does not allow a price request without a click.
-- One-click buying and holding fire have their own section at the end.
S.hold = 0
S.upkeep.every, S.upkeep.bags = 0, 0 -- the walkthrough is about what is shown, not about request turns (those have their own section and tests/pace_test.lua)
ns.Auto.cfg.manyHidden, ns.Auto.cfg.crowded = 1e9, 1e9 -- the walkthrough is not a real session: auto-adjust must not move the smallest profit under it (it has its own section)
ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 1, 1 -- the capital limits have their own section at the end
AuctionMeshDB.cfg.autoConfirm = false -- the walkthrough drives the two-input path; one-input buying has its own section
ns.Deals.cfg.requireTurnover = false -- the fake auction house has no other buyers until the "volume" section
-- the section headings on the panel, each with its column captions
local function headsText()
    local out = {}
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "detail") and f._shown and rawget(f, "sect") and f.sect.head then
            out[#out + 1] = strip(f.head._text) .. " | " .. strip(f.c[1]._text) .. " / " .. strip(f.c[2]._text) .. " / " .. strip(f.c[3]._text) .. " / " .. strip(f.c[4]._text) .. " / " .. strip(f.profit._text)
        end
    end
    return out
end
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
do
    local c = AuctionMeshDB.cfg
    advance(11)
    check(leftChannel == "GoldCrew7" and c.channel == nil and c.password == nil and c.route == nil and c.share == nil and c.v == 14,
        "an install that had joined a sharing channel leaves it once, and the channel settings are forgotten")
    check(#sentAddon == 0, "and nothing was sent while doing so")
end

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
-- THE MOST VALUABLE WAY OUT. The ore was bought under vendor price (5c), but
-- the market is at 9c: after the 5% cut that is 7c, so the auction house is
-- the recommendation, not the vendor.
r = rowsText(); print("     " .. r[1])
check(bags[1] and bags[1].itemID == 2770 and r[1]:find("Post it: worth more than at a vendor", 1, true),
    "mailbox collected automatically; bought under vendor price but worth more on the auction house: the row says Post it, not Sell to a vendor")
-- BOTH WAYS OUT ON THE ROW, with the difference: list it, or a vendor now
check(r[1]:find("List: + 48c (fee 12c first)   or vendor now: + 24c, 24c less, no wait", 1, true),
    "the row's hover text gives both: listed it brings +48c (the 12c fee goes first), a vendor now +24c, 24c less, with no wait")
do
    local h = headsText(); print("     " .. tostring(h[1]))
    check(h[1] == "TO POST, OR SELL TO A VENDOR NOW (1) | QTY / COST / MARKET / VENDOR NOW / P / L" and r[1]:find("| 12 / 3c / 8c / 24c less |", 1, true) and r[1]:find("| +48c |", 1, true),
        "ON THE ROW: it sits under 'To post, or sell to a vendor now', with the listing profit (+48c) and a VENDOR NOW column (24c less)")
end
do  -- not enough gold for the posting fee: the row says so, and when sale gold arrives
    local goldWas, payWas = gold, S.ownSoldPay
    gold = 5
    UI:Render(); r = rowsText(); print("     " .. r[1])
    check(r[1]:find("List: + 48c (fee 12c first: you have 5c)   or vendor now: + 24c", 1, true), "with 5c in hand: the 12c fee is flagged, with what you have")
    S.ownSoldPay = { { amount = 300, due = GetTime() + 720, key = 2589 } }
    UI:Render(); r = rowsText(); print("     " .. r[1])
    check(r[1]:find("(fee 12c first: you have 5c, sale gold in 12 min)", 1, true), "and when sale gold is on its way, in how many minutes it arrives: wait and list, or vendor now")
    gold, S.ownSoldPay = goldWas, payWas
    UI:Render()
end
do
    local e = ns.Seller:Entries()[1]
    local adv = strip((ns.Seller:Advice(e)))
    print("     " .. adv)
    check(e.action == "AH" and e.vendorAlt == 5 and adv:find("^Post 12 at 8c each") and adv:find("+ 48c after the cut", 1, true)
        and adv:find("Or sell it to a vendor now for + 24c", 1, true), "the advice gives both: post at 8c for +48c, or a vendor now for +24c")
    -- without a live price yet, the figure comes from the item's last full listing
    local live = ns.Seller.prices[2770]; ns.Seller.prices[2770] = nil
    e = ns.Seller:Entries()[1]
    adv = strip((ns.Seller:Advice(e)))
    print("     " .. adv)
    check(e.action == "AH" and adv:find("^Worth more on the auction house: about 7c each after the cut, against 5c at a vendor"),
        "no live price yet: still the auction house, from the radar's last read (cheapest 9c: about 7c each against 5c)")
    ns.Seller.prices[2770] = live
end
MailFrame:Hide(); fire("MAIL_CLOSED")
MerchantFrame:Show(); fire("MERCHANT_SHOW"); advance(3)
check(gold == 3200 - 36 and AuctionMeshDB.flips[2770] ~= nil, "opening a vendor sells NOTHING by itself")
r = rowsText()
check(not AuctionMeshFrame.vend._shown and r[1]:find("Worth more on the auction house", 1, true) and r[1]:find("%[Sell%]"),
    "at a vendor: no 'Sell all to vendor' for it; the row says it is worth more on the auction house and still has its own Sell button")
ns.Seller:SellVendor(); advance(3)
check(gold == 3200 - 36 and AuctionMeshDB.flips[2770] ~= nil, "'Sell all to vendor' leaves it alone")
-- the market falls to vendor price: now the vendor IS the best way out
do
    local fp, ft = ns.Store.fp[2770], ns.Store.ft[2770]
    local live = ns.Seller.prices[2770]
    ns.Store.fp[2770], ns.Store.ft[2770], ns.Seller.prices[2770] = 6, GetServerTime(), nil; UI:Render()
    r = rowsText(); print("     " .. r[1])
    check(r[1]:find("Sell to any vendor", 1, true) or r[1]:find("%[Sell%]"), "market at 6c (5c after the cut and undercut): the vendor's 5c is as good, so the row says sell to a vendor")
    check(r[1]:find("Vendor now + 24c   listing instead: about + 12c, 12c less", 1, true), "and it shows what listing would bring instead: about +12c, 12c less than the vendor")
    do
        local h = headsText()
        check(h[1] == "TO SELL TO A VENDOR (1) | QTY / COST / VENDOR / IF LISTED / P / L" and r[1]:find("| 12 / 3c / 5c / 12c less |", 1, true),
            "ON THE ROW: under 'To sell to a vendor' the IF LISTED column says 12c less")
    end
    do  -- the auction house pays a little more, not enough to be the recommendation: the row still shows what waiting would add
        ITEMS[4306] = { "Silk Cloth", 150 }
        AuctionMeshDB.flips[4306] = { kind = "VENDOR", sell = 150, units = 10, cost = 100, at = GetServerTime() }
        bags[5] = { itemID = 4306, stackCount = 10 }; fire("BAG_UPDATE_DELAYED")
        ns.Store.fp[4306], ns.Store.ft[4306] = 170, GetServerTime()
        UI:Render()
        local row
        for _, l in ipairs(rowsText()) do if l:find("Silk Cloth", 1, true) then row = l end end
        print("     " .. tostring(row))
        check(row and row:find("| 10 / 1s00c / 1s50c / +1s00c more |", 1, true) and row:find("| +5s00c |", 1, true),
            "ON THE ROW: the vendor's +5s as the profit, and IF LISTED: +1s00c more")
        check(row and row:find("Sell to any vendor", 1, true) and row:find("Vendor now + 5s00c   or wait and list: about + 6s00c, 1s00c more (fee 10c first)", 1, true),
            "Silk Cloth, vendor 1s50c, market 1s70c: the vendor is recommended (+5s now), and the row shows waiting and listing would bring about +6s, 1s more, after a 10c fee")
        local e
        for _, x in ipairs(ns.Seller:Entries()) do if x.key == 4306 then e = x end end
        local adv = strip((ns.Seller:Advice(e)))
        print("     " .. adv)
        check(adv:find("^Sell it to any vendor: %+ 5s00c, guaranteed%. Or wait and list it: about %+ 6s00c after the cut, 1s00c more%. That takes a posting fee of 10c first%. The gold comes about an hour after it sells%."),
            "the item's advice says the same in words")
        -- HELD AS A FLIP, some of it bought under vendor price (one record per item): a vendor is still a way out, from its own row
        AuctionMeshDB.flips[4306] = { kind = "FLIP", sell = 190, units = 10, cost = 120, at = GetServerTime() }
        local goldWas, realizedWas = gold, AuctionMeshDB.realized or 0
        UI:Render()
        for _, x in ipairs(ns.Seller:Entries()) do if x.key == 4306 then e = x end end
        for _, l in ipairs(rowsText()) do if l:find("Silk Cloth", 1, true) then row = l end end
        print("     " .. tostring(row))
        check(e.action == "AH" and e.vendorAlt == 150 and row:find("%[Sell%]") and row:find("| 10 / 1s20c / 1s90c* / 3s00c less |", 1, true) and row:find("| +6s00c |", 1, true)
            and row:find("or vendor now: + 3s00c, 3s00c less", 1, true),
            "a flip that cost 1s20c with a vendor paying 1s50c: listing brings +6s, VENDOR NOW 3s00c less, and there is a Sell button at the vendor")
        ns.Seller:SellVendor(4306); advance(3)
        check(AuctionMeshDB.flips[4306] == nil and gold == goldWas + 1500 and (AuctionMeshDB.realized or 0) == realizedWas + 300,
            "its own Sell button does: 10 sold at the vendor's 1s50c, +3s00c banked (the vendor's price, not the planned resale price)")
        gold = goldWas
        AuctionMeshDB.realized = realizedWas
        AuctionMeshDB.flips[4306] = nil; bags[5] = nil; fire("BAG_UPDATE_DELAYED")
        ns.Store.fp[4306], ns.Store.ft[4306] = nil, nil
        ITEMS[4306] = nil
        UI:Render()
    end
    check(AuctionMeshFrame.vend._shown and strip(AuctionMeshFrame.vend._text) == "Sell all to vendor  +60c", "and the panel offers one button: Sell all to vendor +60c")
    AuctionMeshFrame.vend._scripts.OnClick(AuctionMeshFrame.vend); advance(3)
    check(gold == 3200 - 36 + 60 and AuctionMeshDB.flips[2770] == nil, "after your click: sold, +24c real profit, list cleared")
    ns.Store.fp[2770], ns.Store.ft[2770], ns.Seller.prices[2770] = fp, ft, live
end
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
do  -- the row's Post button and the Post next button are there together, always
    local Se = ns.Seller
    check(AuctionMeshPostButton:IsShown(), "Post next is shown while something is waiting to be posted")
    local was = Se.prices[2589].at
    advance(60); UI:Render()
    check(Se.prices[2589].at > was and Se:PriceReady(2589), "the price is checked again before it runs out (it used to run out first, and the Post button vanished)")
    -- even with no price at all (just opened, or the answer is late) the button stays
    local keep = Se.prices[2589]
    Se.prices[2589] = nil; UI:Render()
    r = rowsText()
    print("     " .. tostring(r[1]))
    check(r[1] and r[1]:find("%[Post%]") and not r[1]:find("Ready to post") and AuctionMeshPostButton:IsShown(),
        "with no live price yet the row still has its Post button, next to Post next")
    posted = {}
    click(1); UI:Render()
    check(#posted == 0, "a click then asks for the price first; nothing is posted at a price that was not checked")
    r = rowsText()
    print("     " .. tostring(r[1]))
    check(r[1] and r[1]:find("Getting the live price first. Press Post again in a second.", 1, true), "and the row itself says why nothing was posted")
    advance(3); UI:Render()
    r = rowsText()
    check(Se:PriceReady(2589) and r[1] and r[1]:find("Ready to post"), "the price is there a moment later and the row says Ready to post")
    -- the auction house refuses a post: the reason is on the row
    do
        local realPost = C_AuctionHouse.PostCommodity
        C_AuctionHouse.PostCommodity = function() fire("UI_ERROR_MESSAGE", 1, "You don't have enough money to post that auction") end
        local errsWas = ns.Gate.errors
        click(1); UI:Render()
        check(ns.Gate.errors == errsWas and ns.Gate.nextAt <= GetTime() + 0.2 and GetTime() >= (ns.Gate.penaltyUntil or 0),
            "a post the game refuses does not stop the radar: no 5-second stop, nothing counted against the pace (it did both)")
        r = rowsText()
        print("     " .. tostring(r[1]))
        check(#posted == 0 and r[1] and r[1]:find("Not posted. The game says: You don't have enough money to post that auction", 1, true),
            "a refused post shows the game's own reason on the row")
        C_AuctionHouse.PostCommodity = realPost
        advance(5); UI:Render()
    end
    -- pressing Post over and over with no price: the price check is not held back, and the post goes out
    Se.prices[2589] = nil; posted = {}
    for _ = 1, 10 do click(1); advance(0.2) end
    check(#posted == 1 and posted[1].qty == 6 and posted[1].price == 77,
        "spamming Post with no price yet: the price arrives and the item is posted once (each press used to push the price check back)")
end
advance(1); ns.Seller.note = nil
check(posted[1] and posted[1].qty == 6 and posted[1].price == 77 and AuctionMeshDB.flips[2589] == nil, "one click posted all 6 at 77c; removed after bags confirmed")
UI.tab = "SELL"; UI.notice = nil; UI:Render()
check(#rowsText() == 1 and rowsText()[1]:find("Linen Cloth x6") and rowsText()[1]:find("LISTED") and rowsText()[1]:find("+3s18c", 1, true), "the posted auction is on the Bags tab as LISTED with its expected profit")
check(not AuctionMeshPostButton:IsShown(), "with nothing to post there is no Post next button either")
UI.tab = "BUY"; UI:Render()
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(#r == 0, "the Trades tab lists no auction of yours: it is for sniping only")
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
    local hd = heads(); UI.tab = "SELL"; UI:Render(); local hs = heads(); UI.tab = "BUY"; UI:Render()
    print("     sections: " .. table.concat(hd, " / "))
    check(lg:IsShown(), "Trades tab opens with the MONEY section")
    check(hd[1] == "DEALS TO BUY NOW (0)" and hd[2]:find("^None right now") and hd[3] == nil and hs[1] == "LISTED (1)", "below it: deals to buy and nothing else; your auctions are on the Bags tab under a grey heading")
    check(val(lg.rows[1]) == strip(ns.Seller.short(GetMoney())), "MONEY: gold on this character now")
    check(val(lg.rows[4]) == "+ 4s38c", "MONEY: 6 listed at 77c = + 4s38c after the 5% cut")
    check(val(lg.rows[2]) == "-" and val(lg.rows[3]) == "-" and val(lg.rows[5]) == "-", "MONEY: nothing sold yet, nothing waiting to be listed")
    check(val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)), "MONEY: total when it has all sold = gold + listings")
    -- someone lists cheaper: the auction moves to STUCK LISTINGS
    ns.Store:Put(2589, 70, 900, GetServerTime()); UI.tab = "SELL"; UI:Render()
    check(heads()[1] == "STUCK LISTINGS (1)", "a cheaper listing appears: the auction moves under STUCK LISTINGS")
    -- recommendations for that auction, and the drawer's one-item view
    local listedEntry
    for _, e in ipairs(Se:Entries()) do if e.action == "LISTED" and e.key == 2589 then listedEntry = e end end
    local adv, tone = Se:Advice(listedEntry)
    print("     " .. strip(adv))
    check(tone == "do" and strip(adv):find("Someone lists at 70c. Press Cancel on its row", 1, true) and strip(adv):find("post again at 69c: still + 2s70c", 1, true),
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
    UI.tab = "BUY"; UI:Render()
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
    -- as in the real log: a sold row carries the whole amount paid and the seconds until it is paid out
    C_AuctionHouse.GetOwnedAuctionInfo = function() return { itemKey = { itemID = 2589 }, status = 1, quantity = 6, buyoutAmount = 462, timeLeftSeconds = 960 } end
    S:ReadOwned(); UI:Render()
    print("     " .. lg.rows[3].label._text .. " | " .. val(lg.rows[3]))
    do  -- a sold auction is not "stuck": it sits under its own heading with the time its gold arrives
        ns.Store.p[2589], ns.Store.t[2589] = 70, GetServerTime() -- other people list cheaper now; that no longer matters
        UI.tab = "SELL"; UI:Render()
        local hd = heads()
        print("     sections: " .. table.concat(hd, " / "))
        local row
        for _, l in ipairs(rowsText()) do if l:find("Linen Cloth x6") then row = l end end
        print("     " .. tostring(row))
        check(hd[1] == "SOLD, GOLD ON ITS WAY (1)" and row and row:find("Sold: gold arrives in 16 min", 1, true) and row:find("/ SOLD |", 1, true),
            "a sold auction is listed under SOLD, GOLD ON ITS WAY with its pay-out time, not under stuck or undercut")
        ns.Store.p[2589] = 78; UI.tab = "BUY"; UI:Render()
    end
    check(val(lg.rows[3]) == "+ 4s38c  next 16 min" and val(lg.rows[4]) == "-" and val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)),
        "an auction the game lists as sold moves to 'Sold: still on its way', with the game's own amount and pay-out time, without a mailbox visit")
    advance(970); UI:Render()
    check(val(lg.rows[2]) == "+ 4s38c" and val(lg.rows[3]) == "-", "once its pay-out time has passed it counts as waiting in the mailbox")
    C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
    S.ownSoldQty, S.ownSoldPay = {}, {}
    -- right-click no longer removes anything
    do UI.tab = "SELL"; UI:Render()
        local row
        for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._shown and rawget(f, "item") and f.item.key == 2589 then row = f end end
        if row then
            row._scripts.OnMouseUp(row, "RightButton")
            check(AuctionMeshDB.listed[2589] ~= nil and UI.sel == 2589, "a right-click on a row removes nothing; it opens the item's details like any click")
            local rm = AuctionMeshDrawer.remove
            check(rm:IsShown() and rm._text == "Stop tracking this item", "removing is a button in the drawer")
            rm._scripts.OnClick(rm)
            check(AuctionMeshDB.listed[2589] ~= nil and rm._text == "Click again to remove", "and it asks for a second click")
            UI.removeUntil = nil; UI.sel = nil; UI:ToggleDrawer(false)
        end
    end
    S.own, S.ownRead = ownWas, readWas
    UI.tab = "SELL"; UI:Render()
    check(not lg:IsShown(), "the Bags tab has no MONEY section")
    UI.tab = "HISTORY"; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp:IsShown() and #sp.rows == 3 and sp.rows[1].label._text == "Auto-adjust" and sp.rows[2].label._text == "Server limit, measured",
        "Setup tab: the settings, then three lines: what auto-adjust is doing, the server's limit, the radar")
    check(sp.bottom and -40 + sp.bottom >= -480, ("the Setup tab ends %d px under the top of the panel: above the footer, docked (about 513 high) or floating (520)"):format(40 - (sp.bottom or 0)))
    for i = 1, 3 do print("     " .. tostring(sp.rows[i].label._text) .. " | " .. strip(sp.rows[i].value._text)) end
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
advance(2)
check(S.verified[500] == nil, "for a few seconds the same units are not offered again")
advance(13)
check(S.verified[500] ~= nil, "after the short cooldown it is offered again (the listing still shows it)")
click(1); advance(1)
advance(12)
check(S.verified[500] == nil and S.cool[500].n == 2, "missed a second time at the same price: now ignored four times longer, and so on up to 10 minutes")
LIST[500] = nil; S.verified[500] = nil

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

print("an auction that expires: the cases that used to be left to you")
do
    local Se = ns.Seller
    local floor = math.floor
    ITEMS[2592] = { "Wool Cloth", 33 }
    local invWas = GetInboxInvoiceInfo
    GetInboxInvoiceInfo = function(i) return inbox[i] and inbox[i].invoice end
    local function clear()
        for s2 = 1, 16 do bags[s2] = nil end
        fire("BAG_UPDATE_DELAYED")
        AuctionMeshDB.flips[2592] = nil
        inbox = {}
        Se.lastTake = nil
        if ns.Learn.d.items then ns.Learn.d.items[2592] = nil end
    end
    AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
    -- 1. A NEW SESSION: the mailbox is visited before the auction house, so the
    --    addon has no list of your auctions. And you hold 3 more of the item.
    clear()
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, fee = 10, at = GetServerTime() - 13 * 3600 } }
    S.own, S.ownIds, S.ownRead = {}, {}, false
    bags[1] = { itemID = 2592, stackCount = 3 }; fire("BAG_UPDATE_DELAYED")
    AuctionMeshDB.flips[2592] = { kind = "FLIP", units = 3, cost = 40, sell = 160, at = GetServerTime() - 3600 }
    inbox = { { itemID = 2592, stackCount = 5 } }
    local banked = AuctionMeshDB.realized or 0
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
    local f = AuctionMeshDB.flips[2592]
    check(f and f.units == 8 and f.cost == 36 and AuctionMeshDB.listed[2592] == nil,
        "mailbox before the auction house, and more of the item in your bags: the 5 expired units join the 3 you hold (8 at 36c, the average)")
    check(#inbox == 0 and bags[2] and bags[2].itemID == 2592 and bags[2].stackCount == 5 and f.retPending == nil, "and they are taken out of the mailbox by the addon")
    check((AuctionMeshDB.realized or 0) == banked - 10, "the posting fee of the auction that did not sell is booked as lost (10c)")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    -- 2. something you BOUGHT of an item you also have listed is not a returned auction
    clear()
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, at = GetServerTime() - 3600 } }
    inbox = { { itemID = 2592, stackCount = 4, invoice = "buyer" } }
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
    check(AuctionMeshDB.listed[2592] and AuctionMeshDB.listed[2592].qty == 5 and AuctionMeshDB.flips[2592] == nil,
        "a purchase of the same item arriving by mail leaves your listing as it is")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    -- 3. two auctions of the same item: one ran out, the other is still running
    clear()
    AuctionMeshDB.listed = { [2592] = { qty = 10, price = 160, cost = 34, plan = 160, fee = 20, at = GetServerTime() - 13 * 3600 } }
    S.ownRead, S.own = true, { [2592] = { [160] = 10 } } -- as read at the auction house earlier in the session
    S.ownIds = { [2592] = { { id = 11, qty = 5, price = 160, ends = GetTime() + 3600 }, { id = 12, qty = 5, price = 160, ends = GetTime() - 60 } } }
    inbox = { { itemID = 2592, stackCount = 5 } }
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
    f = AuctionMeshDB.flips[2592]
    local L = AuctionMeshDB.listed[2592]
    check(f and f.units == 5 and f.cost == 34 and L and L.qty == 5 and L.fee == 10,
        "two auctions of one item, one ran out: its 5 units come back, the other 5 stay listed with their share of the fee")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    -- 4. you take it out of the mailbox yourself before the addon has looked
    clear()
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, at = GetServerTime() - 13 * 3600 } }
    S.own, S.ownIds, S.ownRead = {}, {}, false
    inbox = { { itemID = 2592, stackCount = 5 } }
    TakeInboxItem(1) -- your own click on the mail
    f = AuctionMeshDB.flips[2592]
    check(f and f.units == 5 and f.cost == 34 and f.retPending == nil and AuctionMeshDB.listed[2592] == nil and bags[1] and bags[1].itemID == 2592,
        "taken out of the mailbox by hand: it is still recognised as your expired auction and tracked")
    TakeInboxItem(1) -- a second click on a mail that is already being taken
    check(AuctionMeshDB.flips[2592].units == 5, "a double click on the mail does not count it twice")
    check(ns.Learn:Blocked(2592) ~= nil, "an auction that ran out is scored as a flip that did not sell")
    -- back at the auction house it is offered for posting again
    LIST[2592] = { { 150, 100 }, { 155, 300 } }
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW")
    UI.tab = "SELL"; advance(4); UI:Render()
    local row
    for _, l in ipairs(rowsText()) do if l:find("Wool Cloth x5", 1, true) then row = l end end
    print("     " .. tostring(row))
    check(row and row:find("Ready to post", 1, true) and row:find("%[Post%]"), "at the auction house the Bags tab has it ready to post again, with a live price")
    UI.tab = "BUY"
    clear(); AuctionMeshDB.listed = {}; LIST[2592] = nil
    S.own, S.ownIds, S.ownRead = {}, {}, true
    GetInboxInvoiceInfo = invWas
end

print("undercut: cancel, collect, post again")
do
    local Se = ns.Seller
    ITEMS[2592] = { "Wool Cloth", 33 }
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    Se.note, Se.cancelArm, Se.cancelling = nil, nil, nil
    -- 5 Wool Cloth of yours listed at 1s60c; someone now lists 50 at 1s20c
    LIST[2592] = { { 120, 50 }, { 125, 300 }, { 160, 5 } }
    ns.Store:Put(2592, 120, 355, GetServerTime())
    AuctionMeshDB.listed = { [2592] = { qty = 5, price = 160, cost = 34, plan = 160, fee = 10, at = GetServerTime() - 3600 } }
    Enum.AuctionStatus = { Active = 0, Sold = 1 }
    local numWas, infoWas = C_AuctionHouse.GetNumOwnedAuctions, C_AuctionHouse.GetOwnedAuctionInfo
    C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
    C_AuctionHouse.GetOwnedAuctionInfo = function()
        return { auctionID = 9001, itemKey = { itemID = 2592 }, status = 0, quantity = 5, buyoutAmount = 160, timeLeftSeconds = 30000 }
    end
    local cancelled = {}
    C_AuctionHouse.CancelAuction = function(id) cancelled[#cancelled + 1] = id end
    S:ReadOwned()
    UI.tab = "SELL"; UI:Render()
    local function rowOf(key)
        for i = 1, #frames do local fr = frames[i]; if rawget(fr, "detail") and fr._shown and rawget(fr, "item") and fr.item.key == key then return fr end end
    end
    local function press() local r = rowOf(2592); r.btn._scripts.OnClick(r.btn); UI:Render() end
    local r = rowOf(2592)
    print("     " .. strip(r.name._text) .. " | " .. strip(r.state._text) .. " | [" .. (r.btn._shown and r.btn._text or "") .. "]")
    check(r and r.item.action == "LISTED" and strip(r.state._text) == "Listed, but someone is cheaper" and r.btn._shown and r.btn._text == "Cancel",
        "an undercut auction has a Cancel button on its row (Trades tab, STUCK LISTINGS)")
    -- the first click only says what it will cost
    press(); r = rowOf(2592)
    print("     " .. strip(r.state._text) .. " | [" .. r.btn._text .. "]")
    check(#cancelled == 0 and r.btn._text == "Sure?" and strip(r.state._text):find("^Click again to cancel 5 at 1s60c each. The posting fee of 10c is not returned."),
        "first click: nothing is cancelled; the row says what a cancel costs and the button asks 'Sure?'")
    check(Se:Busy() and S:YieldTo("swarm") == false, "and nothing else is sent for the next seconds, so the second click finds the auction house free (a real log: four clicks for one cancel, the radar kept it locked)")
    advance(6); UI:Render(); r = rowOf(2592)
    check(#cancelled == 0 and r.btn._text == "Cancel", "left alone for 5 seconds it goes back to Cancel: one stray click never cancels")
    -- busy auction house: the second click is not lost
    press()
    local readyWas = C_AuctionHouse.IsThrottledMessageSystemReady
    C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    press(); r = rowOf(2592)
    check(#cancelled == 0 and strip(r.state._text):find("busy for a moment. Click again", 1, true) and r.btn._text == "Sure?", "auction house busy on the second click: it says so and stays armed")
    C_AuctionHouse.IsThrottledMessageSystemReady = readyWas
    -- the game refuses
    C_AuctionHouse.CancelAuction = function() fire("UI_ERROR_MESSAGE", 1, "Auction not found") end
    local errsWas = ns.Gate.errors
    press(); r = rowOf(2592)
    check(ns.Gate.errors == errsWas and ns.Gate.nextAt <= GetTime() + 0.2, "a cancel the game refuses does not stop the radar either")
    check(Se.cancelling == nil and AuctionMeshDB.listed[2592] and strip(r.state._text):find("Not cancelled. The game says: Auction not found", 1, true), "if the game refuses, the row shows the game's own reason and nothing changes")
    C_AuctionHouse.CancelAuction = function(id) cancelled[#cancelled + 1] = id end
    -- two clicks cancel
    local banked = AuctionMeshDB.realized or 0
    local learnWas = ns.Learn.d.n
    Se.note = nil
    advance(6); UI:Render()
    press(); press(); r = rowOf(2592)
    print("     " .. strip(r.state._text) .. " | cancelled " .. #cancelled)
    check(#cancelled == 1 and cancelled[1] == 9001 and strip(r.state._text) == "Cancelling..." and not r.btn._shown, "two clicks: the auction is cancelled at the auction house (its own id), and the row says Cancelling...")
    press()
    check(#cancelled == 1, "more clicks while it is being cancelled do nothing")
    -- another auction of yours SELLS meanwhile: the game fires the same event for it, after its "sold" notice
    fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Wool Cloth", 777); fire("AUCTION_CANCELED", 777)
    check(Se.cancelling ~= nil and AuctionMeshDB.listed[2592] ~= nil, "a sale reported while the cancel is waiting is not taken for its confirmation")
    advance(0.6)
    -- the confirmation, as a real log shows it: notice 1, and a number that is NOT the auction's
    fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 1, "", 113); fire("AUCTION_CANCELED", 113); UI:Render()
    check(Se.cancelling == nil, "the game confirms the cancel with another number than the auction's (113 for auction 9001): recognised all the same")
    local f = AuctionMeshDB.flips[2592]
    check(AuctionMeshDB.listed[2592] == nil and f and f.units == 5 and f.cost == 34 and f.retPending == 5, "confirmed by the auction house: the 5 units are among your holdings again, at what they cost you")
    check((AuctionMeshDB.realized or 0) == banked - 10, "the posting fee is booked as lost (10c)")
    check(ns.Learn.d.n == learnWas and ns.Learn:Blocked(2592) == nil, "a cancel is not scored as a flip that failed to sell")
    check(rowOf(2592) and rowOf(2592).item.action == "MAIL", "the auction is gone; the Bags tab shows the units as in the mailbox")
    print("     " .. chat[#chat])
    check(chat[#chat]:find("Cancelled:", 1, true) and chat[#chat]:find("5 x Wool Cloth", 1, true) and chat[#chat]:find("collect it at a mailbox, then press Post", 1, true), "chat says what to do next")
    UI.tab = "SELL"; UI:Render()
    local row
    for _, l in ipairs(rowsText()) do if l:find("Wool Cloth x5", 1, true) then row = l end end
    check(row and row:find("In your mailbox", 1, true), "the Bags tab shows it as in your mailbox")
    -- the mailbox: it is collected by the addon
    local invWas = GetInboxInvoiceInfo
    GetInboxInvoiceInfo = function(i) return inbox[i] and inbox[i].invoice end
    inbox = { { itemID = 2592, stackCount = 5 } }
    AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
    check(#inbox == 0 and bags[1] and bags[1].itemID == 2592 and AuctionMeshDB.flips[2592].retPending == nil and AuctionMeshDB.flips[2592].units == 5,
        "at the mailbox the cancelled auction is taken out by the addon, counted once")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    GetInboxInvoiceInfo = invWas
    -- back at the auction house: post again under the cheaper seller
    C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
    LIST[2592] = { { 120, 50 }, { 125, 300 } }
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW")
    UI.tab = "SELL"; advance(4); UI:Render()
    row = nil
    for _, l in ipairs(rowsText()) do if l:find("Wool Cloth x5", 1, true) then row = l end end
    print("     " .. tostring(row))
    check(row and row:find("Ready to post", 1, true) and row:find("Sell 1s19c", 1, true) and row:find("%[Post%]"), "back at the auction house: ready to post at 1s19c, one step under the cheaper seller")
    local np = #posted
    r = rowOf(2592); r.btn._scripts.OnClick(r.btn); advance(2)
    check(#posted == np + 1 and posted[#posted].qty == 5 and posted[#posted].price == 119 and AuctionMeshDB.listed[2592] and AuctionMeshDB.listed[2592].price == 119,
        "one click on Post: listed again, 5 at 1s19c")
    do  -- A CANCEL WHOSE CONFIRMATION NEVER CAME: what the mail brings back is still a cancelled auction
        C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
        C_AuctionHouse.GetOwnedAuctionInfo = function()
            return { auctionID = 9002, itemKey = { itemID = 2592 }, status = 0, quantity = 5, buyoutAmount = 119, timeLeftSeconds = 30000 }
        end
        ns.Store:Put(2592, 110, 400, GetServerTime() + 1)
        S:ReadOwned(); Se.note = nil
        UI.tab = "SELL"; UI:Render()
        advance(4); UI:Render() -- (the hold after the post is over)
        local nc = #cancelled
        press(); press()
        check(#cancelled == nc + 1 and Se.cancelling ~= nil and AuctionMeshDB.cancelSent[2592] ~= nil, "a cancel is sent, and remembered")
        advance(7) -- no confirmation at all
        check(Se.cancelling == nil and AuctionMeshDB.listed[2592] ~= nil, "no confirmation in 6 seconds: nothing is booked yet")
        local learnN, blocked = ns.Learn.d.n, ns.Learn:Blocked(2592)
        C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
        S:ReadOwned()
        local invWas2 = GetInboxInvoiceInfo
        GetInboxInvoiceInfo = function(i) return inbox[i] and inbox[i].invoice end
        for s2 = 1, 16 do bags[s2] = nil end
        fire("BAG_UPDATE_DELAYED")
        inbox = { { itemID = 2592, stackCount = 5 } }
        AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
        MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
        local f2 = AuctionMeshDB.flips[2592]
        print("     " .. tostring(f2 and f2.proof))
        check(f2 and f2.units == 5 and f2.proof == "auction cancelled, returned by mail" and AuctionMeshDB.listed[2592] == nil,
            "the units come back by mail: booked as the auction you cancelled")
        check(ns.Learn.d.n == learnN and ns.Learn:Blocked(2592) == blocked, "not as a flip that failed to sell: the item is not put on hold for 12 hours (a real log: Wool Cloth was)")
        check(AuctionMeshDB.cancelSent[2592] == nil, "(the remembered cancel is used once)")
        MailFrame:Hide(); fire("MAIL_CLOSED")
        GetInboxInvoiceInfo = invWas2
        AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
        -- (back to where this section was: one auction listed, nothing held)
        AuctionMeshDB.flips[2592] = nil; ns.Journal:Dropped(2592, nil, "test")
        for s2 = 1, 16 do bags[s2] = nil end
        fire("BAG_UPDATE_DELAYED")
        AuctionMeshDB.listed[2592] = { qty = 5, price = 119, cost = 34, plan = 119, fee = 10, at = GetServerTime() }
    end
    do  -- THE ONE-TIME REPAIR of a cancel that an earlier version booked as "ran out unsold"
        local d = ns.Learn.d
        local keep = { n = d.n, ok = d.ok, fail = d.fail, mine = d.mine, recent = d.recent, items = d.items }
        d.n, d.ok, d.fail, d.mine, d.recent = 27, 26, 1, 27, { 1, 1, 0 }
        d.items = { [2592] = { ok = 26, fail = 1, streak = 1, last = GetServerTime() - 600 } }
        check(ns.Learn:Blocked(2592) ~= nil, "(as in the real log: 26 sold, then one cancel booked as expired; Wool Cloth on hold for 12 hours)")
        local fixed = Se.RepairCancelRecord()
        print("     " .. chat[#chat])
        check(fixed == 2592 and ns.Learn:Blocked(2592) == nil and d.fail == 0 and d.n == 26 and #d.recent == 2, "first login with the fix: the one wrong record is taken back and Wool Cloth is flipped again")
        d.fail, d.items[2592].fail, d.items[2592].streak = 2, 1, 1
        check(Se.RepairCancelRecord() == nil and ns.Learn:Blocked(2592) ~= nil, "with more than one expiry on record nothing is touched (it cannot be told which was the cancel)")
        d.n, d.ok, d.fail, d.mine, d.recent, d.items = keep.n, keep.ok, keep.fail, keep.mine, keep.recent, keep.items
    end
    -- no button where it cannot work
    ns.Store:Put(2592, 110, 400, GetServerTime() + 1)
    S.own, S.ownIds, S.ownRead = {}, {}, false
    UI.tab = "SELL"; UI:Render(); r = rowOf(2592)
    check(r and not r.btn._shown, "no Cancel button until the auction house has listed your auctions (the addon must know which one to cancel)")
    -- cleanup
    AuctionMeshDB.listed = {}; AuctionMeshDB.flips[2592] = nil; LIST[2592] = nil
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    C_AuctionHouse.GetNumOwnedAuctions, C_AuctionHouse.GetOwnedAuctionInfo = numWas, infoWas
    S.own, S.ownIds, S.ownRead = {}, {}, true
    Se.note, Se.cancelArm, Se.cancelling, Se.posting = nil, nil, nil, nil
    advance(2)
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
check(AuctionMeshDrawer.views.activity == nil and AuctionMeshDrawer.views.trades._text == "Ledger", "the drawer has two views, Ledger and Market (the long activity list is gone)")
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
    check(ns.Tuner.cfg.enabled == false and ns.Learn.cfg.autoTune == false and sp.tune._text == "Auto-adjust: off", "one switch for everything that adjusts itself")
    press(sp.tune)
    local n0 = ns.Tuner.d.n
    press(sp.forget); UI:Render()
    check(ns.Tuner.d.n == n0 and sp.forget._text == "Click again to forget", "forgetting what was learned asks for a second click")
    press(sp.forget); UI:Render()
    check(ns.Tuner.d.n == 0 and sp.forget._text == "Forget what was learned", "the second click clears it")
    -- nothing about sharing is left: no controls, no functions, no files
    check(rawget(sp, "chan") == nil and rawget(sp, "join") == nil and rawget(sp, "share") == nil and rawget(sp, "shareOn") == nil and rawget(sp, "guild") == nil,
        "the Setup tab has no sharing controls")
    check(ns.Comm == nil and ns.Sync == nil and ns.Codec == nil and ns.Do.Channel == nil and ns.Do.Share == nil and ns.Do.Guild == nil,
        "the addon has no communication code: nothing to send with, nothing to receive with")
    do
        local hit
        for _, f in ipairs({ "Core", "UI", "Sniper", "Seller", "Swarm", "Scanner", "Book", "Learn", "Tuner", "Scout", "Auto", "Diag", "Deals", "Store", "Journal", "Seed" }) do
            for line in io.lines("AuctionMesh/" .. f .. ".lua") do
                if not line:match("^%s*%-%-") and (line:find("SendAddonMessage", 1, true) or line:find("JoinTemporaryChannel", 1, true) or line:find("JoinChannelByName", 1, true)
                    or line:find("RegisterAddonMessagePrefix", 1, true) or line:find("CHAT_MSG_ADDON", 1, true) or line:find("SendChatMessage", 1, true)) then hit = f .. ": " .. line end
            end
        end
        check(not hit, "no file sends an addon message, a chat message, or joins a channel" .. (hit and (" (" .. hit .. ")") or ""))
    end
    -- the log window holds the switch to the previous session's log
    do
        AuctionMeshDB.logPrev = { "old line one", "old line two" }
        ns.Diag:Show()
        local w = AuctionMeshLogFrame
        check(w.prev._shown and w.prev._text == "Last session's log" and not w.edit._text:find("old line one", 1, true), "the log window has a 'Last session's log' button")
        w.prev._scripts.OnClick(w.prev)
        check(w.edit._text == "old line one\nold line two" and w.prev._text == "This session's log" and not w.clr._shown, "one click shows the log from before the last reload; no Clear button on it")
        w.prev._scripts.OnClick(w.prev)
        check(w.prev._text == "Last session's log" and w.clr._shown, "and one click goes back")
        ns.Do.Snapshot()
        check(not w.prev._shown, "the Snapshot window does not have that button")
        w:Hide()
    end
    check(type(AuctionMesh_OnAddonCompartmentClick) == "function", "the game's addon list can open the panel")
    for _, f in ipairs({ "AuctionMesh/UI.lua", "AuctionMesh/Seller.lua", "AuctionMesh/Sniper.lua", "AuctionMesh/Swarm.lua", "AuctionMesh/Scanner.lua", "AuctionMesh/Book.lua" }) do
        local bad
        for line in io.lines(f) do if line:find("/amesh", 1, true) and not line:match("^%s*%-%-") then bad = line end end
        check(not bad, f:match("[^/]+$") .. ": no message tells the player to type a command")
    end
    UI.tab = "BUY"; UI:Render()
end

print("a radar read triggers a check; next-step line")
ns.Deals.cfg.requireTurnover = false
S.verified, S.checkedAt, S.floor, S.sweep, S.triggers = {}, {}, {}, {}, {}
LIST[2592], LIST[2589], LIST[2770], LIST[500], LIST[2318], LIST[2319] = nil, nil, nil, nil, nil, nil -- leftovers from earlier sections
ITEMS[4234] = { "Heavy Leather", 2 }
LIST[4234] = { { 60, 4 }, { 190, 300 }, { 191, 300 } }
ns.Store:PutFair(4234, 190, GetServerTime()); gold = 900
-- the radar reads the lowest price of the item
local n1 = #sent
S:OnSweep(4234, 60, 604); advance(3)
local c = 0; for i = n1 + 1, #sent do if sent[i] == "search4234" then c = c + 1 end end
check(c == 1 and S.verified[4234] and S.verified[4234].units == 4, "a price far under the market in a radar read triggered one check and the deal is confirmed")
UI.tab = "SELL"; UI.notice = nil; UI:Render() -- the NEXT line is shown on the Bags tab (the Trades tab has the big button)
local nx = strip(AuctionMeshFrame.next._text)
print("     " .. nx)
check(nx:find("NEXT  Press Buy on Heavy Leather: pay 2s40c, make +", 1, true), "NEXT line says exactly what to press and what it makes")
UI.tab = "BUY"; UI:Render()
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
    check(f1 == 1 and f6 == 13, ("radar interval: a 1-request read runs back to back (shown as every %ds); a 6-request read every %ds"):format(f1, f6))
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
S:RebuildBackground(); UI.tab = "BUY"; S.searching = nil; S.last = nil; S.lastAlert = nil; S.lastEval = nil
-- a routine look at an item: its result is not put on the Trades tab
S:Evaluate(2447, { { price = 20, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI.wheelSeen = nil; UI:Render()
local st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Next check", 1, true) == nil and select(2, st:gsub("\n", "")) == 0,
    "the Trades tab's status is one line: the mode and what the radar is doing")
check(st:find("Peacebloom", 1, true) == nil, "a routine look at an item is not reported on the Trades tab")
check(st:find("^MODE: VENDOR %+ FLIPS%. .-Radar: a read every %d+%.%d%ds%.$") ~= nil, "it gives the measured time between radar reads")
do
    local dt = drawerText("session")
    check(dt:find("RADAR\nA read every  |  %d+%.%d%ds") ~= nil and dt:find("Requests in the last minute  |  %d+ radar, %d+ alerts, %d+ buying, %d+ other") ~= nil,
        "what the last minute's requests went to is in Details, Session")
end
-- the answer to something the radar asked about is shown
S.lastEval = nil; S.searching = { key = 2447, at = GetTime(), src = "market" }
S:Evaluate(2447, { { price = 21, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI:Render()
st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Last alert", 1, true) == nil and drawerText("session"):find("Last alert, %d+s ago: Peacebloom\n   500 cheap units is too many to clear") ~= nil,
    "the last answer to a radar alert, with why it was not a deal, is in Details, Session (not on the Trades tab)")
UI.wheelSeen = GetTime(); UI:Render()
st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("^MODE: VENDOR %+ FLIPS%.") ~= nil and select(2, st:gsub("\n", "")) == 0, "armed: still one line, starting with the mode in capitals")
check(strip(AuctionMeshFrame.snipe.label._text):find("ARMED.-radar first; %d+ listings? still being read for instant flips") ~= nil, "the snipe box says what is still being read for instant flips")
do
    local was = S.ListingReady
    S.ListingReady = function() return true end
    UI:Render(); st = strip(AuctionMeshFrame.status._text)
    check(strip(AuctionMeshFrame.snipe.label._text):find("every request goes to the radar and its alerts", 1, true) ~= nil, "armed with every listing ready: every request goes to the radar and its alerts")
    S.ListingReady = was
end
check(select(2, st:gsub("\n", "")) <= 2, "never more than three lines")
UI.wheelSeen = nil; S.judged = {}

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
    check(has(lines, "^LEDGER") and has(lines, "^Paid for everything bought | %- ") and has(lines, "^Came back from what sold | %+ ") and (has(lines, "^You are up | ") or has(lines, "^You are down | ")),
        "the drawer is a ledger: paid, came back, and whether you are up or down")
    check(has(lines, "^Copper Ore x12  at 3c | SOLD  %+ 24c$"), "one line per purchase: 12 Copper Ore at 3c, sold, + 24c")
    check(has(lines, "^Linen Cloth x6  at 20c | SOLD  %+ 3s19c$"), "an auction sale shows the profit really made (from the invoice): + 3s19c")
    do  -- something bought and not sold shows as money you are down
        local t = J:Bought(7777, "Test Ore", "FLIP", 5, 40, 80)
        UI:Render()
        check(has(UI.drawerLines, "^Test Ore x5  at 40c | NOT SOLD  down 2s00c$") and has(UI.drawerLines, "2 purchases not sold yet: 3s20c still to come back"),
            "a purchase that has not sold says NOT SOLD and how much you are down")
        -- sold on the auction house, gold not paid out yet
        t.listed, t.price = 5, 80
        S.ownSoldQty = { [7777] = 5 }
        UI:Render()
        check(has(UI.drawerLines, "^Test Ore x5  at 40c | SOLD, gold coming  %+ 1s80c$") and has(UI.drawerLines, "^Sold, gold on its way | %+ 3s80c$"),
            "once it sells and the gold is on its way it says so, with the profit that is coming (5 x 76c - 2s00c)")
        S.ownSoldQty = {}
        for i = #J.list, 1, -1 do if J.list[i] == t then table.remove(J.list, i) end end
        UI:Render()
    end
    -- the full story of one item is still there when you click the item
    UI.sel = 2589; UI:Render()
    check(has(UI.drawerLines, "Sold 6 at 77c each, after the cut | %+ 4s39c") and has(UI.drawerLines, "Profit made | %+ 3s19c"),
        "clicking an item still shows its trades in full: what the buyer paid and the profit made")
    UI.sel = nil; UI:Render()
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
    check(#S.background == 1 and S.background[1] == 2589 and S.background.focus and S.watchMin == 60, "the watch list is now only the focus item, re-read every 60s instead of every 5 minutes")
    ITEMS[4306] = { "Silk Cloth", 150 }
    ns.Store.fp[4306], ns.Store.ft[4306] = 400, GetServerTime()
    ns.Store.fp[2589], ns.Store.ft[2589] = 80, GetServerTime()
    S:OnSweep(4306, 200, 50)
    check(S.triggers[4306] == nil, "an item outside the focus: a 50%-under-market listing is not chased as a flip")
    S:OnSweep(2589, 40, 50)
    check(S.triggers[2589] ~= nil, "the focus item: the same kind of listing is checked at once")
    S:OnSweep(4306, 100, 50)
    check(S.triggers[4306] ~= nil or (S.verified[4306] and S.verified[4306].kind == "VENDOR"),
        "outside the focus but under vendor price: still acted on (guaranteed profit is never filtered)")
    S.verified[4306] = nil
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
    check(Sw:Solo() == true, "a radar read that costs 1 request runs back to back")
    Sw.doneAt[Sw.units[1]] = Sw.serverTime()
    Sw.myDoneClock = { [Sw.units[1]] = Sw.clock() - 10 }
    check(Sw:PickUnit() == Sw.units[1], "the radar is due again as soon as its last read is done")
    Sw.unitReq[Sw.units[1]] = 6
    check(Sw:Solo() == false and Sw:PickUnit() == nil, "an expensive read (6 requests) is paced by the radar interval instead")
    Sw.unitReq[Sw.units[1]] = 1
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
        S.verified, S.checkedAt, S.triggers, S.sweep, S.dealSeen, S.floor, S.missed, S.judged = {}, {}, {}, {}, {}, {}, {}, {}
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
    do  -- and the whole panel flashes green around its edge
        local e = rawget(AuctionMeshFrame, "flashEdges")
        check(UI.flashKind == "won" and e and #e == 4 and e[1]._shown, "a purchase: the whole panel's edge flashes green")
        local lt = S.lastTry
        check(lt and lt.key == 2770 and lt.kind == "won" and lt.quote and lt.total and lt.total >= lt.quote, "how the try went in time is kept: when the price was back, when it was over")
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
        local dt = drawerText("session")
        for l in dt:gmatch("[^\n]+") do if l:find("Copper Ore", 1, true) or l:find("you:", 1, true) then print("     " .. l) end end
        check(strip(AuctionMeshFrame.status._text):find("Last try", 1, true) == nil
            and dt:find("%d%d:%d%d:%d%d  Copper Ore  |  BOUGHT in %d+%.%d%ds\n   you: input at %d+%.%d%ds.-, price back at %d+%.%d%ds"),
            "how the try went in time is in Details, Session (not on the Trades tab): bought in so many seconds, with your input and the price answer")
        advance(2)
        check(UI.flashKind == nil and not e[1]._shown, "the flash is gone after a second and a half")
    end
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
    check(not flashes[#flashes][1]:find("MISSED", 1, true), "a miss is no longer written in the middle of the screen")
    check(UI.flashKind == "lost" and rawget(AuctionMeshFrame, "flashEdges")[1]._shown, "a miss: the whole panel's edge flashes red")
    check(not (S.result.text or ""):find("NOT BUYABLE"), "it is never called 'not buyable' on the strength of a quote")
    -- the listing goes on showing the units for a moment after they are gone (seen in a real log)
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.checkedAt = {}; S.priority = 2770; G.holdUntil = nil; advance(1)
    check(S.verified[2770] == nil, "for 4 seconds after a miss the same cheap units are not offered again (the listing lags behind sales)")
    advance(4); S.checkedAt = {}; S.priority = 2770; G.holdUntil = nil; advance(1)
    check(S.verified[2770] ~= nil, "after that, if they are really still there, the deal is offered again")

    -- an alert never waits behind the radar or housekeeping
    reset()
    S.needOwned = true
    S:AddTrigger(2770, "at or under vendor price", 3, 9)
    check(S:YieldTo("swarm") == false, "an alert is waiting: the radar gives up its turn")
    local n5 = #sent
    ns.lastQuery = "sniper"; ns.Swarm.idle = false
    S:Tick()
    check(sent[#sent] == "search2770" and #sent == n5 + 1 and S.needOwned == true, "the alert is checked at once; reading my own auctions waits")
    advance(1); S.needOwned = false

    -- A STANDING LISTING THAT IS NOT A DEAL IS NOT CHECKED AGAIN AND AGAIN
    do
        reset(); gold = 900
        ITEMS[6001] = { "Tin Dust", 10 }
        LIST[6001] = { { 5, 2 }, { 400, 3 } }   -- 2 units under vendor price: a 10c profit, under the 20c minimum (and too few listings for a flip)
        S.candidates, S.background = {}, { i = 1 }; S.lastBg = GetTime() + 1e6; S.lastScreen = GetTime() + 1e6 -- nothing but what this section asks for
        S.ownSweep = { [6001] = { q = 502, p = 5, at = GetTime() } }
        S:AddTrigger(6001, "at or under vendor price", 5, nil, nil, 502); advance(1)
        check(S.verified[6001] == nil and S.judged[6001] and S.judged[6001].p == 5 and S.judged[6001].q == 502, "an alert is checked and judged: not a deal at 5c with 502 listed")
        advance(25)
        check(S:AlertDue(6001, 5, 502) == false, "25 seconds later the radar shows the same price and quantity: no second check (it was checked every 20 seconds, armed or not)")
        check(S:AlertDue(6001, 5, 490) == false, "fewer listed at the same price: still not")
        local due, fast = S:AlertDue(6001, 4, 503)
        check(due == true and fast == true, "a lower price is a new listing: checked at once")
        check(S:AlertDue(6001, 5, 520) == true, "more units at that price: checked again (the profit may now be enough)")
        gold = 950
        check(S:AlertDue(6001, 5, 502) == true, "you have more gold than when it was judged: checked again")
        gold = 900
        do  -- judged under other settings: looked at again
            local was = ns.Deals.cfg.minProfit
            ns.Deals.cfg.minProfit = was - 15
            check(S:AlertDue(6001, 5, 502) == true, "you lowered the smallest profit since it was judged: checked again")
            ns.Deals.cfg.minProfit = was
            check(S:AlertDue(6001, 5, 502) == false, "(same settings as when it was judged: not again)")
        end
        do  -- a deal that exists but is hidden (five misses in a row) is not held against the listing
            local jwas = S.judged[6001]
            LIST[6001] = { { 5, 30 }, { 400, 3 } }
            S.muted = { [6001] = GetTime() + 180 }
            S.priority = 6001; advance(1)
            check(S.verified[6001] == nil and S.judged[6001] == nil, "a deal hidden because the item is muted leaves no 'not a deal' record: it is raised again as soon as the mute ends")
            S.muted = {}; LIST[6001] = { { 5, 2 }, { 400, 3 } }; S.judged[6001] = jwas; S.checkedAt[6001] = GetTime() - 30
        end
        advance(300)
        check(S:AlertDue(6001, 5, 502) == true, "and after 5 minutes it is looked at again in any case")
        -- a lower price goes ahead of the 20 seconds between two checks of one item
        S.priority = 6001; advance(2)
        local n0 = #sent
        S:OnSweep(6001, 4, 503); advance(1)
        check(sent[n0 + 1] == "search6001" or sent[n0 + 2] == "search6001", "a cheaper listing on an item checked a second ago is checked at once (it used to wait out the 20 seconds)")
        LIST[6001] = nil; S.judged = {}
    end

    -- NO GOLD IN HAND: cheap listings are counted and the panel says so (a real log: 5 copper, no alert in 115 radar reads, nothing on the panel)
    do
        reset(); gold = 5; S.poor = {}
        ITEMS[6002] = { "Bolt of Felt", 0 }
        ns.Store.fp[6002], ns.Store.ft[6002] = 100, GetServerTime()
        S.ownSweep, S.sweep = {}, {}
        local n0 = #sent
        S:OnSweep(6002, 15, 300); advance(1)
        local asked = false
        for i = n0 + 1, #sent do if sent[i] == "search6002" then asked = true end end
        check(S.triggers[6002] == nil and not asked and S:PoorCount() == 1, "15c under a 1s market with 5c in hand: no alert, no request, and it is counted as skipped for lack of gold")
        AuctionMeshDB.sales = { waiting = 0, pending = { { amount = 5000, at = GetServerTime() + 27 * 60, key = 2592 } } }
        UI.tab = "BUY"; UI.notice = nil; UI.wheelSeen = nil; UI:Render()
        local st = strip(AuctionMeshFrame.status._text)
        print("     " .. st:match("[^\n]+"))
        check(st:find("Not enough gold in hand: you hold 5c. 1 cheap listing in the last minute costs more than that", 1, true) and st:find("Next sale gold in 27 min", 1, true),
            "the Trades tab says why nothing is offered, and when sale gold arrives")
        check(select(2, st:gsub("\n", "")) <= 2, "still three lines at most")
        -- a flip also needs its posting fee: 20c in hand does not buy a 15c flip with a 1c fee... but 16c does
        gold = 15; S.poor = {}
        S:OnSweep(6002, 15, 301)
        check(S:PoorCount() == 1, "gold for the unit but not for its posting fee: still skipped (the deal rules would refuse it)")
        -- one flip may take only a share of the gold in hand: 15c + 1c fee against 35% of 40c is too much
        do
            local was = ns.Deals.cfg.maxSpend
            ns.Deals.cfg.maxSpend = 0.35
            local purse = ns.Deals.cfg.smallPurse
            ns.Deals.cfg.smallPurse = 30
            gold = 40; S.poor = {}
            S:OnSweep(6002, 15, 303)
            check(S:PoorCount() == 1 and S.triggers[6002] == nil, "a flip that would take more than your share-per-flip of the gold in hand is skipped at the radar too (it was checked every 20 seconds and refused each time)")
            ns.Deals.cfg.maxSpend, ns.Deals.cfg.smallPurse = was, purse
        end
        gold = 900; S.poor = {}; S.sweep, S.ownSweep = {}, {}
        S:OnSweep(6002, 15, 302)
        check(S.triggers[6002] ~= nil or S.searching ~= nil or S.verified[6002] ~= nil, "with gold in hand the same listing is alerted as before")
        advance(1); AuctionMeshDB.sales = nil; reset(); S.poor = {}
    end

    -- GOLD TOO LOW TO POST WHAT YOU HOLD: vendor deals only, by itself, and back by itself
    do
        reset(); gold = 900; S.poor = {}; S.lowGold, S.goldAt, S.feesCache = nil, nil, nil
        local realFee = C_AuctionHouse.CalculateCommodityDeposit
        C_AuctionHouse.CalculateCommodityDeposit = function(id, d, q) return math.max(100, 5 * q) end -- 1s at least, 5c a unit
        S.ClearFees()
        ITEMS[2592] = { "Wool Cloth", 33 }
        AuctionMeshDB.flips[2592] = { kind = "FLIP", units = 60, cost = 34, sell = 160, at = GetServerTime(), proof = "test" } -- fee 3s
        AuctionMeshDB.flips[4306] = { kind = "FLIP", units = 10, cost = 90, sell = 200, at = GetServerTime(), proof = "test" } -- fee 1s
        local fees, n = S:FeesOwed()
        check(fees == 400 and n == 2, "what is bought and not listed is tracked with its posting fees: 4s for 2 items")
        advance(2)
        check(S.lowGold == nil and ns.Deals.cfg.flips == true, "9s in hand covers 4s of fees: nothing changes")
        local nchat = #chat
        gold = 250; S.feesCache = nil; advance(2)
        print("     " .. chat[#chat])
        check(S.lowGold ~= nil and ns.Deals.cfg.flips == false and AuctionMeshDB.cfg.flips ~= false, "2s50c in hand, 4s owed: the addon goes to vendor deals only by itself; your own setting is not touched")
        check(#chat == nchat + 1 and chat[#chat]:find("Gold is low: 2s50c in hand", 1, true) and chat[#chat]:find("takes 4s", 1, true), "and says so once, in chat")
        UI.tab = "BUY"; UI.notice = nil; UI.wheelSeen = nil; UI:Render()
        local st = strip(AuctionMeshFrame.status._text)
        print("     " .. st:match("[^\n]+"))
        check(st:find("Gold is low: vendor deals only. You hold 2s50c; posting the 2 items you bought takes 4s", 1, true), "the Trades tab says it, with the figures")
        check(st:find("MODE: VENDOR ONLY (gold is low).", 1, true), "and the mode on the Trades tab reads VENDOR ONLY (gold is low)")
        -- a flip is not offered now; a vendor deal still is
        LIST[2589] = { { 20, 6 }, { 78, 100 }, { 80, 300 }, { 85, 500 } }
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2589; advance(1); S.priority = 2770; advance(1)
        check(S.verified[2589] == nil and S.verified[2770] ~= nil and S.verified[2770].kind == "VENDOR", "while it lasts: no flip is offered, a vendor deal is")
        S.verified = {}
        advance(30)
        check(#chat <= nchat + 2, "it is not repeated every second")
        -- gold arrives: flips are back by themselves
        nchat = #chat
        gold = 460; advance(2)
        check(S.lowGold ~= nil, "4s60c against 4s owed: not yet (a little to spare is wanted, so it does not switch back and forth)")
        gold = 520; advance(2)
        print("     " .. chat[#chat])
        check(S.lowGold == nil and ns.Deals.cfg.flips == true and chat[#chat]:find("Gold is back", 1, true), "5s20c in hand: flips are on again by themselves, and chat says so")
        S.checkedAt = {}; S.priority = 2589; advance(1)
        check(S.verified[2589] ~= nil and S.verified[2589].kind == "FLIP", "and the flip is offered again")
        -- everything listed or sold: nothing is owed
        gold = 100; AuctionMeshDB.flips[2592] = nil; AuctionMeshDB.flips[4306] = nil; S.feesCache = nil; advance(2)
        check(S.lowGold == nil, "little gold but nothing waiting to be posted: no switch")
        gold = 900
        UI:SetVendorOnly(true); UI.notice = nil; UI:Render()
        check(strip(AuctionMeshFrame.status._text):find("^MODE: VENDOR ONLY%."), "your own vendor-only setting shows as MODE: VENDOR ONLY")
        UI:SetVendorOnly(false); UI.notice = nil; UI:Render()
        check(strip(AuctionMeshFrame.status._text):find("^MODE: VENDOR %+ FLIPS%."), "and with flips on as MODE: VENDOR + FLIPS")
        C_AuctionHouse.CalculateCommodityDeposit = realFee; S.ClearFees()
        LIST[2589], LIST[2770] = nil, nil
        for _, k in ipairs({ 2592, 4306 }) do ns.Journal:Dropped(k, nil, "test") end
        reset(); gold = 900; S.feesCache, S.poor = nil, {}
    end

    -- DETAILS, SESSION: tries in percent, gold over the session with the next hour's sale gold, and how fast
    do
        reset(); gold = 900; S.verified = {}
        local histWas, salesWas, payWas, outWas = AuctionMeshDB.goldHist, AuctionMeshDB.sales, S.ownSoldPay, AuctionMeshDB.outcomes
        local t = GetServerTime()
        -- an hour of play: 5s in hand rising to 9s, worth 12s rising to 20s
        AuctionMeshDB.goldHist = {}
        for i = 0, 60 do AuctionMeshDB.goldHist[#AuctionMeshDB.goldHist + 1] = { t = t - 3600 + i * 60, g = 500 + math.floor(400 * i / 60), w = 1200 + math.floor(800 * i / 60) } end
        S.ownSoldPay = nil
        AuctionMeshDB.sales = { waiting = 0, pending = { { amount = 300, at = t + 600 }, { amount = 500, at = t + 2400 }, { amount = 900, at = t + 7200 } } }
        S.tally.won, S.tally.lost, S.tally.gone = 24, 68, 8
        -- three tries with their timings: one bought, one lost at the price request, one refused at the purchase; one gone with no input
        AuctionMeshDB.outcomes = {
            { t = t - 300, k = "won", key = 2770, i = 0.05, h = 0.44, q = 0.70, e = 1.21, m = "GOT IT" },
            { t = t - 200, k = "lost", key = 2770, i = 0.10, h = 0.40, q = 0.85, e = 0.95, m = "MISSED" },
            { t = t - 100, k = "lost", key = 2770, i = 0.05, q = 0.75, e = 1.30, m = "MISSED" },
            { t = t - 50, k = "gone", key = 2770, g = 3.2, m = "GONE" },
            { t = t - 20, k = "lost", key = 2770, m = "MISSED (kept by an older version: no timings)" },
        }
        local c = AuctionMeshFrame.chart
        do
            local calls, realData = 0, UI.ChartData
            UI.ChartData = function(...) calls = calls + 1; return realData(...) end
            UI.tab = "BUY"; UI.notice = nil; UI.chartAt = nil; UI:Render()
            check(c and calls == 0 and not AuctionMeshDrawer._shown, "the Trades tab has no chart: with the drawer shut nothing of it is drawn or worked out")
            UI.ChartData = realData
        end
        local text = drawerText("session")
        local d = UI.chartState
        for l in text:gmatch("[^\n]+") do print("     | " .. l) end
        check(strip(c.triesText._text) == "TRIES   24 bought (24%)   68 missed (68%)   8 gone, no input (8%)", "TRIES: bought, missed and gone, with their percentages")
        check(d.cols[1] and d.cols[1].g <= 520 and d.cols[#d.cols].g >= 880 and d.cols[#d.cols].w >= 1900, "GOLD: a column for each stretch of the session, from 5s in hand at the start to 9s now, and what it is all worth above it")
        check(d.next[1].g == 900 and d.next[5].g == 1200 and d.next[24].g == 1700, "FORECAST: the next hour, with sale gold that is already sold arriving when it is due (3s after 10 minutes, 5s more after 40)")
        check(d.coming == 800, "only what is due within the hour is counted (the 9s due in two hours is not)")
        check(text:find("GOLD THIS SESSION\nIn hand  |  9s00c\nWhen all has sold (after the cut)  |  26s00c\nSince the start of the session  |  + 14s00c\nSale gold already sold, due within the hour  |  + 8s00c", 1, true),
            "the figures are under the chart: in hand, worth when sold, the change since the start, the sale gold due")
        -- how fast: yours against whoever was first
        local sp = d.speed
        check(#sp.rows == 4 and sp.won.n == 1 and sp.lost.n == 2 and sp.gone.n == 1, "SPEED: every try that was timed has a column (an old record with no timings has none)")
        check(text:find("You bought  |  1, 1.21s on average, fastest 1.21s", 1, true) and text:find("Someone else was first  |  2, within 1.12s on average, fastest 0.95s", 1, true)
            and text:find("Gone, no input  |  1, after 3.20s on average", 1, true), "your purchases against the buyer who was first: how many, the average and the fastest")
        check(text:find("Your purchases, on average: input 0.05s, the game's lock 0.44s,\nprice answer 0.26s, purchase 0.46s.", 1, true), "where the time of your purchases goes: input, lock, price answer, purchase")
        check(text:find("Copper Ore  |  TAKEN within 0.95s\n   you: input at 0.10s, held by the lock 0.40s, price back at 0.95s", 1, true),
            "a miss at the price request: the other buyer had it within 0.95s, next to your own timings")
        check(text:find("Copper Ore  |  TAKEN between 0.80s and 1.30s", 1, true), "a refused purchase: it was still there for your price request (0.80s) and gone for your purchase (1.30s)")
        check(text:find("Copper Ore  |  GONE after 3.20s\n   no input from you while it was up", 1, true) and text:find("Copper Ore  |  BOUGHT in 1.21s", 1, true), "gone with no input, and bought, each with its time")
        check(text:find("LAST TRIES, NEWEST FIRST (4)", 1, true) and text:find("GONE after.-TAKEN between.-TAKEN within.-BOUGHT in") ~= nil, "newest first")
        -- a real try is kept with its timings
        do
            local n0 = #AuctionMeshDB.outcomes
            S.tryInfo = { key = 2770, t0 = GetTime() - 0.9, input = 0.1, held = 0.4, quote = 0.7 }; S:Result("lost", 2770, "MISSED  test")
            local o = AuctionMeshDB.outcomes[#AuctionMeshDB.outcomes]
            check(#AuctionMeshDB.outcomes == n0 + 1 and o.k == "lost" and o.key == 2770 and math.abs(o.e - 1.0) < 0.01 and o.i == 0.1 and o.h == 0.4 and o.q == 0.7,
                "a try that ends is kept with its timings: input, lock, price answer, and the deal showing to the end")
            S:Result("gone", 2770, "GONE  test", 2.5)
            check(AuctionMeshDB.outcomes[#AuctionMeshDB.outcomes].g == 2.5, "a deal that left with no input is kept with how long it was up")
            S.tally.won, S.tally.lost, S.tally.gone, S.tally.inTime, S.tally.late = 24, 68, 8, nil, nil
            S.result, S.lastTry, UI.flashUntil = nil, nil, nil
        end
        -- the graphics take the top of the drawer; the lines start under them
        UI.sel, UI.dview, UI.chartAt = nil, "session", nil
        UI:ToggleDrawer(true)
        local dl = AuctionMeshDrawer.lines
        check(c._shown and strip(dl[1].label._text) == "" and strip(dl[12].label._text) == "" and strip(dl[13].label._text) == "GOLD THIS SESSION", "the charts are fixed at the top of the drawer and the text starts under them")
        -- cheap: worked out once a second at most, at once when a try has ended, and not at all when a deal appears
        local calls, realData = 0, UI.ChartData
        UI.ChartData = function(...) calls = calls + 1; return realData(...) end
        UI:Render(); UI:Render(); UI:Render()
        check(calls == 0, "redrawing the panel does not work the charts out again within the second")
        S.tally.won = 25; UI:Render()
        check(calls == 1 and strip(c.triesText._text):find("25 bought", 1, true), "a try that has ended shows at once")
        local built, realLines = 0, UI.DrawerLines
        UI.DrawerLines = function(...) built = built + 1; return realLines(...) end
        S.tally.won = 26; UI:Now()
        check(built == 0 and calls == 1 and UI.dirty == true, "a deal appearing (the fast redraw) leaves the drawer alone: nothing in it is rebuilt on that path")
        advance(0.5)
        check(built >= 1 and strip(c.triesText._text):find("26 bought", 1, true), "it is brought up to date by the next ordinary redraw, a fifth of a second later")
        UI.DrawerLines = realLines
        S.tally.won = 24
        UI.ChartData = realData
        -- a sample is taken as the session goes on, drawer open or not
        UI:ToggleDrawer(false)
        local n0 = #AuctionMeshDB.goldHist
        advance(45)
        check(#AuctionMeshDB.goldHist >= n0 + 2 and AuctionMeshDB.goldHist[#AuctionMeshDB.goldHist].g == 900, "a gold sample is kept every 20 seconds")
        -- the other views do not show the charts
        UI.dview = "trades"; UI:ToggleDrawer(true)
        check(not c._shown and strip(dl[1].label._text) ~= "", "the Ledger view has no charts, and its lines start at the top")
        UI:ToggleDrawer(false)
        AuctionMeshDB.goldHist, AuctionMeshDB.sales, S.ownSoldPay, AuctionMeshDB.outcomes = histWas, salesWas, payWas, outWas
        S.tally.won, S.tally.lost, S.tally.gone = 0, 0, 0
        UI.chartAt = nil
        reset()
    end

    -- DETAILS, ITEMS: what the addon goes for, with a tick box for Always and one for Ignore
    do
        reset(); gold = 900
        local cfg0 = AuctionMeshDB.cfg
        local itemsWas, ignoreWas, modeWas = cfg0.focusItems, cfg0.ignore, cfg0.focusMode
        local realPrime = ns.Scout.Prime
        ns.Scout.Prime = function() return { { key = 2770, rate = 120, market = 9, score = 3 }, { key = 2589, rate = 45, market = 80, score = 2 } } end
        ITEMS[2770] = ITEMS[2770] or { "Copper Ore", 5 }
        ITEMS[2589] = ITEMS[2589] or { "Linen Cloth", 1 }
        ITEMS[2592] = ITEMS[2592] or { "Wool Cloth", 3 }
        cfg0.focusItems, cfg0.ignore, cfg0.focusMode = { 2592 }, nil, "off"; ns.Scout:Changed()
        local text, lines = drawerText("items")
        for l in text:gmatch("[^\n]+") do print("     | " .. l) end
        check(text:find("MOST ACTIVE ITEMS (2)", 1, true) and text:find("Copper Ore  |  120 sell/h  9c", 1, true) and text:find("YOUR OWN LIST, NOT AMONG THE ABOVE (1)\nWool Cloth", 1, true),
            "the Items view lists what the addon goes for, best first, then your own list")
        check(text:find("Laser focus is off (Setup tab): every material is watched.", 1, true) and text:gsub("\n", " "):find("(it counts once laser focus is on)", 1, true), "with focus off it says so, and that Always counts once focus is on")
        -- the tick boxes
        UI.sel, UI.dview, UI.itemsCache = nil, "items", nil
        UI:ToggleDrawer(true)
        local dl = AuctionMeshDrawer.lines
        local function rowOf(key) for i = 1, #dl do if dl[i].always._shown and dl[i].always.key == key then return dl[i] end end end
        local ore, wool = rowOf(2770), rowOf(2592)
        check(ore and wool and not ore.always.tick._shown and not ore.ignore.tick._shown and wool.always.tick._shown, "each item has two boxes; Always is ticked for what is on your own list")
        check(not dl[1].always._shown, "a heading has no boxes")
        -- Ignore: never offered, and a deal on screen for it goes without counting as a miss
        S.verified[2770] = { key = 2770, kind = "VENDOR", units = 1, cost = 3, sell = 5, profit = 20, deposit = 0, buys = {}, counts = {}, commodity = true, at = GetTime(), from = "me" }
        S.dealSeen[2770] = GetTime()
        local gone0 = S.tally.gone
        ore.ignore._scripts.OnClick(ore.ignore)
        check(cfg0.ignore[2770] == true and S:Ignored(2770) and S.verified[2770] == nil and S.tally.gone == gone0, "a tick on Ignore: the item is never offered, and its deal on screen goes without counting as a miss")
        check(rowOf(2770) == ore and ore.ignore.tick._shown, "the row stays where it is (it does not jump from under the mouse), now ticked")
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770; advance(1)
        check(S.verified[2770] == nil, "a cheap listing of an ignored item is not offered")
        ore.ignore._scripts.OnClick(ore.ignore)
        check(not S:Ignored(2770) and not ore.ignore.tick._shown, "a second click takes it off the ignore list")
        S.checkedAt = {}; S.priority = 2770; advance(1)
        check(S.verified[2770] ~= nil, "and it is offered again")
        S.verified[2770] = nil; S.dealSeen[2770] = nil; LIST[2770] = nil
        -- Always: on your own list; ticking one clears the other
        ore.always._scripts.OnClick(ore.always)
        check(ns.Scout:InList(2770) and ore.always.tick._shown, "a tick on Always puts the item on your own list")
        ore.ignore._scripts.OnClick(ore.ignore)
        check(S:Ignored(2770) and not ns.Scout:InList(2770) and not ore.always.tick._shown, "Ignore takes it off your own list: an item is one or the other")
        ore.always._scripts.OnClick(ore.always)
        check(ns.Scout:InList(2770) and not S:Ignored(2770), "and Always takes it off the ignore list")
        wool.always._scripts.OnClick(wool.always)
        check(not ns.Scout:InList(2592), "a click on a ticked Always takes the item off your own list")
        -- opened again, the list is put together afresh: ignored items have their own section
        cfg0.ignore[2589] = true
        text = drawerText("items")
        check(text:find("MOST ACTIVE ITEMS (1)", 1, true) and text:find("IGNORED (1)\nLinen Cloth", 1, true) and not text:find("Wool Cloth", 1, true),
            "opened again: an ignored item is under IGNORED and no longer among the picks, and what is on no list any more is gone")
        -- with focus on, the list is the focus set
        cfg0.focusMode = "list"; ns.Scout:Changed()
        text = drawerText("items")
        check(text:find("ITEMS THE ADDON GOES FOR (1)", 1, true) and text:find("Focused on your list: 1 item.", 1, true), "with laser focus on your own list, the items are that list")
        UI:ToggleDrawer(false); UI.dview = "trades"
        ns.Scout.Prime = realPrime
        cfg0.focusItems, cfg0.ignore, cfg0.focusMode = itemsWas, ignoreWas, modeWas; ns.Scout:Changed()
        UI.itemsCache = nil
        reset()
    end

    -- AN ALERT IS NOT CHECKED AGAIN while the last check's own answer still stands ("needs 41c or less")
    do
        reset(); gold = 900; S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil
        ITEMS[2318] = { "Light Leather", 15 }
        LIST[2318] = { { 62, 19 }, { 68, 805 }, { 69, 220 }, { 70, 171 } }
        ns.Store.fp[2318], ns.Store.ft[2318] = 68, GetServerTime()
        S.ownSweep = S.ownSweep or {}
        S.ownSweep[2318] = { p = 62, q = 1215, at = GetTime() }
        S.checkedAt = {}; S.judged = {}; S.priority = 2318; advance(1)
        local j = S.judged[2318]
        print("     " .. tostring(S.last and S.last.reason))
        check(S.verified[2318] == nil and j and j.need and j.mkt == 68 and j.need < 60, "a check says: cheapest 62c, market 68c, needs so much or less. The price it needs is remembered")
        local need = j and j.need or 0
        local mid = need + 2 -- a price under 62c that is still above what it needs
        advance(2)
        local function alert(price, market, qty)
            S.triggers = {}
            S:AddTrigger(2318, "under market", price, market, "me", qty)
            return S.triggers[2318] ~= nil
        end
        check(not alert(62, 68, 1300), "the same price with MORE units listed: not checked again (it used to be)")
        check(not alert(mid, 68, 1215), "a LOWER price that is still above what it needs: not checked again (it used to be, at once)")
        check(not alert(mid, 60, 1215), "the same with the market down: not checked again")
        check(alert(need, 68, 1215), "the price it needs: checked at once")
        check(alert(mid, 90, 1215), "the market it was judged against has risen: checked again")
        ns.Deals.cfg.margin = ns.Deals.cfg.margin + 0.01
        check(alert(mid, 68, 1215), "your settings have changed since: checked again")
        ns.Deals.cfg.margin = ns.Deals.cfg.margin - 0.01
        S.judged[2318].at = GetTime() - 301
        check(alert(mid, 68, 1300), "after 5 minutes: checked again")
        S.triggers, S.judged = {}, {}
        LIST[2318] = nil; LIST[2319] = leather; ITEMS[2318] = nil
        ns.Store.fp[2318], ns.Store.ft[2318] = nil, nil
        S.ownSweep[2318] = nil
        advance(1); reset(); UI:Render()
    end

    -- ONE ITEM, ONE RECORD: a flip bought of an item you hold from a vendor deal ADDS to it (it replaced the record: the units were gone from the Bags tab)
    do
        reset(); gold = 90000; S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil
        local flipsWas, listedWas, bagsWas, inboxWas = AuctionMeshDB.flips, AuctionMeshDB.listed, {}, inbox
        for i2 = 1, 16 do bagsWas[i2] = bags[i2]; bags[i2] = nil end
        inbox = {}; fire("BAG_UPDATE_DELAYED")
        AuctionMeshDB.flips, AuctionMeshDB.listed = {}, {}
        ITEMS[4304] = { "Thick Leather", 300 }
        local J = ns.Journal
        local n0 = #J.list
        local realInvoice = GetInboxInvoiceInfo
        GetInboxInvoiceInfo = function(i) return inbox[i] and "buyer" or nil end
        cfg.autoConfirm = nil
        -- 5 bought under vendor price (a vendor deal), then 51 as a flip
        LIST[4304] = { { 257, 5 }, { 520, 400 }, { 521, 300 } }
        S.checkedAt = {}; S.priority = 4304; advance(1)
        check(S.verified[4304] and S.verified[4304].kind == "VENDOR" and S.verified[4304].units == 5, "5 Thick Leather under vendor price: a vendor deal")
        S:Press(4304); advance(1.5)
        local f = AuctionMeshDB.flips[4304]
        check(f and f.kind == "VENDOR" and f.units == 5, "bought: 5 held, as a vendor deal")
        LIST[4304] = { { 330, 51 }, { 560, 400 }, { 561, 300 } }
        ns.Store.fp[4304], ns.Store.ft[4304] = 560, GetServerTime()
        S.checkedAt = {}; S.judged = {}; S.priority = 4304; advance(1)
        check(S.verified[4304] and S.verified[4304].kind == "FLIP" and S.verified[4304].units == 51, "then 51 at 3s30c with the market at 5s60c: a flip")
        S:Press(4304); advance(1.5)
        f = AuctionMeshDB.flips[4304]
        check(f and f.units == 56 and f.kind == "FLIP", "bought: 56 are held, all for the auction house (the 5 used to be dropped from the record)")
        check(f and f.cost == math.floor((257 * 5 + 330 * 51) / 56 + 0.5), "at the average of what they cost")
        local lost = 0
        for i2 = n0 + 1, #J.list do if J.list[i2].key == 4304 then lost = lost + (J.list[i2].lost or 0) end end
        check(lost == 0, "nothing is marked lost in the journal")

        -- THE MAILBOX WITH FULL BAGS: it stops instead of trying for ever, and says what stays
        for i2 = 1, 16 do bags[i2] = { itemID = 2770, stackCount = 1 } end
        bags[16] = nil -- one free slot, two mails to take
        fire("BAG_UPDATE_DELAYED")
        local realLoot = AutoLootMailItem
        local tries = 0
        AutoLootMailItem = function(i)
            tries = tries + 1
            for s2 = 1, 16 do if not bags[s2] then return realLoot(i) end end -- room: it comes out
            -- no room: the mail stays where it is
        end
        local c0 = #chat
        check(#inbox == 2, "(two purchases wait in the mailbox)")
        MailFrame:Show(); fire("MAIL_SHOW"); advance(10)
        local said, collecting = false, 0
        for i2 = c0 + 1, #chat do
            if chat[i2]:find("Your bags are full:", 1, true) then said = true end
            if chat[i2]:find("Collecting from mailbox", 1, true) then collecting = collecting + 1 end
        end
        check(#inbox == 1 and tries <= 7, ("one mail fitted; the other was tried a few times and then left (%d tries in 10 seconds, not 25)"):format(tries))
        check(said and collecting == 2, "it says the bags are full, and each mail is announced once, not on every try")
        local e
        for _, x in ipairs(Se:Entries()) do if x.key == 4304 and x.action == "MAIL" then e = x end end
        check(e ~= nil and AuctionMeshDB.flips[4304].units == 56, "what stayed is still shown as waiting in the mailbox; nothing was dropped")
        MailFrame:Hide(); fire("MAIL_CLOSED")
        -- room is made; the mailbox is opened again
        for i2 = 1, 15 do if bags[i2] and bags[i2].itemID == 2770 then bags[i2] = nil end end
        fire("BAG_UPDATE_DELAYED")
        MailFrame:Show(); fire("MAIL_SHOW"); advance(4)
        check(#inbox == 0, "after room is made the rest comes out at the next visit")
        MailFrame:Hide(); fire("MAIL_CLOSED")
        AutoLootMailItem = realLoot

        -- UNITS THE ADDON HAD LOST TRACK OF (what 3.39 and before did to those 5): found in the bags, they come back
        AuctionMeshDB.flips[4304].units = 51            -- the record as the old version left it
        J:Sync(AuctionMeshDB.flips, AuctionMeshDB.listed, S.nameOf)
        lost = 0
        for i2 = n0 + 1, #J.list do if J.list[i2].key == 4304 then lost = lost + (J.list[i2].lost or 0) end end
        check(lost == 5, "(as before the fix: the record is 5 short and the journal marks 5 lost)")
        c0 = #chat
        check(Se:Recover() == 0 and AuctionMeshDB.flips[4304].units == 51, "units lost in ordinary use are NOT picked up by themselves (they could be your own stock)")
        AuctionMeshDB.recover = { at = GetServerTime() } -- what the update to this version sets, once
        fire("AUCTION_HOUSE_CLOSED"); AuctionHouseFrame:Hide(); AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(0.5)
        f = AuctionMeshDB.flips[4304]
        lost = 0
        for i2 = n0 + 1, #J.list do if J.list[i2].key == 4304 then lost = lost + (J.list[i2].lost or 0) end end
        said = false
        for i2 = c0 + 1, #chat do if chat[i2]:find("Thick Leather: 5 that the addon had lost track of are in your bags", 1, true) then said = true end end
        check(f and f.units == 56 and lost == 0 and said, "at the update: the 5 are in your bags, so they are tracked again, the journal no longer calls them lost, and chat says so")
        check(AuctionMeshDB.recover == nil or AuctionMeshDB.recover.items[4304] == nil, "with all of them found, the one-time repair is over for this item")
        local sellable = 0
        for _, x in ipairs(Se:Entries()) do if x.key == 4304 and (x.action == "AH" or x.action == "VENDOR" or x.action == "HOLD") then sellable = sellable + x.count end end
        check(sellable == 56, "all 56 are on the Bags tab to be sold")
        -- only what is really spare in the bags, and only up to what was marked lost
        AuctionMeshDB.recover = { at = GetServerTime(), items = { [4304] = 9 } }
        check(Se:Recover() == 0 and AuctionMeshDB.flips[4304].units == 56, "never more than your bags hold beyond the record")
        -- tidy up
        GetInboxInvoiceInfo = realInvoice
        for i2 = n0 + 1, #J.list do if J.list[i2].key == 4304 then J.list[i2].lost, J.list[i2].qty, J.list[i2].sold = 0, 0, 0 end end
        for i2 = 1, 16 do bags[i2] = bagsWas[i2] end
        inbox = inboxWas
        AuctionMeshDB.flips, AuctionMeshDB.listed = flipsWas, listedWas
        fire("BAG_UPDATE_DELAYED")
        LIST[4304] = nil; LIST[2319] = leather; ITEMS[4304] = nil
        ns.Store.fp[4304], ns.Store.ft[4304] = nil, nil
        cfg.autoConfirm = false
        S.result, S.lastTry, UI.flashUntil = nil, nil, nil
        S.tally.won, S.tally.lost, S.tally.gone = 0, 0, 0
        AuctionMeshDB.recover = nil
        UI.tab = "BUY"; UI.notice = nil
        advance(1); reset(); UI:Render()
    end

    -- THE LOG SAYS WHAT THE INPUTS WERE DOING when a deal appeared and when it left unbought
    do
        reset(); gold = 900; S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil
        local lines, realLog = {}, ns.Log
        ns.Log = function(fmt, ...) local ok, l = pcall(string.format, fmt, ...); lines[#lines + 1] = ok and l or tostring(fmt); return realLog(fmt, ...) end
        local function logged(pat) for _, l in ipairs(lines) do if l:find(pat) then return l end end end
        UI.inputTimes, UI.inputCount = nil, nil
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.dealSeen[2770] = nil
        S.priority = 2770; advance(1)
        local l = logged("^INPUTS as the deal appeared %(2770%)")
        print("     " .. tostring(l))
        check(S.verified[2770] and l and l:find("0 input%(s%) in the last 5s, last input never | panel open, tab BUY, buy with wheel, wheel bound: yes, key bound: no"),
            "a deal appears: the log says how many inputs came in the last 5 seconds, the tab, the buy mode and what is bound")
        -- nobody presses; the units are bought by someone else
        LIST[2770] = { { 9, 200 }, { 10, 300 } }
        advance(8); S.checkedAt = {}; G.holdUntil = nil; S.priority = 2770; advance(1)
        l = logged("^INPUTS for the deal that went %(2770%)")
        print("     " .. tostring(l))
        check(S.verified[2770] == nil and l and l:find("^INPUTS for the deal that went %(2770%): 0 input%(s%) while it was up, last input never"),
            "it leaves unbought: the log says no input arrived while it was up")
        -- with inputs, they are counted
        lines = {}
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.checkedAt = {}; S.priority = 2770; advance(1)
        local realStart = C_AuctionHouse.StartCommoditiesPurchase
        C_AuctionHouse.StartCommoditiesPurchase = function() end -- the price never comes back: the inputs lead nowhere
        UI.InputPress(true, "wheel"); UI.InputPress(true, "wheel"); UI.InputPress(true, "wheel")
        advance(5)
        C_AuctionHouse.StartCommoditiesPurchase = realStart
        LIST[2770] = { { 9, 200 }, { 10, 300 } }
        S.checkedAt = {}; S.priority = 2770; advance(1)
        l = logged("^INPUTS for the deal that went %(2770%)")
        print("     " .. tostring(l))
        check(l and l:find("3 input%(s%) while it was up"), "inputs that did arrive are counted: 3 while it was up")
        -- AN ERROR IN THE REDRAW is caught, logged once with where it was, shown on the panel, and listed in the Snapshot
        lines = {}
        local realStatus = rawget(AuctionMeshFrame.status, "SetText")
        rawset(AuctionMeshFrame.status, "SetText", function() error("boom in the status line") end)
        local ok = pcall(function() UI:Render(); UI:Render() end)
        rawset(AuctionMeshFrame.status, "SetText", realStatus)
        local e = ns.errList and ns.errList[1]
        check(ok and e and e.n == 2 and e.name == "the redraw" and e.msg:find("boom in the status line", 1, true), "an error in the redraw does not stop the addon: it is caught and counted")
        local n = 0
        for _, x in ipairs(lines) do if x:find("^ERROR in the redraw: .-boom in the status line") then n = n + 1 end end
        check(n == 1, "it is written to the log once, however often it happens")
        UI:Render()
        check(strip(AuctionMeshFrame.status._text or ""):find("AuctionMesh hit an error (the redraw). It is in the log: send a Snapshot.", 1, true), "and the panel says so")
        check(ns.Scout:Snapshot():find("ADDON ERRORS this session: 1 kind%(s%)\n  2 x in the redraw: .-boom in the status line"), "the Snapshot lists it, with how often")
        local okp, r = pcall(UI.InputPress, true, "wheel")
        check(okp and r == true, "inputs still work after it")
        ns.errs, ns.errList, UI.notice = nil, nil, nil
        ns.Log = realLog
        LIST[2770] = nil; LIST[2319] = leather
        S.result, S.lastTry, UI.flashUntil, UI.wheelSeen, UI.inputTimes = nil, nil, nil, nil, nil
        S.tally.won, S.tally.lost, S.tally.gone, S.tally.armed = 0, 0, 0, nil
        advance(1); reset(); UI:Render()
    end

    -- AFTER A PURCHASE the radar is back at once: no re-check unless cheap units may be left
    do
        reset(); gold = 900; cfg.autoConfirm = nil
        S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil -- the standing leather flip is not part of this
        -- every item check, with what asked for it ("recheck" = the look that follows a purchase)
        local asked, realSearch = {}, S.Search
        S.Search = function(self, key, src, ...) asked[#asked + 1] = key .. ":" .. tostring(src); return realSearch(self, key, src, ...) end
        local function rechecks() local n = 0; for _, a in ipairs(asked) do if a == "2770:recheck" then n = n + 1 end end; asked = {}; return n end
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770; advance(1)
        check(S.verified[2770] and not S.verified[2770].more, "a deal for every cheap unit there is")
        local n0 = #sent
        rechecks()
        S:Press(2770); advance(1.5)
        local again = rechecks()
        check(gold == 900 - 36 and again == 0 and S.priority == nil, "bought all 12: no re-check of the item follows (it cost a request, 0.65s without the radar, after every purchase)")
        AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
        -- not enough gold for all of them: cheap units are left, so the item is checked again at once
        reset(); gold = 20
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770; advance(1)
        check(S.verified[2770] and S.verified[2770].units == 6 and S.verified[2770].more == true, "gold for 6 of the 12: the deal is marked as leaving cheap units behind")
        rechecks()
        S:Press(2770); advance(1.5)
        again = rechecks()
        check(gold == 2 and again >= 1, "after buying them the item is checked again at once: more may be bought")
        AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
        -- a purchase the server refuses: the units are left alone for a few seconds instead of being offered again
        reset(); gold = 900
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770; advance(1)
        local realConfirm = C_AuctionHouse.ConfirmCommoditiesPurchase
        C_AuctionHouse.ConfirmCommoditiesPurchase = function() C_Timer.After(0.2, function() fire("COMMODITY_PURCHASE_FAILED") end) end
        rechecks()
        S:Press(2770); advance(1.5)
        C_AuctionHouse.ConfirmCommoditiesPurchase = realConfirm
        again = rechecks()
        check(gold == 900 and S.result and S.result.kind == "lost" and again == 0 and S.verified[2770] == nil and S.cool[2770] and S.cool[2770].price == 3,
            "refused by the server (someone was faster): nothing spent, no re-check, and the units at that price are left alone for 4 seconds")
        S.priority = 2770; advance(1)
        check(S.verified[2770] == nil, "(the listing still shows them: they are not offered again straight away)")
        advance(4); S.checkedAt = {}; S.priority = 2770; advance(1)
        check(S.verified[2770] ~= nil, "after those seconds, if they are really there, the deal is offered again")
        -- a price that never comes back: the deal is checked again after 4 seconds, not 10
        reset(); gold = 900; S.cool = {}
        S.priority = 2770; advance(1)
        local realStart = C_AuctionHouse.StartCommoditiesPurchase
        C_AuctionHouse.StartCommoditiesPurchase = function() end
        S:Press(2770); advance(3.5)
        check(S.buying ~= nil and S.buying.phase == "quote", "a price request with no answer: still waiting after 3.5 seconds")
        advance(1)
        check(S.buying == nil, "given up after 4 seconds (it was 10, with nothing else being sent meanwhile)")
        C_AuctionHouse.StartCommoditiesPurchase = realStart
        advance(1); reset(); cfg.autoConfirm = false
        LIST[2770] = nil; LIST[2319] = leather; S.cool = {}
        S.lastBg, S.lastScreen = 0, 0
        S.Search = realSearch
    end

    -- the radar reads back to back when one request covers everything
    local Sw = ns.Swarm
    Sw.unitReq = { [Sw.units[1]] = 1 }; Sw.claims = {}
    Sw.myDoneClock = { [Sw.units[1]] = Sw.clock() }
    check(Sw:Solo() and Sw:PickUnit() == Sw.units[1], "the moment a radar read is in, the next one is due: the game's own lock is the only pace (it waited 0.4s of its own on top)")

    -- a vendor deal straight from the radar, with no item check in between
    reset(); gold = 900
    ITEMS[5555] = { "Flax Cloth", 13 }
    LIST[5555] = { { 22, 138 }, { 23, 1095 } }
    ns.Store.fp[5555], ns.Store.ft[5555] = 23, GetServerTime()
    S.ownSweep, S.cool = {}, {}
    local n6 = #sent
    S:OnSweep(5555, 22, 1233)          -- radar read: cheapest 22c
    advance(0.7)
    LIST[5555] = { { 2, 21 }, { 22, 138 }, { 23, 1095 } }
    S:OnSweep(5555, 2, 1254)           -- next read: cheapest 2c, 21 more units than before
    local d = S.verified[5555]
    check(d and d.instant and d.units == 21 and d.cost == 42 and d.profit == 231, "price fell under vendor price and 21 units appeared: a deal for 21 at 2c is shown at once")
    local searched = false
    for i = n6 + 1, #sent do if sent[i] == "search5555" then searched = true end end
    check(not searched, "no item check was spent on it first (0.65s saved)")
    print("     " .. label())
    press(); advance(0.3)
    check(S.buying and S.buying.phase == "confirm" and S.buying.total == 42, "first click: the server quotes exactly 21 x 2c, so Buy is offered")
    press(); advance(0.5)
    check(gold == 900 - 42 and AuctionMeshDB.flips[5555] and AuctionMeshDB.flips[5555].units == 21, "second click: bought 21 for 42c")
    AuctionMeshDB.flips[5555] = nil; ns.Journal:Dropped(5555, nil, "test")
    -- the estimate was wrong (some were already gone): the quote says so and nothing is bought
    reset(); gold = 900
    LIST[5555] = { { 2, 5 }, { 22, 138 }, { 23, 1095 } }
    S.ownSweep = { [5555] = { q = 1233, p = 22, at = GetTime() - 0.7 } }
    S:OnSweep(5555, 2, 1254)
    check(S.verified[5555] and S.verified[5555].instant, "second instant deal on screen")
    press(); advance(0.3)
    check(gold == 900 and S.verified[5555] and S.verified[5555].units == 5 and S.verified[5555].cost == 10 and not (S.result and S.result.kind == "lost"),
        "radar said 21 but only 5 were left: the quote says so, nothing is bought yet, and the deal becomes those 5")
    S.verified[5555] = nil
    S.verified[5555] = nil; S.dealSeen = {}; G.holdUntil = nil

    -- THE RADAR ITSELF SHOWS A DEAL IS GONE: off the panel at once, no re-check (it stayed 10 to 21 seconds in a real log, then cost a request)
    do
        reset(); gold = 900; S.cool = {}
        local SwR = ns.Swarm
        local curWas = SwR.current
        LIST[5555] = { { 2, 21 }, { 22, 138 }, { 23, 1095 } }
        S.ownSweep = { [5555] = { q = 1233, p = 22, at = GetTime() - 0.7 } }
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 2, 1254)
        local d5 = S.verified[5555]
        check(d5 and d5.instant and d5.units == 21 and d5.born == GetTime(), "a deal straight from the radar is on the panel")
        -- the read that showed it (sent before the deal existed) does not take it off, whatever it says
        S:OnSweep(5555, 22, 1233)
        check(S.verified[5555] == d5, "a radar read sent BEFORE the deal was read says nothing about it: the deal stays")
        -- a later read with the cheap units still there: it stays
        advance(0.7)
        local n7, gone0 = #sent, S.tally.gone
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 2, 1250)
        check(S.verified[5555] == d5, "a later read that still shows the cheap price: the deal stays")
        -- a later read: the cheapest is back at 22c. Someone bought them.
        G.holdUntil = GetTime() + 5
        advance(0.7)
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 22, 1233)
        local searched = false
        for i = n7 + 1, #sent do if sent[i] == "search5555" then searched = true end end
        check(S.verified[5555] == nil and S.tally.gone == gone0 + 1 and S.result and S.result.kind == "gone" and S.result.key == 5555,
            "a later read shows the cheapest back at 22c: the deal is off the panel at once and counted as gone")
        check(not searched and S.priority ~= 5555, "no re-check is asked for: the radar has already said it (a request, 0.75s without the radar, saved)")
        check(G.holdUntil == nil, "with no other deal up the radar's hold ends")
        local o = AuctionMeshDB.outcomes[#AuctionMeshDB.outcomes]
        check(o.k == "gone" and o.key == 5555 and o.g and o.g > 1.3 and o.g < 1.5, "it is kept with how long it was up (1.4s), for Details, Session")
        -- two deals up, one goes: the hold for the other stands
        S.result = nil
        S.ownSweep = { [5555] = { q = 1233, p = 22, at = GetTime() - 0.7 } }
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 2, 1254)
        S.verified[7777] = { key = 7777, kind = "VENDOR", units = 1, cost = 3, sell = 5, profit = 20, deposit = 0, buys = {}, counts = {}, commodity = true, at = GetTime(), born = GetTime(), from = "me" }
        ITEMS[7777] = { "Test Ore", 5 }
        advance(0.7)
        G.holdUntil = GetTime() + 5
        local holdWas = G.holdUntil
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 22, 1233)
        check(S.verified[5555] == nil and S.verified[7777] ~= nil and G.holdUntil == holdWas, "with another deal still up, its hold stands when the first one goes")
        -- your own purchase in progress is never taken off by the radar
        S.verified[7777] = nil
        S.ownSweep = { [5555] = { q = 1233, p = 22, at = GetTime() - 0.7 } }
        SwR.current = { phase = "query", at = GetTime() - 0.25, unit = SwR.units[1] }
        S:OnSweep(5555, 2, 1254)
        S.buying = { key = 5555, units = 21, max = 42, phase = "quote", deal = S.verified[5555], at = GetTime() }
        advance(0.1)
        SwR.current = { phase = "query", at = GetTime() - 0.05, unit = SwR.units[1] }
        S:OnSweep(5555, 22, 1233)
        check(S.verified[5555] ~= nil, "a deal you are buying is left to the purchase: the server's answer decides")
        S.buying = nil
        SwR.current = curWas
        ITEMS[7777] = nil
        S.verified, S.dealSeen, S.result, G.holdUntil = {}, {}, nil, nil
        S.tally.won, S.tally.lost, S.tally.gone = 0, 0, 0
        UI.flashUntil = nil
    end
    LIST[5555] = nil

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
    S.triggers = {}; S.verified[2319] = nil; S.checkedAt[2319] = nil; S.judged = {}
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(ns.Scout:Day().reads == reads0 and S.triggers[2319] == nil, "a category list that is not the answer to our own radar request is ignored (no alerts for prices that are long gone)")
    Sw.current = { unit = Sw.units[1], phase = "query", at = Sw.clock(), requests = 1 }
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(ns.Scout:Day().reads == reads0 + 1 and S.triggers[2319] ~= nil, "the answer to our own radar request is read")
    Sw.current = nil; S.triggers = {}
    S.hold = 0; reset()
    LIST[2770] = nil
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

print("capital: your money is out of reach for an hour after a sale")
do
    local cfg = AuctionMeshDB.cfg
    ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 0.35, 0.50
    gold = 2155
    AuctionMeshDB.listed = {}; AuctionMeshDB.sales = nil; AuctionMeshDB.flips = {}
    S.ownSoldQty, S.own, S.ownRead = { [2449] = 16 }, {}, true
    S.ownSoldPay = { { amount = 3654, due = GetTime() + 29 * 60 } }
    local c = S:Capital()
    check(c.gold == 2155 and c.tied == 3654 and c.paused == false and c.room == 2904,
        "21s55c in hand, 36s54c sold and on its way: that gold is certain, so flips are NOT paused")
    do
        local o = S:DealOptions(2589, true)
        check(o.tied == 0 and o.coming == 3654, "the deal rules are told: nothing at risk, 36s54c coming")
    end
    -- the same money in auctions that have NOT sold is at risk: big flips stop
    S.ownSoldQty, S.ownSoldPay = {}, {}
    AuctionMeshDB.listed = { [2449] = { qty = 16, price = 240, cost = 125, at = GetServerTime() } }
    c = S:Capital()
    check(c.listed == 3648 and c.paused == true and c.room == 0, "21s55c in hand, 36s48c in auctions that have not sold: big flips are paused")
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
    local st = strip(AuctionMeshFrame.status._text)
    print("     " .. (st:match("^[^\n]+") or ""))
    check(st:find("^Big flips paused: 36s48c of your 58s03c is in auctions that have not sold %(limit 50%%%). Small flips and vendor deals are still shown."),
        "the Trades tab says so")
    UI.tab = "HISTORY"; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp.tied._text == "50% of what you own", "Setup shows the limit")
    sp.tied._scripts.OnClick(sp.tied); UI:Render()
    check(cfg.maxTied == 70 and math.abs(ns.Deals.cfg.maxTied - 0.70) < 1e-9 and sp.tied._text == "70% of what you own" and S:Capital().paused == false,
        "one click raises it to 70%: flips are allowed again")
    ns.Do.MaxTied(50)
    AuctionMeshDB.listed = {}
    S.ownSoldQty = { [2449] = 16 }
    S.ownSoldPay = { { amount = 3654, due = GetTime() + 29 * 60 } }
    -- the pay-out time passes: the gold is in the mailbox, and the panel says to collect it
    advance(30 * 60)
    S.verified = {}
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
    print("     " .. strip(AuctionMeshSnipeButton.label._text))
    S.underMin = nil; UI:Render()
    check(strip(AuctionMeshSnipeButton.label._text) == "Watching. No deal right now.", "the snipe box shows nothing but sniping: no 'visit a mailbox' in it")
    check(strip(AuctionMeshFrame.ledger.rows[2].value._text) == "+ 36s54c", "the gold waiting in the mailbox is in the MONEY rows")
    do  -- collecting it at the mailbox takes it off "waiting" at once, even if you walk away before the mailbox is read again
        local Se = ns.Seller
        AuctionMeshDB.sales = { waiting = 0, pending = { { amount = 980, at = GetServerTime() - 60 }, { amount = 530, at = GetServerTime() - 30 }, { amount = 510, at = GetServerTime() + 900 } } }
        S.ownSoldPay = {}
        local w, o = Se:SalesMoney()
        check(w == 1510 and o == 510, "two sales have paid out (15s10c in the mailbox), one is still on its way (5s10c)")
        local total0 = gold + w + o
        Se.goldSeen = gold
        MailFrame:Show()
        gold = gold + 980; fire("PLAYER_MONEY")
        gold = gold + 530; fire("PLAYER_MONEY")
        MailFrame:Hide() -- closed before any new reading of the mailbox
        w, o = Se:SalesMoney()
        check(w == 0 and o == 510 and gold + w + o == total0, "after collecting, the total is unchanged: the gold is counted once (it used to stay in 'waiting' as well)")
        gold = gold - 1510; Se.goldSeen = gold
        AuctionMeshDB.sales = nil
    end
    do  -- a minimum that hides every deal is pointed out in the box
        local was = ns.Deals.cfg.minProfit
        ns.Deals.cfg.minProfit = 9000
        S.underMin = { n = 4, best = 1122, at = GetTime() }
        UI:Render()
        print("     " .. strip(AuctionMeshSnipeButton.label._text))
        check(strip(AuctionMeshSnipeButton.label._text) == "4 deals hidden by your 90s00c minimum profit (best: + 11s22c). Lower it on the Setup tab.",
            "a minimum of 90s that hides every deal is said so in the box")
        ns.Deals.cfg.minProfit = was; S.underMin = nil
    end
    S.ownSoldPay, S.ownSoldQty = {}, {}
    ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 1, 1
end

print("one input to buy, the wheel, small flips, friends")
do
    local G, cfg, Sw = ns.Gate, AuctionMeshDB.cfg, ns.Swarm
    local btn = AuctionMeshSnipeButton
    local function label() return strip(btn.label._text) end
    local function reset()
        S.verified, S.checkedAt, S.triggers, S.sweep, S.dealSeen, S.floor, S.cool, S.muted, S.streak, S.judged = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
        S.buying, S.searching, S.result, S.lastEval, S.priority = nil, nil, nil, nil, nil
        G.holdUntil, G.outstanding, G.nextAt, G.penaltyUntil, G.userUntil = nil, 0, 0, 0, 0
    end
    UI.tab = "BUY"; UI.notice = nil
    AuctionMeshDB.flips, AuctionMeshDB.listed = {}, {}
    -- one click, where the game allows a purchase that is not sent from a click
    reset(); gold = 900; cfg.autoConfirm = nil
    ITEMS[2770] = { "Copper Ore", 5 }
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(1)
    btn._scripts.OnClick(btn); advance(1)
    check(gold == 900 - 36 and S.result and S.result.kind == "won", "ONE click: the price came back as shown, so the purchase was sent without a second click")
    AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
    -- where the game blocks that: it is switched off, and the next input confirms
    reset(); gold = 900
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(1)
    local realConfirm = C_AuctionHouse.ConfirmCommoditiesPurchase
    C_AuctionHouse.ConfirmCommoditiesPurchase = function() fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()") end
    btn._scripts.OnClick(btn); advance(0.4)
    C_AuctionHouse.ConfirmCommoditiesPurchase = realConfirm
    check(cfg.autoConfirm == false and S.buying and S.buying.phase == "confirm" and gold == 900, "the game blocked it: one-click is switched off for good, the deal waits for a second input")
    check(label():find("^BUY NOW"), "the button says BUY NOW")
    -- that second input can be a notch of the mouse wheel
    check(UI.WheelPress() == true, "a notch of the mouse wheel counts as the second input")
    advance(0.5)
    check(gold == 900 - 36 and S.result.kind == "won", "bought with one click and one wheel notch")
    AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
    LIST[2770] = nil; S.verified = {}; S.buying = nil
    check(UI.WheelPress() == false, "with no deal on the button the wheel scrolls as usual")
    -- the wheel can do both steps
    reset(); gold = 900
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770; advance(1); UI:Render()
    check(strip(btn.hint._text):find("Roll the mouse wheel here (or anywhere), or click: it buys.", 1, true), "the box says the wheel can be used")
    UI.WheelPress(); UI.WheelPress(); advance(0.3); UI.WheelPress(); UI.WheelPress(); advance(0.5)
    check(gold == 900 - 36 and S.result.kind == "won", "a flick of the wheel alone: first notch asks the price, a later notch buys, the rest do nothing")
    AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
    -- THE SNIPE BOX: keep rolling the wheel in it; the first deal that appears is bought
    reset(); gold = 900; cfg.autoConfirm = nil
    local flipsWere = ns.Deals.cfg.flips
    ns.Deals.cfg.flips = false -- vendor deals only, so that nothing else in the test market is a deal
    LIST[2770] = nil; advance(2); S.verified = {}; UI:Render()
    check(strip(btn.hint._text):find("^SNIPE BOX, not armed: put the mouse here and keep rolling the wheel"), "with no deal the box says what to do")
    check(btn._scripts.OnEnter == nil and not G:UserBusy(), "the mouse resting in the box pauses nothing (it used to stop the radar)")
    local wheel = btn._scripts.OnMouseWheel
    local before = ns.Swarm.stats.queries
    for _ = 1, 10 do wheel(btn, 1); advance(0.2) end
    UI:Render()
    print("     " .. label() .. "  |  " .. strip(btn.hint._text))
    check(label():find("^ARMED") and (label():find("every request goes to the radar and its alerts", 1, true) or label():find("radar first; %d+ listings? still being read for instant flips")) and strip(btn.hint._text):find("^Armed: keep the inputs coming%.$"), "rolling in the box with no deal: ARMED, and it says where the requests go")
    print("     " .. strip(btn.hint._text))
    check(strip(AuctionMeshFrame.snipe.pace.text._text):find("^An input every 200 ms: "), "the gauge under the box shows how fast the inputs come: one every 200 ms")
    do  -- THE PACE GAUGE: is that fast enough? Three zones scaled to the game's lock, and a marker where you are
        local pg = rawget(btn, "pace")
        local function pace(gap, n)
            local t, now = {}, GetTime()
            for i = n or 4, 0, -1 do t[#t + 1] = now - i * gap end
            UI.inputTimes = t
            UI:Render()
            return UI.paceState, strip(pg.text._text)
        end
        ns.Gate.cycle = 0.74 -- the lock as measured in the real logs: the window is 490 ms
        local st, txt = pace(0.1)
        print("     " .. txt)
        check(st.zone == "optimal" and txt == "An input every 100 ms: OPTIMAL" and pg.mark._shown,
            "an input every 100 ms: the gauge reads OPTIMAL, and nothing more")
        st, txt = pace(0.24); check(st.zone == "optimal", "240 ms: still optimal (two inputs always land in the window)")
        st, txt = pace(0.35)
        print("     " .. txt)
        check(st.zone == "intime" and txt:find("^An input every 350 ms: IN TIME, NOTHING TO SPARE  %(optimal: every 245 ms or faster%)$"), "350 ms: in time, with nothing to spare, and the target is named")
        st, txt = pace(0.8, 2)
        print("     " .. txt)
        check(st.zone == "slow" and txt:find("^An input every 800 ms: TOO SLOW"), "800 ms: too slow, a deal can sit waiting for the next input")
        UI.inputTimes = { GetTime() - 10, GetTime() - 9 }; UI:Render()
        check(UI.paceState.zone == nil and strip(pg.text._text):find("^Not pressing%.") and not pg.mark._shown, "no inputs: 'Not pressing', and the marker is gone")
        ns.Gate.cycle = 1.0; pace(0.3)
        check(UI.paceState.zone == "optimal" and math.abs(UI.paceState.window - 0.75) < 1e-6, "the zones follow the measured lock: a slower server widens the window")
        ns.Gate.cycle = nil; UI.inputTimes = nil
        -- the verdict on each try
        S.tally.inTime, S.tally.late = 0, 0
        S.tryInfo = { key = 2770, t0 = GetTime(), input = 0.03, held = 0.46 }; S:Result("lost", 2770, "MISSED  test")
        check(S.lastTry and S.lastTry.late == false and S.tally.inTime == 1, "a price request the game had to hold for its lock: the input was IN TIME (it could not have left sooner)")
        S.tryInfo = { key = 2770, t0 = GetTime(), input = 1.4 }; S:Result("lost", 2770, "MISSED  test")
        check(S.lastTry.late == true and S.tally.late == 1, "an input 1.4 seconds after the deal, sent with the lock already open: LATE")
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
        check(drawerText("session"):find("Presses in time this session  |  1 of 2\nOptimal: an input every 245 ms or faster. Too slow: over 490 ms.", 1, true),
            "Details, Session keeps the count (1 of 2 presses in time) and the two limits")
        S.tally.won, S.tally.lost, S.tally.gone, S.tally.inTime, S.tally.late = 0, 0, 0, nil, nil
        S.result, S.lastTry, UI.flashUntil = nil, nil, nil
    end
    check(S:SnipeMode(), "snipe mode is on while you roll: routine item checks and side classes wait")
    check(gold == 900 and S.buying == nil, "nothing is bought while there is no deal")
    check(ns.Swarm.stats.queries > before, "the radar keeps reading while you roll")
    LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
    S.priority = 2770
    local t0, got = GetTime(), nil
    for _ = 1, 60 do -- still rolling: a notch every 0.1s
        wheel(btn, 1); advance(0.1)
        if not got and gold < 900 then got = GetTime() - t0 end
        if gold == 900 - 36 then break end
    end
    print(("     deal put up while rolling: first purchase %.1fs later, no click; all 12 bought for %d"):format(got or -1, 900 - gold))
    check(got and gold == 900 - 36, "a deal appears while you roll: it is bought by the wheel alone, without a click")
    AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
    advance(2); UI:Render()
    check(not UI.Armed() and strip(btn.hint._text):find("^SNIPE BOX, not armed"), "the box stops saying armed within a second of the wheel stopping")
    advance(2)
    check(not S:SnipeMode(), "and snipe mode ends 3 seconds after the last notch")
    -- outside the box, with no deal, the wheel scrolls the list as before
    check(UI.WheelPress() == false and UI.WheelPress(true) == true, "outside the box the wheel still scrolls; inside it never does")
    UI.wheelSeen = nil
    ns.Deals.cfg.flips = flipsWere
    -- if the game does not take the wheel as an input, it is switched off
    -- (only when the blocked action really was a price request or purchase sent from that input)
    S.inputAt, S.inputVia, S.inputCallAt = GetTime(), "wheel", nil; fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()")
    check(UI.BuyMode() == "wheel" and not (cfg.buyBlocked and cfg.buyBlocked.wheel), "a blocked action while the wheel is rolling, but not sent by the wheel, does not switch wheel buying off")
    S.inputAt, S.inputVia, S.inputCallAt = GetTime(), "wheel", GetTime(); fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()")
    check(UI.BuyMode() == "click" and cfg.buyBlocked.wheel and UI.WheelPress() == false, "if the game refuses wheel inputs, buying falls back to clicks and the wheel scrolls again")
    cfg.buyMode, cfg.buyBlocked = nil, nil
    LIST[2770] = nil

    -- BUY WITH: the wheel, a key you tap, or clicks only
    do
        local bound = {}
        SetOverrideBindingClick = function(owner, _, key, target, mouse) bound[owner] = bound[owner] or {}; bound[owner][key] = target .. ":" .. mouse end
        ClearOverrideBindings = function(owner) bound[owner] = nil end
        local function keyBound() return bound[btn] and next(bound[btn]) end
        local sp = AuctionMeshFrame.setup
        reset(); gold = 900; cfg.autoConfirm = nil; cfg.buyKey = nil
        local flipsWere2 = ns.Deals.cfg.flips
        ns.Deals.cfg.flips = false
        UI.tab = "HISTORY"; UI:Render()
        check(UI.BuyMode() == "wheel" and sp.buy._text == "Mouse wheel", "Setup, Buy with: the mouse wheel to begin with")
        sp.buy._scripts.OnClick(sp.buy); UI:Render()
        check(UI.BuyMode() == "key" and sp.buy._text == "A key: tap it" and sp.key._text == "Not set: click, then press a key", "one click: buy with a key; no key chosen yet")
        UI.tab = "BUY"; UI:Render()
        check(strip(btn.hint._text):find("no key chosen yet: Setup tab, Key", 1, true) and not keyBound(), "the snipe box says a key has to be chosen first; nothing is bound")
        -- choosing the key: click the button, press the key
        UI.tab = "HISTORY"; UI:Render()
        sp.key._scripts.OnClick(sp.key); UI:Render()
        check(UI.capturingKey and sp.key._text == "Press a key... (Esc cancels)", "click Key: it waits for a key press")
        sp.key._scripts.OnKeyDown(sp.key, "ESCAPE"); UI:Render()
        check(not UI.capturingKey and cfg.buyKey == nil, "Esc cancels and sets nothing")
        sp.key._scripts.OnClick(sp.key)
        IsShiftKeyDown = function() return true end
        sp.key._scripts.OnKeyDown(sp.key, "LSHIFT")
        check(UI.capturingKey and cfg.buyKey == nil, "a modifier on its own is not taken as the key")
        sp.key._scripts.OnKeyDown(sp.key, "F"); UI:Render()
        IsShiftKeyDown = nil
        check(not UI.capturingKey and cfg.buyKey == "SHIFT-F" and sp.key._text == "Key: SHIFT-F", "Shift+F pressed: the key is SHIFT-F")
        sp.key._scripts.OnClick(sp.key); sp.key._scripts.OnKeyDown(sp.key, "F"); UI:Render()
        check(cfg.buyKey == "F" and sp.key._text == "Key: F", "pressed again without Shift: the key is F")
        check(not keyBound(), "on the Setup tab the key is not taken over")
        -- on the Trades tab the key is bound to the snipe box, deal or no deal; other tabs give it back
        UI.tab = "BUY"; UI:Render()
        check(bound[btn] and bound[btn].F == "AuctionMeshSnipeButton:KEY", "on the Trades tab F is bound to the snipe box")
        check(strip(btn.hint._text):find("tap F (it works anywhere while this tab is open), or click here", 1, true), "and the box says so")
        UI.tab = "SELL"; UI:Render()
        check(not keyBound(), "on the Bags tab F is your own key again")
        UI.tab = "BUY"; UI:Render()
        -- tapping with no deal arms the box, like the wheel does
        local q0 = ns.Swarm.stats.queries
        for _ = 1, 6 do btn._scripts.OnClick(btn, "KEY"); advance(0.2) end
        UI:Render()
        check(label():find("^ARMED") and S:SnipeMode() and gold == 900 and ns.Swarm.stats.queries > q0, "tapping the key with no deal: ARMED, radar only, nothing bought")
        check(UI.WheelPress(true) == false, "in key mode the mouse wheel does not buy (it scrolls)")
        -- a deal appears while tapping: the key alone buys it
        AuctionMeshDB.outcomes = {}
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770
        local t0, at
        t0 = GetTime()
        for _ = 1, 40 do
            btn._scripts.OnClick(btn, "KEY"); advance(0.1)
            if gold < 900 and not at then at = GetTime() - t0 end
        end
        check(gold == 900 - 36 and at and at <= 2.5, ("a deal appears while tapping F: bought by the key alone, %.1fs after it was listed"):format(at or -1))
        do
            local o = AuctionMeshDB.outcomes[#AuctionMeshDB.outcomes]
            check(o and o.k == "won" and o.v == "key", "the outcome is recorded as bought with the key")
        end
        AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test"); LIST[2770] = nil
        reset(); gold = 900; UI.wheelSeen = nil
        -- HOLDING A KEY DOWN IS GONE: the game blocks every purchase sent from a held key (a real log)
        check(UI:SetBuyMode("hold") == nil and UI.BuyMode() ~= "hold" and rawget(btn, "holdBox") == nil, "there is no 'hold a key' way to buy any more")
        cfg.buyMode = "hold"
        check(UI.BuyMode() == "wheel", "a setting saved as 'hold' buys with the wheel")
        cfg.buyMode = nil
        do  -- AN INPUT THE GAME BLOCKS: the purchase is dropped at once and the deal stays (it froze for 4 seconds)
            UI:SetBuyMode("key"); UI:Render()
            LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
            S.priority = 2770; advance(1)
            local realStart = C_AuctionHouse.StartCommoditiesPurchase
            C_AuctionHouse.StartCommoditiesPurchase = function() fire("ADDON_ACTION_BLOCKED", "AuctionMesh", "UNKNOWN()") end
            local blockedWas = ns.Swarm.blocked or 0
            ns.Swarm.browseSentAt = GetTime() -- a radar read went out in the same half second
            btn._scripts.OnClick(btn, "KEY")
            check(S.buying == nil and S.verified[2770] ~= nil, "the game blocks the price request an input sent: nothing is left waiting for a price, and the deal is still on screen")
            check((ns.Swarm.blocked or 0) == blockedWas, "and it is not counted as a blocked radar read (three of those switch the radar off)")
            check(UI.BuyMode() == "wheel" and cfg.buyBlocked.key, "that way of buying is dropped for one that works")
            C_AuctionHouse.StartCommoditiesPurchase = realStart
            btn._scripts.OnMouseWheel(btn, 1); advance(1.5)
            check(gold == 900 - 36, "the next input that works buys it at once")
            AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test"); LIST[2770] = nil
            reset(); gold = 900; UI.wheelSeen = nil; cfg.buyBlocked = nil
        end
        do  -- ONE KEY FOR EVERYTHING: it buys the deal that is up; with none it posts what is ready in your bags
            UI:SetBuyMode("one"); UI.tab = "BUY"; UI:Render()
            check(UI.BuyMode() == "one" and keyBound() and strip(btn.hint._text):find("keep tapping F: it buys the deal that is up; with none it posts what is ready in your bags", 1, true),
                "one key: F is bound on the Trades tab and the box says what it does")
            UI.tab = "SELL"; UI:Render()
            check(keyBound(), "and on the Bags tab too (there it posts)")
            UI.tab = "HISTORY"; UI:Render()
            check(not keyBound(), "on the Setup tab F is your own key")
            UI.tab = "BUY"; UI:Render()
            -- nothing to post, no deal: presses arm the box and say nothing
            local nchat, np = #chat, #posted
            for _ = 1, 20 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
            check(#chat == nchat and #posted == np and S:SnipeMode(), "pressed 20 times a second with nothing to do: armed, nothing posted, not a word in chat")
            -- 5 Wool Cloth in the bags, bought at 34c; the market is at 1s50c
            ITEMS[2592] = { "Wool Cloth", 33 }
            LIST[2592] = { { 150, 100 }, { 155, 300 } }
            AuctionMeshDB.flips[2592] = { kind = "FLIP", units = 5, cost = 34, sell = 160, at = GetServerTime(), proof = "test" }
            for s2 = 1, 16 do bags[s2] = nil end
            bags[1] = { itemID = 2592, stackCount = 5 }; fire("BAG_UPDATE_DELAYED")
            nchat = #chat
            for _ = 1, 60 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
            print(("     posted %d, chat lines %d: %s"):format(#posted - np, #chat - nchat, tostring(chat[#chat])))
            check(#posted == np + 1 and posted[#posted].qty == 5 and posted[#posted].price == 149, "5 Wool Cloth in the bags: the same key, pressed with no deal up, gets the live price and posts them once, at 1s49c")
            check(#chat - nchat <= 2 and chat[#chat]:find("Posted 5x", 1, true), "chat has the 'Posted' line and no line per press")
            UI:Render()
            print("     " .. label())
            check(label():find("^POSTED 5 x Wool Cloth at 1s49c each. Nothing left to post."), "the snipe box says what was posted and that nothing is left (posting from the Trades tab used to show nothing)")
            do  -- each step of a post is shown while it happens
                local Se3 = ns.Seller
                Se3:Note(2592, "Getting the live price first. Press Post again in a second.")
                UI:Render()
                check(label():find("^Posting Wool Cloth: Getting the live price first"), "while the price is being fetched the box says so")
                UI.tab = "SELL"; UI:Render()
                check(strip(AuctionMeshFrame.status._text):find("^Posting Wool Cloth: Getting the live price first"), "and so does the top of the Bags tab")
                check(rawget(btn, "result") and rawget(btn, "result")._shown == false, "the 'Last: GOT IT' line of the snipe box is not left showing over the Bags tab")
                UI.tab = "HISTORY"; UI:Render()
                check(rawget(btn, "result")._shown == false, "nor over the Setup tab")
                UI.tab = "BUY"; UI:Render()
                check(rawget(btn, "result")._shown == true, "it is back on the Trades tab")
                advance(5); UI:Render()
                check(not label():find("^Posting"), "after a few seconds the box is back to sniping")
                Se3.note = nil
            end
            check(AuctionMeshDB.flips[2592] == nil and AuctionMeshDB.listed[2592] ~= nil, "it is booked as listed, like a post made with the Post button")
            -- a deal and something to post at the same time: the deal comes first
            AuctionMeshDB.flips[4306] = { kind = "FLIP", units = 3, cost = 90, sell = 200, at = GetServerTime(), proof = "test" }
            ITEMS[4306] = { "Silk Cloth", 40 }
            LIST[4306] = { { 200, 100 }, { 205, 300 } }
            bags[2] = { itemID = 4306, stackCount = 3 }; fire("BAG_UPDATE_DELAYED")
            LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
            S.verified = {}; S.priority = 2770; advance(1)
            local order = {}
            local realStart, realPost = C_AuctionHouse.StartCommoditiesPurchase, C_AuctionHouse.PostCommodity
            C_AuctionHouse.StartCommoditiesPurchase = function(...) order[#order + 1] = "buy"; return realStart(...) end
            C_AuctionHouse.PostCommodity = function(...) order[#order + 1] = "post"; return realPost(...) end
            for _ = 1, 80 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
            C_AuctionHouse.StartCommoditiesPurchase, C_AuctionHouse.PostCommodity = realStart, realPost
            print("     order: " .. table.concat(order, ", "))
            check(order[1] == "buy" and gold == 900 - 36, "a deal is up and an item is waiting to be posted: the key buys first")
            local postedSilk = false
            for i = 2, #order do if order[i] == "post" then postedSilk = true end end
            check(postedSilk and posted[#posted].qty == 3, "then, with no deal left, it posts the Silk Cloth")
            -- on the Bags tab the key posts as well
            AuctionMeshDB.flips[2589] = { kind = "FLIP", units = 4, cost = 10, sell = 80, at = GetServerTime(), proof = "test" }
            LIST[2589] = { { 78, 100 }, { 80, 300 } }
            bags[3] = { itemID = 2589, stackCount = 4 }; fire("BAG_UPDATE_DELAYED")
            UI.tab = "SELL"; UI:Render()
            np = #posted
            for _ = 1, 60 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
            check(#posted == np + 1 and posted[#posted].qty == 4, "on the Bags tab the one key posts the next item too")
            UI.tab = "BUY"; UI:Render()
            do  -- a post the game refuses is not tried over and over
                AuctionMeshDB.flips[2589] = { kind = "FLIP", units = 4, cost = 10, sell = 80, at = GetServerTime(), proof = "test" }
                bags[3] = { itemID = 2589, stackCount = 4 }; fire("BAG_UPDATE_DELAYED")
                local tries = 0
                local realPost = C_AuctionHouse.PostCommodity
                C_AuctionHouse.PostCommodity = function() tries = tries + 1; fire("UI_ERROR_MESSAGE", 1, "You cannot post that auction") end
                for _ = 1, 200 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
                C_AuctionHouse.PostCommodity = realPost
                check(tries == 1, ("the game refuses a post: the one key tries it once in 10 seconds of pressing, not on every press (%d)"):format(tries))
                Se.refusedAt = {}; Se.note, Se.posting = nil, nil
            end
            ns.Do.Import("AMS1:buy=one"); check(UI.BuyMode() == "one", "a settings code can choose it (buy=one)")
            -- cleanup
            AuctionMeshDB.flips[2770] = nil; AuctionMeshDB.flips[4306] = nil; AuctionMeshDB.flips[2589] = nil; AuctionMeshDB.listed = {}
            for _, k in ipairs({ 2770, 4306, 2589, 2592 }) do ns.Journal:Dropped(k, nil, "test") end
            LIST[2770], LIST[4306], LIST[2589], LIST[2592] = nil, nil, nil, nil
            for s2 = 1, 16 do bags[s2] = nil end
            fire("BAG_UPDATE_DELAYED")
            Se.note, Se.posting = nil, nil
            reset(); gold = 900; UI.wheelSeen = nil; cfg.buyBlocked = nil
        end
        -- clicks only
        UI:SetBuyMode("click"); UI:Render()
        check(UI.WheelPress(true) == false and not keyBound() and strip(btn.hint._text):find("click here", 1, true), "clicks only: no wheel, no key")
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.priority = 2770; advance(1)
        btn._scripts.OnClick(btn, "LeftButton"); advance(1)
        check(gold == 900 - 36, "and a click on the box still buys in every mode")
        AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test"); LIST[2770] = nil
        -- the settings code carries it
        UI:SetBuyMode("key")
        check(ns.Do.SettingsCode():find(";buy=key;key=F;", 1, true), "the settings code says buy=key;key=F")
        ns.Do.Import("AMS1:buy=click"); check(UI.BuyMode() == "click", "a code can set the way to buy (buy=click)")
        ns.Do.Import("AMS1:buy=hold"); check(UI.BuyMode() == "click", "(buy=hold in an old code is ignored)")
        ns.Do.Import("AMS1:buy=key;key=shift-g"); check(UI.BuyMode() == "key" and cfg.buyKey == "SHIFT-G", "and the key (key=shift-g)")
        ns.Do.Import("AMS1:wheel=0"); check(UI.BuyMode() == "click", "an older code with wheel=0 still means clicks only")
        ns.Do.Import("AMS1:wheel=1"); check(UI.BuyMode() == "wheel", "and wheel=1 the mouse wheel")
        ns.Do.Import("AMS1:buy=banana"); check(UI.BuyMode() == "wheel", "a way to buy that does not exist changes nothing")
        -- waiting for a key press ends when the Setup tab is left
        UI.tab = "HISTORY"; UI:Render()
        sp.key._scripts.OnClick(sp.key)
        AuctionMeshFrame.tabBuy._scripts.OnClick(AuctionMeshFrame.tabBuy)
        check(not UI.capturingKey and UI.tab == "BUY", "leaving the Setup tab while it waits for a key cancels the wait")
        -- THE MOST VALUABLE WAY OUT, with the numbers from the real log: Silk Cloth
        -- bought at 99c (a vendor pays 1s50c), market at 1s98c
        do
            local Se2 = ns.Seller
            ITEMS[4306] = { "Silk Cloth", 150 }
            local f = { kind = "VENDOR", units = 11, cost = 99, sell = 150 }
            local was = Se2.prices[4306]; Se2.prices[4306] = nil
            ns.Store.fp[4306], ns.Store.ft[4306] = 198, GetServerTime()
            local exit, net = Se2:BestExit(4306, f)
            check(exit == "AH" and net == 187, "Silk Cloth, vendor 1s50c, market 1s98c: the auction house (1s87c each after the cut) is the recommendation")
            ns.Store.fp[4306] = 170
            exit, net = Se2:BestExit(4306, f)
            check(exit == "VENDOR" and net == 160, "market down to 1s70c (1s60c after the cut): not 10% better than the vendor's sure 1s50c, so the vendor it is")
            Se2.prices[4306] = { hold = "a vendor pays as much", at = GetTime() }
            ns.Store.fp[4306] = 198
            check(Se2:BestExit(4306, f) == "VENDOR", "a live price check that said the vendor pays as much is believed for 10 minutes")
            Se2.prices[4306] = was; ns.Store.fp[4306], ns.Store.ft[4306] = nil, nil
            do  -- LISTINGS UNDER VENDOR PRICE ARE NOT THE MARKET (a real Snapshot: Mageweave Cloth shown as "sell to a vendor" with the market at 4s40c)
                ITEMS[4338] = { "Mageweave Cloth", 250 }
                ns.Sniper.vendor[4338] = nil
                local fl = { kind = "VENDOR", units = 10, cost = 181, sell = 250 }
                AuctionMeshDB.flips[4338] = fl
                local function R(t) local r = {}; for i, x in ipairs(t) do r[i] = { price = x[1], qty = x[2] } end return r end
                -- a pile of 120 at 2s02c (under what a vendor pays) on top of a market at 4s59c
                Se2:OnResults(4338, R({ { 202, 120 }, { 459, 289 }, { 465, 18 }, { 470, 309 }, { 473, 20 } }), true)
                local pr = Se2.prices[4338]
                print("     Mageweave, 120 listed at 2s02c over a 4s59c market: " .. tostring(pr and (pr.price or pr.hold)))
                check(pr and pr.price == 458 and Se2:BestExit(4338, fl) == "AH", "a pile listed under vendor price is not the market: the price is 4s58c and the advice is the auction house, not a vendor")
                -- the whole market really is under vendor price: then the vendor it is
                Se2:OnResults(4338, R({ { 202, 500 }, { 205, 800 }, { 210, 900 } }), true)
                pr = Se2.prices[4338]
                check(pr and pr.hold and Se2:BestExit(4338, fl) == "VENDOR", "when everything listed is under vendor price, a vendor is the better way out")
                -- a market above vendor price but not 10% better after the cut: vendor, as before
                Se2:OnResults(4338, R({ { 270, 500 }, { 272, 800 }, { 275, 900 } }), true)
                pr = Se2.prices[4338]
                check(pr and pr.hold == "a vendor pays as much", "a market only a little over vendor price: still the vendor")
                AuctionMeshDB.flips[4338] = nil; Se2.prices[4338] = nil; ITEMS[4338] = nil; ns.Sniper.vendor[4338] = nil
            end
        end
        cfg.buyMode, cfg.buyBlocked, cfg.buyKey = nil, nil, nil
        SetOverrideBindingClick, ClearOverrideBindings = nil, nil
        UI.wheelBound, UI.keyBound = nil, nil
        ns.Deals.cfg.flips = flipsWere2
        reset(); UI.notice = nil; UI.wheelSeen = nil
    end

    -- a small flip is allowed even when most of the money is out of reach (the 62c Heavy Stone from the real log)
    ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 0.35, 0.50
    local function rows(t) local r = {}; for i, x in ipairs(t) do r[i] = { price = x[1], qty = x[2] } end return r end
    local d = ns.Deals.evaluate(rows({ { 62, 1 }, { 302, 605 }, { 303, 153 }, { 304, 49 } }), { budget = 739, gold = 739, tied = 7506, commodity = true, rate = 5000 })
    check(d and d.units == 1 and d.cost == 62, "7s39c in hand, 75s out of reach: a 62c flip worth +2s is still offered")
    local d2, _, why = ns.Deals.evaluate(rows({ { 150, 10 }, { 302, 605 }, { 303, 153 }, { 304, 49 } }), { budget = 739, gold = 739, tied = 7506, commodity = true, rate = 5000 })
    check(d2 == nil or d2.cost <= 110, "but not one that would take more than 15% of the gold in hand")
    ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 1, 1

    -- the wider scope keeps crafting materials on the fast radar (a real log: materials read every 6s, radar idle half the time)
    do
        local Sw = ns.Swarm
        local keep = { Sw.scope, Sw.units, Sw.side, Sw.sideSet, Sw.sideOwn, Sw.doneAt, ns.peerAt }
        Sw.scope = "money"; Sw:BuildUnits()
        check(#Sw.units == 1 and Sw.units[1] == Sw.unitId(7, nil) and Sw:Solo(),
            "scope 'money': crafting materials are still the one-request radar, read back to back")
        check(#Sw.side == 4 and Sw.sideOwn[Sw.unitId(0, nil)] and Sw.sideOwn[Sw.unitId(5, nil)] and Sw.sideOwn[Sw.unitId(3, nil)] and Sw.sideOwn[Sw.unitId(8, nil)],
            "reagents, consumables, gems and enhancements are side reads")
        ns.peerAt = nil; Sw.doneAt = {}
        local u = Sw:PickUnit()
        check(u and Sw.sideSet[u], "a side class that is due is read")
        for _, s in ipairs(Sw.side) do Sw.doneAt[s] = GetServerTime() end
        Sw.myDoneClock = {}
        check(Sw:PickUnit() == Sw.unitId(7, nil) and Sw:SideGap() == 30, "then it is back to materials; each side class comes round every 30s")
        Sw.scope = "mats"; Sw:BuildUnits()
        check(#Sw.units == 1 and #Sw.side == 0 and next(Sw.sideOwn) == nil and Sw:PickUnit() == Sw.unitId(7, nil),
            "scope 'materials': no side reads at all")
        Sw.scope = "all"; Sw:BuildUnits()
        print(("     whole auction house: %d side classes, each read every %ds"):format(#Sw.side, Sw:SideGap()))
        check(#Sw.units == 1 and #Sw.side >= 14 and Sw:SideGap() > 30, "scope 'everything': materials stay fast, the other classes take at most a quarter of the requests")
        Sw.scope, Sw.units, Sw.side, Sw.sideSet, Sw.sideOwn, Sw.doneAt, ns.peerAt = keep[1], keep[2], keep[3], keep[4], keep[5], keep[6], keep[7]
    end

    -- part of a deal is taken by someone else: what is left is offered at once (Wool Cloth in the real log)
    local dl = { units = 16, cost = 1600, sell = 145, kind = "FLIP", rows = rows({ { 100, 24 }, { 148, 33 }, { 154, 93 } }) }
    local left, cost = S.Remaining(dl, 16, 2080)
    check(left == 6 and cost == 600, "quote for 16 came back as 6 at 1s00c + 10 at 1s48c: 6 are still there")
    check(S.Remaining(dl, 16, 2464) == nil, "quote entirely at the next prices: nothing is left, that is a real miss")
    reset(); gold = 5000; cfg.autoConfirm = false
    local leatherWas = LIST[2319]; LIST[2319] = nil -- keep the big button on the item under test
    ITEMS[2592] = { "Wool Cloth", 33 }
    LIST[2592] = { { 100, 16 }, { 148, 33 }, { 154, 93 }, { 155, 138 }, { 160, 159 } }
    ns.Deals.cfg.requireTurnover = false
    S.priority = 2592; advance(1)
    local dv = S.verified[2592]
    check(dv and dv.units == 16, "16 Wool Cloth at 1s on offer")
    LIST[2592] = { { 100, 6 }, { 148, 33 }, { 154, 93 }, { 155, 138 }, { 160, 159 } } -- someone takes 10 of them
    btn._scripts.OnClick(btn); advance(0.4); UI:Render()
    print("     " .. label())
    dv = S.verified[2592]
    check(dv and dv.units == 6 and dv.cost == 600 and dv.leftOf == 16 and not (S.result and S.result.kind == "lost"), "someone took 10 while you clicked: the deal becomes the 6 that are left, not a miss")
    check(label():find("Wool Cloth x6 (6 of 16 still there)", 1, true), "the button says 6 of 16 are still there")
    btn._scripts.OnClick(btn); advance(0.4); btn._scripts.OnClick(btn); advance(0.6)
    check(gold == 5000 - 600 and AuctionMeshDB.flips[2592] and AuctionMeshDB.flips[2592].units == 6, "two more inputs and the 6 are bought")
    AuctionMeshDB.flips[2592] = nil; ns.Journal:Dropped(2592, nil, "test"); LIST[2592] = nil
    LIST[2319] = leatherWas

    -- the listing changed in other ways too, so no exact count fits: the quote still says about how many are left
    do
        local silk = { units = 31, cost = 3268, sell = 150, kind = "VENDOR", rows = rows({ { 100, 7 }, { 107, 35 }, { 195, 50 }, { 196, 80 }, { 197, 1967 } }) }
        check(S.Remaining(silk, 31, 5095) == nil, "the real Silk Cloth case: a quote of 50s95c for 31 fits no exact number of missing units")
        local n, most = S.Estimate(silk, 31, 5095)
        print(("     estimate: about %s left, at most %s"):format(tostring(n), tostring(most)))
        check(n == 10 and most == 1070, "but it means about 10 of the cheap ones are left (at most 10s70c): that is offered instead of MISSED")
        local n2 = S.Estimate({ units = 20, cost = 2040, sell = 150, kind = "VENDOR", instant = true, next = 186 }, 20, 3200)
        check(n2 == 6, "the radar deal from the same log (20 at 1s02c, quote 32s00c): about 6 left")
        check(S.Estimate({ units = 10, cost = 1070, guess = true, rows = rows({ { 107, 10 }, { 195, 1e6 } }) }, 10, 1500) == 5, "an estimate that misses is halved")
        check(S.Estimate(silk, 31, 31 * 196) == nil and S.Estimate({ units = 1, cost = 100, rows = rows({ { 100, 1 }, { 195, 9 } }) }, 1, 195) == nil,
            "a quote entirely at the dear price, or a single unit: nothing to retry")
        -- in the running addon: Silk Cloth, 31 offered, clicked late; the listing has moved on
        reset(); gold = 9000; cfg.autoConfirm = nil
        ITEMS[4306] = { "Silk Cloth", 150 }
        LIST[4306] = { { 100, 7 }, { 107, 35 }, { 195, 50 }, { 196, 80 }, { 197, 1967 } }
        S.priority = 4306; advance(1)
        local d0 = S.verified[4306]
        check(d0 and d0.kind == "VENDOR" and d0.units == 42, ("42 Silk Cloth under vendor price on offer (%s)"):format(tostring(d0 and d0.units)))
        LIST[4306] = { { 107, 9 }, { 186, 11 }, { 195, 50 }, { 196, 80 }, { 197, 1967 } } -- 33 were taken, and someone listed 11 at 1s86c
        S:Press(4306); advance(0.4); UI:Render()
        local d1 = S.verified[4306]
        check(d1 and d1.guess and d1.units < 42 and d1.units >= 1 and not (S.result and S.result.kind == "lost"),
            ("not MISSED: offered again for about %s units"):format(tostring(d1 and d1.units)))
        for _ = 1, 12 do -- keep pressing: each miss halves the try, until the server sells
            S:Press(4306); advance(0.5)
            if S.result and S.result.kind == "won" then break end
        end
        local got = AuctionMeshDB.flips[4306] and AuctionMeshDB.flips[4306].units or 0
        print(("     bought %d Silk Cloth; gold spent %d"):format(got, 9000 - gold))
        check(got >= 1 and got <= 9 and 9000 - gold == got * 107, "the retries end in a purchase of cheap units only, at 1s07c each, never a dear one")
        AuctionMeshDB.flips[4306] = nil; ns.Journal:Dropped(4306, nil, "test"); LIST[4306] = nil
        cfg.autoConfirm = false
    end

    -- A FLIP STRAIGHT FROM THE RADAR: no item check between the radar read and the deal
    do
        reset(); gold = 5000; cfg.autoConfirm = nil
        local leather = LIST[2319]; LIST[2319] = nil
        ITEMS[2592] = { "Wool Cloth", 33 }
        LIST[2592] = { { 166, 480 }, { 168, 4338 }, { 169, 1018 }, { 170, 1080 } }
        S.priority = 2592; advance(1) -- one full look: no deal, the listing is remembered
        check(S.verified[2592] == nil and S.lastRows[2592] and S.lastRows[2592].rows[1].price == 166, "a full look at Wool Cloth: no deal, listing remembered")
        advance(20)
        local searches = 0
        for i = 1, #sent do if sent[i] == "search2592" then searches = searches + 1 end end
        -- 5 units appear at 33c between two radar reads
        S.ownSweep[2592] = { q = 6916, p = 166, at = GetTime() - 0.7 }
        S.sweep[2592] = { q = 6916, p = 166, at = GetTime() - 0.7 }
        LIST[2592] = { { 33, 5 }, { 166, 480 }, { 168, 4338 }, { 169, 1018 }, { 170, 1080 } }
        S:OnSweep(2592, 33, 6921)
        local d = S.verified[2592]
        local after = 0
        for i = 1, #sent do if sent[i] == "search2592" then after = after + 1 end end
        print("     " .. tostring(d and ("FLIP from the radar: " .. d.units .. " for " .. d.cost .. ", sell " .. d.sell .. ", profit " .. d.profit) or "no deal"))
        check(d and d.instant and d.kind == "FLIP" and d.units == 5 and d.cost == 165 and after == searches,
            "5 Wool Cloth at 33c under a 1s66c market: shown as a deal at once, without an item check")
        S:Press(2592); advance(1.2)
        check(gold == 5000 - 165 and S.result and S.result.kind == "won", "one press: the server's price is 5 x 33c, bought")
        AuctionMeshDB.flips[2592] = nil; ns.Journal:Dropped(2592, nil, "test")
        -- not when the full listing is old, and not when no units appeared
        reset()
        -- WHICH LISTING IS GOOD ENOUGH (it was: read in the last 2 minutes, so flips straight from the radar stopped 2 minutes after you armed)
        local lr = S.lastRows[2592]
        local function try(price, qty)
            S.verified[2592] = nil
            S.ownSweep[2592] = { q = 6916, p = 166, at = GetTime() - 0.7 }
            local ok = S:InstantFlip(2592, price or 33, qty or 6921, S.ownSweep[2592])
            S.verified[2592], S.dealSeen, G.holdUntil = nil, {}, nil
            return ok
        end
        lr.at, lr.broken, lr.gone = GetTime() - 300, nil, 0
        check(try() == true, "a listing read 5 minutes ago, watched by the radar without a gap since: still good for a flip straight from the radar")
        lr.broken = true
        check(try() == false, "the radar lost sight of the item since the listing was read: normal check instead")
        lr.at, lr.broken = GetTime() - 100, true
        check(try() == true, "(a listing under 2 minutes old is used as before, watched or not)")
        lr.at, lr.broken = GetTime() - 1000, nil
        check(try() == false, "a listing read more than 15 minutes ago is never used")
        lr.at, lr.gone = GetTime() - 300, 6910 -- the market it showed held 6916 units; 6910 have left the item since
        check(try() == false, "an older listing whose market has since been bought away (units the radar saw leave): normal check instead")
        lr.gone = 100
        check(try() == true, "a few units gone from a deep market: still good")
        do  -- the bottom of the market is the radar's, never the old listing's
            lr.at, lr.gone, lr.broken = GetTime() - 30, 0, nil
            S.verified[2592] = nil
            S.ownSweep[2592] = { q = 6916, p = 120, at = GetTime() - 0.7 } -- someone listed at 1s20c after the listing was read
            S:InstantFlip(2592, 33, 6921, S.ownSweep[2592])
            local d2 = S.verified[2592]
            print("     " .. tostring(d2 and ("bottom now 1s20c: " .. d2.units .. " units, sell " .. d2.sell .. " each, profit " .. d2.profit) or "no deal"))
            check(d2 and d2.units == 5 and d2.sell == 119 and d2.more, "a cheaper listing that appeared since (the radar's lowest price was 1s20c): only the new units, resale planned under it (1s19c, not the old 1s65c), and the item is checked again after the purchase")
            S.verified[2592], S.dealSeen, G.holdUntil = nil, {}, nil
            S.ownSweep[2592] = { q = 6916, p = 168, at = GetTime() - 0.7 } -- the 480 at 1s66c have sold: the bottom is 1s68c now
            S:InstantFlip(2592, 33, 6921, S.ownSweep[2592])
            d2 = S.verified[2592]
            print("     " .. tostring(d2 and ("bottom now 1s68c: " .. d2.units .. " units, sell " .. d2.sell .. " each") or ("no deal; rows " .. S.RowsText(S.lastRows[2592].rows))))
            check(d2 and d2.units == 5 and d2.sell == 159, "rows of the old listing that have sold out are not counted against the deal (the bottom is 1s68c now; the resale stays at the price recent sales allow)")
            S.verified[2592], S.dealSeen, G.holdUntil = nil, {}, nil
        end
        lr.at, lr.gone, lr.broken = GetTime(), 0, nil
        S.ownSweep[2592] = { q = 6916, p = 166, at = GetTime() - 0.7 }
        check(S:InstantFlip(2592, 33, 6916, S.ownSweep[2592]) == false, "no new units since the last radar read: normal check")
        check(S:InstantFlip(2592, 150, 6921, S.ownSweep[2592]) == false, "a price that is not a deal is not shown")
        LIST[2592] = nil; LIST[2319] = leather; cfg.autoConfirm = false
    end

    -- THE SNAPSHOT: one button on every tab, one short block to paste
    do
        reset(); gold = 3288
        local Se = ns.Seller
        AuctionMeshDB.outcomes = {}
        -- a win with the wheel 0.3s after the deal appeared, then a late click that missed
        S.dealSeen[4306] = GetTime() - 0.3; S.inputAt, S.inputVia = GetTime(), "wheel"
        S.verified[4306] = { key = 4306, units = 16, cost = 1600, sell = 150, profit = 800, deposit = 0, buys = {}, counts = {}, from = "me", kind = "VENDOR", commodity = true, at = GetTime(), rows = rows({ { 100, 16 }, { 196, 31 } }) }
        ITEMS[4306] = { "Silk Cloth", 150 }
        LIST[4306] = { { 100, 16 }, { 196, 31 }, { 197, 1967 } }
        cfg.autoConfirm = nil
        S:Press(4306); advance(1.2)
        S.dealSeen[4306] = GetTime() - 6.4; S.inputAt, S.inputVia = nil, "click"
        S.verified[4306] = { key = 4306, units = 2, cost = 200, sell = 150, profit = 100, deposit = 0, buys = {}, counts = {}, from = "me", kind = "VENDOR", commodity = true, at = GetTime(), rows = rows({ { 100, 2 }, { 196, 31 } }) }
        S:Press(4306); advance(1.2)
        S.verified[4306] = nil
        S.ownSoldQty = { [4304] = 5 }
        S.ownSoldPay = { { amount = 510, due = GetTime() + 236, key = 4304 }, { amount = 2272, due = GetTime() + 797, key = 4304 } }
        ITEMS[4304] = { "Thick Leather", 75 }
        AuctionMeshDB.mailSeen = { at = GetServerTime() - 720, mails = 3, gold = 0, pending = 2, items = { [2589] = 14 } }
        local snap = AuctionMeshFrame.snap
        check(snap and snap._text == "Snapshot", "a Snapshot button sits on the panel header, on every tab")
        snap._scripts.OnClick(snap)
        local text = AuctionMeshLogFrame.edit._text
        for line in text:gmatch("[^\n]+") do print("     | " .. line) end
        local function has(s) return text:find(s, 1, true) ~= nil end
        check(AuctionMeshLogFrame:IsShown() and has("=== AUCTIONMESH SNAPSHOT v1 ===") and has("=== END OF SNAPSHOT ==="), "it opens one block of text to copy")
        check(has("gold in hand: 16s 88c") and has("sold, gold on its way: 27s 82c  (next in 4 min)") and has("Thick Leather: 5s 10c in 4 min") and has("Thick Leather: 22s 72c in 13 min"),
            "money: gold in hand, and each sold auction with when its gold arrives")
        check(has("MAILBOX (as read 12 min ago): 3 mail(s), sale gold 0c, 2 sale(s) still to be paid") and has("items in it: 14 x Linen Cloth"), "the mailbox as it was last read, and how long ago")
        check(has("smallest profit ") and has("one-click buy: works") and has("buy with: Mouse wheel") and not has("sharing"), "the settings, including how you buy and whether one-click buying works; nothing about sharing")
        check(has("| GOT | 0.3s | wheel | GOT IT  16 x Silk Cloth") and has("| MISSED | 6.4s | click | MISSED  Silk Cloth"),
            "the last snipes: result, how long after the deal the input came, and whether it was the wheel or a click")
        check(has("Silk Cloth x16 at 1s 0c each") and has("LAST PURCHASES"), "and the last purchases")
        check(has("| GOT IT  16 x Silk Cloth for 16s00c. Worth + 8s00c when sold. | ") and text:find("| %d+%.%d%ds: %d+%.%d%d, %d+%.%d%d, %d+%.%d%d\n"),
            "each with its timings: the deal showing to its end, the input, the lock, the price answer")
        check(#text < 6200, ("short enough to paste in one go (%d characters)"):format(#text))
        AuctionMeshLogFrame:Hide()
        AuctionMeshDB.flips[4306] = nil; ns.Journal:Dropped(4306, nil, "test"); LIST[4306] = nil
        S.ownSoldQty, S.ownSoldPay = {}, {}; AuctionMeshDB.mailSeen = nil; cfg.autoConfirm = false
    end

    -- IMPORT: paste what Claude sent, Apply, and the settings are set
    do
        reset()
        local D = ns.Deals.cfg
        local keep = { cfg.minProfit, cfg.margin, cfg.scope, cfg.focusMode, cfg.focusItems, cfg.maxTied, cfg.maxSpend, cfg.smallFlip, D.maxSpend, D.maxTied, D.smallFlip, cfg.flips }
        ITEMS[4306] = { "Silk Cloth", 150 }; ITEMS[2592] = { "Wool Cloth", 33 }; ITEMS[2287] = { "Haunch of Meat", 6 }
        cfg.focusItems, cfg.focusMode = {}, "off"
        local code0 = ns.Do.SettingsCode()
        print("     " .. code0)
        check(code0:find("^AMS1:min=%d+;margin=%d+;flips=1;scope=%a+;focus=off;tied=%d+;spend=%d+;small=%d+;every=60;buy=wheel;tune=1"), "the current settings as one code")
        UI.tab = "HISTORY"; UI:Render()
        local sp = AuctionMeshFrame.setup
        -- the whole message is pasted, not just the code
        sp.code:SetText("Here is the tweak. Paste this:\n\n`AMS1:min=75;margin=22;scope=money;focus=prime;watch=+2592,+4306;itemmin=4306:300;ignore=2287;tied=70;spend=40;small=20;bogus=1`.\n\nThen roll the wheel.")
        sp.apply._scripts.OnClick(sp.apply); UI:Render()
        print("     " .. strip(UI.notice and UI.notice.text or "?"))
        check(sp.code._text == "" and cfg.minProfit == 75 and D.minProfit == 75 and cfg.margin == 22 and cfg.scope == "money" and cfg.focusMode == "prime",
            "the code is found in the pasted text and applied: smallest profit, margin, what the radar reads, laser focus")
        check(cfg.focusItems[1] == 2592 and cfg.focusItems[2] == 4306, "items are added to your own watch list")
        check(cfg.maxTied == 70 and math.abs(D.maxTied - 0.7) < 1e-9 and cfg.maxSpend == 40 and math.abs(D.maxSpend - 0.4) < 1e-9 and cfg.smallFlip == 20 and math.abs(D.smallFlip - 0.2) < 1e-9,
            "and the capital limits")
        local n = strip(UI.notice.text)
        check(n:find("^Imported %d+ changes: smallest profit ") and n:find("watch list: added Wool Cloth", 1, true) and n:find("Silk Cloth: smallest profit 3s 0c", 1, true)
            and n:find("ignored from now on: Haunch of Meat", 1, true) and n:find("Not understood and left alone: bogus", 1, true),
            "Apply says exactly what changed, and what it did not understand")
        -- a smallest profit for one item only
        check(S:CfgFor(4306).minProfit == 300 and S:CfgFor(2770).minProfit == 75 and S:CfgFor(4306).margin == D.margin, "Silk Cloth has its own smallest profit; everything else keeps the general one")
        local o = { budget = 5000, gold = 5000, commodity = true, vendor = 150, noFlip = true }
        local d1, _, why = ns.Deals.evaluate(rows({ { 100, 4 }, { 196, 500 }, { 197, 900 } }), o, S:CfgFor(4306))
        local d2 = ns.Deals.evaluate(rows({ { 100, 4 }, { 196, 500 }, { 197, 900 } }), o, S:CfgFor(2770))
        check(d1 == nil and tostring(why):find("under your $300 minimum", 1, true) and d2 and d2.profit == 200, "a 2s Silk Cloth deal is now too small, while the same deal on another item is shown")
        -- an ignored item is never shown
        check(S:Ignored(2287) and not S:Ignored(4306), "Haunch of Meat is on the ignore list")
        S.ownSweep[2287] = { q = 100, p = 9, at = GetTime() - 0.7 }
        S:OnSweep(2287, 2, 150)
        check(S.verified[2287] == nil and #S.triggers == 0, "its deals are not shown and not even checked")
        -- prime focus also watches your own list
        local set, list, text = S:FocusSet()
        print("     " .. tostring(text))
        check(set and set[2592] and set[4306] and tostring(text):find("your own watch list", 1, true), "with laser focus on prime items, your own watch list is watched as well")
        -- the snapshot carries the code
        local snapText = ns.Do.Snapshot(); AuctionMeshLogFrame:Hide()
        check(snapText:find("paste it into the box on the Setup tab): AMS1:min=75;margin=22;", 1, true) and snapText:find("itemmin=4306:300;ignore=2287", 1, true)
            and snapText:find("own watch list: Wool Cloth(2592), Silk Cloth(4306)", 1, true), "the Snapshot holds the settings code, so the next suggestion starts from what is really set")
        -- the same code again changes nothing
        sp.code:SetText(ns.Do.SettingsCode()); sp.apply._scripts.OnClick(sp.apply)
        check(strip(UI.notice.text) == "Settings code read: everything in it is already set that way.", "applying the code you already have changes nothing, and says so")
        -- removing things, and text with no code in it
        ns.Do.Import("AMS1:watch=-2592;ignore=-2287;itemmin=4306:0")
        check(#cfg.focusItems == 1 and cfg.focusItems[1] == 4306 and not S:Ignored(2287) and S:CfgFor(4306) == D, "a code can also remove: off the watch list, off the ignore list, per-item minimum cleared")
        check(ns.Do.Import("nothing useful here") == false and strip(UI.notice.text):find("^No code found in that text"), "text with no code in it changes nothing")
        ns.Do.Import("AMS1:every=90")
        check(cfg.focusEvery == 90 and S.FocusEvery() == 90 and strip(UI.notice.text):find("focus items are re-read every 60s > 90s", 1, true), "how often focus items are re-read is a setting too")
        ns.Do.Import("AMS1:every=5"); check(S.FocusEvery() == 20, "never more often than every 20 seconds")
        cfg.focusEvery = nil
        cfg.minProfit, cfg.margin, cfg.scope, cfg.focusMode, cfg.focusItems, cfg.maxTied, cfg.maxSpend, cfg.smallFlip = keep[1], keep[2], keep[3], keep[4], keep[5], keep[6], keep[7], keep[8]
        D.maxSpend, D.maxTied, D.smallFlip, D.minProfit, D.margin = keep[9], keep[10], keep[11], keep[1], keep[2] / 100
        cfg.itemMin, cfg.ignore = nil, nil
        ns.Swarm.scope = cfg.scope; ns.Swarm:BuildUnits(); ns.Scout:Changed()
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
    end

    -- AUTO-ADJUST: settings that follow what really happens
    do
        reset()
        local A, D = ns.Auto, ns.Deals.cfg
        local keepMin, keepTune = cfg.minProfit, cfg.tune
        local function review(shown, crowd) A.win = { at = GetTime(), shown = shown, crowd = crowd, worked = 0 }; A:Worked(601) end
        A.cfg.manyHidden, A.cfg.crowded = 3, 3
        cfg.tune = true; A.d.log, A.d.manual = {}, {}
        -- nothing shown, deals hidden by the minimum: it comes down, in steps, never under 20c
        UI:SetMinProfit(200); A.d.manual = {}
        S.underMin = { n = 6, best = 150, at = GetTime() }
        review(0)
        print("     " .. tostring(A.d.log[#A.d.log] and A.d.log[#A.d.log].m))
        check(cfg.minProfit == 150 and D.minProfit == 150 and A.d.log[#A.d.log].m == "smallest profit 2s 0c > 1s 50c: 6 deals hidden by it in the last 10 minutes (best hidden: 1s 50c), and no bigger deal had to wait behind a purchase",
            "6 deals hidden by a 2s minimum and nothing had to wait: it is lowered to 1s 50c, and the reason is written down")
        S.underMin = nil; review(0)
        check(cfg.minProfit == 150, "nothing hidden: nothing changes")
        -- A BUSY MARKET DOES NOT RAISE IT ANY MORE (it went up a quarter every 10 minutes that 15 deals were shown, and a session offered less and less)
        gold = 20000; review(69)
        check(cfg.minProfit == 150, "69 deals shown in 10 minutes, none of them kept waiting: the minimum stays where it is")
        S.underMin = { n = 5, best = 120, at = GetTime() }; review(69)
        check(cfg.minProfit == 112, ("and with deals hidden by it, it comes DOWN in a busy market too (%d)"):format(cfg.minProfit))
        -- what does raise it: bigger deals that had to wait behind a smaller purchase
        S.underMin = { n = 5, best = 100, at = GetTime() }; review(40, 2)
        check(cfg.minProfit == 112, "two bigger deals had to wait: not enough to move it either way")
        review(40, 4)
        print("     " .. tostring(A.d.log[#A.d.log] and A.d.log[#A.d.log].m))
        check(cfg.minProfit == 140 and A.d.log[#A.d.log].m == "smallest profit 1s 12c > 1s 40c: 4 bigger deals had to wait behind a smaller purchase in the last 10 minutes",
            "four did: raised by a quarter, never over 2% of what you own, with the reason written down")
        -- the count itself: a deal that appears while a smaller one is being bought
        A.win = { at = GetTime(), shown = 0, worked = 0 }
        S.buying = { key = 111, phase = "quote", deal = { profit = 100 } }
        A:Shown(222, { profit = 500 }); A:Shown(333, { profit = 50 }); A:Shown(111, { profit = 900 })
        S.buying = nil
        A:Shown(444, { profit = 900 })
        check(A.win.shown == 4 and A.win.crowd == 1, "counted: a deal that appears while a purchase of a SMALLER one is in progress (not a smaller one, not the same item, not with nothing being bought)")
        A.win = { at = GetTime(), shown = 0, worked = 0 }
        -- at the update, the old rule's raises are taken back (they are in the log, with their reason)
        do
            local logWas = A.d.log
            A.d.log = { { t = 1, m = "smallest profit 80c > 1s 1c: 3 deals shown and 4 hidden by it in the last 10 minutes (best hidden: 60c)" },
                        { t = 2, m = "smallest profit 81c > 1s 1c: 69 deals shown in the last 10 minutes, more than can be acted on" },
                        { t = 3, m = "smallest profit 1s 1c > 1s 26c: 70 deals shown in the last 10 minutes, more than can be acted on" } }
            check(A:OldRaises(200) == nil, "the minimum is not where the last raise left it (you changed it since): left alone")
            check(A:OldRaises(126) == 81, "two raises by the old rule, 81c > 1s01c > 1s26c: the minimum goes back to 81c")
            check(A.d.log[#A.d.log].m == "smallest profit 1s 26c > 81c: raised by the old rule (many deals shown), taken back", "and that is written down too")
            A.d.log = { { t = 1, m = "smallest profit 2s 0c > 1s 50c: 6 deals hidden by it in the last 10 minutes (best hidden: 1s 50c), and no bigger deal had to wait behind a purchase" } }
            check(A:OldRaises(150) == nil, "a change by the new rule is not touched")
            A.d.log = logWas
        end
        UI:SetMinProfit(150); A.d.manual = {}
        gold = 900
        -- a setting you change yourself is left alone for 30 minutes
        UI:SetMinProfit(300)
        S.underMin = { n = 9, best = 250, at = GetTime() }
        review(0)
        check(cfg.minProfit == 300, "you set it yourself: auto-adjust leaves it alone")
        A.d.manual.min = GetServerTime() - 1801; S.underMin = { n = 9, best = 250, at = GetTime() }; review(0)
        check(cfg.minProfit == 225, "half an hour later it may adjust again")
        -- switched off: nothing moves
        cfg.tune = false; S.underMin = { n = 9, best = 200, at = GetTime() }; review(0)
        check(cfg.minProfit == 225, "with the switch off nothing changes by itself")
        cfg.tune = true
        -- the radar's quiet time follows how fast your inputs come
        AuctionMeshDB.outcomes = {}
        check(A:Hold(false, 6) == 6, "no inputs measured yet: the radar stays quiet 6 seconds after a deal appears")
        for _, r in ipairs({ 0.9, 1.4, 1.0, 6.4, 1.1 }) do table.insert(AuctionMeshDB.outcomes, { t = 0, k = "lost", r = r }) end
        check(math.abs(A:Hold(false, 6) - 2.1) < 1e-9, "your inputs come about 1.1s after a deal: quiet time 2.1 seconds instead of 6")
        check(A:Hold(true, 6) == 1, "while the wheel is rolling: 1 second")
        -- shown on the Setup tab and in the Snapshot
        UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
        local sp = AuctionMeshFrame.setup
        print("     " .. strip(sp.rows[1].label._text) .. ": " .. strip(sp.rows[1].value._text))
        check(strip(sp.rows[1].label._text) == "Auto-adjust, last change" and strip(sp.rows[1].value._text):find("^smallest profit 3s 0c > 2s 25c"), "the Setup tab shows the last change auto-adjust made")
        local snapText = ns.Do.Snapshot(); AuctionMeshLogFrame:Hide()
        check(snapText:find("auto-adjust (on): last changes, newest first", 1, true) and snapText:find("smallest profit 2s 0c > 1s 50c", 1, true), "and the Snapshot lists them")
        A.d.log, A.d.manual = {}, {}
        AuctionMeshDB.outcomes = {}
        UI:SetMinProfit(keepMin); A.d.manual = {}; cfg.tune = keepTune
        A.cfg.manyHidden, A.cfg.crowded = 1e9, 1e9
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
    end

    -- A FAILED PURCHASE IS NOT A PACE PROBLEM (two 5-second radar stops and a slower radar in a real log)
    do
        reset(); gold = 5000; cfg.autoConfirm = nil
        local T, G2 = ns.Tuner, ns.Gate
        ITEMS[2838] = { "Heavy Stone", 15 }
        LIST[2838] = { { 203, 3 }, { 300, 75 }, { 320, 44 }, { 325, 149 }, { 327, 44 } }
        S.verified[2838] = { key = 2838, units = 3, cost = 609, sell = 294, profit = 228, deposit = 0, buys = {}, counts = {}, from = "me", kind = "FLIP", commodity = true, at = GetTime(),
                             rows = rows({ { 203, 3 }, { 300, 75 } }) }
        local realConfirm = C_AuctionHouse.ConfirmCommoditiesPurchase
        C_AuctionHouse.ConfirmCommoditiesPurchase = function()
            C_Timer.After(0.2, function() fire("COMMODITY_PURCHASE_FAILED") end)
            C_Timer.After(0.45, function() fire("AUCTION_HOUSE_SHOW_ERROR", 10) end) -- the game's "internal auction error" for it
        end
        local gapWas, errWas = T.d.gap.i, G2.errors
        S:Press(2838); advance(1.5)
        C_AuctionHouse.ConfirmCommoditiesPurchase = realConfirm
        check(S.result and S.result.kind == "lost", "the server refuses the purchase: reported as MISSED")
        check(G2.errors == errWas and T.d.gap.i == gapWas and (G2.nextAt or 0) < GetTime() + 1,
            "the error message that follows is not counted against the pace: no 5-second stop, no longer pause between requests")
        -- an error with no purchase near it still counts
        advance(5)
        fire("AUCTION_HOUSE_SHOW_ERROR", 10)
        check(G2.errors > errWas, "an error that follows no purchase is still treated as the server pushing back")
        G2.nextAt, G2.penaltyUntil, G2.errors = 0, 0, errWas
        T.d.gap.i = gapWas
        LIST[2838] = nil; S.verified[2838] = nil; cfg.autoConfirm = false
    end

    -- THE HEADER BAR FITS THE SPACE IT HAS
    do
        local f = AuctionMeshFrame
        local realR, realL = rawget(f.tabHist, "GetRight"), rawget(f.snap, "GetLeft")
        rawset(f.tabHist, "GetRight", function() return 300 end)
        rawset(f.snap, "GetLeft", function() return 640 end)
        UI:FitHeader()
        check(UI.barWidth == 230 and f.bar._shown ~= false, "wide panel: the engine bar is its full width, between the tabs and the Snapshot button")
        rawset(f.snap, "GetLeft", function() return 440 end)
        UI:FitHeader()
        check(UI.barWidth == 116, "narrower panel: the bar and its text shrink to the room there is (116)")
        rawset(f.snap, "GetLeft", function() return 350 end)
        UI:FitHeader()
        check(UI.barWidth < 60 and f.bar._shown == false and f.barText._shown == false, "no room at all: the bar is hidden instead of being drawn over the buttons")
        rawset(f.tabHist, "GetRight", realR); rawset(f.snap, "GetLeft", realL)
        UI:FitHeader()
    end

    -- STAKE-OUT: one item watched by asking its price on every wheel notch
    do
        reset(); gold = 5000; cfg.autoConfirm = nil
        local leather = LIST[2319]; LIST[2319] = nil
        local heavy = LIST[4234]; LIST[4234] = nil -- (a deal left over from an earlier section: nothing else to buy here)
        ITEMS[2838] = { "Heavy Stone", 15 }
        LIST[2838] = { { 300, 75 }, { 320, 44 }, { 325, 149 }, { 327, 44 }, { 329, 25 } }
        ns.Deals.cfg.requireTurnover = false
        UI.tab = "BUY"; UI.sel = 2838; UI:ToggleDrawer(true)
        local dbtn = AuctionMeshDrawer.stake
        check(dbtn:IsShown() and dbtn._text == "Stake out this item", "the drawer of an item has a Stake out button")
        dbtn._scripts.OnClick(dbtn)
        check(S:StakeKey() == 2838 and cfg.stake == 2838 and dbtn._text == "Stop the stake-out", "one click sets the stake-out on Heavy Stone")
        UI.sel = nil; UI:ToggleDrawer(false)
        advance(2); S.verified = {} -- its listing is read first
        local max = S:StakeTerms()
        print(("     Heavy Stone, market 3s00c: the stake-out buys at %s or less, up to %s at a time"):format(tostring(max), tostring(S.stake.cap)))
        check(max and max >= 150 and max < 260 and S.stake.kind == "FLIP", "the buying price comes from the normal deal rules and the item's own listing")
        UI:Render()
        check(label():find("^STAKE%-OUT READY    Heavy Stone: buys at ") and strip(btn.hint._text):find("^Stake%-out: put the mouse here and keep rolling the wheel"), "the snipe box shows the stake-out and what it waits for")
        -- rolling with nothing cheap: every notch that the auction house allows asks the price; nothing is bought
        local wheel = btn._scripts.OnMouseWheel
        local radar0, starts0 = ns.Swarm.stats.queries, 0
        for i = 1, #sent do if sent[i] == "start2838" then starts0 = starts0 + 1 end end
        for _ = 1, 30 do wheel(btn, 1); advance(0.1) end
        local starts = 0
        for i = 1, #sent do if sent[i] == "start2838" then starts = starts + 1 end end
        UI:Render()
        print("     " .. label())
        check(S.stake.asked >= 3 and gold == 5000 and S.stake.lastPrice == 300, ("3 seconds of rolling: the price was asked %d times (3s00c each time), nothing bought"):format(S.stake.asked))
        check(ns.Swarm.stats.queries == radar0, "the radar sends nothing while the stake-out runs")
        check(label():find("^STAKE%-OUT    Heavy Stone: buys at ") and label():find("last price 3s00c", 1, true), "the box shows the last price the server gave")
        -- three cheap units are listed
        LIST[2838] = { { 203, 3 }, { 300, 75 }, { 320, 44 }, { 325, 149 }, { 327, 44 }, { 329, 25 } }
        local t0, first = GetTime(), nil
        for _ = 1, 60 do
            wheel(btn, 1); advance(0.1)
            if not first and gold < 5000 then first = GetTime() - t0 end
        end
        print(("     3 units listed at 2s03c: first one bought %.1fs later; %d bought in all for %d"):format(first or -1, S.stake.bought, 5000 - gold))
        check(first and first <= 1.0, "the first cheap unit is bought within a second of being listed, with no radar read and no item check")
        check(S.stake.bought == 3 and gold == 5000 - 609, "all three cheap units are bought (one, then two at the same price), and not one dear unit")
        check(AuctionMeshDB.flips[2838] and AuctionMeshDB.flips[2838].units == 3, "they are in your holdings like any other purchase")
        check(S.stake.q == 1 and S.stake.cheap == nil, "after that the price is 3s00c again: back to asking for one")
        -- the settings code carries it; a code can end it
        check(ns.Do.SettingsCode():find(";stake=2838", 1, true), "the settings code holds the stake-out")
        ns.Do.Import("AMS1:stake=0")
        check(S:StakeKey() == nil and S.stake == nil, "a code (or the drawer button) ends it")
        radar0 = ns.Swarm.stats.queries
        for _ = 1, 20 do wheel(btn, 1); advance(0.1) end
        check(ns.Swarm.stats.queries > radar0, "with no stake-out, rolling is the normal snipe mode again: the radar reads")
        AuctionMeshDB.flips[2838] = nil; ns.Journal:Dropped(2838, nil, "test"); LIST[2838] = nil; LIST[2319] = leather; LIST[4234] = heavy
        UI.wheelSeen = nil; cfg.autoConfirm = false
        UI:Render()
    end

    -- a price that falls under vendor price while the item's total goes down: acted on at once, asking for four
    do
        reset(); gold = 1100
        ITEMS[4306] = { "Silk Cloth", 150 }
        S.ownSweep[4306] = { q = 11556, p = 190, at = GetTime() - 1.1 }
        S:OnSweep(4306, 99, 11540) -- 16 appeared at 99c, but 32 others were bought or cancelled meanwhile
        local d = S.verified[4306]
        print("     " .. tostring(d and d.rowsText))
        check(d and d.instant and d.kind == "VENDOR" and d.units == 4 and d.cost == 396 and #S.triggers == 0,
            "Silk Cloth falls to 99c while its total drops: shown at once for 4 units, with no item check first (it used to wait for one)")
        S.verified[4306] = nil
        -- too small to be worth it on a guess: the normal check finds the exact count instead
        ITEMS[6661] = { "Flax Thread", 13 }
        local wasMin = ns.Deals.cfg.minProfit
        ns.Deals.cfg.minProfit = 120
        S.ownSweep[6661] = { q = 9000, p = 20, at = GetTime() - 1.1 }
        S:OnSweep(6661, 2, 8990)
        check(S.verified[6661] == nil and S.triggers[6661] ~= nil, "4 units at 2c against a 13c vendor price would not clear the smallest profit: that one gets the normal check, which counts the units")
        ns.Deals.cfg.minProfit = wasMin
        S.triggers = {}
    end

    -- a stake-out judges the smallest profit on a lot, not on a single unit
    do
        reset(); gold = 5000
        local wasMin = ns.Deals.cfg.minProfit
        ns.Deals.cfg.minProfit = 120
        ITEMS[4306] = { "Silk Cloth", 150 }
        S.lastRows[4306] = { rows = rows({ { 190, 56 }, { 198, 1181 }, { 199, 2166 }, { 200, 7139 }, { 201, 812 } }), at = GetTime() }
        S:SetStake(4306); S.priority = nil
        local max = S:StakeTerms()
        print(("     Silk Cloth (vendor pays 1s50c, smallest profit 1s20c): the stake-out buys at %s or less, %s at a time"):format(tostring(max), tostring(S.stake and S.stake.cap)))
        check(max and max >= 99 and max < 150, "with a 1s20c smallest profit, a Silk Cloth stake-out still buys at 99c: the profit is judged on eight units, not one")
        S:SetStake(nil)
        ns.Deals.cfg.minProfit = wasMin
    end

    -- side categories with nothing in them are read rarely
    do
        local Sw = ns.Swarm
        local keep = { Sw.scope, Sw.units, Sw.side, Sw.sideSet, Sw.sideOwn, Sw.doneAt, Sw.sideItems, ns.peerAt }
        Sw.scope = "money"; Sw:BuildUnits(); ns.peerAt = nil
        local now = GetServerTime()
        local gems, food = Sw.unitId(3, nil), Sw.unitId(0, nil)
        Sw.doneAt = {}
        for _, s in ipairs(Sw.side) do Sw.doneAt[s] = now - 45 end -- all read 45 seconds ago
        Sw.sideItems = { [gems] = 0, [Sw.unitId(5, nil)] = 1, [Sw.unitId(8, nil)] = 0, [food] = 727 }
        check(Sw:PickUnit() == food, "45 seconds on: the category with 727 items is due; the three empty ones are not")
        Sw.doneAt[food] = now
        Sw.myDoneClock = {}
        check(Sw:PickUnit() == Sw.unitId(7, nil), "the empty ones do not take a request every 30 seconds any more")
        Sw.doneAt[gems] = now - 601
        check(Sw:PickUnit() == gems, "they are looked at again after 10 minutes, in case something was listed")
        Sw.scope, Sw.units, Sw.side, Sw.sideSet, Sw.sideOwn, Sw.doneAt, Sw.sideItems, ns.peerAt = keep[1], keep[2], keep[3], keep[4], keep[5], keep[6], keep[7], keep[8]
    end

    -- five misses in a row: the item is left alone for 3 minutes
    reset(); gold = 900
    ITEMS[4306] = { "Silk Cloth", 150 }
    for i = 1, 5 do
        S.cool = {}
        S.buying = { key = 4306, units = 3, max = 300, phase = "quote", at = GetTime(), deal = { units = 3, cost = 300, sell = 150, kind = "VENDOR", instant = true, next = 188 } }
        S:OnPriceQuote(188, 564)
        if i == 3 then check(not S:Muted(4306), "three misses in a row no longer mute an item") end
    end
    print("     " .. strip(S.result.text))
    check(S:Muted(4306) and S.result.text:find("Fifth miss in a row", 1, true) and S.muted[4306] - GetTime() <= 180,
        "Silk Cloth missed five times running: muted for 3 minutes, and the panel says why")
    S.ownSweep = { [4306] = { q = 100, p = 190, at = GetTime() - 0.7 } }
    S:OnSweep(4306, 100, 103)
    check(S.verified[4306] == nil, "while muted, its deals are not shown")
    S.muted = {}

    -- side reads: the other categories of the chosen radar setting, nothing else
    Sw.scope = "mats"; Sw:BuildUnits()
    check(#Sw.units == 1 and #Sw.side == 0, "crafting materials only: one main read and no side reads at all")
    Sw.scope = "money"; Sw:BuildUnits()
    check(#Sw.units == 1 and #Sw.side == 4, "all money-makers: materials stay the main radar; consumables, gems, reagents and enhancements are side reads")
    Sw.unitReq = { [Sw.units[1]] = 1 }; Sw.doneAt = {}; Sw.sideItems = {}
    Sw.myDoneClock = { [Sw.units[1]] = Sw.clock() }
    local u1 = Sw:PickUnit()
    check(u1 ~= nil and Sw.sideSet[u1], "a side category that has not been read is due")
    do  -- a side class is upkeep: it waits for the upkeep turn, and is never read while you are armed
        local was = S.upkeep.every
        S.upkeep.every = 8; Sw.active = true; Sw.idle = false; ns.radarSince = 3
        check(Sw:PickUnit() == Sw.units[1], "3 radar reads since the last other request: the main radar goes, the side class waits (it used to go ahead of every due main read)")
        ns.radarSince = 8
        u1 = Sw:PickUnit()
        check(u1 ~= nil and Sw.sideSet[u1], "8 radar reads in a row: now the side class has its turn")
        UI.wheelSeen = GetTime()
        check(Sw:PickUnit() == Sw.units[1], "armed: no side class, whatever the count")
        -- one that was picked before you armed gives its turn back
        Sw.current = { unit = Sw.side[1], phase = "claimed", at = Sw.clock() }
        local q0 = #sent
        Sw:Step()
        -- (the upkeep turn is free and you are armed: a listing a flip needs may go first; then the main radar, never the side class)
        local guard = 0
        while not (Sw.current and Sw.current.phase == "query") and guard < 20 do advance(0.3); Sw:Step(); guard = guard + 1 end
        local browses = 0
        for i = q0 + 1, #sent do if sent[i] == "browse" then browses = browses + 1 end end
        check(Sw.current and Sw.current.unit == Sw.units[1] and browses == 1, "a side class picked just before you armed is dropped: the read that goes out is the main radar's")
        UI.wheelSeen = nil; S.upkeep.every = was; Sw.current = nil; advance(0.5)
    end
    for _, su in ipairs(Sw.side) do Sw.doneAt[su] = Sw.serverTime() end
    check(Sw:PickUnit() == Sw.units[1], "all side categories read in the last 30 seconds: back to the main radar only")
    Sw.scope = "mats"; Sw:BuildUnits()
    Sw.unitReq = { [Sw.units[1]] = 1 }
    Sw.myDoneClock = { [Sw.units[1]] = Sw.clock() }
    check(Sw:PickUnit() == Sw.units[1], "the main radar is due again at once")
    cfg.autoConfirm = false
end

print("picks: which item, if any, is worth a stake-out")
do
    local P, Sc, cfg = ns.Picks, ns.Scout, AuctionMeshDB.cfg
    local dealsWas, logWas = Sc.d.deals, AuctionMeshDB.stakeLog
    local now = GetServerTime()
    S.verified, S.buying, S.result, UI.wheelSeen, UI.notice = {}, nil, nil, nil, nil
    S:SetStake(nil); AuctionMeshDB.stakeLog = nil
    ITEMS[4306] = { "Silk Cloth", 150 }; ITEMS[2592] = { "Wool Cloth", 33 }; ITEMS[2589] = { "Linen Cloth", 13 }
    local function deal(key, minsAgo, profit, outcome, extra)
        local e = { t = now - minsAgo * 60, k = key, kind = "FLIP", u = 8, c = 800, s = 198, p = profit, o = outcome, f = "radar" }
        for a, b in pairs(extra or {}) do e[a] = b end
        return e
    end
    -- Silk Cloth: 6 deals. 1 bought, 4 you went for and lost (3s each), 1 gone after 2s.
    -- Wool Cloth: 3 deals. 2 bought, 1 gone. Linen: 1 bought. One Silk deal from two days ago.
    Sc.d.deals = {
        deal(4306, 3000, 300, "failed"),
        deal(4306, 300, 400, "bought", { bu = 8, bc = 800 }), deal(4306, 280, 300, "failed"), deal(4306, 200, 300, "failed"),
        deal(4306, 150, 300, "failed"), deal(4306, 90, 300, "failed"), deal(4306, 40, 250, "gone", { life = 2 }),
        deal(2592, 270, 200, "bought", { bu = 8, bc = 800 }), deal(2592, 100, 200, "bought", { bu = 8, bc = 800 }), deal(2592, 30, 180, "gone", { life = 9 }),
        deal(2589, 20, 100, "bought", { bu = 8, bc = 800 }),
    }
    local nSent = #sent
    P.result = nil
    local r = P:Compute()
    local silk, wool = r.list[1], r.list[2]
    check(r.all == 10 and r.gotAll == 900 and r.hours == 5 and r.enough, "counts the last 24 hours only: 10 deals, 9s of profit caught (the deal from two days ago is left out)")
    check(silk and silk.key == 4306 and silk.n == 6 and silk.got == 1 and silk.miss == 4 and silk.missP == 1200 and silk.gone == 1 and silk.life == 2,
        "Silk Cloth: 6 deals, 1 got, 4 missed worth 12s, 1 gone after 2s")
    check(silk.givenUp == 500 and silk.try == true and r.best == silk, "what you missed on it (12s) is more than the radar made elsewhere (5s): worth a try")
    check(wool and wool.key == 2592 and wool.miss == 0 and wool.gone == 1 and wool.try == false and #r.list == 2, "Wool Cloth is listed (a deal was gone) but not recommended: nothing was lost to speed; Linen with one deal is not listed")
    check(#sent == nSent, "working it out sent nothing to the auction house")
    -- the tab
    S.lastRows = S.lastRows or {}
    S.lastRows[4306] = { rows = { { price = 196, qty = 31 }, { price = 197, qty = 1967 } }, at = GetTime() }
    ns.Store:Put(4306, 196, 1998, GetServerTime())
    P.result = nil
    UI.tab = "PICKS"; UI:Render()
    local pk = AuctionMeshFrame.picks
    local function cell(i, c) return strip(pk.rows[i].c[c]._text) end
    print("     " .. strip(pk.head._text))
    print("     " .. strip(pk.why._text))
    print("     " .. strip(pk.sub._text))
    for i = 1, 2 do print(("     %s | %s | %s | %s | %s | %s | %s | [%s]"):format(cell(i, 1), cell(i, 2), cell(i, 3), cell(i, 4), cell(i, 5), cell(i, 6), cell(i, 7), pk.rows[i].btn._text)) end
    check(pk._shown and not AuctionMeshFrame.setup._shown and not AuctionMeshSnipeButton._shown, "the Picks tab shows its own panel")
    check(strip(pk.head._text) == "Try a stake-out on Silk Cloth." and strip(pk.why._text):find("you went for 4 deals on it and someone was faster: they were worth 12s00c", 1, true)
        and strip(pk.why._text):find("made 5s00c, which is what a stake-out gives up", 1, true), "one sentence says what to do, and the figures behind it")
    check(cell(1, 1) == "Silk Cloth" and cell(1, 2) == "6" and cell(1, 3) == "1" and cell(1, 4) == "4  12s00c" and cell(1, 5) == "1 2s" and cell(1, 7) == "1s96c",
        "the row: deals, got, missed with their worth, gone with how long they lasted, cheapest now")
    check(cell(1, 6) ~= "-" and S:TermsFor(4306).max ~= nil and cell(1, 6) == strip(ns.Seller.short(S:TermsFor(4306).max)), "and what a stake-out would buy at (" .. cell(1, 6) .. "), from the listing as last read")
    check(pk.rows[1].btn._shown and pk.rows[1].btn._text == "Stake out" and pk.rows[2].btn._text == "Stake out" and not pk.rows[3].btn._shown, "each candidate has a Stake out button")
    check(AuctionMeshFrame.tabPick._text == "Picks (1)", "the tab's label says there is a pick")
    check(#sent == nSent, "showing the tab sent nothing either")
    -- one click
    pk.rows[1].btn._scripts.OnClick(pk.rows[1].btn)
    check(S:StakeKey() == 4306 and UI.tab == "BUY" and strip(UI.notice.text):find("^Stake%-out set on Silk Cloth. Roll, tap or hold in the snipe box"), "one click sets the stake-out and takes you to the snipe box")
    check(AuctionMeshFrame.tabPick._text == "Picks", "with the stake-out set the label is plain again")
    S:StakeRecord(4306, 10, 2)
    UI.tab = "PICKS"; UI.notice = nil; UI:Render()
    print("     " .. strip(pk.head._text) .. " " .. strip(pk.why._text))
    check(strip(pk.head._text) == "Stake-out is on Silk Cloth." and strip(pk.why._text):find("price asked 10 times, 2 bought", 1, true) and strip(pk.why._text):find("^It buys at "),
        "the tab then shows the stake-out, what it buys at and what it has done so far")
    check(pk.rows[1].btn._text == "Stop", "its row has Stop")
    pk.rows[1].btn._scripts.OnClick(pk.rows[1].btn)
    check(S:StakeKey() == nil and UI.tab == "PICKS", "Stop ends it")
    -- it never works anything out while you are sniping
    local mark = P.result
    mark.at = GetTime() - 100 -- long overdue
    UI.wheelSeen = GetTime() -- inputs are arriving in the snipe box
    local r2, waiting = P:Get()
    check(r2 == mark and waiting == true, "while inputs arrive in the snipe box nothing is recalculated: the last figures are shown")
    UI.wheelSeen = nil
    S.verified[2589] = { key = 2589, units = 1, cost = 1, sell = 2, profit = 1, kind = "FLIP", buys = {}, counts = {}, at = GetTime() }
    r2, waiting = P:Get()
    check(r2 == mark and waiting == true, "nor while a deal is on screen")
    S.verified = {}
    r2, waiting = P:Get()
    check(r2 ~= mark and waiting == false, "once nothing is being sniped the figures are worked out again")
    -- the radar earns more elsewhere: keep the radar
    Sc.d.deals = {
        deal(4306, 280, 300, "failed"), deal(4306, 200, 400, "bought", { bu = 8, bc = 800 }),
        deal(2592, 270, 500, "bought", { bu = 8, bc = 800 }), deal(2592, 100, 400, "bought", { bu = 4, bc = 400 }), deal(2592, 30, 180, "gone", { life = 9 }),
    }
    P.result = nil; UI:Render()
    print("     " .. strip(pk.head._text) .. " " .. strip(pk.why._text))
    check(P.result.best == nil and strip(pk.head._text) == "Keep the radar. No single item is worth a stake-out."
        and strip(pk.why._text):find("the item you lost most on was Silk Cloth: 1 deal missed, worth 3s00c. The radar's catches on other items made 7s00c", 1, true),
        "missed 3s on Silk, the radar made 7s elsewhere (half of a deal bought counts for half): keep the radar, with the figures")
    check(AuctionMeshFrame.tabPick._text == "Picks", "and the tab's label stays plain")
    -- too little seen
    Sc.d.deals = { deal(4306, 280, 300, "failed"), deal(4306, 200, 300, "failed") }
    P.result = nil; UI:Render()
    check(strip(pk.head._text):find("^Keep sniping with the radar. Not enough has been seen yet") and strip(pk.why._text):find("2 deals recorded", 1, true), "two deals on record: it says there is not enough to go on")
    -- the snapshot carries it
    Sc.d.deals = { deal(4306, 300, 400, "bought", { bu = 8, bc = 800 }), deal(4306, 280, 300, "failed"), deal(4306, 200, 300, "failed"),
        deal(4306, 150, 300, "failed"), deal(2592, 100, 200, "bought", { bu = 8, bc = 800 }) }
    ns.Do.Snapshot()
    local text = AuctionMeshLogFrame.edit._text
    check(text:find("PICKS (5 deals seen in the last 5h, got 6s 0c): try a stake-out on Silk Cloth", 1, true) and text:find("stake-outs so far: Silk Cloth(4306) asked 10, bought 2", 1, true),
        "the Snapshot says what the Picks tab recommends and what stake-outs have done so far")
    AuctionMeshLogFrame:Hide()
    Sc.d.deals, AuctionMeshDB.stakeLog = dealsWas, logWas
    S.lastRows[4306] = nil; P.result = nil; S.termsCache = nil
    UI.tab = "BUY"; UI:Render()
end

print("throttle watch: everything that made a request wait, with its cause")
do
    local W, G = ns.Watch, ns.Gate
    local Se = ns.Seller
    W:Reset()
    G.cycle = 0.65
    local function last() return W.list[#W.list] end
    -- a purchase sent while the radar's read still holds the lock: the game holds it back
    W:Call("SendBrowseQuery", "swarm browse class 7 sub nil", true)
    advance(0.2)
    W:Call("StartCommoditiesPurchase", "buy start 16x 4306, verified total 1584", true)
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED")
    advance(0.45)
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    local e = last()
    print("     " .. e.kind .. ": " .. e.text)
    print("       before it: " .. e.ctx)
    check(W.count.QUEUED == 1 and e.kind == "QUEUED" and math.abs(e.secs - 0.45) < 0.06
        and e.text:find("^'buy start 16x 4306, verified total 1584' waited 0.4%ds: the auction house was still locked by 'swarm browse class 7 sub nil', sent 0.20s before it"),
        "a purchase held back by the game: which request waited, how long, and which one held the lock")
    check(e.ctx:find("buy start 16x 4306, verified total 1584 0.4%ds ago; swarm browse class 7 sub nil 0.6%ds ago") and e.ctx:find("2 requests in the last 2s, 2 in the last 10s", 1, true),
        "with the requests sent just before it and how busy the last seconds were")
    check(ns.Diag:Text():find("THROTTLE QUEUED 0.4%ds: 'buy start 16x 4306", 1) ~= nil, "it is one line in the log that starts with THROTTLE")
    check(W.byCall.StartCommoditiesPurchase and W.byCall.StartCommoditiesPurchase.n == 1, "and counted by the kind of request")
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
    -- the lock stays shut far longer than usual
    advance(1.6)
    fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    e = last()
    print("     " .. e.kind .. ": " .. e.text)
    check(W.count.SLOW == 1 and e.kind == "SLOW" and e.text:find("^the lock stayed shut 1.6%ds after 'buy start 16x 4306, verified total 1584' %(usual: 0.65s%)") and W.slowest > 1.5,
        "a lock that stays shut much longer than usual is an incident, with the request it followed")
    -- a normal answer is only counted
    local nList = #W.list
    W:Call("SendBrowseQuery", "swarm browse class 7 sub nil", true)
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT"); advance(0.65); fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"); fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(#W.list == nList and (W.hist[3] or 0) == 1, "a normal answer (0.65s) is counted in the lock-time table and is no incident")
    -- a stake-out's price requests are held back all the time: counted, not listed
    W:Call("SendBrowseQuery", "swarm browse class 7 sub nil", true)
    W:Call("StartCommoditiesPurchase", "stake-out price request 1x 4306 (buys at 112 or less each)", true)
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED"); advance(0.4); fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
    check(W.count.QUEUED == 2 and #W.list == nList and W.byCall.StartCommoditiesPurchase.n == 2, "a stake-out's price request held back for a normal lock is counted but not listed")
    -- the game drops a request: the addon's 5-second stop is recorded with its reason
    W:Call("SendSearchQuery", "item check 2589", true)
    local gapWas = ns.Tuner.d and ns.Tuner.d.gap and ns.Tuner.d.gap.i
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") -- (this fake client delivers every event twice, so it counts as two)
    e = nil
    for i = #W.list, 1, -1 do if W.list[i].kind == "BACKOFF" then e = W.list[i]; break end end
    print("     " .. e.kind .. ": " .. e.text)
    check((W.count.BACKOFF or 0) >= 1 and e.secs == 5 and e.text:find("^message dropped: the addon stops for 5 seconds") and e.ctx:find("^item check 2589 0.00s ago"),
        "a dropped request: the 5-second stop is recorded, with the request that was dropped")
    e = nil
    for i = #W.list, 1, -1 do if W.list[i].kind == "PACE" then e = W.list[i]; break end end
    if e then print("     " .. e.kind .. ": " .. e.text) end
    check((W.count.PACE or 0) == 0 or (e and e.text:find("pause after 'ready' is now", 1, true) ~= nil), "when that makes the addon lengthen its pause between requests, that is recorded too")
    if gapWas then ns.Tuner.d.gap.i = gapWas; ns.Tuner:Apply() end
    G.nextAt, G.penaltyUntil, G.lastError = 0, 0, -100
    -- nothing sent for seconds: the reason is recorded when sending starts again
    if not AuctionHouseFrame._shown then AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW") end
    UI:Open("BUY")
    S.buying = nil; G.holdUntil = nil
    W.stall, W.lastCallAt = nil, GetTime() - 4.2
    G.userUntil = GetTime() + 10
    W:Tick()
    check(W.stall and W.stall.why:find("one of the game's own screens made a request", 1, true), "a silence of more than 3 seconds is noticed, with the reason at the time")
    G.userUntil = 0
    W:Call("SendBrowseQuery", "swarm browse class 7 sub nil", true)
    e = last()
    print("     " .. e.kind .. ": " .. e.text)
    check(W.count.STALL == 1 and e.kind == "STALL" and e.text:find("^nothing was sent for 4.%ds: one of the game's own screens made a request"), "and written down when requests start again")
    -- the hold while a deal is on screen is on purpose: counted, not listed
    nList = #W.list
    W.lastCallAt = GetTime() - 5
    G.holdUntil = GetTime() + 3
    W:Tick(); G.holdUntil = nil
    W:Call("SendBrowseQuery", "swarm browse class 7 sub nil", true)
    check(W.count.HOLD == 1 and #W.list == nList, "the radar holding still while a deal is on screen is counted as on purpose, not as an incident")
    -- the Snapshot carries all of it
    ns.Do.Snapshot()
    local text = AuctionMeshLogFrame.edit._text
    for line in text:gmatch("[^\n]+") do
        if line:find("THROTTLE WATCH", 1, true) or line:find("^lock time") or line:find("^what made") or line:find("^held on purpose") or line:find("^requests the game held") then print("     | " .. line) end
    end
    check(text:find("THROTTLE WATCH this session: 8 auction house requests", 1, true) and text:find("lock time per request: usual 0.", 1, true)
        and text:find("what made requests wait: QUEUED 2 (0.", 1, true) and text:find("| SLOW 1 (", 1, true) and text:find("| BACKOFF %d %(%d+.0s in all, worst 5.00s%)")
        and text:find("| STALL 1 (", 1, true), "the Snapshot has the throttle watch: requests, lock times, and what made requests wait")
    check(text:find("requests the game held back, by kind: StartCommoditiesPurchase 2 (average 0.4", 1, true) and text:find("held on purpose (a deal on screen or a purchase in progress): 1 time(s)", 1, true),
        "which kind of request was held back and for how long on average; holds on purpose are separate")
    check(text:find("  %d%d:%d%d:%d%d STALL 4.%d+s: nothing was sent") and text:find("  %d%d:%d%d:%d%d QUEUED 0.4%ds: 'buy start 16x 4306"), "and the incidents, newest first, each with what came before it")
    AuctionMeshLogFrame:Hide()
    W:Reset()

    -- FEWER ROUTINE REQUESTS: what you hold is re-priced every 45s only on the Bags tab
    for s2 = 1, 16 do bags[s2] = nil end
    bags[1] = { itemID = 2589, stackCount = 6 }; fire("BAG_UPDATE_DELAYED")
    AuctionMeshDB.flips[2589] = { kind = "FLIP", units = 6, cost = 20, sell = 77, at = GetServerTime() }
    Se.priority, Se.pricedAt = nil, {}
    Se.prices[2589] = { price = 77, at = GetTime() - 60, commodity = true }
    UI.tab = "BUY"
    check(Se:NextToPrice() == nil, "Trades tab: a price read a minute ago is not read again (the request goes to the radar)")
    UI.tab = "SELL"
    check(Se:NextToPrice() == 2589, "Bags tab: it is re-read, as before, so Post always has a fresh price")
    Se.pricedAt = {}; Se.prices[2589] = nil; UI.tab = "BUY"
    check(Se:NextToPrice() == 2589, "an item that has never been priced is priced on any tab")
    Se.pricedAt = {}; Se.prices[2589] = { price = 77, at = GetTime() - 700, commodity = true }
    check(Se:NextToPrice() == 2589, "and on the Trades tab a price is still refreshed once in 10 minutes")
    AuctionMeshDB.flips[2589] = nil; bags[1] = nil; fire("BAG_UPDATE_DELAYED"); Se.prices[2589] = nil; Se.pricedAt = {}; Se.pending = nil
    UI.tab = "BUY"; UI:Render()
end

-- nothing in the whole run raised an error inside the redraw or an input (they are caught, so they must be looked for)
for _, e in ipairs(ns.errList or {}) do print("  ERROR caught " .. e.n .. " x in " .. e.name .. ": " .. e.msg) end
check(#(ns.errList or {}) == 0, "no error was caught in a redraw or an input during the whole run")
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
