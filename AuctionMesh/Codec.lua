-- AuctionMesh Codec
-- Compact, chat-safe wire encoding. Every byte is drawn from a 64-symbol
-- alphabet (no NUL, no '|', no spaces), so messages survive any chat type.
--
-- Unsigned varint: each symbol carries 5 data bits; values >= 32 mean
-- "more symbols follow". A 200,000 item ID costs 4 symbols, a 1,000g price
-- (10,000,000 copper) costs 5. Pure arithmetic: no 32-bit `bit` library
-- limits, so copper amounts up to 2^53 encode exactly.
local _, ns = ...
ns = ns or {}

local Codec = {}
ns.Codec = Codec

local floor, byte, concat = math.floor, string.byte, table.concat

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = ALPHABET:sub(i, i)
    ENC[i - 1] = c
    DEC[byte(c)] = i - 1
end
Codec.ENC, Codec.DEC = ENC, DEC

-- Max addon message payload is 255 bytes.
Codec.MAX_LEN = 255

-- Appends the varint symbols of v to buf starting after index n. Returns new n.
local function putUInt(buf, n, v)
    v = floor(v)
    if v < 0 then v = 0 end
    while v >= 32 do
        local d = v % 32
        n = n + 1
        buf[n] = ENC[d + 32]
        v = (v - d) / 32
    end
    n = n + 1
    buf[n] = ENC[v]
    return n
end
Codec.putUInt = putUInt

function Codec.uint(v)
    local buf = {}
    local n = putUInt(buf, 0, v)
    return concat(buf, "", 1, n)
end

-- Reads a varint from s at pos. Returns value, nextPos (value nil on malformed input).
local function readUInt(s, pos)
    local v, mul = 0, 1
    while true do
        local b = byte(s, pos)
        if not b then return nil, pos end
        local d = DEC[b]
        if not d then return nil, pos end
        pos = pos + 1
        if d >= 32 then
            v = v + (d - 32) * mul
            mul = mul * 32
            if mul > 9007199254740992 then return nil, pos end
        else
            return v + d * mul, pos
        end
    end
end
Codec.readUInt = readUInt

-- Zigzag maps signed -> unsigned so small negatives stay short.
function Codec.zig(v) return v >= 0 and v * 2 or -v * 2 - 1 end
function Codec.unzig(u) return (u % 2 == 0) and (u / 2) or -((u + 1) / 2) end

local zig, unzig = Codec.zig, Codec.unzig

-- One price record: zig(key) price qty age   (age = baseTime - t, clamped >= 0)
function Codec.record(key, price, qty, age)
    local buf = {}
    local n = putUInt(buf, 0, zig(key))
    n = putUInt(buf, n, price)
    n = putUInt(buf, n, qty)
    n = putUInt(buf, n, age > 0 and age or 0)
    return concat(buf, "", 1, n)
end

-- Delta message builder: "D" .. uint(baseTime) .. record*  (op "F" reuses it for fair prices, qty = 0)
-- Reuse one builder per batch; call :add() until it returns false (full),
-- then :finish() and start a new one.
local Builder = {}
Builder.__index = Builder

function Codec.newDelta(baseTime, op)
    local head = (op or "D") .. Codec.uint(baseTime)
    return setmetatable({ parts = { head }, n = 1, len = #head, base = baseTime, count = 0 }, Builder)
end

function Builder:add(key, price, qty, t)
    local rec = Codec.record(key, price, qty, self.base - t)
    if self.len + #rec > Codec.MAX_LEN then return false end
    self.n = self.n + 1
    self.parts[self.n] = rec
    self.len = self.len + #rec
    self.count = self.count + 1
    return true
end

function Builder:finish()
    if self.count == 0 then return nil end
    return concat(self.parts, "", 1, self.n)
end

-- Decodes a delta message, calling fn(key, price, qty, t) per record.
-- Returns the number of records decoded, or nil if malformed.
function Codec.decodeDelta(msg, fn)
    local base, pos = readUInt(msg, 2)
    if not base then return nil end
    local len, count = #msg, 0
    while pos <= len do
        local zk, p, q, age
        zk, pos = readUInt(msg, pos); if not zk then return nil end
        p, pos = readUInt(msg, pos);  if not p then return nil end
        q, pos = readUInt(msg, pos);  if not q then return nil end
        age, pos = readUInt(msg, pos); if not age then return nil end
        fn(unzig(zk), p, q, base - age)
        count = count + 1
    end
    return count
end

return Codec
