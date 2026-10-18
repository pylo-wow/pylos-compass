local _, D = ...
if D.off then return end

-- Zones that have quests (Data\QuestFacts.lua: a quest's zone), as entries { name, zoneID }
-- with ID "z:<uiMapID>", and what their quests say: the levels they are for and how many are
-- open for you now. Built only when asked for (D.Need).
--   D.ZoneLevels(zoneID)  low, high: levels of most of its quests (middle 80 %), nil if none
--   D.ZoneQuests(zoneID, low, high)  how many of its quests you can take now and have not
--                         done, of level low to high (dungeon and raid quests excluded: need a group)

local KEY = "zones"
local ICON = 134269 -- INV_Misc_Map_01

-- Per zone, the quest facts the counting needs, packed once: zone -> { questID, level,
-- minLevel, races, classID (0 none), side (0 both, 1 Alliance, 2 Horde: D.QuestSide), ... },
-- six numbers each (decoding all quests took 17 ms)
local byZone
local RACE_BIT = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [95] = 256, [96] = 512 }

local function Index()
    if byZone then return byZone end
    byZone = {}
    local TAG = D.QUEST_TAG
    for questID, text in pairs(D.questFacts or {}) do
        local head, reputation = text:match("^([^|]*)|[^|]*|[^|]*|[^|]*|([^|]*)")
        head = head or text:match("^[^|]*")
        local n = {}
        for v in head:gmatch("[^,]+") do n[#n + 1] = tonumber(v) end
        local level, minLevel, sort, zone, dungeon, tag, races = n[1], n[2], n[3], n[4], n[5], n[6], n[7]
        if zone and zone ~= 0 and (dungeon or 0) == 0 and tag ~= TAG.DUNGEON and tag ~= TAG.RAID then
            local class = sort < 0 and D.questSortClass and D.questSortClass[-sort] or 0
            local list = byZone[zone] or {}
            byZone[zone] = list
            local side = D.QuestSide(races, reputation)
            local i = #list
            list[i + 1], list[i + 2], list[i + 3], list[i + 4], list[i + 5] = questID, level, minLevel, races, class
            list[i + 6] = side == "Alliance" and 1 or side == "Horde" and 2 or 0
        end
    end
    return byZone
end

function D.ZoneLevels(zoneID)
    local list = Index()[zoneID]
    if not list then return nil end
    local levels = {}
    for i = 2, #list, 6 do levels[#levels + 1] = list[i] end
    table.sort(levels)
    local n = #levels
    return levels[math.max(1, math.floor(n * 0.1 + 0.5))], levels[math.max(1, math.ceil(n * 0.9))]
end

function D.ZoneQuests(zoneID, low, high)
    local list = Index()[zoneID]
    if not list then return 0 end
    local level = UnitLevel("player")
    local raceBit = RACE_BIT[select(3, UnitRace("player")) or 0]
    local classID = select(3, UnitClass("player"))
    local done = C_QuestLog.IsQuestFlaggedCompleted
    local mySide = UnitFactionGroup("player") == "Horde" and 2 or 1
    local count = 0
    for i = 1, #list, 6 do
        local questID, qLevel, minLevel, races, class, side = list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4], list[i + 5]
        if qLevel >= low and qLevel <= high and minLevel <= level and (class == 0 or class == classID)
                and (side == 0 or side == mySide)
                and (races == 0 or not raceBit or math.floor(races / raceBit) % 2 == 1)
                and not done(questID) then
            count = count + 1
        end
    end
    return count
end

local function Continent(info)
    local parent = info and info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
    return parent and parent.name or nil
end

local function Collect(list)
    local meta = D.Meta(KEY)
    for zoneID in pairs(Index()) do
        local info = C_Map.GetMapInfo(zoneID)
        if info and info.name and info.name ~= "" then
            list[#list + 1] = setmetatable({ name = info.name, zoneID = zoneID, category = Continent(info) }, meta)
        end
    end
end

local fields = D.fields[KEY] or {}
D.fields[KEY] = fields
fields.icon = function() return ICON end

D.RegisterDomain({ key = KEY, collect = Collect })
