local ns = select(2, ...).search

-- The search's memory: what you chose after typing what (PylosCompassDB.learned); Rank.lua scores it.
-- learned: text -> entry ID -> { value, time, exact }. The text is each prefix of what was typed (up to
-- 12 characters); exact = 1 under the whole text (only such a choice may pass an exact name in Rank.lua);
-- "" counts every choice, also without text. A choice adds 1, opening only its detail view 0.5; values
-- halve every two weeks.

local EachChar = ns.EachChar
local memory = {}
ns.memory = memory

local HALF_LIFE = 14 * 86400   -- seconds
local MAX_LEARNED_LENGTH = 12
local FORGOTTEN = 0.05         -- values below are dropped at login
local USED_CHOSEN = 0.5        -- the share of "chosen" in the engine's "used" (Engine\Memory.lua)

-- an ID is kept only if this says yes (set in Control.lua); nil: every ID
memory.accept = nil

local function DB() return ns.db end

local function Value(record, now) return ns.data.Decay(record[1], now - record[2], HALF_LIFE) end

-- how strongly a record counts now, 0..1: value / (value + 1)
local function Strength(record, now)
    if not record then return 0 end
    local value = Value(record, now)
    return value / (value + 1)
end

-- the text as learning keys it: searched form, at most 12 characters
local function LearnKey(text)
    local key, count = "", 0
    for char in EachChar(ns.SearchKey(text)) do
        count = count + 1
        if count > MAX_LEARNED_LENGTH then break end
        key = key .. char
    end
    return key
end

-- remembers a choice after typing text (may be empty); amount 1 for a choice, 0.5 for only looking
function memory.Chose(id, amount, text)
    local db = DB()
    if not db or not id or not ns.data.Learns() or (memory.accept and not memory.accept(id)) then return end
    local learned, now = db.learned, time()
    local function Into(key, exact)
        learned[key] = learned[key] or {}
        local bucket = learned[key]
        local record = bucket[id]
        local value = record and Value(record, now) or 0
        bucket[id] = { value + (amount or 1), now, (exact or (record and record[3])) and 1 or nil }
    end
    -- "" counts every choice (also by mouse without text); the text's prefixes only if typed
    Into("")
    local whole = LearnKey(text)
    local key = ""
    for char in EachChar(whole) do
        key = key .. char
        Into(key, key == whole)
    end
end

-- function(id) -> strength 0..1, and true if chosen under exactly this text (not only a longer
-- one starting with it); looked up once per search
function memory.LearnedFor(text)
    local db = DB()
    local key = LearnKey(text)
    local bucket = db and key ~= "" and db.learned[key]
    local now = time()
    return function(id)
        local record = bucket and id and bucket[id]
        if not record then return 0, false end
        return Strength(record, now), record[3] == 1
    end
end

function memory.EachLearned(text, add)
    local db = DB()
    local key = LearnKey(text)
    local bucket = db and key ~= "" and db.learned[key]
    if not bucket then return end
    for id in pairs(bucket) do add(id) end
end

-- how much an entry is chosen at all, 0..USED_CHOSEN (scaled like the engine's "used", which counts more)
function memory.UsedNow()
    local db = DB()
    local all = db and db.learned[""]
    local now = time()
    return function(id)
        return id and all and USED_CHOSEN * Strength(all[id], now) or 0
    end
end

function memory.Recent()
    local db = DB()
    local bucket = db and db.learned[""]
    local list = {}
    if not bucket then return list end
    for id, record in pairs(bucket) do list[#list + 1] = { id, record[2] } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i, item in ipairs(list) do list[i] = item[1] end
    return list
end

function memory.Knows(id)
    local db = DB()
    if not db or not id then return false end
    for _, bucket in pairs(db.learned) do
        if bucket[id] then return true end
    end
    return false
end

function memory.Forget(id)
    local db = DB()
    if not db or not id then return end
    for key, bucket in pairs(db.learned) do
        bucket[id] = nil
        if next(bucket) == nil then db.learned[key] = nil end
    end
end

function memory.Reset()
    local db = DB()
    if db then wipe(db.learned) end
end

-- at most this many entries under a text (and under "", which counts every choice): the strongest stay
local MAX_PER_TEXT, MAX_FOR_ALL = 40, 1500
-- and at most this many texts, the weakest go (a choice writes up to 12 prefix buckets)
local MAX_TEXTS = 4000

function memory.Prune()
    local db = DB()
    if not db then return end
    local now = time()
    local texts = {} -- { text, its strongest record's value }
    for key, bucket in pairs(db.learned) do
        local ids, top = {}, 0
        for id, record in pairs(bucket) do
            local value = Value(record, now)
            if value < FORGOTTEN then
                bucket[id] = nil
            else
                ids[#ids + 1] = id
                if value > top then top = value end
            end
        end
        local limit = key == "" and MAX_FOR_ALL or MAX_PER_TEXT
        if #ids > limit then
            table.sort(ids, function(a, b)
                local va, vb = Value(bucket[a], now), Value(bucket[b], now)
                if va ~= vb then return va > vb end
                return tostring(a) < tostring(b)
            end)
            for i = limit + 1, #ids do bucket[ids[i]] = nil end
        end
        if next(bucket) == nil then db.learned[key] = nil elseif key ~= "" then texts[#texts + 1] = { key, top } end
    end
    if #texts > MAX_TEXTS then
        table.sort(texts, function(a, b)
            if a[2] ~= b[2] then return a[2] > b[2] end
            return a[1] < b[1]
        end)
        for i = MAX_TEXTS + 1, #texts do db.learned[texts[i][1]] = nil end
    end
end
