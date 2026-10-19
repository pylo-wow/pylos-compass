local _, D = ...
local ns = D.engine

-- Learns which reasons you follow, only from signs you give: what you told, chose or did. Not from ignored suggestions
-- (they would count against zones/quests/dungeons that take longer, against a start page opened only to type, and
-- against AFK time, which the player can skew). Evidence kinds, each worth EVIDENCE observations:
--   told     your own word in the menu ("Good" / "Bad suggestion")
--   chose    an active choice between things on offer: a quest reward picked, a loot roll, an upgrade sold or destroyed
--            unworn (Learning\Upgrades.lua); an offered suggestion passed: a trainer's spell, a vendor's item, a recipe
--            beside the one made, an abandoned quest (Learning\Declined.lua)
--   did      a suggestion followed: chosen in the search, done in the game (crafted, cast, used, bought: Memory.lua),
--            NPC talked to, spell or recipe learned, item put on, dungeon entered
-- What the search or the window shows as a suggestion (learning.Shown) waits WINDOW with its reasons: acted on by then,
-- "did" for each; otherwise it is let go without counting. A suggestion shown in combat does not wait.
-- Each reason gets a personal weight x0.5 to x1.5 (Reasons.lua multiplies it in): reasons you follow more than others
-- of their kind rise, those you turn down sink, never below half so something new still comes up. Each kind ("do": the
-- window; "know": the search's lists) learns on its own, with its own overall rate. Everything halves every month.
-- Only counts are kept (PylosCompassEngineDB.reasonStats: kind -> reason -> { hits, misses, time }).
-- Not learned from being followed (reason field learn = false), only from your word and choices:
--   questNeed, rareNearby  killing and looting leave no sure sign
--   upgrade, equip         Learning\Upgrades.lua watches what you do with upgrades instead (most cannot be put on
--                          within half an hour: quest reward, dungeon drop)
--   lookedUp               it is the lookups themselves: choosing one again is no sign
--   nearby                 it only fills in below the real reasons
-- "Bad suggestion" also sinks that entry at once.

local learning = {}
ns.learning = learning

local WINDOW = 30 * 60          -- seconds a suggestion waits to be followed
local EXPIRE_EVERY = 60         -- seconds between looks at what waited too long
local HALF_LIFE = 30 * 86400        -- seconds: counts halve
local PRIOR = 5                 -- observations it takes before a reason's own rate counts much
local LOW, HIGH = 0.5, 1.5
local EVIDENCE = { told = 3, chose = 2, did = 1 }
local BAD_SKIPS = 6             -- "Bad suggestion" tires the entry as six passings over
learning.WINDOW, learning.HALF_LIFE = WINDOW, HALF_LIFE

local pending = {}      -- entry ID -> { at = time(), reasons = { key = true }, spellID, rank }
local multipliers = { ["do"] = {}, know = {} } -- kind -> reason key -> personal weight
local expiredAt = 0

local function Stats(kind) return ns.engineDB and ns.engineDB.reasonStats[kind] end

-- the kind a reason's counts are kept under: its own; for a reason of both kinds the kind suggested
local function KindOf(key, kind)
    local reason = ns.reasons.All()[key]
    local own = reason and reason.kind
    if own == "do" or own == "know" then return own end
    return kind or "do"
end
learning.KindOf = KindOf

local function Counts(record, now)
    if not record then return 0, 0 end
    local since = now - record[3]
    return D.Decay(record[1], since, HALF_LIFE), D.Decay(record[2], since, HALF_LIFE)
end

local function Count(key, hit, evidence, kind)
    local stats = Stats(KindOf(key, kind))
    if not stats or not D.Learns() then return end
    local now = time()
    local hits, misses = Counts(stats[key], now)
    local weight = EVIDENCE[evidence]
    if hit then hits = hits + weight else misses = misses + weight end
    stats[key] = { hits, misses, now }
    D.BumpState("rec:learning") -- the personal weights change (Reasons.lua keeps results by it)
end

-- personal weights from the counts: each reason's follow rate vs. the overall rate of its kind; few signs stay near 1
-- (PRIOR)
function learning.Refresh()
    for kind, list in pairs(multipliers) do
        wipe(list)
        local stats = Stats(kind)
        if stats then
            local now = time()
            local allHits, allSeen = 0, 0
            for _, record in pairs(stats) do
                local hits, misses = Counts(record, now)
                allHits, allSeen = allHits + hits, allSeen + hits + misses
            end
            if allSeen > 0 then
                local overall = (allHits + 1) / (allSeen + 2)
                for key, record in pairs(stats) do
                    local hits, misses = Counts(record, now)
                    local rate = (hits + PRIOR * overall) / (hits + misses + PRIOR)
                    list[key] = math.min(HIGH, math.max(LOW, rate / overall))
                end
            end
        end
    end
end

function learning.Multiplier(key, kind)
    return multipliers[KindOf(key, kind)][key] or 1
end

-- Following

-- acted on: within WINDOW a hit for each of its reasons, later nothing
local function Followed(id)
    local waiting = id and pending[id]
    if not waiting then return end
    pending[id] = nil
    if time() - waiting.at > WINDOW then return end
    local keys = {}
    for key in pairs(waiting.reasons) do
        Count(key, true, "did")
        keys[#keys + 1] = key
    end
    learning.Refresh()
    ns.Log("followed", id, table.concat(keys, " "), waiting.rank or "")
end

function learning.Expire()
    local now = time()
    expiredAt = now
    for id, waiting in pairs(pending) do
        if now - waiting.at > WINDOW then pending[id] = nil end
    end
end

-- Seeing

local function Wait(id, at, key, spellID, rank)
    local waiting = pending[id]
    if not waiting then
        waiting = { at = at, reasons = {}, spellID = spellID }
        pending[id] = waiting
    end
    waiting.reasons[key] = true
    if rank and (not waiting.rank or rank < waiting.rank) then waiting.rank = rank end
end

-- A shown suggestion (ns.Shown) waits to be followed, with its reasons; only what was shown counts. Shown again while
-- waiting, it keeps its time (reasons of another kind are added). What a reason offers there waits too (a trainer's
-- spells: learned, or passed at the trainer, Learning\Declined.lua). Not in combat.
function learning.Shown(entry, kind, rank)
    if not ns.engineDB or not D.Learns() or InCombatLockdown() then return end
    local id = D.EntryID(entry)
    if not id then return end
    local now = time()
    if now - expiredAt >= EXPIRE_EVERY then learning.Expire() end
    local all = ns.reasons.All()
    for _, key in ipairs(ns.reasons.Keys(entry, kind)) do
        local reason = all[key]
        if reason.learn ~= false then
            Wait(id, now, key, entry.hidden and entry.spellID or nil, rank)
            if reason.offers then
                for _, offered in ipairs(reason.offers(entry)) do
                    Wait(offered, now, key, tonumber(offered:match("^s:(%d+)$")))
                end
            end
        end
    end
end

-- Your word on a suggestion ("Good"/"Bad suggestion"): its reasons rise or sink ("told"); a bad one tires the entry
-- at once. kind: "do" (default) or "know".
function learning.Feedback(entry, good, kind)
    local id = D.EntryID(entry)
    if not id or not ns.engineDB then return end
    pending[id] = nil
    local keys = ns.reasons.Keys(entry, kind)
    for _, key in ipairs(keys) do
        Count(key, good, "told", kind)
    end
    if not good then ns.memory.Skipped(id, BAD_SKIPS, kind) end
    learning.Refresh()
    ns.Log(good and "good" or "bad", id, table.concat(keys, " "))
end

-- a sign seen elsewhere (Learning\Upgrades.lua): a reason's hit or miss; evidence a key of EVIDENCE; id and words for
-- the log
function learning.Observe(key, hit, evidence, id, words)
    if not ns.engineDB then return end
    Count(key, hit, evidence)
    learning.Refresh()
    ns.Log(hit and "followed" or "declined", id, key .. " " .. evidence .. (words and (" " .. words) or ""))
end

-- A suggestion on offer right there and passed (Learning\Declined.lua): each of its reasons gets a "chose" miss.
-- Nothing if it was not among the suggestions; true if counted.
function learning.Declined(id, words)
    local waiting = id and pending[id]
    if not waiting or not ns.engineDB then return false end
    pending[id] = nil
    local keys = {}
    for key in pairs(waiting.reasons) do
        Count(key, false, "chose")
        keys[#keys + 1] = key
    end
    learning.Refresh()
    ns.Log("declined", id, table.concat(keys, " ") .. (words and (" " .. words) or ""))
    return true
end

function learning.Pending() return pending end

-- Forgets the follow rates of a kind ("do": the window, "know": the search); the window's also the upgrades judged
function learning.Forget(kind)
    local stats = Stats(kind)
    if stats then wipe(stats) end
    if kind == "do" and ns.engineDB then wipe(ns.engineDB.upgradesJudged) end
    learning.Refresh()
    D.BumpState("rec:learning")
end

D.OnState("spells", function()
    for id, waiting in pairs(pending) do
        if waiting.spellID and D.SpellKnown(waiting.spellID) then Followed(id) end
    end
end)
D.OnState("gear", function()
    for slot = 1, 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID and pending["i:" .. itemID] then Followed("i:" .. itemID) end
    end
end)
local lastZone -- the zone you were in (the state "zone" comes with every subzone too)
D.OnState("zone", function()
    -- a zone suggested for its quests: gone there from another one, not the one you log in to
    local zone = D.PlayerZone()
    if zone and zone ~= lastZone then
        if lastZone then Followed("z:" .. zone) end
        lastZone = zone
    end
    if not IsInInstance() then return end
    local instanceID = select(8, GetInstanceInfo())
    if instanceID then Followed("d:" .. instanceID) end
end)

ns.memory.OnAction(Followed)
