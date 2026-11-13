-- AuctionMesh Comm: transport layer over C_ChatInfo.SendAddonMessage.
--
-- * Three priority lanes: CONTROL (hello/sync handshakes) > LIVE (fresh scan
--   deltas) > BULK (catch-up streams). Bulk never delays live data.
-- * Two prefixes, each with its own client throttle budget: control+live
--   share PREFIX_LIVE, bulk uses PREFIX_BULK. This roughly doubles throughput
--   and keeps catch-up traffic from using up the live budget.
-- * Token bucket per prefix (burst 10, refill ~1/s), matching the retail
--   per-prefix addon message throttle. The send result is checked: on a
--   throttle or lockdown result the message goes back to the front of its
--   lane and that prefix backs off exponentially.
-- * Lazy sources: a lane entry can be an object with :Next() that encodes its
--   next message only when a token is free, so long sync streams always send
--   current data and can be cancelled mid-stream for free.
-- * The pump frame only runs OnUpdate while there is something queued.
local _, ns = ...
ns = ns or {}

local Comm = {}
ns.Comm = Comm

Comm.PREFIX_LIVE = "AMsh"
Comm.PREFIX_BULK = "AMsb"
Comm.CONTROL, Comm.LIVE, Comm.BULK = 1, 2, 3

local BURST, RATE = 10, 0.95 -- slightly under 1/s for safety margin
local MAX_FAILS = 6

local lanes = { {}, {}, {} } -- each lane: { head=1, tail=0, [i]=item }
for i = 1, 3 do lanes[i].head, lanes[i].tail = 1, 0 end

local buckets = {
    [Comm.PREFIX_LIVE] = { tokens = BURST, pausedUntil = 0, fails = 0 },
    [Comm.PREFIX_BULK] = { tokens = BURST, pausedUntil = 0, fails = 0 },
}
local laneprefix = { Comm.PREFIX_LIVE, Comm.PREFIX_LIVE, Comm.PREFIX_BULK }
local retry = {} -- retry[lane] = message that failed and must be resent first

Comm.stats = { sent = 0, bytes = 0, recv = 0, throttled = 0, dropped = 0 }

-- Hooks wired by Core (so this file is testable outside the client).
Comm.now = function() return GetTime() end
Comm.handlers = {} -- handlers[prefix] = function(msg, sender, chatType)

local pump -- frame

local function laneEmpty(l)
    local q = lanes[l]
    return q.head > q.tail and not retry[l]
end

function Comm:Pending()
    return not (laneEmpty(1) and laneEmpty(2) and laneEmpty(3))
end

local function wake()
    if pump and not pump:IsShown() then pump:Show() end
end

function Comm:Enqueue(lane, item)
    local q = lanes[lane]
    q.tail = q.tail + 1
    q[q.tail] = item
    wake()
end

function Comm:LaneSize(lane)
    local q = lanes[lane]
    return q.tail - q.head + 1
end

-- Drop every queued entry for which pred(item) is true (used to cancel jobs).
function Comm:Purge(lane, pred)
    local q = lanes[lane]
    local nq, n = { head = 1 }, 0
    for i = q.head, q.tail do
        local it = q[i]
        if not pred(it) then n = n + 1; nq[n] = it end
    end
    nq.tail = n
    lanes[lane] = nq
end

-- Route: dedicated channel if joined, else guild. Returns chatType, target.
function Comm:Route()
    local name = self.channelName
    if name and GetChannelName then
        local id = GetChannelName(name)
        if id and id > 0 then return "CHANNEL", id end
    end
    if IsInGuild and IsInGuild() then return "GUILD", nil end
    return nil
end

local THROTTLE_CODES
local function isThrottle(ret)
    if not THROTTLE_CODES then
        THROTTLE_CODES = {}
        local E = Enum and Enum.SendAddonMessageResult
        if E then
            for _, k in ipairs({ "AddonMessageThrottle", "ChannelThrottle", "GeneralError" }) do
                if E[k] then THROTTLE_CODES[E[k]] = true end
            end
        else
            THROTTLE_CODES[3] = true
        end
    end
    return THROTTLE_CODES[ret]
end

-- Returns "ok", "retry" (back off and resend), or "drop".
function Comm:RawSend(prefix, msg)
    local chatType, target = self:Route()
    if not chatType then return "retry" end
    local ok, ret = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, chatType, target)
    if not ok then return "retry" end
    -- Older clients return boolean/nil; newer return Enum.SendAddonMessageResult (0 = Success).
    if ret == nil or ret == true or ret == 0 then
        local s = self.stats
        s.sent = s.sent + 1
        s.bytes = s.bytes + #msg
        return "ok"
    end
    if ret == false or isThrottle(ret) then return "retry" end
    -- Other non-success codes (not in group, lockdown in restricted content, ...)
    return "retry"
end

local function nextMessage(l)
    local m = retry[l]
    if m then retry[l] = nil; return m end
    local q = lanes[l]
    while q.head <= q.tail do
        local it = q[q.head]
        if type(it) == "string" then
            q[q.head] = nil
            q.head = q.head + 1
            return it
        end
        local msg = it:Next()
        if msg then return msg end
        q[q.head] = nil
        q.head = q.head + 1
    end
    return nil
end

function Comm:Pump()
    local now = self.now()
    local elapsed = now - (self.last or now)
    self.last = now
    for _, b in pairs(buckets) do
        b.tokens = math.min(BURST, b.tokens + elapsed * RATE)
    end
    if self.paused and self.paused() then return end

    for l = 1, 3 do
        local b = buckets[laneprefix[l]]
        while b.tokens >= 1 and now >= b.pausedUntil do
            local msg = nextMessage(l)
            if not msg then break end
            local res = self:RawSend(laneprefix[l], msg)
            if res == "ok" then
                b.tokens = b.tokens - 1
                b.fails = 0
            else
                self.stats.throttled = self.stats.throttled + 1
                b.fails = b.fails + 1
                b.tokens = 0
                if b.fails > MAX_FAILS and l == Comm.BULK then
                    self.stats.dropped = self.stats.dropped + 1
                    b.fails = 0
                else
                    retry[l] = msg
                end
                b.pausedUntil = now + math.min(30, 2 ^ math.min(b.fails, 5) * 0.5)
                break
            end
        end
    end
    if not self:Pending() and pump then pump:Hide() end
end

-- Send immediately-ish on a lane (convenience).
function Comm:Send(lane, msg) self:Enqueue(lane, msg) end

function Comm:Init()
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX_LIVE)
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX_BULK)
    pump = CreateFrame("Frame")
    pump:Hide()
    pump:SetScript("OnUpdate", function() Comm:Pump() end)
    pump:SetScript("OnShow", function() Comm.last = Comm.now() end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:SetScript("OnEvent", function(_, _, prefix, msg, chatType, sender)
        local h = Comm.handlers[prefix]
        if not h then return end
        -- Always use full Name-Realm so every client agrees on tie-break order.
        if not sender:find("-", 1, true) then sender = sender .. "-" .. (Comm.realm or "") end
        if sender == Comm.me then return end -- our own echo
        Comm.stats.recv = Comm.stats.recv + 1
        h(msg, sender, chatType)
    end)
end

-- Joins (and hides) the private mesh channel.
function Comm:JoinChannel(name, password)
    self.channelName = name
    if not name or name == "" then return end
    if GetChannelName(name) == 0 and JoinTemporaryChannel then
        JoinTemporaryChannel(name, password)
    end
    if ChatFrame_RemoveChannel then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local f = _G["ChatFrame" .. i]
            if f then pcall(ChatFrame_RemoveChannel, f, name) end
        end
    end
end

-- Test hooks
Comm._lanes, Comm._buckets = lanes, buckets
function Comm:_reset()
    for i = 1, 3 do lanes[i] = { head = 1, tail = 0 }; retry[i] = nil end
    for _, b in pairs(buckets) do b.tokens, b.pausedUntil, b.fails = BURST, 0, 0 end
end

return Comm
