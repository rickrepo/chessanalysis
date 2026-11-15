-- AuctionMesh Core: wiring, saved data, seed import/export, tooltip, slash commands.
local ADDON, ns = ...
local Store, Book, Scanner, Swarm, Sniper, Deals, Seller = ns.Store, ns.Book, ns.Scanner, ns.Swarm, ns.Sniper, ns.Deals, ns.Seller
local UI = ns.UI

local floor = math.floor

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AuctionMesh|r " .. tostring(msg))
end
local say = ns.Print

-- New realm: profession goods are where the early money is, so the swarm scans them first.
local DEFAULTS = { focus = "tradegoods", scope = "mats",
    snipeAuto = true, margin = 20, minProfit = 50, flips = true, autoOpen = true, autoScan = true }

local function money(c)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(c) end
    return GetCoinTextureString and GetCoinTextureString(c) or (floor(c / 10000) .. "g")
end

local function ago(s)
    if s < 90 then return s .. "s" elseif s < 5400 then return floor(s / 60) .. "m" end
    return floor(s / 3600) .. "h"
end

---------------------------------------------------------------- seed (companion app)

-- Merge the server snapshot the companion wrote into Seed.lua (read at login).
local function importSeed(realm)
    local seed = AuctionMesh_Seed
    local data = seed and seed.realms and seed.realms[realm]
    if not data then return 0 end
    local n, now, maxAge = 0, GetServerTime(), Book.cfg.maxAge
    for k, p, q, t in data:gmatch("(%-?%d+):(%d+):(%d+):(%d+)") do
        k, p, q, t = tonumber(k), tonumber(p), tonumber(q), tonumber(t)
        if t >= now - maxAge and Store:Put(k, p, q, t) then n = n + 1 end
    end
    return n
end

-- Write everything the server hasn't acknowledged yet for the companion to upload.
local function exportForCompanion(db, realm)
    local seed = AuctionMesh_Seed
    local ack = (seed and seed.ack and seed.ack[realm]) or 0
    local parts, n = {}, 0
    local pp, qq = Store.p, Store.q
    for k, t in pairs(Store.t) do
        if t > ack then
            n = n + 1
            parts[n] = k .. ":" .. pp[k] .. ":" .. qq[k] .. ":" .. t
        end
    end
    db.export = db.export or {}
    db.export[realm] = table.concat(parts, ";")
end

---------------------------------------------------------------- tooltip

local function addTooltip(tooltip, itemID)
    if not itemID then return end
    local p, q, t = Store:Get(itemID)
    if not p then
        local note = Sniper.FlipNote(itemID)
        if note then tooltip:AddLine(note) end
        return
    end
    local now = GetServerTime()
    tooltip:AddDoubleLine("|cff33ff99AH|r cheapest listing",
        ("%s  |cffaaaaaa(%d listed, %s ago)|r"):format(money(p), q, ago(now - t)), 1, 1, 1, 1, 1, 1)
    if Store.ft[itemID] then
        tooltip:AddDoubleLine("|cff33ff99AH|r market price",
            ("%s  |cffaaaaaa(full listing, %s ago)|r"):format(money(Store.fp[itemID]), ago(now - Store.ft[itemID])), 1, 1, 1, 1, 1, 1)
    end
    do
        local t24 = Store:Trend(itemID, now, 24)
        local lo, hi, n = Store:Range(itemID, now, 7 * 24)
        if n and n > 1 then
            tooltip:AddDoubleLine("|cff33ff99AH|r 7-day range",
                ("%s - %s  |cffaaaaaa(%s in 24h, %d records)|r"):format(money(lo), money(hi),
                    t24 and ("%+d%%"):format(floor(t24 * 100 + 0.5)) or "trend n/a", n), 1, 1, 1, 1, 1, 1)
        end
    end
    if Store.st[itemID] then
        tooltip:AddDoubleLine("|cff33ff99AH|r buyers paid",
            ("%s  |cffaaaaaa(%d sold, last %s ago)|r"):format(money(Store.sa[itemID]), Store.sn[itemID], ago(now - Store.st[itemID])), 1, 1, 1, 1, 1, 1)
    end
    local note = Sniper.FlipNote(itemID)
    if note then tooltip:AddLine(note) end
end

local function hookTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if data and data.id then addTooltip(tooltip, data.id) end
        end)
    end
end

---------------------------------------------------------------- lifecycle

local function realmKey()
    return GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AuctionMeshDB = AuctionMeshDB or {}
        local db = AuctionMeshDB
        db.cfg = db.cfg or {}
        for k, v in pairs(DEFAULTS) do if db.cfg[k] == nil then db.cfg[k] = v end end
        if (db.cfg.v or 0) < 2 then db.cfg.v, db.cfg.margin = 2, 40 end -- stricter flip rules
        db.realms = db.realms or {}
    elseif event == "PLAYER_LOGIN" then
        local db, realm = AuctionMeshDB, realmKey()
        db.realms[realm] = db.realms[realm] or {}
        local r = db.realms[realm]
        Store:Attach(r)
        r.learn = r.learn or {}
        ns.Learn:Attach(r.learn)
        db.journal = db.journal or {}
        ns.Journal:Attach(db.journal)
        ns.Journal:Sync(db.flips, db.listed, function(key) return C_Item.GetItemInfo(key) or ("item:" .. key) end)
        do  -- addon version as a number (3.15.0 -> 31500)
            local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
            local a, b, c = tostring(v):match("^(%d+)%.(%d+)%.?(%d*)")
            ns.versionNum = a and (tonumber(a) * 10000 + tonumber(b) * 100 + (tonumber(c) or 0)) or 0
        end
        -- learned from a sale invoice: on this realm the posting fee does not come back
        if db.cfg.feeBack == false then Deals.cfg.depositIsCost = true end
        if db.cfg.maxTied then Deals.cfg.maxTied = db.cfg.maxTied / 100 end
        if db.cfg.maxSpend then Deals.cfg.maxSpend = db.cfg.maxSpend / 100 end
        if db.cfg.smallFlip then Deals.cfg.smallFlip = db.cfg.smallFlip / 100 end
        r.scout = r.scout or {}
        ns.Scout:Attach(r.scout)
        r.tune = r.tune or {}
        ns.Tuner:Attach(r.tune)
        db.auto = db.auto or {}
        ns.Auto:Attach(db.auto)
        if db.cfg.tune == false then ns.Tuner.cfg.enabled = false end
        if db.cfg.autoTune == false then ns.Learn.cfg.autoTune = false end
        local pruned = Store:Prune(GetServerTime() - Book.cfg.maxAge)
        local hItems, hRecords = Store:TrimHistory(GetServerTime())
        ns.historyNote = ("price history: %d items, %d hourly records"):format(hItems, hRecords)
        local seeded = importSeed(realm)

        ns.Diag:Init()
        Scanner:Init()
        Swarm:Init()
        if (db.cfg.v or 0) < 4 then db.cfg.v, db.cfg.focus, db.cfg.scope = 4, "tradegoods", "mats" end
        if (db.cfg.v or 0) < 6 then db.cfg.margin = 20 end -- tuned from a real market log
        if (db.cfg.v or 0) < 7 then db.deposits = nil end -- old per-unit fee guesses were wrong
        if (db.cfg.v or 0) < 5 then if db.cfg.minProfit < 50 then db.cfg.minProfit = 50 end end
        if (db.cfg.v or 0) < 8 then
            -- Sales per hour used to include cancelled auctions (radar churn). Start the measurement again.
            for k in pairs(Store.vu) do Store.vu[k] = nil end
            for k in pairs(Store.vs) do Store.vs[k] = nil end
        end
        if (db.cfg.v or 0) < 10 then
            -- The pause between requests had been raised by errors that belonged
            -- to failed purchases, not to the pace. Start again from no pause.
            local g = r.tune and r.tune.gap
            if g then g.i, g.clean, g.sinceFail, g.stats, g.trial = 1, 0, 1000, {}, nil; ns.Tuner:Apply() end
        end
        if (db.cfg.v or 0) < 11 then
            -- All sharing between players has been removed from the addon. If an
            -- earlier version joined a chat channel for it, leave that channel
            -- once (the game remembers channels between sessions), and forget
            -- the channel settings.
            local old = db.cfg.channel
            if old and old ~= "" then
                C_Timer.After(10, function()
                    if LeaveChannelByName and GetChannelName and (GetChannelName(old) or 0) > 0 then
                        pcall(LeaveChannelByName, old)
                        ns.Print(("Left the chat channel '%s': AuctionMesh no longer shares anything with other players."):format(old))
                    end
                end)
            end
            db.cfg.channel, db.cfg.password, db.cfg.route, db.cfg.share = nil, nil, nil, nil
        end
        db.cfg.v = 11
        Deals.cfg.minProfit = db.cfg.minProfit
        Swarm.scope = db.cfg.scope
        Swarm:SetFocus(db.cfg.focus)
        Deals.cfg.margin, Deals.cfg.minProfit = db.cfg.margin / 100, db.cfg.minProfit
        Deals.cfg.flips = db.cfg.flips
        Sniper:Init(function() return AuctionMeshDB.cfg.snipeAuto end)
        Seller:Init()
        UI:Init()
        -- Scanning starts by itself when the Auction House opens.
        local ah = CreateFrame("Frame")
        ah:RegisterEvent("AUCTION_HOUSE_SHOW")
        ah:SetScript("OnEvent", function()
            C_Timer.After(1.5, function()
                if AuctionMeshDB.cfg.autoScan and not Swarm.active and not Swarm.manual then Swarm:Start(true) end
            end)
        end)
        -- Retail-style AH rejects copper: prices must be whole silver, so undercut by 1s.
        if C_AuctionHouse.SupportsCopperValues and not C_AuctionHouse.SupportsCopperValues() then
            Deals.cfg.step, Deals.cfg.undercut = 100, 100
        end
        hookTooltips()

        ns.sessionStart, ns.realizedAtLogin = GetTime(), AuctionMeshDB.realized or 0
        ns.measure = {} -- live measurements of the request limit and sweep cost
        -- EVENT-DRIVEN PUMP. The instant the auction house unlocks, send the next
        -- request: first the sniper (a click you made, a trigger, a price check),
        -- then the sweep. The slow timers remain only as a safety net.
        ns.OnAHReady = function()
            if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
            local before = ns.Gate.usedAt
            -- a locked-in price becomes BUY NOW the instant the lock opens
            if Sniper.buying and Sniper.buying.phase == "confirm" then UI:Now() end
            Sniper:Tick()
            if ns.Gate.usedAt ~= before and ns.Gate.usedAt == GetTime() then return end -- the slot is taken
            Swarm:Step()
            if Swarm.current and Swarm.current.phase == "claimed" then Swarm:Step() end
        end
        if seeded > 0 or pruned > 0 then
            say(("%d prices loaded (%d from central DB, %d expired)."):format(Store.n, seeded, pruned))
        end
    elseif event == "PLAYER_LOGOUT" then
        local db, realm = AuctionMeshDB, realmKey()
        local r = db.realms and db.realms[realm]
        ns.Diag:Save()
        if r and Store.t then
            exportForCompanion(db, realm)
        end
    end
end)

---------------------------------------------------------------- slash

-- ACTIONS. Everything a player can change is a control on the Setup tab; the
-- controls and the (optional) slash command call the same functions here.
local Do = {}
ns.Do = Do

local SCOPES = { "mats", "money", "all" }
Do.SCOPE_NAMES = { mats = "Crafting materials", money = "All money-makers", all = "Whole auction house" }
-- v = "mats" | "money" | "all"; nil moves to the next one
function Do.Scope(v)
    local cfg = AuctionMeshDB.cfg
    if not v then
        local at = 1
        for i, s in ipairs(SCOPES) do if s == cfg.scope then at = i end end
        v = SCOPES[at % #SCOPES + 1]
    end
    if not Do.SCOPE_NAMES[v] then return end
    cfg.scope, Swarm.scope = v, v
    Swarm.units = {}
    if Swarm.active then Swarm:BuildUnits() end
    Sniper.lastBg = 0
    UI:Notice(v == "all" and "Crafting materials are still read about every second. Every other category is read in turn, about once a minute or slower."
        or v == "money" and "Crafting materials are still read about every second. Reagents, consumables, gems and enhancements are each read every 30 seconds."
        or "The radar reads crafting materials only, about every second.", true)
end

function Do.Dock(on)
    local cfg = AuctionMeshDB.cfg
    cfg.dock = on and true or false
    local tab = UI.tab
    UI:Close()
    UI:Open(tab)
    UI:Notice(cfg.dock and "The panel opens inside the auction house window." or "The panel opens as a separate window.", true)
end

function Do.Auto(on)
    local cfg = AuctionMeshDB.cfg
    cfg.autoOpen = on and true or false
    cfg.snipeAuto, cfg.autoScan = cfg.autoOpen, cfg.autoOpen
    UI:Notice(cfg.autoOpen and "Opens and starts reading prices by itself at the auction house."
        or "Stays closed until you click the AuctionMesh tab under the auction house window.", true)
end

function Do.Margin(pct)
    local cfg = AuctionMeshDB.cfg
    pct = tonumber(pct)
    if pct then
        pct = math.max(5, math.min(90, floor(pct + 0.5)))
        cfg.margin, Deals.cfg.margin = pct, pct / 100
        Sniper.checkedAt = {}
    end
    UI:Notice(("A flip must leave %d%% profit after the auction house cut. Vendor deals need %d%%."):format(cfg.margin, Deals.cfg.vendorMargin * 100), true)
end

-- How much of your money flips may tie up at once (the rest stays free for vendor deals).
local TIED = { 30, 50, 70, 100 }
function Do.MaxTied(pct)
    local cfg = AuctionMeshDB.cfg
    if not pct then
        local at = 1
        for i, v in ipairs(TIED) do if v == (cfg.maxTied or 50) then at = i end end
        pct = TIED[at % #TIED + 1]
    end
    cfg.maxTied = pct
    Deals.cfg.maxTied = pct / 100
    Sniper.checkedAt = {}
    UI:Notice(("Flips may tie up at most %d%% of your money at once. The rest stays free for vendor deals, which pay back in minutes."):format(pct), true)
end

-- Auto-adjust covers both learners: the request engine and the profit bar.
function Do.Tuning(on)
    local cfg = AuctionMeshDB.cfg
    on = on and true or false
    ns.Tuner.cfg.enabled, cfg.tune = on, on
    ns.Learn.cfg.autoTune, cfg.autoTune = on, on
    UI:Notice(on and "Auto-adjust on: the pace, the split of requests, the profit bar, the smallest profit and the radar's quiet time adjust themselves from results."
        or "Auto-adjust off: everything stays as it is now (still measured).", true)
end

function Do.Forget()
    local r = AuctionMeshDB.realms[realmKey()]
    r.tune = {}
    ns.Tuner:Attach(r.tune)
    for k in pairs(ns.Learn.d) do ns.Learn.d[k] = nil end
    ns.Learn:Attach(ns.Learn.d)
    UI:Notice("Forgot everything learned (request limit, pace, split, trade results). Measuring again from scratch.", true)
end

-- Biggest 24h price moves among items with price history: { key, tr, price }.
function Do.Trends(n)
    local now, list = GetServerTime(), {}
    for key in pairs(Store.hist) do
        local tr = Store:Trend(key, now, 24) or Store:Trend(key, now, 6)
        if tr then list[#list + 1] = { key = key, tr = tr, price = Store.fp[key] or Store.p[key] or 0 } end
    end
    table.sort(list, function(a, b) return math.abs(a.tr) > math.abs(b.tr) end)
    for i = #list, (n or 10) + 1, -1 do list[i] = nil end
    return list
end

-- The daily report: one block of text with what the addon measured, to share.
-- The quick one: where the money is and what just happened, in about 60 lines.
function Do.Snapshot()
    local text = ns.Scout:Snapshot({
        version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
        realm = realmKey(), gold = GetMoney(), code = Do.SettingsCode(),
    })
    ns.Diag:ShowText("AuctionMesh snapshot: click in the box, Ctrl+A then Ctrl+C, and paste it to Claude", text)
    return text
end

function Do.Report()
    local errors = 0
    for line in ns.Diag:Text():gmatch("[^\n]+") do
        if line:find("GATE backoff", 1, true) or line:find("PURCHASE FAILED", 1, true) then errors = errors + 1 end
    end
    local text = ns.Scout:Report({
        version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
        realm = realmKey(), gold = GetMoney(), vendorOf = Sniper.vendorOf, vendorSold = Sniper.VENDOR_SOLD,
        classOf = Sniper.classSub, errors = errors,
    })
    ns.Diag:ShowText("AuctionMesh daily report: click in the box, Ctrl+A then Ctrl+C, and paste it to Claude", text)
    return text
end

function Do.FocusMode()
    local mode = ns.Scout:SetMode()
    local _, _, text = Sniper:FocusSet()
    UI:Notice("Laser focus: " .. ns.Scout.MODE_NAMES[mode] .. ". " .. text, true)
end

---------------------------------------------------------------- settings code
-- One line that holds every setting that decides what is shown as a deal.
-- The Snapshot carries it, Claude sends back a changed one, and pasting that
-- into the box on the Setup tab applies it. 
--   AMS1:min=100;margin=25;flips=1;scope=mats;focus=prime;list=2589,2592;
--        tied=50;spend=35;small=15;wheel=1;tune=1;itemmin=4306:200;ignore=2287
-- Changes only (an import need not carry everything):
--   watch=+2589,-4306   add to / remove from your own watch list
--   ignore=+2287,-2589  add to / remove from the ignore list
local function coinText(c)
    c = floor((c or 0) + 0.5)
    local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
    return (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. k .. "c"
end

function Do.SettingsCode()
    local cfg = AuctionMeshDB.cfg
    local t = {}
    local function put(k, v) t[#t + 1] = k .. "=" .. tostring(v) end
    put("min", cfg.minProfit)
    put("margin", cfg.margin)
    put("flips", cfg.flips ~= false and 1 or 0)
    put("scope", cfg.scope or "mats")
    put("focus", cfg.focusMode or "off")
    do
        local ids = {}
        for _, k in ipairs(cfg.focusItems or {}) do ids[#ids + 1] = tostring(k) end
        if #ids > 0 then put("list", table.concat(ids, ",")) end
    end
    put("tied", cfg.maxTied or 50)
    put("spend", cfg.maxSpend or floor(Deals.cfg.maxSpend * 100 + 0.5))
    put("small", cfg.smallFlip or floor(Deals.cfg.smallFlip * 100 + 0.5))
    put("every", Sniper.FocusEvery())
    if Sniper:StakeKey() then put("stake", Sniper:StakeKey()) end
    put("buy", ns.UI and ns.UI.BuyMode and ns.UI.BuyMode() or "wheel")
    if cfg.buyKey and cfg.buyKey ~= "" then put("key", cfg.buyKey) end
    put("tune", cfg.tune ~= false and 1 or 0)
    do
        local ids = {}
        for k, v in pairs(cfg.itemMin or {}) do ids[#ids + 1] = k .. ":" .. v end
        table.sort(ids)
        if #ids > 0 then put("itemmin", table.concat(ids, ",")) end
        local ig = {}
        for k in pairs(cfg.ignore or {}) do ig[#ig + 1] = tostring(k) end
        table.sort(ig)
        if #ig > 0 then put("ignore", table.concat(ig, ",")) end
    end
    return "AMS1:" .. table.concat(t, ";")
end

-- Finds a settings code (AMS1:) and/or a focus code (AMF1:) anywhere in the
-- pasted text and applies it. Says exactly what changed.
function Do.Import(text)
    text = tostring(text or "")
    local body = text:match("AMS1%s*:%s*([^%s]+)")
    local hasFocus = text:find("AMF1", 1, true) ~= nil
    if not body then
        if hasFocus then return Do.FocusCode(text) end
        UI:Notice("|cffff8040No code found in that text.|r A settings code starts with AMS1: and a focus code with AMF1:.", true)
        return false
    end
    body = body:gsub("[%.%)%]\"'`,]+$", "")
    local cfg = AuctionMeshDB.cfg
    local changes, unknown = {}, {}
    local function note(name, old, new)
        if tostring(old) ~= tostring(new) then changes[#changes + 1] = ("%s %s > %s"):format(name, tostring(old), tostring(new)) end
    end
    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, floor(v + 0.5))) end
    local function nameOf(id) return (C_Item.GetItemInfo(id)) or ("item " .. id) end
    local function onoff(v) return (v == "1" or v == "on" or v == "true") end
    local function hasItem(list, id) for i, k in ipairs(list) do if k == id then return i end end end
    for pair in body:gmatch("[^;]+") do
        local k, v = pair:match("^%s*([%a_]+)%s*=%s*(.-)%s*$")
        local n = tonumber(v)
        if k == "min" and n then
            n = clamp(n, 1, 1000000)
            local old = cfg.minProfit
            if old ~= n then UI:SetMinProfit(n) end
            note("smallest profit", coinText(old), coinText(n))
        elseif k == "margin" and n then
            local old = cfg.margin
            if old ~= clamp(n, 5, 90) then Do.Margin(n) end
            note("flip margin", tostring(old) .. "%", tostring(cfg.margin) .. "%")
        elseif k == "flips" then
            local on = onoff(v)
            local old = cfg.flips ~= false
            if old ~= on then UI:SetVendorOnly(not on) end
            note("flips", old and "on" or "off", on and "on" or "off")
        elseif k == "scope" and Do.SCOPE_NAMES[v] then
            local old = cfg.scope
            if old ~= v then Do.Scope(v) end
            note("radar reads", tostring(old), v)
        elseif k == "focus" and ns.Scout.MODE_NAMES[v] then
            local old = cfg.focusMode or "off"
            if old ~= v then ns.Scout:SetMode(v) end
            note("laser focus", old, v)
        elseif k == "list" then
            local ids, seen = {}, {}
            for tok in v:gmatch("%d+") do
                local id = tonumber(tok)
                if id > 0 and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
            note("own watch list", #(cfg.focusItems or {}) .. " items", #ids .. " items")
            cfg.focusItems = ids
        elseif k == "watch" then
            cfg.focusItems = cfg.focusItems or {}
            for sign, tok in v:gmatch("([%+%-]?)(%d+)") do
                local id = tonumber(tok)
                local at = hasItem(cfg.focusItems, id)
                if sign == "-" then
                    if at then table.remove(cfg.focusItems, at); changes[#changes + 1] = "watch list: removed " .. nameOf(id) end
                elseif not at and id > 0 then
                    cfg.focusItems[#cfg.focusItems + 1] = id
                    changes[#changes + 1] = "watch list: added " .. nameOf(id)
                end
            end
        elseif k == "tied" and n then
            local old = cfg.maxTied or 50
            n = clamp(n, 10, 100)
            if old ~= n then Do.MaxTied(n) end
            note("unsold auctions may hold", old .. "%", n .. "%")
        elseif k == "spend" and n then
            local old = cfg.maxSpend or floor(Deals.cfg.maxSpend * 100 + 0.5)
            n = clamp(n, 10, 100)
            cfg.maxSpend, Deals.cfg.maxSpend = n, n / 100
            note("one flip may take (of gold in hand)", old .. "%", n .. "%")
        elseif k == "small" and n then
            local old = cfg.smallFlip or floor(Deals.cfg.smallFlip * 100 + 0.5)
            n = clamp(n, 0, 50)
            cfg.smallFlip, Deals.cfg.smallFlip = n, n / 100
            note("a small flip is always allowed up to", old .. "%", n .. "%")
        elseif k == "stake" and n then
            local old = Sniper:StakeKey()
            n = floor(n)
            if (old or 0) ~= n then
                Sniper:SetStake(n > 0 and n or nil)
                changes[#changes + 1] = n > 0 and ("stake-out set on " .. nameOf(n)) or "stake-out ended"
            end
        elseif k == "every" and n then
            local old = Sniper.FocusEvery()
            cfg.focusEvery = clamp(n, 20, 300)
            Sniper.lastBg = 0
            note("focus items are re-read every", old .. "s", cfg.focusEvery .. "s")
        elseif k == "buy" or k == "wheel" then
            -- buy=wheel|key|hold|click; the older wheel=1/0 still works
            local U = ns.UI
            local mode = v:lower()
            if k == "wheel" then mode = onoff(v) and "wheel" or "click" end
            if U and U.BUY_NAMES and U.BUY_NAMES[mode] then
                local old = U.BuyMode()
                if old ~= mode then
                    cfg.buyMode, cfg.wheel = mode, nil
                    if cfg.buyBlocked then cfg.buyBlocked[mode] = nil end
                end
                note("buy with", U.BUY_NAMES[old], U.BUY_NAMES[mode])
            else
                changes[#changes + 1] = "buy=" .. v .. " is not a way to buy (wheel, key, hold or click): left alone"
            end
        elseif k == "key" then
            local name = v:upper():gsub("%s+", "")
            if name:match("^[%w%-]+$") then
                local old = cfg.buyKey
                cfg.buyKey = name
                note("buy key", old or "not set", name)
            end
        elseif k == "tune" then
            local on, old = onoff(v), cfg.tune ~= false
            if old ~= on then Do.Tuning(on) end
            note("auto-adjust", old and "on" or "off", on and "on" or "off")
        elseif k == "itemmin" then
            cfg.itemMin = cfg.itemMin or {}
            for id, amt in v:gmatch("(%d+):(%d+)") do
                id, amt = tonumber(id), tonumber(amt)
                local old = cfg.itemMin[id]
                cfg.itemMin[id] = amt > 0 and amt or nil
                if old ~= cfg.itemMin[id] then
                    changes[#changes + 1] = ("%s: smallest profit %s"):format(nameOf(id), amt > 0 and coinText(amt) or "back to the general one")
                end
            end
        elseif k == "ignore" then
            cfg.ignore = cfg.ignore or {}
            for sign, tok in v:gmatch("([%+%-]?)(%d+)") do
                local id = tonumber(tok)
                if sign == "-" then
                    if cfg.ignore[id] then cfg.ignore[id] = nil; changes[#changes + 1] = "no longer ignored: " .. nameOf(id) end
                elseif not cfg.ignore[id] and id > 0 then
                    cfg.ignore[id] = true
                    Sniper.verified[id] = nil
                    changes[#changes + 1] = "ignored from now on: " .. nameOf(id)
                end
            end
        elseif k then
            unknown[#unknown + 1] = k
        end
    end
    ns.Scout:Changed()
    Sniper.checkedAt = {}
    if ns.Auto then ns.Auto:Manual("min") end -- an imported setting is yours: auto-adjust leaves it alone for 30 minutes
    if hasFocus then ns.Scout:ApplyCode(text) end
    local msg
    if #changes == 0 then
        msg = "Settings code read: everything in it is already set that way."
    else
        msg = ("|cff33ff66Imported %d change%s:|r %s."):format(#changes, #changes == 1 and "" or "s", table.concat(changes, "; "))
    end
    if #unknown > 0 then msg = msg .. " |cffff8040Not understood and left alone: " .. table.concat(unknown, ", ") .. ".|r" end
    ns.Log("IMPORT %s -> %s", body, (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    if ns.Print then ns.Print(msg) end
    UI:Notice(msg, true)
    return true, changes
end

function Do.FocusCode(text)
    local ok, msg = ns.Scout:ApplyCode(text)
    UI:Notice((ok and "|cff33ff66" or "|cffff8040") .. msg .. "|r", true)
    return ok
end

-- The game's addon list next to the minimap opens the panel (no command needed).
-- The game's own Key Bindings screen (Options > Keybindings > AddOns) lists
-- "Buy the best deal": any key bound there presses the snipe box. Not needed
-- for the mouse wheel, which the addon handles itself.
BINDING_HEADER_AUCTIONMESH = "AuctionMesh"
_G["BINDING_NAME_CLICK AuctionMeshSnipeButton:LeftButton"] = "Buy the best deal"

function AuctionMesh_OnAddonCompartmentClick() UI:Toggle() end

SLASH_AUCTIONMESH1 = "/amesh"
SlashCmdList.AUCTIONMESH = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local cfg = AuctionMeshDB.cfg
    if cmd == "" then
        UI:Toggle()
    elseif cmd == "log" then
        if rest == "clear" then ns.Diag:Clear(); say("Log cleared.")
        elseif rest == "old" then ns.Diag:Show(true)
        else ns.Diag:Show() end
    elseif cmd == "restore" then
        Seller:Restore()
    elseif cmd == "track" then
        -- /amesh track [item link] [cost per unit in copper]
        local id = tonumber(rest:match("item:(%d+)")) or tonumber(rest:match("^(%d+)"))
        local cost = tonumber(rest:match("%]|h|r%s*(%d+)%s*$") or rest:match("^%d+%s+(%d+)%s*$"))
        if id then Seller:Track(id, cost) else say("Drag the item from your bags onto the AuctionMesh panel to track it.") end
    elseif cmd == "vendor" then
        UI:SetVendorOnly(rest ~= "off" and (rest == "on" or Deals.cfg.flips))
    elseif cmd == "flips" then
        UI:SetVendorOnly(rest == "off")
    elseif cmd == "auto" then
        Do.Auto(rest ~= "off")
    elseif cmd == "margin" then
        Do.Margin(rest)
    elseif cmd == "minprofit" then
        -- /amesh minprofit 1s50c  |  2s  |  75c  |  150 (copper)
        local g, s2, cp = rest:match("(%d+)g"), rest:match("(%d+)s"), rest:match("(%d+)c")
        local v = (tonumber(g) or 0) * 10000 + (tonumber(s2) or 0) * 100 + (tonumber(cp) or 0)
        if v == 0 then v = tonumber(rest) or 0 end
        if v > 0 then UI:SetMinProfit(v) else say("Minimum profit per deal: " .. money(cfg.minProfit) .. ". Change it on the Setup tab.") end
    elseif cmd == "dock" then
        Do.Dock(rest ~= "off")
    elseif cmd == "scope" then
        Do.Scope((rest == "all" or rest == "money" or rest == "mats") and rest or nil)
    elseif cmd == "swarm" then
        if Swarm.active then cfg.autoScan = false; Swarm:Stop("Scanning off.") else cfg.autoScan = true; Swarm:Start() end
    elseif cmd == "step" then
        Swarm:ManualStep()
    elseif cmd == "focus" then
        local added = Swarm:SetFocus(rest)
        cfg.focus = table.concat(added, " ")
        say(#added > 0 and ("Focus: " .. cfg.focus .. " (scanned first when you swarm).") or
            "Focus cleared. Names: herbs ore cloth leather cooking elemental enchanting inscription jewelcrafting parts consumables armor weapons gems recipes pets, or classID[:subClassID].")
    elseif cmd == "scan" then
        Scanner:FullScan(rest == "force")
    elseif cmd == "price" then
        local id = tonumber(rest) or (rest ~= "" and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rest))
        local p, q, t = Store:Get(id or 0)
        if p then say(("%s: %s, %d listed, %s ago"):format(rest, money(p), q, ago(GetServerTime() - t)))
        else say("No mesh data for " .. rest) end
    elseif cmd == "trends" then
        local list = Do.Trends(10)
        if #list == 0 then say("No trends yet: the price history needs a few hours of readings.") end
        for _, e in ipairs(list) do
            say(("%s%+d%%|r  %s  now %s"):format(e.tr >= 0 and "|cff33ff66" or "|cffff4040", floor(e.tr * 100 + 0.5), Sniper.nameOf(e.key), money(e.price)))
        end
    elseif cmd == "learn" then
        if rest == "off" or rest == "on" then Do.Tuning(rest == "on")
        elseif rest == "reset" then Do.Forget()
        else say(ns.Learn:Summary()) end
    elseif cmd == "details" then
        if not ns.UI:IsShown() then ns.UI:Open() end
        ns.UI:ToggleDrawer()
    elseif cmd == "limits" then
        -- what has been measured on this client, this session
        local G, M = ns.Gate, ns.measure and ns.measure.last
        say(G.cycle and ("Request limit: %.2fs per request (%.1f a second), measured over %d requests."):format(G.cycle, 1 / G.cycle, G.cycleN or 0)
            or "Request limit: not measured yet (open the auction house with the panel open).")
        say(M and ("Sweep: %d materials in %d request(s); largest page returned %d results; radar every %ds."):format(M.items, M.requests, M.pageMax, Swarm.cfg.fresh)
            or "Sweep: not measured yet.")
        for _, l in ipairs(ns.Tuner:Lines()) do say(l[1] .. ": " .. l[2]) end
        if rest == "reset" then Do.Forget()
        elseif rest == "off" or rest == "on" then Do.Tuning(rest == "on") end
    elseif cmd == "status" then
        local ss = Book.stats
        local fago = Book:FreshestScan()
        say(("prices on record: %d | readings %d, of which %d changed a record"):format(Store.n or 0, ss.observed, ss.netNew))
        if fago then say(("last full scan: %s ago"):format(ago(fago))) end
        if #Swarm.units > 0 then
            local fresh, total, workers = Swarm:Coverage()
            say(("radar %s: %d/%d categories fresh, %d reads / %d requests"):format(
                Swarm.active and "ON" or "off", fresh, total, Swarm.stats.units, Swarm.stats.queries))
        end
    else
        say("Everything is on the panel's Setup tab; no commands are needed. /amesh opens and closes the panel.")
    end
end
