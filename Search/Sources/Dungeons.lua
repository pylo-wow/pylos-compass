local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Dungeons: the instances of the game, dungeons and raids with the levels they are meant for, how many
-- players, the zone of the entrance (searchable: "Westfall" finds the Deadmines) and the bosses in order.
-- Entries come from the data layer (World\Dungeons.lua). Opened without text: all by level, dungeons before
-- raids of the same level. Tabs: dungeons, raids; filter: your level. No action.

-- texts (kind, levels, raid size) and tooltip lines: World\Lines.lua, shared with the recommendations
local KINDS, Levels, Players = D.DUNGEON_KINDS, D.DungeonLevelText, D.DungeonPlayersText

local function ZoneName(id)
    local info = id > 0 and C_Map.GetMapInfo(id)
    return info and info.name or nil
end

local function Describe(entry)
    return { KINDS[entry.kind], Players(entry), ZoneName(entry.zone) }
end

-- Row state (UI\List.lua): its levels ("Level 18-25") colored as the game colors a foe's level: by where
-- it starts while you are below it, even (yellow) within it, by where it ends once you are above it
-- (green, then grey)
local function State(entry)
    if entry.side and entry.side ~= UnitFactionGroup("player") then return L[entry.side .. " only"], "no" end
    if entry.level <= 0 then return nil end
    local text = Levels(entry)
    local level = UnitLevel("player")
    if level < entry.level then return text, ns.ConColor(entry.level) end
    local _, top = D.DungeonLevelRange(entry)
    if top and level > top then return text, ns.ConColor(top) end
    return text, ns.ConColor(level)
end

-- a dungeon's quests (map ID -> list), rebuilt only when the data layer rebuilt the quests
local questsOf = D.Cache({ "data:quests" })
local NONE = {}
local function DungeonQuests(mapID)
    local byDungeon, renewed = questsOf.Get()
    if renewed then
        for _, quest in ipairs(D.Entries("quests")) do
            local dungeon = quest.dungeon
            if dungeon then
                byDungeon[dungeon] = byDungeon[dungeon] or {}
                table.insert(byDungeon[dungeon], quest)
            end
        end
    end
    return byDungeon[mapID] or NONE
end

-- Tooltip's For you (UI\Tooltip.lua): its quests in your log, and the ones you may take
local function ForYou(entry, add)
    local inLog, toTake = 0, 0
    for _, quest in ipairs(DungeonQuests(entry.mapID)) do
        if C_QuestLog.IsOnQuest(quest.questID) == true then
            inLog = inLog + 1
        elseif not C_QuestLog.IsQuestFlaggedCompleted(quest.questID) and D.QuestForYou(quest) then
            toTake = toTake + 1
        end
    end
    if inLog > 0 then add(L["Quests in your log: %d"]:format(inLog), "active") end
    if toTake > 0 then add(L["Quests for you: %d"]:format(toTake), "good") end
end

local source

-- without text: by level (unknown last), a dungeon before a raid of the
-- same level, then A-Z; one list without headings
local function Browse(take)
    local sorted = {}
    for i, entry in ipairs(source.index.entries) do sorted[i] = entry end
    local function Level(entry) return entry.level > 0 and entry.level or 999 end
    table.sort(sorted, function(a, b)
        if Level(a) ~= Level(b) then return Level(a) < Level(b) end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.key < b.key
    end)
    for _, entry in ipairs(sorted) do take(entry) end
end

-- Filters: what fits your level (D.DungeonLevelFit), dungeons, raids
ns.RegisterFilter({
    key = "dungeonsLevel", name = L["Your level"], sources = { "dungeons" },
    description = L["Dungeons and raids meant for your level, as the group browser lists them."],
    words = "level fitting current",
    icon = "Interface\\Icons\\Achievement_Level_10",
    test = function(entry) return D.DungeonLevelFit(entry) ~= nil end,
})
ns.RegisterFilter({
    key = "dungeonsDungeon", name = L["Dungeons"], sources = { "dungeons" }, subcategory = true,
    description = L["Only dungeons, for five to ten players."],
    words = "dungeon instance",
    icon = 136334, -- LFGIcon-Dungeon
    static = true,
    test = function(entry) return entry.kind == 1 end,
})
ns.RegisterFilter({
    key = "dungeonsRaid", name = L["Raids"], sources = { "dungeons" }, subcategory = true,
    description = L["Only raids, for twenty to forty players."],
    words = "raid",
    icon = 136351, -- LFGIcon-Raid
    static = true,
    test = function(entry) return entry.kind == 2 end,
})

-- WoW Forever's group finder symbol (the green eye), from the micro menu
local symbolAtlas, symbolFile = ns.MicroMenuSymbol("LFDMicroButton", "LFGMicroButton", "GroupFinderMicroButton")

source = ns.RegisterSource({
    key = "dungeons",
    domain = "dungeons",
    name = L["Dungeons & raids"],
    hint = L["Search dungeons and raids"],
    icon = symbolFile or "Interface\\Icons\\INV_Misc_Key_03",
    iconAtlas = symbolAtlas or "ui-hud-micromenu-groupfinder-up-c60-2x",
    browse = Browse,
    browseFiltered = true, -- with a filter set too: the order by level stays
    describe = Describe,
    state = State,
    forYou = ForYou,
})
