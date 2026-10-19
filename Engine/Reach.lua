local _, D = ...
local ns = D.engine
local L = ns.L

-- Reach: how easily you can act on a suggestion now, a factor on its value (Reasons.lua: weight x strength x reach).
-- Effort in minutes (the way there, D.TravelMinutes, plus the doing) on one smooth curve: 1 / (1 + minutes / T), T = 10
-- (ten minutes away counts half). Easy things come first unless the far thing is far more important.
-- Named points, for where the minutes are unknown:
--   now 1 (in your bags, a click away); here 0.91 (a minute on foot); zone 0.77 (somewhere in this zone, ZONE_MINUTES);
--   travel 0.4 (place not known at all, UNKNOWN_MINUTES); luck 0.03 (no way known but luck, a world drop: reach.Known
--   says no)
-- Each function returns the factor and a few words for the tooltip ("120 yd away", "sold by X, nearby", "~25 min,
-- overseas"), or nil words.

local reach = {}
ns.reach = reach

local T = 10                -- minutes at which the reach is half
local MOST_MINUTES = 180    -- beyond this the reach stays as it is
local ZONE_MINUTES = 3      -- somewhere in your zone, the spot not known
local UNKNOWN_MINUTES = 15  -- a place not known
local QUEST_MINUTES = 10    -- doing a quest (its objectives, on average)
local DUNGEON_MINUTES = 45  -- a dungeon run
local GROUP_MINUTES = 10    -- finding a group

function reach.Minutes(minutes)
    return 1 / (1 + math.min(minutes, MOST_MINUTES) / T)
end
local Minutes = reach.Minutes

local NOW, HERE, ZONE, TRAVEL, LUCK = 1, Minutes(1), Minutes(ZONE_MINUTES), Minutes(UNKNOWN_MINUTES), 0.03
reach.NOW, reach.HERE, reach.ZONE, reach.TRAVEL, reach.LUCK = NOW, HERE, ZONE, TRAVEL, LUCK
reach.QUEST_MINUTES, reach.GROUP_MINUTES = QUEST_MINUTES, GROUP_MINUTES
reach.ZONE_MINUTES, reach.UNKNOWN_MINUTES = ZONE_MINUTES, UNKNOWN_MINUTES
local AT_HAND, MINUTE = 60, 400 -- yards
local DROP_GOOD = 10 -- percent from which a drop counts as farmable

local mapNames = {} -- mapID -> name or false
local function MapName(mapID)
    local name = mapNames[mapID]
    if name == nil then
        local info = C_Map.GetMapInfo(mapID)
        name = info and info.name or false
        mapNames[mapID] = name
    end
    return name or nil
end

-- The way to a place as minutes and words: "nearby (120 yd)" on your map, else minutes and rides ("~23 min via Deeprun
-- Tram, ..."); nil if it cannot be told, false if no way is known
local function Way(place)
    local minutes, _, rides = D.TravelMinutes(place)
    if not minutes then return minutes end
    local yards = not rides and D.PlaceDistance(place)
    if yards and yards <= MINUTE then
        local rounded = math.floor(yards / 10 + 0.5) * 10
        return minutes, yards <= AT_HAND and L["right here"] or L["nearby (%d yd)"]:format(rounded)
    end
    local name = MapName((D.PlaceParts(place)))
    local shown = math.max(1, math.floor(minutes + 0.5))
    local words = rides and L["~%d min via %s"]:format(shown, rides) or L["~%d min away"]:format(shown)
    -- (a ride named after the place says it already: "via Alterac Mountains - Zephras Isle")
    local named = name and not (rides and rides:find(name, 1, true))
    return minutes, words .. (named and (", " .. name) or "")
end

-- A place (packed: uiMapID * 1000000 + x * 1000 + y) as reach with `extra` minutes of doing there: factor, words,
-- minutes. No way known (an island, another continent without your faction's transport): luck only; not told (an
-- instance): far away.
function reach.Place(place, extra)
    local minutes, words = Way(place)
    if minutes == false then return LUCK, L["no way known"] end
    if not minutes then return TRAVEL, nil end
    minutes = minutes + (extra or 0)
    return Minutes(minutes), words, minutes
end

-- a straight distance as reach where the route planner cannot tell; yards nil (no spot, not on your map): in this zone
-- if inZone, else far
function reach.Yards(yards, inZone)
    if not yards then
        if inZone then return ZONE, L["in this zone"] end
        return TRAVEL, L["far away"]
    end
    local rounded = math.floor(yards / 10 + 0.5) * 10
    local factor = Minutes(D.YardsMinutes(yards))
    if yards <= AT_HAND then return factor, L["right here"] end
    if yards <= MINUTE then return factor, L["nearby (%d yd)"]:format(rounded) end
    return factor, L["%d yd away"]:format(rounded)
end

-- An NPC: factor, words, yards (nil: unknown). Uses the same route planner as other places (mount, detour, zone
-- crossings); where it cannot tell, the straight line or the zone.
--
-- A foe (no role, not friendly) spawns in many places and the one spot kept says little about the nearest one
-- (seen in game: "nearby (160 yd)" for one around you), so its words name only the zone; the factor still counts the
-- spot.
local function FoeWords(entry, yards, words)
    if entry.roles ~= 0 or entry.reaction == 3 then return words end
    if yards or D.NPCInCurrentZone(entry) then return L["in this zone"] end
    return words
end
function reach.NPC(entry)
    local yards = D.NPCDistance(entry)
    local place = entry.place -- where it stands, nil if not known
    if place then
        local minutes = D.TravelMinutes(place)
        if minutes ~= nil then
            local factor, words = reach.Place(place)
            return factor, FoeWords(entry, yards, words), yards
        end
    end
    local inZone = not yards and D.NPCInCurrentZone(entry)
    local factor, words = reach.Yards(yards, inZone)
    return factor, FoeWords(entry, yards, words), yards
end

-- Kept per frame: the nearest of NPC lists, your trainers, the ways to items
local perFrame = D.Cache({ "frame" })
local nearest, trainers = {}, {}
local items = {} -- entry -> { factor, words, via } of reach.Item
local function Fresh()
    local _, renewed = perFrame.Get()
    if renewed then
        wipe(nearest)
        wipe(trainers)
        wipe(items)
    end
end

-- The nearest of some NPCs from a data string ("123,456" of D.SoldBy or "123:40,456:5" of D.DroppedBy; the first
-- number of each part); friendly: only NPCs not hostile to you (vendors). Returns factor, words, entry; nil if none
-- is an entry (or, with friendly, all are hostile).
function reach.Nearest(ids, friendly)
    if not ids or ids == "" then return nil end
    Fresh()
    local key = ids .. (friendly and "+" or "")
    local found = nearest[key]
    if found == nil then
        local best, bestFactor, bestWords = nil, -1, nil
        for id in ids:gmatch("(%d+)[^,]*") do
            local entry = D.EntryByID("n:" .. id)
            if entry and not (friendly and entry.reaction == 1) then
                local factor, words = reach.NPC(entry)
                if factor > bestFactor then best, bestFactor, bestWords = entry, factor, words end
            end
        end
        found = best and { bestFactor, bestWords, best } or false
        nearest[key] = found
    end
    if not found then return nil end
    return found[1], found[2], found[3]
end

-- Your trainer of a class (class ID) or profession (skill line) per D.npcTrainers: the nearest not hostile one; with
-- no distance known, the one you use most (Memory.lua). Returns entry, factor, words; nil if none is known.
local teaching = D.Cache({ "npcs" }) -- rebuilt when trainers are learned in play
function reach.Trainer(teaches)
    if not teaches then return nil end
    local byTeaching, rebuilt = teaching.Get() -- class ID or skill line -> list of NPC IDs
    if rebuilt then
        for npcID, what in pairs(D.npcTrainers or {}) do
            byTeaching[what] = byTeaching[what] or {}
            table.insert(byTeaching[what], npcID)
        end
    end
    Fresh()
    local found = trainers[teaches]
    if found == nil then
        local Used = ns.memory.UsedNow()
        local best, bestFactor, bestWords, bestYards, bestUse
        for _, npcID in ipairs(byTeaching[teaches] or {}) do
            local entry = D.EntryByID("n:" .. npcID)
            if entry and entry.reaction ~= 1 then
                local factor, words, yards = reach.NPC(entry)
                local use = Used("n:" .. npcID)
                local better
                if not best then
                    better = true
                elseif (yards ~= nil) ~= (bestYards ~= nil) then
                    better = yards ~= nil
                elseif yards then
                    better = yards < bestYards
                else
                    better = factor > bestFactor or (factor == bestFactor and use > bestUse)
                end
                if better then best, bestFactor, bestWords, bestYards, bestUse = entry, factor, words, yards, use end
            end
        end
        found = best and { best, bestFactor, bestWords } or false
        trainers[teaches] = found
    end
    if not found then return nil end
    return found[1], found[2], found[3]
end

-- How easy an item is to get (Upgrade, LevelFit, Restock, QuestNeed): the best of the ways (made, a quest reward, sold,
-- dropped). Made by you only with a recipe you know (seen in game: "you can make it" on a belt whose plans were not
-- learned).
local function Craft(entry)
    local spellID, line = D.CraftingRecipe(entry)
    if not spellID then return nil end
    if D.SpellKnown(spellID) then
        if D.CraftTimes({ spellID = spellID, skillLine = line }) > 0 then
            return NOW, L["you can make it"]
        end
        return ZONE, L["your recipe, needs materials"]
    end
    local recipe = D.RecipeEntry(spellID, line)
    if recipe and D.RecipeLearnable(recipe, D.ProfessionRanks()) == "now" then
        return TRAVEL, L["learn the recipe to make it"]
    end
    return nil
end

local Money = D.Money -- (Forever has no GetCoinTextureString)

-- A quest's reward (D.QuestsRewardingItem, from the client's quest cache). The best of the quests you may take and have
-- not done, by minutes: ready to turn in (the way to where the map marks it), in your log (half a quest's doing,
-- there), or one to take (the way to its giver, learned in play, else to its zone, plus the doing).
local function InLog(questID)
    return C_QuestLog.IsOnQuest(questID)
end
local function Done(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID)
end
local QUEST_ABOVE = 3
-- quests still to do before one can be taken: each adds a quest's doing; more than this, no way (long chains are no
-- way to gear now)
local STEPS_MAX = 2
-- quests to do before a quest can be taken (D.QuestPrevious, 1.12 data; their own prerequisites too, at most
-- STEPS_MAX + 1 deep): 0 none
local function StepsBefore(questID, depth)
    local pre = D.QuestPrevious(questID)
    if not pre or depth > STEPS_MAX + 1 then return 0 end
    local steps = 0
    for _, id in ipairs(pre.allOf) do
        if not Done(id) then steps = steps + 1 + StepsBefore(id, depth + 1) end
    end
    local least
    for _, id in ipairs(pre.anyOf) do
        local s = Done(id) and 0 or 1 + StepsBefore(id, depth + 1)
        if not least or s < least then least = s end
    end
    steps = steps + (least or 0)
    if pre.inLog and not InLog(pre.inLog) then steps = steps + 1 end
    return steps
end
reach.StepsBefore = StepsBefore
local function Effort(place, zone, doing)
    local factor, words = reach.Place(place or (zone and zone > 0 and D.ZonePlace(zone)) or nil, doing)
    if not words then factor = Minutes(UNKNOWN_MINUTES + doing) end
    return factor, words
end
-- No closures, words only for a better way (it runs for many items). Returns factor, words, the
-- quest's entry ID if the best is a quest of your log (its row stands for the item in the list of all: Relevant.lua)
-- and the best quest's entry ID (its rewards are one errand: Upgrade.lua's group).
local function QuestReward(entry)
    local quests = D.QuestsRewardingItem(entry.itemID)
    if not quests or #quests == 0 then return nil end
    local best, bestWords, bestQuest, bestSource = nil, nil, nil, nil
    -- D.QuestFact is cached, unlike D.QuestOf's decoded tables
    local Fact = D.QuestFact
    for _, questID in ipairs(quests) do
        local level = Fact(questID, "level")
        local name = D.NameEN("quest", questID)
        if level and name and not Done(questID) then
            local zone = Fact(questID, "zone")
            local marked = D.QuestPlace(questID)
            local factor, words, format
            local steps = 0
            local logged = InLog(questID)
            if logged then
                if C_QuestLog.IsComplete(questID) then
                    factor, words = Effort(marked, zone, 0)
                    factor, format = math.max(factor, marked and 0 or HERE), L["reward of %s, ready to turn in"]
                else
                    factor, words = Effort(marked, zone,
                        QUEST_MINUTES * (ns.QuestRest(questID) or 0.5))
                    format = L["reward of %s, in your log"]
                end
            elseif D.QuestForYou(questID) and level <= UnitLevel("player") + QUEST_ABOVE then
                steps = StepsBefore(questID, 1)
                if steps <= STEPS_MAX then
                    local _, _, giverPlace = D.QuestGiver(questID)
                    factor, words = Effort(giverPlace, zone, QUEST_MINUTES * (1 + steps))
                    format = steps > 0 and L["reward of %s, %d quests before it"] or L["reward of %s"]
                end
            end
            if factor and (not best or factor > best) then
                best, bestWords = factor, format:format(name, steps) .. (words and ("\n" .. words) or "")
                bestQuest = logged and ("q:" .. questID) or nil
                bestSource = "q:" .. questID
            end
        end
    end
    return best, bestWords, bestQuest, bestSource
end

-- Returns factor, words, via, source: the factor is LUCK only when no way is known (a world drop: reach.Known); via the
-- entry ID of a quest of your log when its reward is the best way; source the entry ID of the best quest, in your log
-- or not. Kept per frame.
local function Item(entry)
    local id = entry.itemID
    if D.bagItems[id] then return NOW, L["in your bags"] end
    local best, bestWords, bestVia, bestSource = LUCK, L["world drop"], nil, nil
    local factor, words, via, source = Craft(entry)
    if factor and factor > best then best, bestWords = factor, words end
    factor, words, via, source = QuestReward(entry)
    if factor and factor > best then best, bestWords, bestVia, bestSource = factor, words, via, source end
    local sold, soldWords, vendor = reach.Nearest(D.SoldBy(id), true)
    if sold then
        -- one you cannot pay at that vendor is out of reach for now
        local price = D.PriceAt(id, vendor.npcID)
        if price and price > GetMoney() then
            if LUCK + 0.01 > best then
                best, bestWords, bestVia, bestSource = LUCK + 0.01,
                    L["sold by %s for %s, more than you have"]:format(vendor.name, Money(price)), nil, nil
            end
        else
            -- limited stock may be sold out when you come: half as sure a way
            local limited = D.VendorStock(vendor.npcID, id)
            if limited then sold = sold * 0.5 end
            if sold > best then
                best, bestWords, bestVia, bestSource = sold,
                    (limited and L["sold by %s, limited stock"] or L["sold by %s"]):format(vendor.name)
                    .. "\n" .. soldWords, nil, nil
            end
        end
    end
    -- dropped: only by a dungeon's boss; other mobs' drops are luck like world drops. Effort: the way to the entrance,
    -- a group, and the runs it takes (one at DROP_GOOD * 2 % and more, up to three for a small chance)
    for npc, chance in (D.DroppedBy(id) or ""):gmatch("(%d+):(%d+)") do
        local dungeon = D.DungeonOfBoss(tonumber(npc))
        local boss = dungeon and D.NPCByID(tonumber(npc))
        if boss then
            chance = tonumber(chance)
            local runs = math.min(3, math.max(1, DROP_GOOD * 2 / math.max(chance, 1)))
            local doing = GROUP_MINUTES + DUNGEON_MINUTES * runs
            factor, words = reach.Place(dungeon.place, doing)
            if not words then factor = Minutes(UNKNOWN_MINUTES + doing) end
            if factor > best then
                best, bestWords, bestVia, bestSource = factor,
                    L["drops from %s (%d %%), %s"]:format(boss.name, math.max(chance, 1), dungeon.name)
                    .. (words and ("\n" .. words) or ""), nil, nil
            end
        end
    end
    return best, bestWords, bestVia, bestSource
end

function reach.Item(entry)
    Fresh()
    local known = items[entry]
    if not known then
        known = { Item(entry) }
        items[entry] = known
    end
    return known[1], known[2], known[3], known[4]
end

function reach.Known(entry)
    return (reach.Item(entry)) > LUCK
end

-- Bundling ("if you are there anyway"): NPCs within BUNDLE_YARDS of an NPC (D.npcPlaces, same map). Cached per NPC,
-- recomputed when places were learned (state "places").
local BUNDLE_YARDS = 80
local placesKnown = D.Cache({ "places" })
local byMap -- map ID -> list of NPC IDs
local neighbours = {} -- NPC ID -> list of NPC IDs
function reach.Neighbours(entry)
    local _, renewed = placesKnown.Get()
    if renewed then
        byMap = nil
        wipe(neighbours)
    end
    local npcID = entry.npcID
    local list = npcID and neighbours[npcID]
    if list then return list end
    list = {}
    local places = D.npcPlaces -- (the raw table: a pass over all places, no accessor for that)
    local place = places and places[npcID]
    if place then
        if not byMap then
            byMap = {}
            for id, spot in pairs(places) do
                local map = D.PlaceParts(spot)
                byMap[map] = byMap[map] or {}
                table.insert(byMap[map], id)
            end
        end
        for _, other in ipairs(byMap[(D.PlaceParts(place))] or {}) do
            if other ~= npcID then
                local gap = D.NPCGap(npcID, other)
                if gap and gap <= BUNDLE_YARDS then list[#list + 1] = other end
            end
        end
    end
    if npcID then neighbours[npcID] = list end
    return list
end
