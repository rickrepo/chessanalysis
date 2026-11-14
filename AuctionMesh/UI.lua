-- AuctionMesh UI: the one window.
--
--   +-------------------------------------------------------------+
--   | AuctionMesh                              Gold: 32s 00c   [x] |
--   | [ BUY (2) ] [ SELL (3) ]                                     |
--   | What to do next, in plain words.                             |
--   |-------------------------------------------------------------|
--   | [icon] Copper Ore                                    [ Buy ] |
--   |        SAFE  Buy 12 for 36c > vendor pays 60c > +24c         |
--   | [icon] Linen Cloth x20            Ready to post     [ Post ] |
--   |        Paid 20c > Sell 99c > +71c each                       |
--   |-------------------------------------------------------------|
--   | Paid 4s > back 19s = +15s            [Flips: ON] [Post next] |
--   +-------------------------------------------------------------+
--
-- Deals tab: only deals verified against live listings, with the exact
-- quantity and total you will pay. Money tab: what you hold and what it
-- becomes when everything has sold, then everything you bought, what you
-- paid, what it sells for, and the one thing to do with it.
-- Rendering is throttled (5x per second, only while shown and only if changed).
local _, ns = ...
ns = ns or {}

local UI = {}
ns.UI = UI

local floor, min = math.floor, math.min
local ROWS, ROW_H, WIDTH = 12, 26, 720
local MAXROWS = 18 -- rows that exist; how many are shown depends on the panel's height
local ACCENT = { 0.30, 0.86, 0.76 }  -- teal: selected tab, primary action
local LINE = { 0.34, 0.36, 0.40 }    -- grey outline
local TEAL = "|cff4ddbc2"
local TOP = 146    -- y where the list starts

-- FLAT LOOK (a layout the user picked): dark panel, one-pixel outlines, grey
-- small-caps headings, coin icons from the game. Only the tab that sits under
-- the auction house window uses the game's own tab template.
local function tryFrame(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    return ok and f or nil
end
-- Column layout (x offset inside a row, width). Same grid for both tabs:
--   BUY:  ITEM | BUY (qty @ price) | MARKET | SPREAD | VOLUME | PROFIT | [Buy]
--   SELL: ITEM | QTY               | COST   | MARKET | STATUS | P/L    | [Post]
local COLS = { { 40, 170 }, { 214, 110 }, { 328, 74 }, { 406, 66 }, { 476, 78 } }
local HEAD = {
    BUY = { "ITEM", "BUY", "MARKET", "SPREAD", "VOLUME", "PROFIT" },
    SELL = { "ITEM", "QTY", "COST", "MARKET", "STATUS", "P / L" },
    HISTORY = { "WHEN", "WHAT HAPPENED", "", "", "", "" },
}
local CYAN = "|cff66ccff"
UI.tab = "BUY"

local GREEN, GOLD, BLUE, RED, GREY, ORANGE = "|cff33ff66", "|cffffd100", "|cff4d99ff", "|cffff4040", "|cffaaaaaa", "|cffff8040"

local frame, rows = nil, {}

local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function mailOpen() return MailFrame and MailFrame:IsShown() end

function UI:Dirty() self.dirty = true end

-- Shows the latest message at the top of the window for 10 seconds.
function UI:Notice(text, transient)
    self.notice = { text = text, till = GetTime() + 10 }
    if not transient and AuctionMeshDB then
        -- Everything that happened to your gold and items, newest first (HISTORY tab).
        local h = AuctionMeshDB.history or {}
        AuctionMeshDB.history = h
        table.insert(h, 1, { t = GetServerTime(), m = text })
        while #h > 60 do h[#h] = nil end
    end
    self.dirty = true
end

---------------------------------------------------------------- row content

local function buyRows()
    local S, list = ns.Sniper, {}
    for _, d in pairs(S.verified) do list[#list + 1] = d end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == "VENDOR" end
        return a.profit > b.profit
    end)
    return list
end

local function pct(buy, sell)
    if not buy or buy <= 0 then return "" end
    return ("%+d%%"):format(floor((sell - buy) / buy * 100 + 0.5))
end

local function fillBuy(r, d, short)
    local S = ns.Sniper
    local units, total = S.NextBuy(d)
    r.name:SetText(S.nameOf(d.key))
    r.state:SetText("")
    local each = d.units > 0 and d.profit / d.units or 0
    local unit = units > 0 and floor(total / units + 0.5) or 0
    r.c[1]:SetText(("%d @ %s"):format(units, short(unit)))
    if d.kind == "VENDOR" then
        r.c[2]:SetText(short(d.sell))
        r.c[3]:SetText(GREEN .. pct(unit, d.sell) .. "|r")
        r.c[4]:SetText(GREEN .. "instant|r")
        r.detail:SetText(("%sSAFE|r  Buy %d for %s, vendor pays %s"):format(GREEN, units, short(total), short(d.sell * units)))
        r.profit:SetText(GREEN .. "+" .. short(each * units) .. "|r")
    else
        local tr = ns.Store:Trend(d.key, GetServerTime(), 24) or d.trend
        r.c[2]:SetText(short(d.wall or d.sell) .. (tr and ((tr >= 0 and GREEN or RED) .. (" %+d%%|r"):format(floor(tr * 100 + 0.5))) or ""))
        r.c[3]:SetText(GREEN .. pct(unit, d.sell) .. "|r")
        r.c[4]:SetText(d.rate and ((d.rate >= 60 and GREEN or GOLD) .. ("%d/h|r"):format(floor(d.rate))) or (GREY .. "n/a|r"))
        local proof = d.sold and ("buyers paid %s"):format(short(d.sold)) or ("%d listed at %s+"):format(d.depth or 0, short(d.wall or 0))
        if d.partial then proof = proof .. (", %d cheap left"):format(d.partial) end
        if d.eta then proof = proof .. (", sells in ~%d min"):format(math.max(1, floor(d.eta + 0.5))) end
        r.detail:SetText(("%sFLIP|r  Buy %d for %s, relist at %s %s(%s)|r"):format(
            GOLD, units, short(total), short(d.sell), GREY, proof))
        r.profit:SetText(GREEN .. "+" .. short(d.profit) .. "|r")
    end
    local b = S.buying
    if S.queued and S.queued.key == d.key then
        r.btn:SetText("..."); r.btn:Disable()
    elseif b and b.key == d.key then
        if b.phase == "confirm" then
            r.btn:SetText("Confirm"); r.btn:Enable()
        else
            r.btn:SetText("..."); r.btn:Disable()
        end
    else
        r.btn:SetText("Buy")
        r.btn:SetEnabled(not b)
    end
    r.btn:Show()
end

local STATE = {
    AH = function(e, ready, busy)
        if not ahOpen() then return GOLD .. "Open the AH to post|r", nil end
        if busy then return GREY .. "Checking price...|r", nil end
        if ready then return GOLD .. "Ready to post|r", "Post" end
        return GREY .. "Waiting for price check|r", nil
    end,
    VENDOR = function() return GREEN .. "Sell to any vendor|r", merchantOpen() and "Sell" or nil end,
    MAIL = function(e) return BLUE .. (e.seen and "In your mailbox" or "In your mailbox (not checked yet)") .. "|r", nil end,
    HOLD = function() return RED .. "Waiting: market is below your cost|r", ahOpen() and "Re-check" or nil end,
    LISTED = function(e)
        if e.live == 0 then return GREEN .. "Sold or expired: check your mailbox|r", nil end
        if e.undercut then return ORANGE .. "Listed, but someone is cheaper|r", nil end
        return GREY .. "Listed for sale|r", nil
    end,
}

local function fillSell(r, e, short)
    local Se = ns.Seller
    local name = ns.Sniper.nameOf(e.key)
    r.name:SetText(e.count > 1 and (name .. " x" .. e.count) or name)
    local p = Se.prices[e.key]
    local ready = p and p.price and GetTime() - p.at < 90
    local busy = Se.pending and Se.pending.key == e.key
    if Se.posting and Se.posting.key == e.key then busy = true end
    if e.action == "LISTED" then
        -- someone listed below your price? (from the last sweep, if it is recent)
        local St = ns.Store
        local t = St.t[e.key]
        e.undercut = t and GetServerTime() - t < 600 and St.p[e.key] < (e.listed.price or 0) or false
    end
    local text, button = STATE[e.action](e, ready, busy)
    r.state:SetText(text)
    local paid, sell, _, profit, live = Se:Numbers(e)
    r.c[1]:SetText(tostring(e.count))
    r.c[2]:SetText(paid and short(paid) or (ORANGE .. "?|r"))
    r.c[3]:SetText(short(sell) .. ((e.f.kind == "FLIP" and not live and e.action ~= "LISTED") and (GREY .. "*|r") or ""))
    r.c[4]:SetText(e.action == "LISTED" and (e.live == 0 and (GREEN .. "SOLD?|r") or e.undercut and (ORANGE .. "UNDERCUT|r") or (GREY .. "LISTED|r"))
        or e.action == "AH" and (ready and (GOLD .. "READY|r") or (GREY .. "pricing|r"))
        or e.action == "VENDOR" and (GREEN .. "VENDOR|r") or e.action == "MAIL" and (CYAN .. "MAIL|r") or (RED .. "WAIT|r"))
    if profit and e.action ~= "HOLD" then
        r.profit:SetText((profit >= 0 and GREEN .. "+" or RED) .. short(profit * e.count) .. "|r")
    else
        r.profit:SetText("")
    end
    local paidText = paid and short(paid) or (ORANGE .. "unknown|r")
    if e.action == "HOLD" then
        r.detail:SetText(("Paid %s each  >  market is lower right now"):format(paidText))
    else
        local profitText = ""
        if profit then profitText = ("  >  %s%s%s|r each"):format(profit >= 0 and GREEN or RED, profit >= 0 and "+" or "", short(profit)) end
        local est = (e.f.kind == "FLIP" and not live and e.action ~= "LISTED") and (GREY .. " (planned)|r") or ""
        r.detail:SetText(("Paid %s  >  Sell %s%s%s"):format(paidText, short(sell), est, profitText))
    end
    if button then r.btn:SetText(button); r.btn:Enable(); r.btn:Show() else r.btn:Hide() end
end

---------------------------------------------------------------- status line

local function clock(s)
    s = math.floor(s + 0.5)
    return s >= 60 and ("%d:%02d"):format(s / 60, s % 60) or (s .. "s")
end

-- Three short lines: what is being checked and when, the last result, and the scan timer.
local function buyStatus(n)
    if not ahOpen() then return GOLD .. "Open the Auction House to look for deals.|r" end
    local S, Sw, G = ns.Sniper, ns.Swarm, ns.Gate
    local name, lines = S.nameOf, {}
    local q = S.background
    local mode = ns.Deals.cfg.flips and "" or (GREEN .. "Vendor-only.|r ")

    -- line 1: now / next
    if G:UserBusy() then
        lines[1] = ORANGE .. "Paused for a moment (a click is in progress).|r"
    elseif S.searching then
        lines[1] = mode .. "Checking now: " .. name(S.searching.key)
    else
        local key, pos = S:PeekNext()
        local wait = math.max(0, (G.nextAt or 0) - GetTime())
        if key then
            lines[1] = ("%sNext check: %s in %.1fs%s"):format(mode, name(key), wait,
                (pos and q) and ("  %s(%d of %d, round %d)|r"):format(GREY, pos, #q, (q.rounds or 0) + 1) or "")
        else
            lines[1] = mode .. "Nothing to check yet: waiting for the first price scan."
        end
    end
    -- line 2: last result
    local l = S.last
    if l then
        lines[2] = ("%sLast: %s: %s (%s ago)|r"):format(l.deal and GREEN or GREY, name(l.key),
            l.deal and "DEAL FOUND" or ((l.reason or "no deal"):gsub("%$(%d+)", function(c) return ns.Seller.short(tonumber(c)) .. GREY end)),
            clock(GetTime() - l.at))
    end
    -- line 3: scan timer
    if Sw and Sw.active and #Sw.units > 0 then
        local fresh, total = Sw:Coverage()
        local left = Sw:NextRescan() or 0
        local peers = ns.Sync:PeerCount()
        local M, G = ns.measure and ns.measure.last, ns.Gate
        local measured = M and (" %d items in %d request%s,"):format(M.items, M.requests, M.requests == 1 and "" or "s") or ""
        local limit = G.cycle and (" limit %.1f/s."):format(1 / G.cycle) or ""
        lines[#lines + 1] = ("%sRadar:%s re-read every %ds (next in %s).%s  %s|r"):format(
            GREY, measured, Sw.cfg.fresh, clock(left), limit,
            peers > 0 and (GREEN .. ("Sharing live with %d other player%s."):format(peers, peers == 1 and "" or "s"))
            or "Not sharing: nobody else is connected (/amesh channel or a shared guild).")
    end
    return table.concat(lines, "\n")
end

-- The single most useful thing to do right now, in plain words, with the gold it makes.
local function nextStep(deals, entries, short)
    local S, Se = ns.Sniper, ns.Seller
    local b = S.buying
    if b and b.phase == "confirm" then
        return ("Press |cffffd100Confirm|r to pay %s for %d x %s."):format(short(b.total or 0), b.units, S.nameOf(b.key))
    end
    if #deals > 0 and ahOpen() then
        local d = deals[1]
        local units, total = S.NextBuy(d)
        return ("Press |cffffd100Buy|r on %s: pay %s, make %s+%s|r%s."):format(S.nameOf(d.key), short(total), GREEN, short(d.profit),
            d.kind == "VENDOR" and " (guaranteed: sell to a vendor)" or (d.eta and (" (resale, sells in ~%d min)"):format(math.max(1, floor(d.eta + 0.5))) or " (resale)"))
    end
    local n = { AH = 0, VENDOR = 0, MAIL = 0, HOLD = 0, LISTED = 0 }
    local gain, sold = { AH = 0, VENDOR = 0 }, 0
    for _, e in ipairs(entries) do
        n[e.action] = (n[e.action] or 0) + 1
        local _, _, _, profit = Se:Numbers(e)
        if gain[e.action] and profit then gain[e.action] = gain[e.action] + profit * e.count end
        if e.action == "LISTED" and e.live == 0 then sold = sold + 1 end
    end
    if n.AH > 0 and ahOpen() then
        return ("Open |cffffd100Money|r and press |cffffd100Post|r: %d item(s) to list for %s+%s|r."):format(n.AH, GREEN, short(gain.AH))
    end
    if n.VENDOR > 0 then
        return merchantOpen() and ("Press |cffffd100Sell all to vendor|r to collect %s+%s|r profit."):format(GREEN, short(gain.VENDOR))
            or ("Visit any vendor: %d item(s) to sell for %s+%s|r profit."):format(n.VENDOR, GREEN, short(gain.VENDOR))
    end
    if n.MAIL > 0 then return ("Visit a mailbox: %d purchase(s) to collect."):format(n.MAIL) end
    if sold > 0 then return "Visit a mailbox: an auction sold or expired." end
    if n.AH > 0 then return ("Open the auction house: %d item(s) to post for %s+%s|r."):format(n.AH, GREEN, short(gain.AH)) end
    if not ahOpen() then return "Open the auction house to look for deals." end
    if n.LISTED > 0 then return "Nothing to do: your auctions are listed and deals are being watched." end
    return "Nothing to do yet: watching for deals. A sound plays when one appears."
end

---------------------------------------------------------------- render

function UI:Render()
    self.dirty = false
    if not frame or not frame:IsShown() then return end
    local Se, short = ns.Seller, ns.Seller.short
    local deals, entries = buyRows(), Se:Entries()
    self:Layout()
    do  -- top right: profit actually banked
        local rz = AuctionMeshDB.realized or 0
        frame.gold:SetText(("%sProfit banked so far|r  %s%s%s|r"):format(GREY, rz >= 0 and GREEN or RED, rz >= 0 and "+ " or "- ", short(math.abs(rz))))
    end
    if self.tab == "SELL" then
        -- MONEY: what you hold, what is already earned, what depends on a sale
        -- "ended" = an auction of yours that is no longer listed: it sold or it
        -- expired. Which one is only known at the mailbox, so it is not called sold.
        local ended, listed, bought, held, heldCost = 0, 0, 0, 0, 0
        local cut = 1 - ns.Deals.cfg.cut
        for _, e in ipairs(entries) do
            local paid, _, net = Se:Numbers(e)
            if e.action == "LISTED" then
                local value = floor((e.listed.price or 0) * cut) * e.count
                if e.live == 0 then ended = ended + value else listed = listed + value end
            elseif e.action == "HOLD" then
                held, heldCost = held + 1, heldCost + (paid or 0) * e.count
            else
                bought = bought + (net or 0) * e.count
            end
        end
        local gold = GetMoney()
        local function plus(v, colour) return v > 0 and (colour .. "+ " .. short(v) .. "|r") or (GREY .. "-|r") end
        local lg = frame.ledger
        lg.rows[1].label:SetText("Gold on this character now")
        lg.rows[1].value:SetText(short(gold))
        lg.rows[2].label:SetText("Auction ended (sold or expired): collect at a mailbox")
        lg.rows[2].value:SetText(plus(ended, TEAL))
        lg.rows[3].label:SetText("Listed: if it sells at the listed prices")
        lg.rows[3].value:SetText(plus(listed, ORANGE))
        lg.rows[4].label:SetText("Bought, not sold yet: at the live price")
        lg.rows[4].value:SetText(plus(bought, ORANGE))
        lg.total.label:SetText("Total when it has all sold")
        lg.total.value:SetText(short(gold + ended + listed + bought))
        lg.note:SetText(held > 0 and ("Not counted: %d item(s) held until the price recovers, cost %s."):format(held, short(heldCost))
            or "Amounts are after the 5% auction house cut.")
    end
    for i = 1, 6 do frame.head[i]:SetText(HEAD[self.tab][i]) end
    frame.tabBuy:SetText(("Deals (%d)"):format(#deals))
    frame.tabSell:SetText(("Money (%d)"):format(#entries))
    UI.selectTab(frame.tabBuy, self.tab == "BUY")
    UI.selectTab(frame.tabSell, self.tab == "SELL")
    UI.selectTab(frame.tabHist, self.tab == "HISTORY")

    local list = self.tab == "BUY" and deals or self.tab == "SELL" and entries or (AuctionMeshDB.history or {})
    if self.tab == "HISTORY" then
        frame.headline:SetText("History  " .. GREY .. "everything bought, collected, posted and sold|r")
    elseif self.tab == "BUY" then
        local total = 0
        for _, d in ipairs(deals) do total = total + d.profit end
        frame.headline:SetText(#deals > 0
            and ("Make now  %s+ %s|r  %s(%d deal%s)|r"):format(GREEN, short(total), GREY, #deals, #deals == 1 and "" or "s")
            or ("Make now  " .. GREY .. "nothing yet|r"))
    else
        local inv, back = 0, 0
        for _, e in ipairs(entries) do
            local paid, _, net = Se:Numbers(e)
            if paid and e.action ~= "HOLD" then inv, back = inv + paid * e.count, back + net * e.count end
        end
        frame.headline:SetText(#entries > 0
            and ("%sCOMING IN: +%s|r  %swhen these are sold|r"):format(back >= inv and GREEN or RED, short(back - inv), GREY)
            or (GREY .. "Nothing to sell|r"))
    end
    frame.next:SetText(TEAL .. "NEXT|r  " .. nextStep(deals, entries, short))
    local status = self.tab == "BUY" and buyStatus(#deals) or Se:Instructions(entries)
    if self.tab == "HISTORY" then
        status = GREY .. ns.Learn:Summary() .. "|r"
    end
    if self.tab == "SELL" then status = "" end -- the MONEY section and the NEXT line say it all
    local n = self.notice
    if n and GetTime() < n.till then
        status = n.text
    elseif self.tab == "SELL" and ahOpen() and ns.Gate:UserBusy() then
        status = ORANGE .. "Paused for a moment (a click is in progress).|r " .. status
    end
    frame.status:SetText(status)
    -- as many rows as the panel's height holds
    local h = frame:GetHeight()
    local vis = type(h) == "number" and h > 0 and math.max(3, math.min(MAXROWS, floor((h - (self.listTop or TOP) - 36) / ROW_H))) or ROWS
    self.vis = vis
    for i = 1, MAXROWS do
        local r, item = rows[i], list[i]
        if i > vis then item = nil end
        r.item = item
        if not item then r:Hide() else
            if self.tab == "HISTORY" then
                local age = GetServerTime() - item.t
                r.icon:SetTexture(nil)
                r.name:SetText(GREY .. (age < 90 and (age .. "s ago") or age < 5400 and (floor(age / 60) .. " min ago")
                    or (floor(age / 3600) .. " h ago")) .. "|r")
                for n = 1, 4 do r.c[n]:SetText("") end
                r.state:SetText(""); r.profit:SetText(""); r.btn:Hide()
                r.detail:SetText(item.m)
                r.detail:Show()
            else
                r.detail:Hide()
                r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
                if self.tab == "BUY" then fillBuy(r, item, short) else fillSell(r, item, short) end
            end
            r:Show()
        end
    end
    local more = #list > vis and ("  +" .. (#list - vis) .. " more") or ""

    -- Footer: money tied up in the SELL list.
    local invested, back, unknown = 0, 0, 0
    for _, e in ipairs(entries) do
        local paid, _, net = Se:Numbers(e)
        if paid then invested, back = invested + paid * e.count, back + net * e.count else unknown = unknown + 1 end
    end
    local text = ""
    if #entries > 0 then
        local profit = back - invested
        text = ("Holding: paid %s  >  expect back %s  =  %s%s%s|r"):format(short(invested), short(back),
            profit >= 0 and GREEN or RED, profit >= 0 and "+" or "", short(profit))
    end
    do
        local made = (AuctionMeshDB.realized or 0) - (ns.realizedAtLogin or 0)
        local hours = (GetTime() - (ns.sessionStart or GetTime())) / 3600
        if made ~= 0 and hours > 0.05 then
            text = text .. ("%s   Session %s%s%s|r (%s an hour)"):format(text ~= "" and "  |" or "", made >= 0 and GREEN or RED,
                made >= 0 and "+" or "", short(made), short(made / hours))
        end
    end
    frame.footer:SetText(text .. more)
    frame.post:SetShown(self.tab == "SELL" and ahOpen())
    do  -- vendor sales always need your click
        local nv, gain = 0, 0
        for _, e in ipairs(entries) do
            if e.action == "VENDOR" then nv = nv + 1; gain = gain + (e.f.sell or 0) * e.count end
        end
        frame.vend:SetShown(self.tab == "SELL" and merchantOpen() and nv > 0 and not ahOpen())
        frame.vend:SetText(("Sell all to vendor  +%s"):format((short(gain):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
    end
    frame.flips:SetText(ns.Deals.cfg.flips and "Mode: Vendor + Flips" or "Mode: Vendor only")
    frame.flips:SetShown(self.tab == "BUY")
end

---------------------------------------------------------------- clicks

local function rowButton(self)
    local item = self:GetParent().item
    if not item or UI.tab == "HISTORY" then return end
    if UI.tab == "BUY" then
        local S = ns.Sniper
        local b = S.buying
        if b and b.key == item.key and b.phase == "confirm" then S:Confirm() else S:Buy(item.key) end
    else
        local Se = ns.Seller
        if item.action == "AH" then Se:Post(item.key)
        elseif item.action == "VENDOR" then Se:SellVendor(item.key)
        elseif item.action == "HOLD" then Se.prices[item.key] = nil; Se.priority = item.key
        end
    end
    UI:Dirty()
end

local function rowEnter(self)
    local item = self.item
    if not item or UI.tab == "HISTORY" then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(item.key)
    local st, dt = self.state:GetText(), self.detail:GetText()
    if st and st ~= "" then GameTooltip:AddLine(st, 1, 1, 1, true) end
    if dt and dt ~= "" then GameTooltip:AddLine(dt, 0.8, 0.8, 0.8, true) end
    if UI.tab == "SELL" then
        local p = ns.Seller.prices[item.key]
        if p and p.price then
            local qty = ns.Seller:PostQty(item.key, p)
            GameTooltip:AddLine(("%sPosts %d at %s each, deposit %s|r"):format(GOLD, qty,
                ns.Seller.short(p.price), ns.Seller.short(ns.Seller:DepositTotal(item.key, p.commodity, math.max(qty, 1)))))
            GameTooltip:AddLine(GREY .. "The posting fee comes back when it sells.|r")
        elseif p and p.hold then
            GameTooltip:AddLine(RED .. p.hold .. "|r")
        end
        if item.f.proof then GameTooltip:AddLine(GREEN .. "Purchase confirmed: " .. item.f.proof .. "|r") end
        GameTooltip:AddLine(GREY .. "Right-click: remove from this list|r")
    else
        local d = item
        if d.kind == "FLIP" then
            GameTooltip:AddLine(("%sLive market: %d units listed from %s. Posting fee %s (kept aside, returned on sale).|r"):format(GREY,
                d.depth or 0, ns.Seller.short(d.wall or 0), ns.Seller.short(d.deposit or 0)))
            do  -- what the price history database knows
                local St, now = ns.Store, GetServerTime()
                local t6, t24 = St:Trend(d.key, now, 6), St:Trend(d.key, now, 24)
                local lo, hi, n = St:Range(d.key, now, 24)
                if n and n > 1 then
                    GameTooltip:AddLine(("%sPrice history: %s in 6h, %s in 24h; 24h range %s to %s (%d records).|r"):format(GREY,
                        t6 and ("%+d%%"):format(floor(t6 * 100 + 0.5)) or "n/a", t24 and ("%+d%%"):format(floor(t24 * 100 + 0.5)) or "n/a",
                        ns.Seller.short(lo), ns.Seller.short(hi), n))
                else
                    GameTooltip:AddLine(GREY .. "Price history: still collecting (needs a few hours of readings).|r")
                end
            end
            GameTooltip:AddLine(d.sold and (GREEN .. "Real sales on record: buyers paid " .. ns.Seller.short(d.sold) .. " each.|r")
                or (GREY .. "No recorded sale of this item yet.|r"))
        end
    end
    GameTooltip:Show()
end

local function rowMouseUp(self, button)
    if GetCursorInfo() then return ns.Seller.AcceptDrop() end
    if button == "RightButton" and UI.tab == "SELL" and self.item then ns.Seller:Untrack(self.item.key) end
end

---------------------------------------------------------------- window

-- FLAT STYLE (after a layout the user picked): dark panel, one-pixel outlines,
-- a teal outline on what is selected or primary, grey small-caps section
-- headings, label on the left and amount on the right, a ruled total line.

-- one-pixel outline around a frame; call again to recolour it
local function outline(f, c, a)
    local e = rawget(f, "edges")
    if not e then
        e = {}
        rawset(f, "edges", e)
        for i = 1, 4 do e[i] = f:CreateTexture(nil, "BORDER") end
        e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
        e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
        e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
    end
    for i = 1, 4 do e[i]:SetColorTexture(c[1], c[2], c[3], a or 1) end
end

-- flat button: dark fill, thin outline, soft teal glow on hover
local function button(parent, w, text, onClick, name)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(w, 22)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetAllPoints()
    b.fill:SetColorTexture(0.09, 0.10, 0.12, 1)
    outline(b, LINE)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.14)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeTab(parent, text, onClick)
    return button(parent, 104, text, onClick)
end
-- the selected tab gets the teal outline (the game's own tab under the auction house keeps the game's style)
local function selectTab(t, on)
    if rawget(t, "native") and PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
        if on then pcall(PanelTemplates_SelectTab, t) else pcall(PanelTemplates_DeselectTab, t) end
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 0) end
    elseif rawget(t, "fill") then
        outline(t, on and ACCENT or LINE)
    else
        t:SetEnabled(not on)
    end
end
UI.selectTab = selectTab

-- a "label ........ amount" line
local function ledgerRow(parent, y, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 0, y)
    l:SetJustifyH("LEFT")
    local v = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    v:SetPoint("TOPRIGHT", 0, y)
    v:SetJustifyH("RIGHT")
    return { label = l, value = v }
end

function UI:Create()
    if frame then return end
    frame = CreateFrame("Frame", "AuctionMeshFrame", UIParent)
    frame:SetSize(WIDTH, TOP + 44 + ROWS * ROW_H)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(f) if not UI.docked then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        if UI.docked then return end
        local point, _, rel, x, y = f:GetPoint()
        AuctionMeshDB.cfg.pos = { point, rel, x, y }
    end)
    frame:SetScript("OnReceiveDrag", function() ns.Seller.AcceptDrop() end)
    frame:SetScript("OnMouseUp", function() if GetCursorInfo() then ns.Seller.AcceptDrop() end end)

    -- background: the auction house's own art
    frame.art = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.art:SetAllPoints()
    frame.art:SetColorTexture(0.045, 0.05, 0.06, 0.97)
    outline(frame, LINE)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetText("AuctionMesh")
    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", 0, 0)
    frame.closeBtn:SetScript("OnClick", function() UI:Close() end)

    -- tabs (positioned in Place(): next to the title when floating, at the left edge when docked)
    frame.tabBuy = makeTab(frame, "Deals", function() UI.tab = "BUY"; UI:Render() end)
    frame.tabSell = makeTab(frame, "Money", function() UI.tab = "SELL"; UI:Render() end)
    frame.tabHist = makeTab(frame, "History", function() UI.tab = "HISTORY"; UI:Render() end)
    frame.tabSell:SetPoint("LEFT", frame.tabBuy, "RIGHT", 6, 0)
    frame.tabHist:SetPoint("LEFT", frame.tabSell, "RIGHT", 6, 0)

    -- account strip, top right
    frame.gold = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.gold:SetPoint("TOPRIGHT", -34, -14)
    frame.gold:SetJustifyH("RIGHT")

    -- headline (the one number that matters) and, on its right, the min-profit control
    frame.headline = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.headline:SetPoint("TOPLEFT", 14, -44)
    frame.headline:SetJustifyH("LEFT")
    local log = button(frame, 44, "Log", function() ns.Diag:Show() end)
    log:SetPoint("TOPRIGHT", -12, -40)
    local function box(suffix)
        local e = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        e:SetSize(30, 20)
        e:SetAutoFocus(false)
        e:SetNumeric(true)
        e:SetMaxLetters(3)
        local s = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetPoint("LEFT", e, "RIGHT", 2, 0)
        s:SetText(suffix)
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEditFocusLost", function() UI:ApplyMinProfit() end)
        return e, s
    end
    local cLabel, sLabel
    frame.minC, cLabel = box("|cffeda55fc|r")
    frame.minC:SetPoint("RIGHT", log, "LEFT", -22, 0)
    frame.minS, sLabel = box("|cffc7c7cfs|r")
    frame.minS:SetPoint("RIGHT", frame.minC, "LEFT", -18, 0)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("RIGHT", frame.minS, "LEFT", -10, 0)
    lbl:SetText("Min profit per deal")
    frame.minWidgets = { lbl, frame.minS, sLabel, frame.minC, cLabel } -- a Deals control: hidden on the Money tab

    -- NEXT STEP: one plain instruction, always the most profitable thing to do now
    frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.next:SetPoint("TOPLEFT", 14, -66)
    frame.next:SetPoint("TOPRIGHT", -14, -66)
    frame.next:SetJustifyH("LEFT"); frame.next:SetWordWrap(false)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("TOPLEFT", 14, -86)
    frame.status:SetPoint("TOPRIGHT", -14, -86)
    frame.status:SetHeight(38)
    frame.status:SetJustifyH("LEFT"); frame.status:SetJustifyV("TOP")

    -- MONEY: the answer to "how much do I really have?", on the Money tab
    local lg = CreateFrame("Frame", nil, frame)
    lg:SetPoint("TOPLEFT", 14, -40); lg:SetPoint("TOPRIGHT", -14, -40)
    lg:SetHeight(132)
    lg.title = lg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lg.title:SetPoint("TOPLEFT", 0, 0)
    lg.title:SetText("MONEY")
    lg.rows = {}
    for i = 1, 4 do lg.rows[i] = ledgerRow(lg, -24 - (i - 1) * 16) end
    lg.rule = lg:CreateTexture(nil, "ARTWORK")
    lg.rule:SetPoint("TOPLEFT", 0, -90); lg.rule:SetPoint("TOPRIGHT", 0, -90); lg.rule:SetHeight(1)
    lg.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    lg.total = ledgerRow(lg, -96, "GameFontHighlight")
    lg.note = lg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lg.note:SetPoint("TOPLEFT", 0, -116); lg.note:SetPoint("TOPRIGHT", 0, -116)
    lg.note:SetJustifyH("LEFT"); lg.note:SetWordWrap(false)
    lg:Hide()
    frame.ledger = lg

    -- list heading: grey small caps over a thin rule
    frame.strip = frame:CreateTexture(nil, "ARTWORK")
    frame.strip:SetHeight(1)
    frame.strip:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    frame.head = {}
    for n = 1, 6 do frame.head[n] = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end

    for i = 1, MAXROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetHeight(ROW_H - 2)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.035 or 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.10)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", 30, 0)
        r.name:SetWidth(COLS[1][2] + 6); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.c = {}
        for n = 2, 5 do
            local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f:SetPoint("LEFT", COLS[n][1], 0)
            f:SetWidth(COLS[n][2]); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
            r.c[n - 1] = f
        end
        -- One line per row. The longer explanation and status are kept for the
        -- tooltip (and shown in place only on the HISTORY tab).
        r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail:SetPoint("LEFT", COLS[2][1] - 60, 0)
        r.detail:SetPoint("RIGHT", -8, 0)
        r.detail:SetJustifyH("LEFT"); r.detail:SetWordWrap(false)
        r.detail:Hide()
        r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.state:Hide()
        r.profit = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.profit:SetPoint("RIGHT", -74, 0)
        r.profit:SetWidth(110); r.profit:SetJustifyH("RIGHT"); r.profit:SetWordWrap(false)
        r.btn = button(r, 64, "Buy", rowButton)
        r.btn:SetHeight(20)
        outline(r.btn, ACCENT) -- the action on a row is the primary action
        -- Mouse on a Buy/Post button = you are about to click: background work
        -- stops so the auction house is free when you do.
        r.btn:SetScript("OnEnter", function(self) UI.hoverBtn = self end)
        r.btn:SetScript("OnLeave", function(self) if UI.hoverBtn == self then UI.hoverBtn = nil end end)
        r.btn:SetPoint("RIGHT", -4, 0)
        r:EnableMouse(true)
        r:SetScript("OnEnter", rowEnter)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnMouseUp", rowMouseUp)
        r:Hide()
        rows[i] = r
    end

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 14, 12)
    frame.footer:SetJustifyH("LEFT")
    frame.vend = button(frame, 210, "Sell all to vendor", function() ns.Seller:SellVendor() end)
    frame.vend:SetPoint("BOTTOMRIGHT", -12, 7)
    frame.post = button(frame, 96, "Post next", function() ns.Seller:PostNext() end, "AuctionMeshPostButton")
    frame.post:SetPoint("BOTTOMRIGHT", -12, 7)
    frame.flips = button(frame, 160, "Mode: Vendor + Flips", function() UI:SetVendorOnly(ns.Deals.cfg.flips) end)
    frame.flips:SetPoint("BOTTOMRIGHT", -12, 7)

    -- Throttled redraw: at most 5 per second, and only when something changed.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        if UI.notice and GetTime() >= UI.notice.till then UI.notice = nil; UI.dirty = true end
        local paused = ns.Gate:UserBusy()
        if paused ~= UI.wasPaused then UI.wasPaused = paused; UI.dirty = true end
        -- Timers tick twice a second while the BUY tab is open at the auction house.
        UI.tick = (UI.tick or 0) + 1
        if UI.tab == "BUY" and ahOpen() and UI.tick % 3 == 0 then UI.dirty = true end
        if UI.dirty then UI:Render() end
    end)
    frame:Hide()
end

-- Where things sit depends on the tab: the Money tab has the MONEY section on
-- top and its list below; the other tabs have the headline and status lines.
function UI:Layout()
    local sell = self.tab == "SELL"
    local key = sell and "S" or "B"
    if self.layoutKey == key then return end
    self.layoutKey = key
    local nextY, statusY, statusH, top = -66, -86, 38, TOP
    if sell then nextY, statusY, statusH, top = -180, -198, 14, 240 end
    self.listTop = top
    frame.headline:SetShown(not sell)
    frame.ledger:SetShown(sell)
    for _, w in ipairs(frame.minWidgets) do w:SetShown(not sell) end
    frame.next:ClearAllPoints()
    frame.next:SetPoint("TOPLEFT", 14, nextY); frame.next:SetPoint("TOPRIGHT", -14, nextY)
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOPLEFT", 14, statusY); frame.status:SetPoint("TOPRIGHT", -14, statusY)
    frame.status:SetHeight(statusH)
    frame.strip:ClearAllPoints()
    frame.strip:SetPoint("TOPLEFT", 10, -(top - 4)); frame.strip:SetPoint("TOPRIGHT", -10, -(top - 4))
    for n = 1, 5 do
        frame.head[n]:ClearAllPoints()
        frame.head[n]:SetPoint("TOPLEFT", 10 + COLS[n][1] - (n == 1 and 26 or 0), -(top - 18))
    end
    frame.head[6]:ClearAllPoints()
    frame.head[6]:SetPoint("TOPRIGHT", -84, -(top - 18))
    for i = 1, MAXROWS do
        local r = rows[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -top - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -top - (i - 1) * ROW_H)
    end
end

-- Reads the two "Min profit" boxes and applies them right away.
function UI:ApplyMinProfit()
    local s = tonumber(frame.minS:GetText()) or 0
    local c = tonumber(frame.minC:GetText()) or 0
    self:SetMinProfit(s * 100 + c)
end

function UI:SetMinProfit(copper)
    copper = math.max(1, math.floor(copper))
    AuctionMeshDB.cfg.minProfit = copper
    ns.Deals.cfg.minProfit = copper
    local S = ns.Sniper
    for k, d in pairs(S.verified) do
        if d.profit < copper and not (S.buying and S.buying.key == k) then S.verified[k] = nil end
    end
    S.checkedAt = {} -- deals hidden by the old minimum can show up again
    if frame then
        frame.minS:SetText(tostring(math.floor(copper / 100)))
        frame.minC:SetText(tostring(copper % 100))
    end
    self:Notice(("Minimum profit per deal: %s. Smaller deals are not shown."):format(ns.Seller.short(copper)), true)
    self:Dirty()
end

-- Vendor-only mode: every deal shown is guaranteed profit (buy, sell to an NPC).
function UI:SetVendorOnly(on)
    local cfg = AuctionMeshDB.cfg
    cfg.flips = not on
    ns.Deals.cfg.flips = cfg.flips
    local S = ns.Sniper
    S.verified, S.background, S.lastScreen, S.lastBg = {}, nil, 0, 0
    self:Notice(on and "|cff33ff66Vendor-only mode:|r only items listed below what a vendor pays. Every deal is guaranteed profit."
        or "|cffffd100Vendor + Flips mode:|r also shows auction house resale deals (not guaranteed).", true)
    ns.Print(self.notice.text)
    self:Dirty()
end

-- Where the panel lives.
--   Auction house open: INSIDE the auction house window, covering its content
--   area, exactly its size. It opens, moves and closes with that window. The
--   "AuctionMesh" tab under the window switches between the game's screens and ours.
--   Vendor / mailbox / anywhere else: a compact free-floating window.
function UI:Place()
    local ah = AuctionHouseFrame
    local dock = ahOpen() and AuctionMeshDB.cfg.dock ~= false
    frame:ClearAllPoints()
    frame.tabBuy:ClearAllPoints()
    if dock then
        -- Inside the auction house: no border, title or close button of our own.
        -- The auction house window's own frame is the frame.
        frame:SetParent(ah)
        frame:SetScale(1)
        frame:SetPoint("TOPLEFT", ah, "TOPLEFT", 3, -22)
        frame:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -3, 3)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(false)
        frame.title:Hide(); frame.closeBtn:Hide()
        frame.tabBuy:SetPoint("TOPLEFT", 12, -6)
        frame.gold:SetPoint("TOPRIGHT", -14, -14)
    else
        frame:SetParent(UIParent)
        frame:SetScale(0.9)
        frame:SetSize(WIDTH, TOP + 44 + ROWS * ROW_H)
        frame:SetFrameStrata("HIGH")
        frame:SetMovable(true)
        frame.title:Show(); frame.closeBtn:Show()
        frame.tabBuy:SetPoint("TOPLEFT", 130, -6)
        frame.gold:SetPoint("TOPRIGHT", -34, -14)
        local pos = AuctionMeshDB.cfg.pos
        if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER", 0, 40) end
    end
    self.docked = dock
end

function UI:Open(tab)
    self:Create()
    if tab then self.tab = tab end
    local mp = ns.Deals.cfg.minProfit
    if not frame.minS:HasFocus() and not frame.minC:HasFocus() then
        frame.minS:SetText(tostring(math.floor(mp / 100)))
        frame.minC:SetText(tostring(mp % 100))
    end
    if not frame:IsShown() or (ahOpen() and AuctionMeshDB.cfg.dock ~= false) ~= (self.docked or false) then
        self:Place()
        frame:Show()
    end
    self.openedAt = GetTime()
    if self.ahTab then selectTab(self.ahTab, true); if not self.ahTab.native then self.ahTab:Enable() end end
    self:Render()
end

function UI:Close()
    if frame then frame:Hide() end
    if self.ahTab then selectTab(self.ahTab, false) end
end

function UI:Toggle()
    self:Create()
    if frame:IsShown() then self:Close() else self:Open() end
end

-- The tab under the auction house window.
function UI:CreateAHTab()
    local ah = AuctionHouseFrame
    if self.ahTab or type(ah) ~= "table" then return end
    local b = tryFrame("Button", "AuctionMeshAHTab", ah, "PanelTabButtonTemplate")
    if b then
        -- one of the game's own tabs, placed right after the game's last tab
        b.native = true
        b:SetText("AuctionMesh")
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        local tabs = rawget(ah, "Tabs")
        local last = type(tabs) == "table" and tabs[#tabs] or nil
        if type(last) == "table" and last.GetObjectType then
            b:SetPoint("LEFT", last, "RIGHT", 1, 0)
        else
            b:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 320, 2)
        end
        if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, b) end
    else
        b = CreateFrame("Button", "AuctionMeshAHTab", ah, "UIPanelButtonTemplate")
        b:SetSize(120, 24)
        b:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -8, 1)
        b:SetText("AuctionMesh")
    end
    b:SetScript("OnClick", function() UI:Toggle() end)
    self.ahTab = b
    -- Clicking one of the game's own tabs puts the game's screen back.
    if ah.SetDisplayMode and hooksecurefunc then
        hooksecurefunc(ah, "SetDisplayMode", function()
            if UI.docked and frame and frame:IsShown() and GetTime() - (UI.openedAt or 0) > 0.5 then UI:Close() end
        end)
    end
end

function UI:IsShown() return frame and frame:IsShown() end

function UI:Init()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED", "MAIL_CLOSED", "PLAYER_MONEY" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "AUCTION_HOUSE_SHOW" then
            UI:CreateAHTab()
            if frame and frame:IsShown() then frame:Hide() end -- re-place inside the auction house
            if AuctionMeshDB.cfg.autoOpen then
                -- Things to post? Start on SELL so they go up first.
                local toPost = false
                for _, e in ipairs(ns.Seller:Entries()) do if e.action == "AH" then toPost = true end end
                UI:Open(toPost and "SELL" or "BUY")
            end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            -- The docked panel leaves with the auction house window.
            if frame and UI.docked then frame:Hide(); frame:SetParent(UIParent); UI.docked = false end
            UI:Dirty()
        else
            UI:Dirty()
        end
    end)
end

return UI
