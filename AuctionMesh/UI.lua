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
-- Trades tab: SNIPING ONLY. MONEY (what you hold and what it becomes once
-- everything has sold), then deals verified against live listings with the
-- exact quantity and total you will pay. Bags tab: everything you bought and
-- the one thing to do with it, then your own auctions (sold, undercut with a
-- Cancel button, ended, listed). Setup tab: settings, what the request engine
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
local WHITE_C = "|cffffffff"

local frame, rows = nil, {}

local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function mailOpen() return MailFrame and MailFrame:IsShown() end

function UI:Dirty() self.dirty = true end
-- Draw right now (a deal appeared, a purchase changed state): the usual
-- redraw runs at most 5 times a second, which is too slow for sniping.
function UI:Now()
    if frame and frame:IsShown() then
        -- the drawer (Details) is not rebuilt on this path: it follows on the
        -- next ordinary redraw, a fifth of a second later at most
        self.fast = true
        self:Render()
        self.fast = nil
        if self.drawerStale then self.dirty = true end
    else
        self.dirty = true
    end
end

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
    if S:OneClick(d.key) then
        r.btn:SetText("BUY NOW"); r.btn:Enable()
    elseif b and b.key == d.key then
        r.btn:SetText("..."); r.btn:Enable() -- keep clicking: the click that lands after the price is in buys
    else
        r.btn:SetText("Buy")
        r.btn:SetEnabled(not b)
    end
    r.btn:Show()
end

local STATE = {
    -- The Post button is on the row whenever the auction house is open. With
    -- no live price yet, a click on it asks for the price first.
    AH = function(e, ready, busy)
        if not ahOpen() then
            -- bought under vendor price but worth more on the auction house: at a vendor it can still be sold, for less
            if e.vendorAlt and merchantOpen() then return GOLD .. "Worth more on the auction house|r", "Sell" end
            return GOLD .. (e.vendorAlt and "Post it: worth more than at a vendor|r" or "Open the AH to post|r"), nil
        end
        if ready then return GOLD .. "Ready to post|r", "Post" end
        if busy then return GREY .. "Checking the price...|r", "Post" end
        return GREY .. "Price check is next|r", "Post"
    end,
    VENDOR = function() return GREEN .. "Sell to any vendor|r", merchantOpen() and "Sell" or nil end,
    MAIL = function(e) return BLUE .. (e.seen and "In your mailbox" or "In your mailbox (not checked yet)") .. "|r", nil end,
    HOLD = function() return RED .. "Waiting: market is below your cost|r", ahOpen() and "Re-check" or nil end,
    LISTED = function(e)
        if e.sold then
            return GREEN .. (e.soldIn and ("Sold: gold arrives in %d min"):format(math.max(1, floor(e.soldIn / 60 + 0.5))) or "Sold: gold is on its way") .. "|r", nil
        end
        if e.live == 0 then return GREEN .. "Sold or expired: check your mailbox|r", nil end
        if e.undercut then
            -- CANCEL, to post it again under the cheaper seller. Two clicks on
            -- the same button: "Cancel", then "Sure?".
            local Se = ns.Seller
            if Se.cancelling and Se.cancelling.key == e.key then return GOLD .. "Cancelling...|r", nil end
            local can = ahOpen() and #Se:Cancellable(e.key) > 0
            local arm = Se.cancelArm
            local armed = arm and arm.key == e.key and GetTime() - arm.at < 5
            return ORANGE .. "Listed, but someone is cheaper|r", can and (armed and "Sure?" or "Cancel") or nil
        end
        return GREY .. "Listed for sale|r", nil
    end,
}

local function fillSell(r, e, short)
    local Se = ns.Seller
    local name = ns.Sniper.nameOf(e.key)
    r.name:SetText(e.count > 1 and (name .. " x" .. e.count) or name)
    local ready = Se:PriceReady(e.key)
    local busy = Se.pending and Se.pending.key == e.key
    if Se.posting and Se.posting.key == e.key then busy = true end
    local text, button = STATE[e.action](e, ready, busy)
    if Se.posting and Se.posting.key == e.key then text = GOLD .. "Posting...|r" end
    -- why the last press of Post did nothing, right next to the button
    local why = (e.action == "AH" and Se:NoteFor(e.key)) or (e.action == "LISTED" and Se:NoteFor(e.key, "cancel"))
    if why then text = ORANGE .. why .. "|r" end
    r.state:SetText(text)
    local paid, sell, _, profit, live = Se:Numbers(e)
    r.c[1]:SetText(tostring(e.count))
    r.c[2]:SetText(paid and short(paid) or (ORANGE .. "?|r"))
    r.c[3]:SetText(short(sell) .. ((e.f.kind == "FLIP" and not live and e.action ~= "LISTED") and (GREY .. "*|r") or ""))
    r.c[4]:SetText(e.action == "LISTED" and (e.sold and (GREEN .. "SOLD|r") or e.live == 0 and (GREEN .. "SOLD?|r") or e.undercut and (ORANGE .. "UNDERCUT|r") or (GREY .. "LISTED|r"))
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
        -- A VENDOR WOULD PAY MORE THAN IT COST: both ways out on the row, with
        -- the difference. Vendor now, or wait (for the fee, for the sale) and list it.
        local c = Se:Choice(e)
        if c and e.action == "VENDOR" then
            -- IF LISTED: what waiting and listing brings on top of the vendor (or loses)
            r.c[4]:SetText(c.ah and (c.diff > 0 and ((c.short and ORANGE or GREEN) .. "+" .. short(c.diff) .. " more|r") or (GREY .. short(-c.diff) .. " less|r"))
                or c.held and (GREY .. "less|r") or (GREY .. "?|r"))
        elseif c and e.vendorAlt and c.ah then
            -- VENDOR NOW: what the vendor brings against listing it (orange: you do not have the posting fee now)
            r.c[4]:SetText((c.short and ORANGE or GREY) .. (c.diff >= 0 and (short(c.diff) .. " less") or ("+" .. short(-c.diff) .. " more")) .. "|r")
        end
        if c then
            local function sg(x) return (x >= 0 and "+ " or "- ") .. short(math.abs(x)) end
            local about = c.live and "" or "about "
            local fee = ""
            if c.fee then
                fee = c.short and (" %s(fee %s first: you have %s%s)|r"):format(ORANGE, short(c.fee), short(GetMoney()),
                        c.nextIn and (", sale gold in %d min"):format(math.max(1, floor(c.nextIn / 60 + 0.5))) or "")
                    or (" %s(fee %s first)|r"):format(GREY, short(c.fee))
            end
            if e.action == "VENDOR" then
                local other
                if c.ah and c.diff > 0 then
                    other = ("or wait and list: %s%s%s|r, %s more%s"):format(about, GREEN, sg(c.ah), short(c.diff), fee)
                elseif c.ah then
                    other = ("%slisting instead: %s%s, %s less|r"):format(GREY, about, sg(c.ah), short(-c.diff))
                elseif c.held then
                    other = GREY .. "the auction house pays less right now|r"
                else
                    other = GREY .. "no auction house price known yet|r"
                end
                r.detail:SetText(("Vendor now %s%s|r   %s"):format(GREEN, sg(c.vendor), other))
            elseif c.ah then
                r.detail:SetText(("List: %s%s%s|r%s   or vendor now: %s, %s%s, no wait|r"):format(about, GREEN, sg(c.ah), fee, sg(c.vendor),
                    GREY, c.diff >= 0 and (short(c.diff) .. " less") or (short(-c.diff) .. " more")))
            end
        end
    end
    if button then r.btn:SetText(button); r.btn:Enable(); r.btn:Show() else r.btn:Hide() end
end

---------------------------------------------------------------- status line

local function clock(s)
    s = math.floor(s + 0.5)
    return s >= 60 and ("%d:%02d"):format(s / 60, s % 60) or (s .. "s")
end

-- Three short lines about sniping, each a measured fact:
--   1. the state: armed or not, and how many watched items can be bought
--      straight from the radar (their listing is good enough for a flip)
--   2. the last answer to something the radar asked about
--   3. the radar: seconds between its reads, and what the last minute's
--      requests went to
local function buyStatus(n)
    if not ahOpen() then return GOLD .. "Open the Auction House to look for deals.|r" end
    local S, Sw, G = ns.Sniper, ns.Swarm, ns.Gate
    local name, lines = S.nameOf, {}
    -- THE MODE, first thing on the line, in capitals and in colour:
    -- what kind of deals are being offered right now.
    local mode = "" -- (the mode itself is the badge at the top left of the panel: see RenderMode)
    local cap = S:Capital()
    if ns.Deals.cfg.flips and (AuctionMeshDB.cfg.focusMode or "off") ~= "off" then
        local set, flist = S:FocusSet()
        mode = mode .. (set and (GREY .. ("Focus on %d item%s.|r "):format(#flist, #flist == 1 and "" or "s")) or (GREY .. "Focus: still measuring.|r "))
    end

    -- A STAKE-OUT IS A MODE OF ITS OWN: one item, bought by asking its price; nothing else while you press.
    local sk = S:StakeKey()
    local poor = S.PoorCount and S:PoorCount() or 0
    local low = S.lowGold
    if low then
        -- flips are off by themselves: what is owed, what you hold, and when gold arrives
        lines[#lines + 1] = ("%sGold is low: vendor deals only.|r You hold %s; posting the %d item%s you bought takes %s. Flips come back by themselves.%s"):format(
            ORANGE, ns.Seller.short(GetMoney()), low.items or 0, (low.items or 0) == 1 and "" or "s", ns.Seller.short(low.fees or 0),
            cap.nextIn and (" Next sale gold in %s."):format(cap.nextIn >= 90 and (floor(cap.nextIn / 60 + 0.5) .. " min") or (floor(cap.nextIn) .. "s"))
                or ((cap.onway or 0) + (cap.waiting or 0) > 0 and " Sale gold is waiting at the mailbox." or " Sell to a vendor (Bags tab) to get there."))
    elseif poor > 0 then
        -- cheap listings are there, your gold is not: say so, and when some arrives
        lines[#lines + 1] = ("%sNot enough gold in hand:|r you hold %s. %d cheap listing%s in the last minute cost%s more than that (a flip needs its posting fee too) and %s skipped.%s"):format(
            ORANGE, ns.Seller.short(GetMoney()), poor, poor == 1 and "" or "s", poor == 1 and "s" or "", poor == 1 and "was" or "were",
            cap.nextIn and (" Next sale gold in %s."):format(cap.nextIn >= 90 and (floor(cap.nextIn / 60 + 0.5) .. " min") or (floor(cap.nextIn) .. "s"))
                or ((cap.onway or 0) + (cap.waiting or 0) > 0 and " Sale gold is waiting at the mailbox." or ""))
    elseif cap.paused then
        -- your money is out of reach: say so, and when some of it comes back
        lines[#lines + 1] = ("%sBig flips paused:|r %s of your %s is in auctions that have not sold (limit %d%%).%s Small flips and vendor deals are still shown."):format(
            ORANGE, ns.Seller.short(cap.listed), ns.Seller.short(cap.worth), floor(ns.Deals.cfg.maxTied * 100 + 0.5),
            cap.nextIn and (" Next pay-out in %s."):format(cap.nextIn >= 90 and (floor(cap.nextIn / 60 + 0.5) .. " min") or (floor(cap.nextIn) .. "s")) or "")
    end
    -- ONE LINE: the mode, and what the radar is doing. (How the last try
    -- went, the last alert and the radar's figures are in Details, Session.)
    if G:UserBusy() then
        lines[#lines + 1] = mode .. ORANGE .. "Paused for a moment (a click is in progress).|r"
    elseif sk then
        local max, why = S:StakeTerms()
        lines[#lines + 1] = mode .. (not max and (ORANGE .. "Waiting: " .. tostring(why or "reading its market first") .. ".|r")
            or S:Staking() and (GREEN .. "Running: every input asks its price. Nothing else is bought and the radar is off.|r")
            or (GREY .. "Not running: press in the snipe box to start it. Until then the radar reads as usual.|r"))
    else
        local sr = S.searching
        local alert = S:PeekNext()
        if sr and (sr.src == "vendor" or sr.src == "market" or sr.src == "drop") then
            lines[#lines + 1] = mode .. "Checking an alert: " .. name(sr.key)
        elseif alert then
            lines[#lines + 1] = mode .. "Alert next: " .. name(alert)
        elseif Sw and Sw.active and #Sw.units > 0 then
            local W = ns.Watch
            local m = W and W.LastMinute and W:LastMinute() or {}
            lines[#lines + 1] = mode .. GREY .. (m.every and ("Radar: a read every %.2fs.|r"):format(m.every) or "Radar: starting.|r")
        else
            lines[#lines + 1] = mode
        end
    end
    return table.concat(lines, "\n")
end

-- The single most useful thing to do right now, in plain words, with the gold it makes.
local function nextStep(deals, entries, short)
    local S, Se = ns.Sniper, ns.Seller
    local b = S.buying
    if b and b.phase == "confirm" then
        return ("Press |cffffd100BUY NOW|r to pay %s for %d x %s."):format(short(b.total or 0), b.units, S.nameOf(b.key))
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
    do
        local waiting = Se:SalesMoney()
        if waiting > 0 then return ("Collect %s%s|r at a mailbox: sale gold has arrived."):format(GREEN, short(waiting)) end
    end
    if n.MAIL > 0 then return ("Visit a mailbox: %d item(s) to collect."):format(n.MAIL) end
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
    -- what a vendor pays more for than it cost: the other way out has its own column
    vendor = { "QTY", "COST", "VENDOR", "IF LISTED", "P / L" },
    either = { "QTY", "COST", "MARKET", "VENDOR NOW", "P / L" },
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
--   Trades: deals to buy, and nothing else
--   Bags:   what you hold, grouped by what to do with it, then your auctions
--           (sold, stuck, ended, listed)
--   Setup:  no list (it is all controls)
local function buildList(tab, deals, entries)
    local list = {}
    if tab == "BUY" then
        section(list, "DEALS TO BUY NOW", CAPS.deal, deals)
        if #deals == 0 then
            list[#list + 1] = { note = ahOpen() and "None right now. A sound plays when one appears." or "Open the auction house to look for deals." }
        end
    elseif tab == "SELL" then
        local by = { AH = {}, EITHER = {}, VENDOR = {}, MAIL = {}, HOLD = {} }
        for _, e in ipairs(entries) do
            -- to post, with a vendor as the quicker way out: its own section, so both figures are on the row
            local t = by[(e.action == "AH" and e.vendorAlt) and "EITHER" or e.action]
            if t then t[#t + 1] = e end
        end
        if #by.AH > 0 then section(list, "TO POST AT THE AUCTION HOUSE", CAPS.entry, by.AH) end
        if #by.EITHER > 0 then section(list, "TO POST, OR SELL TO A VENDOR NOW", CAPS.either, by.EITHER) end
        if #by.VENDOR > 0 then section(list, "TO SELL TO A VENDOR", CAPS.vendor, by.VENDOR) end
        if #by.MAIL > 0 then section(list, "IN THE MAILBOX", CAPS.entry, by.MAIL) end
        if #by.HOLD > 0 then section(list, "HELD, PRICE TOO LOW", CAPS.entry, by.HOLD) end
        local stuck, ended, ok, sold = {}, {}, {}, {}
        local _, _, _, soldKeys = ns.Seller:SalesMoney()
        local S = ns.Sniper
        for _, e in ipairs(entries) do
            if e.action == "LISTED" then
                -- An auction that has SOLD is waiting for its gold, not stuck: the
                -- cheaper listings the radar sees now are other people's. (It was
                -- shown under "stuck, undercut" while its gold was on the way.)
                e.sold = soldKeys[e.key] == true
                e.soldIn = nil
                if e.sold then
                    for _, r in ipairs(S.ownSoldPay or {}) do
                        local left = r.due - GetTime()
                        if r.key == e.key and left > 0 and (not e.soldIn or left < e.soldIn) then e.soldIn = left end
                    end
                end
                e.undercut = not e.sold and undercut(e)
                local t = e.sold and sold or e.live == 0 and ended or e.undercut and stuck or ok
                t[#t + 1] = e
            end
        end
        if #sold > 0 then section(list, "SOLD, GOLD ON ITS WAY", CAPS.entry, sold) end
        if #stuck > 0 then section(list, "STUCK LISTINGS", CAPS.entry, stuck) end
        if #ended > 0 then section(list, "ENDED, CHECK A MAILBOX", CAPS.entry, ended) end
        if #ok > 0 then section(list, "LISTED", CAPS.entry, ok) end
        if #list == 0 then list[1] = { note = "Nothing to sell. Items you buy on the Trades tab appear here." } end
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
            if e.live == 0 and soldKeys[e.key] then
                -- sold: its gold is already in the two "Sold" lines above
            else
                -- Still counted when the auction house no longer shows it: it
                -- then either sold (the gold is on its way) or came back (the
                -- item is in the mail). Either way its value has not gone
                -- anywhere. (Leaving these out made the total look 11 silver
                -- short in a real session.)
                listed = listed + floor((e.listed.price or 0) * cut) * e.count
                if e.live == 0 then ended = ended + 1 end
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
    lg.rows[4].label:SetText(ended > 0 and "Listed or just sold: at the listed prices" or "Listed: if it sells at the listed prices")
    lg.rows[4].value:SetText(plus(listed, ORANGE))
    lg.rows[5].label:SetText("Bought, not listed yet: at the live price")
    lg.rows[5].value:SetText(plus(bought, ORANGE))
    lg.total.label:SetText("Total when it has all sold")
    lg.total.value:SetText(short(gold + waiting + onway + listed + bought))
    local parts = {}
    if held > 0 then parts[#parts + 1] = ("%d held item%s that cost %s (tab Bags)"):format(held, held == 1 and "" or "s", short(heldCost)) end
    local endedNote = ended > 0 and (" %d of your auctions %s no longer seen on the auction house (sold, or returned): still counted above; the mailbox shows which."):format(
        ended, ended == 1 and "is" or "are") or ""
    -- the cut and the posting fees, stated every time
    local fees = 0
    for _, Lr in pairs(AuctionMeshDB.listed or {}) do fees = fees + (Lr.fee or 0) end
    local fb = AuctionMeshDB.cfg.feeBack
    local feeText = fees > 0 and (" Posting fees paid on your auctions: %s (%s)."):format(short(fees),
        fb == true and "come back when they sell, confirmed here" or fb == false and "do NOT come back on this realm; already taken off profits"
        or "should come back when they sell; the first sale will confirm it") or ""
    lg.note:SetText((#parts > 0 and ("Not counted: " .. table.concat(parts, "; ") .. ".") or "All amounts are after the 5% auction house cut.") .. endedNote .. feeText)
end

-- The same figures as the MONEY section, as numbers.
function UI.MoneyFigures(entries)
    local Se = ns.Seller
    entries = entries or Se:Entries()
    local waiting, onway, _, soldKeys = Se:SalesMoney()
    local listed, bought = 0, 0
    local cut = 1 - ns.Deals.cfg.cut
    for _, e in ipairs(entries) do
        local _, _, net = Se:Numbers(e)
        if e.action == "LISTED" then
            if not (e.live == 0 and soldKeys[e.key]) then listed = listed + floor((e.listed.price or 0) * cut) * e.count end
        elseif e.action ~= "HOLD" then
            bought = bought + (net or 0) * e.count
        end
    end
    local gold = GetMoney()
    return { gold = gold, waiting = waiting, onway = onway, listed = listed, bought = bought, total = gold + waiting + onway + listed + bought }
end

local DRAWER_CHART_W = 376 -- the drawer's width less its margins
-- THE SESSION, DRAWN (Details, Session view: fixed at the top of the drawer,
-- the text scrolls under it).
--   * TRIES: one bar, green for bought, red for missed, orange for gone
--     before an input, with the percentages.
--   * GOLD: a column for every stretch of the session. Gold: what you hold.
--     The teal tick above it: what you are worth once everything has sold.
--     To the right of "now", paler: the next hour, with the sale gold that is
--     already certain (sold, waiting to be paid) arriving when it is due.
--     Nothing in the forecast is a guess: auctions that have not sold are in
--     the teal figure only.
--   * SPEED: a column for each of the last tries: seconds from the deal
--     showing to its end. Green: you bought it. Red: someone else had it
--     first (their purchase was in before yours got there). Orange: gone
--     with no input from you.
-- A gold sample is kept every 20 seconds (3 hours of them, across reloads).
local CHART_COLS, CHART_NEXT, CHART_W, CHART_H = 84, 24, 3, 44
local SPEED_COLS, SPEED_W, SPEED_H = 40, 8, 36
local SESSION_ROWS = 12 -- drawer lines the graphics take
function UI:SampleGold(force, entries)
    local db = AuctionMeshDB
    if not db then return end
    local now = GetServerTime()
    local h = db.goldHist or {}
    db.goldHist = h
    local last = h[#h]
    if not force and last and now - last.t < 20 then return end
    local ok, m = pcall(UI.MoneyFigures, entries)
    if not ok or not m then return end
    h[#h + 1] = { t = now, g = m.gold, w = m.total }
    while #h > 540 or (h[1] and now - h[1].t > 3 * 3600) do table.remove(h, 1) end
end

-- HOW FAST. The last tries (40 are kept, across reloads), each with its
-- timings in seconds from the moment the deal showed:
--   won:  you had it after `s`.
--   lost: someone else had it first. Their purchase reached the server before
--         yours did, so they took it within `s` (and, when the price was
--         still there for your price request, after `lo`).
--   gone: it left after `s` with no input from you.
function UI.SpeedFigures()
    local list = (AuctionMeshDB and AuctionMeshDB.outcomes) or {}
    local out = { rows = {}, won = { n = 0, sum = 0 }, lost = { n = 0, sum = 0 }, gone = { n = 0, sum = 0 },
                  parts = { n = 0, input = 0, lock = 0, price = 0, buy = 0 } }
    for _, o in ipairs(list) do
        local secs = o.k == "gone" and o.g or o.e
        if secs and out[o.k] then
            local row = { k = o.k, s = secs, t = o.t, key = o.key, i = o.i, h = o.h, q = o.q }
            if o.k == "lost" and o.q and secs - ((o.i or 0) + o.q) > 0.05 then row.lo = (o.i or 0) + o.q end
            out.rows[#out.rows + 1] = row
            local b = out[o.k]
            b.n, b.sum = b.n + 1, b.sum + secs
            if not b.best or secs < b.best then b.best = secs end
            if o.k == "won" and o.q then
                -- where your time went: the input, the game's lock, the price answer, the purchase
                local pt = out.parts
                pt.n = pt.n + 1
                pt.input = pt.input + (o.i or 0)
                pt.lock = pt.lock + (o.h or 0)
                pt.price = pt.price + math.max(0, o.q - (o.h or 0))
                pt.buy = pt.buy + math.max(0, secs - (o.i or 0) - o.q)
            end
        end
    end
    return out
end

-- What the Session view shows, as numbers (the drawing and the tests both use it).
function UI:ChartData(entries)
    local now = GetServerTime()
    local h = (AuctionMeshDB and AuctionMeshDB.goldHist) or {}
    -- this stretch of play: back to the last gap of over 30 minutes
    local from = #h
    while from > 1 and h[from].t - h[from - 1].t <= 1800 do from = from - 1 end
    local t0 = h[from] and h[from].t or now
    local span = math.max(60, now - t0)
    local cols, hi = {}, 1
    local j = from
    local cur
    for i = 1, CHART_COLS do
        local tEnd = t0 + span * i / CHART_COLS
        while h[j] and h[j].t <= tEnd do cur = h[j]; j = j + 1 end
        if cur then
            cols[i] = { g = cur.g, w = cur.w }
            if cur.w > hi then hi = cur.w end
            if cur.g > hi then hi = cur.g end
        end
    end
    -- the next hour: what you hold now, plus the sale gold that is due by then
    local m = UI.MoneyFigures(entries)
    local pays = ns.Seller:PayOuts()
    local nextCols, coming = {}, 0
    for i = 1, CHART_NEXT do
        local tEnd = 3600 * i / CHART_NEXT
        local g = m.gold + m.waiting
        for _, p in ipairs(pays) do if p.secs <= tEnd then g = g + p.amount end end
        nextCols[i] = { g = g, w = m.total }
        if g > hi then hi = g end
    end
    for _, p in ipairs(pays) do if p.secs <= 3600 then coming = coming + p.amount end end
    if m.total > hi then hi = m.total end
    local t = ns.Sniper.tally
    local n = (t.won or 0) + (t.lost or 0) + (t.gone or 0)
    return { cols = cols, next = nextCols, hi = hi, span = span, now = m, coming = coming + m.waiting, start = h[from],
             tries = n, won = t.won or 0, lost = t.lost or 0, gone = t.gone or 0, speed = UI.SpeedFigures() }
end

-- The figures behind the Session view, worked out once a second at most (at
-- once when a try has ended): the panel is redrawn often, and that stays cheap.
function UI:SessionData(entries)
    local t = ns.Sniper.tally
    local n = (t.won or 0) + (t.lost or 0) + (t.gone or 0)
    local now = GetTime()
    if self.chartState and n == self.chartTries and now - (self.chartAt or 0) < 1 then return self.chartState end
    self.chartAt, self.chartTries = now, n
    self.chartState = self:ChartData(entries)
    return self.chartState
end

function UI:RenderChart(show, short, entries)
    local c = frame.chart
    if not c then return end
    c:SetShown(show)
    if not show then return end
    local d = self:SessionData(entries)
    if c.drawn == d then return end
    c.drawn = d
    -- tries
    local W = DRAWER_CHART_W
    local function seg(tex, x, n)
        local w = d.tries > 0 and floor(W * n / d.tries + 0.5) or 0
        tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", c.triesBar, "TOPLEFT", x, 0); tex:SetSize(math.max(w, 0.01), 8); tex:SetShown(w > 0)
        return x + w
    end
    local x = seg(c.won, 0, d.won); x = seg(c.lost, x, d.lost); seg(c.gone, x, d.gone)
    local function pct(n) return d.tries > 0 and floor(n * 100 / d.tries + 0.5) or 0 end
    c.triesText:SetText(d.tries > 0 and ("%sTRIES|r   %s%d bought (%d%%)|r   %s%d missed (%d%%)|r   %s%d gone, no input (%d%%)|r"):format(
        GREY, GREEN, d.won, pct(d.won), RED, d.lost, pct(d.lost), ORANGE, d.gone, pct(d.gone)) or (GREY .. "TRIES   none yet this session|r"))
    -- gold
    local function put(col, v, i, pale)
        local hg = v and math.max(1, floor(CHART_H * v.g / d.hi + 0.5)) or 0
        col.bar:SetHeight(math.max(hg, 0.01)); col.bar:SetShown(v ~= nil)
        col.bar:SetColorTexture(1, 0.82, 0, pale and 0.35 or 0.9)
        if v then
            col.tick:ClearAllPoints()
            col.tick:SetPoint("BOTTOMLEFT", c.plot, "BOTTOMLEFT", (i - 1) * CHART_W, math.min(CHART_H - 2, floor(CHART_H * v.w / d.hi + 0.5)))
        end
        col.tick:SetShown(v ~= nil)
        col.tick:SetColorTexture(0.2, 0.85, 0.8, pale and 0.45 or 1)
    end
    for i = 1, CHART_COLS do put(c.col[i], d.cols[i], i, false) end
    for i = 1, CHART_NEXT do put(c.col[CHART_COLS + i], d.next[i], CHART_COLS + i, true) end
    c.top:SetText(GREY .. short(d.hi) .. "|r")
    local mins = floor(d.span / 60 + 0.5)
    c.axisL:SetText(GREY .. (mins >= 90 and ("%.1f h ago"):format(mins / 60) or (mins .. " min ago")) .. "|r")
    c.axisN:SetText(GREY .. "now|r")
    c.axisR:SetText(GREY .. "+1 h|r")
    -- speed: the last tries, oldest on the left
    local rows = d.speed.rows
    local top = 2
    for _, r in ipairs(rows) do if r.k ~= "gone" and r.s > top then top = r.s end end
    top = math.min(top, 6)
    local first = math.max(0, #rows - SPEED_COLS)
    for i = 1, SPEED_COLS do
        local r, bar = rows[first + i], c.speed[i]
        if r then
            bar:SetHeight(math.max(2, floor(SPEED_H * math.min(r.s, top) / top + 0.5)))
            if r.k == "won" then bar:SetColorTexture(0.2, 0.9, 0.4, 1)
            elseif r.k == "lost" then bar:SetColorTexture(0.9, 0.25, 0.25, 1)
            else bar:SetColorTexture(1, 0.55, 0.2, 0.8) end
        end
        bar:SetShown(r ~= nil)
    end
    c.speedTop:SetText(GREY .. ("%.1fs"):format(top) .. "|r")
    c.speedAxis:SetText(#rows > 0 and (GREY .. "oldest|r") or (GREY .. "no try with a measured time yet|r"))
    c.speedNew:SetText(#rows > 0 and (GREY .. "newest|r") or "")
end

-- How long gold spent on a flip is out of reach: time to sell plus the hour
-- the auction house takes to pay out.
function UI.backIn(d)
    local mins = (d.eta or 0) + 60
    return mins >= 120 and ("%.1f hours"):format(mins / 60) or ("1h %02dm"):format(math.max(0, floor(mins - 60 + 0.5)))
end

-- HOW YOU BUY (Setup tab, "Buy with"). Buying needs real inputs, and any of
-- these supplies them:
--   wheel   roll the mouse wheel in the snipe box (and anywhere while a deal is up)
--   key     tap a key of your choice; it works anywhere while the Trades tab is open
--   (Holding a key down was a fourth way. The game refuses it: a real log shows
--   every purchase sent from a held key blocked, and each one froze the deal
--   for four seconds. It has been removed.)
--   click   clicks on the snipe box only
-- Clicking the box works in every mode.
--   one     ONE KEY FOR EVERYTHING: the same key as "key", and it also posts.
--           Each press does the next useful thing: buy the deal that is up;
--           with no deal, post the next item in your bags that is ready (at
--           the addon's price, never under what it cost you). It works on the
--           Trades tab and on the Bags tab.
UI.BUY_MODES = { "wheel", "key", "one", "click" }
UI.BUY_NAMES = { wheel = "Mouse wheel", key = "A key: tap it", one = "One key: buys and posts", click = "Clicks only" }
function UI.BuyMode()
    local cfg = AuctionMeshDB.cfg
    local m = cfg.buyMode
    if not (m and UI.BUY_NAMES[m]) then m = (cfg.wheel == false) and "click" or "wheel" end
    return m
end

function UI:SetBuyMode(mode)
    local cfg = AuctionMeshDB.cfg
    if not mode then
        local at = 1
        for i, m in ipairs(UI.BUY_MODES) do if m == UI.BuyMode() then at = i end end
        mode = UI.BUY_MODES[at % #UI.BUY_MODES + 1]
    end
    if not UI.BUY_NAMES[mode] then return end
    cfg.buyMode, cfg.wheel = mode, nil
    if cfg.buyBlocked then cfg.buyBlocked[mode] = nil end -- chosen again by hand: try it again
    self:Notice(mode == "wheel" and "Buy with the mouse wheel: put the mouse in the snipe box and roll."
        or mode == "key" and (cfg.buyKey and ("Buy with a key: tap %s while the Trades tab is open."):format(cfg.buyKey) or "Buy with a key: now click 'Key' and press the key you want.")
        or mode == "one" and (cfg.buyKey and ("One key: %s buys the deal that is up; with none it posts the next item in your bags. Trades and Bags tabs."):format(cfg.buyKey) or "One key for buying and posting: now click 'Key' and press the key you want.")
        or "Buy with clicks on the snipe box only.", true)
    self:Dirty()
    return mode
end

-- The game refused a purchase that came from this kind of input: stop using it.
function UI:InputBlocked(via)
    local cfg = AuctionMeshDB.cfg
    if via == "click" or not UI.BUY_NAMES[via or ""] then return end
    cfg.buyBlocked = cfg.buyBlocked or {}
    cfg.buyBlocked[via] = true
    local to = "click"
    for _, m in ipairs({ "wheel", "key" }) do
        if not cfg.buyBlocked[m] and m ~= via and (m ~= "key" or cfg.buyKey) then to = m; break end
    end
    cfg.buyMode, cfg.wheel = to, nil
    ns.Log("INPUT '%s' is blocked by the game for buying: switched to '%s'", tostring(via), to)
    self:Notice(("This game does not accept '%s' as an input for buying. Switched to '%s' (Setup tab, Buy with)."):format(UI.BUY_NAMES[via], UI.BUY_NAMES[to]), true)
    self:Dirty()
end

-- ONE BUY INPUT: a wheel notch, a tap or a repeat of your key, or a click.
-- inBox: it is meant for the snipe box (a wheel notch elsewhere on the panel
-- only counts while a deal is up; otherwise it scrolls the list).
-- Returns true if the input was used for buying.
-- Seconds between your buy inputs, averaged over the last four seconds (nil
-- when the last input is over 1.5 seconds old or there is only one). A press
-- and its release each count.
function UI.InputEvery()
    local t, now = UI.inputTimes, GetTime()
    if not t or #t < 2 or now - t[#t] > 1.5 then return nil end
    local first, n = nil, 0
    for i = #t, 1, -1 do
        if now - t[i] > 4 then break end
        first, n = t[i], n + 1
    end
    if n < 2 then return nil end
    return (t[#t] - first) / (n - 1)
end

-- THE WINDOW. A deal appears with the answer to a radar read or an item
-- check; the game keeps its lock shut for about half a second after that
-- answer, and a price request made in that time is held and leaves the
-- moment the lock opens. So any input inside that window is as fast as
-- possible, and one after it loses exactly the time it came late.
--   optimal   an input at least every half window: two or more always land in it
--   in time   an input at least every window: one always lands in it, with nothing to spare
--   too slow  longer than the window between inputs: a deal can sit waiting for your next one
-- Returns the window in seconds (from the measured lock; 0.49s at a 0.74s lock).
function UI.PaceWindow()
    local lock = (ns.Gate and ns.Gate.cycle) or 0.74
    return math.max(0.2, lock - 0.25)
end
function UI.PaceZone(every)
    if not every then return nil end
    local w = UI.PaceWindow()
    return every <= w / 2 and "optimal" or every <= w and "intime" or "slow"
end

function UI.InputPress(inBox, via)
    via = via or "wheel"
    do
        local t = UI.inputTimes or {}
        UI.inputTimes = t
        t[#t + 1] = GetTime()
        if #t > 60 then table.remove(t, 1) end
        UI.inputCount = (UI.inputCount or 0) + 1
    end
    if ns.Sniper.SessionTouch then ns.Sniper:SessionTouch() end
    if UI.tab == "SELL" and via == "key" and UI.BuyMode() == "one" then return UI.OnePost() end -- the one key, on the Bags tab: it posts
    if UI.tab ~= "BUY" then return false end
    if via == "wheel" and UI.BuyMode() ~= "wheel" then return false end
    local S = ns.Sniper
    local now = GetTime()
    S.inputVia = via
    if via ~= "click" then S.inputAt = now end -- so a blocked input can be traced to what sent it
    local key = S:Target()
    if not (key and (S.verified[key] or S.buying)) then
        if inBox then
            local was = UI.wheelSeen
            UI.wheelSeen = now
            if not was or now - was > 0.7 then
                S.tally.armed = (S.tally.armed or 0) + 1
                ns.Log("ARMED by %s in the snipe box (%s)", via, S:StakeKey() and "stake-out: every input asks the staked item's price" or "snipe mode: radar and alerts only")
                UI:Dirty() -- show ARMED; no redraw per input
            end
            -- the one key, with no deal to buy: post the next item that is ready (a stake-out's price request comes first)
            if not (S:StakeNotch()) and via == "key" and UI.BuyMode() == "one" then UI.OnePost() end
            return true
        end
        return false
    end
    if inBox then UI.wheelSeen = now end
    S:Press()
    return true
end

-- THE ONE KEY, POSTING. At most five times a second, and only when something
-- in your bags is waiting to be posted: a press with nothing to post costs
-- nothing and says nothing.
function UI.OnePost()
    local Se, now = ns.Seller, GetTime()
    if not ahOpen() or (UI.onePostAt and now - UI.onePostAt < 0.2) then return false end
    UI.onePostAt = now
    return Se:PostNext(true) and true or false
end
function UI.WheelPress(inBox) return UI.InputPress(inBox, "wheel") end

-- True while buy inputs are arriving in the snipe box: one in the last 0.7
-- seconds. (It was 1.5 seconds, and with the redraw on top the box went on
-- saying it was armed for two seconds after the inputs had stopped.)
function UI.Armed()
    return UI.wheelSeen ~= nil and GetTime() - UI.wheelSeen < 0.7
end

-- Key bindings that exist only while they are wanted:
--   the wheel, anywhere, while a deal is up or a purchase is in progress (wheel mode);
--   your key, anywhere, while the Trades tab is open (key mode).
function UI:BindInputs(dealUp, off)
    if not frame then return end
    local cfg = AuctionMeshDB.cfg
    local mode = UI.BuyMode()
    local live = not off and self.tab == "BUY" and frame:IsShown()
    local wantWheel = (live and mode == "wheel" and dealUp) and true or false
    -- the one key is also live on the Bags tab (there it posts)
    local keyLive = live or (not off and mode == "one" and self.tab == "SELL" and frame:IsShown())
    local wantKey = (keyLive and (mode == "key" or mode == "one") and cfg.buyKey and cfg.buyKey ~= "" and not self.capturingKey) and cfg.buyKey or false
    if wantWheel == (self.wheelBound or false) and wantKey == (self.keyBound or false) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if wantWheel ~= (self.wheelBound or false) then
        self.wheelBound = wantWheel
        if wantWheel and SetOverrideBindingClick then
            SetOverrideBindingClick(frame, true, "MOUSEWHEELUP", "AuctionMeshSnipeButton", "WHEEL")
            SetOverrideBindingClick(frame, true, "MOUSEWHEELDOWN", "AuctionMeshSnipeButton", "WHEEL")
        elseif ClearOverrideBindings then
            ClearOverrideBindings(frame)
        end
    end
    if wantKey ~= (self.keyBound or false) then
        self.keyBound = wantKey
        if ClearOverrideBindings then ClearOverrideBindings(frame.snipe) end
        if wantKey and SetOverrideBindingClick then SetOverrideBindingClick(frame.snipe, true, wantKey, "AuctionMeshSnipeButton", "KEY") end
    end
end

-- THE BIG BUY BUTTON (Trades tab). It never moves and always acts on the best
-- deal, so it can be clicked without looking for a row, and clicked repeatedly.
--   teal    a deal: the first click asks the server for the price
--   green   BUY NOW: the price is in, this click buys (two clicks in all; the
--           game does not let an addon ask for a price without a click)
--   grey    nothing to buy; shows what happened to the last deal for 6 seconds
-- It is also THE SNIPE BOX: keep the mouse in it and keep rolling the wheel.
-- Nothing happens while there is no deal; the first notch after one appears
-- buys it, so the purchase starts within a few hundredths of a second of the
-- deal being found, with no reaction time.
function UI:RenderSnipe(short)
    local sn = frame.snipe
    local S = ns.Sniper
    local show = self.tab == "BUY"
    sn:SetShown(show)
    frame.next:SetShown(self.tab == "SELL")
    -- the "Last: GOT IT ..." line belongs to the snipe box: it was left showing over the other tabs
    if sn.result then sn.result:SetShown(show) end
    if not show then
        self:BindInputs(false, not (self.tab == "SELL" and UI.BuyMode() == "one")) -- the one key stays live on the Bags tab
        return
    end
    local key = S:Target()
    local d = key and S.verified[key]
    local last = S.result -- stays on the panel until the next outcome
    local res = last
    if res and GetTime() - res.at > 6 then res = nil end
    local b = S.buying
    local text, colour, fill = nil, LINE, { 0.09, 0.10, 0.12 }
    if d then
        local units, total = S.NextBuy(d)
        local back = d.kind == "VENDOR" and " (guaranteed; gold back at the next vendor)"
            or (" (gold back in about %s)"):format(UI.backIn(d))
        local what = ("%s x%d%s    pay %s    make + %s%s"):format(S.nameOf(d.key), units,
            d.leftOf and (ORANGE .. (" (%d of %d still there)|r"):format(units, d.leftOf)) or "", short(total), short(d.profit), back)
        if S:OneClick(key) then
            text, colour, fill = GREEN .. "BUY NOW|r    " .. what, { 0.2, 1, 0.4 }, { 0.05, 0.22, 0.10 }
        elseif b and b.key == key and b.phase == "wait" then
            text, colour = GOLD .. "BUYING...|r    " .. what, ACCENT
        elseif b and b.key == key then
            text, colour = TEAL .. "ASKING THE PRICE (keep clicking)|r    " .. what, ACCENT
        else
            text, colour = TEAL .. "BUY|r    " .. what, ACCENT
        end
    elseif res then
        local c = res.kind == "won" and GREEN or res.kind == "lost" and RED or ORANGE
        text = c .. res.text .. "|r"
        colour = res.kind == "won" and { 0.2, 1, 0.4 } or res.kind == "lost" and { 1, 0.25, 0.25 } or { 1, 0.5, 0.25 }
    else
        -- Nothing but sniping in this box. (Chores such as "visit a mailbox"
        -- used to be shown here; they are on the Bags tab, whose label counts them.)
        local m = S.underMin
        local sk = S:StakeKey()
        if sk then
            -- the stake-out: what it is waiting for, and what the server last said
            local max, why = S:StakeTerms()
            local st = S.stake
            if max then
                local seen = (st.lastPrice and st.lastAt and GetTime() - st.lastAt < 30) and ("    last price " .. short(st.lastPrice)) or ""
                text = (S:SnipeMode() and (GOLD .. "STAKE-OUT RUNNING|r") or (GOLD .. "STAKE-OUT SET, NOT RUNNING|r")) .. "    " .. S.nameOf(sk) .. ": buys at " .. short(max) .. " or less"
                    .. seen .. GREY .. ("    asked %d, bought %d|r"):format(st.asked or 0, st.bought or 0)
            else
                text = ORANGE .. "STAKE-OUT WAITING|r    " .. S.nameOf(sk) .. ": " .. tostring(why or "reading its market first")
            end
        elseif m and GetTime() - m.at < 600 and m.best >= 50 and m.best < ns.Deals.cfg.minProfit then
            text = ORANGE .. ("%d deal%s hidden by your %s minimum profit (best: + %s). Lower it on the Setup tab.|r"):format(
                m.n, m.n == 1 and "" or "s", short(ns.Deals.cfg.minProfit), short(m.best))
        else
            text = GREY .. (ahOpen() and "Watching. No deal right now.|r" or "Open the auction house to look for deals.|r")
        end
    end
    self:BindInputs(d ~= nil or b ~= nil) -- the wheel stays bound for the whole of a purchase in progress
    local mode = UI.BuyMode()
    local armed = UI.Armed()
    if armed and not d then
        -- rolling with nothing to buy yet: say that it is working
        colour, fill = { 0.2, 1, 0.4 }, { 0.04, 0.14, 0.07 }
        if not res and not S:StakeKey() then
            local ready, watched = S:ReadyCount()
            local missing = ns.Deals.cfg.flips and watched - ready or 0
            text = GREEN .. "ARMED|r    the next deal is bought the moment it appears    " .. GREY
                .. (missing > 0 and ("radar first; %d listing%s still being read for instant flips|r"):format(missing, missing == 1 and "" or "s")
                    or "every request goes to the radar and its alerts|r")
        end
    end
    if S:StakeKey() and not d and not res then
        -- gold, whether it is running or not: this box is not doing what it usually does
        colour, fill = { 1, 0.82, 0 }, S:Staking() and { 0.20, 0.15, 0.02 } or { 0.11, 0.09, 0.03 }
    end
    do  -- POSTING, step by step, while no deal is up: what is being posted and what it is waiting for
        local act = ns.Seller.activity
        if act and not d and not b and GetTime() - act.at < 4 then
            text = GOLD .. act.text .. "|r"
            colour, fill = { 1, 0.82, 0 }, { 0.14, 0.11, 0.02 }
        end
    end
    sn.label:SetText(text)
    do  -- one line under it: how to buy, in the mode you chose
        local cfg = AuctionMeshDB.cfg
        local how
        if mode == "wheel" then
            how = d and "Roll the mouse wheel here (or anywhere), or click: it buys."
                or "put the mouse here and keep rolling the wheel"
        elseif mode == "key" then
            how = cfg.buyKey and ("tap " .. cfg.buyKey .. " (it works anywhere while this tab is open), or click here")
                or "no key chosen yet: Setup tab, Key"
        elseif mode == "one" then
            how = cfg.buyKey and ("keep tapping " .. cfg.buyKey .. ": it buys the deal that is up; with none it posts what is ready in your bags")
                or "no key chosen yet: Setup tab, Key"
        else
            how = "click here"
        end
        local hint
        if armed and S:StakeKey() then
            hint = GREEN .. "Stake-out running: every input asks the server this item's price and buys if it is low. The radar is off meanwhile.|r"
        elseif S:StakeKey() and not d then
            hint = GREY .. "Stake-out: " .. how .. ". End it with the Stop stake-out button below.|r"
        elseif armed then
            -- your inputs against the game's lock, measured
            hint = GREEN .. "Armed: keep the inputs coming.|r"
        elseif d then
            hint = GREY .. (mode == "wheel" and how or ("To buy: " .. how .. ".")) .. "|r"
        else
            hint = GREY .. "SNIPE BOX, not armed: " .. how .. ". A deal is bought the moment it appears.|r"
        end
        sn.hint:SetText(hint)
    end
    sn.fill:SetColorTexture(fill[1], fill[2], fill[3], 1)
    UI.outline(sn, colour)
    do  -- THE PACE GAUGE
        local pg = sn.pace
        if pg then
            local every, w = UI.InputEvery(), UI.PaceWindow()
            local zone = UI.PaceZone(every)
            UI.paceState = { every = every, zone = zone, window = w }
            -- short: the figure and the verdict. The target is named only when
            -- you are not on it. (The count of presses in time is in Details, Session.)
            local ideal = ("  %s(optimal: every %d ms or faster)|r"):format(GREY, floor(w / 2 * 1000 + 0.5))
            if every then
                local x = math.min(1, every / (2 * w)) * 240
                pg.mark:ClearAllPoints(); pg.mark:SetPoint("CENTER", pg, "LEFT", x, 0); pg.mark:Show()
                pg.text:SetText(("%sAn input every %d ms: %s|r%s"):format(
                    zone == "optimal" and GREEN or zone == "intime" and GOLD or RED, floor(every * 1000 + 0.5),
                    zone == "optimal" and "OPTIMAL" or zone == "intime" and "IN TIME, NOTHING TO SPARE" or "TOO SLOW",
                    zone == "optimal" and "" or ideal))
            else
                pg.mark:Hide()
                pg.text:SetText(GREY .. "Not pressing.|r" .. ideal)
            end
        end
    end
    -- The line under the button never leaves you guessing: the last outcome
    -- stays there with its age, next to the count for this session.
    -- (the session's count is in the footer: SESSION, TODAY, the year)
    if last and not (res and not d) then
        local age = GetTime() - last.at
        sn.result:SetText(("%sLast:|r %s%s|r %s(%s ago)|r"):format(GREY, last.kind == "won" and GREEN or last.kind == "lost" and RED or ORANGE,
            last.text, GREY, age < 90 and (floor(age) .. "s") or (floor(age / 60) .. " min")))
    else
        sn.result:SetText("")
    end
end

-- The bar at the top: what the request engine is doing right now.
--   orange = measuring or trying something (the bar is its progress)
--   teal   = tuned (the bar is how much of the request budget is in use)
function UI:RenderBar()
    local paused
    if not ahOpen() then paused = "Idle: the auction house is closed"
    elseif GetTime() < (ns.Gate.holdUntil or 0) then paused = "Holding fire: the auction house is free for your click"
    elseif ns.Gate:UserBusy() then paused = "Paused while you click"
    elseif not ns.Sniper.active then paused = "Idle" end
    local st = ns.Tuner:State(paused)
    local bar = frame.bar
    if not self.barWidth or self.barWidth < 60 or frame.snap:GetLeft() ~= self.fitAt then
        self.fitAt = frame.snap:GetLeft()
        self:FitHeader() -- the window was resized or moved since the bar was last fitted
    end
    local w = floor(math.max(0, math.min(1, st.fill)) * ((self.barWidth or BAR_W) - 2) + 0.5)
    bar.fill:SetShown(w > 0)
    bar.fill:SetWidth(math.max(1, w))
    if st.mode == "try" then bar.fill:SetColorTexture(1, 0.55, 0.25, 1)
    else bar.fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
    frame.barText:SetText((st.mode == "try" and ORANGE or GREY) .. st.text .. "|r")
    self.barState = st
end

-- Setup tab: every control shows its current value; then what the engine has learned.
-- THE PICKS TAB. One sentence that says what to do with your inputs right now,
-- the figures behind it, and one button per item.
function UI:RenderPicks(short)
    local pk, S, P = frame.picks, ns.Sniper, ns.Picks
    local r, waiting = P:Get()
    local name = S.nameOf
    local stake = S:StakeKey()
    local hrs = (r.hours or 0) <= 1 and "the last hour" or ("the last %d hours"):format(r.hours)
    local head, why
    local best, top = r.best, r.top
    if stake then
        local st = S.stake or {}
        local terms = S:TermsFor(stake)
        local rec = S:StakeRecord(stake)
        head = TEAL .. "Stake-out is on " .. name(stake) .. ".|r"
        why = (terms.max and ("It buys at %s or less. "):format(short(terms.max)) or ("Waiting: " .. tostring(terms.why or "reading its market first") .. ". "))
            .. ("Run it from the snipe box on the Trades tab. So far on this item: price asked %d time%s, %d bought%s.")
                :format(rec.asked, rec.asked == 1 and "" or "s", rec.bought,
                    (st.lastPrice and st.lastAt and GetTime() - st.lastAt < 600) and (", last price the server gave " .. short(st.lastPrice)) or "")
        local it
        for _, x in ipairs(r.list) do if x.key == stake then it = x end end
        if r.enough and not (it and it.try) then
            why = why .. ORANGE .. " The record does not favour it" .. (it and (": the deals you missed on it were worth %s, the radar's catches on other items made %s")
                :format(short(it.missP), short(it.givenUp)) or ": no deal on it was missed in " .. hrs) .. ". Stop it to give the radar every request back.|r"
        end
    elseif not r.enough then
        head = GREY .. "Keep sniping with the radar. Not enough has been seen yet to pick an item.|r"
        why = ("%d deal%s recorded in %s; this needs at least %d. It fills in by itself while the radar runs.")
            :format(r.all or 0, (r.all or 0) == 1 and "" or "s", hrs, P.cfg.minAll)
    elseif best then
        head = GREEN .. "Try a stake-out on " .. name(best.key) .. ".|r"
        why = ("In %s you went for %d deal%s on it and someone was faster: they were worth %s. Everything the radar caught for you on other items in that time made %s, which is what a stake-out gives up while it runs.")
            :format(hrs, best.miss, best.miss == 1 and "" or "s", short(best.missP), short(best.givenUp))
    else
        head = "Keep the radar. No single item is worth a stake-out."
        if top and top.miss > 0 then
            why = ("In %s the item you lost most on was %s: %d deal%s missed, worth %s. The radar's catches on other items made %s in the same time, and a stake-out would give those up.")
                :format(hrs, name(top.key), top.miss, top.miss == 1 and "" or "s", short(top.missP), short(top.givenUp))
        else
            why = ("In %s you did not go for a deal and lose it: nothing a faster purchase would have won. Deals that were gone before any input are listed below; they are won by being at the snipe box, not by a stake-out.")
                :format(hrs)
        end
    end
    pk.head:SetText(head)
    pk.why:SetText(why)
    pk.sub:SetText(("STAKE-OUT CANDIDATES    %d deal%s seen in %s, you got %s of profit from them%s"):format(r.all or 0, (r.all or 0) == 1 and "" or "s", hrs,
        short(r.gotAll or 0), waiting and "    (figures wait while you snipe)" or ""))
    for i, row in ipairs(pk.rows) do
        local it = r.list[i]
        if it then
            local on = stake == it.key
            row.c[1]:SetText((it.try and GREEN or "") .. name(it.key) .. (it.try and "|r" or ""))
            row.c[2]:SetText(tostring(it.n))
            row.c[3]:SetText(it.got > 0 and tostring(it.got) or (GREY .. "0|r"))
            row.c[4]:SetText(it.miss > 0 and (("%d  "):format(it.miss) .. short(it.missP)) or (GREY .. "0|r"))
            row.c[5]:SetText(it.gone > 0 and (tostring(it.gone) .. (it.life and (GREY .. (" %.0fs|r"):format(it.life)) or "")) or (GREY .. "0|r"))
            row.c[6]:SetText(it.max and short(it.max) or (GREY .. "-|r"))
            row.c[7]:SetText(it.low and short(it.low) or (GREY .. "-|r"))
            row.btn.key = it.key
            row.btn:SetText(on and "Stop" or "Stake out")
            row.btn.tipText = (on and "Ends the stake-out; the radar gets every request back."
                or ("Sets the stake-out on this item and takes you to the snipe box. While you roll or tap there, every input asks the server this item's price and buys at "
                    .. (it.max and (short(it.max) .. " or less") or "a price worked out once its listing has been read") .. ". The radar is off meanwhile."))
                .. ((it.record and it.record.asked > 0) and ("\nStake-outs on it so far: asked %d times, %d bought."):format(it.record.asked, it.record.bought) or "")
                .. ((not it.max and it.why) and ("\nNo buying price yet: " .. tostring(it.why) .. ".") or "")
            UI.outline(row.btn, (on or it.try) and ACCENT or LINE)
            row.btn:Show()
        else
            for c = 1, 7 do row.c[c]:SetText("") end
            row.btn.key = nil
            row.btn:Hide()
        end
    end
    pk.note:SetText("MISSED: you went for the deal and someone was faster. Only these count for the recommendation, because speed is what a stake-out adds."
        .. "\nGONE: it left before any input, with how long those lasted. Being at the snipe box wins these, not a stake-out."
        .. "\nBUYS AT: the most a stake-out would pay per unit now, from the item's listing as last read. CHEAPEST: the radar's last read."
        .. "\nA stake-out watches one item by asking its price with every input. It is quicker than the radar, and the radar is off while it runs.")
end

-- THE TRADES TAB'S FOOTER: SESSION | TODAY | THE YEAR. What you bought and
-- what it is worth when sold.
--   SESSION is one stretch of pressing, with its clock: it starts with your
--   first input after a break of 10 minutes or more. After 10 minutes with
--   no input it is over and stays shown until the next one starts.
--   TODAY and the year carry over reloads and log-outs.
local function clockText(secs)
    secs = math.max(0, floor(secs))
    local h, m, sec = floor(secs / 3600), floor(secs / 60) % 60, secs % 60
    return h > 0 and ("%d:%02d:%02d"):format(h, m, sec) or ("%d:%02d"):format(m, sec)
end
function UI.TradesFooter(short)
    local S = ns.Sniper
    local se, t = S.session, S:Totals()
    local parts = {}
    local function worth(c) return GREEN .. "+ " .. short(c) .. "|r" end
    if se then
        local over = GetTime() - (se.last or se.at) > 600
        parts[1] = ("%sSESSION|r %s%s%s|r  %d bought, %d missed  %s"):format(WHITE_C, over and GREY or GOLD,
            clockText((over and se.last or GetTime()) - se.at), over and " (over)" or "", se.won, se.lost, worth(se.profit))
    else
        parts[1] = ("%sSESSION|r %sstarts with your first press|r"):format(WHITE_C, GREY)
    end
    parts[2] = ("%sTODAY|r  %d bought  %s"):format(WHITE_C, t.day.n, worth(t.day.profit))
    parts[3] = ("%s%d|r  %d bought  %s"):format(WHITE_C, t.year.id, t.year.n, worth(t.year.profit))
    return parts
end

-- THE MODE BADGE (top left). What is being bought, and one click to change it.
function UI:RenderMode()
    local b = frame and frame.mode
    if not b then return end
    local S = ns.Sniper
    local sk = S:StakeKey()
    local text, c
    if sk then text, c = "STAKE-OUT: " .. S.nameOf(sk), { 1, 0.82, 0 }
    elseif S.lowGold then text, c = "VENDOR ONLY: GOLD LOW", { 1, 0.5, 0.25 }
    elseif not ns.Deals.cfg.flips then text, c = "VENDOR ONLY", { 0.2, 1, 0.4 }
    else text, c = "VENDOR + FLIPS", ACCENT end
    b:SetText(("|cff%02x%02x%02x%s|r"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5), text))
    UI.outline(b, c)
    self.modeText = text
end
function UI:ModeClick()
    local S = ns.Sniper
    if S:StakeKey() then
        S:SetStake(nil)
        self:Notice("Stake-out ended. The radar has every request again.", true)
    else
        self:SetVendorOnly(AuctionMeshDB.cfg.flips ~= false)
    end
    self:Render()
end

-- Waiting for a key press (Setup, Key) ends when the Setup tab is left.
function UI:StopKeyCapture()
    if not self.capturingKey then return end
    self.capturingKey = false
    local k = frame and frame.setup and frame.setup.key
    if k and k.EnableKeyboard then k:EnableKeyboard(false) end
end

function UI:RenderSetup()
    local sp, cfg = frame.setup, AuctionMeshDB.cfg
    -- your own setting (while gold is low the addon runs on vendor deals only without changing it)
    sp.flips:SetText(AuctionMeshDB.cfg.flips ~= false and (ns.Sniper.lowGold and "Vendor deals + flips (off: low gold)" or "Vendor deals + flips") or "Vendor deals only")
    sp.scope:SetText(ns.Do.SCOPE_NAMES[cfg.scope] or ns.Do.SCOPE_NAMES.mats)
    sp.tied:SetText(("%d%% unsold"):format(floor(ns.Deals.cfg.maxTied * 100 + 0.5)))
    sp.spend:SetText(("%d%% a flip"):format(floor(ns.Deals.cfg.maxSpend * 100 + 0.5)))
    sp.dock:SetText(cfg.dock ~= false and "Inside the auction house" or "A window of its own")
    sp.auto:SetText(cfg.autoOpen and "Opens by itself: on" or "Opens by itself: off")
    sp.tune:SetText(ns.Tuner.cfg.enabled and "Auto-adjust: on" or "Auto-adjust: off")
    do  -- how you buy
        local mode = UI.BuyMode()
        sp.buy:SetText(UI.BUY_NAMES[mode])
        sp.key:SetText(self.capturingKey and "Press a key... (Esc cancels)" or (cfg.buyKey and ("Key: " .. cfg.buyKey) or "Not set: click, then press a key"))
        UI.outline(sp.key, self.capturingKey and ACCENT or LINE)
    end
    do
        local _, flist = ns.Sniper:FocusSet()
        local mode = cfg.focusMode or "off"
        sp.focus:SetText(ns.Scout.MODE_NAMES[mode] .. ((mode ~= "off" and #flist > 0) and (" (%d)"):format(#flist) or ""))
    end
    sp.forget:SetText((self.forgetUntil and GetTime() < self.forgetUntil) and "Click again to forget" or "Forget what was learned")
    if not sp.margin:HasFocus() then sp.margin:SetText(tostring(cfg.margin or floor(ns.Deals.cfg.margin * 100 + 0.5))) end
    -- three lines: what auto-adjust last did, the server's limit, the radar
    local lines = {}
    do
        local a = ns.Auto and ns.Auto:Lines(1) or {}
        if cfg.tune == false then
            lines[1] = { "Auto-adjust", "off: nothing changes by itself" }
        elseif #a == 0 then
            lines[1] = { "Auto-adjust", "on: watching. Smallest profit is reviewed every 10 minutes of use" }
        else
            local age = GetServerTime() - a[1].t
            lines[1] = { "Auto-adjust, last change", a[1].m .. "  (" .. (age < 90 and (age .. "s") or (floor(age / 60) .. " min")) .. " ago)" }
        end
        local t = ns.Tuner:Lines()
        if t[1] then lines[2] = t[1] end
        local M = ns.measure and ns.measure.last
        if M then
            lines[3] = { "Radar", ("%d items in %d request%s, re-read about every %ds"):format(M.items, M.requests, M.requests == 1 and "" or "s", ns.Swarm.cfg.fresh) }
        elseif t[2] then
            lines[3] = t[2]
        end
    end
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
    self.lastDeals, self.lastEntries = deals, entries
    local tab = self.tab
    self:Layout()
    self:RenderBar()
    if tab == "BUY" then self:RenderMoney(entries, short) end
    if tab == "HISTORY" then self:RenderSetup() end
    if tab == "PICKS" then self:RenderPicks(short) end

    local todo = 0
    for _, e in ipairs(entries) do if e.action ~= "LISTED" then todo = todo + 1 end end
    frame.tabBuy:SetText(#deals > 0 and ("Trades (%d)"):format(#deals) or "Trades")
    frame.tabSell:SetText(todo > 0 and ("Bags (%d)"):format(todo) or "Bags")
    UI.selectTab(frame.tabBuy, tab == "BUY")
    UI.selectTab(frame.tabSell, tab == "SELL")
    UI.selectTab(frame.tabHist, tab == "HISTORY")
    UI.selectTab(frame.tabPick, tab == "PICKS")
    do  -- "Picks (1)" when a stake-out is worth a try and none is set
        local P = ns.Picks
        local r = P and P.result
        frame.tabPick:SetText((r and r.best and not ns.Sniper:StakeKey()) and "Picks (1)" or "Picks")
    end

    if tab == "SELL" then frame.next:SetText(TEAL .. "NEXT|r  " .. nextStep(deals, entries, short)) end -- (hidden on the other tabs)
    self:RenderMode()
    self:RenderSnipe(short)
    if frame.stakeStop then frame.stakeStop:SetShown(tab == "BUY" and ns.Sniper:StakeKey() ~= nil) end
    local status = tab == "BUY" and buyStatus(#deals) or tab == "SELL" and Se:Instructions(entries) or ""

    local n = self.notice
    if n and GetTime() < n.till then
        status = n.text
    elseif tab == "SELL" and ahOpen() and ns.Gate:UserBusy() then
        status = ORANGE .. "Paused for a moment (a click is in progress).|r " .. status
    end
    if tab == "SELL" and Se.activity and GetTime() - Se.activity.at < 4 then
        status = GOLD .. Se.activity.text .. "|r\n" .. status -- what the post is doing right now, first
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
        for _, part in ipairs(UI.TradesFooter(short)) do parts[#parts + 1] = part end
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
    -- (the Trades tab has no button at the bottom right: its footer may use the whole width)
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("BOTTOMLEFT", 14, 12)
    frame.footer:SetPoint("BOTTOMRIGHT", tab == "BUY" and -14 or -230, 12)
    frame.footer:SetText(table.concat(parts, tab == "BUY" and (GREY .. "   |   |r") or "    "))

    do  -- "Post next" only when there is something to post
        local toPost = false
        for _, e in ipairs(entries) do if e.action == "AH" then toPost = true end end
        frame.post:SetShown(tab == "SELL" and ahOpen() and toPost)
    end
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
        ns.Sniper:Press(item.key)
    else
        local Se = ns.Seller
        if item.action == "AH" and item.vendorAlt and merchantOpen() and not ahOpen() then Se:SellVendor(item.key)
        elseif item.action == "AH" then Se:Post(item.key)
        elseif item.action == "VENDOR" then Se:SellVendor(item.key)
        elseif item.action == "HOLD" then Se.prices[item.key] = nil; Se.priority = item.key
        elseif item.action == "LISTED" then Se:CancelClick(item.key)
        end
    end
    UI:Dirty()
end

local function rowEnter(self)
    local item = self.item
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(item.key)
    if not item.action then
        GameTooltip:AddLine(item.kind == "VENDOR" and (GREEN .. "Your gold is back as soon as you sell it to a vendor.|r")
            or (GOLD .. "Your gold is out of reach for about " .. UI.backIn(item) .. ": until it sells, plus the hour the auction house takes to pay.|r"), 1, 1, 1, true)
        if item.instant then GameTooltip:AddLine(TEAL .. "Shown straight from the radar, without an item check. The server's price decides when you buy.|r", 1, 1, 1, true) end
    end
    local st, dt = self.state:GetText(), self.detail:GetText()
    if st and st ~= "" then GameTooltip:AddLine(st, 1, 1, 1, true) end
    if dt and dt ~= "" then GameTooltip:AddLine(dt, 0.8, 0.8, 0.8, true) end
    if item.action then
        local p = ns.Seller.prices[item.key]
        if p and p.price then
            local qty = ns.Seller:PostQty(item.key, p)
            GameTooltip:AddLine(("%sPosts %d at %s each, deposit %s|r"):format(GOLD, qty,
                ns.Seller.short(p.price), ns.Seller.short(ns.Seller:DepositTotal(item.key, p.commodity, math.max(qty, 1)))))
            GameTooltip:AddLine(GREY .. (AuctionMeshDB.cfg.feeBack == false and "The posting fee does not come back on this realm; it is taken off the profit.|r"
                or "The posting fee comes back when it sells; it is lost if the auction runs out.|r"))
        elseif p and p.hold then
            GameTooltip:AddLine(RED .. p.hold .. "|r")
        end
        if item.f.proof then GameTooltip:AddLine(GREEN .. "Purchase confirmed: " .. item.f.proof .. "|r") end
        GameTooltip:AddLine(GREY .. "Click: details and what to do|r")
    else
        local d = item
        if d.kind == "FLIP" then
            local fb = AuctionMeshDB.cfg.feeBack
            GameTooltip:AddLine(("%sLive market: %d units listed from %s. Profit is after the 5%% cut. Posting fee %s: %s.|r"):format(GREY,
                d.depth or 0, ns.Seller.short(d.wall or 0), ns.Seller.short(d.deposit or 0),
                fb == false and "taken off the profit (it does not come back on this realm)"
                or fb == true and "kept aside, comes back when it sells (confirmed here)"
                or "kept aside; it should come back when it sells, the first sale will confirm it"))
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
    -- a click (either button) opens this item's details in the drawer; nothing
    -- is removed by a stray right-click any more
    if self.item and self.item.key then
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

-- THE WHOLE PANEL FLASHES: green around its edge for a purchase, red for a
-- miss. One and a half seconds, then it is gone.
local FLASH_RGB = { won = { 0.2, 1, 0.4 }, lost = { 1, 0.2, 0.2 } }
function UI:Flash(kind)
    local c = FLASH_RGB[kind]
    if not (frame and c) then return end
    local e = rawget(frame, "flashEdges")
    if not e then
        e = {}
        rawset(frame, "flashEdges", e)
        for i = 1, 4 do e[i] = frame:CreateTexture(nil, "OVERLAY") end
        e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(4)
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(4)
        e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(4)
        e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(4)
    end
    for i = 1, 4 do e[i]:SetColorTexture(c[1], c[2], c[3], 1); e[i]:Show() end
    self.flashKind, self.flashUntil = kind, GetTime() + 1.5
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
UI.outline = outline

-- a "label ........ amount" line
-- A label on the left and a value on the right that can never overlap,
-- whatever the panel's width or the font's size: text that does not fit is
-- cut off with "...".
--   labelW = nil  the value keeps its own width, the label gets what is left
--   labelW = n    the label is n wide, the value gets what is left
local function ledgerRow(parent, y, font, labelW)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 0, y)
    l:SetJustifyH("LEFT"); l:SetWordWrap(false)
    local v = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    v:SetPoint("TOPRIGHT", 0, y)
    v:SetJustifyH("RIGHT"); v:SetWordWrap(false)
    if labelW then
        l:SetWidth(labelW)
        v:SetPoint("TOPLEFT", labelW + 8, y)
    else
        l:SetPoint("RIGHT", v, "LEFT", -8, 0)
    end
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
        if UI.WheelPress() then return end -- a deal is up: the wheel buys instead of scrolling
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
    frame.title:Hide() -- its place is the mode badge's now
    -- A separate window is dragged by any part of it that is not a button or a
    -- box: the background, the item rows, the drawer.
    function UI.Draggable(w)
        w:EnableMouse(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", function() if not UI.docked then frame:StartMoving() end end)
        w:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            if UI.docked then return end
            local point, _, rel, x, y = frame:GetPoint()
            AuctionMeshDB.cfg.pos = { point, rel, x, y }
        end)
    end
    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", 0, 0)
    frame.closeBtn:SetScript("OnClick", function() UI:Close() end)

    -- THE MODE, top left on every tab, where the name used to be: what is being
    -- bought right now, in colour. A click changes it (no trip to the Setup tab).
    frame.mode = button(frame, 158, "", function() UI:ModeClick() end)
    frame.mode:SetHeight(20)
    frame.mode:SetPoint("TOPLEFT", 12, -7)
    frame.mode:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("What is being bought", 1, 1, 1)
        GameTooltip:AddLine("VENDOR + FLIPS: everything. Vendor deals (listed under what a vendor pays) and flips (resold on the auction house).", 0.30, 0.86, 0.76, true)
        GameTooltip:AddLine("VENDOR ONLY: vendor deals only. Gold back at the next vendor, guaranteed.", 0.2, 1, 0.4, true)
        GameTooltip:AddLine("VENDOR ONLY: GOLD LOW: the addon's own switch while you cannot pay the posting fees; flips come back by themselves.", 1, 0.5, 0.25, true)
        GameTooltip:AddLine("STAKE-OUT: one item, bought by asking its price with every input; nothing else while you press. Set on the Picks tab.", 1, 0.82, 0, true)
        GameTooltip:AddLine(ns.Sniper:StakeKey() and "Click: end the stake-out." or "Click: switch between VENDOR + FLIPS and VENDOR ONLY.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- tabs (positioned in Place(): to the right of the mode badge)
    frame.tabBuy = makeTab(frame, "Trades", function() UI:StopKeyCapture(); UI.tab = "BUY"; UI:Render() end)
    frame.tabSell = makeTab(frame, "Bags", function() UI:StopKeyCapture(); UI.tab = "SELL"; UI:Render() end)
    frame.tabPick = makeTab(frame, "Picks", function() UI:StopKeyCapture(); UI.tab = "PICKS"; UI:Render() end)
    frame.tabHist = makeTab(frame, "Setup", function() UI.tab = "HISTORY"; UI:Render() end)
    frame.tabSell:SetPoint("LEFT", frame.tabBuy, "RIGHT", 6, 0)
    frame.tabPick:SetPoint("LEFT", frame.tabSell, "RIGHT", 6, 0)
    frame.tabHist:SetPoint("LEFT", frame.tabPick, "RIGHT", 6, 0)

    -- POP OUT / DOCK. Inside the auction house the panel is part of that window
    -- and cannot be dragged on its own; this button turns it into a separate
    -- window that can, and back.
    frame.pop = button(frame, 62, "Pop out", function() ns.Do.Dock(not UI.docked) end)
    frame.pop:SetHeight(18)
    frame.pop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(UI.docked and "Pop out" or "Dock", 1, 1, 1)
        GameTooltip:AddLine(UI.docked and "Makes the panel a separate window that you can drag anywhere."
            or "Puts the panel back inside the auction house window.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.pop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- SNAPSHOT: on every tab. One short block of text to copy and paste to
    -- Claude: gold, mailbox, auctions, bags, settings and the last snipes.
    frame.snap = button(frame, 74, "Snapshot", function() ns.Do.Snapshot() end)
    frame.snap:SetHeight(18)
    frame.snap:SetPoint("RIGHT", frame.pop, "LEFT", -6, 0)
    outline(frame.snap, ACCENT)
    frame.snap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Snapshot for Claude", 1, 1, 1)
        GameTooltip:AddLine("Opens one short block of text: your gold, what is in the mailbox, what has sold and is on its way, what is listed and in your bags, your settings, and the last 20 snipes with how fast each input was. Copy it and paste it to Claude.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.snap:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    frame.barText:SetWidth(BAR_W)
    frame.barText:SetJustifyH("RIGHT"); frame.barText:SetWordWrap(false)

    -- NEXT STEP: one plain instruction, always the most profitable thing to do now
    frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.next:SetJustifyH("LEFT"); frame.next:SetWordWrap(false)

    -- THE BIG BUY BUTTON: fixed place, always the best deal, safe to spam
    local sn = button(frame, 100, "", function(self, btn)
        if btn == "WHEEL" then UI.InputPress(true, "wheel")
        elseif btn == "KEY" then UI.InputPress(true, "key")
        else
            UI.InputPress(true, "click")
        end
    end, "AuctionMeshSnipeButton")
    sn:SetHeight(46)
    -- Buying takes two messages to the server (ask the price, then buy) and the
    -- game wants a real input for each. To make that as close to one action as
    -- possible, every kind of input counts: the press AND the release of a
    -- click are each an input, and so is every notch of the mouse wheel. One
    -- flick of the wheel sends a burst: the first notch asks the price, the
    -- first notch after the answer buys.
    if sn.RegisterForClicks then sn:RegisterForClicks("AnyDown", "AnyUp") end
    sn:EnableMouseWheel(true)
    sn:SetScript("OnMouseWheel", function() UI.InputPress(true, "wheel") end)
    sn:SetPoint("TOPLEFT", 12, -178); sn:SetPoint("TOPRIGHT", -12, -178)
    sn.label = sn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sn.label:SetPoint("TOPLEFT", 10, -8); sn.label:SetPoint("TOPRIGHT", -10, -8)
    sn.label:SetJustifyH("LEFT"); sn.label:SetWordWrap(false)
    sn.hint = sn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sn.hint:SetPoint("BOTTOMLEFT", 10, 7); sn.hint:SetPoint("BOTTOMRIGHT", -10, 7)
    sn.hint:SetJustifyH("LEFT"); sn.hint:SetWordWrap(false)
    sn.result = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sn.result:SetPoint("TOPLEFT", sn, "BOTTOMLEFT", 2, -4); sn.result:SetPoint("TOPRIGHT", sn, "BOTTOMRIGHT", -2, -4)
    sn.result:SetJustifyH("LEFT"); sn.result:SetWordWrap(false)
    -- THE PACE GAUGE: are your inputs coming fast enough? A bar in three
    -- zones (green: optimal, yellow: in time with nothing to spare, red: too
    -- slow), scaled to the game's own lock, and a white marker where you are.
    local pg = CreateFrame("Frame", nil, sn)
    pg:SetPoint("TOPLEFT", sn, "BOTTOMLEFT", 2, -21)
    pg:SetSize(240, 9)
    pg.zone = {}
    local ZC = { { 0.15, 0.75, 0.3 }, { 0.9, 0.75, 0.1 }, { 0.8, 0.2, 0.2 } }
    local ZW = { 0.25, 0.25, 0.5 } -- shares of the bar: 0 to half a window, to one window, to two windows
    local x = 0
    for i = 1, 3 do
        local t = pg:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", x, 0); t:SetSize(240 * ZW[i], 9)
        t:SetColorTexture(ZC[i][1], ZC[i][2], ZC[i][3], 0.85)
        pg.zone[i] = t
        x = x + 240 * ZW[i]
    end
    pg.mark = pg:CreateTexture(nil, "OVERLAY")
    pg.mark:SetSize(3, 15); pg.mark:SetColorTexture(1, 1, 1, 1)
    pg.mark:SetPoint("CENTER", pg, "LEFT", 0, 0)
    pg.text = pg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pg.text:SetPoint("LEFT", pg, "RIGHT", 8, 0)
    pg.text:SetJustifyH("LEFT"); pg.text:SetWordWrap(false)
    sn.pace = pg
    -- The mouse resting in this box pauses NOTHING. (It used to: "the mouse
    -- on it means a click is coming". With the mouse parked on the Buy button
    -- waiting for a deal, the radar stood still and no deal could appear.)
    sn:Hide()
    frame.snipe = sn
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetJustifyH("LEFT"); frame.status:SetJustifyV("TOP")
    -- shown on the Trades tab only while a stake-out is set: one click ends it
    frame.stakeStop = button(frame, 120, "Stop stake-out", function()
        ns.Sniper:SetStake(nil)
        UI:Notice("Stake-out ended. The radar has every request again.", true)
        UI:Render()
    end)
    frame.stakeStop:SetHeight(18)
    frame.stakeStop:SetPoint("TOPRIGHT", frame.status, "TOPRIGHT", 0, 3)
    outline(frame.stakeStop, { 1, 0.82, 0 })
    frame.stakeStop:Hide()

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

    -- SETUP tab: a control for everything that can be changed (no commands
    -- to remember), then what the request engine has learned.
    local sp = CreateFrame("Frame", nil, frame)
    sp:SetPoint("TOPLEFT", 14, -40); sp:SetPoint("TOPRIGHT", -14, -40)
    sp:SetHeight(430)
    heading(sp, 0, "SETTINGS    (AuctionMesh version " .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AuctionMesh", "Version") or "?") .. ")")
    local function setting(y, text)
        local l = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 0, y)
        l:SetJustifyH("LEFT"); l:SetWordWrap(false)
        l:SetText(text)
        return l
    end
    -- the label of a row ends where the row's leftmost control begins
    local function upTo(label, control)
        label:SetPoint("RIGHT", control, "LEFT", -8, 0)
    end
    local function box(w, numeric, letters, suffix, onDone)
        local e = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
        e:SetSize(w, 20)
        e:SetAutoFocus(false)
        if numeric then e:SetNumeric(true) end
        e:SetMaxLetters(letters)
        if suffix then
            local s = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetPoint("LEFT", e, "RIGHT", 2, 0)
            s:SetText(suffix)
        end
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        if onDone then e:SetScript("OnEditFocusLost", onDone) end
        return e
    end
    local function tip(b, text)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- THE SETUP TAB, in five short groups. Everything that can be changed is
    -- here; nothing else is. (It used to be eleven unsorted rows, among them
    -- sharing with friends, two log buttons and eight lines about the request
    -- engine.)
    -- Heights: the heading is at 0, the one-line status (what a click just did)
    -- at -15, then the groups. The last line ends 473 px under the top of the
    -- panel, above the footer in both the docked and the floating window.
    local ROW, HEAD = 22, 15
    local yy = -28
    local function group(text)
        yy = yy - 4
        heading(sp, yy, text)
        yy = yy - HEAD
    end
    local function row(text)
        local l = setting(yy, text)
        local at = yy
        yy = yy - ROW
        return l, at
    end

    group("DEALS")
    local L, at = row("Smallest profit worth showing")
    frame.minC = box(30, true, 3, "c", function() UI:ApplyMinProfit() end)
    frame.minC:SetPoint("TOPRIGHT", -12, at + 5)
    frame.minS = box(30, true, 3, "s", function() UI:ApplyMinProfit() end)
    frame.minS:SetPoint("RIGHT", frame.minC, "LEFT", -18, 0)
    upTo(L, frame.minS)

    L, at = row("Profit a flip must leave after the auction house cut")
    sp.margin = box(30, true, 2, "%", function() ns.Do.Margin(tonumber(sp.margin:GetText())) end)
    sp.margin:SetPoint("TOPRIGHT", -12, at + 5)
    upTo(L, sp.margin)

    L, at = row("Show")
    sp.flips = tip(button(sp, 190, "", function() UI:SetVendorOnly(AuctionMeshDB.cfg.flips ~= false) end),
        "Vendor deals are guaranteed profit: the item is listed for less than a vendor pays. Flips are resold on the auction house and are not guaranteed.")
    sp.flips:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.flips)

    L, at = row("Most of your money in unsold auctions, and in one flip")
    sp.spend = tip(button(sp, 92, "", function() ns.Do.MaxSpend() end),
        "The most of the gold you hold that ONE flip may take. Click to change: 35%, 50%, 75%, 100%. At 100% the first big pile can take everything you hold; nothing more can be bought until it sells and pays out.")
    sp.spend:SetPoint("TOPRIGHT", 0, at + 5)
    sp.tied = tip(button(sp, 92, "", function() ns.Do.MaxTied() end),
        "The most of your money that may sit in auctions that have NOT SOLD yet. Gold from auctions that have sold is on its way and does not count. A small flip (15% of the gold in hand) is always allowed. Click to change: 30%, 50%, 70%, 100%.")
    sp.tied:SetPoint("RIGHT", sp.spend, "LEFT", -6, 0)
    upTo(L, sp.tied)

    group("BUYING")
    L, at = row("Buy with")
    sp.buy = tip(button(sp, 190, "", function() UI:SetBuyMode() end),
        "Click to change.\nMouse wheel: put the mouse in the snipe box and roll.\nA key, tap it: pick a key below; tapping it buys, anywhere, while the Trades tab is open.\nOne key, buys and posts: the same key; with no deal up, each press posts the next item in your bags that is ready, at the addon's price. Trades and Bags tabs.\nClicks only: click the snipe box.\nClicking the box works in every mode.")
    sp.buy:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.buy)

    L, at = row("Key (for 'A key: tap it')")
    sp.key = tip(button(sp, 190, "", function(self)
        -- click, then press the key you want (Esc cancels; a mouse side button works too)
        UI.capturingKey = not UI.capturingKey
        if self.EnableKeyboard then self:EnableKeyboard(UI.capturingKey and true or false) end
        UI:Dirty()
    end), "Click, then press the key you want to buy with. A modifier can be held with it (Shift, Ctrl, Alt). Mouse side buttons work too. While the Trades tab is open that key buys instead of doing what it normally does; everywhere else it is untouched.")
    sp.key:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.key)
    local function gotKey(name)
        local cfg = AuctionMeshDB.cfg
        UI.capturingKey = false
        if sp.key.EnableKeyboard then sp.key:EnableKeyboard(false) end
        if name then
            cfg.buyKey = name
            if cfg.buyBlocked then cfg.buyBlocked.key = nil end
            UI:Notice(("Buy key set to %s. It buys while the Trades tab is open (Buy with: A key, tap it; or One key, which also posts)."):format(name), true)
        end
        UI:Dirty()
    end
    sp.key:SetScript("OnKeyDown", function(_, key)
        if not UI.capturingKey then return end
        if key == "ESCAPE" then return gotKey(nil) end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then return end
        local name = (IsAltKeyDown and IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "") .. key
        gotKey(name)
    end)
    sp.key:SetScript("OnMouseDown", function(_, btn)
        if not UI.capturingKey then return end
        local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        if map[btn] then gotKey(map[btn]) end
    end)
    UI.GotKey = gotKey

    group("WATCHING")
    L, at = row("Radar reads")
    sp.scope = tip(button(sp, 250, "", function() ns.Do.Scope() end),
        "Click to change. Crafting materials are read about every second whatever is chosen; a wider setting adds the other categories, each every 30 seconds.")
    sp.scope:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.scope)

    L, at = row("Look for flips only on")
    sp.focus = tip(button(sp, 250, "", function() ns.Do.FocusMode() end),
        "Click to change.\nOff: every material is watched.\nPrime items: the addon picks the items measured to sell fastest with the most gold moving, and re-reads each one about once a minute. Your own watch list is included.\nMy own list: only items you added in the drawer or with a settings code.\nVendor-price deals are always shown, whatever is chosen.")
    sp.focus:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.focus)

    group("CLAUDE")
    L, at = row("Import: paste what Claude sent")
    sp.apply = tip(button(sp, 50, "Apply", function()
        if ns.Do.Import(sp.code:GetText()) then sp.code:SetText("") end
    end), "Paste a settings code (it starts with AMS1:), or the whole message it came in: the code is found in the text. Apply sets everything in it and says exactly what changed. Your current code is in the Snapshot.")
    sp.apply:SetPoint("TOPRIGHT", 0, at + 5)
    sp.code = box(196, false, 4000)
    sp.code:SetPoint("RIGHT", sp.apply, "LEFT", -8, 0)
    upTo(L, sp.code)
    -- A key-press tool goes on pressing your buy key on this tab, where the key
    -- is not bound: with the box in focus it types into it (ten "9" a second,
    -- until the box is full: then nothing can be pasted and Backspace cannot
    -- keep up). One character repeated is never a settings code: the box is
    -- emptied and the panel says what is happening.
    sp.code:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        if #t >= 4 and t == string.rep(t:sub(1, 1), #t) then
            self:SetText("")
            UI:Notice(("|cffff8040Something keeps typing '%s' into the import box|r (a key-press tool still running?). Pause it, then paste."):format(t:sub(1, 1)), true)
        end
    end)
    sp.code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end) -- a paste replaces what is there
    sp.code:SetScript("OnEnterPressed", function(self)
        if ns.Do.Import(self:GetText()) then self:SetText("") end
        self:ClearFocus()
    end)

    L, at = row("Send to Claude")
    local log = tip(button(sp, 60, "Log", function() ns.Diag:Show() end), "Everything the addon did this session, step by step. Send it when something looks wrong.")
    log:SetPoint("TOPRIGHT", 0, at + 5)
    sp.report = tip(button(sp, 100, "Daily report", function() ns.Do.Report() end),
        "The long version, once a day: what sold, what was found and missed, which items move the most gold.")
    sp.report:SetPoint("RIGHT", log, "LEFT", -6, 0)
    sp.snap = tip(button(sp, 90, "Snapshot", function() ns.Do.Snapshot() end),
        "The short version, any time: gold, mailbox, auctions, settings and the last snipes. The same as the Snapshot button at the top.")
    sp.snap:SetPoint("RIGHT", sp.report, "LEFT", -6, 0)
    outline(sp.snap, ACCENT)
    upTo(L, sp.snap)

    group("ADDON")
    L, at = row("The panel")
    sp.dock = tip(button(sp, 190, "", function() ns.Do.Dock(AuctionMeshDB.cfg.dock == false) end),
        "Inside the auction house window, or as a window of its own that you can drag anywhere.")
    sp.dock:SetPoint("TOPRIGHT", 0, at + 5)
    sp.auto = tip(button(sp, 150, "", function() ns.Do.Auto(not AuctionMeshDB.cfg.autoOpen) end),
        "On: the panel opens and starts reading prices when you open the auction house. Off: click the AuctionMesh tab under the auction house window.")
    sp.auto:SetPoint("RIGHT", sp.dock, "LEFT", -6, 0)
    upTo(L, sp.auto)

    L, at = row("Auto-adjust (pace, smallest profit, quiet time)")
    sp.forget = tip(button(sp, 190, "Forget what was learned", function()
        -- two clicks, so it can't happen by accident
        if UI.forgetUntil and GetTime() < UI.forgetUntil then
            UI.forgetUntil = nil
            ns.Do.Forget()
        else
            UI.forgetUntil = GetTime() + 5
            UI:Dirty()
        end
    end), "Clears the measured request limit, the pace and the record of how trades turned out. Needs a second click.")
    sp.forget:SetPoint("TOPRIGHT", 0, at + 5)
    sp.tune = tip(button(sp, 150, "", function() ns.Do.Tuning(not ns.Tuner.cfg.enabled) end),
        "On: the pace of requests, the flip profit bar, the smallest profit and the radar's quiet time adjust themselves from results, and each change is listed below. Off: nothing changes by itself.")
    sp.tune:SetPoint("RIGHT", sp.forget, "LEFT", -6, 0)
    upTo(L, sp.tune)

    -- three lines of what the addon is doing by itself
    yy = yy - 6
    sp.rows = {}
    for i = 1, 3 do sp.rows[i] = ledgerRow(sp, yy - (i - 1) * 14, nil, 170) end
    sp.bottom = yy - 2 * 14 - 12 -- where the last line ends, for the layout test
    sp:Hide()
    frame.setup = sp

    -- THE PICKS TAB: which item, if any, is worth a stake-out. Everything on
    -- it is worked out from deals the radar has already seen (see Picks.lua):
    -- it sends nothing to the auction house and waits while you are sniping.
    local pk = CreateFrame("Frame", nil, frame)
    pk:SetPoint("TOPLEFT", 14, -40); pk:SetPoint("TOPRIGHT", -14, -40)
    pk:SetHeight(430)
    heading(pk, 0, "PICKS    worked out from deals the radar has already seen: no requests, and never while you are sniping")
    pk.head = pk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pk.head:SetPoint("TOPLEFT", 0, -34); pk.head:SetPoint("TOPRIGHT", 0, -34)
    pk.head:SetJustifyH("LEFT"); pk.head:SetWordWrap(false)
    pk.why = pk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pk.why:SetPoint("TOPLEFT", 0, -54); pk.why:SetPoint("TOPRIGHT", 0, -54)
    pk.why:SetJustifyH("LEFT"); pk.why:SetJustifyV("TOP"); pk.why:SetWordWrap(true)
    pk.why:SetHeight(42)
    pk.sub = heading(pk, -106, "")
    -- columns: where each starts, how wide it is
    local PCOL = { { 0, 150, "LEFT" }, { 156, 44, "RIGHT" }, { 206, 54, "RIGHT" }, { 266, 96, "RIGHT" }, { 368, 56, "RIGHT" },
                   { 430, 76, "RIGHT" }, { 512, 72, "RIGHT" } }
    local function cells(y, font)
        local t = {}
        for i, c in ipairs(PCOL) do
            local fs = pk:CreateFontString(nil, "OVERLAY", font)
            fs:SetPoint("TOPLEFT", c[1], y)
            fs:SetWidth(c[2]); fs:SetJustifyH(c[3]); fs:SetWordWrap(false)
            t[i] = fs
        end
        return t
    end
    pk.caps = cells(-124, "GameFontDisableSmall")
    for i, text in ipairs({ "ITEM", "DEALS", "YOU GOT", "MISSED", "GONE", "BUYS AT", "CHEAPEST" }) do pk.caps[i]:SetText(text) end
    pk.rows = {}
    for i = 1, 6 do
        local y = -124 - i * 24
        local r = { c = cells(y - 5, "GameFontHighlightSmall") }
        r.btn = button(pk, 92, "", function(self)
            local key = self.key
            if not key then return end
            local S = ns.Sniper
            if S:StakeKey() == key then
                S:SetStake(nil)
                UI:Notice("Stake-out ended. The radar has every request again.", true)
            else
                -- one click: the stake-out is set and you are at the snipe box
                S:SetStake(key)
                UI.tab = "BUY"
                UI:Notice(("Stake-out set on %s. Roll or tap in the snipe box to run it; the radar is off while you do. Stop it with the button under the snipe box.")
                    :format(S.nameOf(key)), true)
            end
            UI:Render()
        end)
        r.btn:SetPoint("TOPRIGHT", 0, y)
        r.btn:SetScript("OnEnter", function(self)
            if not self.tipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(self.tipText, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        r.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pk.rows[i] = r
    end
    pk.note = pk:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pk.note:SetPoint("TOPLEFT", 0, -124 - 7 * 24 - 4); pk.note:SetPoint("TOPRIGHT", 0, -124 - 7 * 24 - 4)
    pk.note:SetJustifyH("LEFT"); pk.note:SetJustifyV("TOP"); pk.note:SetWordWrap(true)
    pk.note:SetHeight(84)
    pk:Hide()
    frame.picks = pk

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
        r.btn:SetScript("OnEnter", function(self) UI.hoverBtn, UI.hoverAt = self, GetTime() end)
        r.btn:SetScript("OnLeave", function(self) if UI.hoverBtn == self then UI.hoverBtn = nil end end)
        r.btn:SetPoint("RIGHT", -4, 0)
        UI.Draggable(r)
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
        UI:SampleGold() -- one gold sample every 20 seconds for the Session view (a time check on the others)
        do  -- the session clock in the footer: once a second, the footer's text only
            local sec = floor(GetTime())
            if UI.tab == "BUY" and ns.Sniper.session and sec ~= UI.clockSec and not UI.dirty then
                UI.clockSec = sec
                frame.footer:SetText(table.concat(UI.TradesFooter(ns.Seller.short), GREY .. "   |   |r"))
            end
        end
        if UI.flashUntil and GetTime() >= UI.flashUntil then
            UI.flashUntil, UI.flashKind = nil, nil
            for _, t in ipairs(rawget(frame, "flashEdges") or {}) do t:Hide() end
        end
        local paused = ns.Gate:UserBusy()
        if paused ~= UI.wasPaused then UI.wasPaused = paused; UI.dirty = true end
        local armed = UI.Armed()
        if armed ~= UI.wasArmed then UI.wasArmed = armed; UI.dirty = true end
        -- Timers and the engine bar tick twice a second while the auction house is open.
        UI.tick = (UI.tick or 0) + 1
        if ahOpen() and UI.tick % 3 == 0 then UI.dirty = true end
        -- a locked price turns into BUY NOW the moment the auction house is ready: don't wait for the slow redraw
        local sb = ns.Sniper.buying
        if sb and sb.phase == "confirm" and ns.Sniper:OneClick(sb.key) ~= UI.wasOneClick then UI.wasOneClick = ns.Sniper:OneClick(sb.key); UI.dirty = true end
        if UI.dirty then UI:Render() end
    end)
    self:CreateDrawer()
    frame:Hide()
end

-- Where things sit depends on the tab.
--   Trades: MONEY on top, then the NEXT line, the timers, the list
--   Bags:   the NEXT line, what to do, the list
--   Setup:  one status line under the heading, then the settings
local LAYOUT = {
    BUY = { next = -182, status = -260, statusH = 38, top = 304 }, -- (the pace gauge sits between the snipe box's lines and the status)
    SELL = { next = -40, status = -58, statusH = 38, top = 104 },
    HISTORY = { status = -55, statusH = 14, top = 480 },
    PICKS = { status = -55, statusH = 14, top = 480 },
}
function UI:Layout()
    local tab = self.tab
    local L = LAYOUT[tab]
    self.listTop = L.top
    if self.layoutKey == tab then return end
    self.layoutKey = tab
    frame.ledger:SetShown(tab == "BUY")
    frame.setup:SetShown(tab == "HISTORY")
    frame.picks:SetShown(tab == "PICKS")
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
    if ns.Auto then ns.Auto:Manual("min") end -- (ignored when the auto-adjust itself is the one setting it)
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
    S.lowGold, S.goldAt = nil, nil -- looked at afresh with the new setting
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
        frame.closeBtn:Hide()
        frame.tabBuy:SetPoint("TOPLEFT", 178, -8)
        frame.pop:ClearAllPoints(); frame.pop:SetPoint("TOPRIGHT", -12, -6)
        frame.pop:SetText("Pop out"); frame.pop:Show()
    else
        frame:SetParent(UIParent)
        frame:SetScale(0.9)
        frame:SetSize(WIDTH, FLOAT_H)
        frame:SetFrameStrata("HIGH")
        frame:SetMovable(true)
        frame.closeBtn:Show()
        frame.tabBuy:SetPoint("TOPLEFT", 178, -8)
        -- "Dock" only makes sense while the auction house is open
        frame.pop:ClearAllPoints(); frame.pop:SetPoint("TOPRIGHT", -34, -6)
        frame.pop:SetText("Dock"); frame.pop:SetShown(ahOpen() and true or false)
        -- with no Dock button the Snapshot button takes its place
        frame.snap:ClearAllPoints()
        if ahOpen() then frame.snap:SetPoint("RIGHT", frame.pop, "LEFT", -6, 0) else frame.snap:SetPoint("TOPRIGHT", -34, -6) end
        local pos = AuctionMeshDB.cfg.pos
        if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER", 0, 40) end
    end
    if dock then frame.snap:ClearAllPoints(); frame.snap:SetPoint("RIGHT", frame.pop, "LEFT", -6, 0) end
    self.docked = dock
    self:FitHeader()
end

-- The engine bar and its line of text live in the space between the tabs and
-- the Snapshot button, and are sized to it: on a narrow panel they shrink, and
-- when there is no room at all they are hidden rather than drawn over the
-- buttons. (The bar had a fixed place and a fixed 420-wide text, which ran
-- over the Snapshot button and the Setup tab.)
function UI:FitHeader()
    if not frame then return end
    local bar, txt = frame.bar, frame.barText
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", frame.snap, "LEFT", -10, 3)
    local function num(v) return type(v) == "number" and v or nil end
    local left = num(frame.tabHist.GetRight and frame.tabHist:GetRight())
    local right = num(frame.snap.GetLeft and frame.snap:GetLeft())
    local room = (left and right) and (right - left - 24) or BAR_W
    local w = math.max(0, math.min(BAR_W, floor(room)))
    self.barWidth = w
    if w < 60 then
        bar:Hide(); txt:Hide()
    else
        bar:Show(); txt:Show()
        bar:SetWidth(w)
        txt:SetWidth(w)
    end
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
    if (t.feeLost or 0) > 0 then
        out[#out + 1] = { l = "Posting fee lost (auction ran out)", r = RED .. "- " .. short(t.feeLost) .. "|r" }
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

-- DETAILS, SESSION: the figures under the charts.
function UI:SessionLines(entries, short)
    local S = ns.Sniper
    local d = self:SessionData(entries)
    local out = {}
    local function secs(x) return ("%.2fs"):format(x) end
    out[#out + 1] = { head = "GOLD THIS SESSION" }
    out[#out + 1] = { l = "In hand", r = GOLD .. short(d.now.gold) .. "|r" }
    out[#out + 1] = { l = "When all has sold (after the cut)", r = TEAL .. short(d.now.total) .. "|r" }
    local up = d.now.total - (d.start and d.start.w or d.now.total)
    out[#out + 1] = { l = "Since the start of the session", r = (up >= 0 and GREEN or RED) .. (up >= 0 and "+ " or "- ") .. short(math.abs(up)) .. "|r" }
    out[#out + 1] = { l = "Sale gold already sold, due within the hour", r = d.coming > 0 and (ORANGE .. "+ " .. short(d.coming) .. "|r") or (GREY .. "none|r") }
    -- how fast: yours against the buyer who was first
    local sp = d.speed
    out[#out + 1] = { head = "SPEED: FROM A DEAL SHOWING TO ITS PURCHASE" }
    if #sp.rows == 0 then
        out[#out + 1] = { l = GREY .. "Nothing measured yet: it fills in with your next tries.|r" }
    else
        local function line(label, b, word)
            if b.n == 0 then return end
            out[#out + 1] = { l = label, rw = 236, r = ("%d, %s%s on average, fastest %s"):format(b.n, word, secs(b.sum / b.n), secs(b.best)) }
        end
        line(GREEN .. "You bought|r", sp.won, "")
        line(RED .. "Someone else was first|r", sp.lost, "within ")
        line(ORANGE .. "Gone, no input|r", sp.gone, "after ")
        local pt = sp.parts
        if pt.n > 0 then
            out[#out + 1] = { l = GREY .. ("Your purchases, on average: input %s, the game's lock %s,|r"):format(secs(pt.input / pt.n), secs(pt.lock / pt.n)) }
            out[#out + 1] = { l = GREY .. ("price answer %s, purchase %s.|r"):format(secs(pt.price / pt.n), secs(pt.buy / pt.n)) }
        end
    end
    do  -- your pressing
        local t = S.tally
        local n = (t.inTime or 0) + (t.late or 0)
        local w = UI.PaceWindow()
        out[#out + 1] = { l = "Presses in time this session", r = n > 0 and ("%d of %d"):format(t.inTime or 0, n) or (GREY .. "none yet|r") }
        out[#out + 1] = { l = GREY .. ("Optimal: an input every %d ms or faster. Too slow: over %d ms.|r"):format(floor(w / 2 * 1000 + 0.5), floor(w * 1000 + 0.5)) }
    end
    if #sp.rows > 0 then
        out[#out + 1] = { head = ("LAST TRIES, NEWEST FIRST (%d)"):format(#sp.rows) }
        for i = #sp.rows, 1, -1 do
            local r = sp.rows[i]
            local what
            if r.k == "won" then
                what = GREEN .. "BOUGHT in " .. secs(r.s) .. "|r"
            elseif r.k == "lost" then
                what = RED .. (r.lo and ("TAKEN between %s and %s"):format(secs(r.lo), secs(r.s)) or ("TAKEN within " .. secs(r.s))) .. "|r"
            else
                what = ORANGE .. "GONE after " .. secs(r.s) .. "|r"
            end
            out[#out + 1] = { l = GREY .. date("%H:%M:%S", r.t) .. "|r  " .. (r.key and S.nameOf(r.key) or "?"), rw = 190, r = what }
            if r.k == "gone" then
                out[#out + 1] = { l = GREY .. "   no input from you while it was up|r" }
            else
                out[#out + 1] = { l = GREY .. ("   you: input at %s%s%s|r"):format(secs(r.i or 0),
                    r.h and (", held by the lock " .. secs(r.h)) or "",
                    r.q and (", price back at " .. secs((r.i or 0) + r.q)) or ", no price came back") }
            end
        end
    end
    do  -- the radar and its last alert (they were on the Trades tab)
        local Sw, G, W = ns.Swarm, ns.Gate, ns.Watch
        out[#out + 1] = { head = "RADAR" }
        local m = W and W.LastMinute and W:LastMinute() or {}
        out[#out + 1] = { l = "A read every", r = m.every and (("%.2fs"):format(m.every) .. (G.cycle and (GREY .. (" (limit %.2fs)|r"):format(G.cycle)) or "")) or (GREY .. "starting|r") }
        if (m.n or 0) > 0 then
            out[#out + 1] = { l = "Requests in the last minute", rw = 210,
                r = ("%d radar, %d alerts, %d buying, %d other"):format(m.radar or 0, m.alert or 0, m.buy or 0, (m.upkeep or 0) + (m.sell or 0)) }
        end
        local ready, watched = S:ReadyCount()
        if ns.Deals.cfg.flips and watched > 0 then
            out[#out + 1] = { l = "Ready for a flip straight from the radar", r = ("%d of %d"):format(ready, watched) }
        end
        local l = S.lastAlert
        if l and GetTime() - l.at < 600 then
            out[#out + 1] = { l = GREY .. ("Last alert, %s ago: %s|r"):format(clock(GetTime() - l.at), S.nameOf(l.key)) }
            local why = l.deal and "DEAL FOUND" or ((l.reason or "no deal"):gsub("%$(%d+)", function(c) return short(tonumber(c)) end))
            for _, t in ipairs(wrap(why, 62)) do out[#out + 1] = { l = (l.deal and GREEN or GREY) .. "   " .. t .. "|r" } end
        end
    end
    return out
end

-- DETAILS, ITEMS: what the addon goes for, with two tick boxes on each item.
--   Always: on your own list (watched whatever the addon picks).
--   Ignore: never offered, flip or vendor deal.
-- The list keeps its order while you tick (it is put together again when the
-- view is opened, or after two minutes), so a row never jumps from under the mouse.
function UI:ItemRows()
    local c = self.itemsCache
    if c and GetTime() - c.at < 120 then return c end
    local S, Sc = ns.Sniper, ns.Scout
    local cfg = AuctionMeshDB.cfg
    local set, flist, ftext = S:FocusSet()
    local prime = Sc:Prime(S:Budget(), S.VENDOR_SOLD)
    local facts, seen = {}, {}
    for _, f in ipairs(prime) do facts[f.key] = f end
    c = { at = GetTime(), focused = set ~= nil, text = ftext, facts = facts, picks = {}, own = {}, ignored = {} }
    local function add(list, key) if not seen[key] then seen[key] = true; list[#list + 1] = key end end
    -- what you ignore is not gone for, whoever picked it: it has its own section
    local ig = {}
    for k in pairs(cfg.ignore or {}) do ig[#ig + 1] = k end
    table.sort(ig, function(a, b) return S.nameOf(a) < S.nameOf(b) end)
    for _, k in ipairs(ig) do add(c.ignored, k) end
    if set then
        for _, k in ipairs(flist) do add(c.picks, k) end
    else
        for i = 1, math.min(30, #prime) do add(c.picks, prime[i].key) end
    end
    for _, k in ipairs(cfg.focusItems or {}) do add(c.own, k) end
    self.itemsCache = c
    return c
end

function UI:ItemLines(short)
    local S = ns.Sniper
    local c = self:ItemRows()
    local out = {}
    local function rows(list)
        for _, k in ipairs(list) do
            local f = c.facts[k]
            out[#out + 1] = { item = k, l = S.nameOf(k), rw = 110, r = f and (GREY .. ("%d sell/h  %s|r"):format(floor(f.rate + 0.5), short(f.market))) or "" }
        end
    end
    local mode = AuctionMeshDB.cfg.focusMode or "off"
    out[#out + 1] = { head = (c.focused and "ITEMS THE ADDON GOES FOR (%d)" or "MOST ACTIVE ITEMS (%d)"):format(#c.picks) }
    local text = c.focused and c.text
        or mode == "off" and "Laser focus is off (Setup tab): every material is watched. These have the most gold moving."
        or c.text
    for _, l in ipairs(wrap(text or "", 62)) do out[#out + 1] = { l = GREY .. l .. "|r" } end
    out[#out + 1] = { l = GREY .. "Always  Ignore|r", rw = 110, r = GREY .. "sells, price|r" }
    if #c.picks == 0 then out[#out + 1] = { l = GREY .. "None yet: selling speed takes some minutes of watching to measure.|r" } end
    rows(c.picks)
    if #c.own > 0 then
        out[#out + 1] = { head = ("YOUR OWN LIST, NOT AMONG THE ABOVE (%d)"):format(#c.own) }
        rows(c.own)
    end
    if #c.ignored > 0 then
        out[#out + 1] = { head = ("IGNORED (%d)"):format(#c.ignored) }
        rows(c.ignored)
    end
    out[#out + 1] = { rule = true }
    for _, l in ipairs(wrap("Always: on your own list, watched whatever the addon picks" .. (mode == "off" and " (it counts once laser focus is on)" or "")
        .. ". Ignore: never offered. To add another item, click it on the left, then 'Add to my focus list'.", 62)) do
        out[#out + 1] = { l = GREY .. l .. "|r" }
    end
    return out
end

-- A tick box in the Items view was clicked.
function UI:ItemTick(key, which)
    local S, Sc = ns.Sniper, ns.Scout
    local cfg = AuctionMeshDB.cfg
    cfg.ignore = cfg.ignore or {}
    if which == "ignore" then
        if cfg.ignore[key] then
            cfg.ignore[key] = nil
        else
            cfg.ignore[key] = true
            if Sc:InList(key) then Sc:Toggle(key) end
            -- a deal on screen for it goes, without counting as a miss
            S.verified[key] = nil
            if S.dealSeen then S.dealSeen[key] = nil end
        end
    else
        if Sc:Toggle(key) then cfg.ignore[key] = nil end
    end
    if S.judged then S.judged[key] = nil end -- its next listing is looked at afresh
    Sc:Changed()
    self:Render()
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
    local view = self.dview or "trades"
    if not key and view == "session" then return self:SessionLines(entries, short) end
    if not key and view == "items" then return self:ItemLines(short) end
    if not key and view == "market" then
        -- what the price history and the volume measurements say
        -- where the money moves: the prime items, with the reason each one is prime
        local set, flist, ftext = S:FocusSet()
        local prime = ns.Scout:Prime(S:Budget(), S.VENDOR_SOLD)
        out[#out + 1] = { head = ("PRIME ITEMS: FAST SELLERS WITH GOLD MOVING (%d)"):format(#prime) }
        for _, l in ipairs(wrap(ftext, 62)) do out[#out + 1] = { l = GREY .. l .. "|r" } end
        if #prime == 0 then
            for _, l in ipairs(wrap("None yet. An item is prime once it has been watched for 10 minutes and is measured to sell 30 or more an hour.", 62)) do
                out[#out + 1] = { l = GREY .. l .. "|r" }
            end
        end
        for i = 1, math.min(12, #prime) do
            local f = prime[i]
            out[#out + 1] = { l = ((set and set[f.key]) and TEAL .. "> |r" or "") .. S.nameOf(f.key), r = short(f.market), prime = f.key }
            out[#out + 1] = { l = GREY .. "   " .. ns.Scout:Why(f, short) .. "|r" }
        end
        local moves = ns.Do.Trends(12)
        out[#out + 1] = { head = "BIGGEST PRICE MOVES, 24 HOURS" }
        if #moves == 0 then out[#out + 1] = { l = GREY .. "Not yet: the price history needs a few hours of readings.|r" } end
        for _, m in ipairs(moves) do
            out[#out + 1] = { l = S.nameOf(m.key), r = (m.tr >= 0 and GREEN or RED) .. ("%+d%%|r"):format(floor(m.tr * 100 + 0.5)) .. "  " .. short(m.price) }
        end
        local fast = {}
        for k in pairs(St.vs) do
            local rate = St:Rate(k, 100)
            if rate and rate >= 1 then fast[#fast + 1] = { key = k, rate = rate } end
        end
        table.sort(fast, function(a, b) return a.rate > b.rate end)
        out[#out + 1] = { head = "WHAT SELLS FASTEST, MEASURED" }
        if #fast == 0 then out[#out + 1] = { l = GREY .. "Not yet: volume is measured by watching listings over time.|r" } end
        for i = 1, math.min(12, #fast) do
            local f = fast[i]
            out[#out + 1] = { l = S.nameOf(f.key), r = ("%d an hour"):format(floor(f.rate + 0.5)) .. (St.p[f.key] and ("  " .. short(St.p[f.key])) or "") }
        end
        return out
    end
    if key then
        -- ONE ITEM: the market as last read, then your trades in it
        local now = GetServerTime()
        out[#out + 1] = { l = WHITE .. S.nameOf(key) .. "|r", big = true }
        do  -- is it prime, and why or why not
            local f = ns.Scout:Facts(key, now)
            local score, why = ns.Scout:Score(f, S:Budget(), S.VENDOR_SOLD[key])
            for _, l in ipairs(wrap(score and ("Prime item: " .. ns.Scout:Why(f, short) .. ".") or ("Not a prime item: " .. why .. "."), 62)) do
                out[#out + 1] = { l = (score and TEAL or GREY) .. l .. "|r" }
            end
        end
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
    -- THE LEDGER: one line per purchase. What was bought and at what price on
    -- the left; on the right what became of it: the profit if it sold, or how
    -- much you are down while it has not. Nothing else. (Click an item on the
    -- left of the panel for the full story of one item.)
    local trades = J:Trades()
    local _, _, _, soldKeys = Se:SalesMoney()
    local cut = ns.Deals.cfg.cut
    local spent, back, coming, out_, waiting = 0, 0, 0, 0, 0
    local rows = {}
    for _, t in ipairs(trades) do
        local left, done, lost = J.left(t), (t.sold or 0) + (t.vend or 0), t.lost or 0
        local l = ("%s x%d"):format(tostring(t.name), t.qty) .. (t.cost and (GREY .. "  at " .. short(t.cost) .. "|r") or "")
        local r
        if not t.cost then
            r = GREY .. "price paid not known|r"
        else
            local counted = t.qty - lost
            spent = spent + t.cost * counted
            back = back + (t.got or 0) - (t.feeLost or 0)
            local listed = math.min(t.listed or 0, left)
            if left <= 0 and done > 0 then
                local p = J.realized(t) or 0
                r = (p >= 0 and GREEN or RED) .. "SOLD  " .. signed(p, short) .. "|r"
            elseif left <= 0 then
                r = GREY .. "not found, not counted|r"
            elseif listed > 0 and soldKeys[t.key] then
                -- sold on the auction house, the gold is still on its way
                local net = floor((t.price or 0) * (1 - cut)) * listed
                local p = (t.got or 0) + net - t.cost * counted - (t.feeLost or 0)
                coming = coming + net
                r = ORANGE .. "SOLD, gold coming  " .. signed(p, short) .. "|r"
            else
                local down = t.cost * left
                out_, waiting = out_ + down, waiting + 1
                r = RED .. (done > 0 and ("%d NOT SOLD"):format(left) or "NOT SOLD") .. "  down " .. short(down) .. "|r"
            end
        end
        rows[#rows + 1] = { l = l, r = r, ledger = true, trade = t }
    end
    local now = back - spent
    out[#out + 1] = { head = "LEDGER" }
    out[#out + 1] = { l = "Paid for everything bought", r = "- " .. short(spent) }
    out[#out + 1] = { l = "Came back from what sold", r = GREEN .. "+ " .. short(back) .. "|r" }
    if coming > 0 then out[#out + 1] = { l = "Sold, gold on its way", r = ORANGE .. "+ " .. short(coming) .. "|r" } end
    out[#out + 1] = { rule = true }
    out[#out + 1] = { l = WHITE .. (now + coming >= 0 and "You are up" or "You are down") .. "|r",
        r = (now + coming >= 0 and GREEN or RED) .. short(math.abs(now + coming)) .. "|r" }
    if waiting > 0 then
        out[#out + 1] = { l = GREY .. ("%d purchase%s not sold yet: %s still to come back|r"):format(waiting, waiting == 1 and "" or "s", short(out_)) }
    end
    out[#out + 1] = { head = ("WHAT YOU BOUGHT, NEWEST FIRST (%d)"):format(#rows) }
    if #rows == 0 then out[#out + 1] = { l = GREY .. "Nothing yet. Buy a deal on the Trades tab.|r" } end
    for _, r in ipairs(rows) do out[#out + 1] = r end
    return out
end

function UI:CreateDrawer()
    local d = CreateFrame("Frame", "AuctionMeshDrawer", frame)
    d:SetWidth(DRAWER_W)
    d:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0)
    d:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 1, 0)
    UI.Draggable(d)
    d.art = d:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.art:SetAllPoints()
    d.art:SetColorTexture(0.045, 0.05, 0.06, 0.97)
    outline(d, LINE)
    -- four views: this session (tries, gold, speed), the items the addon goes
    -- for, the ledger of what you bought, and the market
    d.views = {}
    local prev
    for _, v in ipairs({ { "session", "Session" }, { "items", "Items" }, { "trades", "Ledger" }, { "market", "Market" } }) do
        local b = button(d, 56, v[2], function() UI.sel, UI.dview, UI.dscroll, UI.itemsCache = nil, v[1], 0, nil; UI:Render() end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 12, -8) end
        d.views[v[1]] = b
        prev = b
    end
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
        -- two tick boxes, used by the Items view only
        local function box(x, which)
            local b = CreateFrame("Button", nil, d)
            b:SetSize(12, 12); b:SetPoint("TOPLEFT", x, y - 1)
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.06)
            b.tick = b:CreateTexture(nil, "ARTWORK")
            b.tick:SetPoint("TOPLEFT", 3, -3); b.tick:SetPoint("BOTTOMRIGHT", -3, 3)
            if which == "ignore" then b.tick:SetColorTexture(0.9, 0.25, 0.25, 1) else b.tick:SetColorTexture(0.30, 0.86, 0.76, 1) end
            b.tick:Hide()
            outline(b, LINE)
            b:SetScript("OnClick", function(self) if self.key then UI:ItemTick(self.key, which) end end)
            b:Hide()
            return b
        end
        d.lines[i] = { label = l, value = v, rule = rule, y = y, always = box(23, "always"), ignore = box(62, "ignore") }
    end
    -- THE SESSION VIEW'S GRAPHICS: fixed at the top, the lines scroll under them
    do
        local c = CreateFrame("Frame", nil, d)
        c:SetPoint("TOPLEFT", 12, -38); c:SetSize(DRAWER_CHART_W, SESSION_ROWS * DLINE_H)
        local function small(x, y2, anchor, rel, relPoint)
            local f = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            f:SetPoint(anchor or "TOPLEFT", rel or c, relPoint or "TOPLEFT", x, y2)
            f:SetJustifyH("LEFT"); f:SetWordWrap(false)
            return f
        end
        -- tries
        c.triesText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.triesText:SetPoint("TOPLEFT", 0, 0); c.triesText:SetJustifyH("LEFT"); c.triesText:SetWordWrap(false)
        c.triesBar = CreateFrame("Frame", nil, c)
        c.triesBar:SetPoint("TOPLEFT", 0, -14); c.triesBar:SetSize(DRAWER_CHART_W, 8)
        local bg = c.triesBar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.06)
        c.won, c.lost, c.gone = c.triesBar:CreateTexture(nil, "ARTWORK"), c.triesBar:CreateTexture(nil, "ARTWORK"), c.triesBar:CreateTexture(nil, "ARTWORK")
        c.won:SetColorTexture(0.2, 0.9, 0.4, 1); c.lost:SetColorTexture(0.9, 0.25, 0.25, 1); c.gone:SetColorTexture(1, 0.55, 0.2, 1)
        -- gold
        small(0, -28):SetText(GREY .. "GOLD   columns: in hand   " .. TEAL .. "line: when all has sold|r" .. GREY .. "   pale: the next hour|r")
        c.plot = CreateFrame("Frame", nil, c)
        c.plot:SetPoint("TOPLEFT", 0, -42); c.plot:SetSize((CHART_COLS + CHART_NEXT) * CHART_W, CHART_H)
        local pbg = c.plot:CreateTexture(nil, "BACKGROUND")
        pbg:SetAllPoints(); pbg:SetColorTexture(1, 1, 1, 0.04)
        c.col = {}
        for i = 1, CHART_COLS + CHART_NEXT do
            local bar = c.plot:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("BOTTOMLEFT", (i - 1) * CHART_W, 0); bar:SetSize(CHART_W, 1)
            local tick = c.plot:CreateTexture(nil, "OVERLAY")
            tick:SetSize(CHART_W, 2)
            c.col[i] = { bar = bar, tick = tick }
        end
        local nowLine = c.plot:CreateTexture(nil, "OVERLAY")
        nowLine:SetPoint("BOTTOMLEFT", CHART_COLS * CHART_W, 0); nowLine:SetSize(1, CHART_H); nowLine:SetColorTexture(1, 1, 1, 0.5)
        c.top = small(6, 0, "TOPLEFT", c.plot, "TOPRIGHT")
        c.axisL = small(0, -3, "TOPLEFT", c.plot, "BOTTOMLEFT")
        c.axisN = small(CHART_COLS * CHART_W, -3, "TOP", c.plot, "BOTTOMLEFT")
        c.axisR = small(0, -3, "TOPRIGHT", c.plot, "BOTTOMRIGHT")
        -- speed
        small(0, -106):SetText(GREY .. "SPEED|r   " .. GREEN .. "you bought|r   " .. RED .. "someone else first|r   " .. ORANGE .. "gone, no input|r")
        c.speedPlot = CreateFrame("Frame", nil, c)
        c.speedPlot:SetPoint("TOPLEFT", 0, -120); c.speedPlot:SetSize(SPEED_COLS * SPEED_W, SPEED_H)
        local sbg = c.speedPlot:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints(); sbg:SetColorTexture(1, 1, 1, 0.04)
        c.speed = {}
        for i = 1, SPEED_COLS do
            local bar = c.speedPlot:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("BOTTOMLEFT", (i - 1) * SPEED_W, 0); bar:SetSize(SPEED_W - 2, 1)
            bar:Hide()
            c.speed[i] = bar
        end
        c.speedTop = small(6, 0, "TOPLEFT", c.speedPlot, "TOPRIGHT")
        c.speedAxis = small(0, -3, "TOPLEFT", c.speedPlot, "BOTTOMLEFT")
        c.speedNew = small(0, -3, "TOPRIGHT", c.speedPlot, "BOTTOMRIGHT")
        c:Hide()
        frame.chart = c
    end
    -- shown for one item: put it on, or take it off, your own focus list
    d.focus = button(d, 126, "", function()
        if not UI.sel then return end
        local on = ns.Scout:Toggle(UI.sel)
        UI:Notice(on and "Added to your focus list. Laser focus uses it when set to 'My own list' (Setup tab)."
            or "Removed from your focus list.", true)
        UI:Render()
    end)
    d.focus:SetPoint("TOPRIGHT", -12, -8)
    d.focus:Hide()
    -- stop tracking an item (it used to be a right-click on the row, which was too easy to do by accident)
    d.remove = button(d, 150, "", function()
        if not UI.sel then return end
        if UI.removeUntil and GetTime() < UI.removeUntil then
            UI.removeUntil = nil
            ns.Seller:Untrack(UI.sel)
            UI.sel = nil
        else
            UI.removeUntil = GetTime() + 5
        end
        UI:Render()
    end)
    d.remove:SetPoint("BOTTOMRIGHT", -12, 26)
    d.remove:Hide()
    -- STAKE-OUT: watch this one item by asking its price on every wheel notch
    d.stake = button(d, 170, "", function()
        if not UI.sel then return end
        local S = ns.Sniper
        if S:StakeKey() == UI.sel then
            S:SetStake(nil)
            UI:Notice("Stake-out ended. The radar is back to reading everything.", true)
        else
            S:SetStake(UI.sel)
            UI:Notice("Stake-out set on " .. S.nameOf(UI.sel) .. ". Roll the wheel in the snipe box: every notch asks its price and buys if it is low. The radar is off while you roll.", true)
        end
        UI:Render()
    end)
    d.stake:SetPoint("BOTTOMLEFT", 12, 26)
    d.stake:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Stake-out", 1, 1, 1)
        GameTooltip:AddLine("For one item that keeps being listed cheap. While you roll the wheel in the snipe box, every notch asks the server what one unit costs and buys it the moment that is a deal by your normal rules. This is about a second faster than the radar. Nothing else is watched while you roll.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    d.stake:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.stake:Hide()
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
        GameTooltip:AddLine("This session in charts, the items the addon goes for,\nthe ledger of what you bought, and the market.", 0.8, 0.8, 0.8)
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
    -- On a screen with no room to the right of the panel the drawer opens on
    -- the left instead of running off the edge.
    local left = false
    do
        local r, sw = frame.GetRight and frame:GetRight(), UIParent and UIParent.GetWidth and UIParent:GetWidth()
        local fs, us = frame.GetEffectiveScale and frame:GetEffectiveScale(), UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
        if type(r) == "number" and type(sw) == "number" and type(fs) == "number" and type(us) == "number" and us > 0 then
            left = (r + DRAWER_W + 24) * fs > sw * us
        end
    end
    d:ClearAllPoints()
    if left then
        d:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1, 0); d:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -1, 0)
    else
        d:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0); d:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 1, 0)
    end
    self.drawerLeft = left
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", (open and not left) and d or frame, "TOPRIGHT", 0, -40)
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
    -- A deal has just appeared (UI:Now): nothing in here is needed to buy it.
    -- What is on the drawer stays, and it is brought up to date by the next
    -- ordinary redraw.
    local sig = tostring(self.sel) .. ":" .. (self.dview or "trades")
    if self.fast and self.drawerLines and self.drawerSig == sig then self.drawerStale = true; return end
    self.drawerStale, self.drawerSig = nil, sig
    local session = not self.sel and self.dview == "session"
    self:RenderChart(session, ns.Seller.short, entries)
    local lines = self:DrawerLines(entries)
    self.drawerLines = lines
    local h = frame:GetHeight()
    local vis = type(h) == "number" and h > 0 and math.max(6, math.min(DLINES, floor((h - 38 - 28) / DLINE_H))) or 28
    local skip = session and SESSION_ROWS or 0 -- the graphics' rows: the lines start under them
    local off = math.max(0, math.min(self.dscroll or 0, #lines - (vis - skip)))
    self.dscroll = off
    for name, b in pairs(d.views) do outline(b, (not self.sel and (self.dview or "trades") == name) and ACCENT or LINE) end
    do
        local tracked = false
        if self.sel then for _, e in ipairs(entries) do if e.key == self.sel then tracked = true end end end
        d.remove:SetShown(tracked)
        d.remove:SetText((self.removeUntil and GetTime() < self.removeUntil) and "Click again to remove" or "Stop tracking this item")
    end
    d.focus:SetShown(self.sel ~= nil)
    d.stake:SetShown(self.sel ~= nil)
    if self.sel then
        local on = ns.Sniper:StakeKey() == self.sel
        d.stake:SetText(on and "Stop the stake-out" or "Stake out this item")
        outline(d.stake, on and ACCENT or LINE)
    end
    if self.sel then d.focus:SetText(ns.Scout:InList(self.sel) and "Remove from my focus" or "Add to my focus list") end
    local cfg = AuctionMeshDB.cfg
    for i = 1, DLINES do
        local w, ln = d.lines[i], (i > skip and i <= vis) and lines[i - skip + off] or nil
        local item = ln and ln.item
        if (w.indent or false) ~= (item ~= nil) then
            -- an item's line starts to the right of its two tick boxes
            w.indent = item ~= nil
            w.label:ClearAllPoints(); w.label:SetPoint("TOPLEFT", item and 92 or 12, w.y)
        end
        w.always:SetShown(item ~= nil); w.ignore:SetShown(item ~= nil)
        if item then
            w.always.key, w.ignore.key = item, item
            w.always.tick:SetShown(ns.Scout:InList(item))
            w.ignore.tick:SetShown(cfg.ignore ~= nil and cfg.ignore[item] == true)
        end
        if not ln then
            w.label:SetText(""); w.value:SetText(""); w.rule:Hide()
        else
            w.rule:SetShown(ln.rule == true)
            local rw = ln.rw or (ln.wide and 70 or ln.ledger and 170 or 130)
            w.label:SetWidth((ln.r and (DRAWER_W - 24 - rw) or (DRAWER_W - 24)) - (item and 80 or 0))
            w.label:SetText(ln.head and (GREY .. ln.head .. "|r") or ln.l or "")
            w.value:SetText(ln.r or "")
        end
    end
    local shown = vis - skip
    d.hint:SetText(#lines > shown and ("lines %d-%d of %d (mouse wheel). Click an item on the left for its details."):format(off + 1, math.min(#lines, off + shown), #lines)
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
    if frame then
        self:BindInputs(false, true)
        self:StopKeyCapture()
        frame:Hide()
    end
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
    -- a gold sample every 20 seconds for the session chart, panel open or not
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(20, function() UI:SampleGold() end) end
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

-- FOR THE LOG: what the inputs were doing, so that "a deal sat there and was
-- not bought" can be told apart from "no input reached the addon".
--   since = the input count when the deal appeared (nil: the last 5 seconds)
function UI.InputTrace(since)
    local t, now = UI.inputTimes or {}, GetTime()
    local n
    if since then
        n = (UI.inputCount or 0) - since
    else
        n = 0
        for i = #t, 1, -1 do
            if now - t[i] > 5 then break end
            n = n + 1
        end
    end
    local cfg = (AuctionMeshDB and AuctionMeshDB.cfg) or {}
    local mode = UI.BuyMode and UI.BuyMode() or "?"
    return ("%d input(s) %s, last input %s | panel %s, tab %s, buy with %s%s, wheel bound: %s, key bound: %s"):format(
        n, since and "while it was up" or "in the last 5s",
        t[#t] and ("%.2fs ago"):format(now - t[#t]) or "never",
        (frame and frame:IsShown()) and "open" or "shut", tostring(UI.tab), tostring(mode),
        (mode == "key" or mode == "one") and (" (key " .. tostring(cfg.buyKey or "none chosen") .. ")") or "",
        UI.wheelBound and "yes" or "no", UI.keyBound and tostring(UI.keyBound) or "no")
end

-- ERRORS ARE NOT SWALLOWED IN SILENCE. The game hides addon errors unless
-- you switch them on, so one in here would only show as "it stopped
-- working". The redraw and the input handler run guarded: an error goes to
-- the log and the Snapshot with where it happened (once per kind, counted),
-- and everything else carries on.
do
    local function catcher(name)
        return function(e)
            local msg = tostring(e)
            ns.errs = ns.errs or {}
            ns.errList = ns.errList or {}
            local rec = ns.errs[msg]
            if not rec then
                rec = { n = 0, name = name, msg = msg }
                ns.errs[msg] = rec
                ns.errList[#ns.errList + 1] = rec
                local st = debugstack and tostring(debugstack(2, 5, 0) or "") or ""
                rec.stack = (st:gsub("%s*\n%s*", " < "))
                if ns.Log then ns.Log("ERROR in %s: %s | %s", name, msg, rec.stack) end
                UI.notice = { text = "|cffff4040AuctionMesh hit an error|r (" .. name .. "). It is in the log: send a Snapshot.", till = GetTime() + 20 }
            end
            rec.n, rec.at = rec.n + 1, GetTime()
        end
    end
    local realRender, onRenderErr = UI.Render, catcher("the redraw")
    local function runRender() return realRender(UI) end
    function UI:Render()
        if not xpcall(runRender, onRenderErr) then self.fast = nil end
    end
    local realPress, onPressErr = UI.InputPress, catcher("an input")
    local a1, a2
    local function runPress() return realPress(a1, a2) end
    function UI.InputPress(inBox, via)
        a1, a2 = inBox, via
        local ok, r = xpcall(runPress, onPressErr)
        return ok and r or false
    end
end

return UI
