-- WHO GETS THE AUCTION HOUSE'S REQUEST SLOTS. The real addon is loaded against
-- a fake client that models the game's lock as measured in real logs: one
-- request at a time, the answer 0.15s after it is sent, the lock open again
-- 0.5s after that (one request per 0.65s), a request made while locked is
-- queued by the game and sent when the lock opens.
--
-- What is checked: the radar reads back to back, armed or not; nothing that
-- is not sniping takes more than its small share; an alert is checked at the
-- next unlock; a standing listing that is not a deal is not checked again
-- and again; flips can be bought straight from the radar long after arming.
--
-- Run: lua5.1 tests/pace_test.lua            (all scenarios)
--      lua5.1 tests/pace_test.lua armed      (one scenario, with its request log if TRACE=seconds is set)
local SCEN = arg[1]
local ALL = { "armed", "unarmed", "money", "bags", "alert", "flip", "lost" }

if not SCEN then
    local pass, fail = 0, 0
    local lua = arg[-1] or "lua5.1"
    for _, name in ipairs(ALL) do
        local p = io.popen(("%s %s %s 2>&1"):format(lua, arg[0], name))
        local out = p:read("*a")
        p:close()
        io.write(out)
        local a, b = out:match("(%d+) passed, (%d+) failed")
        if a then pass, fail = pass + tonumber(a), fail + tonumber(b) else fail = fail + 1; print("  FAIL scenario " .. name .. " did not finish") end
    end
    print(("\n%d passed, %d failed"):format(pass, fail))
    os.exit(fail == 0 and 0 or 1)
end

local ANSWER, LOCK, FPS = 0.15, 0.50, 60
local T, gold, timers, frames, chat = 100, 5000000, {}, {}, {}
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
local seq = 0
local function addTimer(t) seq = seq + 1; t.seq = seq; timers[#timers + 1] = t end
local function advance(s)
    local stop = T + s
    while T < stop - 1e-9 do
        T = T + 1 / FPS
        local due = timers; timers = {}
        table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
        for _, t in ipairs(due) do
            if t.at <= T then
                if not t.cancelled then t.fn(); if t.every and not t.cancelled then t.at = t.at + t.every; if t.at <= T then t.at = T + t.every end; addTimer(t) end end
            else timers[#timers + 1] = t end
        end
        for i = 1, #frames do local f = frames[i]; if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1 / FPS) end end
    end
end
C_Timer = {
    After = function(s, fn) addTimer({ at = T + s, fn = fn }) end,
    NewTicker = function(s, fn) local t = { at = T + s, fn = fn, every = s }; t.Cancel = function() t.cancelled = true end; addTimer(t); return t end,
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
hooksecurefunc = function(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
    end
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = strip(m) end }
SlashCmdList = {}
UIParent = widget(); GameTooltip = widget()
AuctionHouseFrame = widget(); AuctionHouseFrame:Hide()
MerchantFrame = widget(); MerchantFrame:Hide()
MailFrame = widget(); MailFrame:Hide()
Enum = { AuctionHouseSortOrder = { Price = 1 }, SendAddonMessageResult = { Success = 0 } }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() return 0 end }
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "c" end }
ItemLocation = { CreateFromBagAndSlot = function() return {} end }
GetCursorInfo = function() end

-- THE WORLD: 400 crafting materials (class 7) and four side classes with 20 items each.
-- Every item: lowest price 1000-1096, 500 listed, a vendor pays 10.
local ITEMCLASS = {}
for i = 1, 400 do ITEMCLASS[10000 + i] = 7 end
for _, c in ipairs({ 5, 0, 3, 8 }) do for i = 1, 20 do ITEMCLASS[c * 1000 + 20000 + i] = c end end
C_Item = {
    GetItemInfo = function(k) local c = ITEMCLASS[k]; if c then return "Item" .. k, nil, 1, 1, 1, "", "", 200, "", 1, 10, c, 1 end end,
    GetItemInfoInstant = function(k) return k, "", "", "", 1, ITEMCLASS[k] or 7, 1 end,
    GetItemIconByID = function() return 1 end,
}
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
GetInboxNumItems = function() return 0, 0 end
TakeInboxMoney = function() end

local radarPrice, radarQty = {}, {}   -- what the radar shows for an item when it is not the default
local listing = {}                    -- item -> rows { price, qty } when not the default
local function base(id) return 1000 + id % 97 end
local function rowsOf(id)
    if listing[id] then return listing[id] end
    local b = base(id)
    return { { b, 50 }, { b + 5, 200 }, { b + 9, 250 } }
end

-- THE LOCK
local locked, queue, log = false, {}, {}
local dropNext                       -- name pattern of a request whose answer is lost once
local curBrowse
local skipNext                       -- name pattern of a request the game does not transmit at all, once
local function send(name, onAnswer)
    if skipNext and name:find(skipNext) then skipNext = nil; log[#log + 1] = { t = T, name = "(not transmitted) " .. name }; return end
    local function go()
        locked = true
        log[#log + 1] = { t = T, name = name }
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
        local lost = dropNext and name:find(dropNext)
        if lost then dropNext = nil end
        C_Timer.After(ANSWER, function()
            fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
            if onAnswer and not lost then onAnswer() end
        end)
        C_Timer.After(ANSWER + LOCK, function()
            locked = false
            if #queue > 0 then local q = table.remove(queue, 1); q() else fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
        end)
    end
    if locked then fire("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED"); queue[#queue + 1] = go else go() end
end
local function browseRows(class)
    local out = {}
    for id, c in pairs(ITEMCLASS) do
        if c == class then out[#out + 1] = { itemKey = { itemID = id }, minPrice = radarPrice[id] or base(id), totalQuantity = radarQty[id] or 500 } end
    end
    return out
end
C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return not locked end,
    SupportsCopperValues = function() return true end,
    MakeItemKey = function(id) return { itemID = id } end,
    GetAuctionItemSubClasses = function() return {} end,
    SendBrowseQuery = function(q)
        local class = q.itemClassFilters[1].classID
        send("BROWSE class " .. class, function() curBrowse = browseRows(class); fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
    end,
    HasFullBrowseResults = function() return true end,
    GetBrowseResults = function() return curBrowse or {} end,
    RequestMoreBrowseResults = function() send("BROWSE next page", function() fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {}) end) end,
    HasFullCommoditySearchResults = function() return true end,
    RequestMoreCommoditySearchResults = function(id) send("MORE " .. id, function() fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end) end,
    SendSearchQuery = function(key)
        local id = key.itemID
        send("SEARCH " .. id, function() fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end)
    end,
    GetNumCommoditySearchResults = function(id) return #rowsOf(id) end,
    GetCommoditySearchResultInfo = function(id, i) local r = rowsOf(id)[i]; return { unitPrice = r[1], quantity = r[2], numOwnerItems = 0 } end,
    GetCommoditySearchResultsQuantity = function(id) local n = 0; for _, r in ipairs(rowsOf(id)) do n = n + r[2] end; return n end,
    CalculateCommodityDeposit = function(id, d, q) return 1 * q end,
    StartCommoditiesPurchase = function(id, q) send("QUOTE " .. id) end,
    ConfirmCommoditiesPurchase = function(id, q) send("CONFIRM " .. id) end,
    CancelCommoditiesPurchase = function() end,
    QueryOwnedAuctions = function() send("OWNED", function() fire("OWNED_AUCTIONS_UPDATED") end) end,
    GetNumOwnedAuctions = function() return 0 end,
}

local ns = { plainMoney = true }
for line in io.lines("AuctionMesh/AuctionMesh.toc") do
    if line:match("%.lua$") then assert(loadfile("AuctionMesh/" .. line))("AuctionMesh", ns) end
end
local FOCUS = {}
for i = 1, 12 do FOCUS[i] = 10000 + i end
AuctionMeshDB = { cfg = { v = 11, focusMode = "list", focusItems = FOCUS } }
if SCEN == "money" then AuctionMeshDB.cfg.scope = "money" end
fire("ADDON_LOADED", "AuctionMesh")
fire("PLAYER_LOGIN")
local UI, S, Sw = ns.UI, ns.Sniper, ns.Swarm
advance(11)
AuctionHouseFrame:Show(); fire("AUCTION_HOUSE_SHOW")
local t0 = T
local armed = false
local function run(secs)
    local stop = T + secs
    while T < stop - 1e-9 do
        advance(0.1)
        if armed then UI.InputPress(true, "wheel") end
    end
end

-- what was sent between two times (seconds after the auction house opened)
local function kindOf(name)
    if name:find("^BROWSE class 7") then return "radar" end
    if name:find("^BROWSE") then return "side" end
    return name:match("^(%u+)")
end
local function window(a, b)
    local w = { n = 0, radar = 0, other = 0, gaps = {}, maxGap = 0, runOther = 0, minBetween = math.huge, list = {} }
    local lastRadar, run, since = nil, 0, nil
    for _, e in ipairs(log) do
        local t = e.t - t0
        if t >= a and t < b then
            local k = kindOf(e.name)
            w.n = w.n + 1
            w[k] = (w[k] or 0) + 1
            w.list[#w.list + 1] = { t = t, k = k, name = e.name }
            if k == "radar" then
                if lastRadar then local g = t - lastRadar; w.gaps[#w.gaps + 1] = g; if g > w.maxGap then w.maxGap = g end end
                lastRadar, run = t, 0
                if since then since = since + 1 end
            else
                w.other = w.other + 1
                run = run + 1
                if run > w.runOther then w.runOther = run end
                if since and since < w.minBetween then w.minBetween = since end
                since = 0
            end
        end
    end
    local sum = 0
    for _, g in ipairs(w.gaps) do sum = sum + g end
    w.mean = #w.gaps > 0 and sum / #w.gaps or 0
    return w
end
local function show(label, w)
    local parts = {}
    for _, k in ipairs({ "radar", "side", "SEARCH", "OWNED", "QUOTE", "CONFIRM", "MORE" }) do if w[k] and w[k] > 0 then parts[#parts + 1] = k:lower() .. " " .. w[k] end end
    print(("     %s: %d requests (%s); radar every %.3fs on average, longest gap %.2fs"):format(label, w.n, table.concat(parts, ", "), w.mean, w.maxGap))
end
local function trace()
    local secs = tonumber(os.getenv("TRACE") or "")
    if not secs then return end
    local prev
    for _, e in ipairs(log) do
        if e.t - t0 <= secs then print(("%8.3f  +%.3f  %s"):format(e.t - t0, prev and (e.t - prev) or 0, e.name)) end
        prev = e.t
    end
end
local function count(pat, a, b)
    local n = 0
    for _, e in ipairs(log) do local t = e.t - t0; if t >= (a or 0) and t < (b or 1e9) and e.name:find(pat) then n = n + 1 end end
    return n
end
local PER_MIN = 60 / (ANSWER + LOCK) -- 92.3: what the lock allows

print(("pace: %s (the lock allows %.0f requests a minute)"):format(SCEN, PER_MIN))

if SCEN == "armed" then
    -- rolling the wheel from the moment the auction house opens
    armed = true
    run(180)
    local first = log[1]
    check(first and first.name == "BROWSE class 7" and first.t - t0 < 0.5, ("the first request after the auction house opens is a radar read, %.2fs after it opened (it was 1.6s or later)"):format(first and first.t - t0 or -1))
    local w1, w2, w3 = window(0, 60), window(60, 120), window(120, 180)
    show("minute 1", w1); show("minute 2", w2); show("minute 3", w3)
    check(w1.radar >= 80 and w2.radar >= 88 and w3.radar >= 90, ("armed from the first second: %d, %d and %d radar reads a minute (it was 71 to 75: every second read left 0.3s late)"):format(w1.radar, w2.radar, w3.radar))
    check(w3.mean < 0.67, "the radar reads once per lock: 0.65s to 0.67s between reads")
    local all = window(0, 180)
    check(all.SEARCH == 12 and all.other == 12 and all.runOther <= 1 and all.minBetween >= 8,
        "armed with no listing read yet: the 12 focus listings are read once each (8 radar reads between two of them), so that flips on them can be bought straight from the radar")
    check(w3.other == 0, "after that every request is a radar read")
    local n = S:ReadyCount()
    check(n == 12, ("%d of 12 focus items are ready for a flip straight from the radar"):format(n))
    check((w1.OWNED or 0) + (w2.OWNED or 0) + (w3.OWNED or 0) == 0 and (w1.side or 0) == 0, "armed: no list of your own auctions, no side class")
    check(S.tally.armed and S.tally.armed >= 1 and S:SnipeMode(), "(the box is armed throughout)")
    local st = strip(AuctionMeshFrame.status._text or "")
    UI:Render(); st = strip(AuctionMeshFrame.status._text or "")
    print("     " .. st:gsub("\n", "\n     "))
    check(st:find("Radar: a read every 0%.6%ds%.$") ~= nil and select(2, st:gsub("\n", "")) == 0, "the Trades tab shows it in one line: a read every 0.6xs")
    local m = ns.Watch:LastMinute()
    check((m.radar or 0) >= 90 and (m.radar or 0) <= 99 and (m.alert or 0) == 0 and (m.buy or 0) == 0 and (m.upkeep or 0) + (m.sell or 0) == 0,
        "the last minute: 9x radar reads and no other request")

elseif SCEN == "unarmed" then
    -- the panel open on the Trades tab, no input: 12 focus items want their listings read
    run(180)
    local first = log[1]
    check(first and first.name == "BROWSE class 7" and first.t - t0 < 0.5, "the first request after the auction house opens is a radar read")
    local w1, w2, w3 = window(0, 60), window(60, 120), window(120, 180)
    show("minute 1", w1); show("minute 2", w2); show("minute 3", w3)
    check(w1.radar >= 80 and w2.radar >= 82 and w3.radar >= 82, ("not armed: %d, %d and %d radar reads a minute with 12 focus items to keep ready (it was 64 to 68)"):format(w1.radar, w2.radar, w3.radar))
    local all = window(0, 180)
    check(all.runOther <= 1, "never two requests in a row that are not radar reads (it was a burst of 12 radar/check pairs)")
    check(all.minBetween >= 8, ("at least 8 radar reads between two other requests (least seen: %s)"):format(tostring(all.minBetween)))
    check(count("^OWNED") == 1 and count("^OWNED", 0, 4) == 0, "the list of your own auctions is read once, after the radar's first reads, not before them")
    check(count("^SEARCH", 0, 180) >= 12, "all 12 focus listings were read (they are what a flip straight from the radar is judged against)")
    local n, total = S:ReadyCount()
    check(n == 12 and total == 12, ("%d of %d focus items are ready for a flip straight from the radar"):format(n, total))
    -- nothing changes on the radar for these items: their listings are not re-read every minute
    local late = count("^SEARCH", 120, 180)
    check(late <= 1, ("a listing the radar sees no change in is not re-read after a minute (item checks in minute 3: %d; it was 12 a minute)"):format(late))
    -- the radar shows one focus item changing: that one is re-read, the others are not
    local before = count("^SEARCH 10003")
    radarQty[10003] = 480
    run(70)
    check(count("^SEARCH 10003") == before + 1, "the radar shows a focus item's quantity change: its listing is re-read once")
    -- arming stops upkeep at once
    armed = true
    local a = T - t0
    run(60)
    local w = window(a + 1, a + 60)
    show("armed after that", w)
    check(w.other <= 1 and w.radar >= 88, "the moment you arm, the radar has every request")

elseif SCEN == "money" then
    -- the wider scope: four side classes besides the materials
    run(180)
    local first = log[1]
    check(first and first.name == "BROWSE class 7" and first.t - t0 < 0.5, "wider scope: the first request is still the materials read (the four side classes used to go first: 6.9s)")
    local firstSide
    for _, e in ipairs(log) do if kindOf(e.name) == "side" then firstSide = e.t - t0; break end end
    check(firstSide and firstSide > 4 and firstSide < 30, ("the first side class is read %.1fs in: after the main radar's first reads, and not kept waiting by item upkeep"):format(firstSide or -1))
    local all = window(0, 180)
    show("3 minutes", all)
    check(all.runOther <= 1 and all.minBetween >= 8, "side classes and item upkeep share one turn: never two in a row, 8 radar reads between them")
    check((all.side or 0) >= 4, "every side class is read")
    check(all.radar >= 3 * 80, ("the materials radar keeps %d reads in 3 minutes (it was about 180)"):format(all.radar))
    armed = true
    local a = T - t0
    run(60)
    local w = window(a + 1, a + 60)
    check((w.side or 0) == 0 and w.radar >= 88, "armed: no side class is read")

elseif SCEN == "bags" then
    -- on the Bags tab upkeep may take one request in four (prices are wanted there); the radar keeps three
    run(20)
    UI.tab = "SELL"; UI:Render()
    local a = T - t0
    run(60)
    local w = window(a, a + 60)
    show("Bags tab", w)
    check(w.runOther <= 1 and w.minBetween >= 3, "Bags tab: still never two in a row, 3 radar reads between two other requests")
    check(w.radar >= 68, ("Bags tab: the radar keeps %d reads a minute"):format(w.radar))

elseif SCEN == "alert" then
    -- a listing appears under vendor price that is NOT a deal by the rules (too little profit)
    ns.Deals.cfg.minProfit = 5000
    run(100)            -- the focus listings are read first
    armed = true
    run(10)
    local a = T - t0
    radarPrice[10050] = 5                       -- the radar: lowest price 5c, a vendor pays 10c
    listing[10050] = { { 5, 3 }, { 1040, 200 }, { 1045, 250 } }
    run(3)
    local tAlert, tRadar
    for _, e in ipairs(log) do
        local t = e.t - t0
        if t >= a and not tAlert and e.name == "SEARCH 10050" then tAlert = t end
    end
    for _, e in ipairs(log) do
        local t = e.t - t0
        if tAlert and t < tAlert and kindOf(e.name) == "radar" then tRadar = t end
    end
    check(tAlert and tRadar and tAlert - tRadar < 0.70, ("armed: the alert's item check goes out at the very next unlock, %.2fs after the radar read that saw it"):format((tAlert or 0) - (tRadar or 0)))
    check(S.verified[10050] == nil and S.judged[10050] ~= nil, "it is judged: not a deal (profit under the minimum)")
    run(120)
    local n = count("^SEARCH 10050")
    check(n == 1, ("the same standing listing is not checked again: %d item check in 2 minutes (it was one every 20 seconds, 6 in 2 minutes, with the radar waiting for each)"):format(n))
    local w = window(a + 5, a + 120)
    check(w.radar >= math.floor(115 / 0.65) - 4, "and the radar reads back to back meanwhile")
    -- cheaper still: that is a new listing, and it is checked at once
    local b = T - t0
    radarPrice[10050] = 4
    listing[10050] = { { 4, 2 }, { 5, 3 }, { 1040, 200 }, { 1045, 250 } }
    run(3)
    check(count("^SEARCH 10050", b) == 1, "a lower price on it is a new listing: checked at once")
    -- and when it really is a deal it is shown
    ns.Deals.cfg.minProfit = 1
    local c = T - t0
    radarPrice[10050] = 3; radarQty[10050] = 520
    listing[10050] = { { 3, 20 }, { 4, 2 }, { 5, 3 }, { 1040, 200 }, { 1045, 250 } }
    S.hold = 0
    run(1.5)
    check(S.verified[10050] ~= nil or (S.buying and S.buying.key == 10050), "a real deal on the same item is shown (straight from the radar: 20 new units at 3c)")
    check(count("^SEARCH 10050", c) == 0, "with no item check in between")

elseif SCEN == "flip" then
    -- listings are read while not armed; then 10 minutes of rolling; then a cheap listing appears
    ns.Deals.cfg.requireTurnover = false
    ns.Deals.cfg.minProfit = 1
    run(120)
    local n = S:ReadyCount()
    check(n == 12, "12 focus listings read before arming")
    armed = true
    local a = T - t0
    run(600)
    local w = window(a + 1, a + 600)
    show("10 minutes armed", w)
    check(w.other <= 2 and w.radar >= 890, ("10 minutes armed: %d radar reads, %d other requests"):format(w.radar, w.other))
    local ready = S:ReadyCount()
    check(ready == 12, ("after 10 minutes of rolling all 12 listings are still good for a flip straight from the radar (%d; they used to lapse after 2 minutes)"):format(ready))
    local id = 10007
    local searches = count("^SEARCH " .. id)
    local b = T - t0
    radarPrice[id] = 400; radarQty[id] = 505      -- 5 units appear at 4s, under a market of about 10s
    listing[id] = { { 400, 5 }, { base(id), 50 }, { base(id) + 5, 200 }, { base(id) + 9, 250 } }
    S.hold = 0
    run(1.0)
    local quote
    for _, e in ipairs(log) do if e.t - t0 >= b and e.name == "QUOTE " .. id then quote = e.t - t0 - b; break end end
    check(count("^SEARCH " .. id) == searches, "a flip appears: no item check is sent for it")
    check(quote and quote < 0.95, ("the price request for it leaves %.2fs after the listing appeared (an item check first would add 0.65s)"):format(quote or -1))
    local d = S.buying and S.buying.deal
    check(d and d.kind == "FLIP" and d.instant and d.units == 5 and d.sell < base(id), "it is a flip of the 5 new units, resale planned under the radar's own bottom price")

elseif SCEN == "lost" then
    -- a radar read whose answer never arrives
    armed = true
    run(20)
    dropNext = "^BROWSE class 7"
    local a = T - t0
    run(30)
    local w = window(a, a + 30)
    show("30s with one lost answer", w)
    check(w.maxGap < 1.6, ("one radar answer is lost: the read is sent again the moment the auction house is free, %.1fs between two reads (it stood still for 60s, then 6s, then 3s)"):format(w.maxGap))
    check(w.radar >= 30, "and reads on back to back")
    local W = ns.Watch
    check((W.count["NO-ANSWER"] or 0) >= 1, "the throttle watch lists it as NO-ANSWER")
    -- a read the game never transmits (no lock, no answer): sent again 0.4s later
    run(5)
    skipNext = "^BROWSE class 7"
    local b = T - t0
    run(10)
    local lostAt, againAt
    for _, e in ipairs(log) do
        local t = e.t - t0
        if t >= b and not lostAt and e.name:find("^%(not transmitted%)") then lostAt = t
        elseif lostAt and not againAt and e.name == "BROWSE class 7" then againAt = t end
    end
    check(lostAt and againAt and againAt - lostAt < 0.7, ("a read the game never transmits is sent again %.2fs later (it waited 2.7 to 3 seconds)"):format((againAt or 0) - (lostAt or 0)))
    local last = W.list[#W.list]
    print("     " .. tostring(last and last.text))
    check(last and last.kind == "NO-ANSWER" and tostring(last.text):find("the game never transmitted it", 1, true), "and the incident says the game never transmitted it")
end

trace()
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
