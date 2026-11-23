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
-- Buy tab: SNIPING ONLY. MONEY (what you hold and what it becomes once
-- everything has sold), then deals verified against live listings with the
-- exact quantity and total you will pay. Sell tab: everything you bought and
-- the one thing to do with it, then your own auctions (sold, undercut with a
-- Cancel button, ended, listed). More tab: settings, what the request engine
-- has learned, recent activity. A bar at the top shows what the engine is doing.
-- Rendering is throttled (5x per second, only while shown and only if changed).
local _, ns = ...
ns = ns or {}

local UI = {}
ns.UI = UI

local floor, min = math.floor, math.min
local ROWS, ROW_H, WIDTH = 10, 22, 720
local FLOAT_H = 520 -- floating window height
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
        self.fast = true
        self:Render()
        self.fast = nil
    else
        self.dirty = true
    end
end

-- Shows the latest message at the top of the window for 10 seconds.
-- The Refresh button: what you hold is read again and everything is redrawn
-- from scratch (lists back at their top, nothing kept from the last drawing).
function UI:Refresh()
    local Se = ns.Seller
    local back = Se:Rescan()
    self.scroll, self.fast = {}, nil
    local n = 0
    for _, e in ipairs(Se:Entries()) do if e.action ~= "LISTED" then n = n + 1 end end
    self:Notice(("Refreshed: %s. %d item%s to deal with (tab Sell).%s"):format(Se:BagsSeenText(), n, n == 1 and "" or "s",
        back > 0 and (" %d unit%s the addon had lost track of %s back."):format(back, back == 1 and "" or "s", back == 1 and "is" or "are") or ""), true)
    self:Render()
end

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
    local shownProfit
    r.c[1]:SetText(("%d @ %s"):format(units, short(unit)))
    if d.kind == "VENDOR" then
        r.c[2]:SetText(short(d.sell))
        r.c[3]:SetText(GREEN .. pct(unit, d.sell) .. "|r")
        r.c[4]:SetText(GREEN .. "instant|r")
        r.detail:SetText(("%sSAFE|r  Buy %d for %s, vendor pays %s"):format(GREEN, units, short(total), short(d.sell * units)))
        shownProfit = each * units
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
        shownProfit = d.profit
    end
    -- the more it makes, the stronger the row: tint, name and profit figure
    local heat, tier = UI.Heat(shownProfit)
    r.profit:SetText(heat[4] .. "+" .. short(shownProfit) .. "|r")
    if tier <= 2 then r.name:SetText(heat[4] .. S.nameOf(d.key) .. "|r") end
    if heat[2] then r.heat:SetColorTexture(heat[2][1], heat[2][2], heat[2][3], heat[3]); r.heat:Show() end
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
            -- (always there on an undercut row while the auction house is open: with no auction
            -- on record to cancel, a click reads your auctions first)
            local can = ahOpen()
            local arm = Se.cancelArm
            local armed = arm and arm.key == e.key and GetTime() - arm.at < 5
            -- RELIST OR HOLD, with the reason (worked out by Seller:Undercut from the listing, the sale rate and the fees)
            local a = e.adv
            local text = a and ((a.rec == "relist" and GOLD or GREY) .. (a.rec == "relist" and "Relist: " or a.rec == "hold" and "Hold: " or "") .. a.why .. "|r")
                or (ORANGE .. "Listed, but someone is cheaper|r")
            return text, can and (armed and "Sure?" or "Cancel") or nil
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
    if e.noPrice then text, button = ORANGE .. "No price to go by|r", nil end
    r.state:SetText(text)
    local paid, sell, _, profit, live = Se:Numbers(e)
    r.c[1]:SetText(tostring(e.count))
    r.c[2]:SetText(e.farm and (GREEN .. "farmed|r") or paid and short(paid) or (ORANGE .. "?|r"))
    r.c[3]:SetText(short(sell) .. ((e.f.kind == "FLIP" and not live and e.action ~= "LISTED") and (GREY .. "*|r") or ""))
    local adv = e.action == "LISTED" and e.undercut and e.adv or nil
    local advWord
    if adv then
        -- a hold with a time counts down; when it is up the listing is read again (see Seller:Undercut)
        advWord = adv.word
        local left = adv.untilT and (adv.untilT - GetTime()) or nil
        if adv.rec == "hold" and left and left > 0 then
            advWord = "HOLD " .. (left >= 3600 and ("%dh%02d"):format(floor(left / 3600), floor(left / 60) % 60) or ("%d:%02d"):format(floor(left / 60), floor(left) % 60))
            UI.holdTick = true
        end
        -- WHY, in a few words, where the cost and the market price are on other rows
        r.c[2]:SetText(""); r.c[3]:SetText("")
        r.brief:SetText((adv.rec == "relist" and GOLD or GREY) .. tostring(adv.brief or adv.why or "") .. "|r")
        r.brief:Show()
    end
    r.c[4]:SetText(e.action == "LISTED" and (e.sold and (GREEN .. "SOLD|r") or e.live == 0 and (GREEN .. "SOLD?|r")
            or adv and ((adv.rec == "relist" and GOLD or adv.rec == "hold" and GREEN or GREY) .. advWord .. "|r")
            or e.undercut and (ORANGE .. "UNDERCUT|r") or (GREY .. "LISTED|r"))
        or e.action == "AH" and (ready and (GOLD .. "READY|r") or (GREY .. "pricing|r"))
        or e.action == "VENDOR" and (GREEN .. "VENDOR|r") or e.action == "MAIL" and (CYAN .. "MAIL|r") or (RED .. "WAIT|r"))
    if adv and adv.pl then
        -- UNDERCUT: what the advised choice leaves you with, every lost fee and the relist included (Seller:Undercut)
        r.profit:SetText((adv.pl >= 0 and (GREEN .. "+") or (RED .. "-")) .. short(math.abs(adv.pl)) .. "|r")
    elseif adv and profit then
        -- (it cannot be worked out, no sale rate yet: the plain figure if it sells at your price, in grey)
        r.profit:SetText(GREY .. (profit >= 0 and "+" or "-") .. short(math.abs(profit * e.count)) .. "|r")
    elseif profit and e.action ~= "HOLD" then
        r.profit:SetText((profit >= 0 and GREEN .. "+" or RED) .. short(profit * e.count) .. "|r")
    else
        r.profit:SetText("")
    end
    local paidText = paid and short(paid) or (ORANGE .. "unknown|r")
    if e.farm and e.action ~= "HOLD" then
        local vm = e.action ~= "LISTED" and Se.vendorMore and Se.vendorMore[e.key]
        if e.noPrice then r.c[4]:SetText(ORANGE .. "NO PRICE|r"); r.profit:SetText("") end
        r.detail:SetText(e.noPrice and (ORANGE .. "Farmed or mined: " .. e.noPrice .. "|r") or ("Farmed or mined: cost nothing  >  Sell %s%s  >  %s+%s|r each, all profit%s"):format(short(sell),
            (not live and e.action ~= "LISTED") and (GREY .. " (about)|r") or "", GREEN, short(profit or 0),
            vm and (ORANGE .. ("   (a vendor pays more: %s each)|r"):format(short(vm))) or ""))
    elseif e.action == "HOLD" then
        r.detail:SetText(("Paid %s each  >  market is lower right now"):format(paidText))
    else
        local profitText = ""
        if profit then profitText = ("  >  %s%s%s|r each"):format(profit >= 0 and GREEN or RED, profit >= 0 and "+" or "", short(profit)) end
        local est = (e.f.kind == "FLIP" and not live and e.action ~= "LISTED") and (GREY .. " (planned)|r") or ""
        r.detail:SetText(("Paid %s  >  Sell %s%s%s"):format(paidText, short(sell), est, profitText))
        -- A VENDOR WOULD PAY MORE THAN IT COST: both ways out on the row, with
        -- the difference. Vendor now, or wait (for the fee, for the sale) and list it.
        if e.undercut and e.adv then r.detail:SetText(e.adv.text) end -- (the whole advice, with its figures: shown when the mouse is on the row)
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
    -- the button to press stands out when the advice is to relist; with "hold" it is there but plain
    UI.outline(r.btn, (e.undercut and e.adv and e.adv.rec ~= "relist") and LINE or ACCENT)
end

---------------------------------------------------------------- status line

local function clock(s)
    s = math.floor(s + 0.5)
    return s >= 60 and ("%d:%02d"):format(s / 60, s % 60) or (s .. "s")
end

-- The Buy tab's status: anything urgent about your gold first, then SPEED in
-- numbers (two lines, each a measured fact of the last 60 seconds):
--   1. SPEED n%: lock unused, radar reads lost, held for a deal
--   2. what the requests went to, and the game's lock per request
-- Switched off on this character (a bank alt is set and this is not it): said
-- in full wherever a status line is. With the panel opened by hand nothing
-- happens, and that must never look like something is stuck.
local function dormantLine()
    local cfg = AuctionMeshDB.cfg
    local c = (AuctionMeshDB.chars or {})[cfg.bankAlt or ""]
    return ORANGE .. ("SWITCHED OFF ON THIS CHARACTER: the addon is set to work on %s only. Nothing runs here: no deals, no prices, no posting, no mail.|r "):format(c and c.name or "your bank alt")
        .. GOLD .. "Click the badge at the top left to use it on every character again.|r"
end
local function buyStatus(n)
    if ns.Dormant() then return dormantLine() end
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
                or ((cap.onway or 0) + (cap.waiting or 0) > 0 and " Sale gold is waiting at the mailbox." or " Sell to a vendor (Sell tab) to get there."))
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
    -- went and the radar's figures are in the Snapshot.)
    if G:UserBusy() then
        lines[#lines + 1] = mode .. ORANGE .. "Paused for a moment (a click is in progress).|r"
    elseif sk then
        local max, why = S:StakeTerms()
        lines[#lines + 1] = mode .. (not max and (ORANGE .. "Waiting: " .. tostring(why or "reading its market first") .. ".|r")
            or S:Staking() and (GREEN .. "Running: every input asks its price. Nothing else is bought and the radar is off.|r")
            or (GREY .. "Not running: press in the snipe box to start it. Until then the radar reads as usual.|r"))
    else
        if Sw and Sw.active and #Sw.units > 0 then
            -- SPEED, IN NUMBERS (measured over the last 60 seconds; see Watch:Speed).
            -- 100% = every request left the moment the game allowed it, and every one was answered.
            local W = ns.Watch
            local m = W and W.Speed and W:Speed() or {}
            if m.pct then
                local pc = floor(m.pct * 100 + 0.5)
                local bad = ORANGE
                lines[#lines + 1] = mode .. (pc >= 99 and GREEN or pc >= 95 and GOLD or RED) .. ("SPEED %d%%|r"):format(pc)
                    .. GREY .. "  last 60s: lock unused |r" .. (m.idle >= 0.6 and bad or GREY) .. ("%.1fs|r"):format(m.idle)
                    .. GREY .. ", radar reads lost |r" .. (m.lost > 0 and bad or GREY) .. m.lost .. "|r"
                    .. GREY .. (", held for a deal %.1fs|r"):format(m.held)
                if #lines == 1 then -- (the second line, when nothing more urgent has taken one)
                    lines[#lines + 1] = GREY .. ("Requests %d: radar %d, alert checks %d, buying %d, upkeep %d. The game's lock: %s a request.|r"):format(
                        m.n, m.radar or 0, m.alert or 0, m.buy or 0, (m.upkeep or 0) + (m.sell or 0), m.lock and ("%.2fs"):format(m.lock) or "not measured yet")
                end
            else
                lines[#lines + 1] = mode .. GREY .. "SPEED: measuring (the first requests are going out).|r"
            end
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
    -- farmed or mined: it cost nothing, so what it sells for is all profit
    -- in your bags, not tracked: what it is worth if you add and post it
    loose = { "QTY", "", "MARKET", "", "WORTH" },
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

-- SORTING BY A COLUMN. A click on a column's caption in a heading row sorts
-- that tab's rows by it (largest first; a second click turns it round; a
-- click on the heading's name puts the usual order back). Kept per tab.
-- Sorting changes what is shown and nothing else: which deal a press buys
-- is decided by the sniper, not by this order.
UI.sortBy = {}
local function sortVal(item, col)
    if item.sortv then return item.sortv[col] or 0 end
    if item.loose then return ({ item.count, 0, item.market or 0, 0, (item.market or 0) * item.count })[col] or 0 end
    if item.action then
        local paid, sell, _, profit = ns.Seller:Numbers(item)
        local adv = item.adv
        return ({ item.count, paid or 0, sell or 0, (adv and adv.rec == "relist") and 2 or adv and 1 or 0, (adv and adv.pl) or (profit or 0) * item.count })[col] or 0
    end
    if item.key and item.profit and not item.ghost then -- a deal
        local units, total = ns.Sniper.NextBuy(item)
        local unit = units > 0 and total / units or 0
        return ({ total, item.wall or item.sell or 0, unit > 0 and ((item.sell or 0) - unit) / unit or 0, item.rate or 0, item.profit })[col] or 0
    end
    return 0
end
local function sorted(tab, items)
    local sb = UI.sortBy[tab]
    if not sb or #items < 2 then return items end
    local out, vals = {}, {}
    for i, it in ipairs(items) do out[i] = it; vals[it] = sortVal(it, sb.col) end
    table.sort(out, function(a, b)
        if vals[a] ~= vals[b] then
            if sb.desc then return vals[a] > vals[b] end
            return vals[a] < vals[b]
        end
        return (a.key or 0) < (b.key or 0)
    end)
    return out
end
-- the captions, with a mark on the column the tab is sorted by
local function capsFor(tab, caps)
    local sb = UI.sortBy[tab]
    if not sb or not caps then return caps end
    local c = {}
    for i = 1, 5 do c[i] = caps[i] end
    if c[sb.col] and c[sb.col] ~= "" then c[sb.col] = c[sb.col] .. (sb.desc and " v" or " ^") end
    return c
end
-- A click on a caption: col 1 to 5; 0 = the heading's name (the usual order again).
function UI:SortBy(tab, col)
    if not col or col <= 0 then
        self.sortBy[tab] = nil
    else
        local sb = self.sortBy[tab]
        if sb and sb.col == col then sb.desc = not sb.desc else self.sortBy[tab] = { col = col, desc = true } end
    end
    self.scroll = self.scroll or {}
    self.scroll[tab] = 0
    self:Render()
end

-- THE SOLD TAB: what has sold. Three lists:
--   SOLD, GOLD ON ITS WAY    auctions the auction house lists as sold and not
--                            paid out yet
--   ENDED, CHECK A MAILBOX   auctions the auction house no longer lists: sold
--                            or run out, the mailbox shows which (they were a
--                            section of the Sell tab; nothing there to do)
--   PAID, LAST 24 HOURS      sales whose gold you have collected, from the
--                            record of your trades
-- Columns: COST, SOLD AT, SPREAD (the price it sold at over what it cost, the
-- same figure as SPREAD on the Buy tab), when, PROFIT (after the cut and
-- fees). The quantity is in the name. A click on a caption sorts by it.
-- Rows are plain cells: nothing to press here.
local function spreadOf(cost, price, farm)
    -- returns the text and the value to sort by (farmed: cost nothing, so no ratio: sorted above every ratio)
    if farm then return GREEN .. "all profit|r", 1e9 end
    if not cost or cost <= 0 or not price or price <= 0 then return GREY .. "?|r", -1e9 end
    local v = (price - cost) / cost
    return (v >= 0 and GREEN or RED) .. ("%+d%%"):format(floor(v * 100 + 0.5)) .. "|r", v
end
UI.SpreadOf = spreadOf
function UI.SoldData(entries)
    local Se, S, J = ns.Seller, ns.Sniper, ns.Journal
    local short = Se.short
    local d = { pending = {}, ended = {}, paid = {}, coming = 0, nextIn = nil, paidSum = 0 }
    local _, _, _, soldKeys = Se:SalesMoney()
    for _, e in ipairs(entries) do
        local isSold = e.action == "LISTED" and soldKeys[e.key] == true
        if isSold then
            local soldIn
            for _, r in ipairs(S.ownSoldPay or {}) do
                local left = r.due - GetTime()
                if r.key == e.key and left > 0 and (not soldIn or left < soldIn) then soldIn = left end
            end
            local paid, sell, net, profit = Se:Numbers(e)
            local p = (profit or 0) * e.count
            local sp, spv = spreadOf(paid, sell, e.farm)
            d.coming = d.coming + (net or 0) * e.count
            if soldIn and (not d.nextIn or soldIn < d.nextIn) then d.nextIn = soldIn end
            d.pending[#d.pending + 1] = {
                key = e.key, plainRow = true, name = S.nameOf(e.key) .. (e.count > 1 and (" x" .. e.count) or ""),
                cells = { e.farm and (GREEN .. "farmed|r") or paid and short(paid) or (ORANGE .. "?|r"), short(sell or 0), sp,
                          GREEN .. (soldIn and ("in %d min"):format(math.max(1, floor(soldIn / 60 + 0.5))) or "on its way") .. "|r" },
                profit = (p >= 0 and (GREEN .. "+") or RED) .. short(p) .. "|r",
                sortv = { paid or 0, sell or 0, spv, soldIn or 0, p },
            }
        elseif e.action == "LISTED" and e.live == 0 then
            -- no longer on the auction house, and not (yet) listed there as sold
            local paid, sell, _, profit = Se:Numbers(e)
            local p = (profit or 0) * e.count
            local sp, spv = spreadOf(paid, sell, e.farm)
            d.ended[#d.ended + 1] = {
                key = e.key, plainRow = true, name = S.nameOf(e.key) .. (e.count > 1 and (" x" .. e.count) or ""),
                cells = { e.farm and (GREEN .. "farmed|r") or paid and short(paid) or (ORANGE .. "?|r"), short(sell or 0), sp, GOLD .. "mailbox|r" },
                profit = GREY .. (p >= 0 and "+" or "-") .. short(math.abs(p)) .. "|r", -- (grey: only if it sold)
                sortv = { paid or 0, sell or 0, spv, 0, p },
            }
        end
    end
    local now = GetServerTime()
    for _, t in ipairs(J.list or {}) do
        if (t.sold or 0) > 0 and t.soldAt and now - t.soldAt <= 24 * 3600 then
            local p = J.realized(t) or 0
            local age = now - t.soldAt
            local farm = t.kind == "FARM"
            local sp, spv = spreadOf(t.cost, t.soldPrice, farm)
            d.paidSum = d.paidSum + p
            d.paid[#d.paid + 1] = {
                key = t.key, plainRow = true, name = tostring(t.name) .. (t.sold > 1 and (" x" .. t.sold) or ""),
                cells = { farm and (GREEN .. "farmed|r") or t.cost and short(t.cost) or (ORANGE .. "?|r"), short(t.soldPrice or 0), sp,
                          GREY .. (age < 5400 and (math.max(1, floor(age / 60)) .. " min ago") or (floor(age / 3600) .. " h ago")) .. "|r" },
                profit = (p >= 0 and (GREEN .. "+") or RED) .. short(math.abs(p)) .. "|r",
                sortv = { t.cost or 0, t.soldPrice or 0, spv, -age, p },
                age = age,
            }
        end
    end
    table.sort(d.paid, function(x, y) return x.age < y.age end) -- newest first
    return d
end

-- What a tab lists, as one sequence of heading rows and item rows.
--   Trades: deals to buy, and nothing else
--   Bags:   what you hold, grouped by what to do with it, then your auctions
--           (sold, stuck, ended, listed)
--   Setup:  no list (it is all controls)
local function buildList(tab, deals, entries)
    local list = {}
    if tab == "BUY" then
        local shown = sorted("BUY", UI.dealRows(deals))
        list[#list + 1] = { head = ("DEALS TO BUY NOW (%d)"):format(#deals), caps = capsFor("BUY", CAPS.deal), sortTab = "BUY" }
        for _, it in ipairs(shown) do list[#list + 1] = it end
        if #shown == 0 then
            list[#list + 1] = { note = ahOpen() and "None right now. A sound plays when one appears." or "Open the auction house to look for deals." }
        end
    elseif tab == "SELL" then
        local by = { AH = {}, EITHER = {}, VENDOR = {}, MAIL = {}, HOLD = {} }
        for _, e in ipairs(entries) do
            -- to post, with a vendor as the quicker way out: its own section, so both figures are on the row
            -- (what you farmed or mined is posted like anything else, in the same section: only its
            -- COST differs, "farmed". It is kept apart where the results are added up, not here.)
            local t = by[(e.action == "AH" and e.vendorAlt and not e.farm) and "EITHER" or e.action]
            if t then t[#t + 1] = e end
        end
        -- THE ORDER: what you can act on first (post, sell, collect, add), then
        -- what needs a decision (stuck listings), then what only needs
        -- waiting: SOLD and LISTED, each folded into ONE line by default (a
        -- click on a heading opens or closes its section; that is remembered).
        -- With thirty auctions up, those two used to be most of the list.
        local cfg = AuctionMeshDB.cfg
        cfg.fold = cfg.fold or {}
        local FOLD_DEFAULT = { SOLD = true, LISTED = true }
        local function sect(id, text, caps, items, sum)
            if #items == 0 then return end
            local folded = cfg.fold[id]
            if folded == nil then folded = FOLD_DEFAULT[id] or false end
            list[#list + 1] = { head = ("%s %s (%d)"):format(folded and "[+]" or "[-]", text, #items), caps = (not folded) and capsFor("SELL", caps) or nil,
                                fold = id, folded = folded, sum = folded and sum or nil, sortTab = "SELL" }
            if not folded then for _, it in ipairs(sorted("SELL", items)) do list[#list + 1] = it end end
        end
        sect("AH", "TO POST", CAPS.entry, by.AH)
        sect("EITHER", "POST, OR VENDOR NOW", CAPS.either, by.EITHER)
        sect("VENDOR", "TO SELL TO A VENDOR", CAPS.vendor, by.VENDOR)
        sect("MAIL", "IN THE MAILBOX", CAPS.entry, by.MAIL)
        sect("HOLD", "HELD, PRICE TOO LOW", CAPS.entry, by.HOLD)
        -- what is in your bags that the addon does not track: one click on Add and it is yours to post, as farmed
        sect("LOOSE", "IN YOUR BAGS, NOT TRACKED", CAPS.loose, ns.Seller:Loose(), "press Add on one to sell it")
        local stuck, ok = {}, {}
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
                e.adv = (e.undercut and e.live ~= 0) and ns.Seller:Undercut(e) or nil
                -- (what has sold, and what the auction house no longer lists, is on the Sold tab)
                local t = (not e.sold and e.live ~= 0) and (e.undercut and stuck or ok) or nil
                if t then t[#t + 1] = e end
            end
        end
        do  -- undercut: relist first, and the heading counts each advice
            local nRelist, nHold, nRead = 0, 0, 0
            for _, e in ipairs(stuck) do
                local rec = e.adv and e.adv.rec
                if rec == "relist" then nRelist = nRelist + 1 elseif rec == "hold" then nHold = nHold + 1 else nRead = nRead + 1 end
            end
            table.sort(stuck, function(a, b)
                local ra, rb = (a.adv and a.adv.rec == "relist") and 1 or 2, (b.adv and b.adv.rec == "relist") and 1 or 2
                if ra ~= rb then return ra < rb end
                return a.key < b.key
            end)
            local parts = {}
            if nRelist > 0 then parts[#parts + 1] = GOLD .. "relist " .. nRelist .. "|r" end
            if nHold > 0 then parts[#parts + 1] = GREEN .. "hold " .. nHold .. "|r" end
            if nRead > 0 then parts[#parts + 1] = GREY .. "reading " .. nRead .. "|r" end
            sect("STUCK", "UNDERCUT", { "QTY", "WHY", "", "ADVICE", "P / L" }, stuck, table.concat(parts, GREY .. ", |r"))
        end
        do  -- listed and not undercut: one line (what has SOLD is on its own tab)
            local sum = 0
            local Se, short = ns.Seller, ns.Seller.short
            for _, e in ipairs(ok) do
                local _, _, net = Se:Numbers(e)
                sum = sum + (net or 0) * e.count
            end
            sect("LISTED", "LISTED", CAPS.entry, ok, GREY .. "nobody is cheaper: " .. "|r" .. ORANGE .. "+ " .. short(sum) .. "|r" .. GREY .. " if they sell|r")
        end
        if #list == 0 then list[1] = { note = "Nothing to sell. Items you buy on the Buy tab appear here." } end
    elseif tab == "SOLD" then
        local d = UI.SoldData(entries)
        UI.soldNow = d
        local caps = { "COST", "SOLD AT", "SPREAD", "GOLD ARRIVES", "PROFIT" }
        list[#list + 1] = { head = ("SOLD, GOLD ON ITS WAY (%d)"):format(#d.pending), caps = capsFor("SOLD", caps), sortTab = "SOLD" }
        for _, it in ipairs(sorted("SOLD", d.pending)) do list[#list + 1] = it end
        if #d.pending == 0 then list[#list + 1] = { note = "Nothing sold and waiting to be paid. (The auction house pays out an hour after a sale.)" } end
        if #d.ended > 0 then
            -- no longer on the auction house: sold or run out. The mailbox shows which (and has the gold or the item)
            list[#list + 1] = { head = ("ENDED, CHECK A MAILBOX (%d)"):format(#d.ended), caps = capsFor("SOLD", { "COST", "LISTED AT", "SPREAD", "WHERE", "IF SOLD" }), sortTab = "SOLD" }
            for _, it in ipairs(sorted("SOLD", d.ended)) do list[#list + 1] = it end
        end
        list[#list + 1] = { head = ("PAID, LAST 24 HOURS (%d)"):format(#d.paid), caps = capsFor("SOLD", { "COST", "SOLD AT", "SPREAD", "WHEN", "PROFIT" }), sortTab = "SOLD" }
        for _, it in ipairs(sorted("SOLD", d.paid)) do list[#list + 1] = it end
        if #d.paid == 0 then list[#list + 1] = { note = "No sale collected in the last 24 hours." } end
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
    self.moneyNow = { gold = gold, waiting = waiting, onway = onway, listed = listed, bought = bought, total = gold + waiting + onway + listed + bought }
    local parts = {}
    if held > 0 then parts[#parts + 1] = ("%d held item%s that cost %s (tab Sell)"):format(held, held == 1 and "" or "s", short(heldCost)) end
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

-- How long gold spent on a flip is out of reach: time to sell plus the hour
-- the auction house takes to pay out.
function UI.backIn(d)
    local mins = (d.eta or 0) + 60
    return mins >= 120 and ("%.1f hours"):format(mins / 60) or ("1h %02dm"):format(math.max(0, floor(mins - 60 + 0.5)))
end

-- HOW YOU BUY (More tab, "Buy with"). Buying needs real inputs, and any of
-- these supplies them:
--   wheel   roll the mouse wheel in the snipe box (and anywhere while a deal is up)
--   key     tap a key of your choice; it works anywhere while the Buy tab is open
--   (Holding a key down was a fourth way. The game refuses it: a real log shows
--   every purchase sent from a held key blocked, and each one froze the deal
--   for four seconds. It has been removed.)
--   click   clicks on the snipe box only
-- Clicking the box works in every mode.
--   one     ONE KEY FOR EVERYTHING: the same key as "key", and it also posts.
--           Each press does the next useful thing: buy the deal that is up;
--           with no deal, post the next item in your bags that is ready (at
--           the addon's price, never under what it cost you). It works on the
--           Buy tab and on the Sell tab.
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
        or mode == "key" and (cfg.buyKey and ("Buy with a key: tap %s while the Buy tab is open."):format(cfg.buyKey) or "Buy with a key: now click 'Key' and press the key you want.")
        or mode == "one" and (cfg.buyKey and ("One key: %s buys the deal that is up; with none it posts the next item in your bags. Trades and Sell tabs."):format(cfg.buyKey) or "One key for buying and posting: now click 'Key' and press the key you want.")
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
    self:Notice(("This game does not accept '%s' as an input for buying. Switched to '%s' (More tab, Buy with)."):format(UI.BUY_NAMES[via], UI.BUY_NAMES[to]), true)
    self:Dirty()
end

-- ONE BUY INPUT: a wheel notch, a tap or a repeat of your key, or a click.
-- inBox: it is meant for the snipe box (a wheel notch elsewhere on the panel
-- only counts while a deal is up; otherwise it scrolls the list).
-- Returns true if the input was used for buying.
-- Seconds between your buy inputs, averaged over the LAST SECOND of them
-- (and never fewer than three inputs, while those are under four seconds
-- old). nil when the last input is over 1.5 seconds old or there is only
-- one. A press and its release each count.
-- (It was the average of the last four seconds: pressing faster or slower
-- hardly moved the figure, so it looked stuck.)
function UI.InputEvery()
    local t, now = UI.inputTimes, GetTime()
    if not t or #t < 2 or now - t[#t] > 1.5 then return nil end
    local last, first, n = t[#t], nil, 0
    for i = #t, 1, -1 do
        if now - t[i] > 4 or (n >= 3 and last - t[i] > 1) then break end
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
    if UI.tab == "SELL" and via == "key" and UI.BuyMode() == "one" then return UI.OnePost() end -- the one key, on the Sell tab: it posts
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
--   your key, anywhere, while the Buy tab is open (key mode).
function UI:BindInputs(dealUp, off)
    if not frame then return end
    local cfg = AuctionMeshDB.cfg
    local mode = UI.BuyMode()
    local live = not off and self.tab == "BUY" and frame:IsShown()
    local wantWheel = (live and mode == "wheel" and dealUp) and true or false
    -- the one key is also live on the Sell tab (there it posts)
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

-- THE BIG BUY BUTTON (Buy tab). It never moves and always acts on the best
-- deal, so it can be clicked without looking for a row, and clicked repeatedly.
--   teal    a deal: the first click asks the server for the price
--   green   BUY NOW: the price is in, this click buys (two clicks in all; the
--           game does not let an addon ask for a price without a click)
--   grey    nothing to buy; shows what happened to the last deal for 6 seconds
-- It is also THE SNIPE BOX: keep the mouse in it and keep rolling the wheel.
-- Nothing happens while there is no deal; the first notch after one appears
-- buys it, so the purchase starts within a few hundredths of a second of the
-- deal being found, with no reaction time.
-- THE PACE GAUGE under the snipe box: how fast your inputs come, against the
-- game's lock. Drawn with the panel, and on its own five times a second
-- while inputs are arriving (a text and a marker: no redraw of the panel).
function UI:RenderPace()
    local pg = frame and frame.snipe and rawget(frame.snipe, "pace")
    if not pg then return end
    local every, w = UI.InputEvery(), UI.PaceWindow()
    local zone = UI.PaceZone(every)
    UI.paceState = { every = every, zone = zone, window = w }
    -- short: the figure and the verdict. The target is named only when
    -- you are not on it. (The count of presses in time is kept for the session.)
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

function UI:RenderSnipe(short)
    local sn = frame.snipe
    local S = ns.Sniper
    local show = self.tab == "BUY"
    sn:SetShown(show)
    frame.next:SetShown(self.tab == "SELL")
    -- the "Last: GOT IT ..." line belongs to the snipe box: it was left showing over the other tabs
    if sn.result then sn.result:SetShown(show) end
    if not show then
        self:BindInputs(false, not (self.tab == "SELL" and UI.BuyMode() == "one")) -- the one key stays live on the Sell tab
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
        -- used to be shown here; they are on the Sell tab, whose label counts them.)
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
            text = ORANGE .. ("%d deal%s hidden by your %s minimum profit (best: + %s). Lower it on the More tab.|r"):format(
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
                or "no key chosen yet: More tab, Key"
        elseif mode == "one" then
            how = cfg.buyKey and ("keep tapping " .. cfg.buyKey .. ": it buys the deal that is up; with none it posts what is ready in your bags")
                or "no key chosen yet: More tab, Key"
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
    self:RenderPace()
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

-- More tab: every control shows its current value; then what the engine has learned.
-- THE PICKS TAB. One sentence that says what to do with your inputs right now,
-- the figures behind it, and one button per item.
-- THE CHART TAB, DRAWN (see where its widgets are made, and Gold.lua).
-- x: where the plot begins (the amounts are to its left). cols x colW = w.
UI.GOLD = { x = 64, top = 74, w = 560, h = 180, cols = 140, colW = 4, grid = 6, days = 31, ticks = 9, hover = 35, marks = 6, lines = 5, markShare = 0.02 }
function UI:RenderGold(short)
    local gd, G, C = frame.gold, ns.Gold, UI.GOLD
    -- the range: the one you picked, or (Auto) the shortest that holds everything on record
    local view = self.goldView or G:AutoView()
    for name, b in pairs(gd.views) do
        UI.outline(b, ((self.goldView == nil and name == "auto") or name == self.goldView) and ACCENT or LINE)
    end
    local now, inHand, soldAmt = G:Cash() -- cash: gold in hand plus what has sold (see Gold.lua)
    local L = G:Line(view, C.cols)
    local first, last = L.first or now, L.last or now
    local chg = last - first
    -- less on record than the range asked for: the chart shows what there is, and says since when
    local rangeName = L.short and ("since " .. date((L.span > 20 * 3600) and "%a %H:%M" or "%H:%M", L.from))
        or (G.LINES[view] or G.LINES.d1).name
    local up = chg >= 0
    local RGB = up and { 0.20, 0.90, 0.40 } or { 1.00, 0.25, 0.20 }
    local function signed(c) return ((c >= 0) and (GREEN .. "+ ") or (RED .. "- ")) .. short(math.abs(c)) .. "|r" end
    -- the amount now, and the change over the range with its percentage
    gd.big:SetText("|cffffffff" .. short(now) .. "|r")
    gd.chg:SetText((up and GREEN or RED) .. (up and "+ " or "- ") .. short(math.abs(chg))
        .. ((first > 0) and ("  [%+.2f%%]"):format(chg / first * 100) or "") .. "|r" .. GREY .. "  " .. rangeName .. "|r")
    do  -- under it, in one line: what the figure is made of, and what is not in it yet
        local m = self.moneyNow
        local line = GREY .. "Cash = in hand |r" .. GOLD .. short(inHand) .. "|r" .. GREY .. " + sold |r" .. GREEN .. short(soldAmt) .. "|r"
        if m then
            local tied = {}
            if m.listed > 0 then tied[#tied + 1] = short(m.listed) .. " listed" end
            if m.bought > 0 then tied[#tied + 1] = short(m.bought) .. " in your bags" end
            line = line .. GREY .. "      Not sold yet: |r" .. (#tied > 0 and (ORANGE .. table.concat(tied, ", ") .. "|r") or (GREY .. "nothing|r"))
        end
        gd.sum:SetText(line)
    end
    -- the range drawn: a little room above and below, lines at round amounts
    local lo, hi = math.min(L.lo or now, now), math.max(L.hi or now, now)
    do
        local span = hi - lo
        if span <= 0 then span = math.max(4, floor(hi * 0.04)) end
        lo, hi = math.max(0, lo - span * 0.10), hi + span * 0.12
    end
    local PH = C.h
    local function y(v) return floor((v - lo) / (hi - lo) * (PH - 1) + 0.5) end
    local step = G.AxisStep(lo, hi, 4)
    local gridVals = {}
    do
        local v = math.ceil(lo / step) * step
        for i = 1, C.grid do
            local g = gd.grid[i]
            if v <= hi and y(v) <= PH - 6 then
                gridVals[#gridVals + 1] = v
                g.line:ClearAllPoints()
                g.line:SetPoint("BOTTOMLEFT", gd.plot, "BOTTOMLEFT", 0, y(v))
                g.line:Show()
                g.label:SetText(short(v))
                v = v + step
            else
                g.line:Hide(); g.label:SetText("")
            end
        end
    end
    -- THE LINE, AND THE AREA UNDER IT.
    -- pts[0] is the amount the chart begins with, pts[i] the amount at the end
    -- of column i. With real line segments (see where the widgets are made)
    -- the line runs straight from each point to the next; without them it is
    -- pieced together from blocks.
    local lines = gd.segs ~= nil and not UI.goldNoLines
    local pts = {}
    if L.cols[1] and not L.cols[1].none then pts[0] = first end
    for i = 1, C.cols do
        local c = L.cols[i]
        pts[i] = (c and not c.none) and c.v or nil
    end
    local prev
    for i = 1, C.cols do
        local w, c = gd.cols[i], L.cols[i]
        if not c or c.none then
            w.fill:Hide(); w.line:Hide()
        else
            -- the area: up to the middle of this stretch of line
            local from = pts[i - 1] or c.v
            w.fill:SetHeight(math.max(1, lines and y((from + c.v) / 2) or y(c.v)))
            w.fill:SetColorTexture(RGB[1], RGB[2], RGB[3], 0.22)
            w.fill:Show()
            if lines then
                w.line:Hide()
            else
                -- from the least to the most it was in this stretch, joined to the stretch before
                local a, b2 = math.min(c.lo, prev or c.lo), math.max(c.hi, prev or c.hi)
                local y0, y1 = y(a), y(b2)
                w.line:ClearAllPoints()
                w.line:SetPoint("BOTTOMLEFT", gd.plot, "BOTTOMLEFT", (i - 1) * C.colW, y0)
                w.line:SetHeight(math.max(2, y1 - y0 + 2))
                w.line:SetColorTexture(RGB[1], RGB[2], RGB[3], 1)
                w.line:Show()
            end
            prev = c.v
        end
    end
    if gd.segs then
        local drawn = 0
        local ok = not lines or pcall(function()
            for i = 1, C.cols do
                local sg, a, b2 = gd.segs[i], pts[i - 1], pts[i]
                if a and b2 then
                    sg:SetStartPoint("BOTTOMLEFT", gd.plot, (i - 1) * C.colW, y(a))
                    sg:SetEndPoint("BOTTOMLEFT", gd.plot, i * C.colW, y(b2))
                    sg:SetColorTexture(RGB[1], RGB[2], RGB[3], 1)
                    sg:Show()
                    drawn = drawn + 1
                else
                    sg:Hide()
                end
            end
        end)
        if not lines or not ok then
            for i = 1, C.cols do gd.segs[i]:Hide() end
            if lines then
                -- this client's lines do not work the way they should: blocks from now on, and say so once
                UI.goldNoLines = true
                ns.Log("GOLD CHART: line segments are not usable on this client; the line is drawn in blocks")
                self.dirty = true
            end
        end
        self.goldSegs = drawn
    end
    -- where each day begins, with its date under the stretch it covers
    do
        local bounds = { 1 }
        for _, d in ipairs(L.days) do bounds[#bounds + 1] = d.col end
        bounds[#bounds + 1] = C.cols + 1
        local n = #bounds - 1 -- the days in view
        for i = 1, C.days do
            local w = gd.days[i]
            local from, to = bounds[i], bounds[i + 1]
            if not (from and to) then
                w.line:Hide(); w.label:SetText("")
            else
                local x0, x1 = (from - 1) * C.colW, (to - 1) * C.colW
                w.line:ClearAllPoints()
                w.line:SetPoint("BOTTOMLEFT", gd.plot, "BOTTOMLEFT", x0, 0)
                w.line:SetShown(i > 1)
                local t = (L.cols[math.min(C.cols, from + 1)] or {}).t or L.to
                local wide = x1 - x0
                local text = ""
                if n <= 3 then text = date("%a %d %b", t)
                elseif n <= 8 then text = (wide >= 40) and date("%a %d", t) or ""
                elseif (n - i) % 5 == 0 then text = date("%d %b", t) end
                w.label:ClearAllPoints()
                w.label:SetPoint("TOP", gd.plot, "BOTTOMLEFT", (x0 + x1) / 2, (n <= 3) and -18 or -4)
                w.label:SetText(text)
            end
        end
    end
    do  -- times along the bottom, spaced for the length of what is drawn
        local k = 0
        local span = L.span
        if span <= 60 * 3600 then
            -- the widest spacing that still gives about six marks
            local step = 6 * 3600
            for _, st in ipairs({ 300, 900, 1800, 3600, 3 * 3600 }) do if span / st <= 8 then step = st; break end end
            local unit = math.min(step, 3600)
            local t = math.ceil(L.from / unit) * unit
            while t < L.to and k < C.ticks do
                local h, mi = tonumber(date("%H", t)) or 0, tonumber(date("%M", t)) or 0
                local on
                if step >= 3600 then on = mi == 0 and h % (step / 3600) == 0 and not (h == 0 and #L.days > 0)
                else on = (mi * 60) % step == 0 end
                if on then
                    k = k + 1
                    local lab = gd.ticks[k]
                    lab:ClearAllPoints()
                    lab:SetPoint("TOP", gd.plot, "BOTTOMLEFT", (t - L.from) / span * C.w, -4)
                    lab:SetText(step >= 6 * 3600 and (h == 12 and "12P" or (h < 12 and (h .. "A") or ((h - 12) .. "P"))) or date("%H:%M", t))
                end
                t = t + unit
            end
        end
        for i = k + 1, C.ticks do gd.ticks[i]:SetText("") end
    end
    do  -- the latest amount, in its box at the end of the line
        local yl = y(last)
        local xl = C.w - 3
        gd.dot:ClearAllPoints()
        gd.dot:SetPoint("CENTER", gd.plot, "BOTTOMLEFT", xl, yl)
        local above = yl + 46 <= PH
        gd.call:ClearAllPoints()
        gd.call:SetPoint(above and "BOTTOMRIGHT" or "TOPRIGHT", gd.plot, "BOTTOMLEFT", C.w - 2, above and (yl + 24) or (yl - 24))
        gd.call.text:SetText("|cffffffff" .. short(last) .. "|r")
        gd.stem:ClearAllPoints()
        gd.stem:SetPoint("BOTTOMLEFT", gd.plot, "BOTTOMLEFT", xl, above and yl or (yl - 24))
        gd.stem:SetSize(1, 24)
    end
    -- what moved the gold most, on the line and listed under the chart
    local swings = G:Swings(view, C.lines, C.cols, L.from)
    local used = {}
    -- A MARK ONLY WHERE THE LINE VISIBLY MOVES: a change of at least a
    -- fiftieth of the height drawn. (A real chart had red squares for posting
    -- fees of 4c and 2c on a line at 15g: marks for dips that cannot be seen.)
    -- Smaller changes are still in the list under the chart.
    local minMark = (hi - lo) * UI.GOLD.markShare
    local marked = 0
    for i = 1, C.marks do
        local m, e = gd.marks[i], swings[i]
        if not e or math.abs(e.d) < minMark then
            m:Hide(); m.tip = nil
        else
            marked = marked + 1
            local key = e.col .. (e.d > 0 and "u" or "d")
            local nth = used[key] or 0
            used[key] = nth + 1
            local yy = (e.d > 0) and (y(e.g) + 6 + nth * 12) or (y(e.g) - 17 - nth * 12)
            yy = math.max(1, math.min(PH - 12, yy))
            m:ClearAllPoints()
            m:SetPoint("BOTTOMLEFT", gd.plot, "BOTTOMLEFT", math.max(0, math.min(C.w - 11, (e.col - 1) * C.colW - 4)), yy)
            if e.d > 0 then m.tex:SetColorTexture(0.2, 1, 0.4, 1) else m.tex:SetColorTexture(1, 0.2, 0.2, 1) end
            m.tip = { date("%a %d %b, %H:%M", e.t), signed(e.d), G.Why(e), GREY .. "Cash after it: " .. short(e.g) .. "|r" }
            m:Show()
        end
    end
    do  -- the mouse on the chart: the amount at that time
        local per = C.cols / C.hover
        local byStrip = {}
        for _, e in ipairs(G:Swings(view, 60, C.cols, L.from)) do
            local sidx = math.ceil(e.col / per)
            byStrip[sidx] = byStrip[sidx] or {}
            table.insert(byStrip[sidx], e)
        end
        for i = 1, C.hover do
            local c = L.cols[math.min(C.cols, floor(i * per + 0.5))]
            local tip
            if not c or c.none then
                tip = { date("%a %d %b, %H:%M", c and c.t or L.to), "Nothing on record yet at this time." }
            else
                tip = { date("%a %d %b, %H:%M", c.t), "Cash (in hand + sold): " .. short(c.v), "Since the start of this chart: " .. signed(c.v - first) }
                for k, e in ipairs(byStrip[i] or {}) do
                    if k > 3 then break end
                    tip[#tip + 1] = date("%H:%M", e.t) .. "  " .. signed(e.d) .. "  " .. G.Why(e)
                end
            end
            gd.hover[i].tip = tip
        end
    end
    gd.head:SetText(GREY .. "BIGGEST CHANGES, " .. (L.short and rangeName:upper() or ("LAST " .. rangeName:upper()))
        .. (marked > 0 and "   (the squares on the line mark the ones big enough to see: mouse over one)" or "") .. "|r")
    for i = 1, C.lines do
        local w, e = gd.lines[i], swings[i]
        if e then
            w.label:SetText(GREY .. date("%a %d %b %H:%M", e.t) .. "|r   " .. G.Why(e))
            w.value:SetText(signed(e.d))
        else
            w.label:SetText((i == 1) and (GREY .. "Nothing recorded yet in this range. The line fills in as your gold changes.|r") or "")
            w.value:SetText("")
        end
    end
    self.goldState = { view = view, first = first, last = last, change = chg, up = up, lo = lo, hi = hi, grid = gridVals, swings = swings, line = L,
                       lines = gd.segs ~= nil and not UI.goldNoLines, segs = self.goldSegs, marked = marked }
end

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
            .. ("Run it from the snipe box on the Buy tab. So far on this item: price asked %d time%s, %d bought%s.")
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
    -- today's clock: all of today's sessions, running while one is on
    local live = (se and GetTime() - (se.last or se.at) <= 600) and (GetTime() - (se.last or se.at)) or 0
    parts[2] = ("%sTODAY|r %s%s|r  %d bought  %s"):format(WHITE_C, live > 0 and GOLD or GREY, clockText((t.day.secs or 0) + live), t.day.n, worth(t.day.profit))
    parts[3] = ("%s%d|r  %d bought  %s"):format(WHITE_C, t.year.id, t.year.n, worth(t.year.profit))
    return parts
end

-- WHAT IS BEING SNIPED, in one plain line at the top of the Buy tab: the
-- profit a deal must make to be offered, and the kinds of deal. The figure
-- is the addon's own (it raises and lowers it from how your tries go) unless
-- auto-adjust is off; there is nothing here to set or to work out.
function UI.TargetLine(short)
    local S, cfg = ns.Sniper, AuctionMeshDB.cfg
    if ns.Dormant() then return "" end
    local sk = S:StakeKey()
    if sk then
        local max = S:StakeTerms()
        return GOLD .. "SNIPING FOR|r  " .. WHITE_C .. S.nameOf(sk) .. (max and (" at " .. short(max) .. " or less") or "") .. "|r" .. GREY .. "    one item, by asking its price (stake-out)|r"
    end
    local kinds = (ns.Deals.cfg.flips and not S.lowGold) and "vendor deals and flips" or "vendor deals only"
    local whose = (cfg.tune ~= false) and "the addon sets this figure from your results" or "fixed by you (More, Advanced)"
    return GOLD .. "SNIPING FOR|r  " .. WHITE_C .. "any deal that makes|r " .. GREEN .. "+ " .. short(ns.Deals.cfg.minProfit) .. "|r" .. WHITE_C .. " or more|r"
        .. GREY .. "    " .. kinds .. "    " .. whose .. "|r"
end

-- THE MODE BADGE (top left). What is being bought, and one click to change it.
function UI:RenderMode()
    local b = frame and frame.mode
    if not b then return end
    local S = ns.Sniper
    local sk = S:StakeKey()
    local text, c
    if ns.Dormant() then text, c = "OFF ON THIS CHARACTER", { 0.6, 0.6, 0.6 }
    elseif sk then text, c = "STAKE-OUT: " .. S.nameOf(sk), { 1, 0.82, 0 }
    elseif S.lowGold then text, c = "VENDOR ONLY: GOLD LOW", { 1, 0.5, 0.25 }
    elseif not ns.Deals.cfg.flips then text, c = "VENDOR ONLY", { 0.2, 1, 0.4 }
    else text, c = "VENDOR + FLIPS", ACCENT end
    b:SetText(("|cff%02x%02x%02x%s|r"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5), text))
    UI.outline(b, c)
    self.modeText = text
end
function UI:ModeClick()
    local S = ns.Sniper
    local cfg = AuctionMeshDB.cfg
    if ns.Dormant() then
        -- switched off here (not the bank alt): one click and the addon works
        -- on every character again. The bank alt is remembered: Setup's button
        -- offers it first.
        ns.Do.BankAlt(false)
    elseif S:StakeKey() then
        S:SetStake(nil)
        self:Notice("Stake-out ended. The radar has every request again.", true)
    else
        self:SetVendorOnly(cfg.flips ~= false)
    end
    self:Render()
end

-- Waiting for a key press (Setup, Key) ends when the More tab is left.
function UI:StopKeyCapture()
    if not self.capturingKey then return end
    self.capturingKey = false
    local k = frame and frame.setup and frame.setup.key
    if k and k.EnableKeyboard then k:EnableKeyboard(false) end
end

function UI:RenderSetup()
    local sp, cfg = frame.setup, AuctionMeshDB.cfg
    do  -- the page: Settings, or Advanced
        local pg = (self.morePage == "adv") and "adv" or "basic"
        for name, f in pairs(sp.pages) do f:SetShown(name == pg) end
        sp.title:SetText(GREY .. (pg == "adv" and "ADVANCED: the addon sets and adjusts these by itself. Change one only to overrule it.    "
            or "SETTINGS    ") .. sp.version .. "|r")
    end
    -- your own setting (while gold is low the addon runs on vendor deals only without changing it)
    sp.flips:SetText(AuctionMeshDB.cfg.flips ~= false and (ns.Sniper.lowGold and "Vendor deals + flips (off: low gold)" or "Vendor deals + flips") or "Vendor deals only")
    sp.scope:SetText(ns.Do.SCOPE_NAMES[cfg.scope] or ns.Do.SCOPE_NAMES.mats)
    sp.tied:SetText(("%d%% unsold"):format(floor(ns.Deals.cfg.maxTied * 100 + 0.5)))
    sp.spend:SetText(("%d%% a flip"):format(floor(ns.Deals.cfg.maxSpend * 100 + 0.5)))
    sp.dock:SetText(cfg.dock ~= false and "Inside the auction house" or "A window of its own")
    sp.auto:SetText(cfg.autoOpen and "Opens by itself: on" or "Opens by itself: off")
    do
        local c = cfg.bankAlt and (AuctionMeshDB.chars or {})[cfg.bankAlt]
        sp.bank:SetText(not cfg.bankAlt and "Use on: every character" or ("Only on: " .. (c and c.name or cfg.bankAlt) .. (ns.BankAlt() and " (this one)" or "")))
        UI.outline(sp.bank, ns.BankAlt() and ACCENT or LINE)
    end
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
    if tab == "BUY" or tab == "GOLD" then self:RenderMoney(entries, short) end
    if tab == "HISTORY" then self:RenderSetup() end
    if tab == "PICKS" then self:RenderPicks(short) end
    if tab == "GOLD" then self:RenderGold(short) end

    local todo = 0
    for _, e in ipairs(entries) do if e.action ~= "LISTED" then todo = todo + 1 end end
    frame.tabBuy:SetText(#deals > 0 and ("Buy (%d)"):format(#deals) or "Buy")
    frame.tabSell:SetText(todo > 0 and ("Sell (%d)"):format(todo) or "Sell")
    UI.selectTab(frame.tabBuy, tab == "BUY")
    UI.selectTab(frame.tabSell, tab == "SELL")
    UI.selectTab(frame.tabHist, tab == "HISTORY" or tab == "PICKS")
    UI.selectTab(frame.tabPick, tab == "PICKS")
    UI.selectTab(frame.navBasic, tab == "HISTORY" and (self.morePage or "basic") == "basic")
    UI.selectTab(frame.navAdv, tab == "HISTORY" and self.morePage == "adv")
    UI.selectTab(frame.tabGold, tab == "GOLD")
    UI.selectTab(frame.tabSold, tab == "SOLD")
    do  -- "Sold (4)": auctions that have sold and are waiting to be paid
        local n = 0
        local _, _, _, soldKeys = Se:SalesMoney()
        for _, e in ipairs(entries) do if e.action == "LISTED" and soldKeys[e.key] == true then n = n + 1 end end
        frame.tabSold:SetText(n > 0 and ("Sold (%d)"):format(n) or "Sold")
    end
    do  -- "Picks (1)" when a stake-out is worth a try and none is set
        local P = ns.Picks
        local r = P and P.result
        local pick = r and r.best and not ns.Sniper:StakeKey()
        frame.tabPick:SetText(pick and "Stake-out picks (1)" or "Stake-out picks")
        frame.tabHist:SetText(pick and "More (1)" or "More")
    end

    if tab == "SELL" then frame.next:SetText(TEAL .. "NEXT|r  " .. nextStep(deals, entries, short)) end -- (hidden on the other tabs)
    self:RenderMode()
    if tab == "BUY" then frame.target:SetText(UI.TargetLine(short)) end
    self:RenderSnipe(short)
    if frame.stakeStop then frame.stakeStop:SetShown(tab == "BUY" and ns.Sniper:StakeKey() ~= nil) end
    local status = tab == "BUY" and buyStatus(#deals) or tab == "SELL" and Se:Instructions(entries) or ""
    if tab == "SOLD" then
        local d = UI.SoldData(entries)
        status = GREY .. "On its way: |r" .. GREEN .. "+ " .. short(d.coming) .. "|r"
            .. (d.nextIn and (GREY .. (", the next in %d min"):format(math.max(1, floor(d.nextIn / 60 + 0.5))) .. "|r") or "")
            .. GREY .. "      Profit on what was paid in the last 24 hours: |r" .. ((d.paidSum >= 0) and (GREEN .. "+ ") or (RED .. "- ")) .. short(math.abs(d.paidSum)) .. "|r"
            .. GREY .. "      Click a column's name to sort by it.|r"
    end
    if tab == "SELL" and ns.Dormant() then status = dormantLine() end

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
    UI.holdTick = nil -- (set while the list is drawn, if an undercut auction's hold is counting down)
    local list = buildList(tab, deals, entries)
    local h = frame:GetHeight()
    local vis = type(h) == "number" and h > 0 and math.max(3, math.min(MAXROWS, floor((h - self.listTop - 36) / ROW_H))) or ROWS
    self.vis = vis
    self.scroll = self.scroll or {}
    local off = math.max(0, math.min(self.scroll[tab] or 0, #list - vis))
    self.scroll[tab] = off
    do  -- the scroll bar follows: as long as the list is longer than what fits
        local sb, most = frame.scrollBar, math.max(0, #list - vis)
        sb:SetShown(most > 0)
        if most > 0 then
            self.scrollSetting = true
            if sb.SetMinMaxValues then sb:SetMinMaxValues(0, most) end
            if sb.SetValue then sb:SetValue(off) end
            self.scrollSetting = nil
        end
        self.scrollMost = most
    end
    for i = 1, MAXROWS do
        local r, item = rows[i], (i <= vis) and list[i + off] or nil
        r.item, r.sect, r.looseItem = nil, nil, nil
        r.heat:Hide()
        r.brief:Hide()
        do  -- the item just bought (green) or missed (red): its row is framed for the length of the flash
            local c = item and item.key ~= nil and not item.action and tab == "BUY" and item.key == self.flashKey
                and self.flashUntil and GetTime() < self.flashUntil and UI.FLASH_RGB[self.flashKind]
            for n = 1, 4 do
                if c then r.flash[n]:SetColorTexture(c[1], c[2], c[3], 1) end
                r.flash[n]:SetShown(c and true or false)
            end
            if c then r.heat:SetColorTexture(c[1], c[2], c[3], 0.22); r.heat:Show() end
        end
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
                if item.sum then r.detail:SetText(item.sum); r.detail:Show() end -- (a folded section: what is in it, in one line)
            elseif item.m then
                local age = GetServerTime() - item.t
                r.icon:SetTexture(nil)
                r.name:SetText(GREY .. (age < 90 and (age .. "s ago") or age < 5400 and (floor(age / 60) .. " min ago")
                    or (floor(age / 3600) .. " h ago")) .. "|r")
                for c = 1, 4 do r.c[c]:SetText("") end
                r.state:SetText(""); r.profit:SetText(""); r.btn:Hide()
                r.detail:SetText(item.m)
                r.detail:Show()
            elseif item.loose then
                -- in your bags, not tracked: Add makes it a farmed holding (nothing is posted by that click)
                r.looseItem = item
                r.detail:Hide()
                r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
                local name = ns.Sniper.nameOf(item.key)
                r.name:SetText(GREY .. (item.count > 1 and (name .. " x" .. item.count) or name) .. "|r")
                r.c[1]:SetText(GREY .. item.count .. "|r"); r.c[2]:SetText("")
                r.c[3]:SetText(GREY .. (item.market and short(item.market) or "?") .. "|r"); r.c[4]:SetText("")
                r.state:SetText("")
                r.profit:SetText(GREY .. (item.market and ("about " .. short(floor(item.market * (1 - ns.Deals.cfg.cut)) * item.count)) or "price read on Add") .. "|r")
                r.btn:SetText("Add"); r.btn:Enable(); r.btn:Show()
            elseif item.plainRow then
                r.detail:Hide()
                r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
                r.name:SetText(item.name)
                for c = 1, 4 do r.c[c]:SetText(item.cells[c] or "") end
                r.state:SetText(""); r.profit:SetText(item.profit or ""); r.btn:Hide()
            elseif item.ghost then
                -- a deal that is over: its row for the length of the flash, with what happened
                r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
                r.name:SetText(ns.Sniper.nameOf(item.key))
                for c = 1, 4 do r.c[c]:SetText("") end
                r.state:SetText(""); r.profit:SetText(""); r.btn:Hide()
                r.detail:SetText((item.ghost == "won" and GREEN or RED) .. tostring(item.text or (item.ghost == "won" and "BOUGHT" or "MISSED")) .. "|r")
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
        local invested, back, any, farmed = 0, 0, false, 0
        for _, e in ipairs(entries) do
            local paid, _, net = Se:Numbers(e)
            if e.farm then
                -- farmed or mined, in your bags or listed: all of it is profit, counted apart from what you bought
                if e.action ~= "HOLD" then farmed = farmed + (net or 0) * e.count end
            elseif paid and e.action ~= "LISTED" then invested, back, any = invested + paid * e.count, back + net * e.count, true end
        end
        if farmed > 0 then parts[#parts + 1] = ("Farmed: %s+ %s|r"):format(GREEN, short(farmed)) end
        if any then
            local profit = back - invested
            parts[#parts + 1] = ("Bought, to sell: paid %s, %s%s%s|r"):format(short(invested),
                profit >= 0 and GREEN or RED, profit >= 0 and "+ " or "- ", short(math.abs(profit)))
        end
    elseif tab ~= "GOLD" and tab ~= "SOLD" then
        parts[#parts + 1] = GREY .. ns.Learn:Summary() .. "|r"
    end
    if #list > vis then
        parts[#parts + 1] = ("%srows %d-%d of %d (mouse wheel)|r"):format(GREY, off + 1, math.min(#list, off + vis), #list)
    end
    -- (the Buy tab has no button at the bottom right: its footer may use the whole width)
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("BOTTOMLEFT", 14, 12)
    frame.footer:SetPoint("BOTTOMRIGHT", tab == "BUY" and -14 or -230, 12)
    frame.footer:SetText(table.concat(parts, tab == "BUY" and (GREY .. "   |   |r") or "    "))

    do  -- "Post next" only when there is something to post
        local toPost = false
        for _, e in ipairs(entries) do if e.action == "AH" then toPost = true end end
        frame.post:SetShown(tab == "SELL" and ahOpen() and toPost)
        self.postShown = tab == "SELL" and ahOpen() and toPost
    end
    do  -- vendor sales always need your click
        local nv, gain = 0, 0
        for _, e in ipairs(entries) do
            if e.action == "VENDOR" then nv = nv + 1; gain = gain + (e.f.sell or 0) * e.count end
        end
        local vendShown = tab == "SELL" and merchantOpen() and nv > 0 and not ahOpen()
        frame.vend:SetShown(vendShown)
        frame.vend:SetText(("Sell all to vendor  +%s"):format((short(gain):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
        if tab ~= "BUY" then
            -- the footer is only as narrow as the button next to it needs (it was always cut short for the widest one)
            frame.footer:ClearAllPoints()
            frame.footer:SetPoint("BOTTOMLEFT", 14, 12)
            frame.footer:SetPoint("BOTTOMRIGHT", vendShown and -230 or self.postShown and -116 or -14, 12)
        end
    end
end

---------------------------------------------------------------- clicks

local function rowButton(self)
    local loose = rawget(self:GetParent(), "looseItem")
    if loose then
        -- "Add": what is in your bags becomes a farmed holding, to post (nothing is posted by this click)
        local n = ns.Seller:Farm(loose.key)
        if n > 0 then
            UI:Notice(("Added %d x %s as farmed or mined: it cost nothing, so what it sells for is all profit. %s"):format(n, ns.Sniper.nameOf(loose.key),
                ahOpen() and "Its price is being read: press Post on its row." or "Open the auction house to post it."), true)
        end
        return UI:Dirty()
    end
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
    local loose = rawget(self, "looseItem")
    if loose then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetItemByID(loose.key)
        GameTooltip:AddLine(GREY .. "In your bags, not bought by the addon. Add: it is tracked as farmed or mined (cost nothing) and can be posted like anything else. Nothing is posted by that click.|r", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
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
        GameTooltip:AddLine(GREY .. "Shift + right-click: stop tracking this item|r")
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

-- Which column of a row the mouse is on: 1 to 4 for the four value columns,
-- 5 for the profit column at the right, 0 for the name. nil if the game does
-- not say where the mouse is.
function UI.ColumnAt(row)
    if not (GetCursorPosition and row.GetLeft and row.GetEffectiveScale) then return nil end
    local cx = GetCursorPosition()
    local left, scale = row:GetLeft(), row:GetEffectiveScale()
    if type(cx) ~= "number" or type(left) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
    local x = cx / scale - left
    if x >= COLS[5][1] + COLS[5][2] then return 5 end -- right of the last value column: the profit column
    for n = 5, 2, -1 do
        if x >= COLS[n][1] then return n - 1 end
    end
    return 0
end

local function rowMouseUp(self, button)
    if GetCursorInfo() then return ns.Seller.AcceptDrop() end
    -- Shift + right-click on a row of the Sell tab: stop tracking that item
    -- (something added by mistake, or that you want to keep). A plain click
    -- does nothing, so a stray one removes nothing. (This was a button in the
    -- Details sidebar, which is gone.)
    do  -- A CLICK ON A HEADING ROW. On a column's caption: sort by that column.
        -- On the heading's name: open or close the section (Sell tab), or put
        -- the usual order back (Buy, Sold).
        local sect = rawget(self, "sect")
        if sect and (sect.fold or sect.sortTab) then
            local col = UI.ColumnAt(self)
            if col and col > 0 and sect.sortTab and sect.caps then return UI:SortBy(sect.sortTab, col) end
            if sect.fold then
                local cfg = AuctionMeshDB.cfg
                cfg.fold = cfg.fold or {}
                cfg.fold[sect.fold] = not sect.folded
                return UI:Render()
            end
            if sect.sortTab then return UI:SortBy(sect.sortTab, 0) end
        end
    end
    local item = rawget(self, "item")
    if item and item.key and item.action and button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
        local name = ns.Sniper.nameOf(item.key)
        ns.Seller:Untrack(item.key)
        UI:Notice("Stopped tracking " .. name .. ". It is still yours: it shows under 'in your bags' again, and nothing was sold.", true)
        UI:Render()
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
UI.FLASH_RGB = FLASH_RGB
function UI:Flash(kind, key, text)
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
    -- THE ITEM'S OWN ROW says it too: under DEALS TO BUY NOW the row of the
    -- item is framed in the same colour. A deal that is over has no row any
    -- more, so for the length of the flash it keeps one, where it was, with
    -- what happened written in it (see dealRows).
    self.flashKey, self.flashRow = key, nil
    if key then
        local at = 1
        for i, d in ipairs(self.lastDeals or {}) do if d.key == key then at = i end end
        self.flashRow = { ghost = kind, key = key, at = at, text = text }
    end
end

-- The rows under DEALS TO BUY NOW: the deals, and for the length of a flash
-- the row of the deal that was just bought or missed, if it is no longer one.
-- For the eye only: nothing is ever bought from this list (purchases go by
-- the deals themselves).
local function dealRows(deals)
    local g = UI.flashRow
    if not (g and UI.flashUntil and GetTime() < UI.flashUntil) then return deals end
    for _, d in ipairs(deals) do if d.key == g.key then return deals end end
    local out = {}
    for i, d in ipairs(deals) do out[i] = d end
    table.insert(out, math.min(g.at, #out + 1), g)
    return out
end
UI.dealRows = dealRows

-- DEAL ROWS ARE COLOURED BY PROFIT, in copper: the more a deal makes, the
-- stronger its row. { from this profit, row tint, tint strength, text colour }
UI.HEAT = {
    { 10000, { 1.00, 0.80, 0.15 }, 0.32, "|cffffd633" }, -- 1g and more: gold
    { 2500,  { 0.15, 0.95, 0.40 }, 0.26, "|cff40ff70" }, -- 25s and more: bright green
    { 500,   { 0.15, 0.95, 0.40 }, 0.11, "|cff33d95c" }, -- 5s and more: green
    { 0,     nil,                  0,    "|cff8fae96" }, -- less: plain, greyed green
}
function UI.Heat(profit)
    for i, h in ipairs(UI.HEAT) do if (profit or 0) >= h[1] then return h, i end end
    return UI.HEAT[#UI.HEAT], #UI.HEAT
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

-- THE HEADER, measured. From the left: the mode badge, then four tabs. From
-- the right: the close button (floating only), Dock / Pop out (floating: only
-- while the auction house is open), Snapshot, Refresh. The narrowest panel is
-- the floating one (WIDTH), with Dock shown: the sizes below leave a gap
-- there, and UI.HeaderRoom works it out so the test can hold it to that.
-- (In 3.47 Refresh was added without this sum, and lay over the More tab.)
-- (3.54: four tabs, Trades, Bags, Gold, More, and one button on the right,
-- Refresh. Snapshot and Dock are on the More tab, where they also were; the
-- engine bar is gone: the Buy tab's status line says what the radar does.)
-- (3.63: Buy, Sell, Sold, Chart, More)
local HDR = { tabX = 178, tabW = { 56, 62, 62, 54, 62 }, tabGap = 4, close = 34, edge = 12, refresh = 56 }
UI.HDR = HDR
-- pixels between the last tab and the Refresh button
function UI.HeaderRoom(width, floating)
    local tabsRight = HDR.tabX + (#HDR.tabW - 1) * HDR.tabGap
    for _, w in ipairs(HDR.tabW) do tabsRight = tabsRight + w end
    return width - (floating and HDR.close or HDR.edge) - HDR.refresh - tabsRight
end
local function makeTab(parent, n, text, onClick)
    return button(parent, HDR.tabW[n], text, onClick)
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
    -- bought right now, in colour. A click changes it (no trip to the More tab).
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
    frame.tabBuy = makeTab(frame, 1, "Buy", function() UI:StopKeyCapture(); UI.tab = "BUY"; UI:Render() end)
    frame.tabSell = makeTab(frame, 2, "Sell", function() UI:StopKeyCapture(); UI.tab = "SELL"; UI:Render() end)
    frame.tabSold = makeTab(frame, 3, "Sold", function() UI:StopKeyCapture(); UI.tab = "SOLD"; UI:Render() end)
    frame.tabGold = makeTab(frame, 4, "Chart", function() UI:StopKeyCapture(); UI.tab = "GOLD"; UI:Render() end)
    frame.tabHist = makeTab(frame, 5, "More", function() UI:StopKeyCapture(); UI.tab = "HISTORY"; UI.morePage = "basic"; UI:Render() end)
    frame.tabSell:SetPoint("LEFT", frame.tabBuy, "RIGHT", HDR.tabGap, 0)
    frame.tabSold:SetPoint("LEFT", frame.tabSell, "RIGHT", HDR.tabGap, 0)
    frame.tabGold:SetPoint("LEFT", frame.tabSold, "RIGHT", HDR.tabGap, 0)
    frame.tabHist:SetPoint("LEFT", frame.tabGold, "RIGHT", HDR.tabGap, 0)
    -- MORE has three pages, picked on a row of its own under the tabs:
    -- Settings, Advanced, and the stake-out picks (which used to be a tab).
    do
        local nav = CreateFrame("Frame", nil, frame)
        nav:SetPoint("TOPLEFT", 14, -40); nav:SetPoint("TOPRIGHT", -14, -40)
        nav:SetHeight(22)
        frame.navBasic = button(nav, 90, "Settings", function() UI:StopKeyCapture(); UI.tab = "HISTORY"; UI.morePage = "basic"; UI:Render() end)
        frame.navBasic:SetPoint("TOPLEFT", 0, 0)
        frame.navAdv = button(nav, 90, "Advanced", function() UI:StopKeyCapture(); UI.tab = "HISTORY"; UI.morePage = "adv"; UI:Render() end)
        frame.navAdv:SetPoint("LEFT", frame.navBasic, "RIGHT", 4, 0)
        frame.tabPick = button(nav, 130, "Stake-out picks", function() UI:StopKeyCapture(); UI.tab = "PICKS"; UI:Render() end)
        frame.tabPick:SetPoint("LEFT", frame.navAdv, "RIGHT", 4, 0)
        nav:Hide()
        frame.moreNav = nav
    end

    -- REFRESH: reads your bags (and the open mailbox) again and redraws everything
    frame.refresh = button(frame, HDR.refresh, "Refresh", function() UI:Refresh() end)
    frame.refresh:SetHeight(18)
    frame.refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Refresh", 1, 1, 1)
        GameTooltip:AddLine("For when the lists do not match what you hold. Counts your bags again (and the mailbox, if it is open), tracks again anything the addon had given up on as not found that is in your bags after all, and redraws the panel. Nothing is bought, posted or sold.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    sn:SetPoint("TOPLEFT", 12, -184); sn:SetPoint("TOPRIGHT", -12, -184)
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
    -- shown on the Buy tab only while a stake-out is set: one click ends it
    frame.stakeStop = button(frame, 120, "Stop stake-out", function()
        ns.Sniper:SetStake(nil)
        UI:Notice("Stake-out ended. The radar has every request again.", true)
        UI:Render()
    end)
    frame.stakeStop:SetHeight(18)
    frame.stakeStop:SetPoint("TOPRIGHT", frame.status, "TOPRIGHT", 0, 3)
    outline(frame.stakeStop, { 1, 0.82, 0 })
    frame.stakeStop:Hide()

    -- THE FRONT OF THE TRADES TAB, above the snipe box:
    --   1. WHAT IS BEING SNIPED: the profit a deal must make to be offered.
    --      The addon sets and adjusts that figure itself; it is said here in
    --      plain words so there is nothing to work out.
    --   2. YOUR MONEY, broken down: gold in hand, what has sold (in the
    --      mailbox, on its way), what is listed, what is in your bags, and the
    --      total. (3.54 folded this into one line with the breakdown behind
    --      the mouse. It is back as it was: it was the part that was liked.)
    frame.target = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.target:SetPoint("TOPLEFT", 14, -42); frame.target:SetPoint("TOPRIGHT", -14, -42)
    frame.target:SetJustifyH("LEFT"); frame.target:SetWordWrap(false)
    frame.target:Hide()

    local lg = CreateFrame("Frame", nil, frame)
    lg:SetPoint("TOPLEFT", 14, -62); lg:SetPoint("TOPRIGHT", -14, -62)
    lg:SetHeight(116)
    lg.rows = {}
    for i = 1, 5 do lg.rows[i] = ledgerRow(lg, -(i - 1) * 15) end
    lg.rule = lg:CreateTexture(nil, "ARTWORK")
    lg.rule:SetPoint("TOPLEFT", 0, -77); lg.rule:SetPoint("TOPRIGHT", 0, -77); lg.rule:SetHeight(1)
    lg.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    lg.total = ledgerRow(lg, -83, "GameFontHighlight")
    lg.note = lg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lg.note:SetPoint("TOPLEFT", 0, -102); lg.note:SetPoint("TOPRIGHT", 0, -102)
    lg.note:SetJustifyH("LEFT"); lg.note:SetWordWrap(false)
    lg:Hide()
    frame.ledger = lg

    -- SETUP tab: a control for everything that can be changed (no commands
    -- to remember), then what the request engine has learned.
    local sp = CreateFrame("Frame", nil, frame)
    sp:SetPoint("TOPLEFT", 14, -86); sp:SetPoint("TOPRIGHT", -14, -86)
    sp:SetHeight(384)
    -- TWO PAGES. "Settings": the few things you set once (how you buy, where
    -- the panel lives, your bank alt, what to send to Claude). "Advanced":
    -- the figures the addon works out and adjusts by itself (the smallest
    -- profit, the flip margin, the money limits, what the radar reads), for
    -- when you want to overrule it. Each control is made on the page it
    -- belongs to; `cur` is the page being filled.
    sp.pages = { basic = CreateFrame("Frame", nil, sp), adv = CreateFrame("Frame", nil, sp) }
    for _, pg in pairs(sp.pages) do pg:SetAllPoints(sp) end
    local cur, curName = sp.pages.adv, "adv"
    sp.title = heading(sp, 0, "")
    sp.version = ("(AuctionMesh version " .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AuctionMesh", "Version") or "?") .. ")")
    local function setting(y, text)
        local l = cur:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
        local e = CreateFrame("EditBox", nil, cur, "InputBoxTemplate")
        e:SetSize(w, 20)
        e:SetAutoFocus(false)
        if numeric then e:SetNumeric(true) end
        e:SetMaxLetters(letters)
        if suffix then
            local s = cur:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    local ROW, HEAD = 26, 15 -- (26: the buttons are 22 high and used to touch the row below)
    local yy = -28
    local ys = { basic = -28, adv = -28 }
    local function page(name)
        ys[curName] = yy
        cur, curName, yy = sp.pages[name], name, ys[name]
    end
    local function group(text)
        yy = yy - 4
        heading(cur, yy, text)
        yy = yy - HEAD
    end
    local function row(text)
        local l = setting(yy, text)
        local at = yy
        yy = yy - ROW
        return l, at
    end

    page("adv")
    group("DEALS: WORKED OUT BY THE ADDON (change one only to overrule it)")
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
    sp.flips = tip(button(cur, 190, "", function() UI:SetVendorOnly(AuctionMeshDB.cfg.flips ~= false) end),
        "Vendor deals are guaranteed profit: the item is listed for less than a vendor pays. Flips are resold on the auction house and are not guaranteed.")
    sp.flips:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.flips)

    L, at = row("Most of your money in unsold auctions, and in one flip")
    sp.spend = tip(button(cur, 92, "", function() ns.Do.MaxSpend() end),
        "The most of the gold you hold that ONE flip may take. Click to change: 35%, 50%, 75%, 100%. At 100% the first big pile can take everything you hold; nothing more can be bought until it sells and pays out.")
    sp.spend:SetPoint("TOPRIGHT", 0, at + 5)
    sp.tied = tip(button(cur, 92, "", function() ns.Do.MaxTied() end),
        "The most of your money that may sit in auctions that have NOT SOLD yet. Gold from auctions that have sold is on its way and does not count. A small flip (15% of the gold in hand) is always allowed. Click to change: 30%, 50%, 70%, 100%.")
    sp.tied:SetPoint("RIGHT", sp.spend, "LEFT", -6, 0)
    upTo(L, sp.tied)

    page("basic")
    group("BUYING")
    L, at = row("Buy with")
    sp.buy = tip(button(cur, 190, "", function() UI:SetBuyMode() end),
        "Click to change.\nMouse wheel: put the mouse in the snipe box and roll.\nA key, tap it: pick a key below; tapping it buys, anywhere, while the Buy tab is open.\nOne key, buys and posts: the same key; with no deal up, each press posts the next item in your bags that is ready, at the addon's price. Trades and Sell tabs.\nClicks only: click the snipe box.\nClicking the box works in every mode.")
    sp.buy:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.buy)

    L, at = row("Key (for 'A key: tap it')")
    sp.key = tip(button(cur, 190, "", function(self)
        -- click, then press the key you want (Esc cancels; a mouse side button works too)
        UI.capturingKey = not UI.capturingKey
        if self.EnableKeyboard then self:EnableKeyboard(UI.capturingKey and true or false) end
        UI:Dirty()
    end), "Click, then press the key you want to buy with. A modifier can be held with it (Shift, Ctrl, Alt). Mouse side buttons work too. While the Buy tab is open that key buys instead of doing what it normally does; everywhere else it is untouched.")
    sp.key:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.key)
    local function gotKey(name)
        local cfg = AuctionMeshDB.cfg
        UI.capturingKey = false
        if sp.key.EnableKeyboard then sp.key:EnableKeyboard(false) end
        if name then
            cfg.buyKey = name
            if cfg.buyBlocked then cfg.buyBlocked.key = nil end
            UI:Notice(("Buy key set to %s. It buys while the Buy tab is open (Buy with: A key, tap it; or One key, which also posts)."):format(name), true)
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

    page("adv")
    group("WATCHING")
    L, at = row("Radar reads")
    sp.scope = tip(button(cur, 250, "", function() ns.Do.Scope() end),
        "Click to change. Crafting materials are read about every second whatever is chosen; a wider setting adds the other categories, each every 30 seconds.")
    sp.scope:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.scope)

    L, at = row("Look for flips only on")
    sp.focus = tip(button(cur, 250, "", function() ns.Do.FocusMode() end),
        "Click to change.\nOff: every material is watched.\nPrime items: the addon picks the items measured to sell fastest with the most gold moving, and re-reads each one about once a minute. Your own watch list is included.\nMy own list: only items you added in the drawer or with a settings code.\nVendor-price deals are always shown, whatever is chosen.")
    sp.focus:SetPoint("TOPRIGHT", 0, at + 5)
    upTo(L, sp.focus)

    group("A CODE FROM CLAUDE")
    L, at = row("Import: paste what Claude sent")
    sp.apply = tip(button(cur, 50, "Apply", function()
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

    page("basic")
    group("SEND TO CLAUDE")
    L, at = row("When something looks wrong")
    local log = tip(button(cur, 60, "Log", function() ns.Diag:Show() end), "Everything the addon did this session, step by step. Send it when something looks wrong.")
    log:SetPoint("TOPRIGHT", 0, at + 5)
    sp.report = tip(button(cur, 100, "Daily report", function() ns.Do.Report() end),
        "The long version, once a day: what sold, what was found and missed, which items move the most gold.")
    sp.report:SetPoint("RIGHT", log, "LEFT", -6, 0)
    sp.snap = tip(button(cur, 90, "Snapshot", function() ns.Do.Snapshot() end),
        "The short version, any time: gold, mailbox, auctions, settings and the last snipes. The same as the Snapshot button at the top.")
    sp.snap:SetPoint("RIGHT", sp.report, "LEFT", -6, 0)
    outline(sp.snap, ACCENT)
    upTo(L, sp.snap)

    group("ADDON")
    L, at = row("Panel / bank alt")
    sp.dock = tip(button(cur, 190, "", function() ns.Do.Dock(AuctionMeshDB.cfg.dock == false) end),
        "Inside the auction house window, or as a window of its own that you can drag anywhere.")
    sp.dock:SetPoint("TOPRIGHT", 0, at + 5)
    sp.auto = tip(button(cur, 150, "", function() ns.Do.Auto(not AuctionMeshDB.cfg.autoOpen) end),
        "On: the panel opens and starts reading prices when you open the auction house. Off: click the AuctionMesh tab under the auction house window.")
    sp.auto:SetPoint("RIGHT", sp.dock, "LEFT", -6, 0)
    sp.bank = tip(button(cur, 190, "", function() ns.Do.BankAlt() end),
        "Your bank alt: the one character the addon is for. Click to pick: every character, then each of your characters in turn (the one picked last comes first). With a bank alt set, the addon works on that character and is switched off on all the others: it opens nowhere by itself and nothing runs. Kept for the whole account. A character is on the list once it has logged in with the addon.")
    sp.bank:SetPoint("RIGHT", sp.auto, "LEFT", -6, 0)
    upTo(L, sp.bank)

    page("adv")
    group("AUTO-ADJUST")
    L, at = row("Auto-adjust (pace, smallest profit, quiet time)")
    sp.forget = tip(button(cur, 190, "Forget what was learned", function()
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
    sp.tune = tip(button(cur, 150, "", function() ns.Do.Tuning(not ns.Tuner.cfg.enabled) end),
        "On: the pace of requests, the flip profit bar, the smallest profit and the radar's quiet time adjust themselves from results, and each change is listed below. Off: nothing changes by itself.")
    sp.tune:SetPoint("RIGHT", sp.forget, "LEFT", -6, 0)
    upTo(L, sp.tune)

    -- three lines of what the addon is doing by itself
    yy = yy - 6
    sp.rows = {}
    for i = 1, 3 do sp.rows[i] = ledgerRow(cur, yy - (i - 1) * 14, nil, 170) end
    page("basic") -- (both pages' ends are known now)
    sp.bottom = math.min(ys.basic, ys.adv - 2 * 14 - 12) - 46 -- where the longer page ends (the pages start 46 lower than the tab once did), for the layout test
    sp:Hide()
    frame.setup = sp

    -- THE CHART TAB: your gold as a line with the area under it filled, the way
    -- a market chart is drawn on television. The amount now in large figures
    -- with the change over the range next to it (green up, red down), the
    -- amounts down the left with a line across for each, a divider where each
    -- day begins with its date under it, and a box on the latest amount. The
    -- biggest single changes are marked on the line; the mouse over a mark
    -- says what it was. Recorded by Gold.lua; nothing here sends a request.
    do
        local C = UI.GOLD
        local gd = CreateFrame("Frame", nil, frame)
        gd:SetPoint("TOPLEFT", 14, -40); gd:SetPoint("TOPRIGHT", -14, -40)
        gd:SetHeight(430)
        gd.big = gd:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        gd.big:SetPoint("TOPLEFT", 0, -2); gd.big:SetJustifyH("LEFT")
        gd.chg = gd:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        gd.chg:SetPoint("LEFT", gd.big, "RIGHT", 14, 0); gd.chg:SetJustifyH("LEFT"); gd.chg:SetWordWrap(false)
        gd.sum = gd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gd.sum:SetPoint("TOPLEFT", 0, -27); gd.sum:SetPoint("TOPRIGHT", 0, -27)
        gd.sum:SetJustifyH("LEFT"); gd.sum:SetWordWrap(false)
        -- THE RANGE, on a row of its own under the two lines of figures: Auto
        -- (the range grows with what is on record), hours (1, 3, 6, 12) and
        -- days (1, 2, 7, 30).
        gd.views = {}
        local prev
        local function rangeButton(id, label, w)
            local bt = button(gd, w, label, function() UI.goldView = (id ~= "auto") and id or nil; UI:Render() end)
            bt:SetHeight(20)
            if prev then bt:SetPoint("LEFT", prev, "RIGHT", 3, 0) else bt:SetPoint("TOPLEFT", C.x, -47) end
            gd.views[id] = bt
            prev = bt
        end
        rangeButton("auto", "Auto", 46)
        for _, id in ipairs(ns.Gold.ORDER) do rangeButton(id, ns.Gold.LINES[id].short, 38) end
        gd.chg:SetPoint("RIGHT", gd, "RIGHT", 0, 0)
        -- the plot
        local plot = CreateFrame("Frame", nil, gd)
        plot:SetPoint("TOPLEFT", C.x, -C.top); plot:SetSize(C.w, C.h)
        local bg = plot:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.09, 0.20, 0.85)
        gd.plot = plot
        -- the amounts down the left, each with a line across
        gd.grid = {}
        for i = 1, C.grid do
            local ln = plot:CreateTexture(nil, "BORDER")
            ln:SetSize(C.w, 1); ln:SetColorTexture(1, 1, 1, 0.10)
            local lab = gd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lab:SetPoint("RIGHT", ln, "LEFT", -6, 0); lab:SetJustifyH("RIGHT")
            gd.grid[i] = { line = ln, label = lab }
        end
        -- the line and the area under it: one column of each
        gd.cols = {}
        for i = 1, C.cols do
            local fill = plot:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("BOTTOMLEFT", (i - 1) * C.colW, 0); fill:SetSize(C.colW, 1)
            local line = plot:CreateTexture(nil, "OVERLAY")
            line:SetSize(C.colW, 2)
            gd.cols[i] = { fill = fill, line = line }
        end
        -- THE LINE ITSELF: real line segments (the game's Line object), one from
        -- each point to the next, so the line slopes between amounts instead
        -- of going up and down in blocks. If this client cannot make them, the
        -- line is drawn from the columns' own pieces as before.
        if type(plot.CreateLine) == "function" then
            local segs, good = {}, true
            for i = 1, C.cols do
                local ok, ln = pcall(plot.CreateLine, plot, nil, "OVERLAY")
                if not ok or type(ln) ~= "table" then good = false; break end
                if ln.SetThickness then ln:SetThickness(2) end
                ln:Hide()
                segs[i] = ln
            end
            if good then gd.segs = segs end
        end
        -- where each day begins, and its date
        gd.days = {}
        for i = 1, C.days do
            local dv = plot:CreateTexture(nil, "OVERLAY")
            dv:SetSize(1, C.h); dv:SetColorTexture(0.6, 0.75, 1, 0.45)
            local lab = gd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lab:SetJustifyH("CENTER")
            gd.days[i] = { line = dv, label = lab }
        end
        -- times of day along the bottom (the 2-day view)
        gd.ticks = {}
        for i = 1, C.ticks do
            local lab = gd:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            lab:SetJustifyH("CENTER")
            gd.ticks[i] = lab
        end
        -- the latest amount, in a box on the line's end
        local call = CreateFrame("Frame", nil, plot)
        call:SetSize(84, 20)
        local cbg = call:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints(); cbg:SetColorTexture(0.10, 0.22, 0.45, 1)
        outline(call, { 0.6, 0.8, 1 })
        call.text = call:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        call.text:SetPoint("CENTER")
        gd.call = call
        gd.dot = plot:CreateTexture(nil, "OVERLAY")
        gd.dot:SetSize(6, 6); gd.dot:SetColorTexture(1, 1, 1, 1)
        gd.stem = plot:CreateTexture(nil, "OVERLAY")
        gd.stem:SetColorTexture(0.6, 0.8, 1, 0.9)
        local function tipOf(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for i, l in ipairs(self.tip) do
                if i == 1 then GameTooltip:AddLine(l, 1, 1, 1) else GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
            end
            GameTooltip:Show()
        end
        local function tipOff() GameTooltip:Hide() end
        -- the mouse anywhere on the chart: the amount at that time
        gd.hover = {}
        local hw = C.w / C.hover
        for i = 1, C.hover do
            local h = CreateFrame("Frame", nil, plot)
            h:SetPoint("BOTTOMLEFT", (i - 1) * hw, 0); h:SetSize(hw, C.h)
            h:EnableMouse(true)
            h:SetScript("OnEnter", tipOf); h:SetScript("OnLeave", tipOff)
            gd.hover[i] = h
        end
        -- the biggest changes, marked with a small diamond: the mouse over one says what it was.
        -- (They were 11-pixel squares. The diamond is a 6-pixel square turned on its corner; the
        -- area that answers the mouse stays a little larger than what is drawn.)
        gd.marks = {}
        for i = 1, C.marks do
            local m = CreateFrame("Button", nil, plot)
            m:SetSize(11, 11)
            m.edge = m:CreateTexture(nil, "ARTWORK")
            m.edge:SetSize(8, 8); m.edge:SetPoint("CENTER")
            m.edge:SetColorTexture(0, 0, 0, 0.9)
            m.tex = m:CreateTexture(nil, "OVERLAY")
            m.tex:SetSize(6, 6); m.tex:SetPoint("CENTER")
            if m.tex.SetRotation then m.tex:SetRotation(math.pi / 4); m.edge:SetRotation(math.pi / 4) end
            m:SetScript("OnEnter", tipOf); m:SetScript("OnLeave", tipOff)
            do  -- above the hover strips, so that the mouse reaches the mark
                local lv = plot.GetFrameLevel and plot:GetFrameLevel()
                if type(lv) == "number" and m.SetFrameLevel then m:SetFrameLevel(lv + 5) end
            end
            m:Hide()
            gd.marks[i] = m
        end
        -- the same changes as a list, largest first
        gd.head = gd:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gd.head:SetPoint("TOPLEFT", 0, -C.top - C.h - 40)
        gd.lines = {}
        for i = 1, C.lines do
            local y = -C.top - C.h - 56 - (i - 1) * 15
            local l = gd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l:SetPoint("TOPLEFT", 0, y)
            l:SetWidth(C.x + C.w - 100); l:SetJustifyH("LEFT"); l:SetWordWrap(false)
            local v = gd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            v:SetPoint("TOPRIGHT", gd, "TOPLEFT", C.x + C.w, y)
            v:SetJustifyH("RIGHT"); v:SetWordWrap(false)
            gd.lines[i] = { label = l, value = v }
        end
        gd:Hide()
        frame.gold = gd
    end

    -- THE PICKS TAB: which item, if any, is worth a stake-out. Everything on
    -- it is worked out from deals the radar has already seen (see Picks.lua):
    -- it sends nothing to the auction house and waits while you are sniping.
    local pk = CreateFrame("Frame", nil, frame)
    pk:SetPoint("TOPLEFT", 14, -86); pk:SetPoint("TOPRIGHT", -14, -86)
    pk:SetHeight(384)
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
        -- a deal's row is tinted by its profit; the row of the item just bought or missed is tinted and framed
        r.heat = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.heat:SetAllPoints()
        r.heat:Hide()
        r.flash = {}
        for n = 1, 4 do r.flash[n] = r:CreateTexture(nil, "OVERLAY"); r.flash[n]:Hide() end
        r.flash[1]:SetPoint("TOPLEFT"); r.flash[1]:SetPoint("TOPRIGHT"); r.flash[1]:SetHeight(2)
        r.flash[2]:SetPoint("BOTTOMLEFT"); r.flash[2]:SetPoint("BOTTOMRIGHT"); r.flash[2]:SetHeight(2)
        r.flash[3]:SetPoint("TOPLEFT"); r.flash[3]:SetPoint("BOTTOMLEFT"); r.flash[3]:SetWidth(2)
        r.flash[4]:SetPoint("TOPRIGHT"); r.flash[4]:SetPoint("BOTTOMRIGHT"); r.flash[4]:SetWidth(2)
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
        -- an undercut auction's row: why the advice is what it is, across the COST and MARKET columns
        r.brief = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.brief:SetPoint("LEFT", COLS[3][1], 0)
        r.brief:SetWidth(COLS[5][1] - COLS[3][1] - 8); r.brief:SetJustifyH("LEFT"); r.brief:SetWordWrap(false)
        r.brief:Hide()
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

    -- THE SCROLL BAR of the list, at its right edge: drag it, or roll the
    -- wheel over the list as before. Shown only when the list is longer than
    -- the panel.
    do
        local sb = CreateFrame("Slider", nil, frame)
        sb:SetWidth(10)
        if sb.SetOrientation then sb:SetOrientation("VERTICAL") end
        local bg = sb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.06)
        local thumb = sb:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(10, 36); thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
        if sb.SetThumbTexture then sb:SetThumbTexture(thumb) end
        sb.thumb = thumb
        if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
        if sb.SetValueStep then sb:SetValueStep(1) end
        if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(true) end
        sb:SetScript("OnValueChanged", function(_, v)
            if UI.scrollSetting or type(v) ~= "number" then return end -- (the redraw itself moving the bar)
            UI.scroll = UI.scroll or {}
            local to = floor(v + 0.5)
            if UI.scroll[UI.tab] ~= to then UI.scroll[UI.tab] = to; UI:Render() end
        end)
        sb:Hide()
        frame.scrollBar = sb
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
        do  -- the session clock in the footer: once a second, the footer's text only
            local sec = floor(GetTime())
            if UI.tab == "BUY" and ns.Sniper.session and sec ~= UI.clockSec and not UI.dirty then
                UI.clockSec = sec
                frame.footer:SetText(table.concat(UI.TradesFooter(ns.Seller.short), GREY .. "   |   |r"))
            end
        end
        do  -- the pace gauge follows your inputs: its own text, five times a second while they arrive
            local t = UI.inputTimes
            if UI.tab == "BUY" and t and t[#t] and GetTime() - t[#t] < 2 then UI:RenderPace() end
        end
        do  -- a hold counting down on the Sell tab: redrawn once a second while one is shown
            local sec = floor(GetTime())
            if UI.tab == "SELL" and UI.holdTick and sec ~= UI.holdSec then UI.holdSec = sec; UI.dirty = true end
        end
        if UI.flashUntil and GetTime() >= UI.flashUntil then
            UI.flashUntil, UI.flashKind = nil, nil
            for _, t in ipairs(rawget(frame, "flashEdges") or {}) do t:Hide() end
            if UI.flashKey then UI.flashKey, UI.flashRow, UI.dirty = nil, nil, true end -- the row's frame goes with it
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
    frame:Hide()
end

-- Where things sit depends on the tab.
--   Trades: MONEY on top, then the NEXT line, the timers, the list
--   Bags:   the NEXT line, what to do, the list
--   Setup:  one status line under the heading, then the settings
local LAYOUT = {
    BUY = { next = -188, status = -266, statusH = 38, top = 310 }, -- (the pace gauge sits between the snipe box's lines and the status)
    SELL = { next = -40, status = -58, statusH = 38, top = 104 },
    HISTORY = { status = -66, statusH = 14, top = 480 },
    PICKS = { status = -66, statusH = 14, top = 480 },
    GOLD = { status = -55, statusH = 14, top = 480 },
    SOLD = { status = -44, statusH = 14, top = 64 },
}
function UI:Layout()
    local tab = self.tab
    local L = LAYOUT[tab]
    self.listTop = L.top
    if self.layoutKey == tab then return end
    self.layoutKey = tab
    frame.ledger:SetShown(tab == "BUY")
    frame.target:SetShown(tab == "BUY")
    frame.setup:SetShown(tab == "HISTORY")
    frame.picks:SetShown(tab == "PICKS")
    frame.gold:SetShown(tab == "GOLD")
    frame.moreNav:SetShown(tab == "HISTORY" or tab == "PICKS")
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
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -L.top - (i - 1) * ROW_H)
    end
    frame.scrollBar:ClearAllPoints()
    frame.scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -L.top)
    frame.scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 36)
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
    if dock then
        -- Inside the auction house: no title or close button of our own.
        frame:SetParent(ah)
        frame:SetScale(1)
        frame:SetPoint("TOPLEFT", ah, "TOPLEFT", 3, -22)
        frame:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -3, 3)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(false)
        frame.closeBtn:Hide()
        frame.tabBuy:SetPoint("TOPLEFT", HDR.tabX, -8)
        frame.refresh:ClearAllPoints(); frame.refresh:SetPoint("TOPRIGHT", -HDR.edge, -6)
    else
        frame:SetParent(UIParent)
        frame:SetScale(0.9)
        frame:SetSize(WIDTH, FLOAT_H)
        frame:SetFrameStrata("HIGH")
        frame:SetMovable(true)
        frame.closeBtn:Show()
        frame.tabBuy:SetPoint("TOPLEFT", HDR.tabX, -8)
        frame.refresh:ClearAllPoints(); frame.refresh:SetPoint("TOPRIGHT", -HDR.close, -6)
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
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED", "MAIL_CLOSED", "PLAYER_MONEY" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "AUCTION_HOUSE_SHOW" and ns.Dormant() then
            -- switched off on this character: no tab under the auction house, and the panel stays closed
        elseif event == "AUCTION_HOUSE_SHOW" then
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
