-- AuctionMesh Diag: shareable debug log + one gate for every auction house request.
--
-- Log
--   Every C_AuctionHouse call (ours AND the Blizzard AH window's), every AH
--   error / throttle event, and what AuctionMesh was trying to do, with
--   millisecond timestamps. Starts empty on every /reload or login (last 800
--   lines kept; the previous session is available with /amesh log old).
--   /amesh log  opens a window: Ctrl+A, Ctrl+C, paste it to Claude.
--
-- Gate
--   The AH server handles one request at a time. All AuctionMesh requests
--   (searches, browse pages, posts, purchases) go through Gate:Ready()/Use():
--     * waits until the client says the AH is ready AND the server has answered
--       our previous request (THROTTLED_MESSAGE_SENT / RESPONSE_RECEIVED)
--     * keeps a minimum spacing between requests (0.6s to start)
--     * on "Internal auction error" or a dropped message: pause 5s and widen
--       the spacing (up to 3s); it relaxes again after a minute without errors.
local ADDON, ns = ...
ns = ns or {}

local Diag = {}
ns.Diag = Diag

local MAX_LINES = 800
local buf, n = {}, 0 -- in-memory ring, flushed to SavedVariables on logout

local function stamp()
    local t = GetTime and GetTime() or 0
    return ("%s %.3f"):format(date and date("%H:%M:%S") or "", t)
end

function ns.Log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    n = n + 1
    buf[n] = stamp() .. "  " .. line
    if n > MAX_LINES * 1.25 then
        local keep = {}
        for i = n - MAX_LINES + 1, n do keep[#keep + 1] = buf[i] end
        buf, n = keep, #keep
    end
end
local Log = ns.Log

-- Compact description of API arguments (itemKeys, item locations, query tables).
local function describe(v, depth)
    local t = type(v)
    if t == "table" then
        if v.itemID then
            return ("key{%s/%s/%s/%s}"):format(v.itemID, v.itemLevel or 0, v.itemSuffix or 0, v.battlePetSpeciesID or 0)
        end
        if v.GetBagAndSlot then
            local ok, b, s = pcall(v.GetBagAndSlot, v)
            return ok and ("loc{%s:%s}"):format(tostring(b), tostring(s)) or "loc{?}"
        end
        if (depth or 0) > 1 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. describe(x, (depth or 0) + 1)
            if #parts >= 6 then parts[#parts + 1] = "..."; break end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function args(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = describe((select(i, ...))) end
    return table.concat(out, ", ")
end

---------------------------------------------------------------- the gate

-- MEASURED LIMIT (from real logs of this client): the auction house takes one
-- request at a time. The server answers in ~0.15s, then the client stays locked
-- for ~0.5s more and fires AUCTION_HOUSE_THROTTLED_SYSTEM_READY. Floor: one
-- request per ~0.62s (about 1.6 a second), whatever the request is (category
-- sweep, item search, next page, price quote, post).
-- So: no extra spacing of our own (it only wastes budget), and the next
-- request is sent from the READY event itself instead of from a polling timer.
local Gate = { interval = 0.05, nextAt = 0, outstanding = 0, changedAt = 0, lastError = 0, errors = 0, sentCount = 0 }
ns.Gate = Gate

-- True when background work must stay silent: the AuctionMesh panel is not
-- open, the mouse is on one of its Buy/Post buttons, or the game's own UI sent
-- an auction request in the last 8s. Moving the mouse over the auction house
-- window does NOT pause anything.
local BLIZZ = { "ItemSellFrame", "CommoditiesSellFrame", "ItemBuyFrame", "CommoditiesBuyFrame", "WoWTokenSellFrame" }
function Gate:UserBusy()
    if GetTime() < (self.userUntil or 0) then return true end
    local hb = ns.UI and ns.UI.hoverBtn
    if hb and hb.IsShown and hb:IsShown() and hb:IsMouseOver() then return true end
    local ah = AuctionHouseFrame
    if type(ah) ~= "table" or not (ah.IsShown and ah:IsShown()) then return false end
    -- AuctionMesh only works while its own panel is open. On the game's own
    -- auction screens it sends nothing, so it never changes what the game shows you.
    if not (ns.UI and ns.UI:IsShown()) then return true end
    if ns.UI.docked then return false end
    -- Separate-window mode: stay quiet while one of the game's sell/buy dialogs is up.
    for _, name in ipairs(BLIZZ) do
        local f = rawget(ah, name)
        if type(f) == "table" and f.IsShown and f:IsShown() then return true end
    end
    return false
end

function Gate:Ready()
    local now = GetTime()
    if self:UserBusy() then return false end
    -- Safety: if the server never confirmed, don't wait forever.
    if self.outstanding > 0 and now - self.changedAt > 5 then self.outstanding = 0 end
    if self.errors > 0 and now - self.lastError > 60 then
        self.errors, self.interval = 0, 0.05
        Log("GATE relaxed: back to the client's own pace")
    end
    return now >= self.nextAt and self.outstanding <= 0 and C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- Your own clicks (Buy, Confirm, Post) don't wait for the background spacing:
-- they only need the server to be ready and no error back-off in progress.
-- Background scanning then waits its turn behind the click.
function Gate:ReadyForUser()
    local now = GetTime()
    if self.outstanding > 0 and now - self.changedAt > 5 then self.outstanding = 0 end
    return now >= (self.penaltyUntil or 0) and C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- Call right before sending a request.
function Gate:Use(what)
    self.nextAt = GetTime() + self.interval
    self.usedAt = GetTime()
    Log("SEND %s", what)
end

function Gate:Penalize(why)
    local now = GetTime()
    self.errors, self.lastError = self.errors + 1, now
    self.interval = math.min(3, math.max(0.6, self.interval * 1.5))
    self.nextAt = now + 5
    self.penaltyUntil = now + 2
    Log("GATE backoff (%s): pause 5s, spacing now %.2fs", why, self.interval)
end

---------------------------------------------------------------- hooks & events

local HOOKED = {
    "SendSearchQuery", "SendSellSearchQuery", "SendBrowseQuery", "RequestMoreBrowseResults",
    "RefreshCommoditySearchResults", "RefreshItemSearchResults", "RequestMoreItemSearchResults",
    "RequestMoreCommoditySearchResults", "ReplicateItems", "PostItem", "PostCommodity",
    "ConfirmPostItem", "ConfirmPostCommodity", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase",
    "CancelCommoditiesPurchase", "PlaceBid", "CancelAuction", "QueryOwnedAuctions", "QueryBids",
}

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "UI_ERROR_MESSAGE", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_SHOW_NOTIFICATION", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "REPLICATE_ITEM_LIST_UPDATE", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN", "AUCTION_HOUSE_PURCHASE_COMPLETED", "OWNED_AUCTIONS_UPDATED", "PLAYER_MONEY", "BIDS_UPDATED",
}

local function isAHError(msg)
    if not msg then return false end
    msg = tostring(msg)
    return (ERR_AUCTION_DATABASE_ERROR and msg == ERR_AUCTION_DATABASE_ERROR)
        or msg:lower():find("auction") ~= nil
end

local function onEvent(_, event, ...)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        -- The lock just opened: send the next request this very frame.
        if ns.OnAHReady then ns.OnAHReady() end
        return -- too frequent to be worth a log line each
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
        Gate.sentCount, Gate.sawSent = Gate.sentCount + 1, true
        Gate.outstanding, Gate.changedAt = Gate.outstanding + 1, GetTime()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
        Gate.outstanding, Gate.changedAt = math.max(0, Gate.outstanding - 1), GetTime()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        Gate.outstanding, Gate.changedAt = math.max(0, Gate.outstanding - 1), GetTime()
        Gate:Penalize("message dropped")
    elseif event == "UI_ERROR_MESSAGE" then
        local _, msg = ...
        if not isAHError(msg) and not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
        if isAHError(msg) then Gate:Penalize(tostring(msg)) end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and GetTime() < (Gate.ignoreErrorUntil or 0) then
        -- follows our own cancelled purchase: log it, no back-off
    elseif event == "PLAYER_MONEY" then
        if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
        Log("MONEY now %d", GetMoney())
        return
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        Gate:Penalize("show error " .. tostring((...)))
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and (...) ~= ADDON then
        return
    end
    -- Search result events are frequent: log them briefly.
    Log("EVENT %s(%s) outstanding=%d", event, args(...), Gate.outstanding)
end

function Diag:Init()
    AuctionMeshDB.log = AuctionMeshDB.log or {}
    -- Every /reload or login starts an empty log. The previous session is kept
    -- aside (not shown) and can be opened with /amesh log old.
    AuctionMeshDB.logPrev = AuctionMeshDB.log
    AuctionMeshDB.log = {}
    buf, n = {}, 0
    local _, build, _, toc = GetBuildInfo()
    Log("==== session start: AuctionMesh %s, build %s, interface %s, realm %s, copperValues=%s, step=%s",
        C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
        tostring(build), tostring(toc), tostring(GetRealmName and GetRealmName()),
        tostring(C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues()),
        tostring(ns.Deals and ns.Deals.cfg.step))
    if ns.historyNote then Log(ns.historyNote) end
    for _, name in ipairs(HOOKED) do
        if C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, function(...)
                local ours = (Gate.usedAt == GetTime()) or name:find("^Cancel") or name:find("^Confirm")
                if not ours then Gate.userUntil = GetTime() + 8 end
                Log("CALL %s(%s) ready=%s%s", name, args(...), tostring(C_AuctionHouse.IsThrottledMessageSystemReady()),
                    ours and "" or "  [you / game UI: background paused 8s]")
            end)
        end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", onEvent)
end

function Diag:Save()
    local out = {}
    for i = math.max(1, n - MAX_LINES + 1), n do out[#out + 1] = buf[i] end
    AuctionMeshDB.log = out
end

function Diag:Text(previous)
    if previous then return table.concat(AuctionMeshDB.logPrev or {}, "\n") end
    local from = math.max(1, n - MAX_LINES + 1)
    return table.concat(buf, "\n", from, n)
end

function Diag:Clear()
    buf, n = {}, 0
    Log("==== log cleared")
end

---------------------------------------------------------------- copy window

local win
function Diag:Show(previous)
    if not win then
        win = CreateFrame("Frame", "AuctionMeshLogFrame", UIParent, "BackdropTemplate")
        win:SetSize(720, 460)
        win:SetPoint("CENTER")
        win:SetFrameStrata("DIALOG")
        win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        win:SetBackdropColor(0, 0, 0, 0.95)
        win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("AuctionMesh log: click in the box, Ctrl+A then Ctrl+C, and paste it to Claude")
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", "AuctionMeshLogScroll", win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -32)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
        edit:SetWidth(670)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() win:Hide() end)
        scroll:SetScrollChild(edit)
        win.edit = edit
        local sel = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        sel:SetSize(110, 22); sel:SetPoint("BOTTOMLEFT", 10, 10); sel:SetText("Select all")
        sel:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
        local clr = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        clr:SetSize(110, 22); clr:SetPoint("LEFT", sel, "RIGHT", 8, 0); clr:SetText("Clear log")
        clr:SetScript("OnClick", function() Diag:Clear(); edit:SetText(Diag:Text()) end)
    end
    win.edit:SetText(self:Text(previous))
    win:Show()
    win.edit:SetFocus()
    win.edit:HighlightText()
end

return Diag
