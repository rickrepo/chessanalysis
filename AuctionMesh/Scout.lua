-- AuctionMesh Scout: finds where the money actually moves, and keeps the
-- record that makes that visible.
--
--   1. COUNTS, kept per realm across sessions:
--        per item   radar reads, how often the cheapest listing was 20% or
--                   more under the market ("dips"), deals confirmed, their
--                   profit, deals that vanished before a buy and how long
--                   they lasted
--        per day    minutes with the panel working, reads, checks, deals,
--                   purchases, missed deals, failed purchases
--        per hour   of the day: reads, dips, deals (when to play)
--        reasons    why item checks were not deals, counted
--        deals      the last 400 deals seen, with what became of them
--
--   2. PRIME ITEMS. An item is prime when it is measured to sell fast
--      (30+ an hour over at least 10 minutes of watching), has a known
--      market price and is affordable. Prime items are ranked by
--          gold traded per hour x (how often it dips + 2%) x (1 + deals found)
--      so the list is the handful of items where a quick flip is realistic.
--
--   3. LASER FOCUS. With focus on, flips are only looked for on the focus
--      items, and each of them gets a full check every 30 seconds instead of
--      every 5 minutes. Vendor-price deals are never filtered: they are
--      guaranteed. Focus is either the prime list (picked from the counts
--      above) or your own list (items and categories), which can also be set
--      by pasting a code.
--
--   4. THE DAILY REPORT. One block of text with everything above, the trades
--      and the engine's figures, compact enough to paste into a chat.
--
-- Focus code:  AMF1:2589,2592,c7.5,m25,p150
--   a number = item id, cA.B = category (class.subclass), mNN = flip margin %,
--   pNN = minimum profit in copper.
local _, ns = ...
ns = ns or {}

local Scout = {}
ns.Scout = Scout

local floor, min, max = math.floor, math.min, math.max

Scout.cfg = {
    dipAt = 0.80,       -- cheapest listing at or under this share of the market = a dip
    dipGap = 3,         -- ... and at least this many copper under it (3c against 4c is rounding, not a dip)
    primeRate = 30,     -- units an hour an item must be measured to sell
    primeObs = 600,     -- seconds of watching before a rate is trusted
    primeTop = 12,      -- how many prime items are focused on
    primeMin = 3,       -- fewer than this: not enough measured yet, no focus
    days = 7,
}

Scout.now = function() return GetServerTime() end
Scout.hour = function()
    local h = GetGameTime and GetGameTime()
    return type(h) == "number" and h or tonumber(date("%H")) or 0
end
local function dayOf(t) return floor(t / 86400) end
local function plainName(key)
    return (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(key)) or ("item:" .. key)
end

function Scout:Attach(t)
    t.items, t.days, t.hours = t.items or {}, t.days or {}, t.hours or {}
    t.deals, t.reasons = t.deals or {}, t.reasons or {}
    self.d = t
    self.focusCache = nil
    self:Day()
end

-- today's record; old days are dropped
function Scout:Day()
    local d = self.d
    local today = dayOf(self.now())
    local rec = d.days[today]
    if not rec then
        rec = { reads = 0, checks = 0, deals = 0, profit = 0, bought = 0, spent = 0, gone = 0, fails = 0, secs = 0,
                sweeps = 0, req = 0, near = {} }
        d.days[today] = rec
        for k in pairs(d.days) do if k < today - self.cfg.days then d.days[k] = nil end end
        d.reasons = {} -- reasons are counted per day
    end
    return rec, today
end

local function item(self, key)
    local it = self.d.items[key]
    if not it then
        it = { r = 0, d = 0, n = 0, p = 0, g = 0, gs = 0 }
        self.d.items[key] = it
    end
    return it
end

---------------------------------------------------------------- counting

-- One radar read of one item whose market price is known.
function Scout:Read(key, price, market)
    if not self.d or not market or market <= 0 then return end
    local it = item(self, key)
    it.r = it.r + 1
    local hr = self.hour()
    local h = self.d.hours[hr] or { r = 0, d = 0, n = 0 }
    self.d.hours[hr] = h
    h.r = h.r + 1
    local day = self:Day()
    day.reads = day.reads + 1
    if price <= market * self.cfg.dipAt and market - price >= self.cfg.dipGap then
        it.d = it.d + 1
        h.d = h.d + 1
    end
end

-- One radar read finished; one background request was answered.
function Scout:Sweep()
    if not self.d then return end
    local day = self:Day()
    day.sweeps = (day.sweeps or 0) + 1
end
function Scout:Request()
    if not self.d then return end
    local day = self:Day()
    day.req = (day.req or 0) + 1
end

-- How close a failed check was: cheapest price against the most a deal could
-- pay. Tells whether a slightly lower profit bar would find many more deals.
Scout.NEAR = { { 1.05, "within 5%" }, { 1.15, "5-15% over" }, { 1.30, "15-30% over" }, { math.huge, "more than 30% over" } }

-- One full item check came back without a deal.
function Scout:NoDeal(key, reason)
    if not self.d then return end
    local day = self:Day()
    day.checks = day.checks + 1
    do
        local low, need = tostring(reason or ""):match("^cheapest is %$(%d+), market %$%d+: needs %$(%d+) or less")
        low, need = tonumber(low), tonumber(need)
        if low and need and need > 0 then
            day.near = day.near or {}
            for i, b in ipairs(self.NEAR) do
                if low / need <= b[1] then day.near[i] = (day.near[i] or 0) + 1; break end
            end
        end
    end
    -- the same reason with different numbers counts as one reason
    local r = tostring(reason or "?"):gsub("%$?%d+", "#"):sub(1, 70)
    self.d.reasons[r] = (self.d.reasons[r] or 0) + 1
end

-- A deal was confirmed against the live listing (first time it is seen).
function Scout:Deal(key, deal)
    if not self.d then return end
    local it = item(self, key)
    it.n, it.p = it.n + 1, it.p + (deal.profit or 0)
    local day = self:Day()
    day.checks, day.deals, day.profit = day.checks + 1, day.deals + 1, day.profit + (deal.profit or 0)
    local hr = self.hour()
    local h = self.d.hours[hr] or { r = 0, d = 0, n = 0 }
    self.d.hours[hr] = h
    h.n = h.n + 1
    local log = self.d.deals
    log[#log + 1] = { t = self.now(), k = key, kind = deal.kind, u = deal.units, c = deal.cost, s = deal.sell,
                      p = deal.profit, r = deal.rate and floor(deal.rate) or nil, o = "seen",
                      f = deal.instant and "radar" or "check" }
    while #log > 400 do table.remove(log, 1) end -- (80 until 3.31: too few to say which item loses most)
end

local function lastDeal(self, key)
    local log = self.d.deals
    for i = #log, 1, -1 do if log[i].k == key then return log[i] end end
end

-- A confirmed deal disappeared before it was bought, after `secs` seconds.
function Scout:Gone(key, secs)
    if not self.d then return end
    local it = item(self, key)
    it.g, it.gs = it.g + 1, it.gs + (secs or 0)
    local day = self:Day()
    day.gone = day.gone + 1
    local e = lastDeal(self, key)
    if e and e.o == "seen" then e.o, e.life = "gone", floor(secs or 0) end
end

function Scout:Bought(key, units, spent)
    if not self.d then return end
    local day = self:Day()
    day.bought, day.spent = day.bought + 1, day.spent + (spent or 0)
    local e = lastDeal(self, key)
    if e then e.o, e.bu, e.bc = "bought", units, spent end
end

function Scout:Fail(key, why)
    if not self.d then return end
    local day = self:Day()
    day.fails = day.fails + 1
    local e = key and lastDeal(self, key)
    if e and e.o == "seen" then e.o, e.why = "failed", tostring(why or "?"):sub(1, 40) end
end

-- Seconds the engine was working (auction house open, panel open).
function Scout:Online(secs)
    if not self.d or not secs or secs <= 0 or secs > 5 then return end
    local day = self:Day()
    day.secs = day.secs + secs
    if not day.gold0 and GetMoney then day.gold0 = GetMoney() end -- gold when the day's first session began
end

---------------------------------------------------------------- prime items

-- Everything known about one item, in one table.
function Scout:Facts(key, now)
    local St = ns.Store
    now = now or self.now()
    local it = self.d and self.d.items[key] or {}
    local rate, obs = St:Rate(key, 0)
    local f = {
        key = key, low = St.p[key], lowAt = St.t[key], market = St.fp[key], marketAt = St.ft[key],
        rate = rate, obs = obs, reads = it.r or 0, dips = it.d or 0, deals = it.n or 0, profit = it.p or 0,
        gone = it.g or 0, life = (it.g or 0) > 0 and (it.gs / it.g) or nil,
        churn = St.Churn and St:Churn(key) or nil,
    }
    f.value = (rate and f.market) and rate * f.market or nil
    f.dipShare = f.reads > 0 and f.dips / f.reads or 0
    return f
end

-- Is this item prime, and how does it rank? Returns score (nil = not prime), reason.
function Scout:Score(f, budget, vendorSold)
    local c = self.cfg
    if not f.rate or (f.obs or 0) < c.primeObs then return nil, "not watched long enough to know how fast it sells" end
    if f.rate < c.primeRate then return nil, ("sells only %d an hour"):format(floor(f.rate + 0.5)) end
    if not f.market or f.market <= 0 then return nil, "no market price yet" end
    if not f.low or f.low > budget then return nil, "costs more than you have" end
    if vendorSold then return nil, "vendors sell it, so its price cannot rise" end
    if ns.Learn and ns.Learn:Blocked(f.key) then return nil, "an auction of it expired recently" end
    return f.rate * f.market * (0.02 + f.dipShare) * (1 + min(f.deals, 5))
end

-- Prime items, best first: { key, score, facts... }. vendorSold = set of item ids.
function Scout:Prime(budget, vendorSold)
    local St, out = ns.Store, {}
    if not self.d then return out end
    local now = self.now()
    for key in pairs(St.vs or {}) do
        if key > 0 then
            local f = self:Facts(key, now)
            local s = self:Score(f, budget, vendorSold and vendorSold[key])
            if s then
                f.score = s
                out[#out + 1] = f
            end
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

-- One plain line on why an item is prime.
function Scout:Why(f, short)
    local parts = { ("%d sell an hour"):format(floor(f.rate + 0.5)) }
    if f.value then parts[#parts + 1] = short(floor(f.value)) .. " traded an hour" end
    if f.reads >= 20 then parts[#parts + 1] = ("under market in %d%% of reads"):format(floor(f.dipShare * 100 + 0.5)) end
    if f.deals > 0 then parts[#parts + 1] = ("%d deal%s found"):format(f.deals, f.deals == 1 and "" or "s") end
    return table.concat(parts, ", ")
end

---------------------------------------------------------------- laser focus

local function cfgOf() return AuctionMeshDB and AuctionMeshDB.cfg or {} end

Scout.MODES = { "off", "prime", "list" }
Scout.MODE_NAMES = { off = "Off: watch everything", prime = "Prime items, picked from activity", list = "My own list" }

-- The items flips are limited to right now: set, list, and a sentence for the
-- panel. set = nil means no limit (focus off, or not enough known yet).
function Scout:Focus(budget, vendorSold, classOf)
    local now = self.now()
    local fc = self.focusCache
    if fc and now - fc.at < 60 and fc.budget == budget then return fc.set, fc.list, fc.text end
    local cfg = cfgOf()
    local mode = cfg.focusMode or "off"
    local set, list, text = nil, {}, "Focus is off: every material is watched."
    if mode == "prime" then
        local prime = self:Prime(budget, vendorSold)
        local own = cfg.focusItems or {}
        if #prime >= self.cfg.primeMin or #own > 0 then
            set = {}
            if #prime >= self.cfg.primeMin then
                for i = 1, min(#prime, self.cfg.primeTop) do set[prime[i].key] = true; list[#list + 1] = prime[i].key end
            end
            local picked, extra = #list, 0
            -- your own watch list is always included, on top of what the addon picked
            for _, key in ipairs(own) do
                if not set[key] then set[key] = true; list[#list + 1] = key; extra = extra + 1 end
            end
            if picked == 0 then
                text = ("Focused on your own watch list (%d item%s). The addon adds its own picks once selling speed is measured."):format(extra, extra == 1 and "" or "s")
            else
                text = ("Focused on the %d items with the best measured activity%s."):format(picked,
                    extra > 0 and (", plus %d from your own watch list"):format(extra) or "")
            end
        else
            text = ("Focus is waiting: %d prime item%s so far, %d needed. Selling speed takes about %d minutes of watching to measure."):format(
                #prime, #prime == 1 and "" or "s", self.cfg.primeMin, floor(self.cfg.primeObs / 60))
        end
    elseif mode == "list" then
        set = {}
        for _, key in ipairs(cfg.focusItems or {}) do
            if not set[key] then set[key] = true; list[#list + 1] = key end
        end
        local cats = cfg.focusCats or {}
        if #cats > 0 and classOf then
            -- a category brings in its items that are measured to sell fast enough
            local want = {}
            for _, c in ipairs(cats) do want[c] = true end
            for _, f in ipairs(self:Prime(budget, vendorSold)) do
                local cl, sub = classOf(f.key)
                if cl and not set[f.key] and (want[cl .. "." .. (sub or 0)] or want[tostring(cl)]) then
                    set[f.key] = true; list[#list + 1] = f.key
                end
            end
        end
        if #list == 0 then
            set, text = nil, "Your focus list is empty: click an item, then 'Add to my focus list' in the drawer, or paste a focus code on the Setup tab."
        else
            text = ("Focused on your list: %d item%s."):format(#list, #list == 1 and "" or "s")
        end
    end
    self.focusCache = { at = now, budget = budget, set = set, list = list, text = text }
    return set, list, text
end

function Scout:Changed()
    self.focusCache = nil
    if ns.Sniper then ns.Sniper.lastBg = 0 end
    if ns.UI then ns.UI:Dirty() end
end

function Scout:SetMode(mode)
    local cfg = cfgOf()
    if not mode then
        local at = 1
        for i, m in ipairs(self.MODES) do if m == (cfg.focusMode or "off") then at = i end end
        mode = self.MODES[at % #self.MODES + 1]
    end
    if not self.MODE_NAMES[mode] then return end
    cfg.focusMode = mode
    self:Changed()
    return mode
end

function Scout:InList(key)
    for _, k in ipairs(cfgOf().focusItems or {}) do if k == key then return true end end
    return false
end

-- Adds or removes one item from your own focus list. Returns true if it is on the list now.
function Scout:Toggle(key)
    local cfg = cfgOf()
    cfg.focusItems = cfg.focusItems or {}
    local l = cfg.focusItems
    for i, k in ipairs(l) do
        if k == key then table.remove(l, i); self:Changed(); return false end
    end
    l[#l + 1] = key
    self:Changed()
    return true
end

-- Applies a focus code. Returns ok, sentence.
function Scout:ApplyCode(text)
    local body = tostring(text or ""):match("AMF1%s*:%s*([%w%.,;%s]+)")
    if not body then return false, "That is not a focus code. A code starts with AMF1: followed by item numbers." end
    local items, cats, seen, margin, minProfit = {}, {}, {}, nil, nil
    for tok in body:gmatch("[^,;%s]+") do
        local id = tonumber(tok) or tonumber(tok:match("^i(%d+)$"))
        local c, s = tok:match("^c(%d+)%.?(%d*)$")
        if id and id > 0 and not seen[id] then
            seen[id] = true; items[#items + 1] = id
        elseif c then
            cats[#cats + 1] = (s ~= "") and (c .. "." .. s) or c
        elseif tok:match("^m%d+$") then
            margin = tonumber(tok:sub(2))
        elseif tok:match("^p%d+$") then
            minProfit = tonumber(tok:sub(2))
        end
    end
    if #items == 0 and #cats == 0 and not margin and not minProfit then return false, "The focus code had nothing in it." end
    local cfg = cfgOf()
    local parts = {}
    if #items > 0 or #cats > 0 then
        cfg.focusItems, cfg.focusCats, cfg.focusMode = items, cats, "list"
        parts[#parts + 1] = ("focus on %d item%s%s"):format(#items, #items == 1 and "" or "s",
            #cats > 0 and (" and %d categor%s"):format(#cats, #cats == 1 and "y" or "ies") or "")
    end
    if margin and ns.Do then
        ns.Do.Margin(margin)
        parts[#parts + 1] = ("flip profit %d%%"):format(cfg.margin or margin)
    end
    if minProfit and minProfit > 0 and ns.UI then
        ns.UI:SetMinProfit(minProfit)
        parts[#parts + 1] = ("smallest deal %d copper"):format(minProfit)
    end
    self:Changed()
    return true, "Focus code applied: " .. table.concat(parts, ", ") .. "."
end

-- The current focus as a code (goes into the report, and can be pasted back).
function Scout:Code()
    local cfg = cfgOf()
    local t = {}
    for _, k in ipairs(cfg.focusItems or {}) do t[#t + 1] = tostring(k) end
    for _, c in ipairs(cfg.focusCats or {}) do t[#t + 1] = "c" .. c end
    return "AMF1:" .. table.concat(t, ",")
end

---------------------------------------------------------------- the daily report

local function num(v) return v and tostring(floor(v + 0.5)) or "-" end
local function pct(v) return v and ("%+d%%"):format(floor(v * 100 + 0.5)) or "-" end

-- money as plain text: 1g 23s 45c
local function coin(c)
    if not c then return "-" end
    c = floor(c + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out = (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. k .. "c"
    return (neg and "-" or "") .. out
end
local function mins(secs)
    if not secs then return "-" end
    return secs < 90 and (floor(secs + 0.5) .. "s") or (floor(secs / 60 + 0.5) .. " min")
end

-- THE SNAPSHOT: one short block for sharing right now. Where the money is,
-- what the mailbox held when it was last read, the settings, and what the
-- last snipes did. The daily report is the long version.
function Scout:Snapshot(o)
    o = o or {}
    local St, J, Se, S = ns.Store, ns.Journal, ns.Seller, ns.Sniper
    local now = self.now()
    local cfg = cfgOf()
    local L = {}
    local function add(...) L[#L + 1] = table.concat({ ... }, "") end
    local gold = o.gold or 0

    add("=== AUCTIONMESH SNAPSHOT v1 ===")
    add("addon ", tostring(o.version or "?"), " | realm ", tostring(o.realm or "?"), " | server time ", date("%Y-%m-%d %H:%M", now),
        " | this session ", mins(ns.sessionStart and (GetTime() - ns.sessionStart) or nil))

    -- MONEY
    local waiting, onway, nextIn, soldKeys = 0, 0, nil, {}
    if Se and Se.SalesMoney then waiting, onway, nextIn, soldKeys = Se:SalesMoney() end
    local cut = 1 - ((ns.Deals and ns.Deals.cfg.cut) or 0.05)
    local listed, listedLines = 0, {}
    for key, Lr in pairs(AuctionMeshDB.listed or {}) do
        if not soldKeys[key] then
            local net = floor((Lr.price or 0) * cut) * (Lr.qty or 0)
            listed = listed + net
            local low, t = St.p[key], St.t[key]
            local fresh = t and now - t < 900
            listedLines[#listedLines + 1] = ("  %d x %s at %s each (paid %s), listed %.1fh ago, cheapest other now %s%s"):format(Lr.qty or 0, plainName(key),
                coin(Lr.price), coin(Lr.cost), (now - (Lr.at or now)) / 3600, fresh and coin(low) or "not known",
                (fresh and low and low < (Lr.price or 0)) and " (UNDERCUT)" or "")
        end
    end
    local held, heldLines = 0, {}
    if Se and Se.Entries then
        local what = { AH = "to post", VENDOR = "sell to a vendor", MAIL = "in the mailbox", HOLD = "held: market below cost" }
        for _, e in ipairs(Se:Entries()) do
            if e.action ~= "LISTED" then
                local paid, sell, net = Se:Numbers(e)
                local worth = (net or 0) * e.count
                if e.action ~= "HOLD" then held = held + worth end
                heldLines[#heldLines + 1] = ("  %d x %s, paid %s each, %s, worth %s when sold"):format(e.count, plainName(e.key),
                    coin(paid), what[e.action] or tostring(e.action), coin(worth))
            end
        end
    end
    add("")
    add("MONEY")
    add("gold in hand: ", coin(gold))
    local ms = AuctionMeshDB.mailSeen
    add("sale gold waiting in the mailbox: ", coin(waiting), ms and ("  (mailbox last read " .. mins(now - ms.at) .. " ago)") or "  (mailbox not read yet)")
    add("sold, gold on its way: ", coin(onway), nextIn and ("  (next in " .. mins(nextIn) .. ")") or "")
    for _, r in ipairs(S and S.ownSoldPay or {}) do
        local left = r.due - GetTime()
        if left > 0 then add("  ", r.key and plainName(r.key) or "an auction", ": ", coin(r.amount), " in ", mins(left)) end
    end
    add("listed, not sold yet: ", coin(listed))
    for _, l in ipairs(listedLines) do add(l) end
    add("bought, not listed: ", coin(held))
    for _, l in ipairs(heldLines) do add(l) end
    do  -- the posting fees still owed, and whether the addon has gone to vendor deals only because of them
        local S = ns.Sniper
        local fees, items = 0, 0
        if S and S.FeesOwed then fees, items = S:FeesOwed() end
        add("posting fees owed for what is bought and not listed: ", coin(fees), " (", tostring(items), " item(s))",
            (S and S.lowGold) and " | LOW GOLD: flips are off until the gold in hand covers them" or "")
    end
    add("TOTAL when it has all sold: ", coin(gold + waiting + onway + listed + held))
    do
        local r = self:Day()
        add("gold at the start of today: ", coin(r.gold0), " | profit banked this session: ", coin((AuctionMeshDB.realized or 0) - (ns.realizedAtLogin or AuctionMeshDB.realized or 0)),
            " | banked all-time: ", coin(AuctionMeshDB.realized or 0))
    end

    -- MAILBOX
    add("")
    if ms then
        add("MAILBOX (as read ", mins(now - ms.at), " ago): ", ms.mails or 0, " mail(s), sale gold ", coin(ms.gold), ", ", ms.pending or 0, " sale(s) still to be paid")
        local parts = {}
        for id, n in pairs(ms.items or {}) do parts[#parts + 1] = n .. " x " .. plainName(id) end
        table.sort(parts)
        add("  items in it: ", #parts > 0 and table.concat(parts, ", ") or "none")
    else
        add("MAILBOX: not read yet (open a mailbox once)")
    end

    -- SETTINGS
    add("")
    add("SETTINGS")
    add("smallest profit ", coin(cfg.minProfit), " | flip margin ", tostring(cfg.margin), "% | flips ", cfg.flips ~= false and "on" or "off (vendor deals only)",
        " | radar reads: ", tostring(cfg.scope or "mats"), " | laser focus: ", tostring(cfg.focusMode or "off"),
        " | focus items re-read every ", tostring(ns.Sniper and ns.Sniper.FocusEvery and ns.Sniper.FocusEvery() or "?"), "s")
    add("unsold auctions may hold ", tostring(cfg.maxTied or 50), "% | buy with: ", (ns.UI and ns.UI.BuyMode and ns.UI.BUY_NAMES[ns.UI.BuyMode()] or "?"), (cfg.buyKey and (" (key " .. cfg.buyKey .. ")") or ""),
        " | one-click buy: ", cfg.autoConfirm == false and "BLOCKED by the game (second input needed)" or (cfg.autoTried and "works" or "on, not tried yet"),
        " | auto-adjust ", cfg.tune ~= false and "on" or "off", " | posting fee comes back: ", cfg.feeBack == nil and "not known yet" or tostring(cfg.feeBack))
    do
        local parts = {}
        for _, k in ipairs(cfg.focusItems or {}) do parts[#parts + 1] = plainName(k) .. "(" .. k .. ")" end
        if #parts > 0 then add("own watch list: ", table.concat(parts, ", ")) end
        parts = {}
        for k, v in pairs(cfg.itemMin or {}) do parts[#parts + 1] = plainName(k) .. "(" .. k .. ") " .. coin(v) end
        table.sort(parts)
        if #parts > 0 then add("smallest profit per item: ", table.concat(parts, ", ")) end
        parts = {}
        for k in pairs(cfg.ignore or {}) do parts[#parts + 1] = plainName(k) .. "(" .. k .. ")" end
        table.sort(parts)
        if #parts > 0 then add("ignored items: ", table.concat(parts, ", ")) end
    end
    if S and S.StakeKey and S:StakeKey() then
        local st = S.stake or {}
        add("stake-out: ", plainName(S:StakeKey()), "(", S:StakeKey(), "), ", st.max and ("buys at " .. coin(st.max) .. " or less") or ("waiting: " .. tostring(st.why or "reading its market first")),
            " | this session: asked ", st.asked or 0, " time(s), bought ", st.bought or 0, st.lastPrice and (" | last price " .. coin(st.lastPrice)) or "")
    end
    do  -- stake-outs so far, per item, and what the Picks tab says
        local parts = {}
        for k, r in pairs(AuctionMeshDB.stakeLog or {}) do
            parts[#parts + 1] = plainName(k) .. "(" .. k .. ") asked " .. (r.asked or 0) .. ", bought " .. (r.bought or 0)
        end
        table.sort(parts)
        if #parts > 0 then add("stake-outs so far: ", table.concat(parts, "; ")) end
        local P = ns.Picks
        local r = P and P.Compute and P:Compute()
        if r then
            add("PICKS (", r.all, " deals seen in the last ", r.hours, "h, got ", coin(r.gotAll), "): ",
                not r.enough and "not enough seen yet" or r.best and ("try a stake-out on " .. plainName(r.best.key)) or "keep the radar, no item is worth a stake-out")
            for _, it in ipairs(r.list) do
                add("  ", plainName(it.key), "(", it.key, "): ", it.n, " deals, got ", it.got, ", missed ", it.miss, " worth ", coin(it.missP),
                    ", gone ", it.gone, it.life and (" (lasted " .. ("%.0f"):format(it.life) .. "s)") or "",
                    " | radar elsewhere made ", coin(it.givenUp), it.max and (" | would buy at " .. coin(it.max)) or "", it.low and (" | cheapest " .. coin(it.low)) or "")
            end
        end
    end
    if ns.Auto then
        local lines = ns.Auto:Lines(6)
        add("auto-adjust (", cfg.tune ~= false and "on" or "off", "): ", #lines == 0 and "no changes yet" or "last changes, newest first")
        for _, l in ipairs(lines) do add("  ", date("%H:%M", l.t), " ", l.m) end
    end
    if o.code then add("settings code (Claude sends back a changed one; paste it into the box on the Setup tab): ", o.code) end

    -- SNIPING
    add("")
    local t = S and S.tally or {}
    add("SNIPING this session: ", t.won or 0, " got, ", t.lost or 0, " missed after an input, ", t.gone or 0, " gone before any input | snipe box armed ",
        t.armed or 0, " time(s), ", t.wheel or 0, " purchase(s) started with the wheel")
    do
        local m = S and S.underMin
        if m and GetTime() - m.at < 600 then
            add("in the last 10 min ", m.n, " deal(s) were hidden by the smallest-profit setting (best: ", coin(m.best), ")")
        end
        local muted = {}
        for key, till in pairs(S and S.muted or {}) do
            if till > GetTime() then muted[#muted + 1] = plainName(key) .. " (" .. mins(till - GetTime()) .. " more)" end
        end
        if #muted > 0 then add("muted after 5 misses in a row: ", table.concat(muted, ", ")) end
    end
    add("last outcomes, newest first (time | result | input came this long after the deal appeared | input | what happened):")
    do
        local list = AuctionMeshDB.outcomes or {}
        if #list == 0 then add("  none yet") end
        for i = #list, max(1, #list - 19), -1 do
            local e = list[i]
            add("  ", date("%H:%M:%S", e.t), " | ", e.k == "won" and "GOT" or e.k == "lost" and "MISSED" or "GONE", " | ",
                e.r and ("%.1fs"):format(e.r) or "-", " | ", tostring(e.v or "-"), " | ", tostring(e.m))
        end
    end

    -- WHY NOT
    add("")
    add("WHY CHECKS WERE NOT DEALS today (top 8; # stands for a number):")
    do
        local rs = {}
        for r, n in pairs(self.d.reasons or {}) do rs[#rs + 1] = { r = r, n = n } end
        table.sort(rs, function(a, b) return a.n > b.n end)
        for i = 1, min(#rs, 8) do add("  ", rs[i].n, " x ", rs[i].r) end
        if #rs == 0 then add("  nothing recorded yet") end
    end

    -- PURCHASES
    add("")
    add("LAST PURCHASES, newest first (up to 12):")
    if J then
        local trades = J:Trades()
        if #trades == 0 then add("  none yet") end
        for i = 1, min(#trades, 12) do
            local tr = trades[i]
            local left = J.left(tr)
            local made = J.realized(tr)
            local state
            if left <= 0 and (tr.sold or 0) + (tr.vend or 0) > 0 then state = "SOLD, profit " .. coin(made or 0)
            elseif left <= 0 then state = "not found, not counted"
            elseif (tr.listed or 0) > 0 and soldKeys[tr.key] then state = "SOLD, gold on its way"
            elseif (tr.listed or 0) > 0 then state = ("listed at %s, not sold"):format(coin(tr.price))
            else state = "not sold, not listed" end
            add(("  %s x%d at %s each, %.1fh ago: %s"):format(tostring(tr.name), tr.qty, coin(tr.cost), (now - (tr.at or now)) / 3600, state))
        end
    end

    -- THROTTLE WATCH: everything that made a request wait this session, and why
    add("")
    if ns.Watch then for _, l in ipairs(ns.Watch:Lines()) do add(l) end end

    -- ENGINE
    add("")
    do
        local r = self:Day()
        local cyc = ns.Tuner and ns.Tuner.d and ns.Tuner.d.cycle
        add("ENGINE today: ", num(r.secs / 60), " min working, radar read ", r.sweeps or 0, " times",
            (r.sweeps or 0) > 0 and (" (every %.1fs on average)"):format(r.secs / r.sweeps) or "",
            cyc and (", server allows one request every %.2fs"):format(cyc) or "",
            ", ", r.checks or 0, " item checks, ", r.deals or 0, " deals found, ", r.bought or 0, " bought, ", r.gone or 0, " gone, ", r.fails or 0, " failed")
    end
    add("=== END OF SNAPSHOT ===")
    return table.concat(L, "\n")
end

-- One block of text for sharing. All money is in copper (100 = 1 silver).
function Scout:Report(o)
    o = o or {}
    local St, J, d = ns.Store, ns.Journal, self.d
    local now = self.now()
    local cfg = cfgOf()
    local L = {}
    local function add(...) L[#L + 1] = table.concat({ ... }, "") end
    local budget = o.gold or 0

    add("=== AUCTIONMESH DAILY REPORT v2 ===")
    add("addon ", tostring(o.version or "?"), " | realm ", tostring(o.realm or "?"), " | server time ", date("%Y-%m-%d %H:%M", now),
        " | gold ", tostring(budget), "c")
    add("All money is in copper (100 = 1 silver, 10000 = 1 gold).")
    add("settings: minProfit=", tostring(cfg.minProfit), " margin=", tostring(cfg.margin), "% flips=", tostring(cfg.flips ~= false),
        " scope=", tostring(cfg.scope), " focus=", tostring(cfg.focusMode or "off"), " tune=", tostring(cfg.tune ~= false),
        " postingFeeComesBack=", cfg.feeBack == nil and "unknown (no sale yet)" or tostring(cfg.feeBack))
    if ns.Sniper and ns.Sniper.tally then
        local t = ns.Sniper.tally
        add("snipes this session: ", t.won, " got, ", t.lost, " missed after a click, ", t.gone, " gone before a click")
    end
    do
        local _, list, text = self:Focus(budget, o.vendorSold, o.classOf)
        local names = {}
        for i = 1, min(#list, 20) do names[#names + 1] = plainName(list[i]) .. "(" .. list[i] .. ")" end
        add("focus: ", text, #names > 0 and (" " .. table.concat(names, ", ")) or "")
        add("focus code: ", self:Code())
    end

    add("")
    add("-- DAYS (newest first): minutes working, radar sweeps, requests answered, item reads, item checks, deals found and their profit, purchases, copper spent, deals gone before a buy, failed buys, gold at the day's start")
    add("day | min | sweeps | requests | reads | checks | deals | dealProfit | bought | spent | gone | fails | goldStart")
    do
        local _, today = self:Day()
        for dd = today, today - self.cfg.days, -1 do
            local r = d.days[dd]
            if r then
                add(dd == today and "today" or ("-" .. (today - dd) .. "d"), " | ", num(r.secs / 60), " | ", (r.sweeps or 0), " | ", (r.req or 0), " | ", r.reads,
                    " | ", r.checks, " | ", r.deals, " | ", r.profit, " | ", r.bought, " | ", r.spent, " | ", r.gone, " | ", r.fails, " | ", num(r.gold0))
            end
        end
    end

    do  -- how much of the request budget was used, and how often the radar came round
        local r = self:Day()
        local cyc = ns.Tuner and ns.Tuner.d and ns.Tuner.d.cycle
        if r.secs > 60 and cyc then
            add(("today: %d%% of the request budget used; radar came round every %.1fs on average"):format(
                floor((r.req or 0) * cyc / r.secs * 100 + 0.5), (r.sweeps or 0) > 0 and r.secs / r.sweeps or 0))
        end
    end

    if ns.Sniper and ns.Sniper.Capital then
        local c = ns.Sniper:Capital()
        add(("capital: gold %d, out of reach %d (listed %d, sold not paid out %d, sale gold in mailbox %d); unsold auctions may hold %d%%, room left %d; next pay-out in %s"):format(
            c.gold, c.tied, c.listed, c.onway, c.waiting, floor(ns.Deals.cfg.maxTied * 100 + 0.5), c.room, c.nextIn and (floor(c.nextIn / 60) .. " min") or "-"))
    end

    add("")
    add("-- MY AUCTIONS NOW: listed, cheapest listing now, undercut or not, hours since posting")
    add("item(id) | qty | my price | cost each | cheapest now | state | hours listed")
    for key, Lr in pairs(AuctionMeshDB.listed or {}) do
        local low, t = St.p[key], St.t[key]
        local fresh = t and now - t < 900
        add(plainName(key), "(", key, ") | ", num(Lr.qty), " | ", num(Lr.price), " | ", num(Lr.cost), " | ", fresh and num(low) or "-", " | ",
            (fresh and low and low < (Lr.price or 0)) and "UNDERCUT" or (fresh and "cheapest" or "unknown"), " | ", ("%.1f"):format((now - (Lr.at or now)) / 3600))
    end
    for key, f in pairs(AuctionMeshDB.flips or {}) do
        add(plainName(key), "(", key, ") | ", num(f.units), " | not listed | ", f.unknownCost and "?" or num(f.cost), " | ", num(St.p[key]), " | in bags or mail (", tostring(f.kind), ") | -")
    end

    add("")
    add("-- TRADES (newest first, up to 30): bought, where it is, what came back")
    add("item(id) | qty | cost each | planned sell | listed qty@price | sold qty@price | vendored qty | received | profit made | expired x | hours to sell | bought")
    if J then
        local s = J:Totals()
        add("totals: ", s.trades, " trades, ", s.finished, " finished, ", s.open, " open, profit made ", s.profit, ", spent ", s.spent,
            ", banked all-time ", tostring(AuctionMeshDB.realized or 0))
        local trades = J:Trades()
        for i = 1, min(#trades, 30) do
            local t = trades[i]
            local made = J.realized(t)
            add(tostring(t.name), "(", t.key, ") | ", t.qty, " | ", num(t.cost), " | ", num(t.plan), " | ", (t.listed or 0), "@", num(t.price),
                " | ", (t.sold or 0), "@", num(t.soldPrice), " | ", (t.vend or 0), " | ", (t.got or 0), " | ", made and tostring(made) or "-",
                " | ", (t.expired or 0), " | ", (t.soldAt and t.listedAt) and ("%.1f"):format((t.soldAt - t.listedAt) / 3600) or "-",
                " | ", ("%.1fh ago"):format((now - (t.at or now)) / 3600), (t.lost or 0) > 0 and (" | lost " .. t.lost .. ": " .. tostring(t.lostWhy)) or "")
        end
    end

    add("")
    add("-- DEALS SEEN (newest first, up to 40): what was offered and what became of it")
    add("found by: check = the radar then an item check; radar = straight from the radar, no item check")
    add("ago | item(id) | kind | units | pay | sell each | profit | sells/h | found by | outcome")
    for i = #d.deals, max(1, #d.deals - 39), -1 do
        local e = d.deals[i]
        add(("%.1fh"):format((now - e.t) / 3600), " | ", plainName(e.k), "(", e.k, ") | ", tostring(e.kind), " | ", num(e.u), " | ", num(e.c), " | ", num(e.s),
            " | ", num(e.p), " | ", num(e.r), " | ", tostring(e.f or "-"), " | ", tostring(e.o), e.life and (" after " .. e.life .. "s") or "", e.why and (" (" .. e.why .. ")") or "")
    end

    add("")
    add("-- WHY CHECKS WERE NOT DEALS (today; # stands for a number)")
    do
        local rs = {}
        for r, n in pairs(d.reasons) do rs[#rs + 1] = { r = r, n = n } end
        table.sort(rs, function(a, b) return a.n > b.n end)
        for i = 1, min(#rs, 15) do add(rs[i].n, " x ", rs[i].r) end
        local near, parts = self:Day().near or {}, {}
        for i, b in ipairs(self.NEAR) do parts[#parts + 1] = b[2] .. ": " .. (near[i] or 0) end
        add("how far the cheapest listing was from a deal: ", table.concat(parts, ", "))
    end

    add("")
    add("-- HOURS OF THE DAY (server time, all days): reads with a known market, dips, deals")
    do
        local parts = {}
        for h = 0, 23 do
            local r = d.hours[h]
            if r and r.r > 0 then parts[#parts + 1] = ("%02d: %d/%d/%d"):format(h, r.r, r.d, r.n) end
        end
        add(table.concat(parts, "  "))
    end

    add("")
    add("-- MARKET: the 40 items with the most copper traded per hour, then every other item with a dip or a deal on record")
    add("sold/h = units eaten from the cheap end between full listings (real sales, may under-count). churn/h = units leaving the whole listing between radar reads (sales + cancelled auctions).")
    add("item(id) | low | market | vendor | sold/h | watched min | traded/h | churn/h | 6h | 24h | 24h range | reads | dips | deals | dealProfit | gone | avg life s | prime")
    do
        local all, shown = {}, {}
        local have = {}
        for key in pairs(St.vs or {}) do if key > 0 then all[#all + 1] = self:Facts(key, now); have[key] = true end end
        for key, it in pairs(d.items) do
            if not have[key] and ((it.d or 0) > 0 or (it.n or 0) > 0) then all[#all + 1] = self:Facts(key, now); have[key] = true end
        end
        for key in pairs(St.cs or {}) do
            if key > 0 and not have[key] then all[#all + 1] = self:Facts(key, now) end
        end
        -- real sales first; among items with no measured sales yet, the busiest listings
        local function weight(f) return (f.value or 0) * 1000 + (f.churn or 0) * (f.market or f.low or 0) / 1000 end
        table.sort(all, function(a, b) return weight(a) > weight(b) end)
        local function line(f)
            local lo, hi = St:Range(f.key, now, 24)
            local score, why = self:Score(f, budget, o.vendorSold and o.vendorSold[f.key])
            add(plainName(f.key), "(", f.key, ") | ", num(f.low), " | ", num(f.market), " | ", num(o.vendorOf and o.vendorOf(f.key)), " | ", num(f.rate),
                " | ", num(f.obs and f.obs / 60), " | ", num(f.value), " | ", num(f.churn), " | ", pct(St:Trend(f.key, now, 6)), " | ", pct(St:Trend(f.key, now, 24)),
                " | ", lo and (num(lo) .. "-" .. num(hi)) or "-", " | ", f.reads, " | ", f.dips, " | ", f.deals, " | ", f.profit, " | ", f.gone,
                " | ", num(f.life), " | ", score and "PRIME" or ("no: " .. tostring(why)))
        end
        for i, f in ipairs(all) do
            if i <= 40 or f.dips > 0 or f.deals > 0 then
                if #shown < 120 then shown[#shown + 1] = f; line(f) end
            end
        end
        add("(", #all, " items measured, ", #shown, " shown)")
    end

    add("")
    add("-- ENGINE")
    if ns.Tuner then for _, l in ipairs(ns.Tuner:Lines()) do add(l[1], ": ", l[2]) end end
    do
        local M = ns.measure and ns.measure.last
        if M then add("radar read: ", M.items, " items in ", M.requests, " requests, largest page ", M.pageMax, ", re-read every ", tostring(ns.Swarm and ns.Swarm.cfg.fresh), "s") end
        if ns.Learn then add(ns.Learn:Summary()) end
        if o.errors then add("errors this session: ", o.errors) end
    end
    add("=== END OF REPORT ===")
    return table.concat(L, "\n")
end

return Scout
