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
--        deals      the last 80 deals seen, with what became of them
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
        rec = { reads = 0, checks = 0, deals = 0, profit = 0, bought = 0, spent = 0, gone = 0, fails = 0, secs = 0 }
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
    if price <= market * self.cfg.dipAt then
        it.d = it.d + 1
        h.d = h.d + 1
    end
end

-- One full item check came back without a deal.
function Scout:NoDeal(key, reason)
    if not self.d then return end
    local day = self:Day()
    day.checks = day.checks + 1
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
                      p = deal.profit, r = deal.rate and floor(deal.rate) or nil, o = "seen" }
    while #log > 80 do table.remove(log, 1) end
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
        if #prime >= self.cfg.primeMin then
            set = {}
            for i = 1, min(#prime, self.cfg.primeTop) do set[prime[i].key] = true; list[#list + 1] = prime[i].key end
            text = ("Focused on the %d items with the best measured activity."):format(#list)
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

-- One block of text for sharing. All money is in copper (100 = 1 silver).
function Scout:Report(o)
    o = o or {}
    local St, J, d = ns.Store, ns.Journal, self.d
    local now = self.now()
    local cfg = cfgOf()
    local L = {}
    local function add(...) L[#L + 1] = table.concat({ ... }, "") end
    local budget = o.gold or 0

    add("=== AUCTIONMESH DAILY REPORT v1 ===")
    add("addon ", tostring(o.version or "?"), " | realm ", tostring(o.realm or "?"), " | server time ", date("%Y-%m-%d %H:%M", now),
        " | gold ", tostring(budget), "c")
    add("All money is in copper (100 = 1 silver, 10000 = 1 gold).")
    add("settings: minProfit=", tostring(cfg.minProfit), " margin=", tostring(cfg.margin), "% flips=", tostring(cfg.flips ~= false),
        " scope=", tostring(cfg.scope), " focus=", tostring(cfg.focusMode or "off"), " tune=", tostring(cfg.tune ~= false))
    do
        local _, list, text = self:Focus(budget, o.vendorSold, o.classOf)
        local names = {}
        for i = 1, min(#list, 20) do names[#names + 1] = plainName(list[i]) .. "(" .. list[i] .. ")" end
        add("focus: ", text, #names > 0 and (" " .. table.concat(names, ", ")) or "")
        add("focus code: ", self:Code())
    end

    add("")
    add("-- DAYS (newest first): minutes working, radar reads, item checks, deals found and their profit, purchases, copper spent, deals gone before a buy, failed buys")
    add("day | min | reads | checks | deals | dealProfit | bought | spent | gone | fails")
    do
        local _, today = self:Day()
        for dd = today, today - self.cfg.days, -1 do
            local r = d.days[dd]
            if r then
                add(dd == today and "today" or ("-" .. (today - dd) .. "d"), " | ", num(r.secs / 60), " | ", r.reads, " | ", r.checks, " | ", r.deals,
                    " | ", r.profit, " | ", r.bought, " | ", r.spent, " | ", r.gone, " | ", r.fails)
            end
        end
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
    add("ago | item(id) | kind | units | pay | sell each | profit | sells/h | outcome")
    for i = #d.deals, max(1, #d.deals - 39), -1 do
        local e = d.deals[i]
        add(("%.1fh"):format((now - e.t) / 3600), " | ", plainName(e.k), "(", e.k, ") | ", tostring(e.kind), " | ", num(e.u), " | ", num(e.c), " | ", num(e.s),
            " | ", num(e.p), " | ", num(e.r), " | ", tostring(e.o), e.life and (" after " .. e.life .. "s") or "", e.why and (" (" .. e.why .. ")") or "")
    end

    add("")
    add("-- WHY CHECKS WERE NOT DEALS (today; # stands for a number)")
    do
        local rs = {}
        for r, n in pairs(d.reasons) do rs[#rs + 1] = { r = r, n = n } end
        table.sort(rs, function(a, b) return a.n > b.n end)
        for i = 1, min(#rs, 15) do add(rs[i].n, " x ", rs[i].r) end
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
    add("item(id) | low | market | vendor | sells/h | watched min | traded/h | 6h | 24h | 24h range | reads | dips | deals | dealProfit | gone | avg life s | prime")
    do
        local all, shown = {}, {}
        for key in pairs(St.vs or {}) do if key > 0 then all[#all + 1] = self:Facts(key, now) end end
        for key, it in pairs(d.items) do
            if not (St.vs and St.vs[key]) and ((it.d or 0) > 0 or (it.n or 0) > 0) then all[#all + 1] = self:Facts(key, now) end
        end
        table.sort(all, function(a, b) return (a.value or 0) > (b.value or 0) end)
        local function line(f)
            local lo, hi = St:Range(f.key, now, 24)
            local score, why = self:Score(f, budget, o.vendorSold and o.vendorSold[f.key])
            add(plainName(f.key), "(", f.key, ") | ", num(f.low), " | ", num(f.market), " | ", num(o.vendorOf and o.vendorOf(f.key)), " | ", num(f.rate),
                " | ", num(f.obs and f.obs / 60), " | ", num(f.value), " | ", pct(St:Trend(f.key, now, 6)), " | ", pct(St:Trend(f.key, now, 24)),
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
        if o.sharing then add("sharing: ", o.sharing) end
        if o.errors then add("errors this session: ", o.errors) end
    end
    add("=== END OF REPORT ===")
    return table.concat(L, "\n")
end

return Scout
