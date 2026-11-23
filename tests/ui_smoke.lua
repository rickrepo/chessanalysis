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
        -- the game's Line object: a start and an end, kept so tests can look at them
        CreateLine = function(s)
            local l = widget(s)
            rawset(l, "SetStartPoint", function(me, _, _, x, yy) me._x0, me._y0 = x, yy end)
            rawset(l, "SetEndPoint", function(me, _, _, x, yy) me._x1, me._y1 = x, yy end)
            return l
        end,
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
    UseContainerItem = function(b, s) local it = bags[s]; gold = gold + ITEMS[it.itemID][2] * it.stackCount; bags[s] = nil; fire("PLAYER_MONEY"); fire("BAG_UPDATE_DELAYED") end, -- (the game says the gold changed, as it does)
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
AuctionMeshDB.cfg.minProfit, ns.Deals.cfg.minProfit = 20, 20 -- the walkthrough uses small deals
-- The walkthrough below drives the two-click path (first click asks for the price, second buys),
-- which is what happens when the game does not allow a price request without a click.
-- One-click buying and holding fire have their own section at the end.
S.hold = 0
S.upkeep.every, S.upkeep.bags, S.upkeep.bagsNew = 0, 0, 0 -- the walkthrough is about what is shown, not about request turns (those have their own section and tests/pace_test.lua)
ns.Auto.cfg.manyHidden, ns.Auto.cfg.crowded = 1e9, 1e9 -- the walkthrough is not a real session: auto-adjust must not move the smallest profit under it (it has its own section)
ns.Deals.cfg.maxSpend, ns.Deals.cfg.maxTied = 1, 1 -- the capital limits have their own section at the end
AuctionMeshDB.cfg.autoConfirm = false -- the walkthrough drives the two-input path; one-input buying has its own section
ns.Deals.cfg.requireTurnover = false -- the fake auction house has no other buyers until the "volume" section
AuctionMeshDB.cfg.fold = { SOLD = false, LISTED = false } -- the walkthrough looks at the rows of every section (folding has its own section)
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
-- the plain rows of the Sold tab: name | cells | profit
local function plainRows()
    local out = {}
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "detail") and f._shown and not rawget(f, "item") and not rawget(f, "sect") and not rawget(f, "looseItem") and strip(f.name._text or "") ~= "" then
            out[#out + 1] = strip(f.name._text) .. " | " .. strip(f.c[1]._text) .. " / " .. strip(f.c[2]._text) .. " / " .. strip(f.c[3]._text) .. " / " .. strip(f.c[4]._text) .. " | " .. strip(f.profit._text)
        end
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
    check(leftChannel == "GoldCrew7" and c.channel == nil and c.password == nil and c.route == nil and c.share == nil and c.v == 15,
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
do
    local ft = strip(AuctionMeshFrame.footer._text)
    print("     " .. ft)
    check(ft:find("^SESSION starts with your first press   |   TODAY 0:00  0 bought  %+ 0c   |   %d%d%d%d  0 bought  %+ 0c$"),
        "footer: SESSION (not started yet), TODAY and the year")
    check(strip(AuctionMeshFrame.mode._text) == "VENDOR + FLIPS", "the mode badge at the top left reads VENDOR + FLIPS")
end
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
    check(h[1] == "[-] POST, OR VENDOR NOW (1) | QTY / COST / MARKET / VENDOR NOW / P / L" and r[1]:find("| 12 / 3c / 8c / 24c less |", 1, true) and r[1]:find("| +48c |", 1, true),
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
        check(h[1] == "[-] TO SELL TO A VENDOR (1) | QTY / COST / VENDOR / IF LISTED / P / L" and r[1]:find("| 12 / 3c / 5c / 12c less |", 1, true),
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
check(#rowsText() == 1 and rowsText()[1]:find("Linen Cloth x6") and rowsText()[1]:find("LISTED") and rowsText()[1]:find("+3s18c", 1, true), "the posted auction is on the Sell tab as LISTED with its expected profit")
check(not AuctionMeshPostButton:IsShown(), "with nothing to post there is no Post next button either")
UI.tab = "BUY"; UI:Render()
r = rowsText(); for _, l in ipairs(r) do print("     " .. l) end
check(#r == 0, "the Buy tab lists no auction of yours: it is for sniping only")
check(AuctionMeshDB.realized == 24, "banked profit so far: +24c from the vendor sale")
local function heads()
    local out = {}
    for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._shown and rawget(f, "sect") then out[#out + 1] = strip(f.head._text) end end
    return out
end
do  -- the MONEY section on the Buy tab: label on the left, amount on the right, ruled total
    local lg = AuctionMeshFrame.ledger
    local function val(row) return strip(row.value._text) end
    for i = 1, 5 do print("     " .. lg.rows[i].label._text .. " | " .. val(lg.rows[i])) end
    print("     " .. lg.total.label._text .. " | " .. val(lg.total))
    print("     " .. strip(lg.note._text))
    local hd = heads(); UI.tab = "SELL"; UI:Render(); local hs = heads(); UI.tab = "BUY"; UI:Render()
    print("     sections: " .. table.concat(hd, " / "))
    do  -- the front of the Buy tab: what is being sniped, then the money broken down
        local W2 = AuctionMeshFrame
        print("     " .. strip(W2.target._text))
        check(W2.target._shown and strip(W2.target._text):find("^SNIPING FOR  any deal that makes %+ 20c or more    vendor deals and flips    the addon sets this figure from your results$"),
            "the Buy tab says in one plain line what is being sniped: any deal that makes + 20c or more")
        check(lg:IsShown() and rawget(W2, "money") == nil and lg.rows[1].label._text == "Gold on this character now" and lg.total.label._text == "Total when it has all sold",
            "under it the money is broken down, always there: in hand, sold, listed, in your bags, and the total")
    end
    check(hd[1] == "DEALS TO BUY NOW (0)" and hd[2]:find("^None right now") and hd[3] == nil and hs[1] == "[-] LISTED (1)", "below it: deals to buy and nothing else; your auctions are on the Sell tab under a grey heading")
    check(val(lg.rows[1]) == strip(ns.Seller.short(GetMoney())), "MONEY: gold on this character now")
    check(val(lg.rows[4]) == "+ 4s38c", "MONEY: 6 listed at 77c = + 4s38c after the 5% cut")
    check(val(lg.rows[2]) == "-" and val(lg.rows[3]) == "-" and val(lg.rows[5]) == "-", "MONEY: nothing sold yet, nothing waiting to be listed")
    check(val(lg.total) == strip(ns.Seller.short(GetMoney() + 438)), "MONEY: total when it has all sold = gold + listings")
    -- someone lists cheaper: the auction moves to STUCK LISTINGS
    ns.Store:Put(2589, 70, 900, GetServerTime()); UI.tab = "SELL"; UI:Render()
    check(heads()[1] == "[-] UNDERCUT (1)", "a cheaper listing appears: the auction moves under UNDERCUT")
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
        check(rawget(_G, "AuctionMeshDrawer") == nil and rawget(AuctionMeshFrame, "handle") == nil and AuctionMeshDB.listed[2589] ~= nil,
            "there is no Details sidebar: a click on a row opens nothing and changes nothing")
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
    do  -- a sold auction is not "stuck": it is on the Sold tab, with the time its gold arrives
        ns.Store.p[2589], ns.Store.t[2589] = 70, GetServerTime() -- other people list cheaper now; that no longer matters
        UI.tab = "SELL"; UI:Render()
        local hdSell = table.concat(heads(), " / ")
        UI.tab = "SOLD"; UI:Render()
        local hd = heads()
        print("     Sold tab: " .. table.concat(hd, " / "))
        local row
        for _, l in ipairs(plainRows()) do if l:find("Linen Cloth x6") then row = l end end
        print("     " .. tostring(row))
        check(hd[1] == "SOLD, GOLD ON ITS WAY (1)" and row and row:find("/ in 16 min |", 1, true) and AuctionMeshFrame.tabSold._text == "Sold (1)",
            "a sold auction is on the Sold tab, under SOLD, GOLD ON ITS WAY, with its pay-out time; the tab's label counts it")
        check(not hdSell:find("SOLD", 1, true) and not hdSell:find("UNDERCUT", 1, true), "and it is not on the Sell tab any more: not as sold, not as undercut")
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
            check(AuctionMeshDB.listed[2589] ~= nil, "a plain right-click on a row removes nothing")
        end
    end
    S.own, S.ownRead = ownWas, readWas
    UI.tab = "SELL"; UI:Render()
    check(not lg:IsShown(), "the Sell tab has no MONEY section")
    UI.tab = "HISTORY"; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp:IsShown() and #sp.rows == 3 and sp.rows[1].label._text == "Auto-adjust" and sp.rows[2].label._text == "Server limit, measured",
        "More tab: the settings, then three lines: what auto-adjust is doing, the server's limit, the radar")
    check(sp.bottom and -40 + sp.bottom >= -480, ("the More tab ends %d px under the top of the panel: above the footer, docked (about 513 high) or floating (520)"):format(40 - (sp.bottom or 0)))
    for i = 1, 3 do print("     " .. tostring(sp.rows[i].label._text) .. " | " .. strip(sp.rows[i].value._text)) end
    check(rawget(AuctionMeshFrame, "bar") == nil and rawget(AuctionMeshFrame, "snap") == nil and rawget(AuctionMeshFrame, "pop") == nil and UI.RenderBar == nil,
        "the header has no engine bar, Snapshot or Dock button any more: they said or did what something else already does")
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
    check(row and row:find("Ready to post", 1, true) and row:find("%[Post%]"), "at the auction house the Sell tab has it ready to post again, with a live price")
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
    check(r and r.item.action == "LISTED" and (strip(r.state._text):find("^Hold: ") or strip(r.state._text):find("^Relist: ") or strip(r.state._text):find("listing is"))
        and r.btn._shown and r.btn._text == "Cancel",
        "an undercut auction has its advice and a Cancel button on its row (Sell tab, UNDERCUT)")
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
    check(rowOf(2592) and rowOf(2592).item.action == "MAIL", "the auction is gone; the Sell tab shows the units as in the mailbox")
    print("     " .. chat[#chat])
    check(chat[#chat]:find("Cancelled:", 1, true) and chat[#chat]:find("5 x Wool Cloth", 1, true) and chat[#chat]:find("collect it at a mailbox, then press Post", 1, true), "chat says what to do next")
    UI.tab = "SELL"; UI:Render()
    local row
    for _, l in ipairs(rowsText()) do if l:find("Wool Cloth x5", 1, true) then row = l end end
    check(row and row:find("In your mailbox", 1, true), "the Sell tab shows it as in your mailbox")
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
        check(S.ownIds[2592] ~= nil and S.needOwned and S.needOwnedNow, "a list that is suddenly empty is not believed at once: it is asked for again")
        S.ownAskedAt = GetTime(); S:ReadOwned() -- (the answer to the addon's own request)
        check(S.ownIds[2592] == nil, "the answer to its own request is believed: the auction is gone")
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
    check(r and r.btn._shown and r.btn._text == "Cancel", "the Cancel button is there before your auctions have been read")
    S.needOwned, S.needOwnedNow = false, nil
    do
        local nc = #cancelled
        r.btn._scripts.OnClick(r.btn); r.btn._scripts.OnClick(r.btn)
        check(#cancelled == nc and S.needOwned and S.needOwnedNow and tostring(Se.note and Se.note.text or Se.note):find("Reading your auctions first", 1, true),
            "a click then cancels nothing: it has your auctions read first, and says so")
        Se.note = nil
    end
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
check(#ns.Diag:Text(true) > 1000, "the previous session is still available (More tab, Last session's log)")

print("history")
UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
local hist, seen = AuctionMeshDB.history or {}, {}
for _, h in ipairs(hist) do local m = strip(h.m); for _, w in ipairs({ "Bought:", "Collected from mailbox:", "Posted", "Sold vendor flips", "Nothing bought, nothing spent" }) do if m:find(w, 1, true) then seen[w] = true end end end
check(seen["Bought:"] and seen["Collected from mailbox:"] and seen["Posted"] and seen["Sold vendor flips"] and seen["Nothing bought, nothing spent"],
    "HISTORY lists purchases, mailbox pick-ups, posts, vendor sales and cancelled buys")
for i = 1, math.min(4, #hist) do print("     " .. strip(hist[i].m)) end
UI.tab = "BUY"

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
        "the More tab has no sharing controls")
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
UI.tab = "SELL"; UI.notice = nil; UI:Render() -- the NEXT line is shown on the Sell tab (the Buy tab has the big button)
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
-- a routine look at an item: its result is not put on the Buy tab
S:Evaluate(2447, { { price = 20, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI.wheelSeen = nil; UI:Render()
local st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Next check", 1, true) == nil and select(2, st:gsub("\n", "")) == 0,
    "the Buy tab's status is one line: the mode and what the radar is doing")
check(st:find("Peacebloom", 1, true) == nil, "a routine look at an item is not reported on the Buy tab")
check(st:find("Radar: a read every %d+%.%d%ds%.$") ~= nil and st:find("MODE", 1, true) == nil, "it gives the measured time between radar reads (the mode itself is the badge at the top left)")
-- the answer to something the radar asked about is shown
S.lastEval = nil; S.searching = { key = 2447, at = GetTime(), src = "market" }
S:Evaluate(2447, { { price = 21, qty = 500 }, { price = 78, qty = 100 }, { price = 80, qty = 300 } }, true)
UI.notice = nil; UI:Render()
st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(st:find("Last alert", 1, true) == nil and S.lastAlert and S.lastAlert.key == 2447,
    "the last answer to a radar alert is kept, and is not on the Buy tab")
UI.wheelSeen = GetTime(); UI:Render()
st = strip(AuctionMeshFrame.status._text)
for l in st:gmatch("[^\n]+") do print("     " .. l) end
check(select(2, st:gsub("\n", "")) == 0 and strip(AuctionMeshFrame.mode._text) == "VENDOR + FLIPS", "armed: still one line; the mode is on the badge")
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

print("the journal: every trade from purchase to sale")
do
    local s = ns.Journal:Totals()
    check(s.trades >= 3 and s.finished >= 2, ("journal totals: %d trades, %d finished, %d open"):format(s.trades, s.finished, s.open))
    check(UI.DrawerLines == nil and UI.FocusLines == nil and UI.ToggleDrawer == nil, "the Details sidebar and everything it drew are gone")
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
    check(strip(AuctionMeshFrame.status._text):find("Focus on 1 item.", 1, true), "the Buy tab says what the focus is")
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
        local o = AuctionMeshDB.outcomes[#AuctionMeshDB.outcomes]
        check(strip(AuctionMeshFrame.status._text):find("Last try", 1, true) == nil and o and o.k == "won" and o.key == 2770 and o.i and o.q and o.e,
            "how the try went in time is not on the Buy tab; it is kept with the outcome (input, price answer, end) for the Snapshot")
        -- and the item's own row, under DEALS TO BUY NOW: it stays for the flash, framed green, with what happened
        local function flashRows()
            local out = {}
            for i = 1, #frames do
                local f = frames[i]
                if rawget(f, "detail") and f._shown and rawget(f, "flash") and f.flash[1]._shown then out[#out + 1] = f end
            end
            return out
        end
        local fr = flashRows()
        check(S.verified[2770] == nil and #fr == 1 and strip(fr[1].name._text) == "Copper Ore" and strip(fr[1].detail._text):find("^GOT IT  12 x Copper Ore for 36c")
            and fr[1].heat._shown and rawget(fr[1], "item") == nil and not fr[1].btn._shown,
            "the row of the item just bought stays where it was, framed and tinted green, saying GOT IT (it has no button: nothing can be bought from it)")
        check(table.concat(headsText(), "\n"):find("DEALS TO BUY NOW (0)", 1, true) ~= nil, "it is not counted as a deal")
        advance(2)
        check(#flashRows() == 0 and UI.flashKey == nil and UI.flashRow == nil, "the row and its frame go when the flash ends")
        check(UI.flashKind == nil and not e[1]._shown, "the flash is gone after a second and a half")
    end
    check(strip(btn.result._text) == "" and strip(AuctionMeshFrame.footer._text):find("^SESSION "), "the count is in the footer now, not under the button")
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
            "the Buy tab says why nothing is offered, and when sale gold arrives")
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
        check(st:find("Gold is low: vendor deals only. You hold 2s50c; posting the 2 items you bought takes 4s", 1, true), "the Buy tab says it, with the figures")
        check(strip(AuctionMeshFrame.mode._text) == "VENDOR ONLY: GOLD LOW", "and the mode badge reads VENDOR ONLY: GOLD LOW")
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
        check(strip(AuctionMeshFrame.mode._text) == "VENDOR ONLY", "your own vendor-only setting shows on the badge as VENDOR ONLY")
        UI:SetVendorOnly(false); UI.notice = nil; UI:Render()
        check(strip(AuctionMeshFrame.mode._text) == "VENDOR + FLIPS", "and with flips on as VENDOR + FLIPS")
        do  -- one click on the badge changes it, without the More tab
            local m = AuctionMeshFrame.mode
            m._scripts.OnClick(m)
            check(AuctionMeshDB.cfg.flips == false and strip(m._text) == "VENDOR ONLY", "a click on the badge: VENDOR ONLY")
            m._scripts.OnClick(m)
            check(AuctionMeshDB.cfg.flips ~= false and strip(m._text) == "VENDOR + FLIPS", "another click: VENDOR + FLIPS again")
            UI.notice = nil; UI:Render()
        end
        C_AuctionHouse.CalculateCommodityDeposit = realFee; S.ClearFees()
        LIST[2589], LIST[2770] = nil, nil
        for _, k in ipairs({ 2592, 4306 }) do ns.Journal:Dropped(k, nil, "test") end
        reset(); gold = 900; S.feesCache, S.poor = nil, {}
    end

    -- THE FOOTER: SESSION (with its clock) | TODAY | THE YEAR
    do
        reset(); gold = 900; cfg.autoConfirm = nil
        S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil
        local totalsWas, sessionWas = AuctionMeshDB.totals, S.session
        local year = tonumber(os.date("%Y", GetServerTime()))
        AuctionMeshDB.totals = { day = { id = tonumber(os.date("%Y%m%d", GetServerTime())), n = 3, profit = 500 }, year = { id = year, n = 40, profit = 9000 } }
        S.session = nil
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
        local function foot() return strip(AuctionMeshFrame.footer._text) end
        check(foot() == ("SESSION starts with your first press   |   TODAY 0:00  3 bought  + 5s00c   |   %d  40 bought  + 90s00c"):format(year),
            "before your first press: no session yet; today and the year are there from earlier")
        -- the first press starts the session and its clock
        UI.InputPress(true, "wheel")
        UI:Render()
        check(foot():find("^SESSION 0:00  0 bought, 0 missed  %+ 0c   |   TODAY 0:00  3 bought"), "your first press starts the session: its clock is at 0:00, and so is today's")
        advance(65)
        check(foot():find("^SESSION 1:0%d  0 bought, 0 missed"), "the clock runs by itself (1:05 after 65 seconds), with no redraw of the panel needed")
        check(foot():find("TODAY 1:0%d  3 bought"), "today has a clock too, running with the session")
        -- a purchase counts in all three
        LIST[2770] = { { 3, 12 }, { 9, 200 }, { 10, 300 } }
        S.checkedAt = {}; S.priority = 2770; advance(1)
        UI.InputPress(true, "wheel"); advance(1.5)
        UI:Render()
        local worth = S.session.profit
        print("     " .. foot())
        check(gold == 900 - 36 and S.session.won == 1 and worth > 0, "a deal is bought in the session")
        check(foot():find("^SESSION 1:0%d  1 bought, 0 missed  %+ ") and AuctionMeshDB.totals.day.n == 4 and AuctionMeshDB.totals.day.profit == 500 + worth
            and AuctionMeshDB.totals.year.n == 41 and AuctionMeshDB.totals.year.profit == 9000 + worth,
            "it counts in the session, in today and in the year, each with what it is worth when sold")
        -- a miss counts in the session
        S:Result("lost", 2770, "MISSED  test"); UI:Render()
        check(foot():find("1 bought, 1 missed", 1, true), "a miss counts in the session")
        -- ten minutes with no press: the session is over; it stays shown until the next one starts
        advance(601); UI:Render()
        check(foot():find("^SESSION %d:%d%d %(over%)  1 bought, 1 missed"), "ten minutes without a press: the session is over, its figures stay")
        UI.InputPress(true, "wheel"); UI:Render()
        check(foot():find("^SESSION 0:00  0 bought, 0 missed  %+ 0c") and AuctionMeshDB.totals.day.n == 4, "the next press starts a new session from zero; today keeps its total")
        check(foot():find("TODAY 1:0%d  4 bought") and AuctionMeshDB.totals.day.secs >= 65 and AuctionMeshDB.totals.day.secs < 70,
            "today's clock keeps the time of the session before (up to its last press) and goes on from there")
        -- the day turns: today starts again, the year goes on
        AuctionMeshDB.totals.day.id = AuctionMeshDB.totals.day.id - 1
        UI:Render()
        check(AuctionMeshDB.totals.day.n == 0 and AuctionMeshDB.totals.year.n == 41 and foot():find("TODAY 0:00  0 bought", 1, true), "a new day: today starts at zero (its clock too), the year goes on")
        -- the first time, the totals are filled from the journal of your trades
        AuctionMeshDB.totals = nil
        local tt = S:Totals()
        check(tt.year.n >= 1 and tt.year.profit > 0 and tt.day.n >= 1, "with no totals yet they are worked out once from the journal of your trades")
        AuctionMeshDB.flips[2770] = nil; ns.Journal:Dropped(2770, nil, "test")
        AuctionMeshDB.totals, S.session = totalsWas, sessionWas
        LIST[2770] = nil; LIST[2319] = leather
        cfg.autoConfirm = false
        S.result, S.lastTry, UI.flashUntil, UI.wheelSeen = nil, nil, nil, nil
        S.tally.won, S.tally.lost, S.tally.gone = 0, 0, 0
        advance(1); reset(); UI:Render()
    end

    -- FAST SELLERS OUTSIDE THE FOCUS SET are checked for flips too (they were passed over), without taking the radar's turns
    do
        reset(); gold = 90000; S.cool, S.streak, S.muted = {}, {}, {}
        local leather = LIST[2319]; LIST[2319] = nil
        local realFocus, realWide = S.InFocus, S.InWide
        S.InFocus = function(_, k) return k == 2770 end            -- laser focus: Copper Ore only
        S.InWide = function(_, k) return k == 3356 or k == 3820 end -- Kingsblood and Stranglekelp: fast sellers outside it
        ITEMS[3356], ITEMS[3820], ITEMS[785] = { "Kingsblood", 30 }, { "Stranglekelp", 100 }, { "Mageroyal", 20 }
        local now = GetServerTime()
        for _, k in ipairs({ 3356, 3820, 785 }) do ns.Store.fp[k], ns.Store.ft[k] = 300, now end
        local everyWas, bagsWas = S.upkeep.every, S.upkeep.bags
        S.upkeep.every, S.upkeep.bags, S.upkeep.bagsNew = 8, 8, 8
        S.wide, S.triggers, S.judged, S.checkedAt, S.ownSweep, S.sweep = {}, {}, {}, {}, {}, {}
        local n0 = #sent
        local function searched(k) for i = n0 + 1, #sent do if sent[i] == "search" .. k then return true end end return false end
        -- not a fast seller and not in focus: passed over, as before
        S:OnSweep(785, 200, 500)
        check(S.wide[785] == nil and S.triggers[785] == nil, "an item that is neither in focus nor measured to sell fast: no flip alert, as before")
        -- a fast seller outside the focus, 30% under its market
        S:OnSweep(3356, 210, 800)
        check(S.wide[3356] ~= nil and S.triggers[3356] == nil and #S.triggers == 0, "Kingsblood (a fast seller outside the focus) at 2s10c under a 3s market: noted, but NOT as an alert that holds the radar")
        ns.radarSince = 0
        check(S:YieldTo() == true and not searched(3356), "the radar's next read goes out: the check waits for the upkeep turn")
        ns.radarSince = 8
        LIST[3356] = { { 210, 40 }, { 300, 500 }, { 301, 400 }, { 305, 300 } }
        check(S:YieldTo() == false and searched(3356) and S.wide[3356] == nil, "in the upkeep turn (one request in nine) it is checked")
        advance(1)
        check(S.verified[3356] and S.verified[3356].kind == "FLIP" and S.verified[3356].units == 40, "and the flip is offered: 40 Kingsblood at 2s10c")
        S.verified[3356] = nil; S.dealSeen[3356] = nil
        -- gone from the radar before its turn came: no request is spent on it
        S.checkedAt, S.judged = {}, {}
        S:OnSweep(3356, 210, 800)
        S:OnSweep(3356, 300, 760) -- the next read: back at the market price
        n0 = #sent
        ns.radarSince = 8
        local nextKey = S:NextCheck(true) -- the upkeep turn's pick
        check(nextKey ~= 3356 and not searched(3356) and S.wide[3356] == nil, "the cheap price is gone from the radar's next read before its turn: dropped, no request spent")
        -- at half the market price or less: an ordinary alert, at once
        S.checkedAt, S.judged = {}, {}
        ns.radarSince = 0
        S:OnSweep(3820, 140, 300)
        check(S.triggers[3820] ~= nil and S.wide[3820] == nil, "Stranglekelp at 1s40c under a 3s market (less than half): an ordinary alert, checked at once")
        S.triggers, S.trigInfo, S.wide = {}, {}, {}
        S.InFocus, S.InWide = realFocus, realWide
        S.upkeep.every, S.upkeep.bags, S.upkeep.bagsNew = everyWas, bagsWas, 0
        for _, k in ipairs({ 3356, 3820, 785 }) do ns.Store.fp[k], ns.Store.ft[k] = nil, nil; ITEMS[k] = nil; LIST[k] = nil; S.ownSweep[k] = nil; S.sweep[k] = nil end
        LIST[2319] = leather
        ns.radarSince = 0
        S.result, S.lastTry, UI.flashUntil = nil, nil, nil
        advance(1); reset(); UI:Render()
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

    -- ONE ITEM, ONE RECORD: a flip bought of an item you hold from a vendor deal ADDS to it (it replaced the record: the units were gone from the Sell tab)
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
        check(sellable == 56, "all 56 are on the Sell tab to be sold")
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
        local heavy = LIST[4234]; LIST[4234] = nil -- (standing deals of other sections are not part of this)
        S.verified, S.dealSeen, G.holdUntil = {}, {}, nil
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
        LIST[2770] = nil; LIST[2319] = leather; LIST[4234] = heavy
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
    local dockBtn = AuctionMeshFrame.setup.dock
    UI.tab = "HISTORY"; UI:Render()
    check(UI.docked == true and dockBtn._text == "Inside the auction house", "inside the auction house; More, Settings has the button that says so")
    dockBtn._scripts.OnClick(dockBtn)
    check(UI.docked == false and AuctionMeshDB.cfg.dock == false and AuctionMeshFrame:IsShown() and AuctionMeshFrame._parent == UIParent, "one click makes it a separate window")
    UI:Render()
    check(dockBtn._text == "A window of its own", "the button now says: a window of its own")
    local moved = 0
    AuctionMeshFrame.StartMoving = function() moved = moved + 1 end
    local row
    for i = 1, #frames do local f = frames[i]; if rawget(f, "detail") and f._scripts.OnDragStart then row = f; break end end
    row._scripts.OnDragStart(row)
    AuctionMeshFrame._scripts.OnDragStart(AuctionMeshFrame)
    check(moved == 2, "the separate window is dragged by its background or its rows")
    dockBtn._scripts.OnClick(dockBtn)
    check(UI.docked == true and AuctionMeshDB.cfg.dock == true, "the same button puts it back inside the auction house")
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
        "the Buy tab says so")
    UI.tab = "HISTORY"; UI:Render()
    local sp = AuctionMeshFrame.setup
    check(sp.tied._text == "50% unsold", "Setup shows the limit")
    sp.tied._scripts.OnClick(sp.tied); UI:Render()
    check(cfg.maxTied == 70 and math.abs(ns.Deals.cfg.maxTied - 0.70) < 1e-9 and sp.tied._text == "70% unsold" and S:Capital().paused == false,
        "one click raises it to 70%: flips are allowed again")
    ns.Do.MaxTied(50)
    do  -- ONE FLIP MAY TAKE: its own button (no code to paste), 35 > 50 > 75 > 100 > 35
        local spendWas = cfg.maxSpend
        ns.Do.MaxSpend(35); UI:Render()
        check(sp.spend._text == "35% a flip", "Setup shows how much of the gold in hand one flip may take")
        sp.spend._scripts.OnClick(sp.spend); UI:Render()
        check(cfg.maxSpend == 50 and math.abs(ns.Deals.cfg.maxSpend - 0.50) < 1e-9 and sp.spend._text == "50% a flip", "one click: 50%")
        sp.spend._scripts.OnClick(sp.spend); sp.spend._scripts.OnClick(sp.spend); UI:Render()
        check(cfg.maxSpend == 100 and sp.spend._text == "100% a flip" and strip(UI.notice.text):find("The first big pile can take all of it", 1, true), "two more: 100%, with what that means")
        sp.spend._scripts.OnClick(sp.spend)
        check(cfg.maxSpend == 35, "and round to 35% again")
        cfg.maxSpend = spendWas; ns.Deals.cfg.maxSpend = (spendWas or 100) / 100
        -- THE IMPORT BOX with a key-press tool still running: it is not allowed to fill up with one character
        local code = sp.code
        UI.notice = nil
        code:SetText("9999"); code._scripts.OnTextChanged(code)
        check((code._text or "") == "" and UI.notice and strip(UI.notice.text):find("Something keeps typing '9' into the import box", 1, true),
            "a box filling with one repeated character is emptied, and the panel says a key-press tool is typing into it")
        code:SetText("AMS1:spend=50"); code._scripts.OnTextChanged(code)
        check(code._text == "AMS1:spend=50", "a pasted code is left alone")
        code._scripts.OnEnterPressed(code)
        check(cfg.maxSpend == 50 and (code._text or "") == "", "Enter in the box applies it")
        cfg.maxSpend = spendWas; ns.Deals.cfg.maxSpend = (spendWas or 100) / 100
        UI.notice = nil
    end
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
        check(strip(AuctionMeshSnipeButton.label._text) == "4 deals hidden by your 90s00c minimum profit (best: + 11s22c). Lower it on the More tab.",
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
        do  -- THE FIGURE FOLLOWS YOUR PRESSING: three seconds at 400 ms, then one second at 100 ms
            ns.Gate.cycle = 0.74
            local t, now = {}, GetTime()
            for i = 0, 7 do t[#t + 1] = now - 4 + i * 0.4 end   -- ... up to 1.2 seconds ago
            for i = 0, 10 do t[#t + 1] = now - 1 + i * 0.1 end  -- the last second: every 100 ms
            UI.inputTimes = t
            UI:Render()
            print("     " .. strip(pg.text._text))
            check(strip(pg.text._text) == "An input every 100 ms: OPTIMAL",
                "pressing faster shows within a second: the figure is the last second of inputs (the average of four seconds said 222 ms)")
            -- and it is redrawn on its own while inputs arrive, without a redraw of the panel
            local renders, realRender = 0, UI.Render
            UI.Render = function(...) renders = renders + 1; return realRender(...) end
            UI.dirty = false
            local closeWas = AuctionHouseFrame._shown
            AuctionHouseFrame:Hide() -- (with the auction house shut the panel is not redrawn on a timer)
            UI.inputTimes = { GetTime() - 0.9, GetTime() - 0.6, GetTime() - 0.3, GetTime() }
            pg.text:SetText("stale")
            AuctionMeshFrame._scripts.OnUpdate(AuctionMeshFrame, 0.25)
            print("     " .. strip(pg.text._text) .. "  (panel redraws: " .. renders .. ")")
            check(strip(pg.text._text):find("^An input every 300 ms: ") and renders == 0, "the gauge is brought up to date five times a second while inputs arrive, with no redraw of the panel")
            UI.Render = realRender
            if closeWas then AuctionHouseFrame:Show() end
        end
        ns.Gate.cycle = nil; UI.inputTimes = nil
        -- the verdict on each try
        S.tally.inTime, S.tally.late = 0, 0
        S.tryInfo = { key = 2770, t0 = GetTime(), input = 0.03, held = 0.46 }; S:Result("lost", 2770, "MISSED  test")
        check(S.lastTry and S.lastTry.late == false and S.tally.inTime == 1, "a price request the game had to hold for its lock: the input was IN TIME (it could not have left sooner)")
        S.tryInfo = { key = 2770, t0 = GetTime(), input = 1.4 }; S:Result("lost", 2770, "MISSED  test")
        check(S.lastTry.late == true and S.tally.late == 1, "an input 1.4 seconds after the deal, sent with the lock already open: LATE")
        UI.tab = "BUY"; UI.notice = nil; UI:Render()
        check(S.tally.inTime == 1 and S.tally.late == 1, "the session keeps the count: 1 of 2 presses in time")
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
        check(strip(btn.hint._text):find("no key chosen yet: More tab, Key", 1, true) and not keyBound(), "the snipe box says a key has to be chosen first; nothing is bound")
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
        check(not keyBound(), "on the More tab the key is not taken over")
        -- on the Buy tab the key is bound to the snipe box, deal or no deal; other tabs give it back
        UI.tab = "BUY"; UI:Render()
        check(bound[btn] and bound[btn].F == "AuctionMeshSnipeButton:KEY", "on the Buy tab F is bound to the snipe box")
        check(strip(btn.hint._text):find("tap F (it works anywhere while this tab is open), or click here", 1, true), "and the box says so")
        UI.tab = "SELL"; UI:Render()
        check(not keyBound(), "on the Sell tab F is your own key again")
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
                "one key: F is bound on the Buy tab and the box says what it does")
            UI.tab = "SELL"; UI:Render()
            check(keyBound(), "and on the Sell tab too (there it posts)")
            UI.tab = "HISTORY"; UI:Render()
            check(not keyBound(), "on the More tab F is your own key")
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
            check(label():find("^POSTED 5 x Wool Cloth at 1s49c each. Nothing left to post."), "the snipe box says what was posted and that nothing is left (posting from the Buy tab used to show nothing)")
            do  -- each step of a post is shown while it happens
                local Se3 = ns.Seller
                Se3:Note(2592, "Getting the live price first. Press Post again in a second.")
                UI:Render()
                check(label():find("^Posting Wool Cloth: Getting the live price first"), "while the price is being fetched the box says so")
                UI.tab = "SELL"; UI:Render()
                check(strip(AuctionMeshFrame.status._text):find("^Posting Wool Cloth: Getting the live price first"), "and so does the top of the Sell tab")
                check(rawget(btn, "result") and rawget(btn, "result")._shown == false, "the 'Last: GOT IT' line of the snipe box is not left showing over the Sell tab")
                UI.tab = "HISTORY"; UI:Render()
                check(rawget(btn, "result")._shown == false, "nor over the More tab")
                UI.tab = "BUY"; UI:Render()
                check(rawget(btn, "result")._shown == true, "it is back on the Buy tab")
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
            -- on the Sell tab the key posts as well
            AuctionMeshDB.flips[2589] = { kind = "FLIP", units = 4, cost = 10, sell = 80, at = GetServerTime(), proof = "test" }
            LIST[2589] = { { 78, 100 }, { 80, 300 } }
            bags[3] = { itemID = 2589, stackCount = 4 }; fire("BAG_UPDATE_DELAYED")
            UI.tab = "SELL"; UI:Render()
            np = #posted
            for _ = 1, 60 do btn._scripts.OnClick(btn, "KEY"); advance(0.05) end
            check(#posted == np + 1 and posted[#posted].qty == 4, "on the Sell tab the one key posts the next item too")
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
        -- waiting for a key press ends when the More tab is left
        UI.tab = "HISTORY"; UI:Render()
        sp.key._scripts.OnClick(sp.key)
        AuctionMeshFrame.tabBuy._scripts.OnClick(AuctionMeshFrame.tabBuy)
        check(not UI.capturingKey and UI.tab == "BUY", "leaving the More tab while it waits for a key cancels the wait")
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
        local snap = AuctionMeshFrame.setup.snap
        check(snap and snap._text == "Snapshot", "the Snapshot button is on More, Settings")
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
        check(snapText:find("paste it into the box on the More tab): AMS1:min=75;margin=22;", 1, true) and snapText:find("itemmin=4306:300;ignore=2287", 1, true)
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
        -- shown on the More tab and in the Snapshot
        UI.tab = "HISTORY"; UI.notice = nil; UI:Render()
        local sp = AuctionMeshFrame.setup
        print("     " .. strip(sp.rows[1].label._text) .. ": " .. strip(sp.rows[1].value._text))
        check(strip(sp.rows[1].label._text) == "Auto-adjust, last change" and strip(sp.rows[1].value._text):find("^smallest profit 3s 0c > 2s 25c"), "the More tab shows the last change auto-adjust made")
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

    -- DEAL ROWS: coloured by profit, and the one you went for is framed red when it is missed
    do
        reset(); gold = 90000; S.verified = {}
        local function deal(key, profit) return { key = key, kind = "FLIP", units = 10, cost = 100, sell = 50, profit = profit, deposit = 0, buys = {}, counts = {}, commodity = true, at = GetTime(), born = GetTime(), from = "me" } end
        ITEMS[2770] = ITEMS[2770] or { "Copper Ore", 5 }
        ITEMS[2589] = ITEMS[2589] or { "Linen Cloth", 1 }
        ITEMS[2592] = ITEMS[2592] or { "Wool Cloth", 3 }
        ITEMS[4306] = ITEMS[4306] or { "Silk Cloth", 3 }
        S.verified[2770], S.verified[2589], S.verified[2592], S.verified[4306] = deal(2770, 12000), deal(2589, 3000), deal(2592, 600), deal(4306, 120)
        UI.tab = "BUY"; UI.notice = nil; UI.flashUntil, UI.flashKey, UI.flashRow = nil, nil, nil; UI:Render()
        local by = {}
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "detail") and f._shown and rawget(f, "item") and not f.item.action then by[f.item.key] = f end
        end
        local _, t1 = UI.Heat(12000); local _, t2 = UI.Heat(3000); local _, t3 = UI.Heat(600); local _, t4 = UI.Heat(120)
        check(t1 == 1 and t2 == 2 and t3 == 3 and t4 == 4, "four steps by profit: 1g and more, 25s and more, 5s and more, less")
        check(by[2770] and by[2770].heat._shown and by[2770].profit._text:find("|cffffd633", 1, true) and by[2770].name._text:find("|cffffd633", 1, true),
            "a deal that makes 1g or more: its row is tinted gold, with its name and profit in gold")
        check(by[2589].heat._shown and by[2589].profit._text:find("|cff40ff70", 1, true) and by[2589].name._text:find("|cff40ff70", 1, true),
            "25s or more: tinted bright green, name and profit in bright green")
        check(by[2592].heat._shown and by[2592].profit._text:find("|cff33d95c", 1, true) and not by[2592].name._text:find("|c", 1, true),
            "5s or more: a lighter green tint, the name left plain")
        check(not by[4306].heat._shown and by[4306].profit._text:find("|cff8fae96", 1, true), "less than 5s: no tint, the profit greyed")
        local rt = rowsText()
        check(rt[1]:find("^Copper Ore") and rt[2]:find("^Linen Cloth") and rt[3]:find("^Wool Cloth") and rt[4]:find("^Silk Cloth"), "and they are listed most profit first")
        -- missed: its row turns red where it was (second), the others stay
        S.verified[2589] = nil
        S:Result("lost", 2589, "MISSED  Linen Cloth: someone was faster. Nothing spent.")
        UI:Render()
        local red, order = nil, {}
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "detail") and f._shown and rawget(f, "flash") and f.icon and strip(f.name._text or "") ~= "" and (rawget(f, "item") or f.flash[1]._shown) then
                order[#order + 1] = strip(f.name._text)
                if f.flash[1]._shown then red = f end
            end
        end
        check(red ~= nil and strip(red.name._text) == "Linen Cloth" and strip(red.detail._text):find("^MISSED  Linen Cloth") and red.detail._text:find("|cffff", 1, true)
            and order[1] == "Copper Ore" and order[2] == "Linen Cloth" and order[3] == "Wool Cloth",
            "a missed deal: its row stays in its place for the flash, framed red, saying MISSED")
        check(by[2770].flash[1]._shown == false or by[2770] == red, "only that row is framed")
        -- a deal that is still there after a purchase of part of it keeps its real row, framed green
        S:Result("won", 2770, "GOT IT  5 x Copper Ore")
        UI:Render()
        check(by[2770].flash[1]._shown and rawget(by[2770], "item") ~= nil and by[2770].btn._shown, "a deal bought in part: its own row is framed green, and it can still be bought")
        advance(2)
        S.verified = {}; S.result, S.lastTry = nil, nil
        S.tally.won, S.tally.lost = 0, 0
        reset(); gold = 900
    end

    -- THE REFRESH BUTTON: the bags are read again, and what was given up on as not found is tracked again
    do
        reset(); gold = 900
        local J = ns.Journal
        ITEMS[9191] = { "Refresh Cloth", 3 } -- an item with no history in this run
        local b = AuctionMeshFrame.refresh
        check(b ~= nil and b._text == "Refresh", "there is a Refresh button at the top of the panel, on every tab")
        -- 8 Refresh Cloth are in the bags; the addon's record says nothing is held (the game's bag event was missed)
        local t = J:Bought(9191, "Refresh Cloth", "FLIP", 8, 30, 90)
        t.lost, t.lostWhy = 8, "not found in bags or mailbox"
        local flipWas = AuctionMeshDB.flips[9191]
        AuctionMeshDB.flips[9191] = nil
        -- (put in the bags with no word from the game that they changed: that is the missed event)
        local slotOf, slotWas = { [9191] = 14, [4306] = 15 }, { bags[14], bags[15] }
        local function setBag(id, n) bags[slotOf[id]] = n > 0 and { itemID = id, stackCount = n } or nil end
        setBag(9191, 8)
        UI.tab = "SELL"; UI.scroll = { SELL = 7 }; UI:Render()
        local function held() for _, e in ipairs(Se:Entries()) do if e.key == 9191 and e.action ~= "LISTED" then return e end end end
        check(held() == nil, "before: 8 Refresh Cloth in the bags that the lists do not show")
        b._scripts.OnClick(b)
        local e = held()
        check(e ~= nil and e.count == 8 and AuctionMeshDB.flips[9191].cost == 30 and t.lost == 0,
            "Refresh: they are back on the Sell tab, 8 of them at the 30c each they cost")
        check(UI.scroll.SELL == 0 and strip(AuctionMeshFrame.status._text):find("^Refreshed: %d+ stacks? in your bags %(16 slots%), no reagent bag found%. %d+ items? to deal with %(tab Sell%)%. 8 units the addon had lost track of are back%."),
            "the lists start from their top again and the panel says what the refresh found")
        -- pressed again: nothing more is taken (never more than was marked not found)
        setBag(9191, 20)
        b._scripts.OnClick(b)
        check(held().count == 8, "more of the same item in the bags is yours, not the addon's: a second Refresh takes nothing more")
        -- something of yours the addon never bought is left alone
        setBag(4306, 5)
        local was = AuctionMeshDB.flips[4306]
        AuctionMeshDB.flips[4306] = nil
        b._scripts.OnClick(b)
        check(AuctionMeshDB.flips[4306] == nil, "what you hold that the addon never bought is not picked up")
        AuctionMeshDB.flips[4306] = was
        bags[14], bags[15] = slotWas[1], slotWas[2]; Se:ScanBags()
        AuctionMeshDB.flips[9191] = flipWas; ITEMS[9191] = nil
        for i = #J.list, 1, -1 do if J.list[i] == t then table.remove(J.list, i) end end
        UI.tab = "BUY"; UI.notice = nil
        reset()
    end

    -- THE HEADER FITS: four tabs on the left, Refresh (and the close button) on the right
    do
        local f = AuctionMeshFrame
        check(UI.HeaderRoom(720, true) >= 40 and UI.HeaderRoom(794, false) >= 40, ("floating panel (720 wide): %d px between the More tab and the Refresh button"):format(UI.HeaderRoom(720, true)))
        check(f.tabBuy._text:find("^Buy") and f.tabSell._text:find("^Sell") and f.tabGold._text == "Chart" and f.tabHist._text:find("^More"), "the tabs: Buy, Sell, Sold, Chart, More")
        -- More: three pages on a row of their own
        f.tabHist._scripts.OnClick(f.tabHist)
        local sp = f.setup
        check(UI.tab == "HISTORY" and f.moreNav._shown and sp.pages.basic._shown and not sp.pages.adv._shown and strip(sp.title._text):find("^SETTINGS"),
            "More opens on Settings: how you buy, the panel and bank alt, what to send to Claude")
        f.navAdv._scripts.OnClick(f.navAdv)
        check(sp.pages.adv._shown and not sp.pages.basic._shown and strip(sp.title._text):find("^ADVANCED: the addon sets and adjusts these by itself"),
            "Advanced holds the figures the addon works out itself: the smallest profit, the flip margin, the money limits, what the radar reads")
        f.tabPick._scripts.OnClick(f.tabPick)
        check(UI.tab == "PICKS" and f.picks._shown and not sp._shown and f.moreNav._shown, "the stake-out picks are the third page of More (they were a tab)")
        f.tabBuy._scripts.OnClick(f.tabBuy)
        check(UI.tab == "BUY" and not f.moreNav._shown, "(back on Trades the page row is gone)")
    end

    -- STAKE-OUT: one item watched by asking its price on every wheel notch
    do
        reset(); gold = 5000; cfg.autoConfirm = nil
        local leather = LIST[2319]; LIST[2319] = nil
        local heavy = LIST[4234]; LIST[4234] = nil -- (a deal left over from an earlier section: nothing else to buy here)
        ITEMS[2838] = { "Heavy Stone", 15 }
        LIST[2838] = { { 300, 75 }, { 320, 44 }, { 325, 149 }, { 327, 44 }, { 329, 25 } }
        ns.Deals.cfg.requireTurnover = false
        UI.tab = "BUY"
        S:SetStake(2838) -- (set from the Picks tab's Stake out button, or a code)
        check(S:StakeKey() == 2838 and cfg.stake == 2838, "the stake-out is set on Heavy Stone")
        advance(2); S.verified = {} -- its listing is read first
        local max = S:StakeTerms()
        print(("     Heavy Stone, market 3s00c: the stake-out buys at %s or less, up to %s at a time"):format(tostring(max), tostring(S.stake.cap)))
        check(max and max >= 150 and max < 260 and S.stake.kind == "FLIP", "the buying price comes from the normal deal rules and the item's own listing")
        UI:Render()
        check(label():find("^STAKE%-OUT SET, NOT RUNNING    Heavy Stone: buys at ") and strip(btn.hint._text):find("^Stake%-out: put the mouse here and keep rolling the wheel"), "the snipe box shows the stake-out and what it waits for")
        do  -- IT IS UNMISTAKABLE THAT A STAKE-OUT IS SET: the mode line, a gold snipe box, and a button to end it
            UI.notice = nil; UI:Render()
            local stt = strip(AuctionMeshFrame.status._text)
            print("     " .. stt)
            check(strip(AuctionMeshFrame.mode._text) == "STAKE-OUT: Heavy Stone" and stt:find("^Not running: press in the snipe box to start it%. Until then the radar reads as usual%.$"),
                "the badge reads STAKE-OUT: Heavy Stone, and the status line says it is not running yet")
            check(AuctionMeshFrame.stakeStop._shown and AuctionMeshFrame.stakeStop._text == "Stop stake-out", "a Stop stake-out button is on the Buy tab while one is set")
            UI.tab = "SELL"; UI:Render()
            check(not AuctionMeshFrame.stakeStop._shown, "(on the Buy tab only)")
            UI.tab = "BUY"; UI:Render()
        end
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
        check(label():find("^STAKE%-OUT RUNNING    Heavy Stone: buys at ") and label():find("last price 3s00c", 1, true), "the box shows the last price the server gave")
        do
            UI.notice = nil; UI:Render()
            local stt = strip(AuctionMeshFrame.status._text)
            check(strip(AuctionMeshFrame.mode._text) == "STAKE-OUT: Heavy Stone" and stt:find("^Running: every input asks its price%. Nothing else is bought and the radar is off%.$"),
                "while it runs the status line says so: only this item, radar off")
        end
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
        check(S:StakeKey() == nil and S.stake == nil, "a code (or the Stop button) ends it")
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
    check(AuctionMeshFrame.tabPick._text == "Stake-out picks (1)" and AuctionMeshFrame.tabHist._text == "More (1)", "the tab's label says there is a pick")
    check(#sent == nSent, "showing the tab sent nothing either")
    -- one click
    pk.rows[1].btn._scripts.OnClick(pk.rows[1].btn)
    check(S:StakeKey() == 4306 and UI.tab == "BUY" and strip(UI.notice.text):find("^Stake%-out set on Silk Cloth. Roll or tap in the snipe box"), "one click sets the stake-out and takes you to the snipe box")
    check(AuctionMeshFrame.tabPick._text == "Stake-out picks", "with the stake-out set the label is plain again")
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
    check(AuctionMeshFrame.tabPick._text == "Stake-out picks", "and the tab's label stays plain")
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

    -- FEWER ROUTINE REQUESTS: what you hold is re-priced every 45s only on the Sell tab
    for s2 = 1, 16 do bags[s2] = nil end
    bags[1] = { itemID = 2589, stackCount = 6 }; fire("BAG_UPDATE_DELAYED")
    AuctionMeshDB.flips[2589] = { kind = "FLIP", units = 6, cost = 20, sell = 77, at = GetServerTime() }
    Se.priority, Se.pricedAt = nil, {}
    Se.prices[2589] = { price = 77, at = GetTime() - 60, commodity = true }
    UI.tab = "BUY"
    check(Se:NextToPrice() == nil, "Buy tab: a price read a minute ago is not read again (the request goes to the radar)")
    UI.tab = "SELL"
    check(Se:NextToPrice() == 2589, "Sell tab: it is re-read, as before, so Post always has a fresh price")
    Se.pricedAt = {}; Se.prices[2589] = nil; UI.tab = "BUY"
    -- REQUESTS FOLLOW THE TAB: on the Buy tab nothing is read for selling, on the Sell tab everything is
    check(Se:NextToPrice() == nil, "Buy tab: an item with no price at all is still not priced there: every request is for buying")
    Se.pricedAt = {}; Se.prices[2589] = { price = 77, at = GetTime() - 700, commodity = true }
    check(Se:NextToPrice() == nil, "Buy tab: nor is a price that is ten minutes old read again")
    Se.pricedAt = {}; Se.prices[2589] = nil
    do  -- the one exception: the "one key" way of buying also posts from the Buy tab, and needs the prices for it
        local modeWas = AuctionMeshDB.cfg.buyMode
        AuctionMeshDB.cfg.buyMode = "one"
        check(UI.BuyMode() == "one" and Se:NextToPrice() == 2589, "(with 'One key: buys and posts' the prices are still read on the Buy tab: that key posts from there)")
        AuctionMeshDB.cfg.buyMode = modeWas
        Se.pricedAt = {}
    end
    UI.tab = "SELL"
    check(Se:NextToPrice() == 2589, "Sell tab: it is priced at once")
    UI.tab = "BUY"
    AuctionMeshDB.flips[2589] = nil; bags[1] = nil; fire("BAG_UPDATE_DELAYED"); Se.prices[2589] = nil; Se.pricedAt = {}; Se.pending = nil
    UI.tab = "BUY"; UI:Render()
end

print("bank alt: the one character the addon is for; switched off on the others")
do
    local cfg, Do, Sw, flips = AuctionMeshDB.cfg, ns.Do, ns.Swarm, AuctionMeshDB.flips
    AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED"); MerchantFrame:Hide(); MailFrame:Hide(); UI:Close()
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    check(ns.charKey == "Tester-Realm" and AuctionMeshDB.chars["Tester-Realm"] ~= nil and AuctionMeshDB.chars["Tester-Realm"].name == "Tester",
        "the character that logs in is added to the list of your characters")
    check(cfg.bankAlt == nil and not ns.BankAlt() and not ns.Dormant(), "no bank alt until you pick one: the addon works on every character")
    AuctionMeshDB.chars["Banker-Realm"] = { name = "Banker", realm = "Realm", seen = GetServerTime() } -- another character that has logged in before
    -- Setup: one button; each click moves to the next choice, then back to every character
    UI:Open("HISTORY")
    local sp = AuctionMeshFrame.setup
    check(sp.bank ~= nil and sp.bank._text == "Use on: every character", "Setup has the button: 'Use on: every character' to begin with")
    sp.bank._scripts.OnClick(sp.bank)
    check(cfg.bankAlt == "Banker-Realm" and sp.bank._text == "Only on: Banker" and ns.Dormant() and not ns.BankAlt(),
        "a click picks the first of your characters, Banker: the addon is now for Banker only")
    check(UI.modeText == "OFF ON THIS CHARACTER" and strip(AuctionMeshFrame.status._text):find("^The addon is for Banker only%. On this character it is switched off"),
        "on this character (not Banker) the badge reads OFF ON THIS CHARACTER and the panel says why")

    -- SWITCHED OFF HERE: nothing by itself, anywhere
    UI:Close()
    local n0 = #sent
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(5)
    check(not UI:IsShown() and not Sw.active and not S.active and #sent == n0,
        "at the auction house the panel stays closed, the radar and the sniper do not start, and no request is sent")
    S:Start(); Sw:Start(true)
    check(not Sw.active and not S.active, "they cannot be started by hand there either")
    UI:Open("BUY"); UI.notice = nil; UI:Render()
    check(strip(AuctionMeshFrame.status._text):find("^SWITCHED OFF ON THIS CHARACTER: the addon is set to work on Banker only"),
        "opened by hand, the Buy tab says it is switched off here (it never looks stuck)")
    UI.tab = "SELL"; UI:Render()
    check(strip(AuctionMeshFrame.status._text):find("^SWITCHED OFF ON THIS CHARACTER"), "and so does the Sell tab")
    UI:Close()
    AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
    -- the mailbox: nothing is taken, and what the bank alt holds is not given up on
    flips[2592] = { kind = "FLIP", units = 5, cost = 30, sell = 90, at = GetServerTime() - 1000 }
    inbox[#inbox + 1] = { itemID = 2592, stackCount = 5 }
    local inboxWas = #inbox
    MailFrame:Show(); fire("MAIL_SHOW"); advance(4); fire("MAIL_INBOX_UPDATE"); advance(400); fire("MAIL_INBOX_UPDATE"); advance(4)
    check(#inbox == inboxWas and not UI:IsShown() and flips[2592] and flips[2592].units == 5 and flips[2592].missingSince == nil,
        "at the mailbox nothing is collected, the panel stays closed, and what the bank alt holds is not marked as not found")
    MailFrame:Hide(); fire("MAIL_CLOSED")
    table.remove(inbox)
    -- a vendor, even with something the addon bought in these bags
    ITEMS[2770] = ITEMS[2770] or { "Copper Ore", 5 }
    flips[2770] = { kind = "VENDOR", units = 12, cost = 3, sell = 5, at = GetServerTime() }
    bags[1] = { itemID = 2770, stackCount = 12 }; fire("BAG_UPDATE_DELAYED")
    MerchantFrame:Show(); fire("MERCHANT_SHOW"); advance(1)
    check(not UI:IsShown(), "at a vendor it stays closed too")
    MerchantFrame:Hide(); fire("MERCHANT_CLOSED")

    -- the badge: one click and the addon works on every character again; the bank alt is remembered
    UI:Open("BUY")
    local badge = AuctionMeshFrame.mode
    badge._scripts.OnClick(badge); UI.notice = nil; UI:Render()
    check(cfg.bankAlt == nil and cfg.bankAltLast == "Banker-Realm" and not ns.Dormant() and UI.modeText ~= "OFF ON THIS CHARACTER",
        "a click on the OFF badge: the addon works on every character again, and the bank alt is remembered")
    UI.tab = "HISTORY"; UI:Render()
    check(sp.bank._text == "Use on: every character", "(Setup: every character)")
    sp.bank._scripts.OnClick(sp.bank)
    check(cfg.bankAlt == "Banker-Realm", "the next click on Setup's button offers the remembered bank alt first")

    -- ON THE BANK ALT: everything works as it always did
    sp.bank._scripts.OnClick(sp.bank)
    check(cfg.bankAlt == "Tester-Realm" and sp.bank._text == "Only on: Tester (this one)" and ns.BankAlt() and not ns.Dormant(),
        "the next click picks this character: 'Only on: Tester (this one)'")
    UI.notice = nil; UI:Render()
    check(UI.modeText ~= "OFF ON THIS CHARACTER", "on the bank alt the badge is the ordinary mode badge")
    UI:Close()
    MerchantFrame:Show(); fire("MERCHANT_SHOW"); advance(1)
    check(UI:IsShown() and UI.tab == "SELL", "on the bank alt the panel opens at a vendor as before")
    local goldWas = gold
    Se:SellVendor(2770); advance(3)
    check(gold == goldWas + 60 and flips[2770] == nil, "and selling works: 12 Copper Ore to the vendor for 60c")
    MerchantFrame:Hide(); fire("MERCHANT_CLOSED"); UI:Close()
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(2)
    check(S.active == true and UI:IsShown(), "at the auction house the panel opens and the sniper runs, as before")
    -- switched to another character while the auction house is open, and back: stops, then starts at once
    Do.BankAlt("Banker-Realm")
    check(ns.Dormant() and not S.active and not Sw.active, "the bank alt moved to another character with the auction house open: everything stops here")
    Do.BankAlt("Tester-Realm")
    check(not ns.Dormant() and S.active == true, "moved back: the sniper starts at once, with no need to reopen the auction house")

    -- clean up: no bank alt
    Do.BankAlt(false); cfg.bankAltLast = nil
    check(cfg.bankAlt == nil and not ns.Dormant(), "set back to every character")
    flips[2592] = nil; ns.Journal:Dropped(2592, nil, "test"); ns.Journal:Dropped(2770, nil, "test")
    AuctionMeshDB.chars["Banker-Realm"] = nil
    UI.notice = nil
end

print("farmed or mined: what you did not buy, added by a click and posted as pure profit")
do
    local flips, J, St = AuctionMeshDB.flips, ns.Journal, ns.Store
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    for s2 = 1, 16 do bags[s2] = nil end
    S.verified = {}; LIST[2319], LIST[4234], LIST[2589], LIST[2770] = nil, nil, nil, nil
    ITEMS[9292] = { "Farm Ore", 4 }     -- a vendor pays 4c
    ITEMS[9293] = { "Dull Herb", 95 }   -- a vendor pays 95c, the auction house about the same
    LIST[9292] = { { 100, 40 }, { 101, 60 } }
    LIST[9293] = { { 96, 40 }, { 97, 60 } }
    St:Put(9292, 100, 100, GetServerTime()) -- the radar has seen both on the auction house
    St:Put(9293, 96, 100, GetServerTime())
    bags[1] = { itemID = 9292, stackCount = 20 }
    bags[2] = { itemID = 9293, stackCount = 10 }
    -- selling has nothing to do with what the radar is set to buy: gear and anything else that is not bound is offered too
    bags[3] = { itemID = 9500, stackCount = 1, quality = 3 }  -- gear that binds when equipped: the radar has no price for it
    bags[4] = { itemID = 9501, stackCount = 1, quality = 2 }  -- a green that nobody lists
    bags[5] = { itemID = 9502, stackCount = 3, quality = 1 }  -- a common item with no price on record
    bags[6] = { itemID = 9503, stackCount = 7, quality = 0 }  -- grey vendor junk
    ITEMS[9500], ITEMS[9501], ITEMS[9502], ITEMS[9503] = { "Blue Sword", 800 }, { "Green Belt", 300 }, { "Odd Thing", 1 }, { "Broken Fang", 2 }
    LIST[9500] = { { 5000, 1 }, { 5200, 2 } }
    LIST[9501] = {}
    fire("BAG_UPDATE_DELAYED")
    UI:Open("SELL"); UI.notice = nil; UI:Render()
    local function heads() return table.concat(headsText(), "\n") end
    local function looseRow(key)
        for i = 1, #frames do
            local f = frames[i]
            local l = rawget(f, "looseItem")
            if rawget(f, "detail") and f._shown and l and l.key == key then return f end
        end
    end
    check(heads():find("IN YOUR BAGS, NOT TRACKED (5)", 1, true) ~= nil,
        "the Sell tab lists everything in your bags that is not bound and that the addon did not buy")
    check(flips[9292] == nil and flips[9293] == nil and flips[9500] == nil, "nothing is tracked by itself")
    do
        local order = {}
        for _, l in ipairs(Se:Loose()) do order[#order + 1] = l.key end
        check(#order == 5 and (order[1] == 9500 or order[1] == 9501) and (order[2] == 9500 or order[2] == 9501) and order[3] == 9292 and order[4] == 9293 and order[5] == 9502,
            "gear and other uncommon-or-better items first (the radar has no price for them), then what has a price by its worth, then the rest")
        local sword = looseRow(9500)
        check(sword ~= nil and strip(sword.c[3]._text) == "?" and strip(sword.profit._text) == "price read on Add" and looseRow(9503) == nil,
            "an item with no price on record says its price is read when you add it; grey vendor junk is not offered")
    end
    local row = looseRow(9292)
    check(row ~= nil and strip(row.name._text) == "Farm Ore x20" and row.btn._text == "Add" and strip(row.profit._text) == "about 19s00c",
        "each has an Add button and what it is worth after the cut (20 x 95c)")
    local n0 = #posted
    row.btn._scripts.OnClick(row.btn)
    local f = flips[9292]
    check(f ~= nil and f.units == 20 and f.cost == 0 and f.farm == 20 and not f.unknownCost and #posted == n0,
        "Add: 20 Farm Ore are tracked as farmed, at a cost of nothing; nothing is posted by that click")
    check(J.list[#J.list].key == 9292 and J.list[#J.list].kind == "FARM", "the record says farmed, not bought")
    UI.notice = nil; UI:Render()
    do
        local h, cost = heads(), nil
        for i = 1, #frames do
            local fr = frames[i]
            if rawget(fr, "detail") and fr._shown and rawget(fr, "item") and fr.item.key == 9292 then cost = strip(fr.c[2]._text) end
        end
        check(h:find("TO POST (1)", 1, true) ~= nil and not h:find("FARMED", 1, true) and looseRow(9292) == nil and cost == "farmed",
            "it is under TO POST with everything else to post, not in a section of its own: its COST says farmed")
    end
    advance(3); UI:Render()
    local p = Se.prices[9292]
    check(p and p.price == 99, "its price is read at once and set like any post: 1c under the cheapest (99c)")
    local fr
    for i = 1, #frames do
        local x = frames[i]
        if rawget(x, "detail") and x._shown and rawget(x, "item") and x.item.key == 9292 then fr = x end
    end
    print("     " .. strip(fr.name._text) .. " | " .. strip(fr.c[2]._text) .. " | " .. strip(fr.profit._text) .. " | " .. strip(fr.detail._text))
    check(strip(fr.c[2]._text) == "farmed" and strip(fr.profit._text) == "+18s80c" and strip(fr.detail._text):find("^Farmed or mined: cost nothing  >  Sell 99c  >  %+94c each, all profit"),
        "the row says farmed where the cost would be, and all of what it sells for after the cut is profit (20 x 94c)")
    local ft = strip(AuctionMeshFrame.footer._text)
    check(ft:find("Farmed: + 18s80c", 1, true) ~= nil and ft:find("Bought, to sell:", 1, true) == nil,
        "the footer counts it apart from what you bought")
    -- posted with the ordinary Post click
    Se:Post(9292); advance(1)
    local L = AuctionMeshDB.listed[9292]
    check(#posted == n0 + 1 and posted[#posted].qty == 20 and posted[#posted].price == 99 and L and L.farm == true and L.cost == 0 and flips[9292] == nil,
        "Post puts all 20 up at 99c; the auction is still marked farmed")
    UI:Render()
    for i = 1, #frames do
        local x = frames[i]
        if rawget(x, "detail") and x._shown and rawget(x, "item") and x.item.key == 9292 then fr = x end
    end
    check(strip(fr.c[2]._text) == "farmed" and fr.item.action == "LISTED", "and its listed row says farmed too")
    -- never held back: even where a vendor pays more than the auction house, it is priced and can be posted
    row = looseRow(9293)
    row.btn._scripts.OnClick(row.btn)
    advance(3); UI:Render()
    local ph = Se.prices[9293]
    check(flips[9293] and flips[9293].farm == 10 and ph and ph.price == 95 and ph.hold == nil,
        "something a vendor pays more for (95c against 90c after the cut) is still priced, 1c under the cheapest: farmed items are never held back")
    local held = false
    for _, e in ipairs(Se:Entries()) do if e.key == 9293 and e.action == "HOLD" then held = true end end
    for i = 1, #frames do
        local x = frames[i]
        if rawget(x, "detail") and x._shown and rawget(x, "item") and x.item.key == 9293 then fr = x end
    end
    check(not held and fr.item.key == 9293 and strip(fr.detail._text):find("%(a vendor pays more: 95c each%)$") and fr.btn._text == "Post",
        "it is under FARMED OR MINED with its Post button, and the row says a vendor pays more: the choice is yours")
    -- gear that binds when equipped: added, priced from its own listing, posted like anything else
    row = looseRow(9500)
    row.btn._scripts.OnClick(row.btn)
    advance(3); UI:Render()
    local pg = Se.prices[9500]
    check(flips[9500] and flips[9500].farm == 1 and flips[9500].cost == 0 and pg and pg.price == 4999,
        "a blue sword you farmed: Add tracks it at no cost, and its price is read from its own listing (50s, so 49s99c)")
    -- a green nobody lists: no price is made up
    row = looseRow(9501)
    row.btn._scripts.OnClick(row.btn)
    advance(3); UI:Render()
    local pn = Se.prices[9501]
    local belt
    for i = 1, #frames do
        local x = frames[i]
        if rawget(x, "detail") and x._shown and rawget(x, "item") and x.item.key == 9501 then belt = x end
    end
    check(pn and pn.price == nil and tostring(pn.hold):find("^nobody else lists this item now") and belt ~= nil and strip(belt.state._text) == "No price to go by" and not belt.btn._shown,
        "an item nobody lists gets no invented price: its row says there is no price to go by, and there is no Post button")
    do
        local ready, total = Se:PriceProgress()
        check(total == 2 and ready == 2, ("it is not waited for: the count is of what can be priced (%d of %d ready)"):format(ready, total))
    end
    -- Shift + right-click on its row: stop tracking it (the Details sidebar had the button for this)
    do
        local herb
        for i = 1, #frames do
            local x = frames[i]
            if rawget(x, "detail") and x._shown and rawget(x, "item") and x.item.key == 9293 then herb = x end
        end
        IsShiftKeyDown = function() return false end
        herb._scripts.OnMouseUp(herb, "RightButton")
        check(flips[9293] ~= nil, "a plain right-click on a row does nothing")
        IsShiftKeyDown = function() return true end
        herb._scripts.OnMouseUp(herb, "RightButton")
        IsShiftKeyDown = function() return false end
        UI:Render()
        check(flips[9293] == nil and looseRow(9293) ~= nil, "Shift + right-click stops tracking the item: it is back under 'in your bags', and nothing was sold")
        UI.notice = nil
    end
    -- more of an item that is partly bought: the cost is spread over all of it
    flips[9292] = { kind = "FLIP", units = 10, cost = 40, sell = 99, at = GetServerTime() }
    bags[1] = { itemID = 9292, stackCount = 30 }; fire("BAG_UPDATE_DELAYED")
    check(Se:Farm(9292) == 20 and flips[9292].units == 30 and flips[9292].cost == 13 and flips[9292].farm == 20,
        "20 farmed added to 10 bought at 40c: one holding of 30 at 13c each")
    local mixed
    for _, e in ipairs(Se:Entries()) do if e.key == 9292 and e.action ~= "LISTED" then mixed = e end end
    check(mixed and mixed.farm == nil, "a holding that is part bought is listed with what you bought, not as farmed")
    -- clean up
    flips[9292], flips[9293], flips[9500], flips[9501], AuctionMeshDB.listed[9292] = nil, nil, nil, nil, nil
    for i = #J.list, 1, -1 do local k = J.list[i].key; if k == 9292 or k == 9293 or k == 9500 or k == 9501 then table.remove(J.list, i) end end
    LIST[9500], LIST[9501] = nil, nil; Se.prices[9500], Se.prices[9501] = nil, nil
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    LIST[9292], LIST[9293] = nil, nil
    Se.prices[9292], Se.prices[9293] = nil, nil
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
end

print("the Sell tab with many auctions: sold and listed fold into a line each, and the list has a scroll bar")
do
    local cfg = AuctionMeshDB.cfg
    local listedWas, ownWas, readWas, foldWas, salesWas = AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, AuctionMeshDB.sales
    local soldQtyWas, soldPayWas = S.ownSoldQty, S.ownSoldPay
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    -- 20 auctions: 4 have sold (their gold is on its way), 2 are undercut, 14 are simply listed
    AuctionMeshDB.listed, S.own, S.ownSoldQty, S.ownSoldPay = {}, {}, {}, {}
    AuctionMeshDB.sales = nil
    for i = 1, 20 do
        local k = 9700 + i
        ITEMS[k] = { "Auction Item " .. i, 1 }
        AuctionMeshDB.listed[k] = { qty = 10, price = 100, cost = 40, at = GetServerTime() }
        if i <= 4 then
            S.ownSoldQty[k] = 10
            S.ownSoldPay[#S.ownSoldPay + 1] = { amount = 950, due = GetTime() + 600 + i * 60, key = k }
        else
            S.own[k] = { [100] = 10 }
            if i <= 6 then ns.Store:Put(k, 90, 50, GetServerTime()) end -- someone lists these two cheaper
        end
    end
    S.ownRead = true
    cfg.fold = nil -- as on a new install
    UI:Open("SELL"); UI.notice = nil; UI.scroll = {}; UI:Render()
    local function heads() return headsText() end
    local function sumOf(text)
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "detail") and f._shown and rawget(f, "sect") and f.sect.head and strip(f.head._text):find(text, 1, true) then return f, strip(f.detail._text or "") end
        end
    end
    local hs = table.concat(heads(), "\n")
    print("     " .. hs:gsub("\n", "\n     "))
    check(hs:find("[-] UNDERCUT (2)", 1, true) and not hs:find("SOLD", 1, true) and hs:find("[+] LISTED (14)", 1, true),
        "what needs a decision is open (2 undercut); the 14 simply listed are folded into a line; the 4 that sold are on the Sold tab")
    check(#rowsText() == 2, "so the list is 2 rows and two headings, not 20 rows")
    local listedHead0, listedSum = sumOf("[+] LISTED")
    print("     " .. listedSum)
    check(listedSum == "nobody is cheaper: + 1g33s if they sell", "the folded heading says what is in it: what the listings bring if they sell")
    check(not AuctionMeshFrame.scrollBar._shown, "everything fits: no scroll bar")
    -- a click on a heading opens it; that is remembered
    local listedHead = sumOf("[+] LISTED")
    listedHead._scripts.OnMouseUp(listedHead, "LeftButton")
    check(cfg.fold.LISTED == false and UI.scrollMost and UI.scrollMost > 0 and AuctionMeshFrame.scrollBar._shown,
        "a click on the LISTED heading opens it: the list is longer than the panel now, and the scroll bar appears")
    -- the scroll bar moves the list; the wheel still does
    local sb = AuctionMeshFrame.scrollBar
    local first0 = rowsText()[1]
    sb._scripts.OnValueChanged(sb, 5)
    check(UI.scroll.SELL == 5 and rowsText()[1] ~= first0, "dragging the bar scrolls the list")
    AuctionMeshFrame._scripts.OnMouseWheel(AuctionMeshFrame, -1)
    check(UI.scroll.SELL == 8, "the mouse wheel scrolls it too, three rows a notch")
    sb._scripts.OnValueChanged(sb, 0)
    -- closing it again
    local openListed = sumOf("[-] LISTED")
    openListed._scripts.OnMouseUp(openListed, "LeftButton")
    check(cfg.fold.LISTED == true and #rowsText() == 2 and not AuctionMeshFrame.scrollBar._shown, "a click on an open heading folds it again")
    -- THE SOLD TAB: what has sold, apart from what is still to sell
    do
        local J = ns.Journal
        local t = J:Bought(9790, "Paid Ore", "FLIP", 10, 40, 100)
        ITEMS[9790] = { "Paid Ore", 1 }
        t.sold, t.got, t.soldAt, t.soldPrice, t.doneAt = 10, 950, GetServerTime() - 600, 100, GetServerTime() - 600
        local tab = AuctionMeshFrame.tabSold
        tab._scripts.OnClick(tab)
        local hd = headsText()
        local rowsP = plainRows()
        print("     " .. table.concat(hd, "\n     "))
        for _, l in ipairs(rowsP) do print("     " .. l) end
        check(UI.tab == "SOLD" and tab._text == "Sold (4)" and hd[1] == "SOLD, GOLD ON ITS WAY (4) | COST / SOLD AT / SPREAD / GOLD ARRIVES / PROFIT"
            and hd[#hd]:find("^PAID, LAST 24 HOURS %(%d+%) | COST / SOLD AT / SPREAD / WHEN / PROFIT$"),
            "the Sold tab: what has sold and is on its way (4), then what was paid in the last 24 hours, each with its SPREAD")
        check(rowsP[1] == "Auction Item 1 x10 | 40c / 1s00c / +150% / in 11 min | +5s50c" and rowsP[4]:find("^Auction Item 4 x10 | 40c / 1s00c / %+150%% / in 14 min"),
            "each sold auction: what it cost, what it sold at, the spread between the two, when its gold arrives, and the profit")
        local paidRow
        for _, l in ipairs(rowsP) do if l:find("^Paid Ore x10") then paidRow = l end end
        check(paidRow == "Paid Ore x10 | 40c / 1s00c / +150% / 10 min ago | +5s50c", "a sale already paid: the same figures, and how long ago")
        do  -- SPREAD sorts like any column; what was farmed has no ratio and comes above every ratio
            local t2 = J:Bought(9791, "Thin Ore", "FLIP", 10, 80, 100)
            ITEMS[9791] = { "Thin Ore", 1 }
            t2.sold, t2.got, t2.soldAt, t2.soldPrice, t2.doneAt = 10, 950, GetServerTime() - 1200, 100, GetServerTime() - 1200
            local t3 = J:Bought(9792, "Dug Ore", "FARM", 10, 0, 100)
            ITEMS[9792] = { "Dug Ore", 1 }
            t3.sold, t3.got, t3.soldAt, t3.soldPrice, t3.doneAt = 10, 950, GetServerTime() - 1800, 100, GetServerTime() - 1800
            UI:SortBy("SOLD", 3)
            local order = {}
            for _, l in ipairs(plainRows()) do
                local n = l:match("^(%a+ Ore) x10")
                if n then order[#order + 1] = n .. " " .. (l:match("/ ([^/]+) / [^/]+ |") or "?") end
            end
            print("     by SPREAD: " .. table.concat(order, ", "))
            check(table.concat(order, ", "):find("Dug Ore all profit, Paid Ore +150%, Thin Ore +25%", 1, true) ~= nil and headsText()[1]:find("SPREAD v", 1, true),
                "sorted by SPREAD: farmed (all profit) first, then the widest spread down to the narrowest")
            UI:SortBy("SOLD", 3)
            order = {}
            for _, l in ipairs(plainRows()) do local n = l:match("^(%a+ Ore) x10"); if n then order[#order + 1] = n end end
            check(table.concat(order, ", "):find("Thin Ore, Paid Ore, Dug Ore", 1, true) ~= nil, "a second click: the narrowest first")
            UI:SortBy("SOLD", 0)
            for i = #J.list, 1, -1 do if J.list[i] == t2 or J.list[i] == t3 then table.remove(J.list, i) end end
            ITEMS[9791], ITEMS[9792] = nil, nil
            UI:Render()
        end
        check(strip(AuctionMeshFrame.status._text):find("^On its way: %+ 38s00c, the next in 11 min      Profit on what was paid in the last 24 hours: "),
            "the line at the top adds them up: the gold on its way, and the profit on what was paid")
        -- SORTING: a click on a column's caption
        UI:SortBy("SOLD", 4)
        rowsP = plainRows()
        hd = headsText()
        check(rowsP[1]:find("^Auction Item 4 x10") and rowsP[4]:find("^Auction Item 1 x10") and hd[1]:find("GOLD ARRIVES v", 1, true),
            "sorted by GOLD ARRIVES: the last to arrive first, and the caption is marked")
        UI:SortBy("SOLD", 4)
        rowsP = plainRows()
        check(rowsP[1]:find("^Auction Item 1 x10") and headsText()[1]:find("GOLD ARRIVES ^", 1, true), "a second click turns the order round")
        UI:SortBy("SOLD", 0)
        check(UI.sortBy.SOLD == nil and not headsText()[1]:find(" v", 1, true), "a click on the heading's name puts the usual order back")
        -- the click itself: where the mouse is decides the column
        local headRow
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "detail") and f._shown and rawget(f, "sect") and f.sect.head and f.sect.head:find("^SOLD, GOLD") then headRow = f end
        end
        rawset(headRow, "GetLeft", function() return 100 end)
        rawset(headRow, "GetEffectiveScale", function() return 1 end)
        GetCursorPosition = function() return 100 + 600, 0 end -- over the PROFIT caption
        check(UI.ColumnAt(headRow) == 5, "the mouse over the caption at the right is the profit column")
        headRow._scripts.OnMouseUp(headRow, "LeftButton")
        check(UI.sortBy.SOLD and UI.sortBy.SOLD.col == 5 and UI.sortBy.SOLD.desc == true, "a click there sorts by profit, largest first")
        GetCursorPosition = function() return 100 + 340, 0 end -- over COST
        check(UI.ColumnAt(headRow) == 2, "(the mouse over COST is column 2)")
        GetCursorPosition = function() return 100 + 60, 0 end -- over the heading's name
        headRow._scripts.OnMouseUp(headRow, "LeftButton")
        check(UI.sortBy.SOLD == nil, "a click on the heading's name clears the sort")
        GetCursorPosition = nil
        rawset(headRow, "GetLeft", nil); rawset(headRow, "GetEffectiveScale", nil)
        for i = #J.list, 1, -1 do if J.list[i] == t then table.remove(J.list, i) end end
        ITEMS[9790] = nil
        UI.tab = "SELL"; UI:Render()
    end
    check(strip(AuctionMeshFrame.status._text):find("auction%(s%) listed") == nil, "the status lines no longer repeat how many auctions are listed")
    for i = 1, 20 do ITEMS[9700 + i] = nil end
    AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, AuctionMeshDB.sales = listedWas, ownWas, readWas, foldWas, salesWas
    S.ownSoldQty, S.ownSoldPay = soldQtyWas, soldPayWas
    UI.tab = "BUY"; UI.scroll = {}; UI.notice = nil; UI:Render()
end

print("an undercut auction: relist or hold, worked out")
do
    local cfg = AuctionMeshDB.cfg
    local St = ns.Store
    local listedWas, ownWas, readWas, foldWas, rowsWas = AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.lastRows
    local soldQtyWas, soldPayWas, feeBackWas, idsWas = S.ownSoldQty, S.ownSoldPay, cfg.feeBack, S.ownIds
    local realRate, realTrend, realGoldRate = St.Rate, St.Trend, Se.GoldRate
    local rate, trend, rho = nil, nil, 0
    St.Rate = function(_, key) if key == 9801 then return rate, 3600 end return realRate(St, key) end
    St.Trend = function(_, key, ...) if key == 9801 then return trend end return realTrend(St, key, ...) end
    Se.GoldRate = function() return rho, 9 end -- what free gold earns an hour, set by each case
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    ITEMS[9801] = { "Stuck Ore", 1 }
    -- 30 of yours listed at 1s00c two hours ago (cost 40c each, fee 30c, 10 hours left): someone lists cheaper
    AuctionMeshDB.listed, S.own, S.ownSoldQty, S.ownSoldPay = {}, {}, {}, {}
    AuctionMeshDB.listed[9801] = { qty = 30, price = 100, cost = 40, at = GetServerTime() - 2 * 3600, fee = 30, plan = 100 }
    S.own[9801] = { [100] = 30 }
    S.ownIds = { [9801] = { { id = 77, qty = 30, price = 100, ends = GetTime() + 36000 } } }
    S.ownRead = true
    cfg.feeBack = true
    St:Put(9801, 90, 500, GetServerTime())
    local e = { key = 9801, action = "LISTED", count = 30, live = 30, f = { kind = "FLIP", cost = 40, sell = 100 }, listed = AuctionMeshDB.listed[9801] }
    local function reset() Se.ucCache, Se.ucSeen, Se.ucLogged, Se.wantRows = nil, nil, nil, nil end
    local function advice()
        Se.ucCache = nil
        local r = Se:Undercut(e)
        return r, strip(r.why), strip(r.text), strip(r.brief)
    end
    local function listing(rows) S.lastRows[9801] = { rows = rows, at = GetTime() } end
    local CHEAP = { { price = 90, qty = 20 }, { price = 95, qty = 40 }, { price = 110, qty = 200 } } -- 60 units under yours
    gold = 5000
    reset()
    -- its listing has not been read: it is asked for
    S.lastRows = {}
    local a, why, text, brief = advice()
    check(a.rec == "read" and a.word == "READING" and Se.wantRows[9801] == true, "with no full listing on record it waits for one: READING, and the listing is asked for")
    -- no sale rate: nothing to work it out from
    listing(CHEAP); rate = nil; reset()
    a, why, text, brief = advice()
    check(a.rec == "hold" and a.ahead == 60 and a.low == 90 and a.mean == 106 and a.repost == 89 and brief == "sale rate not known yet: cannot be worked out",
        "60 cheaper units ahead (others ask 1s06c on average) and no sale rate measured: HOLD, it cannot be worked out yet")

    -- THE SUM. 120 sell an hour: the 60 ahead are gone in 30 minutes, then yours.
    --   hold:   30 x (95c - 40c) = 16s50c                (it sells well inside the 10 hours)
    --   relist: 30 x (84c - 40c) = 13s20c, less the 30c fee lost with the cancel = 12s90c
    rate = 120; rho = 0; reset()
    a, why, text, brief = advice()
    print("     " .. text)
    check(a.rec == "hold" and a.evHold == 1650 and a.evRelist == 1290 and brief == "holding is worth 3s60c more",
        "120 sell an hour: holding is worth 16s50c, a relist 12s90c. HOLD, worth 3s60c more")
    check(a.untilT and math.abs((a.untilT - GetTime()) - 1800) < 2, "and the hold counts down the 30 minutes until your first unit should sell")
    check(text:find("Hold = + 16s50c (30 sell at 1s00c, your turn in 30 min: + 16s50c)", 1, true)
        and text:find("Relist = + 12s90c (30 sell at 89c, first in line: + 13s20c; fees lost 30c)", 1, true)
        and text:find("Your call: Cancel on this row relists it anyway.", 1, true),
        "the sums are behind the mouse: what each choice brings, the fee a relist loses, and how to overrule it")
    check(a.pl == 1650 and a.plFees == 0 and a.plRelist == 1290 and a.plRelistFees == 30 and text:find("Following it leaves you + 16s50c. ", 1, true),
        "the profit of the advised choice: holding leaves 16s50c with no fee lost (a relist would leave 12s90c, the 30c fee of this auction gone)")

    -- THE WAIT HAS A PRICE once it is known what your gold earns. 20 sell an hour: 3 hours to your turn.
    --   no rate for your gold yet: hold 16s50c against 12s90c: HOLD
    --   your gold earns 6% an hour: hold 16s50c - 6% x 28s50c x 3.75h = 10s09c; relist 12s90c - 6% x 25s20c x 0.75h = 11s77c: RELIST
    rate = 20; rho = 0; reset()
    a, why, text, brief = advice()
    check(a.rec == "hold" and a.evHold == 1650 and a.evRelist == 1290, "20 sell an hour, and nothing known about what your gold earns: the wait is free, so HOLD (16s50c against 12s90c)")
    rho = 0.06; reset()
    a, why, text, brief = advice()
    print("     " .. text)
    check(a.rec == "relist" and math.abs(a.evHold - 1008.75) < 0.01 and math.abs(a.evRelist - 1176.6) < 0.01 and brief == "relist is worth 1s68c more",
        "the same auction when your gold earns 6% an hour: three hours of waiting cost more than the lower price. RELIST, worth 1s68c more")
    check(text:find("the wait of 4 hours costs 6s41c", 1, true) and text:find("your free gold earns 6.0% an hour", 1, true)
        and text:find("^RELIST at 89c: a relist is worth %+ 11s77c, holding %+ 10s09c: 1s68c more%. Press Cancel on this row %(twice%)"),
        "the advice says what the wait costs, and what to press")
    check(a.pl == 1290 and a.plFees == 30 and text:find("Following it leaves you + 12s90c, after 30c in fees lost. ", 1, true),
        "the profit shown for a RELIST is at the lower price and less the fee lost with the cancel: 12s90c, not the 16s50c of the price it is listed at (the wait decides, but is not gold lost)")
    rho = 0

    -- IT RUNS OUT FIRST. 5 sell an hour: 12 hours to your turn, 10 left. Holding means posting it again once: one fee lost.
    --   hold: 16s50c - 30c = 16s20c; relist: 12s90c. HOLD: the fee is cheaper than the price cut.
    rate = 5; reset()
    a, why, text, brief = advice()
    print("     " .. text)
    check(a.rec == "hold" and a.hold.expiries == 1 and a.evHold == 1620 and a.evRelist == 1290 and text:find("fees lost 30c (it runs out 1 time first)", 1, true),
        "5 sell an hour: it runs out once before your turn. One fee lost (16s20c) still beats cutting the price (12s90c): HOLD")
    check(a.pl == 1620 and a.plFees == 30, "and the profit shown for that HOLD has the fee of the auction that runs out taken off: 16s20c")

    -- A BIG PRICE CUT IS NEVER WORTH IT ON ITS OWN. Cheaper units at 60c: a relist would go to 59c.
    --   hold: wait for the 60 to sell, then yours at 1s00c: 16s20c; relist at 59c: 30 x (56c - 40c) - 30c = 4s50c
    listing({ { price = 60, qty = 60 }, { price = 110, qty = 200 } }); reset()
    a, why, text, brief = advice()
    check(a.rec == "hold" and a.repost == 59 and a.evRelist == 450 and a.evHold == 1620 and brief == "holding is worth 11s70c more",
        "cheaper units at 60c: a relist at 59c is worth 4s50c, holding 16s20c. HOLD, by 11s70c")
    -- a falling price takes value off the hold
    trend = -0.8; reset() -- the item lost 80% in 24 hours
    a = advice()
    check(a.rec == "hold" and math.abs(a.hold.sellAt - 60) < 0.001 and math.abs(a.evHold - (30 * (57 - 40) - 30)) < 0.001, "an item whose price is falling fast: by the time your turn comes its price is counted lower (60c), and the hold is worth that much less")
    trend = nil
    listing(CHEAP)

    -- THE QUEUE DOES NOT MOVE. The listing read again ten minutes later: still 60 ahead (as many listed under you as were bought).
    rate = 20; reset()
    advice()
    advance(700)
    listing(CHEAP)
    St:Put(9801, 90, 500, GetServerTime())
    a, why, text, brief = advice()
    print("     " .. a.word .. ": " .. why)
    check(a.rec == "relist" and a.watched == true and a.sells == 0 and a.hold.never == true and brief == "the queue is not moving; relist is worth 12s90c",
        "read again ten minutes later and the 60 ahead are still 60: holding does not sell. RELIST")
    -- ...and when it does move, that measured speed is what the sum uses
    advance(700)
    listing({ { price = 90, qty = 10 }, { price = 95, qty = 26 }, { price = 110, qty = 200 } }) -- 36 ahead: 24 gone
    St:Put(9801, 90, 500, GetServerTime())
    a, why, text, brief = advice()
    check(a.watched == true and math.abs(a.sells - 24 / (1400 / 3600)) < 0.5 and text:find("they have gone down by 62 an hour since the listing was first read", 1, true),
        "then the units ahead go from 60 to 36: the sum uses how fast they really went (62 an hour), not the item's average")

    -- no gold for the new fee
    rate = 20; rho = 0.06; gold = 5; reset(); listing(CHEAP)
    a, why = advice()
    check(a.rec == "hold" and why:find("needs a posting fee of 30c first and you have 5c", 1, true), "a relist that is worth more but cannot be paid for: HOLD, and it says so")
    gold = 5000
    -- where fees never come back, the new fee is the cost of a relist
    cfg.feeBack = false; reset()
    a = advice()
    check(a.relist.feeLost == 30 and a.rec == "relist", "where posting fees never come back, the new fee is the cost of a relist (and it is counted)")
    check(a.plFees == 60 and a.pl == a.relist.fromSales - 60, "there the profit shown has both fees off: the one already paid and the new one")
    cfg.feeBack = true
    rho = 0

    -- the log has the sums
    do
        local logLines, realLog = {}, ns.Log
        ns.Log = function(fmt, ...) local ok, l = pcall(string.format, fmt, ...); logLines[#logLines + 1] = ok and l or tostring(fmt); return realLog(fmt, ...) end
        rate = 120; reset(); listing(CHEAP)
        advice()
        ns.Log = realLog
        local found
        for _, l in ipairs(logLines) do if l:find("^ADVICE 9801: HOLD") and l:find("HOLD 1650 = sales 1650 %- fees 0 %- wait 0") and l:find("RELIST at 89: 1290 = sales 1320 %- fees 30 %- wait 0") then found = l end end
        print("     " .. tostring(found))
        check(found ~= nil, "the log has the advice with its sums")
    end

    -- ON THE SELL TAB: the row carries the advice, the heading counts it, the hold counts down and is worked out again when its time is up
    local function wait(secs)
        while secs > 0 do
            local step = math.min(120, secs)
            advance(step); secs = secs - step
            St:Put(9801, 90, 500, GetServerTime())
        end
    end
    cfg.fold = nil; rate = 120; rho = 0; reset(); listing(CHEAP)
    UI:Open("SELL"); UI.notice = nil; UI:Render()
    local row
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "detail") and f._shown and rawget(f, "item") and f.item.key == 9801 then row = f end
    end
    local hs = table.concat(headsText(), "\n")
    print("     " .. strip(row.name._text) .. " | " .. strip(row.c[4]._text) .. " | " .. strip(row.brief._text))
    check(hs:find("[-] UNDERCUT (1) | QTY / WHY /  / ADVICE / P / L", 1, true) and row and (strip(row.c[4]._text) == "HOLD 30:00" or strip(row.c[4]._text):find("^HOLD 29:5%d$"))
        and row.brief._shown and strip(row.brief._text) == "holding is worth 3s60c more" and row.btn._text == "Cancel" and strip(row.detail._text):find("^HOLD: holding is worth"),
        "on the Sell tab the row says HOLD with the time left and, in a few words, what the sum came to; Cancel is still there to overrule it")
    check(strip(row.profit._text) == "+16s50c", "its P / L is what holding leaves: + 16s50c")
    wait(60); UI:Render()
    check(strip(row.c[4]._text):find("^HOLD 28:5%d$") and UI.holdTick == true, "a minute later it reads 28:5x: it counts down by itself")
    -- the time runs out and nothing ahead of you has sold: the listing is read again, and the sum now says relist
    LIST[9801] = { { 90, 20 }, { 95, 40 }, { 110, 200 } }
    Se.pricedAt = {}
    local n0 = 0
    for i = 1, #sent do if sent[i] == "search9801" then n0 = n0 + 1 end end
    wait(1760)
    local n1 = 0
    for i = 1, #sent do if sent[i] == "search9801" then n1 = n1 + 1 end end
    Se.ucCache = nil; UI:Render()
    print("     " .. strip(row.c[4]._text) .. " | " .. strip(row.brief._text))
    check(n1 > n0 and strip(row.c[4]._text) == "RELIST" and strip(row.brief._text):find("^the queue is not moving; relist is worth"),
        "when its time is up the listing is read again by itself; the 60 ahead have not moved, so the sum now says RELIST")
    print("     P / L: " .. strip(row.profit._text))
    check(strip(row.profit._text) == "+12s90c", "and its P / L is now what the relist leaves, the lost fee and the lower price included: + 12s90c (it said + 16s50c)")
    -- the listing is read on the Sell tab when it is missing
    S.lastRows[9801] = nil; reset(); Se.pricedAt = {}
    St:Put(9801, 90, 500, GetServerTime())
    UI:Render()
    check(Se.wantRows and Se.wantRows[9801] == true and Se:NextToPrice() == 9801, "with no listing on record it is asked for on the Sell tab")
    Se.pricedAt = {}
    advance(6); UI:Render()
    check(S.lastRows[9801] ~= nil and #S.lastRows[9801].rows == 3, "the listing is read, and the sum has its figures")

    -- WHAT YOUR GOLD EARNS: from your own finished flips
    do
        Se.GoldRate = realGoldRate
        Se.goldRate = nil
        local J = ns.Journal
        local keep = J.list
        J.list = {}
        local tnow = GetServerTime()
        check(select(1, Se:GoldRate()) == 0, "with no finished flips the wait is not charged for")
        for i = 1, 6 do
            J.list[i] = { id = i, key = 9900 + i, name = "Flip " .. i, kind = "FLIP", qty = 10, cost = 100, at = tnow - 48 * 3600, doneAt = tnow - 3600, sold = 10, vend = 0, lost = 0, got = 1500 }
        end
        Se.goldRate = nil
        local capital = (ns.Gold:Cash())
        for _, Lr in pairs(AuctionMeshDB.listed or {}) do capital = capital + math.floor((Lr.price or 0) * 0.95) * (Lr.qty or 0) end
        local got, nflips = Se:GoldRate()
        local want = (6 * 500) / capital / 48
        print(("     6 flips made 30s00c in 48 hours on %d copper: %.4f%% an hour"):format(capital, got * 100))
        check(nflips == 6 and math.abs(got - math.min(0.2, want)) < 1e-9, "six finished flips: their profit, over all you have, per hour of the stretch they cover")
        J.list = keep
        Se.goldRate = nil
    end

    ITEMS[9801] = nil; LIST[9801] = nil
    St.Rate, St.Trend, Se.GoldRate = realRate, realTrend, realGoldRate
    AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.lastRows = listedWas, ownWas, readWas, foldWas, rowsWas
    S.ownSoldQty, S.ownSoldPay, cfg.feeBack, S.ownIds = soldQtyWas, soldPayWas, feeBackWas, idsWas
    reset()
    gold = 900
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
end

print("cancelling one undercut auction leaves the Cancel buttons of the others")
do
    local cfg = AuctionMeshDB.cfg
    local St = ns.Store
    local listedWas, ownWas, readWas, foldWas, rowsWas, idsWas = AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.lastRows, S.ownIds
    local soldQtyWas, soldPayWas = S.ownSoldQty, S.ownSoldPay
    local numWas, infoWas, cancelWas = C_AuctionHouse.GetNumOwnedAuctions, C_AuctionHouse.GetOwnedAuctionInfo, C_AuctionHouse.CancelAuction
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    Enum.AuctionStatus = { Active = 0, Sold = 1 }
    AuctionMeshDB.listed = {}
    local owned = {}
    for i = 1, 3 do
        local k = 9870 + i
        ITEMS[k] = { "Cut Item " .. i, 1 }
        AuctionMeshDB.listed[k] = { qty = 10, price = 100, cost = 40, plan = 100, fee = 10, at = GetServerTime() - 3600 }
        owned[#owned + 1] = { auctionID = 8800 + i, itemKey = { itemID = k }, status = 0, quantity = 10, buyoutAmount = 100, timeLeftSeconds = 30000 }
        LIST[k] = { { 90, 50 }, { 110, 300 } }
        St:Put(k, 90, 350, GetServerTime())
    end
    C_AuctionHouse.GetNumOwnedAuctions = function() return #owned end
    C_AuctionHouse.GetOwnedAuctionInfo = function(i) return owned[i] end
    local cancelled = {}
    C_AuctionHouse.CancelAuction = function(id)
        cancelled[#cancelled + 1] = id
        -- as the game does: the auction leaves your list, the list is announced as changed, and the cancel is confirmed
        for i = #owned, 1, -1 do if owned[i].auctionID == id then table.remove(owned, i) end end
        C_Timer.After(0.2, function() fire("OWNED_AUCTIONS_UPDATED"); fire("AUCTION_CANCELED", id) end)
    end
    S:ReadOwned()
    cfg.fold = nil; Se.ucCache, Se.ucSeen, Se.wantRows, Se.note, Se.cancelArm, Se.cancelling = nil, nil, nil, nil, nil, nil
    UI:Open("SELL"); UI.notice = nil; UI:Render()
    local function rowOf(key)
        for i = 1, #frames do local fr = frames[i]; if rawget(fr, "detail") and fr._shown and rawget(fr, "item") and fr.item.key == key then return fr end end
    end
    local function buttons()
        local out = {}
        for i = 1, 3 do
            local r = rowOf(9870 + i)
            out[#out + 1] = r and ((r.item.action == "LISTED" and r.btn._shown) and r.btn._text or ("-" .. tostring(r.item.action))) or "gone"
        end
        return table.concat(out, " ")
    end
    print("     before: " .. buttons())
    check(buttons() == "Cancel Cancel Cancel", "three undercut auctions, each with its Cancel button")
    local r1 = rowOf(9871)
    r1.btn._scripts.OnClick(r1.btn); UI:Render()
    r1 = rowOf(9871)
    r1.btn._scripts.OnClick(r1.btn); UI:Render()
    print("     just after the second click: " .. buttons())
    for step = 1, 6 do
        advance(1); St:Put(9872, 90, 350, GetServerTime()); St:Put(9873, 90, 350, GetServerTime()); UI:Render()
        print(("     %ds after: %s"):format(step, buttons()))
    end
    check(#cancelled == 1 and cancelled[1] == 8801, "the first one is cancelled")
    local b = buttons()
    check(b:find("Cancel Cancel$") ~= nil, "the other two still have their Cancel buttons (" .. b .. ")")
    -- THE GAME'S LIST IS EMPTY FOR A MOMENT after a cancel (it announces "your auctions changed" before it has them again)
    do
        local queryWas = C_AuctionHouse.QueryOwnedAuctions
        local blank, asked = false, 0
        C_AuctionHouse.GetNumOwnedAuctions = function() return blank and 0 or #owned end
        C_AuctionHouse.QueryOwnedAuctions = function(...)
            asked = asked + 1; blank = false
            C_Timer.After(0.1, function() fire("OWNED_AUCTIONS_UPDATED") end)
        end
        C_AuctionHouse.CancelAuction = function(id)
            cancelled[#cancelled + 1] = id
            for i = #owned, 1, -1 do if owned[i].auctionID == id then table.remove(owned, i) end end
            blank = true
            C_Timer.After(0.2, function() fire("OWNED_AUCTIONS_UPDATED"); fire("AUCTION_CANCELED", id) end)
        end
        -- a deal is on screen too: on the Sell tab your own auctions are still read at once
        local verWas = S.verified
        S.verified = { [424242] = { key = 424242, commodity = true, units = 1, cost = 10, price = 10, sell = 20, profit = 8, at = GetTime(), expires = GetTime() + 600 } }
        local r2 = rowOf(9872)
        r2.btn._scripts.OnClick(r2.btn); UI:Render()
        r2 = rowOf(9872)
        r2.btn._scripts.OnClick(r2.btn); UI:Render()
        advance(0.5); St:Put(9873, 90, 350, GetServerTime()); UI:Render()
        print("     0.5s after, the game's list empty: " .. buttons())
        check(buttons():find("Cancel$") ~= nil and rowOf(9873).item.action == "LISTED", "while the game's list is empty for a moment the third auction keeps its Cancel button")
        for step = 1, 4 do
            advance(1); St:Put(9873, 90, 350, GetServerTime()); UI:Render()
        end
        b = buttons()
        print("     4s after: " .. b .. "  (own auctions asked for " .. asked .. " time(s))")
        check(#cancelled == 2 and cancelled[2] == 8802 and asked >= 1 and b:find("Cancel$") ~= nil and S.ownIds[9873] and #S.ownIds[9873] == 1,
            "the list is asked for again, at once, also with a deal on screen: the third auction is still yours and can still be cancelled")
        local inEnded = false
        for _, l in ipairs(rowsText()) do if l:find("Cut Item 3", 1, true) and l:find("mailbox", 1, true) then inEnded = true end end
        check(not inEnded, "it is not shown as ended")
        S.verified = verWas
        C_AuctionHouse.QueryOwnedAuctions = queryWas
    end
    for i = 1, 3 do ITEMS[9870 + i] = nil; LIST[9870 + i] = nil; AuctionMeshDB.flips[9870 + i] = nil; ns.Journal:Dropped(9870 + i, nil, "test") end
    C_AuctionHouse.GetNumOwnedAuctions, C_AuctionHouse.GetOwnedAuctionInfo, C_AuctionHouse.CancelAuction = numWas, infoWas, cancelWas
    AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.lastRows, S.ownIds = listedWas, ownWas, readWas, foldWas, rowsWas, idsWas
    S.ownSoldQty, S.ownSoldPay = soldQtyWas, soldPayWas
    Se.ucCache, Se.ucSeen, Se.wantRows, Se.note, Se.cancelArm, Se.cancelling = nil, nil, nil, nil, nil, nil
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
end

print("an auction the auction house no longer lists is on the Sold tab, not the Sell tab")
do
    local cfg = AuctionMeshDB.cfg
    local listedWas, ownWas, readWas, foldWas, idsWas = AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.ownIds
    local soldQtyWas, soldPayWas = S.ownSoldQty, S.ownSoldPay
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    ITEMS[9880], ITEMS[9881] = { "Gone Item", 1 }, { "Still Item", 1 }
    AuctionMeshDB.listed = {
        [9880] = { qty = 10, price = 100, cost = 40, plan = 100, fee = 10, at = GetServerTime() - 3600 },
        [9881] = { qty = 10, price = 100, cost = 40, plan = 100, fee = 10, at = GetServerTime() - 3600 },
    }
    S.own, S.ownIds, S.ownRead = { [9881] = { [100] = 10 } }, { [9881] = { { id = 8890, qty = 10, price = 100 } } }, true
    S.ownSoldQty, S.ownSoldPay = {}, {}
    cfg.fold = { LISTED = false }
    UI:Open("SELL"); UI.notice = nil; UI:Render()
    local sell = table.concat(headsText(), "\n") .. "\n" .. table.concat(rowsText(), "\n")
    print("     Sell: " .. table.concat(headsText(), "  ||  "))
    check(sell:find("Still Item", 1, true) ~= nil and not sell:find("Gone Item", 1, true) and not sell:find("ENDED", 1, true),
        "the Sell tab lists the auction that is still up, and has no ENDED section")
    UI:Open("SOLD"); UI:Render()
    local hd, line = headsText(), nil
    for _, l in ipairs(plainRows()) do if l:find("^Gone Item x10") then line = l end end
    print("     Sold: " .. table.concat(hd, "  ||  "))
    print("     " .. tostring(line))
    local at
    for i, h in ipairs(hd) do if h:find("^ENDED, CHECK A MAILBOX %(1%) | COST / LISTED AT / SPREAD / WHERE / IF SOLD$") then at = i end end
    check(at == 2 and line == "Gone Item x10 | 40c / 1s00c / +150% / mailbox | +5s50c",
        "the Sold tab has it, under ENDED, CHECK A MAILBOX: what it cost, what it was listed at, the spread, and the profit if it sold")
    ITEMS[9880], ITEMS[9881] = nil, nil
    AuctionMeshDB.flips[9880], AuctionMeshDB.flips[9881] = nil, nil
    AuctionMeshDB.listed, S.own, S.ownRead, cfg.fold, S.ownIds = listedWas, ownWas, readWas, foldWas, idsWas
    S.ownSoldQty, S.ownSoldPay = soldQtyWas, soldPayWas
    UI:Open("SELL"); UI:Render()
end

print("sorting by a column on the Buy and Sell tabs")
do
    local flips = AuctionMeshDB.flips
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    local function deal(key, profit, sell, rate)
        return { key = key, kind = "FLIP", units = 10, cost = 100, sell = sell, profit = profit, rate = rate, deposit = 0, buys = {}, counts = {}, commodity = true, at = GetTime(), born = GetTime(), from = "me" }
    end
    ITEMS[9851], ITEMS[9852], ITEMS[9853] = { "Sort A", 1 }, { "Sort B", 1 }, { "Sort C", 1 }
    S.verified = { [9851] = deal(9851, 300, 50, 10), [9852] = deal(9852, 900, 20, 90), [9853] = deal(9853, 600, 80, 40) }
    UI.sortBy = {}
    UI:Open("BUY"); UI.notice = nil; UI.flashUntil, UI.flashKey, UI.flashRow = nil, nil, nil; UI:Render()
    local function names()
        local out = {}
        for _, l in ipairs(rowsText()) do out[#out + 1] = l:match("^(Sort %a)") end
        return table.concat(out, " ")
    end
    check(names() == "Sort B Sort C Sort A", "the usual order of deals: most profit first")
    UI:SortBy("BUY", 3)
    check(names() == "Sort C Sort A Sort B" and headsText()[1]:find("SPREAD v", 1, true), "sorted by SPREAD: the widest first, and the caption says so")
    UI:SortBy("BUY", 4)
    check(names() == "Sort B Sort C Sort A" and headsText()[1]:find("VOLUME v", 1, true), "sorted by VOLUME: what sells fastest first")
    UI:SortBy("BUY", 4)
    check(names() == "Sort A Sort C Sort B" and headsText()[1]:find("VOLUME ^", 1, true), "a second click: slowest first")
    check(S:Target() ~= nil, "(which deal a press buys is the sniper's choice, whatever the order shown)")
    UI:SortBy("BUY", 0)
    check(names() == "Sort B Sort C Sort A" and UI.sortBy.BUY == nil, "and the usual order comes back")
    S.verified = {}
    -- the Sell tab: rows of a section by P / L
    for s2 = 1, 16 do bags[s2] = nil end
    local keys = { 9861, 9862, 9863 }
    local price = { 300, 900, 600 }
    for i, k in ipairs(keys) do
        ITEMS[k] = { "Sell " .. ("ABC"):sub(i, i), 1 }
        flips[k] = { kind = "FLIP", units = 5, cost = 100, sell = price[i], at = GetServerTime() }
        bags[i] = { itemID = k, stackCount = 5 }
        Se.prices[k] = { price = price[i], at = GetTime(), commodity = true }
    end
    fire("BAG_UPDATE_DELAYED")
    UI.tab = "SELL"; UI:Render()
    local function sellNames()
        local out = {}
        for _, l in ipairs(rowsText()) do local n = l:match("^(Sell %a)"); if n then out[#out + 1] = n end end
        return table.concat(out, " ")
    end
    UI:SortBy("SELL", 5)
    check(sellNames() == "Sell B Sell C Sell A", "the Sell tab sorted by P / L: the most profit first")
    UI:SortBy("SELL", 5)
    check(sellNames() == "Sell A Sell C Sell B", "and the least first on a second click")
    UI:SortBy("SELL", 0)
    for _, k in ipairs(keys) do flips[k] = nil; Se.prices[k] = nil; ITEMS[k] = nil; ns.Journal:Dropped(k, nil, "test") end
    ITEMS[9851], ITEMS[9852], ITEMS[9853] = nil, nil, nil
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    UI.sortBy = {}
    UI.tab = "BUY"; UI:Render()
end

print("the reagent bag is read like any other bag")
do
    local flips = AuctionMeshDB.flips
    local realSlots, realInfo = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
    local reagent = { [1] = { itemID = 9601, stackCount = 40, quality = 1 }, [2] = { itemID = 9602, stackCount = 12, quality = 1 } }
    ITEMS[9601], ITEMS[9602] = { "Reagent Ore", 3 }, { "Reagent Herb", 2 }
    C_Container.GetContainerNumSlots = function(b) return b == 5 and 32 or realSlots(b) end
    C_Container.GetContainerItemInfo = function(b, sl) if b == 5 then return reagent[sl] end return realInfo(b, sl) end
    for s2 = 1, 16 do bags[s2] = nil end
    check(table.concat(Se.BagList(), ",") == "0,1,2,3,4,5", "the bags read: the backpack, four bags and the reagent bag (its number is asked of the game; 5 if it names none)")
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    UI:Open("SELL")
    local b = AuctionMeshFrame.refresh
    b._scripts.OnClick(b)
    local st = strip(AuctionMeshFrame.status._text)
    print("     " .. st)
    check(st:find("^Refreshed: 0 stacks in your bags %(16 slots%), 2 in the reagent bag %(32 slots%)%."), "Refresh says what it read: the bags, and the reagent bag with its slots")
    local keys = {}
    for _, l in ipairs(Se:Loose()) do keys[l.key] = l.count end
    check(keys[9601] == 40 and keys[9602] == 12, "what is in the reagent bag is offered on the Sell tab like anything else")
    LIST[9601] = { { 50, 100 }, { 52, 100 } }
    check(Se:Farm(9601) == 40 and flips[9601] and flips[9601].units == 40, "and can be added from there")
    advance(3)
    local bag, slot, n = Se.FindInBags(9601)
    check(bag == 5 and slot == 1 and n == 40 and Se.prices[9601] and Se.prices[9601].price == 49, "it is found in the reagent bag for posting, and priced")
    flips[9601] = nil; LIST[9601] = nil; Se.prices[9601] = nil
    for i = #ns.Journal.list, 1, -1 do if ns.Journal.list[i].key == 9601 then table.remove(ns.Journal.list, i) end end
    C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = realSlots, realInfo
    Se:ScanBags()
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
end

print("posting: what is going on while prices are read")
do
    local flips = AuctionMeshDB.flips
    AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW"); advance(1)
    for s2 = 1, 16 do bags[s2] = nil end
    S.verified = {}
    local keys = { 9401, 9402, 9403 }
    for i, k in ipairs(keys) do
        ITEMS[k] = { "Post Item " .. i, 1 }
        LIST[k] = { { 100 + i, 40 }, { 110 + i, 60 } }
        flips[k] = { kind = "FLIP", units = 5, cost = 20, sell = 100, at = GetServerTime() }
        bags[i] = { itemID = k, stackCount = 5 }
        Se.prices[k] = nil
    end
    Se.pricedAt = {}; Se.pending = nil; Se.priority = nil
    fire("BAG_UPDATE_DELAYED")
    local wasNew, wasBags = S.upkeep.bagsNew, S.upkeep.bags
    S.upkeep.bagsNew, S.upkeep.bags = 0, 3 -- (as shipped)
    UI:Open("SELL"); UI.notice = nil; UI.wheelSeen = nil; UI:Render()
    local st = strip(AuctionMeshFrame.status._text)
    print("     " .. st:gsub("\n", "\n     "))
    check(st:find("READING PRICES: 0 of 3 ready", 1, true) and st:find("About %d+s for the rest%.") and st:find("Post lights up on a row as its price comes in.", 1, true),
        "with nothing priced yet the Sell tab says so in figures: 0 of 3 ready, and about how long the rest takes")
    check(Se:Unpriced() == true and S:UpkeepEvery() == 0 and S:UpkeepTurn() == true, "on the Sell tab, while prices are missing, EVERY request goes to reading them")
    -- rolling the wheel: sniping has every request, and the tab says the prices wait
    UI.wheelSeen = GetTime(); UI:Render()
    st = strip(AuctionMeshFrame.status._text)
    check(st:find("READING PRICES: 0 of 3 ready.", 1, true) and st:find("Paused while you roll the wheel", 1, true), "while you roll the wheel the prices wait, and the tab says that too")
    UI.wheelSeen = nil
    -- they come in one by one
    local seen = {}
    for _ = 1, 40 do
        advance(0.5); UI:Render()
        local r = Se:PriceProgress()
        seen[r] = true
        if r == 3 then break end
    end
    st = strip(AuctionMeshFrame.status._text)
    check(seen[1] and seen[2] and seen[3] and st:find("All 3 priced and ready: press Post on each item, or Post next.", 1, true),
        "the count goes up as each price comes in, and ends at: all 3 priced and ready")
    check(Se:Unpriced() == false and S:UpkeepEvery() == 3, "with every price in, the radar has three of every four requests again")
    for _, k in ipairs(keys) do flips[k] = nil; LIST[k] = nil; Se.prices[k] = nil; ns.Journal:Dropped(k, nil, "test") end
    for s2 = 1, 16 do bags[s2] = nil end
    fire("BAG_UPDATE_DELAYED")
    S.upkeep.bagsNew, S.upkeep.bags = wasNew, wasBags
    UI.tab = "BUY"; UI.notice = nil; UI:Render()
end

print("the Chart tab: your gold as a line chart")
do
    local G = ns.Gold
    check(G ~= nil and G.d ~= nil and AuctionMeshDB.gold["Tester-Realm"] == G.d and #G.d.d >= 1, "the gold of the character that logged in has been recorded since login")
    do  -- a purchase and a vendor sale, each recorded with what it was
        local seen
        for _, e in ipairs(G.d.ev) do
            for _, w in ipairs(e.why or {}) do if w:find("^Bought %d+ x ") and e.d < 0 then seen = w end end
        end
        print("     " .. tostring(seen))
        check(seen ~= nil, "the purchases of this run are among the swings, each with what was bought")
        -- a vendor sale, from the Sell tab's Sell button
        local flips = AuctionMeshDB.flips
        local soldFn = G.sold
        G.sold = function() return 0 end
        AuctionHouseFrame:Hide(); fire("AUCTION_HOUSE_CLOSED")
        for s2 = 1, 16 do bags[s2] = nil end
        ITEMS[2770] = ITEMS[2770] or { "Copper Ore", 5 }
        flips[2770] = { kind = "VENDOR", units = 12, cost = 3, sell = 5, at = GetServerTime() }
        bags[1] = { itemID = 2770, stackCount = 12 }; fire("BAG_UPDATE_DELAYED")
        G:OnMoney() -- (the record is level with the test's gold before the sale)
        MerchantFrame:Show(); fire("MERCHANT_SHOW"); advance(1)
        Se:SellVendor(2770); advance(3)
        local e = G.d.ev[#G.d.ev]
        print("     " .. tostring(e and e.d) .. " " .. tostring(e and e.why and e.why[1]))
        check(e and e.d == 60 and e.why and e.why[1] == "Sold 12 x Copper Ore to a vendor", "a sale to a vendor is recorded as + 60c, 'Sold 12 x Copper Ore to a vendor'")
        MerchantFrame:Hide(); fire("MERCHANT_CLOSED")
        ns.Journal:Dropped(2770, nil, "test")
        G.sold = soldFn
    end
    -- a known history: 1g, a sale to 1g60s yesterday, a purchase down to 1g10s six hours ago, a vendor sale to 1g15s just now
    local was = G.d
    local now = GetServerTime()
    local day = G.dayId
    G.d = { h = {}, d = {}, ev = {} }
    G.d.d[1] = { id = day(now - 5 * 86400), t = now - 5 * 86400, tc = now - 5 * 86400, o = 10000, h = 10000, l = 10000, c = 10000 }
    G.d.ev = {
        { t = now - 30 * 3600, t2 = now - 30 * 3600, d = 6000, g = 16000, n = 2, why = { "Sold 40 x Thick Leather (auction)" } },
        { t = now - 6 * 3600, t2 = now - 6 * 3600, d = -5000, g = 11000, n = 1, why = { "Bought 60 x Runecloth" } },
        { t = now - 600, t2 = now - 600, d = 500, g = 11500, n = 1 },
    }
    local goldWas, soldWas = gold, G.sold
    G.sold = function() return 0 end -- (nothing sold and unpaid in this history; that has its own check below)
    gold = 11500; G.last, G.lastMoney = 11500, 11500
    UI:Open("BUY")
    local tab = AuctionMeshFrame.tabGold
    check(tab ~= nil and tab._text == "Chart", "there is a Chart tab")
    UI.goldView = nil
    tab._scripts.OnClick(tab)
    local gd = AuctionMeshFrame.gold
    local C = UI.GOLD
    check(UI.tab == "GOLD" and gd._shown and #rowsText() == 0, "it opens the chart, with no list rows under it")
    local st = UI.goldState
    -- THE RANGE: Auto, hours and days
    do
        local n = 0
        for _ in pairs(gd.views) do n = n + 1 end
        check(n == 9 and gd.views.auto._text == "Auto" and gd.views.h1._text == "1h" and gd.views.h3._text == "3h" and gd.views.h6._text == "6h"
            and gd.views.h12._text == "12h" and gd.views.d1._text == "1d" and gd.views.d2._text == "2d" and gd.views.d7._text == "7d" and gd.views.d30._text == "30d",
            "the ranges: Auto, then 1, 3, 6 and 12 hours, then 1, 2, 7 and 30 days")
        check(st and st.view == "d7" and G:AutoView() == "d7" and UI.goldView == nil,
            "Auto: with five days on record the chart shows the shortest range that holds it all, 7 days")
        local keep = G.d
        G.d = { h = {}, d = { { id = day(now - 1500), t = now - 1500, tc = now - 1500, o = 100, h = 100, l = 100, c = 100 } }, ev = {} }
        check(G:AutoView() == "h1", "with 25 minutes on record Auto is 1 hour")
        G.d.d[1].t = now - 4 * 3600
        check(G:AutoView() == "h6", "with 4 hours on record it is 6 hours: the range grows with the record")
        G.d.d[1].t = now - 40 * 86400
        check(G:AutoView() == "d30", "and it ends at 30 days")
        G.d = keep
        gd.views.h3._scripts.OnClick(gd.views.h3)
        check(UI.goldView == "h3" and UI.goldState.view == "h3" and UI.goldState.line.span == 3 * 3600 and strip(gd.chg._text):find("3 hours$"),
            "a click on 3h shows the last 3 hours, and it stays on that")
        gd.views.auto._scripts.OnClick(gd.views.auto)
        check(UI.goldView == nil and UI.goldState.view == "d7", "Auto goes back to following the record")
    end
    gd.views.d2._scripts.OnClick(gd.views.d2)
    st = UI.goldState
    check(st and st.view == "d2" and #st.line.cols == C.cols, "2d shows the last 2 days")
    print("     " .. strip(gd.big._text) .. "   " .. strip(gd.chg._text))
    check(strip(gd.big._text) == "1g15s" and strip(gd.chg._text) == "+ 15s00c  [+15.00%]  2 days" and st.up == true,
        "at the top, large: the gold now, and the change over the range with its percentage (+ 15s on the 1g it began with)")
    -- A TRUE LINE: one real line segment from each point to the next, the area under it filled
    local shown, blocks = 0, 0
    for i = 1, C.cols do
        if gd.cols[i].fill._shown and gd.segs[i]._shown then shown = shown + 1 end
        if gd.cols[i].line._shown then blocks = blocks + 1 end
    end
    check(st.lines == true and shown == C.cols and blocks == 0 and st.segs == C.cols,
        "the line is drawn with real line segments across the whole chart (no blocks), with the area under it filled")
    do
        local cS = math.ceil((48 - 30) / 48 * C.cols) -- the column of the sale
        local flat, rise = gd.segs[cS - 3], gd.segs[cS]
        check(flat._y0 == flat._y1 and flat._x1 - flat._x0 == C.colW, "where the amount does not change the line is level")
        check(rise._y1 > rise._y0 + 40 and rise._x1 - rise._x0 == C.colW and rise._x0 == (cS - 1) * C.colW and gd.segs[cS + 1]._y0 == rise._y1,
            "at the sale it slopes up from the old amount to the new one, and the next piece starts where it ends: one unbroken line")
        -- a client that cannot draw lines: the blocks are used, as before
        UI.goldNoLines = true; UI:Render()
        local segsShown, blocksShown = 0, 0
        for i = 1, C.cols do
            if gd.segs[i]._shown then segsShown = segsShown + 1 end
            if gd.cols[i].line._shown then blocksShown = blocksShown + 1 end
        end
        check(segsShown == 0 and blocksShown == C.cols and UI.goldState.lines == false, "without line segments the line is pieced together from blocks, as it was")
        UI.goldNoLines = nil
        -- line segments that fail when used: the chart falls back by itself, once, and says so in the log
        local real = rawget(gd.segs[5], "SetStartPoint")
        rawset(gd.segs[5], "SetStartPoint", function() error("not supported") end)
        UI:Render()
        check(UI.goldNoLines == true, "if the line segments fail when used, the chart goes back to blocks by itself")
        UI:Render()
        blocksShown = 0
        for i = 1, C.cols do if gd.cols[i].line._shown then blocksShown = blocksShown + 1 end end
        check(blocksShown == C.cols and #(ns.errList or {}) == 0, "and still draws, with no error")
        rawset(gd.segs[5], "SetStartPoint", real)
        UI.goldNoLines = nil; UI:Render()
        st = UI.goldState
    end
    local L = st.line
    check(L.cols[1].v == 10000 and L.cols[C.cols].v == 11500 and L.lo == 10000 and L.hi == 16000,
        "it begins at 1g, peaks at 1g60s and ends at 1g15s")
    local cSale, cBuy = math.ceil((48 - 30) / 48 * C.cols), math.ceil((48 - 6) / 48 * C.cols)
    check(L.cols[cSale - 1].v == 10000 and L.cols[cSale].v == 16000 and L.cols[cSale].lo == 10000 and L.cols[cBuy].v == 11000 and L.cols[cBuy - 1].v == 16000,
        "it steps up at the sale and down at the purchase, at the times they happened")
    -- the amounts down the left, at round figures
    local labels = {}
    for i = 1, C.grid do if strip(gd.grid[i].label._text or "") ~= "" then labels[#labels + 1] = strip(gd.grid[i].label._text) end end
    print("     axis: " .. table.concat(labels, "  "))
    check(#st.grid >= 3 and #labels == #st.grid and st.grid[2] - st.grid[1] == 2000 and st.grid[1] % 2000 == 0,
        "the amounts are down the left at round figures (every 20s here), each with a line across")
    -- the days: a divider where each begins, and its date under it
    local dividers, dates = 0, {}
    for i = 1, C.days do
        if gd.days[i].line._shown then dividers = dividers + 1 end
        if strip(gd.days[i].label._text or "") ~= "" then dates[#dates + 1] = strip(gd.days[i].label._text) end
    end
    check(dividers == #L.days and #L.days >= 1 and #L.days <= 2 and #dates == #L.days + 1 and dates[1]:find("^%a%a%a %d%d %a%a%a$"),
        "a divider marks where each day begins, with the date under each day")
    local ticks = 0
    for i = 1, C.ticks do if strip(gd.ticks[i]._text or "") ~= "" then ticks = ticks + 1 end end
    check(ticks >= 5, "times of day run along the bottom (6A, 12P, 6P)")
    -- the box on the latest amount
    check(gd.call._shown and strip(gd.call.text._text) == "1g15s", "the latest amount is in a box at the end of the line")
    -- the marks
    shown = 0
    for _, m in ipairs(gd.marks) do if m._shown then shown = shown + 1 end end
    check(shown == 3 and strip(gd.marks[1].tip[2]) == "+ 60s00c" and gd.marks[1].tip[3] == "Sold 40 x Thick Leather (auction)" and strip(gd.marks[1].tip[4]) == "Cash after it: 1g60s",
        "the biggest changes are marked on the line; the mouse over the biggest says: + 60s, the Thick Leather sale, and the gold after it")
    check(strip(gd.marks[2].tip[2]) == "- 50s00c" and gd.marks[2].tip[3] == "Bought 60 x Runecloth", "the next: - 50s, Bought 60 x Runecloth")
    check(gd.marks[3].tip[3] == "gold came in, or something sold: not seen by the addon as it happened", "a change the addon did not see happen says so")
    do  -- changes too small to see are listed, not marked (a real chart had red squares for fees of 4c and 2c)
        G.d.ev[#G.d.ev + 1] = { t = now - 300, t2 = now - 300, d = -4, g = 11496, n = 1, why = { "Posting fee: 10 x Rough Stone" } }
        G.d.ev[#G.d.ev + 1] = { t = now - 200, t2 = now - 200, d = 3, g = 11499, n = 1 }
        UI:Render()
        local shownNow = 0
        for _, m in ipairs(gd.marks) do if m._shown then shownNow = shownNow + 1 end end
        check(shownNow == 3 and UI.goldState.marked == 3 and strip(gd.lines[4].label._text):find("Posting fee: 10 x Rough Stone$") and strip(gd.lines[4].value._text) == "- 4c",
            "a posting fee of 4c is in the list but gets no square: the line does not visibly move for it")
        table.remove(G.d.ev); table.remove(G.d.ev)
        UI:Render()
    end
    do  -- what has sold is known from the auction house's list, or else from the last look into the mailbox
        local payWas, salesWas = S.ownSoldPay, AuctionMeshDB.sales
        S.ownSoldPay, AuctionMeshDB.sales = nil, nil
        check(soldWas() == nil, "with neither reading the sold amount is not known")
        AuctionMeshDB.sales = { waiting = 500, pending = { { amount = 300, at = GetServerTime() + 600 } } }
        check(soldWas() == 800, "a mailbox reading on record: 5s waiting there and 3s on its way count as sold, also after a reload")
        S.ownSoldPay, AuctionMeshDB.sales = payWas, salesWas
    end
    -- the mouse anywhere on the chart
    local hv = gd.hover[C.hover]
    check(hv.tip and strip(hv.tip[2]) == "Cash (in hand + sold): 1g15s" and strip(hv.tip[3]) == "Since the start of this chart: + 15s00c", "the mouse on the chart gives the amount at that time")
    -- the list under the chart
    check(strip(gd.head._text):find("^BIGGEST CHANGES, LAST 2 DAYS") and strip(gd.lines[1].label._text):find("Sold 40 x Thick Leather %(auction%)$") and strip(gd.lines[1].value._text) == "+ 60s00c"
        and strip(gd.lines[2].value._text) == "- 50s00c" and strip(gd.lines[4].label._text) == "",
        "the same changes are listed under the chart, largest first")
    check(strip(gd.sum._text):find("^Cash = in hand 1g15s %+ sold 0c      Not sold yet: "), "under the amount, in one line: what the cash is made of, and what has not sold yet")
    -- SOLD COUNTS AS CASH: 40s of sales on their way lift the figure and the line; collecting them changes nothing
    G.sold = function() return 4000 end
    G:OnMoney(); UI:Render()
    check(strip(gd.big._text) == "1g55s" and strip(gd.sum._text):find("^Cash = in hand 1g15s %+ sold 40s00c") and G.d.ev[#G.d.ev].d == 4000,
        "40s of sales on their way: the cash is 1g55s (1g15s in hand + 40s sold), and the line steps up by 40s")
    gold = 15500; G.sold = function() return 0 end
    fire("PLAYER_MONEY"); advance(0.1); UI:Render()
    check(strip(gd.big._text) == "1g55s" and G.d.ev[#G.d.ev].d == 4000 and strip(gd.sum._text):find("^Cash = in hand 1g55s %+ sold 0c"),
        "collecting that gold at the mailbox changes nothing on the chart: it only moves from sold to in hand")
    table.remove(G.d.ev); gold = 11500; G.last, G.lastMoney = 11500, 11500
    -- a falling range is drawn in red
    G.d.ev[#G.d.ev + 1] = { t = now - 60, t2 = now - 60, d = -3000, g = 8500, n = 1, why = { "Bought 10 x Mageweave Cloth" } }
    gold = 8500; G.last, G.lastMoney = 8500, 8500
    UI:Render()
    st = UI.goldState
    check(st.up == false and strip(gd.chg._text) == "- 15s00c  [-15.00%]  2 days" and strip(gd.call.text._text) == "85s00c", "a range that ends lower than it began is red, with the change as a minus")
    -- 7 and 30 days
    gd.views.d7._scripts.OnClick(gd.views.d7)
    st = UI.goldState
    check(st.view == "d7" and st.line.short == true and #st.line.days >= 4 and #st.line.days <= 5 and st.line.cols[1].v == 10000 and gd.cols[1].fill._shown,
        "'7 days' with five days on record: the chart begins where the record begins, with no empty stretch")
    check(strip(gd.chg._text):find("since %a%a%a %d%d:%d%d$") and strip(gd.head._text):find("^BIGGEST CHANGES, SINCE "),
        "and it says since when, in place of '7 days'")
    gd.views.d30._scripts.OnClick(gd.views.d30)
    check(UI.goldState.view == "d30" and UI.goldState.line.short == true, "'30 days' the same")
    -- the first evening with the addon: 25 minutes on record (a real screenshot showed two empty days and a sliver)
    do
        local keep = G.d
        G.d = { h = {}, d = {}, ev = {} }
        G.d.d[1] = { id = day(now - 1500), t = now - 1500, tc = now - 1500, o = 104800, h = 104800, l = 104800, c = 104800 }
        G.d.ev = {
            { t = now - 1200, t2 = now - 1190, d = -17282, g = 87518, n = 3, why = { "Bought 22 x Crisp Spider Meat" } },
            { t = now - 600, t2 = now - 590, d = 19250, g = 106768, n = 4, why = { "Sold 22 x Crisp Spider Meat to a vendor" } },
            { t = now - 60, t2 = now - 50, d = -66873, g = 39895, n = 6, why = { "Bought 48 x Deviate Fish" } },
        }
        gold = 39895; G.last, G.lastMoney = gold, gold
        gd.views.d2._scripts.OnClick(gd.views.d2)
        local s2 = UI.goldState
        local shown2, ticks2 = 0, {}
        for i = 1, C.cols do if gd.cols[i].fill._shown then shown2 = shown2 + 1 end end
        for i = 1, C.ticks do if strip(gd.ticks[i]._text or "") ~= "" then ticks2[#ticks2 + 1] = strip(gd.ticks[i]._text) end end
        print("     " .. strip(gd.chg._text) .. "   marks: " .. table.concat(ticks2, " "))
        check(s2.line.short == true and math.abs(s2.line.span - 1501) <= 1 and shown2 == C.cols,
            "25 minutes on record, '2 days' picked: those 25 minutes fill the whole chart")
        check(#ticks2 >= 4 and ticks2[1]:find("^%d%d:%d%d$") and strip(gd.chg._text):find("since %d%d:%d%d$"),
            "the times along the bottom are a few minutes apart, and the change is 'since' the time recording began")
        local xs = {}
        for i = 1, 3 do xs[i] = UI.goldState.swings[i].col end
        check(xs[1] > 120 and xs[2] > 70 and xs[2] < 100 and xs[3] > 20 and xs[3] < 40, "the marks are spread along the line where each change happened, not piled at the edge")
        G.d = keep
        gold = 8500; G.last, G.lastMoney = 8500, 8500
        gd.views.d30._scripts.OnClick(gd.views.d30)
    end
    -- gold changing while the tab is open is drawn at once
    gold = 9500; fire("PLAYER_MONEY"); advance(0.1)
    check(G.d.ev[#G.d.ev].d == 1000, "gold changes while the tab is open: recorded")
    UI:Render()
    check(strip(gd.big._text) == "95s00c", "(the new amount is shown)")
    G.d = was; gold = goldWas; G.sold = soldWas; G.last, G.lastMoney = nil, gold
    UI.tab = "BUY"; UI.goldView = nil; UI:Render()
end

-- nothing in the whole run raised an error inside the redraw or an input (they are caught, so they must be looked for)
for _, e in ipairs(ns.errList or {}) do print("  ERROR caught " .. e.n .. " x in " .. e.name .. ": " .. e.msg) end
check(#(ns.errList or {}) == 0, "no error was caught in a redraw or an input during the whole run")
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
