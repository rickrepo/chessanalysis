-- AuctionMesh Learn: the addon keeps score on itself, with everyone on the channel.
--
-- Every flip has a prediction (we will resell at X) and an outcome:
--   SOLD     the sale invoice says what the buyer really paid
--   EXPIRED  the auction came back unsold in the mail
-- Each outcome is recorded here AND broadcast to the channel, so the rules are
-- tuned on the whole group's trades, not just yours. Three things are learned,
-- all bounded and all visible (/amesh learn, HISTORY tab):
--
--   1. Price factor.  Average of (real sale price / planned price) over sold
--      flips. If sales come in at 93% of plan, every future plan is multiplied
--      by 0.93. Never above 1.00 (no optimism), never below 0.80.
--   2. Item record.   An item that expired is not flipped again for 12 hours
--      (24h after two failures in a row, and so on up to 48h). A sale clears it.
--   3. Margin.        Looks at the last 20 outcomes. Under 70% sold: the profit
--      bar goes up 5 points (max 50%). Over 90% sold: down 2 points (min 12%).
--      Checked once per 10 new outcomes, so it moves slowly.
--
-- This is bookkeeping and calibration, not a neural network. It needs real
-- trades to learn from: with few trades it changes nothing.
--
-- Wire: Z <zig(key)> <sold 1|0> <ratio * 100>
local _, ns = ...
ns = ns or {}

local Codec, Comm, Sync, Deals = ns.Codec, ns.Comm, ns.Sync, ns.Deals
local Learn = {}
ns.Learn = Learn

local floor, min, max = math.floor, math.min, math.max

Learn.cfg = {
    minOutcomes = 5,     -- nothing is adjusted before this many outcomes
    window = 20,         -- outcomes looked at for the margin
    every = 10,          -- margin is reconsidered once per this many new outcomes
    blockHours = 12,     -- first failure blocks the item this long
    marginMin = 0.12, marginMax = 0.50,
    autoTune = true,
}

Learn.serverTime = function() return GetServerTime() end

function Learn:Attach(t)
    -- n: outcomes; ok / fail: sold / expired; mine: how many were ours;
    -- ratio: smoothed real/planned price; recent: last outcomes (1 sold, 0 expired);
    -- items[key] = { ok, fail, streak (failures in a row), last (time) }
    t.n, t.ok, t.fail, t.mine = t.n or 0, t.ok or 0, t.fail or 0, t.mine or 0
    t.ratio = t.ratio or 1
    t.recent = t.recent or {}
    t.items = t.items or {}
    t.sinceTune = t.sinceTune or 0
    self.d = t
end

-- Multiplier for planned resale prices (1 until enough sold outcomes exist).
function Learn:Factor()
    local d = self.d
    if not d or d.ok < self.cfg.minOutcomes then return 1 end
    return max(0.80, min(1, d.ratio))
end

-- If this item recently failed to sell, returns the hours left on its block.
function Learn:Blocked(key)
    local it = self.d and self.d.items[key]
    if not it or (it.streak or 0) <= 0 then return nil end
    local hours = min(48, self.cfg.blockHours * it.streak)
    local left = hours * 3600 - (self.serverTime() - (it.last or 0))
    if left <= 0 then return nil end
    return left / 3600
end

function Learn:SoldRate()
    local r = self.d.recent
    if #r == 0 then return nil end
    local s = 0
    for i = 1, #r do s = s + r[i] end
    return s / #r, #r
end

-- Applies one outcome (ours or a friend's).
function Learn:Apply(key, sold, ratio, mine)
    local d = self.d
    if not d then return end
    d.n = d.n + 1
    if mine then d.mine = d.mine + 1 end
    local it = d.items[key] or { ok = 0, fail = 0, streak = 0 }
    d.items[key] = it
    it.last = self.serverTime()
    if sold then
        d.ok, it.ok, it.streak = d.ok + 1, it.ok + 1, 0
        if ratio and ratio > 0.2 and ratio < 3 then
            -- smoothed: each new sale moves the average by 15%
            d.ratio = d.ok == 1 and ratio or (d.ratio * 0.85 + ratio * 0.15)
        end
    else
        d.fail, it.fail, it.streak = d.fail + 1, it.fail + 1, (it.streak or 0) + 1
    end
    local r = d.recent
    r[#r + 1] = sold and 1 or 0
    while #r > self.cfg.window do table.remove(r, 1) end
    d.sinceTune = d.sinceTune + 1
    self:Tune()
    if ns.Log then
        ns.Log("LEARN %s %s%s: %d outcomes, %d sold, %d expired, price factor %.2f, margin %d%%", tostring(key),
            sold and "SOLD" or "EXPIRED", mine and "" or " (from a friend)", d.n, d.ok, d.fail, self:Factor(),
            floor(Deals.cfg.margin * 100 + 0.5))
    end
    if ns.UI then ns.UI:Dirty() end
end

-- Slow, bounded adjustment of the profit bar from the group's sold rate.
function Learn:Tune()
    local d, c = self.d, self.cfg
    if not c.autoTune or d.sinceTune < c.every or #d.recent < c.every then return end
    d.sinceTune = 0
    local rate = self:SoldRate()
    local m = Deals.cfg.margin
    if rate < 0.70 then m = min(c.marginMax, m + 0.05)
    elseif rate > 0.90 then m = max(c.marginMin, m - 0.02) end
    if m ~= Deals.cfg.margin then
        if ns.Log then ns.Log("LEARN margin %d%% -> %d%% (%d%% of the last %d flips sold)", floor(Deals.cfg.margin * 100 + 0.5),
            floor(m * 100 + 0.5), floor(rate * 100 + 0.5), #d.recent) end
        Deals.cfg.margin = m
        d.margin = m -- remembered across sessions
        if AuctionMeshDB and AuctionMeshDB.cfg then AuctionMeshDB.cfg.margin = floor(m * 100 + 0.5) end
    end
end

-- One of OUR flips finished. Records it and tells the channel.
function Learn:Outcome(key, sold, ratio)
    self:Apply(key, sold, ratio, true)
    local pct = floor(((sold and ratio) or 0) * 100 + 0.5)
    if pct < 0 then pct = 0 end
    Comm:Enqueue(Comm.LIVE, "Z" .. Codec.uint(Codec.zig(key)) .. Codec.uint(sold and 1 or 0) .. Codec.uint(pct))
end

function Learn:OnOutcome(msg, sender)
    local z, pos = Codec.readUInt(msg, 2)
    local sold, pct
    sold, pos = Codec.readUInt(msg, pos)
    pct = Codec.readUInt(msg, pos)
    if not z or not sold or not pct then return end
    self:Apply(Codec.unzig(z), sold == 1, pct / 100, false)
end
Sync.OPS[90] = function(_, msg, sender) Learn:OnOutcome(msg, sender) end -- 'Z'

-- One plain sentence for the window and /amesh learn.
function Learn:Summary()
    local d = self.d
    if not d or d.n == 0 then
        return "Learning: no finished flips yet. Every sale or expired auction (yours or a friend's) is scored against its prediction."
    end
    local rate, n = self:SoldRate()
    local s = ("Learning from %d finished flip%s (%d yours, %d from friends): %d%% of the last %d sold"):format(
        d.n, d.n == 1 and "" or "s", d.mine, d.n - d.mine, floor((rate or 0) * 100 + 0.5), n or 0)
    if d.ok >= self.cfg.minOutcomes then
        s = s .. (", sales came in at %d%% of the planned price"):format(floor(d.ratio * 100 + 0.5))
    else
        s = s .. (", %d more sale(s) needed before prices are adjusted"):format(self.cfg.minOutcomes - d.ok)
    end
    return s .. (". Profit bar: %d%%."):format(floor(Deals.cfg.margin * 100 + 0.5))
end

return Learn
