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
-- BUY tab: only deals verified against live listings, with the exact
-- quantity and total you will pay. SELL tab: everything you bought, what you
-- paid, what it sells for, and the one thing to do with it.
-- Rendering is throttled (5x per second, only while shown and only if changed).
local _, ns = ...
ns = ns or {}

local UI = {}
ns.UI = UI

local floor, min = math.floor, math.min
local ROWS, ROW_H, WIDTH = 8, 38, 520
UI.tab = "BUY"

local GREEN, GOLD, BLUE, RED, GREY, ORANGE = "|cff33ff66", "|cffffd100", "|cff4d99ff", "|cffff4040", "|cffaaaaaa", "|cffff8040"

local frame, rows = nil, {}

local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function mailOpen() return MailFrame and MailFrame:IsShown() end

function UI:Dirty() self.dirty = true end

-- Shows the latest message at the top of the window for 10 seconds.
function UI:Notice(text)
    self.notice = { text = text, till = GetTime() + 10 }
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

local function fillBuy(r, d, short)
    local S = ns.Sniper
    local units, total = S.NextBuy(d)
    r.name:SetText(S.nameOf(d.key))
    r.state:SetText("")
    local each = d.units > 0 and d.profit / d.units or 0
    if d.kind == "VENDOR" then
        r.detail:SetText(("%sSAFE|r  Buy %d for %s, vendor pays %s"):format(GREEN, units, short(total), short(d.sell * units)))
        r.profit:SetText(GREEN .. "+" .. short(each * units) .. "|r")
    else
        local proof = d.sold and ("buyers paid %s"):format(short(d.sold)) or ("%d listed at %s+"):format(d.depth or 0, short(d.wall or 0))
        if d.partial then proof = proof .. (", %d cheap left"):format(d.partial) end
        r.detail:SetText(("%sFLIP|r  Buy %d for %s, relist at %s %s(%s)|r"):format(
            GOLD, units, short(total), short(d.sell), GREY, proof))
        r.profit:SetText(GREEN .. "+" .. short(d.profit) .. "|r")
    end
    local b = S.buying
    if b and b.key == d.key then
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
        local est = (e.f.kind == "FLIP" and not live) and (GREY .. " (planned)|r") or ""
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
        lines[1] = ORANGE .. "Paused while your mouse is on the game's auction window.|r"
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
        lines[#lines + 1] = fresh < total and ("%sPrice scan running: %d of %d categories.|r"):format(GREY, fresh, total)
            or ("%sNext price scan in %s. Watching %d materials, full round about every %s.|r"):format(GREY, clock(left),
                q and #q or 0, clock(math.max(15, (q and #q or 0) * 1.3)))
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------- render

function UI:Render()
    self.dirty = false
    if not frame or not frame:IsShown() then return end
    local Se, short = ns.Seller, ns.Seller.short
    local deals, entries = buyRows(), Se:Entries()
    frame.gold:SetText("Gold: " .. short(GetMoney()))
    frame.tabBuy:SetText(("BUY (%d)"):format(#deals))
    frame.tabSell:SetText(("SELL (%d)"):format(#entries))
    frame.tabBuy:SetEnabled(self.tab ~= "BUY")
    frame.tabSell:SetEnabled(self.tab ~= "SELL")

    local list = self.tab == "BUY" and deals or entries
    if self.tab == "BUY" then
        local total = 0
        for _, d in ipairs(deals) do total = total + d.profit end
        frame.headline:SetText(#deals > 0
            and ("%sMAKE NOW: +%s|r  %s(%d deal%s)|r"):format(GREEN, short(total), GREY, #deals, #deals == 1 and "" or "s")
            or (GREY .. "MAKE NOW: nothing yet|r"))
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
    local status = self.tab == "BUY" and buyStatus(#deals) or Se:Instructions(entries)
    local n = self.notice
    if n and GetTime() < n.till then
        status = n.text
    elseif self.tab == "SELL" and ahOpen() and ns.Gate:UserBusy() then
        status = ORANGE .. "Paused while your mouse is on the game's auction window.|r " .. status
    end
    frame.status:SetText(status)
    for i = 1, ROWS do
        local r, item = rows[i], list[i]
        r.item = item
        if not item then r:Hide() else
            r.icon:SetTexture(C_Item.GetItemIconByID(item.key) or 134400)
            if self.tab == "BUY" then fillBuy(r, item, short) else fillSell(r, item, short) end
            r:Show()
        end
    end
    local more = #list > ROWS and ("  +" .. (#list - ROWS) .. " more") or ""

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
    frame.footer:SetText(text .. more)
    frame.post:SetShown(self.tab == "SELL" and ahOpen())
    frame.flips:SetText(ns.Deals.cfg.flips and "Mode: Vendor + Flips" or "Mode: Vendor only")
    frame.flips:SetShown(self.tab == "BUY")
end

---------------------------------------------------------------- clicks

local function rowButton(self)
    local item = self:GetParent().item
    if not item then return end
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
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(item.key)
    if UI.tab == "SELL" then
        local p = ns.Seller.prices[item.key]
        if p and p.price then
            local qty = ns.Seller:PostQty(item.key, p)
            GameTooltip:AddLine(("%sPosts %d at %s each, deposit %s|r"):format(GOLD, qty,
                ns.Seller.short(p.price), ns.Seller.short((p.depEach or 0) * qty)))
        elseif p and p.hold then
            GameTooltip:AddLine(RED .. p.hold .. "|r")
        end
        if item.f.proof then GameTooltip:AddLine(GREEN .. "Purchase confirmed: " .. item.f.proof .. "|r") end
        GameTooltip:AddLine(GREY .. "Right-click: remove from this list|r")
    else
        local d = item
        if d.kind == "FLIP" then
            GameTooltip:AddLine(("%sLive market: %d units listed from %s. Deposit to relist: %s.|r"):format(GREY,
                d.depth or 0, ns.Seller.short(d.wall or 0), ns.Seller.short(d.deposit or 0)))
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

local function button(parent, w, text, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function UI:Create()
    if frame then return end
    frame = CreateFrame("Frame", "AuctionMeshFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 154 + ROWS * ROW_H)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, rel, x, y = f:GetPoint()
        AuctionMeshDB.cfg.pos = { point, rel, x, y }
    end)
    frame:SetScript("OnReceiveDrag", function() ns.Seller.AcceptDrop() end)
    frame:SetScript("OnMouseUp", function() if GetCursorInfo() then ns.Seller.AcceptDrop() end end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("AuctionMesh")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    frame.gold = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.gold:SetPoint("TOPRIGHT", -34, -12)

    frame.tabBuy = button(frame, 110, "BUY", function() UI.tab = "BUY"; UI:Render() end)
    frame.tabBuy:SetPoint("TOPLEFT", 10, -34)
    frame.tabSell = button(frame, 110, "SELL", function() UI.tab = "SELL"; UI:Render() end)
    frame.tabSell:SetPoint("LEFT", frame.tabBuy, "RIGHT", 6, 0)
    -- Minimum profit per deal: anything that makes less is never shown.
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", frame.tabSell, "RIGHT", 14, 0)
    lbl:SetText("Min profit per deal:")
    local function box(anchor, x, suffix)
        local e = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        e:SetSize(30, 20)
        e:SetPoint("LEFT", anchor, "RIGHT", x, 0)
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
    local sLabel
    frame.minS, sLabel = box(lbl, 8, "|cffc7c7cfs|r")
    frame.minC = box(sLabel, 6, "|cffeda55fc|r")
    local log = button(frame, 50, "Log", function() ns.Diag:Show() end)
    log:SetPoint("TOPRIGHT", -10, -34)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- The one number that matters, big.
    frame.headline = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.headline:SetPoint("TOPLEFT", 12, -62)
    frame.headline:SetWidth(WIDTH - 24)
    frame.headline:SetJustifyH("LEFT")
    frame.status:SetPoint("TOPLEFT", 12, -90)
    frame.status:SetWidth(WIDTH - 24)
    frame.status:SetHeight(40)
    frame.status:SetJustifyH("LEFT"); frame.status:SetJustifyV("TOP")

    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetSize(WIDTH - 20, ROW_H - 2)
        r:SetPoint("TOPLEFT", 10, -134 - (i - 1) * ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.07)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 3, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", 40, -4)
        r.name:SetWidth(210); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.state:SetPoint("TOPLEFT", 252, -5)
        r.state:SetWidth(170); r.state:SetJustifyH("LEFT"); r.state:SetWordWrap(false)
        r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail:SetPoint("BOTTOMLEFT", 40, 4)
        r.detail:SetWidth(WIDTH - 20 - 40 - 170); r.detail:SetJustifyH("LEFT"); r.detail:SetWordWrap(false)
        r.profit = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        r.profit:SetPoint("RIGHT", -78, 0)
        r.profit:SetWidth(96); r.profit:SetJustifyH("RIGHT"); r.profit:SetWordWrap(false)
        r.btn = button(r, 68, "Buy", rowButton)
        r.btn:SetPoint("RIGHT", -4, 0)
        r:EnableMouse(true)
        r:SetScript("OnEnter", rowEnter)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnMouseUp", rowMouseUp)
        r:Hide()
        rows[i] = r
    end

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 12, 13)
    frame.footer:SetJustifyH("LEFT")
    frame.post = button(frame, 96, "Post next", function() ns.Seller:PostNext() end, "AuctionMeshPostButton")
    frame.post:SetPoint("BOTTOMRIGHT", -10, 8)
    frame.flips = button(frame, 160, "Mode: Vendor + Flips", function() UI:SetVendorOnly(ns.Deals.cfg.flips) end)
    frame.flips:SetPoint("BOTTOMRIGHT", -10, 8)

    -- Throttled redraw: at most 5 per second, and only when something changed.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        if UI.notice and GetTime() >= UI.notice.till then UI.notice = nil; UI.dirty = true end
        local paused = ns.Gate:UserBusy()
        if paused ~= UI.wasPaused then UI.wasPaused = paused; UI.dirty = true end
        -- Timers tick while the BUY tab is open at the auction house.
        if UI.tab == "BUY" and ahOpen() then UI.dirty = true end
        if UI.dirty then UI:Render() end
    end)
    frame:Hide()
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
    self:Notice(("Minimum profit per deal: %s. Smaller deals are not shown."):format(ns.Seller.short(copper)))
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
        or "|cffffd100Vendor + Flips mode:|r also shows auction house resale deals (not guaranteed).")
    ns.Print(self.notice.text)
    self:Dirty()
end

function UI:Open(tab)
    self:Create()
    if tab then self.tab = tab end
    local mp = ns.Deals.cfg.minProfit
    if not frame.minS:HasFocus() and not frame.minC:HasFocus() then
        frame.minS:SetText(tostring(math.floor(mp / 100)))
        frame.minC:SetText(tostring(mp % 100))
    end
    if not frame:IsShown() then
        frame:ClearAllPoints()
        local pos = AuctionMeshDB.cfg.pos
        if ahOpen() and not pos then
            frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
        elseif pos then
            frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            frame:SetPoint("CENTER", 250, 0)
        end
        frame:Show()
    end
    self:Render()
end

function UI:Toggle()
    self:Create()
    if frame:IsShown() then frame:Hide() else self:Open() end
end

function UI:IsShown() return frame and frame:IsShown() end

function UI:Init()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED", "MAIL_CLOSED", "PLAYER_MONEY" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "AUCTION_HOUSE_SHOW" then
            if AuctionMeshDB.cfg.autoOpen then
                -- Things to post? Start on SELL so they go up first.
                local toPost = false
                for _, e in ipairs(ns.Seller:Entries()) do if e.action == "AH" then toPost = true end end
                UI:Open(toPost and "SELL" or "BUY")
            end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if frame and frame:IsShown() and #ns.Seller:Entries() == 0 then frame:Hide() end
            UI:Dirty()
        else
            UI:Dirty()
        end
    end)
end

return UI
