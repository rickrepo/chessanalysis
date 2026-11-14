-- AuctionMesh Core: wiring, saved data, seed import/export, tooltip, slash commands.
local ADDON, ns = ...
local Codec, Store, Comm, Sync, Scanner, Swarm, Sniper, Deals, Seller = ns.Codec, ns.Store, ns.Comm, ns.Sync, ns.Scanner, ns.Swarm, ns.Sniper, ns.Deals, ns.Seller
local UI = ns.UI

local floor = math.floor

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AuctionMesh|r " .. tostring(msg))
end
local say = ns.Print

-- New realm: profession goods are where the early money is, so the swarm scans them first.
local DEFAULTS = { channel = "", password = "", route = "channel", focus = "tradegoods", scope = "mats",
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
    local n, now, maxAge = 0, GetServerTime(), Sync.cfg.maxAge
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

local function applyRoute()
    local cfg = AuctionMeshDB.cfg
    if cfg.route == "channel" and cfg.channel ~= "" then
        Comm:JoinChannel(cfg.channel, cfg.password ~= "" and cfg.password or nil)
    else
        Comm.channelName = nil
    end
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
        r.tune = r.tune or {}
        ns.Tuner:Attach(r.tune)
        if db.cfg.tune == false then ns.Tuner.cfg.enabled = false end
        if db.cfg.autoTune == false then ns.Learn.cfg.autoTune = false end
        local pruned = Store:Prune(GetServerTime() - Sync.cfg.maxAge)
        local hItems, hRecords = Store:TrimHistory(GetServerTime())
        ns.historyNote = ("price history: %d items, %d hourly records"):format(hItems, hRecords)
        local seeded = importSeed(realm)
        Sync.lastSeen = r.lastSeen or 0

        ns.Diag:Init()
        Comm.realm = realm
        Comm.me = UnitName("player") .. "-" .. realm
        Comm.paused = function() return InCombatLockdown() end
        Comm.handlers[Comm.PREFIX_LIVE] = Sync.Dispatch
        Comm.handlers[Comm.PREFIX_BULK] = Sync.Dispatch
        Comm:Init()
        Scanner:Init()
        Swarm:Init()
        if (db.cfg.v or 0) < 4 then db.cfg.v, db.cfg.focus, db.cfg.scope = 4, "tradegoods", "mats" end
        if (db.cfg.v or 0) < 6 then db.cfg.margin = 20 end -- tuned from a real market log
        if (db.cfg.v or 0) < 7 then db.deposits = nil end -- old per-unit fee guesses were wrong
        if (db.cfg.v or 0) < 5 then if db.cfg.minProfit < 50 then db.cfg.minProfit = 50 end end
        db.cfg.v = 7
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

        -- Channels can't be joined reliably in the first seconds after login.
        C_Timer.After(6, function()
            applyRoute()
            C_Timer.After(2 + math.random() * 3, function() Sync:Hello() end)
        end)
        C_Timer.NewTicker(30, function() Sync:Tidy() end)
        C_Timer.NewTicker(150, function()
            if Comm:Route() then
                Sync:Beacon()
                -- with friends connected, pass on what has been measured (at most every 10 minutes)
                if ns.peerAt and GetTime() - ns.peerAt < 600 then ns.Tuner:Share() end
            end
        end)
        ns.sessionStart, ns.realizedAtLogin = GetTime(), AuctionMeshDB.realized or 0
        ns.measure = {} -- live measurements of the request limit and sweep cost
        -- EVENT-DRIVEN PUMP. The instant the auction house unlocks, send the next
        -- request: first the sniper (a click you made, a trigger, a price check),
        -- then the sweep. The slow timers remain only as a safety net.
        ns.OnAHReady = function()
            if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
            local before = ns.Gate.usedAt
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
            r.lastSeen = GetServerTime()
            exportForCompanion(db, realm)
        end
    end
end)

---------------------------------------------------------------- slash

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
        if id then Seller:Track(id, cost) else say("Usage: /amesh track [item link] [cost in copper], or drag the item onto the AuctionMesh window.") end
    elseif cmd == "vendor" then
        UI:SetVendorOnly(rest ~= "off" and (rest == "on" or Deals.cfg.flips))
    elseif cmd == "flips" then
        UI:SetVendorOnly(rest == "off")
    elseif cmd == "auto" then
        cfg.autoOpen = (rest ~= "off"); cfg.snipeAuto = cfg.autoOpen; cfg.autoScan = cfg.autoOpen
        say(cfg.autoOpen and "Opens and scans automatically at the Auction House." or "Automatic open/scan off. Use /amesh.")
    elseif cmd == "margin" then
        local m = tonumber(rest)
        if m then cfg.margin = m; Deals.cfg.margin = m / 100 end
        say(("Flip margin: %d%% profit after the AH cut and deposit (vendor deals use %d%%)."):format(cfg.margin, Deals.cfg.vendorMargin * 100))
    elseif cmd == "minprofit" then
        -- /amesh minprofit 1s50c  |  2s  |  75c  |  150 (copper)
        local g, s2, cp = rest:match("(%d+)g"), rest:match("(%d+)s"), rest:match("(%d+)c")
        local v = (tonumber(g) or 0) * 10000 + (tonumber(s2) or 0) * 100 + (tonumber(cp) or 0)
        if v == 0 then v = tonumber(rest) or 0 end
        if v > 0 then UI:SetMinProfit(v) else say("Minimum profit per deal: " .. money(cfg.minProfit) .. ". Example: /amesh minprofit 1s50c") end
    elseif cmd == "dock" then
        cfg.dock = (rest ~= "off")
        UI:Close()
        say(cfg.dock and "The panel opens inside the auction house window." or "The panel opens as a separate window.")
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then UI:Open() end
    elseif cmd == "scope" then
        if rest == "all" or rest == "money" or rest == "mats" then
            cfg.scope, Swarm.scope = rest, rest
            Swarm.units = {}
            if Swarm.active then Swarm:BuildUnits() end
        end
        say(cfg.scope == "all" and "Scope: the whole auction house."
            or cfg.scope == "money" and "Scope: trade goods, reagents, consumables, gems, enhancements."
            or "Scope: crafting materials only. (/amesh scope money or all for more)")
        Sniper.lastBg = 0
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
    elseif cmd == "channel" then
        local name, pw = rest:match("^(%S+)%s*(%S*)$")
        if not name then say("Usage: /amesh channel <name> [password]"); return end
        cfg.channel, cfg.password, cfg.route = name, pw or "", "channel"
        applyRoute()
        say("Mesh channel set to '" .. name .. "'. Everyone in your group must use the same name/password.")
        C_Timer.After(3, function() Sync:Hello() end)
    elseif cmd == "guild" then
        cfg.route = "guild"; applyRoute(); say("Mesh routed over guild addon channel.")
        C_Timer.After(1, function() Sync:Hello() end)
    elseif cmd == "sync" then
        Sync:Hello(); say("Asked the mesh for anything we're missing.")
    elseif cmd == "price" then
        local id = tonumber(rest) or (rest ~= "" and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rest))
        local p, q, t = Store:Get(id or 0)
        if p then say(("%s: %s, %d listed, %s ago"):format(rest, money(p), q, ago(GetServerTime() - t)))
        else say("No mesh data for " .. rest) end
    elseif cmd == "trends" then
        -- biggest 24h moves among items with price history
        local now, list = GetServerTime(), {}
        for key in pairs(Store.hist) do
            local tr = Store:Trend(key, now, 24) or Store:Trend(key, now, 6)
            if tr then list[#list + 1] = { key = key, tr = tr } end
        end
        table.sort(list, function(a, b) return math.abs(a.tr) > math.abs(b.tr) end)
        if #list == 0 then say("No trends yet: the price history needs a few hours of readings.") end
        for i = 1, math.min(10, #list) do
            local e = list[i]
            say(("%s%+d%%|r  %s  now %s"):format(e.tr >= 0 and "|cff33ff66" or "|cffff4040", floor(e.tr * 100 + 0.5),
                Sniper.nameOf(e.key), money(Store.fp[e.key] or 0)))
        end
    elseif cmd == "learn" then
        if rest == "off" or rest == "on" then
            ns.Learn.cfg.autoTune = (rest == "on"); cfg.autoTune = ns.Learn.cfg.autoTune
            say(ns.Learn.cfg.autoTune and "The profit bar adjusts itself from results." or "The profit bar stays where you set it.")
        elseif rest == "reset" then
            for k in pairs(ns.Learn.d) do ns.Learn.d[k] = nil end
            ns.Learn:Attach(ns.Learn.d); say("Learning data cleared.")
        else
            say(ns.Learn:Summary())
        end
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
        if rest == "reset" then
            local r = AuctionMeshDB.realms[realmKey()]
            r.tune = {}
            ns.Tuner:Attach(r.tune)
            say("Everything learned about the request limit was cleared; measuring again.")
        elseif rest == "off" or rest == "on" then
            ns.Tuner.cfg.enabled = rest == "on"
            cfg.tune = rest == "on"
            say(rest == "on" and "The addon adjusts its own pace and split again." or "Pace and split are frozen at their current values (still measured).")
        end
    elseif cmd == "status" then
        local cs, ss = Comm.stats, Sync.stats
        local chatType, target = Comm:Route()
        local fago, fby = Sync:FreshestScan()
        say(("route=%s%s  prices=%d  pendingOut=%d  queues c/l/b=%d/%d/%d"):format(
            chatType or "NONE", target and ("#" .. target) or "", Store.n or 0, Sync.npending,
            Comm:LaneSize(1), Comm:LaneSize(2), Comm:LaneSize(3)))
        say(("sent %d msgs (%d B), recv %d, throttled %d | observed %d, net-new %d, applied %d, dup %d, rejected %d"):format(
            cs.sent, cs.bytes, cs.recv, cs.throttled, ss.observed, ss.netNew, ss.applied, ss.ignored, ss.rejected))
        if fago then say(("last full scan: %s ago by %s"):format(ago(fago), fby or "?")) end
        if #Swarm.units > 0 then
            local fresh, total, workers = Swarm:Coverage()
            say(("swarm %s: %d/%d categories fresh, %d peers scanning, you did %d units / %d queries"):format(
                Swarm.active and "ON" or "off", fresh, total, workers, Swarm.stats.units, Swarm.stats.queries))
        end
    else
        say("/amesh = open the window | details | learn | limits [on|off|reset] | trends | dock on/off | vendor (vendor-only mode on/off) | auto on/off | margin <pct> | log | restore | track <item> [cost] | status")
        say("Sharing: /amesh channel <name> [password] | guild | sync.   Scanning: /amesh scope money/all | swarm | focus <types>")
    end
end
