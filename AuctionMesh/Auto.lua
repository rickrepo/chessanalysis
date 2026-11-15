-- AuctionMesh Auto: settings that adjust themselves from what really happens.
--
-- Fixed, bounded rules fed by counts the addon already keeps. Every change is
-- written down with its reason (Setup tab, Snapshot), and the Auto-adjust
-- switch freezes all of it. A setting you change yourself (or import) is left
-- alone for 30 minutes.
--
--   1. SMALLEST PROFIT. Looked at every 10 minutes of working time:
--        hardly any deal shown, several hidden by the minimum  -> 25% lower
--        more deals shown than can be acted on                 -> 25% higher
--      Never under 20c, never over 2% of everything you own (at least 1s).
--   2. THE RADAR'S QUIET TIME after a deal appears (so that your input is not
--      queued behind a radar read). While you roll the wheel your input comes
--      within a notch: 1 second. Otherwise it follows how fast your last
--      inputs really came (their median plus a second), between 2 and 6.
local _, ns = ...
ns = ns or {}

local Auto = {}
ns.Auto = Auto

local floor, min, max = math.floor, math.min, math.max
Auto.cfg = { every = 600, manualHold = 1800, fewShown = 1, manyHidden = 3, tooMany = 15, step = 0.25, minFloor = 20 }

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

-- A deal was shown (called by the sniper).
function Auto:Shown()
    if self.win then self.win.shown = self.win.shown + 1 end
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
        if w.shown <= c.fewShown and hidden >= c.manyHidden and cur > c.minFloor then
            new = max(c.minFloor, floor(cur * (1 - c.step)))
            why = ("%d deal%s shown and %d hidden by it in the last 10 minutes (best hidden: %s)"):format(w.shown, w.shown == 1 and "" or "s", hidden, coin(m.best))
        elseif w.shown >= c.tooMany then
            local top = max(100, floor(worth() * 0.02))
            if cur < top then
                new = min(top, floor(cur * (1 + c.step) + 0.5))
                why = ("%d deals shown in the last 10 minutes, more than can be acted on"):format(w.shown)
            end
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
