-- AuctionMesh Auto: settings that adjust themselves from what really happens.
--
-- Fixed, bounded rules fed by counts the addon already keeps. Every change is
-- written down with its reason (Setup tab, Snapshot), and the Auto-adjust
-- switch freezes all of it. A setting you change yourself (or import) is left
-- alone for 30 minutes.
--
--   1. SMALLEST PROFIT. Looked at every 10 minutes of working time:
--        bigger deals had to wait behind a smaller purchase       -> 25% higher
--        deals hidden by the minimum, and no bigger deal waited   -> 25% lower
--      Never under 20c, never over 2% of everything you own (at least 1s).
--      A small deal has one measurable cost: while it is being bought (about
--      two seconds of auction house lock) a bigger one that appears has to
--      wait, and deals last about a second. That is counted: a deal that
--      appears while a purchase of a smaller one is in progress. (The rule
--      used to be "15 deals shown in 10 minutes is more than can be acted
--      on": true when buying with clicks, not with the wheel or a key. In a
--      busy market it raised the minimum a quarter every 10 minutes and
--      nothing brought it back, so a session offered less and less.)
--   2. THE RADAR'S QUIET TIME after a deal appears (so that your input is not
--      queued behind a radar read). While you roll the wheel your input comes
--      within a notch: 1 second. Otherwise it follows how fast your last
--      inputs really came (their median plus a second), between 2 and 6.
local _, ns = ...
ns = ns or {}

local Auto = {}
ns.Auto = Auto

local floor, min, max = math.floor, math.min, math.max
Auto.cfg = { every = 600, manualHold = 1800, manyHidden = 3, crowded = 3, step = 0.25, minFloor = 20 }

function Auto:Attach(t)
    t.log = t.log or {}
    t.rest, t.streak = nil, nil -- (an earlier rule; no longer used)
    self.d = t
    self.win = { at = GetTime(), shown = 0, worked = 0 }
end

function Auto:Enabled()
    local cfg = AuctionMeshDB and AuctionMeshDB.cfg
    return self.d ~= nil and not (cfg and cfg.tune == false)
end

local function coin(c)
    c = floor((c or 0) + 0.5)
    local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
    return (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. k .. "c"
end

function Auto:Note(text)
    local d = self.d
    if not d then return end
    d.log[#d.log + 1] = { t = GetServerTime(), m = text }
    while #d.log > 20 do table.remove(d.log, 1) end
    if ns.Log then ns.Log("AUTO-ADJUST %s", text) end
    if ns.UI then ns.UI:Notice("|cff33ccccAuto-adjust:|r " .. text, true) end
    if ns.Print then ns.Print("|cff33ccccAuto-adjust:|r " .. text) end
end

-- THE OLD RULE'S RAISES, TAKEN BACK (once, at the update). Every raise is in
-- the log with its reason. The newest run of "N deals shown ... more than can
-- be acted on" raises is undone: the smallest profit goes back to what it was
-- before the first of them, provided nothing else has changed it since.
-- Returns the value to restore, or nil.
local function uncoin(t)
    t = tostring(t or "")
    return (tonumber(t:match("(%d+)g")) or 0) * 10000 + (tonumber(t:match("(%d+)s")) or 0) * 100 + (tonumber(t:match("(%d+)c")) or 0)
end
function Auto:OldRaises(current)
    local log = self.d and self.d.log
    if not log or #log == 0 then return nil end
    local back, last
    for i = #log, 1, -1 do
        local from, to = tostring(log[i].m):match("^smallest profit (.-) > (.-): %d+ deals shown in the last 10 minutes, more than can be acted on$")
        if not from then break end
        if not last then
            last = uncoin(to)
            if last ~= current then return nil end -- changed since (by you, or by a settings code): left alone
        end
        back = uncoin(from)
    end
    if back and back > 0 and back < current then
        self:Note(("smallest profit %s > %s: raised by the old rule (many deals shown), taken back"):format(coin(current), coin(back)))
        return back
    end
    return nil
end

-- You changed this setting yourself: it is yours for the next 30 minutes.
function Auto:Manual(what)
    if self.setting or not self.d then return end
    self.d.manual = self.d.manual or {}
    self.d.manual[what] = GetServerTime()
end

function Auto:Held(what)
    local m = self.d and self.d.manual and self.d.manual[what]
    return m ~= nil and GetServerTime() - m < self.cfg.manualHold
end

-- A deal was shown (called by the sniper, with the deal).
function Auto:Shown(key, deal)
    local w = self.win
    if not w then return end
    w.shown = w.shown + 1
    -- it appeared while a purchase of another, smaller deal was in progress: it has to wait for the lock
    local S = ns.Sniper
    local b = S and S.buying
    if deal and b and b.key ~= key and b.deal and (deal.profit or 0) > (b.deal.profit or 0) then
        w.crowd = (w.crowd or 0) + 1
        if ns.Log then
            ns.Log("AUTO-ADJUST noted: %s (profit %d) appeared while %s (profit %d) was being bought: it has to wait (%d in this 10 minutes)",
                tostring(key), deal.profit or 0, tostring(b.key), b.deal.profit or 0, w.crowd)
        end
    end
end

-- Seconds of working time (auction house and panel open), called with the engine's own tick.
function Auto:Worked(secs)
    local w = self.win
    if not w then return end
    w.worked = w.worked + secs
    if w.worked >= self.cfg.every then self:Review() end
end

-- everything you own, for the upper bound of the smallest profit
local function worth()
    local c = ns.Sniper and ns.Sniper.Capital and ns.Sniper:Capital()
    return c and c.worth or GetMoney()
end

function Auto:Review()
    local w, c = self.win, self.cfg
    self.win = { at = GetTime(), shown = 0, worked = 0 }
    if not self:Enabled() then return end
    local S, D = ns.Sniper, ns.Deals
    if not (S and D) then return end
    -- 1. smallest profit
    if not self:Held("min") then
        local cur = D.cfg.minProfit
        local m = S.underMin
        local hidden = (m and GetTime() - m.at < c.every) and m.n or 0
        local new, why
        local crowd = w.crowd or 0
        if crowd >= c.crowded then
            local top = max(100, floor(worth() * 0.02))
            if cur < top then
                new = min(top, floor(cur * (1 + c.step) + 0.5))
                why = ("%d bigger deals had to wait behind a smaller purchase in the last 10 minutes"):format(crowd)
            end
        elseif crowd == 0 and hidden >= c.manyHidden and cur > c.minFloor then
            new = max(c.minFloor, floor(cur * (1 - c.step)))
            why = ("%d deal%s hidden by it in the last 10 minutes (best hidden: %s), and no bigger deal had to wait behind a purchase"):format(
                hidden, hidden == 1 and "" or "s", coin(m.best))
        end
        if new and new ~= cur then
            self.setting = true
            if ns.UI and ns.UI.SetMinProfit then ns.UI:SetMinProfit(new) else D.cfg.minProfit = new; AuctionMeshDB.cfg.minProfit = new end
            self.setting = nil
            S.underMin = nil
            self:Note(("smallest profit %s > %s: %s"):format(coin(cur), coin(new), why))
        end
    end
end

-- 2. how long the radar stays quiet when a deal appears
function Auto:Hold(armed, base)
    if not self:Enabled() then return base end
    if armed then return 1 end
    local list = AuctionMeshDB.outcomes or {}
    local r = {}
    for i = #list, max(1, #list - 14), -1 do
        if list[i].r then r[#r + 1] = list[i].r end
        if #r >= 7 then break end
    end
    if #r < 3 then return base end
    table.sort(r)
    return max(2, min(base, r[floor((#r + 1) / 2)] + 1))
end

-- the last changes, newest first, as plain text
function Auto:Lines(n)
    local out, log = {}, self.d and self.d.log or {}
    for i = #log, max(1, #log - (n or 5) + 1), -1 do
        out[#out + 1] = { t = log[i].t, m = log[i].m }
    end
    return out
end

return Auto
