local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Quests: every quest of the game (World\Quests.lua: the client's quest cache), searchable by
-- name. Here only how they are shown:
--   row      quest symbol (a dungeon's or raid's for those), grey once done; below the name its level,
--            zone (or class, profession), the side if only one may take it, in your log or done
--   tooltip  and detail view: what it asks for and gives, who gives and takes it (learned in play),
--            the quest after it (lines: World\Lines.lua)
--   links    (Links\Quests.lua) its objectives, rewards, giver, taker and next quest; for items and
--            NPCs the quests they belong to
-- Opened without text: your quest log (its filter set by itself); with no filter only the hint to
-- type or pick one. Filters: your level, in your log, not done, done, too low (grey for you), in your
-- zone. No action.

-- WoW Forever's quest log symbol (the micro menu's exclamation mark): atlas ui-hud-micromenu-questlog-up-c60-2x
-- is not known at run time, so its measured part of the file is used (UI\Kit\Widgets.lua)
local QUEST_PART = ns.widgets.QUEST_PART
local LEVEL_BELOW, LEVEL_ABOVE = ns.LEVEL_BELOW, ns.LEVEL_ABOVE

local function InLog(entry)
    return C_QuestLog.IsOnQuest(entry.questID) == true
end
local function Done(entry)
    return C_QuestLog.IsQuestFlaggedCompleted(entry.questID) == true
end

-- row texts and tooltip lines: World\Lines.lua, shared with the recommendations
local Belongs = D.QuestBelongs

-- line below the name: kind (elite, dungeon, raid, PvP; daily, weekly), where (zone or dungeon; class,
-- profession); level and whether it is in your log, done or for you are the row's state
local TAG = D.QUEST_TAG
local TAGS = { [TAG.ELITE] = L["Elite"], [TAG.DUNGEON] = L["Dungeon"], [TAG.RAID] = L["Raid"], [TAG.PVP] = L["PvP"] }
local REPEATS = { daily = L["Daily"], weekly = L["Weekly"] }
local function Describe(entry)
    local kind = TAGS[entry.tag]
    local again = REPEATS[entry.repeats]
    if kind and again then kind = kind .. ns.widgets.DOT .. again end
    return { kind or again, Belongs(entry) }
end

-- Row state (UI\List.lua): in your log (ready to turn in), done, not for you (side, race, class), the level
-- it may be taken at while above yours; else its level in the color the quest log gives it
local function State(entry)
    local questID = entry.questID
    if C_QuestLog.IsOnQuest(questID) == true then
        if C_QuestLog.IsComplete(questID) then return L["Ready"], "good" end
        return L["In your log"], "active"
    end
    if C_QuestLog.IsQuestFlaggedCompleted(questID) == true then return L["Done"], "done" end
    -- a world event not running now: the event, grey
    local away = D.EventAway(entry)
    if away then return away, "done" end
    if entry.side and entry.side ~= UnitFactionGroup("player") then return L[entry.side .. " only"], "no" end
    if not D.QuestRaceFits(entry.side, entry.races) then return L["Not your race"], "no" end
    if entry.classID and entry.classID ~= select(3, UnitClass("player")) then return L["Other class"], "no" end
    if (entry.minLevel or 0) > UnitLevel("player") then return L["From level %d"]:format(entry.minLevel), "no" end
    if entry.level <= 0 then return nil end
    return L["Level %d"]:format(entry.level), ns.ConColor(entry.level)
end

-- Tooltip's For you (UI\Tooltip.lua): in your log your progress as the quest log words it (green: done),
-- ready to turn in; else a quest it needs first that you have not done (1.12 data, unchecked)
local function QuestName(questID)
    local quest = D.EntryByID("q:" .. questID)
    return quest and quest.name or ("#" .. questID)
end
local function DoneID(questID) return C_QuestLog.IsQuestFlaggedCompleted(questID) == true end
local function ForYou(entry, add)
    local questID = entry.questID
    if C_QuestLog.IsOnQuest(questID) == true then
        if C_QuestLog.IsComplete(questID) then add(L["Ready to turn in"], "good") end
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
            if objective.text and objective.text ~= "" then
                add(objective.text, objective.finished and "good" or "active")
            end
        end
        return
    end
    if DoneID(questID) then return end
    local before = D.QuestPrevious(questID)
    if not before then return end
    local anyDone = #before.anyOf == 0
    for _, id in ipairs(before.anyOf) do if DoneID(id) then anyDone = true end end
    if not anyDone then
        add(L["First: %s"]:format(QuestName(before.anyOf[1])) .. " " .. D.UNCHECKED, "no")
    end
    for _, id in ipairs(before.allOf) do
        if not DoneID(id) then add(L["First: %s"]:format(QuestName(id)) .. " " .. D.UNCHECKED, "no") end
    end
end

-- level and zone are read once per search (prepare), not per quest
local level, grey, zone = 1, 0, nil -- yours, the highest grey quest level, your zone

ns.RegisterFilter({
    key = "questsLevel", name = L["Your level"], sources = { "quests" },
    description = L["Quests near your level that your character may take."],
    words = "level fitting current",
    icon = "Interface\\Icons\\Achievement_Level_10",
    prepare = function() level = UnitLevel("player") end,
    test = function(entry)
        return entry.level >= level - LEVEL_BELOW and entry.level <= level + LEVEL_ABOVE and D.QuestForYou(entry)
            and not Done(entry)
    end,
})
ns.RegisterFilter({
    key = "questsLog", name = L["In your log"], sources = { "quests" },
    description = L["The quests in your quest log."],
    words = "log active current",
    icon = "Interface\\Icons\\INV_Misc_Book_08",
    test = InLog,
})
ns.RegisterFilter({
    key = "questsOpen", name = L["Not done"], sources = { "quests" },
    description = L["Quests your character has not turned in yet and may take."],
    words = "open undone todo",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    test = function(entry) return not Done(entry) and D.QuestForYou(entry) end,
})

-- Your class's quests as a subcategory (tab). Known by the game's own sort (QuestSort: 376 of them); the few
-- class quests sorted under a zone are not among them. Professions not: their sort is no sure sign.
-- Only those your race may take (most class quests are open to every race).
local playerClass = select(3, UnitClass("player"))
ns.RegisterFilter({
    key = "questsClass", name = L["Class quests"], sources = { "quests" }, subcategory = true,
    description = L["The quests of your class."],
    words = "class",
    icon = "Interface\\Icons\\ClassIcon_" .. (select(2, UnitClass("player")) or "Warrior"),
    static = true,
    test = function(entry)
        return entry.classID ~= nil and entry.classID == playerClass and D.QuestRaceFits(entry.side, entry.races)
    end,
})

-- Dungeon and raid quests as a subcategory: sorted under a dungeon (entry.dungeon), else tagged dungeon
-- or raid (a few are sorted under a zone); only those your race may take. Listed under their dungeon's
-- heading, the dungeons by level (BrowseDungeons).
local INSTANCE_TAGS = { [D.QUEST_TAG.DUNGEON] = true, [D.QUEST_TAG.RAID] = true }
local function IsDungeonQuest(entry) return entry.dungeon ~= nil or INSTANCE_TAGS[entry.tag] == true end
ns.RegisterFilter({
    key = "questsDungeon", name = L["Dungeon quests"], sources = { "quests" }, subcategory = true,
    description = L["Quests in dungeons and raids, by dungeon."],
    words = "dungeon raid instance",
    icon = 136334, -- LFGIcon-Dungeon
    static = true,
    test = function(entry) return IsDungeonQuest(entry) and D.QuestRaceFits(entry.side, entry.races) end,
})

ns.RegisterFilter({
    key = "questsDone", name = L["Done"], sources = { "quests" },
    description = L["Quests your character has turned in."],
    words = "done finished completed",
    icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
    test = Done,
})
-- grey for you (D.GreyLevel: next to no experience)
ns.RegisterFilter({
    key = "questsLow", name = L["Too low"], sources = { "quests" },
    description = L["Quests grey for you: far below your level, next to no experience."],
    words = "low grey gray trivial",
    icon = "Interface\\Icons\\INV_Misc_Note_02",
    prepare = function() grey = D.GreyLevel(UnitLevel("player")) end,
    test = function(entry) return entry.level <= grey end,
})
ns.RegisterFilter({
    key = "questsZone", name = L["In your zone"], sources = { "quests" },
    description = L["Quests of the zone you are in."],
    words = "zone here area",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    prepare = function() zone = D.PlayerZone(true) end,
    test = function(entry) return zone ~= nil and entry.zone == zone end,
})

-- Opened without text: with a filter ("In your log" is set by itself) every quest that passes, by level,
-- then A-Z; without one only the hint. The order is kept until the data layer rebuilds its quests.
local sorted = D.Cache({ "data:quests" })
local function ByLevel(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.key < b.key
end
-- the dungeon quests under their dungeon's heading: the dungeons by their
-- lowest level, then name; quests of no known dungeon last
local OTHER = 1000
local function DungeonKey(entry)
    if not entry.dungeon then return OTHER, L["Other dungeon quests"] end
    return D.DungeonMinLevel(entry.dungeon), D.DungeonName(entry.dungeon) or L["Other dungeon quests"]
end
local function BrowseDungeons(take, list)
    local quests, levels, names = {}, {}, {}
    for _, entry in ipairs(list) do
        if IsDungeonQuest(entry) then
            quests[#quests + 1] = entry
            levels[entry], names[entry] = DungeonKey(entry)
        end
    end
    local at = {}
    for i, entry in ipairs(quests) do at[entry] = i end
    table.sort(quests, function(a, b)
        if levels[a] ~= levels[b] then return levels[a] < levels[b] end
        if names[a] ~= names[b] then return names[a] < names[b] end
        return at[a] < at[b]
    end)
    for _, entry in ipairs(quests) do take(entry, names[entry]) end
end
local function Browse(take, filters)
    if #(filters or {}) == 0 then return end
    local list, renewed = sorted.Get()
    if renewed then
        for i, entry in ipairs(D.Entries("quests")) do list[i] = entry end
        table.sort(list, ByLevel)
    end
    for _, f in ipairs(filters) do
        if f.key == "questsDungeon" then return BrowseDungeons(take, list) end
    end
    for _, entry in ipairs(list) do take(entry) end
end

ns.RegisterSource({
    key = "quests",
    domain = "quests",
    name = L["Quests"],
    emptyHint = L["Type to search, or pick a filter."],
    icon = "Interface\\Icons\\INV_Misc_Book_08",
    iconPart = QUEST_PART,
    defaultFilters = { "questsLog" }, -- opened: your quest log
    browse = Browse,
    browseFiltered = true, -- with a filter set too: the order by level stays
    describe = Describe,
    state = State,
    forYou = ForYou,
})
