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
local DEFAULTS = { channel = "", password = "", route = "channel", focus = "tradegoods", scope = "money",
    snipeAuto = true, margin = 40, minProfit = 20, flips = true, autoOpen = true, autoScan = true }

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
        local pruned = Store:Prune(GetServerTime() - Sync.cfg.maxAge)
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
        if db.cfg.v ~= 3 then db.cfg.v, db.cfg.focus, db.cfg.scope = 3, "tradegoods", "money" end
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
        if rest == "clear" then ns.Diag:Clear(); say("Log cleared.") else ns.Diag:Show() end
    elseif cmd == "restore" then
        Seller:Restore()
    elseif cmd == "track" then
        -- /amesh track [item link] [cost per unit in copper]
        local id = tonumber(rest:match("item:(%d+)")) or tonumber(rest:match("^(%d+)"))
        local cost = tonumber(rest:match("%]|h|r%s*(%d+)%s*$") or rest:match("^%d+%s+(%d+)%s*$"))
        if id then Seller:Track(id, cost) else say("Usage: /amesh track [item link] [cost in copper], or drag the item onto the AuctionMesh window.") end
    elseif cmd == "flips" then
        cfg.flips = (rest ~= "off")
        Deals.cfg.flips = cfg.flips
        Sniper.verified = {}
        say(cfg.flips and "Flips ON: resale deals are shown too (not guaranteed)." or "Flips OFF: only guaranteed vendor deals.")
    elseif cmd == "auto" then
        cfg.autoOpen = (rest ~= "off"); cfg.snipeAuto = cfg.autoOpen; cfg.autoScan = cfg.autoOpen
        say(cfg.autoOpen and "Opens and scans automatically at the Auction House." or "Automatic open/scan off. Use /amesh.")
    elseif cmd == "margin" then
        local m = tonumber(rest)
        if m then cfg.margin = m; Deals.cfg.margin = m / 100 end
        say(("Flip margin: %d%% profit after the AH cut and deposit (vendor deals use %d%%)."):format(cfg.margin, Deals.cfg.vendorMargin * 100))
    elseif cmd == "minprofit" then
        local m = tonumber(rest)
        if m then cfg.minProfit = m; Deals.cfg.minProfit = m end
        say("Minimum profit per deal: " .. money(cfg.minProfit))
    elseif cmd == "scope" then
        if rest == "all" or rest == "money" then
            cfg.scope, Swarm.scope = rest, rest
            Swarm.units = {}
            if Swarm.active then Swarm:BuildUnits() end
        end
        say(cfg.scope == "all" and "Scanning the whole auction house." or
            "Scanning only money-makers: trade goods, reagents, consumables, gems, enhancements. (/amesh scope all for everything)")
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
        say("/amesh = open the window | flips on/off | auto on/off | margin <pct> | log | restore | track <item> [cost] | status")
        say("Sharing: /amesh channel <name> [password] | guild | sync.   Scanning: /amesh scope money/all | swarm | focus <types>")
    end
end
