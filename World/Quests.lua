local _, D = ...
if D.off then return end

-- Quests: every quest with a title (Data\QuestNames_enUS.lua) and facts from the client's quest
-- cache (Data\QuestFacts.lua; format in its header), as entries { name, questID } with ID
-- "q:<quest>". Built in the background (2,785 quests) only when an addon asks (D.Need).
-- The facts answer without the domain: D.QuestOf(questID), plus reverse links for other domains
-- (quests that need an item or NPC, reward an item, or are begun by an item; built on first use).
-- Givers and takers are learned in play (LearnQuests.lua: D.QuestGiver, D.QuestTaker).

local KEY = "quests"

D.QUEST_TAG = { ELITE = 1, PVP = 41, RAID = 62, DUNGEON = 81 }

-- Forever's playable races as race bits (quest.races): race IDs 1-8 as bits 0-7, 95 High Order 256, 96 Windshaper 512
local RACE_BIT = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [95] = 256, [96] = 512 }
local ALLIANCE, HORDE = 1 + 4 + 8 + 64 + 256, 2 + 16 + 32 + 128 + 512

-- The facts of a quest
-- D.QuestOf(questID) -> nil (not a data quest) or a shared table (do not change):
--   questID, level, minLevel
--   sort        QuestSortID (> 0 its area, < 0 a QuestSort, 0 none)
--   area        AreaTable area (zone or subzone; C_Map.GetAreaInfo names it), nil if sort is no area
--   questSort   QuestSort ID (class, profession, holiday ...), nil if none
--   zone        uiMapID of the area's zone, nil if none or unknown
--   dungeon     Map ID of the area's instance (the dungeons' "d:<map>"), nil
--   tag         0 or a D.QUEST_TAG
--   races       allowed Forever races as bits (RACE_BIT); 0 all
--   side        "Alliance" or "Horde" if only that faction may take it, else nil (D.QuestSide)
--   classID     class of a class quest (by QuestSort), else nil; class quests sorted under a zone are not detected
--   skillLine   profession of a profession quest (by QuestSort), else nil
--   nextQuest   offered right after it, nil if none
--   providedItem  given when you take it (a kit, a letter), nil if none
--   xp          full value (less for a character more than five levels above)
--   money       copper (< 0: the quest costs that)
--   repeats     "daily" or "weekly", else nil
--   rewards, choices  { { itemID, count }, ... }
--   spells      { spellID, ... } learned or cast
--   reputation  { { factionID, amount }, ... }
--   objectives  { { kind, id, count, text }, ... }: kind "n" creature to kill, "t" creature to
--               talk to, "i" item, "o" object, "r" faction (count = standing needed), "m" money
--               (count = copper), "a" area to reach, "x" anything else (achievement criteria ...);
--               text as the quest log shows it, nil where the server gives none (most kill/item objectives)
--   startedBy   { itemID, ... } items that begin it (ItemSparse)

-- Faction a quest is for: by races, else by reputation given with a one-sided faction
-- (capitals, battleground sides): the cache says "all races" for many one-sided quests (the
-- Undercity's "A Recipe For Death" was suggested to a human). nil: both or unknown.
-- races: race bits; reputation: the data's "faction:amount,...".
-- A class quest with neither (questID given; the cache names none for most): the faction our
-- data derives (D.questClassSide, Data\QuestLinks.lua: races, 1.12 required races, givers' and
-- takers' reaction), else the faction of the giver seen in play (friendly to one side only, by
-- its reaction in Data\NPCFacts.lua; once the NPC list is built)
local CLASS_SIDES = { "Alliance", "Horde" }
local REACTION_SHIFT = 536870912 -- Data\NPCFacts.lua: reaction = alliance * 4 + horde
local function GiverSide(questID)
    local learned = D.world and D.world.quests and D.world.quests[questID]
    local entry = learned and learned.from and D.NPCByID and D.NPCByID(learned.from)
    if not entry then return nil end
    local both = math.floor(entry.packed / REACTION_SHIFT) % 16
    local alliance, horde = math.floor(both / 4), both % 4
    if alliance == 3 and horde ~= 3 then return "Alliance" end
    if horde == 3 and alliance ~= 3 then return "Horde" end
    return nil
end
local SIDE_FACTIONS = {
    [72] = "Alliance", [47] = "Alliance", [69] = "Alliance", [54] = "Alliance", [730] = "Alliance", [890] = "Alliance",
    [509] = "Alliance",
    [76] = "Horde", [81] = "Horde", [68] = "Horde", [530] = "Horde", [729] = "Horde", [889] = "Horde", [510] = "Horde",
}
function D.QuestSide(races, reputation, questID)
    if races ~= 0 then
        if bit.band(races, HORDE) == 0 then return "Alliance" end
        if bit.band(races, ALLIANCE) == 0 then return "Horde" end
        return nil
    end
    local side
    for faction, amount in (reputation or ""):gmatch("(%d+):(%-?%d+)") do
        local s = SIDE_FACTIONS[tonumber(faction)]
        if s and tonumber(amount) > 0 then
            if side and side ~= s then return nil end
            side = s
        end
    end
    if side == nil and questID and D.questClassSide then side = CLASS_SIDES[D.questClassSide[questID] or 0] end
    if side == nil and questID then side = GiverSide(questID) end
    return side
end

local decoded = setmetatable({}, { __mode = "v" }) -- questID -> facts, weak

local function Parts(text)
    local parts = {}
    for part in (text .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
    return parts
end
local function Counts(text)
    local list = {}
    for id, count in (text or ""):gmatch("(%d+):?(%d*)") do list[#list + 1] = { tonumber(id), tonumber(count) or 1 } end
    return list
end
local function Nonzero(value) return value ~= 0 and value or nil end
local REPEATS = { "daily", "weekly" } -- head field 12

function D.QuestOf(questID)
    local q = decoded[questID]
    if q then return q end
    local text = D.questFacts and D.questFacts[questID]
    if not text then return nil end
    local parts = Parts(text)
    local head = {}
    for n in parts[1]:gmatch("[^,]+") do head[#head + 1] = tonumber(n) end
    local sort, races = head[3], head[7]
    q = {
        questID = questID, level = head[1], minLevel = head[2], sort = sort,
        area = sort > 0 and sort or nil, questSort = sort < 0 and -sort or nil,
        zone = Nonzero(head[4]), dungeon = Nonzero(head[5]), tag = head[6], races = races,
        side = D.QuestSide(races, parts[5], questID),
        classID = sort < 0 and D.questSortClass and D.questSortClass[-sort] or nil,
        skillLine = sort < 0 and D.questSortSkill and D.questSortSkill[-sort] or nil,
        nextQuest = Nonzero(head[8]), providedItem = Nonzero(head[9]), xp = head[10], money = head[11],
        repeats = D.QuestRepeats(questID), rewards = Counts(parts[2]), choices = Counts(parts[3]), spells = {}, reputation = {}, objectives = {}, startedBy = {},
    }
    for id in (parts[4] or ""):gmatch("%d+") do q.spells[#q.spells + 1] = tonumber(id) end
    for faction, amount in (parts[5] or ""):gmatch("(%d+):(%-?%d+)") do
        q.reputation[#q.reputation + 1] = { tonumber(faction), tonumber(amount) }
    end
    local texts = D.questObjectiveTexts and D.questObjectiveTexts[questID]
    for kind, id, count in (parts[6] or ""):gmatch("(%a)(%d+):(%-?%d+)") do
        local n = #q.objectives + 1
        q.objectives[n] = { kind, tonumber(id), tonumber(count), texts and texts[n] }
    end
    for id in (parts[7] or ""):gmatch("%d+") do q.startedBy[#q.startedBy + 1] = tonumber(id) end
    decoded[questID] = q
    return q
end

-- Where a logged quest is to be done now, as the world map marks it (C_QuestLog.GetQuestsOnMap;
-- a done quest: where it is turned in): a place (uiMapID * 1000000 + x * 1000 + y) on your zone's
-- map or the quest's, nil if neither marks it. Works in Forever; read once per frame per map.
local onMapCache = D.Cache({ "frame" }) -- uiMapID -> { questID -> place }
local function Marked(mapID)
    local onMap = onMapCache.Get()
    local marks = onMap[mapID]
    if marks then return marks end
    marks = {}
    for _, info in ipairs(C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        if info.questID then marks[info.questID] = D.Place(mapID, info.x, info.y) end
    end
    onMap[mapID] = marks
    return marks
end
function D.QuestPlace(questID)
    local zone = D.PlayerZone(true)
    local place = zone and Marked(zone)[questID]
    if place then return place end
    local questZone = D.QuestFact(questID, "zone")
    if questZone and questZone ~= zone then return Marked(questZone)[questID] end
    return nil
end

-- Grey: a quest of this level or below gives next to no experience to a character of that level.
-- The client's rule (GetQuestDifficultyColor): grey where the quest lies more than the green
-- range below you; classic green range (GetQuestGreenRange): 5 up to level 5, then 5 + level / 10,
-- from 40 1 + level / 5, at 60 9. The 1.12 servers' gray level (vmangos MaNGOS::XP::GetGrayLevel)
-- is the same number but they take a quest of that very level as grey; the client does not.
local MAX_LEVEL = 60
function D.GreyLevel(level)
    local range
    if level <= 5 then range = 5
    elseif level <= 39 then range = 5 + math.floor(level / 10)
    elseif level <= 59 then range = 1 + math.floor(level / 5)
    else range = 9 end
    return math.max(level - range - 1, 0)
end
-- Last character level a quest of this level is not grey for (at most MAX_LEVEL)
function D.QuestGreyAfter(questLevel)
    local level = math.max(questLevel, 1)
    while level < MAX_LEVEL and questLevel > D.GreyLevel(level + 1) do level = level + 1 end
    return level
end

-- Single facts of a quest (level, zone, races, ...; not its lists), kept for the session: the
-- weak cache above is collected, and every quest filter then decoded all 2,800 quests again
-- (13-18 ms and 7 MB garbage). One array of numbers per quest asked (false for nil), ~0.3 KB.
local SINGLE = { "level", "minLevel", "sort", "area", "questSort", "zone", "dungeon", "tag", "races", "side",
    "classID", "skillLine", "nextQuest", "providedItem", "xp", "money", "repeats" }
local SINGLE_AT = {}
for i, name in ipairs(SINGLE) do SINGLE_AT[name] = i end
local singles = {} -- questID -> array (SINGLE's order) or false: no such quest
local head = {}    -- numbers of a text's head, reused
local function Or(value) if value == nil then return false end return value end
-- Reads only the text's head (and its reputation part for the side): no lists or strings
-- for the other parts (using D.QuestOf made 7 MB of garbage for the first quest tab)
local function Single(questID)
    local s = singles[questID]
    if s == nil then
        s = false
        local text = D.questFacts and D.questFacts[questID]
        if text then
            local n = 0
            for number in text:match("^[^|]*"):gmatch("[^,]+") do
                n = n + 1
                head[n] = tonumber(number)
            end
            for i = n + 1, 12 do head[i] = nil end
            local sort, races = head[3], head[7]
            local reputation = races == 0 and text:match("^[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)") or nil
            s = { head[1], head[2], sort, Or(sort > 0 and sort or nil), Or(sort < 0 and -sort or nil),
                Or(Nonzero(head[4])), Or(Nonzero(head[5])), head[6], races, Or(D.QuestSide(races, reputation, questID)),
                Or(sort < 0 and D.questSortClass and D.questSortClass[-sort] or nil),
                Or(sort < 0 and D.questSortSkill and D.questSortSkill[-sort] or nil),
                Or(Nonzero(head[8])), Or(Nonzero(head[9])), head[10], head[11], Or(REPEATS[head[12] or 0]) }
        end
        singles[questID] = s
    end
    return s
end
-- One single fact by name (nil if none or no such quest): D.QuestFact(questID, "level");
-- cheaper than D.QuestOf
local function Fact(questID, name)
    local s = Single(questID)
    if not s then return nil end
    local value = s[SINGLE_AT[name]]
    if value == false then return nil end
    return value
end
D.QuestFact = Fact

-- May you take the quest: race, class (class quests), profession (profession quests), level;
-- takes a quest ID or its facts. Cannot tell: prerequisite quests, class/profession quests sorted under a zone.
function D.QuestForYou(quest)
    local minLevel, classID, side, races, skillLine
    if type(quest) == "table" then
        minLevel, classID, side, races, skillLine = quest.minLevel, quest.classID, quest.side, quest.races,
            quest.skillLine
    else
        if not Single(quest) then return false end
        minLevel, classID, side, races, skillLine = Fact(quest, "minLevel"), Fact(quest, "classID"),
            Fact(quest, "side"), Fact(quest, "races"), Fact(quest, "skillLine")
    end
    if minLevel == nil then return false end -- a table of no quest
    if UnitLevel("player") < minLevel then return false end
    if classID and classID ~= select(3, UnitClass("player")) then return false end
    if skillLine and D.ProfessionRanks and D.ProfessionRanks()[skillLine] == nil then return false end
    return D.QuestRaceFits(side, races)
end

function D.QuestRaceFits(side, races)
    if side and side ~= UnitFactionGroup("player") then return false end
    local raceBit = RACE_BIT[select(3, UnitRace("player")) or 0] -- nil: race unknown to the data
    return races == nil or races == 0 or raceBit == nil or math.floor(races / raceBit) % 2 == 1
end

-- The entries
-- An entry keeps its name and quest ID (and the build key); every fact above is a field computed on demand.

-- D.fields.quests exists before the domain registers (RegisterDomain keeps it)
local fields = D.fields[KEY] or {}
D.fields[KEY] = fields
for _, name in ipairs({ "level", "minLevel", "sort", "area", "questSort", "zone", "dungeon", "tag", "races", "side",
        "classID", "skillLine", "nextQuest", "providedItem", "xp", "money", "repeats", "rewards", "choices", "spells",
        "reputation", "objectives", "startedBy" }) do
    if SINGLE_AT[name] then
        fields[name] = function(entry) return Fact(entry.questID, name) end
    else
        fields[name] = function(entry)
            local q = D.QuestOf(entry.questID)
            return q and q[name]
        end
    end
end

fields.repeats = function(entry) return D.QuestRepeats(entry.questID) end

local function Collect(list, Pause)
    local meta = D.Meta(KEY)
    local count = 0
    -- only quests with facts: a title without cache data (server did not answer) has no level, zone, etc.
    local facts = D.questFacts or {}
    for questID, name in pairs(D.questNamesEN or {}) do
        if facts[questID] then
            list[#list + 1] = setmetatable({ name = name, questID = questID }, meta)
            count = count + 1
            if count % 64 == 0 then Pause() end
        end
    end
end

D.RegisterDomain({ key = KEY, background = true, collect = Collect })

-- The links
-- item ID / NPC ID -> quests (IDs, ascending), built from the facts (one pass over 2,785
-- texts) in the background after the quests are built, or on first use if that comes first.
local needItem, needNPC, rewardItem, startItem
local NONE = {}
local function NoPause() end
local function Maps(Pause)
    if needItem then return end
    Pause = Pause or NoPause
    local need, npc, reward, start = {}, {}, {}, {}
    local function Note(map, id, questID)
        local list = map[id] or {}
        map[id] = list
        if list[#list] ~= questID then list[#list + 1] = questID end
    end
    local count = 0
    for questID, text in pairs(D.questFacts or {}) do
        local parts = Parts(text)
        for _, part in ipairs({ parts[2] or "", parts[3] or "" }) do
            for id in part:gmatch("(%d+):?%d*") do Note(reward, tonumber(id), questID) end
        end
        for kind, id in (parts[6] or ""):gmatch("(%a)(%d+):") do
            if kind == "i" then Note(need, tonumber(id), questID)
            elseif kind == "n" or kind == "t" then Note(npc, tonumber(id), questID) end
        end
        for id in (parts[7] or ""):gmatch("%d+") do Note(start, tonumber(id), questID) end
        count = count + 1
        if count % 64 == 0 then Pause() end
    end
    for _, map in ipairs({ need, npc, reward, start }) do
        for _, list in pairs(map) do table.sort(list) end
        Pause()
    end
    if needItem then return end -- built by a use meanwhile
    needItem, needNPC, rewardItem, startItem = need, npc, reward, start
end
D.OnBuilt(function(key)
    if key ~= "quests" then return end
    if not needItem then D.Background("quest links", Maps) end
    -- also every quest's single facts, so the first quest tab and filter read them from cache
    D.Background("quest facts", function(Pause)
        local count = 0
        for questID in pairs(D.questFacts or {}) do
            Single(questID)
            count = count + 1
            if count % 128 == 0 then Pause() end
        end
    end)
end)
function D.QuestsNeedingItem(itemID)
    Maps()
    return needItem[itemID] or NONE
end
function D.QuestsNeedingNPC(npcID)
    Maps()
    return needNPC[npcID] or NONE
end
function D.QuestsRewardingItem(itemID)
    Maps()
    return rewardItem[itemID] or NONE
end
-- Quests an item begins (ItemSparse; Forever's hotfix-added items are missing)
function D.QuestsStartedByItem(itemID)
    Maps()
    return startItem[itemID] or NONE
end
