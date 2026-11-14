-- AuctionMesh UI: the one window.
--
--   [ Trades ] [ Bags ] [ Setup ]                    [######------]
--                                 Tuned: 1.6 requests a second, 94% in use
--   MONEY
--   Gold on this character now                          42g 58s 88c
--   Sold: waiting in the mailbox now                   + 1g 33s 67c
--   ...
--   -----------------------------------------------------------------
--   Total when it has all sold                          62g 53s 04c
--   NEXT  the single most useful thing to do right now
--   DEALS TO BUY NOW (2)    BUY  MARKET  SPREAD  VOLUME  PROFIT
--   [icon] Copper Ore       ...                              [ Buy ]
--
-- Trades tab: MONEY (what you hold and what it becomes once everything has
-- sold), then deals verified against live listings with the exact quantity and
-- total you will pay, then your auctions. Bags tab: everything you bought and
-- the one thing to do with it. Setup tab: settings, what the request engine
-- has learned, recent activity. A bar at the top shows what the engine is doing.
-- Rendering is throttled (5x per second, only while shown and only if changed).
local _, ns = ...
ns = ns or {}

local UI = {}
ns.UI = UI

local floor, min = math.floor, math.min
local ROWS, ROW_H, WIDTH = 10, 22, 720
local FLOAT_H, BAR_W = 520, 230 -- floating window height; width of the engine bar
local MAXROWS = 24 -- rows that exist; how many are shown depends on the panel's height
local ACCENT = { 0.30, 0.86, 0.76 }  -- teal: selected tab, primary action
local LINE = { 0.34, 0.36, 0.40 }    -- grey outline
local TEAL = "|cff4ddbc2"

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
        return ("Open |cffffd100Bags|r and press |cffffd100Post|r: %d item(s) to list for %s+%s|r."):format(n.AH, GREEN, short(gain.AH))
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

-- Column captions shown on a section's heading row.
local CAPS = {
    deal = { "BUY", "MARKET", "SPREAD", "VOLUME", "PROFIT" },
    entry = { "QTY", "COST", "MARKET", "STATUS", "P / L" },
}

local function section(list, text, caps, items)
    list[#list + 1] = { head = ("%s (%d)"):format(text, #items), caps = caps }
    for _, it in ipairs(items) do list[#list + 1] = it end
end

-- Someone listed below your price? (from the last radar read, if it is recent)
local function undercut(e)
    local St = ns.Store
    local t = St.t[e.key]
    return (t and GetServerTime() - t < 600 and St.p[e.key] < (e.listed.price or 0)) or false
end

-- What a tab lists, as one sequence of heading rows and item rows.
--   Trades: deals to buy, then your auctions (stuck, ended, listed)
--   Bags:   what you hold, grouped by what to do with it
--   Setup:  recent activity
local function buildList(tab, deals, entries)
    local list = {}
    if tab == "BUY" then
        section(list, "DEALS TO BUY NOW", CAPS.deal, deals)
        if #deals == 0 then
            list[#list + 1] = { note = ahOpen() and "None right now. A sound plays when one appears." or "Open the auction house to look for deals." }
        end
        local stuck, ended, ok = {}, {}, {}
        for _, e in ipairs(entries) do
            if e.action == "LISTED" then
                e.undercut = undercut(e)
                local t = e.live == 0 and ended or e.undercut and stuck or ok
                t[#t + 1] = e
            end
        end
        if #stuck > 0 then section(list, "STUCK LISTINGS", CAPS.entry, stuck) end
        if #ended > 0 then section(list, "ENDED, CHECK A MAILBOX", CAPS.entry, ended) end
        if #ok > 0 then section(list, "LISTED", CAPS.entry, ok) end
    elseif tab == "SELL" then
        local by = { AH = {}, VENDOR = {}, MAIL = {}, HOLD = {} }
        for _, e in ipairs(entries) do
            local t = by[e.action]
            if t then t[#t + 1] = e end
        end
        if #by.AH > 0 then section(list, "TO POST AT THE AUCTION HOUSE", CAPS.entry, by.AH) end
        if #by.VENDOR > 0 then section(list, "TO SELL TO A VENDOR", CAPS.entry, by.VENDOR) end
        if #by.MAIL > 0 then section(list, "IN THE MAILBOX", CAPS.entry, by.MAIL) end
        if #by.HOLD > 0 then section(list, "HELD, PRICE TOO LOW", CAPS.entry, by.HOLD) end
        if #list == 0 then list[1] = { note = "Nothing to sell. Items you buy on the Trades tab appear here." } end
    else
        section(list, "RECENT ACTIVITY", nil, AuctionMeshDB.history or {})
    end
    return list
end

-- MONEY: what you hold, what is already earned, what depends on a sale.
function UI:RenderMoney(entries, short)
    local Se = ns.Seller
    local waiting, onway, nextIn, soldKeys = Se:SalesMoney()
    local listed, bought, held, heldCost, ended = 0, 0, 0, 0, 0
    local cut = 1 - ns.Deals.cfg.cut
    for _, e in ipairs(entries) do
        local paid, _, net = Se:Numbers(e)
        if e.action == "LISTED" then
            if e.live == 0 then
                -- No longer listed: it sold or it expired. Counted only once a
                -- sale invoice for it has been seen at the mailbox.
                if not soldKeys[e.key] then ended = ended + 1 end
            else
                listed = listed + floor((e.listed.price or 0) * cut) * e.count
            end
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
    lg.rows[2].label:SetText("Sold: waiting in the mailbox now")
    lg.rows[2].value:SetText(plus(waiting, GREEN))
    lg.rows[3].label:SetText("Sold: still on its way")
    lg.rows[3].value:SetText(plus(onway, TEAL) .. ((onway > 0 and nextIn) and ("  %snext %s|r"):format(GREEN,
        nextIn >= 90 and (floor(nextIn / 60 + 0.5) .. " min") or (floor(nextIn) .. "s")) or ""))
    lg.rows[4].label:SetText("Listed: if it sells at the listed prices")
    lg.rows[4].value:SetText(plus(listed, ORANGE))
    lg.rows[5].label:SetText("Bought, not listed yet: at the live price")
    lg.rows[5].value:SetText(plus(bought, ORANGE))
    lg.total.label:SetText("Total when it has all sold")
    lg.total.value:SetText(short(gold + waiting + onway + listed + bought))
    local parts = {}
    if held > 0 then parts[#parts + 1] = ("%d held item%s that cost %s (tab Bags)"):format(held, held == 1 and "" or "s", short(heldCost)) end
    if ended > 0 then parts[#parts + 1] = ("%d auction%s that ended, sold or expired: a mailbox visit tells which"):format(ended, ended == 1 and "" or "s") end
    lg.note:SetText(#parts > 0 and ("Not counted: " .. table.concat(parts, "; ") .. ".")
        or "Sale amounts are after the 5% auction house cut. Sold amounts are read from the mailbox.")
end

-- The bar at the top: what the request engine is doing right now.
--   orange = measuring or trying something (the bar is its progress)
--   teal   = tuned (the bar is how much of the request budget is in use)
function UI:RenderBar()
    local paused
    if not ahOpen() then paused = "Idle: the auction house is closed"
    elseif ns.Gate:UserBusy() then paused = "Paused while you click"
    elseif not ns.Sniper.active then paused = "Idle" end
    local st = ns.Tuner:State(paused)
    local bar = frame.bar
    local w = floor(math.max(0, math.min(1, st.fill)) * (BAR_W - 2) + 0.5)
    bar.fill:SetShown(w > 0)
    bar.fill:SetWidth(math.max(1, w))
    if st.mode == "try" then bar.fill:SetColorTexture(1, 0.55, 0.25, 1)
    else bar.fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
    frame.barText:SetText((st.mode == "try" and ORANGE or GREY) .. st.text .. "|r")
    self.barState = st
end

-- Setup tab: the settings and what the request engine has learned.
function UI:RenderSetup()
    local sp = frame.setup
    sp.flips:SetText(ns.Deals.cfg.flips and "Vendor deals + flips" or "Vendor deals only")
    sp.tune:SetText(ns.Tuner.cfg.enabled and "Self-tuning: on" or "Self-tuning: off")
    local lines = ns.Tuner:Lines()
    for i = 1, #sp.rows do
        local l = lines[i]
        sp.rows[i].label:SetText(l and l[1] or "")
        sp.rows[i].value:SetText(l and (GREY .. l[2] .. "|r") or "")
    end
end

function UI:Render()
    self.dirty = false
    if not frame or not frame:IsShown() then return end
    local Se, short = ns.Seller, ns.Seller.short
    local deals, entries = buyRows(), Se:Entries()
    local tab = self.tab
    self:Layout()
    self:RenderBar()
    if tab == "BUY" then self:RenderMoney(entries, short) end
    if tab == "HISTORY" then self:RenderSetup() end

    local todo = 0
    for _, e in ipairs(entries) do if e.action ~= "LISTED" then todo = todo + 1 end end
    frame.tabBuy:SetText(#deals > 0 and ("Trades (%d)"):format(#deals) or "Trades")
    frame.tabSell:SetText(todo > 0 and ("Bags (%d)"):format(todo) or "Bags")
    UI.selectTab(frame.tabBuy, tab == "BUY")
    UI.selectTab(frame.tabSell, tab == "SELL")
    UI.selectTab(frame.tabHist, tab == "HISTORY")

    frame.next:SetText(TEAL .. "NEXT|r  " .. nextStep(deals, entries, short))
    local status = tab == "BUY" and buyStatus(#deals) or tab == "SELL" and Se:Instructions(entries) or ""
    local n = self.notice
    if n and GetTime() < n.till then
        status = n.text
    elseif tab == "SELL" and ahOpen() and ns.Gate:UserBusy() then
        status = ORANGE .. "Paused for a moment (a click is in progress).|r " .. status
    end
    frame.status:SetText(status)

    -- as many rows as the panel's height holds; the mouse wheel scrolls the rest
    local list = buildList(tab, deals, entries)
    local h = frame:GetHeight()
    local vis = type(h) == "number" and h > 0 and math.max(3, math.min(MAXROWS, floor((h - self.listTop - 36) / ROW_H))) or ROWS
    self.vis = vis
    self.scroll = self.scroll or {}
    local off = math.max(0, math.min(self.scroll[tab] or 0, #list - vis))
    self.scroll[tab] = off
    for i = 1, MAXROWS do
        local r, item = rows[i], (i <= vis) and list[i + off] or nil
        r.item, r.sect = nil, nil
        r.sel:SetShown(item ~= nil and item.key ~= nil and item.key == self.sel and AuctionMeshDB.cfg.drawer == true)
        if not item then r:Hide() else
            local plain = item.head or item.note
            r.head:SetText(plain and (GREY .. plain .. "|r") or "")
            r.rule:SetShown(item.head ~= nil)
            r.bg:SetShown(not plain and i % 2 == 1)
            if plain then
                -- a section heading (with its column captions) or a one-line remark
                r.sect = item
                r.icon:SetTexture(nil)
                r.name:SetText(""); r.state:SetText(""); r.detail:Hide(); r.btn:Hide()
                local caps = item.caps
                for c = 1, 4 do r.c[c]:SetText(caps and (GREY .. caps[c] .. "|r") or "") end
                r.profit:SetText(caps and (GREY .. caps[5] .. "|r") or "")
            elseif item.m then
                local age = GetServerTime() - item.t
                r.icon:SetTexture(nil)
                r.name:SetText(GREY .. (age < 90 and (age .. "s ago") or age < 5400 and (floor(age / 60) .. " min ago")
                    or (floor(age / 3600) .. " h ago")) .. "|r")
                for c = 1, 4 do r.c[c]:SetText("") end
                r.state:SetText(""); r.profit:SetText(""); r.btn:Hide()
                r.detail:SetText(item.m)
                r.detail:Show()
            else
                r.item = item
                r.detail:Hide()
                r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
                if item.action then fillSell(r, item, short) else fillBuy(r, item, short) end
            end
            r:Show()
        end
    end

    -- Footer: one line of totals for the tab.
    local parts = {}
    if tab == "BUY" then
        if #deals > 0 then
            local total = 0
            for _, d in ipairs(deals) do total = total + d.profit end
            parts[#parts + 1] = ("Make now  %s+ %s|r  %s(%d deal%s)|r"):format(GREEN, short(total), GREY, #deals, #deals == 1 and "" or "s")
        end
        local rz = AuctionMeshDB.realized or 0
        parts[#parts + 1] = ("%sBanked so far|r  %s%s%s|r"):format(GREY, rz >= 0 and GREEN or RED, rz >= 0 and "+ " or "- ", short(math.abs(rz)))
        local made = rz - (ns.realizedAtLogin or 0)
        local hours = (GetTime() - (ns.sessionStart or GetTime())) / 3600
        if made ~= 0 and hours > 0.05 then
            parts[#parts + 1] = ("%sThis session|r  %s%s%s|r %s(%s an hour)|r"):format(GREY, made >= 0 and GREEN or RED,
                made >= 0 and "+ " or "- ", short(math.abs(made)), GREY, short(made / hours))
        end
    elseif tab == "SELL" then
        local invested, back, any = 0, 0, false
        for _, e in ipairs(entries) do
            local paid, _, net = Se:Numbers(e)
            if paid and e.action ~= "LISTED" then invested, back, any = invested + paid * e.count, back + net * e.count, true end
        end
        if any then
            local profit = back - invested
            parts[#parts + 1] = ("Holding: paid %s  >  expect back %s  =  %s%s%s|r"):format(short(invested), short(back),
                profit >= 0 and GREEN or RED, profit >= 0 and "+ " or "- ", short(math.abs(profit)))
        end
    else
        parts[#parts + 1] = GREY .. ns.Learn:Summary() .. "|r"
    end
    if #list > vis then
        parts[#parts + 1] = ("%srows %d-%d of %d (mouse wheel)|r"):format(GREY, off + 1, math.min(#list, off + vis), #list)
    end
    frame.footer:SetText(table.concat(parts, "    "))

    frame.post:SetShown(tab == "SELL" and ahOpen())
    do  -- vendor sales always need your click
        local nv, gain = 0, 0
        for _, e in ipairs(entries) do
            if e.action == "VENDOR" then nv = nv + 1; gain = gain + (e.f.sell or 0) * e.count end
        end
        frame.vend:SetShown(tab == "SELL" and merchantOpen() and nv > 0 and not ahOpen())
        frame.vend:SetText(("Sell all to vendor  +%s"):format((short(gain):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
    end
    self:RenderDrawer(entries)
end

---------------------------------------------------------------- clicks

local function rowButton(self)
    local item = self:GetParent().item
    if not item then return end
    if not item.action then
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
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(item.key)
    local st, dt = self.state:GetText(), self.detail:GetText()
    if st and st ~= "" then GameTooltip:AddLine(st, 1, 1, 1, true) end
    if dt and dt ~= "" then GameTooltip:AddLine(dt, 0.8, 0.8, 0.8, true) end
    if item.action then
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
        GameTooltip:AddLine(GREY .. "Click: details and what to do. Right-click: remove from this list|r")
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
        GameTooltip:AddLine(GREY .. "Click: everything known about this item|r")
    end
    GameTooltip:Show()
end

local function rowMouseUp(self, button)
    if GetCursorInfo() then return ns.Seller.AcceptDrop() end
    if button == "RightButton" and self.item and self.item.action then return ns.Seller:Untrack(self.item.key) end
    -- left click: this item's details in the drawer
    if self.item and self.item.key and button ~= "RightButton" then
        UI.sel, UI.dscroll = self.item.key, 0
        UI:ToggleDrawer(true)
    end
end

---------------------------------------------------------------- window

-- FLAT STYLE (the layout the user picked): dark panel, one-pixel outlines, a
-- teal outline on what is selected or primary, grey small-caps section
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
    return button(parent, 86, text, onClick)
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

local function heading(parent, y, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 0, y)
    h:SetText(text)
    return h
end

function UI:Create()
    if frame then return end
    frame = CreateFrame("Frame", "AuctionMeshFrame", UIParent)
    frame:SetSize(WIDTH, FLOAT_H)
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
    -- the mouse wheel scrolls the list
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        UI.scroll = UI.scroll or {}
        UI.scroll[UI.tab] = math.max(0, (UI.scroll[UI.tab] or 0) - (delta or 0) * 3)
        UI:Render()
    end)

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
    frame.tabBuy = makeTab(frame, "Trades", function() UI.tab = "BUY"; UI:Render() end)
    frame.tabSell = makeTab(frame, "Bags", function() UI.tab = "SELL"; UI:Render() end)
    frame.tabHist = makeTab(frame, "Setup", function() UI.tab = "HISTORY"; UI:Render() end)
    frame.tabSell:SetPoint("LEFT", frame.tabBuy, "RIGHT", 6, 0)
    frame.tabHist:SetPoint("LEFT", frame.tabSell, "RIGHT", 6, 0)

    -- ENGINE BAR, top right on every tab: what the request engine is doing now
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(BAR_W, 8)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.09, 0.10, 0.12, 1)
    outline(bar, LINE)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1); bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetWidth(1)
    frame.bar = bar
    frame.barText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.barText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
    frame.barText:SetWidth(300)
    frame.barText:SetJustifyH("RIGHT"); frame.barText:SetWordWrap(false)

    -- NEXT STEP: one plain instruction, always the most profitable thing to do now
    frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.next:SetJustifyH("LEFT"); frame.next:SetWordWrap(false)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetJustifyH("LEFT"); frame.status:SetJustifyV("TOP")

    -- MONEY (Trades tab): the answer to "how much do I really have?"
    local lg = CreateFrame("Frame", nil, frame)
    lg:SetPoint("TOPLEFT", 14, -40); lg:SetPoint("TOPRIGHT", -14, -40)
    lg:SetHeight(134)
    lg.title = heading(lg, 0, "MONEY")
    lg.rows = {}
    for i = 1, 5 do lg.rows[i] = ledgerRow(lg, -16 - (i - 1) * 15) end
    lg.rule = lg:CreateTexture(nil, "ARTWORK")
    lg.rule:SetPoint("TOPLEFT", 0, -93); lg.rule:SetPoint("TOPRIGHT", 0, -93); lg.rule:SetHeight(1)
    lg.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    lg.total = ledgerRow(lg, -99, "GameFontHighlight")
    lg.note = lg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lg.note:SetPoint("TOPLEFT", 0, -119); lg.note:SetPoint("TOPRIGHT", 0, -119)
    lg.note:SetJustifyH("LEFT"); lg.note:SetWordWrap(false)
    lg:Hide()
    frame.ledger = lg

    -- SETUP tab: settings, then what the request engine has learned
    local sp = CreateFrame("Frame", nil, frame)
    sp:SetPoint("TOPLEFT", 14, -40); sp:SetPoint("TOPRIGHT", -14, -40)
    sp:SetHeight(250)
    heading(sp, 0, "SETTINGS")
    local function setting(y, text)
        local l = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 0, y)
        l:SetText(text)
    end
    local function box(suffix)
        local e = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
        e:SetSize(30, 20)
        e:SetAutoFocus(false)
        e:SetNumeric(true)
        e:SetMaxLetters(3)
        local s = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetPoint("LEFT", e, "RIGHT", 2, 0)
        s:SetText(suffix)
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEditFocusLost", function() UI:ApplyMinProfit() end)
        return e
    end
    setting(-20, "Smallest profit worth showing a deal for")
    frame.minC = box("c")
    frame.minC:SetPoint("TOPRIGHT", -12, -15)
    frame.minS = box("s")
    frame.minS:SetPoint("RIGHT", frame.minC, "LEFT", -18, 0)
    setting(-44, "What to look for")
    sp.flips = button(sp, 150, "Vendor deals + flips", function() UI:SetVendorOnly(ns.Deals.cfg.flips) end)
    sp.flips:SetPoint("TOPRIGHT", 0, -39)
    setting(-68, "Request engine and its log (to share when something looks wrong)")
    local log = button(sp, 50, "Log", function() ns.Diag:Show() end)
    log:SetPoint("TOPRIGHT", 0, -63)
    sp.tune = button(sp, 110, "Self-tuning: on", function()
        local on = not ns.Tuner.cfg.enabled
        ns.Tuner.cfg.enabled, AuctionMeshDB.cfg.tune = on, on
        UI:Notice(on and "Self-tuning on: the pace and the split of requests adjust themselves."
            or "Self-tuning off: pace and split stay as they are now (still measured).", true)
    end)
    sp.tune:SetPoint("RIGHT", log, "LEFT", -6, 0)
    heading(sp, -112, "REQUEST ENGINE: WHAT IT HAS LEARNED")
    sp.rows = {}
    for i = 1, 8 do sp.rows[i] = ledgerRow(sp, -128 - (i - 1) * 15) end
    sp:Hide()
    frame.setup = sp

    for i = 1, MAXROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetHeight(ROW_H - 2)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.035)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.10)
        -- teal edge on the row whose details are open in the drawer
        r.sel = r:CreateTexture(nil, "ARTWORK")
        r.sel:SetPoint("TOPLEFT", 0, 0); r.sel:SetPoint("BOTTOMLEFT", 0, 0); r.sel:SetWidth(2)
        r.sel:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        r.sel:Hide()
        -- section heading: grey small caps over a thin rule
        r.head = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.head:SetPoint("LEFT", 4, 0)
        r.head:SetJustifyH("LEFT"); r.head:SetWordWrap(false)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetPoint("BOTTOMLEFT", 0, 0); r.rule:SetPoint("BOTTOMRIGHT", 0, 0); r.rule:SetHeight(1)
        r.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 0.6)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(17, 17); r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", 28, 0)
        r.name:SetWidth(COLS[1][2] + 8); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.c = {}
        for n = 2, 5 do
            local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f:SetPoint("LEFT", COLS[n][1], 0)
            f:SetWidth(COLS[n][2]); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
            r.c[n - 1] = f
        end
        -- One line per row. The longer explanation and status are kept for the
        -- tooltip (and shown in place only for recent activity).
        r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail:SetPoint("LEFT", COLS[2][1] - 60, 0)
        r.detail:SetPoint("RIGHT", -8, 0)
        r.detail:SetJustifyH("LEFT"); r.detail:SetWordWrap(false)
        r.detail:Hide()
        r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.state:Hide()
        r.profit = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.profit:SetPoint("RIGHT", -74, 0)
        r.profit:SetWidth(110); r.profit:SetJustifyH("RIGHT"); r.profit:SetWordWrap(false)
        r.btn = button(r, 64, "Buy", rowButton)
        r.btn:SetHeight(18)
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
    frame.footer:SetPoint("BOTTOMRIGHT", -230, 12)
    frame.footer:SetJustifyH("LEFT"); frame.footer:SetWordWrap(false)
    frame.vend = button(frame, 210, "Sell all to vendor", function() ns.Seller:SellVendor() end)
    frame.vend:SetPoint("BOTTOMRIGHT", -12, 7)
    outline(frame.vend, ACCENT)
    frame.post = button(frame, 96, "Post next", function() ns.Seller:PostNext() end, "AuctionMeshPostButton")
    frame.post:SetPoint("BOTTOMRIGHT", -12, 7)
    outline(frame.post, ACCENT)

    -- Throttled redraw: at most 5 per second, and only when something changed.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        if UI.notice and GetTime() >= UI.notice.till then UI.notice = nil; UI.dirty = true end
        local paused = ns.Gate:UserBusy()
        if paused ~= UI.wasPaused then UI.wasPaused = paused; UI.dirty = true end
        -- Timers and the engine bar tick twice a second while the auction house is open.
        UI.tick = (UI.tick or 0) + 1
        if ahOpen() and UI.tick % 3 == 0 then UI.dirty = true end
        if UI.dirty then UI:Render() end
    end)
    self:CreateDrawer()
    frame:Hide()
end

-- Where things sit depends on the tab.
--   Trades: MONEY on top, then the NEXT line, the timers, the list
--   Bags:   the NEXT line, what to do, the list
--   Setup:  settings and the request engine, then recent activity
local LAYOUT = {
    BUY = { next = -182, status = -200, statusH = 38, top = 246 },
    SELL = { next = -40, status = -58, statusH = 38, top = 104 },
    HISTORY = { status = -134, statusH = 14, top = 296 },
}
function UI:Layout()
    local tab = self.tab
    local L = LAYOUT[tab]
    self.listTop = L.top
    if self.layoutKey == tab then return end
    self.layoutKey = tab
    frame.ledger:SetShown(tab == "BUY")
    frame.setup:SetShown(tab == "HISTORY")
    frame.next:SetShown(L.next ~= nil)
    if L.next then
        frame.next:ClearAllPoints()
        frame.next:SetPoint("TOPLEFT", 14, L.next); frame.next:SetPoint("TOPRIGHT", -14, L.next)
    end
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOPLEFT", 14, L.status); frame.status:SetPoint("TOPRIGHT", -14, L.status)
    frame.status:SetHeight(L.statusH)
    for i = 1, MAXROWS do
        local r = rows[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -L.top - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -L.top - (i - 1) * ROW_H)
    end
end

-- Reads the two "smallest profit" boxes and applies them right away.
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
    frame.bar:ClearAllPoints()
    if dock then
        -- Inside the auction house: no title or close button of our own.
        frame:SetParent(ah)
        frame:SetScale(1)
        frame:SetPoint("TOPLEFT", ah, "TOPLEFT", 3, -22)
        frame:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -3, 3)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(false)
        frame.title:Hide(); frame.closeBtn:Hide()
        frame.tabBuy:SetPoint("TOPLEFT", 12, -8)
        frame.bar:SetPoint("TOPRIGHT", -14, -9)
    else
        frame:SetParent(UIParent)
        frame:SetScale(0.9)
        frame:SetSize(WIDTH, FLOAT_H)
        frame:SetFrameStrata("HIGH")
        frame:SetMovable(true)
        frame.title:Show(); frame.closeBtn:Show()
        frame.tabBuy:SetPoint("TOPLEFT", 130, -8)
        frame.bar:SetPoint("TOPRIGHT", -34, -9)
        local pos = AuctionMeshDB.cfg.pos
        if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER", 0, 40) end
    end
    self.docked = dock
end

---------------------------------------------------------------- detail drawer

-- A panel that slides out on the right: every trade from purchase to sale
-- with its profit, and one recommendation per open trade. Clicking an item
-- row on the left shows that item alone, with everything known about it.
local DRAWER_W, DLINES, DLINE_H = 400, 34, 15
local WHITE = "|cffffffff"

local function ago(t)
    local age = GetServerTime() - (t or GetServerTime())
    if age < 90 then return age .. "s ago" end
    if age < 5400 then return floor(age / 60) .. " min ago" end
    if age < 48 * 3600 then return floor(age / 3600) .. " h ago" end
    return floor(age / 86400) .. " days ago"
end

-- breaks plain text into lines of about `width` characters, at spaces
local function wrap(text, width)
    local out, line = {}, ""
    local function len(s) return #(s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end -- colour codes take no room
    for word in tostring(text):gmatch("%S+") do
        if #line > 0 and len(line) + 1 + len(word) > width then out[#out + 1] = line; line = word
        else line = (#line > 0) and (line .. " " .. word) or word end
    end
    if #line > 0 then out[#out + 1] = line end
    return out
end

local function signed(c, short) return (c >= 0 and "+ " or "- ") .. short(math.abs(c)) end

local TONE = { ["do"] = { TEAL, "DO" }, wait = { GREY, "WAIT" }, warn = { ORANGE, "CHECK" } }

-- one recommendation, wrapped, with its tone word in front of the first line
local function adviceLines(out, e)
    local text, tone = ns.Seller:Advice(e)
    local t = TONE[tone] or TONE.wait
    text = text:gsub("^Wait%. ", "") -- the tone word in front already says it
    for i, l in ipairs(wrap(text, 56)) do
        out[#out + 1] = { l = (i == 1 and (t[1] .. t[2] .. "|r  ") or "         ") .. l, advice = i == 1 and tone or nil }
    end
end

-- the lines of one trade: bought, what became of it, profit, what to do
local function tradeLines(out, t, byKey, short)
    local J, Se = ns.Journal, ns.Seller
    local left = J.left(t)
    out[#out + 1] = { l = WHITE .. tostring(t.name) .. " x" .. t.qty .. "|r", r = GREY .. ago(t.at) .. "|r", trade = t }
    out[#out + 1] = { l = t.cost and ("Bought at %s each"):format(short(t.cost)) or "Bought (cost not known)",
        r = t.cost and ("- " .. short(t.cost * t.qty)) or (GREY .. "?|r") }
    local sold, vend = t.sold or 0, t.vend or 0
    if sold > 0 and vend == 0 then
        out[#out + 1] = { l = ("Sold %d at %s each, after the cut"):format(sold, short(t.soldPrice or 0)), r = GREEN .. "+ " .. short(t.got or 0) .. "|r" }
    elseif vend > 0 and sold == 0 then
        out[#out + 1] = { l = ("Sold %d to a vendor at %s each"):format(vend, short(t.vendPrice or 0)), r = GREEN .. "+ " .. short(t.got or 0) .. "|r" }
    elseif sold > 0 then
        out[#out + 1] = { l = ("Sold %d at auction and %d to a vendor"):format(sold, vend), r = GREEN .. "+ " .. short(t.got or 0) .. "|r" }
    end
    if (t.expired or 0) > 0 then
        out[#out + 1] = { l = GREY .. ("Came back unsold %d time%s|r"):format(t.expired, t.expired == 1 and "" or "s") }
    end
    if (t.lost or 0) > 0 then
        out[#out + 1] = { l = GREY .. ("%d not counted: %s|r"):format(t.lost, tostring(t.lostWhy or "removed")) }
    end
    local made = J.realized(t)
    if made then
        out[#out + 1] = { l = left > 0 and "Profit made so far" or "Profit made", r = (made >= 0 and GREEN or RED) .. signed(made, short) .. "|r" }
    end
    if left > 0 then
        local listed = math.min(t.listed or 0, left)
        local expect, known = 0, t.cost ~= nil
        if listed > 0 then
            local net = floor((t.price or 0) * (1 - ns.Deals.cfg.cut)) * listed
            expect = expect + net
            out[#out + 1] = { l = ("On the auction house: %d at %s each"):format(listed, short(t.price or 0)), r = ORANGE .. "+ " .. short(net) .. "|r" }
        end
        local rest = left - listed
        local held
        for _, e in ipairs(byKey[t.key] or {}) do if e.action ~= "LISTED" then held = held or e end end
        if rest > 0 then
            if held then
                local _, _, net = Se:Numbers(held)
                expect = expect + (net or 0) * rest
                local where = held.action == "MAIL" and "In the mailbox" or held.action == "HOLD" and "Held in your bags" or "In your bags"
                out[#out + 1] = { l = ("%s: %d, at the live price"):format(where, rest), r = ORANGE .. "+ " .. short((net or 0) * rest) .. "|r" }
            else
                known = false
                out[#out + 1] = { l = GREY .. ("%d not found in bags or mailbox yet|r"):format(rest) }
            end
        end
        if known then
            local p = expect - t.cost * left
            out[#out + 1] = { l = "Profit if this sells", r = (p >= 0 and ORANGE or RED) .. signed(p, short) .. "|r" }
        end
        -- what to do: one recommendation per state this trade is in
        for _, e in ipairs(byKey[t.key] or {}) do
            if (e.action == "LISTED" and listed > 0) or (e.action ~= "LISTED" and rest > 0) then adviceLines(out, e) end
        end
    end
    out[#out + 1] = { rule = true }
end

-- everything the drawer shows, as a flat list of lines
function UI:DrawerLines(entries)
    local J, Se, S, St = ns.Journal, ns.Seller, ns.Sniper, ns.Store
    local short = Se.short
    local out, byKey = {}, {}
    for _, e in ipairs(entries) do
        byKey[e.key] = byKey[e.key] or {}
        table.insert(byKey[e.key], e)
    end
    local key = self.sel
    if key then
        -- ONE ITEM: the market as last read, then your trades in it
        local now = GetServerTime()
        out[#out + 1] = { l = WHITE .. S.nameOf(key) .. "|r", big = true }
        out[#out + 1] = { head = "MARKET" }
        local function fact(l, v) out[#out + 1] = { l = l, r = v or (GREY .. "not known yet|r") } end
        fact("Cheapest listing", St.p[key] and (short(St.p[key]) .. GREY .. "  " .. ago(St.t[key]) .. "|r"))
        local ft = St.ft[key]
        fact("Market price, from the full listing", (ft and St.fp[key]) and (short(St.fp[key]) .. GREY .. "  " .. ago(ft) .. "|r"))
        local tr = St:Trend(key, now, 24)
        fact("Change in 24 hours", tr and ((tr >= 0 and GREEN or RED) .. ("%+d%%|r"):format(floor(tr * 100 + 0.5))))
        local rate = St:Rate(key, 100)
        fact("Sold per hour, measured", rate and tostring(floor(rate + 0.5)))
        local paid = St:Sold(key, now, 48 * 3600)
        fact("Buyers really paid, last 48h", paid and short(paid))
        local v = S.vendorOf(key)
        fact("A vendor pays", v and v > 0 and short(v) or (GREY .. "nothing|r"))
        local why = S.reasons and S.reasons[key]
        if why then
            why = tostring(why):gsub("%$(%d+)", function(c) return short(tonumber(c)) end)
            for i, l in ipairs(wrap("Last check: " .. why, 60)) do out[#out + 1] = { l = GREY .. l .. "|r" } end
        end
        local trades = J:Trades(key)
        out[#out + 1] = { head = ("YOUR TRADES IN THIS ITEM (%d)"):format(#trades) }
        if #trades == 0 then out[#out + 1] = { l = GREY .. "You have not bought this item with the addon.|r" } end
        for _, t in ipairs(trades) do tradeLines(out, t, byKey, short) end
        return out
    end
    -- EVERYTHING: totals, open trades, finished trades
    local s = J:Totals()
    local trades = J:Trades()
    local open, done, expect = {}, {}, 0
    for _, t in ipairs(trades) do
        if J.left(t) > 0 then open[#open + 1] = t else done[#done + 1] = t end
    end
    for _, e in ipairs(entries) do
        local paid, _, net = Se:Numbers(e)
        if paid and e.action ~= "HOLD" and not (e.action == "LISTED" and e.live == 0) then
            local each = e.action == "LISTED" and floor((e.listed.price or 0) * (1 - ns.Deals.cfg.cut)) or net
            expect = expect + (each - paid) * e.count
        end
    end
    out[#out + 1] = { head = "ALL TRADES" }
    out[#out + 1] = { l = "Bought so far", r = ("%d trade%s, %s spent"):format(s.trades, s.trades == 1 and "" or "s", short(s.spent)) }
    out[#out + 1] = { l = "Finished / still open", r = ("%d / %d"):format(s.finished, s.open) }
    out[#out + 1] = { l = "Profit made on what has sold", r = (s.profit >= 0 and GREEN or RED) .. signed(s.profit, short) .. "|r" }
    out[#out + 1] = { l = "Profit if everything open sells", r = (expect >= 0 and ORANGE or RED) .. signed(expect, short) .. "|r" }
    out[#out + 1] = { head = ("OPEN (%d)"):format(#open) }
    if #open == 0 then out[#out + 1] = { l = GREY .. "Nothing open. Buy a deal on the Trades tab.|r" } end
    for _, t in ipairs(open) do tradeLines(out, t, byKey, short) end
    out[#out + 1] = { head = ("FINISHED (%d)"):format(#done) }
    if #done == 0 then out[#out + 1] = { l = GREY .. "Nothing has sold yet.|r" } end
    for _, t in ipairs(done) do tradeLines(out, t, byKey, short) end
    return out
end

function UI:CreateDrawer()
    local d = CreateFrame("Frame", "AuctionMeshDrawer", frame)
    d:SetWidth(DRAWER_W)
    d:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0)
    d:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 1, 0)
    d:EnableMouse(true)
    d.art = d:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.art:SetAllPoints()
    d.art:SetColorTexture(0.045, 0.05, 0.06, 0.97)
    outline(d, LINE)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.title:SetPoint("TOPLEFT", 12, -14)
    d.title:SetText("DETAILS")
    d.all = button(d, 90, "All trades", function() UI.sel = nil; UI.dscroll = 0; UI:Render() end)
    d.all:SetPoint("TOPRIGHT", -12, -8)
    d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.hint:SetPoint("BOTTOMLEFT", 12, 10)
    d.hint:SetPoint("BOTTOMRIGHT", -12, 10)
    d.hint:SetJustifyH("LEFT"); d.hint:SetWordWrap(false)
    d.lines = {}
    for i = 1, DLINES do
        local y = -38 - (i - 1) * DLINE_H
        local l = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 12, y)
        l:SetJustifyH("LEFT"); l:SetWordWrap(false)
        local v = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        v:SetPoint("TOPRIGHT", -12, y)
        v:SetJustifyH("RIGHT"); v:SetWordWrap(false)
        local rule = d:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 12, y - 7); rule:SetPoint("TOPRIGHT", -12, y - 7); rule:SetHeight(1)
        rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 0.6)
        d.lines[i] = { label = l, value = v, rule = rule }
    end
    d:EnableMouseWheel(true)
    d:SetScript("OnMouseWheel", function(_, delta)
        UI.dscroll = math.max(0, (UI.dscroll or 0) - (delta or 0) * 4)
        UI:Render()
    end)
    d:Hide()
    frame.drawer = d

    -- the handle on the panel's right edge: opens and closes the drawer
    local h = button(frame, 18, "", function() UI:ToggleDrawer() end)
    h:SetHeight(112)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Details")
        GameTooltip:AddLine("Every trade from purchase to sale, its profit,\nand what to do with what you hold.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.handle = h
    self:PlaceDrawer()
end

function UI:PlaceDrawer()
    local d, h = frame.drawer, frame.handle
    local open = AuctionMeshDB.cfg.drawer == true
    d:SetShown(open)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", open and d or frame, "TOPRIGHT", 0, -40)
    h:SetText(open and "<\n\nH\nI\nD\nE" or ">\n\nD\nE\nT\nA\nI\nL\nS")
end

function UI:ToggleDrawer(on)
    self:Create()
    if on == nil then on = not (AuctionMeshDB.cfg.drawer == true) end
    AuctionMeshDB.cfg.drawer = on and true or false
    self:PlaceDrawer()
    self:Render()
end

function UI:RenderDrawer(entries)
    local d = frame.drawer
    if not d or not d:IsShown() then return end
    local lines = self:DrawerLines(entries)
    self.drawerLines = lines
    local h = frame:GetHeight()
    local vis = type(h) == "number" and h > 0 and math.max(6, math.min(DLINES, floor((h - 38 - 28) / DLINE_H))) or 28
    local off = math.max(0, math.min(self.dscroll or 0, #lines - vis))
    self.dscroll = off
    d.all:SetShown(self.sel ~= nil)
    d.title:SetText(self.sel and "DETAILS: ONE ITEM" or "DETAILS")
    for i = 1, DLINES do
        local w, ln = d.lines[i], (i <= vis) and lines[i + off] or nil
        if not ln then
            w.label:SetText(""); w.value:SetText(""); w.rule:Hide()
        else
            w.rule:SetShown(ln.rule == true)
            w.label:SetWidth(ln.r and (DRAWER_W - 24 - 130) or (DRAWER_W - 24))
            w.label:SetText(ln.head and (GREY .. ln.head .. "|r") or ln.l or "")
            w.value:SetText(ln.r or "")
        end
    end
    d.hint:SetText(#lines > vis and ("lines %d-%d of %d (mouse wheel). Click an item on the left for its details."):format(off + 1, math.min(#lines, off + vis), #lines)
        or "Click an item on the left for its details.")
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
