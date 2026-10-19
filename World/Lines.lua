local _, D = ...

-- Tooltip lines, icons and categories for NPCs, quests and dungeons (entry.lines, entry.icon,
-- entry.category; quests also entry.iconPart and entry.iconColor), so every host shows the same.
-- entry.lines: list of { text, role, wrap }. The role names a style guide colour that the host
-- applies (UI\Kit\Widgets.lua: W.EntryText): "white" (default), "soft", "sub", "gold",
-- "blue" (places), "orange" (one faction only), "green" (done, ready).
-- A line { " " } is a gap.

local DOT = D.DOT

-- entry.creatureType names (12, 14: Forever's creature cache)
D.NPC_TYPE_NAMES = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter",
    "Mechanical", nil, "Totem", "Non-combat Pet", nil, "Wild Pet" }
local RANKS = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
local ROLES = { { 1, "Vendor" }, { 2, "Trainer" }, { 4, "Quest giver" }, { 8, "Flight master" },
    { 16, "Innkeeper" }, { 32, "Banker" }, { 64, "Auctioneer" }, { 128, "Repair" } }
-- Icons by creature type (entry.creatureType) and role (first match wins, in ROLES order), for
-- NPCs without a portrait (a host draws entry.displayID where it can)
local TYPE_ICONS = { "Ability_Hunter_Pet_Wolf", "INV_Misc_Head_Dragon_01", "Spell_Shadow_SummonFelHunter",
    "Spell_Fire_Elemental_Totem", "Ability_Warrior_StrengthOfArms", "Spell_Shadow_RaiseDead", "INV_Misc_Head_Human_01",
    "Ability_Hunter_Pet_Crab", "INV_Misc_Gear_01" }
local ROLE_ICONS = { { 1, "INV_Misc_Coin_01" }, { 2, "INV_Misc_Book_09" }, { 4, "INV_Misc_Note_01" },
    { 8, "Ability_Mount_MechaStrider" }, { 16, "INV_Misc_Bag_10_Blue" }, { 32, "INV_Misc_Coin_01" },
    { 64, "INV_Misc_Coin_01" }, { 128, "INV_Misc_Gear_01" } }

D.fields.npcs.icon = function(entry)
    local roles = entry.roles
    for _, role in ipairs(ROLE_ICONS) do
        if math.floor(roles / role[1]) % 2 == 1 then return "Interface\\Icons\\" .. role[2] end
    end
    return "Interface\\Icons\\" .. (TYPE_ICONS[entry.creatureType] or "INV_Misc_QuestionMark")
end
D.fields.npcs.category = function(entry)
    if entry.title ~= "" then return entry.title end
    return D.NPC_TYPE_NAMES[entry.creatureType] or ""
end

function D.NPCZoneNames(entry)
    local names = {}
    for _, id in ipairs(D.NPCZones(entry)) do
        local info = C_Map.GetMapInfo(id)
        if info and info.name then names[#names + 1] = info.name end
    end
    return names
end

function D.NPCLevelText(entry)
    local low, high = entry.levelMin, entry.levelMax
    if high == 0 then return nil end
    if low == high then return ("Level %d"):format(low) end
    return ("Level %d-%d"):format(low, high)
end

-- Facts only the 1.12 data gives (not yet seen in Forever) are marked (D.NPCOrigin, LearnNPCs.lua)
D.UNCHECKED = "(unchecked)"
local function Unchecked(text, origin)
    if text and origin == "1.12" then return text .. " " .. D.UNCHECKED end
    return text
end

-- Roles seen in Forever, and roles only the 1.12 data gives
local function RoleTexts(entry)
    local seen, unchecked = {}, {}
    for _, role in ipairs(ROLES) do
        local origin = D.NPCRoleOrigin(entry, role[1])
        if origin == "seen" then seen[#seen + 1] = role[2]
        elseif origin then unchecked[#unchecked + 1] = role[2] end
    end
    return #seen > 0 and table.concat(seen, DOT) or nil,
        #unchecked > 0 and Unchecked(table.concat(unchecked, DOT), "1.12") or nil
end

-- Zones: the one you met the NPC in, then the 1.12 data's (unchecked)
local function ZoneText(entry)
    local zones = D.NPCZones(entry)
    local met = D.MetZone(entry.npcID)
    local first, rest = nil, {}
    for _, id in ipairs(zones) do
        local info = C_Map.GetMapInfo(id)
        if info and info.name then
            if id == met then first = info.name else rest[#rest + 1] = info.name end
        end
    end
    local others = #rest > 0 and Unchecked(table.concat(rest, ", "), "1.12") or nil
    if first and others then return first .. DOT .. others end
    return first or others
end

D.fields.npcs.lines = function(entry)
    local lines = {}
    if not entry.hasFacts then
        lines[1] = { "No data for this NPC yet (new in WoW Forever).", "sub", true }
        return lines
    end
    if entry.title ~= "" then lines[#lines + 1] = { entry.title, "soft" } end
    -- Level only for NPCs you can attack (a vendor's says nothing)
    local attackable = entry.reaction == 1 or entry.reaction == 2
    local about = { attackable and Unchecked(D.NPCLevelText(entry), D.NPCOrigin(entry, "level")) or nil,
        D.NPC_TYPE_NAMES[entry.creatureType], RANKS[entry.npcRank] }
    local text = {}
    for i = 1, 3 do -- not ipairs: a hole (no type name) would hide the rank
        if about[i] then text[#text + 1] = about[i] end
    end
    if #text > 0 then lines[#lines + 1] = { table.concat(text, DOT) } end
    local roles, uncheckedRoles = RoleTexts(entry)
    if roles then lines[#lines + 1] = { roles, "gold" } end
    if uncheckedRoles then lines[#lines + 1] = { uncheckedRoles, "sub" } end
    local zones = ZoneText(entry)
    if zones then lines[#lines + 1] = { zones, "blue", true } end
    return lines
end

local TAG = D.QUEST_TAG
local TAG_NAMES = { [TAG.ELITE] = "Elite", [TAG.DUNGEON] = "Dungeon", [TAG.RAID] = "Raid", [TAG.PVP] = "PvP" }

-- Icon: dungeon finder icons for dungeon/raid quests, else the quest log micro menu
-- exclamation mark cut from its file: iconPart = { file ID, left, right, top, bottom }.
-- The atlas ui-hud-micromenu-questlog-up-c60-2x is unknown to the client at run time (seen in
-- game); same numbers as W.QUEST_PART in UI\Kit\Widgets.lua: file 8200846 is 1024 x 512, the
-- cell from DB2 UiTextureAtlasMember x 397, y 169. Grey once done (iconColor tints the icon).
local QUEST_ICON, DUNGEON_ICON, RAID_ICON = 134327, 136334, 136351 -- INV_Misc_Note_01, LFGIcon-Dungeon, -Raid
local QUEST_PART = { 8200846, (397 + 4.5) / 1024, (397 + 58.5) / 1024, (169 + 13.5) / 512, (169 + 67.5) / 512 }
local DONE_COLOR = { 0.45, 0.45, 0.45 }
local function GroupQuest(entry) return entry.tag == TAG.RAID or entry.tag == TAG.DUNGEON or entry.dungeon ~= nil end
D.fields.quests.icon = function(entry)
    if entry.tag == TAG.RAID then return RAID_ICON end
    if GroupQuest(entry) then return DUNGEON_ICON end
    return QUEST_ICON
end
D.fields.quests.iconPart = function(entry)
    if GroupQuest(entry) then return nil end
    return QUEST_PART
end
D.fields.quests.iconColor = function(entry)
    if C_QuestLog.IsQuestFlaggedCompleted(entry.questID) == true then return DONE_COLOR end
    return nil
end

-- "Level 10 (6-16)": quest level, from the minimum level to the last level it is not grey for
function D.QuestLevelText(entry)
    return ("Level %d (%d-%d)"):format(entry.level, math.max(entry.minLevel, 1), D.QuestGreyAfter(entry.level))
end

-- English dungeon name and entrance zone (uiMapID or nil) by map ID; built on first use
local dungeonsByMap
local function DungeonData(mapID)
    if not dungeonsByMap then
        dungeonsByMap = {}
        for _, d in ipairs(D.dungeons or {}) do dungeonsByMap[d[1]] = d end
    end
    local d = dungeonsByMap[mapID]
    if d then return d[2], d[6] ~= 0 and d[6] or nil end
    return nil
end
-- Client's localized instance name, nil if none. GetRealZoneText(mapID) may ignore the ID and
-- name your current zone, so that answer is rejected outside the instance.
local function ClientDungeonName(mapID)
    if not GetRealZoneText then return nil end
    local name = GetRealZoneText(mapID)
    if not name or name == "" then return nil end
    if name == GetRealZoneText() and select(8, GetInstanceInfo()) ~= mapID then return nil end
    return name
end
-- Instance name (client's, else the data's English one) and lowest level (0: unknown), by map ID
function D.DungeonName(mapID)
    return ClientDungeonName(mapID) or (DungeonData(mapID))
end
function D.DungeonMinLevel(mapID)
    DungeonData(mapID)
    local d = dungeonsByMap[mapID]
    return d and d[5] or 0
end
-- Dungeon quest place: client name (plus English name in brackets if different and long is
-- set), then the entrance zone if known
local function DungeonPlace(mapID, long)
    local english, zone = DungeonData(mapID)
    local name = ClientDungeonName(mapID) or english
    if not name then return nil end
    if long and english and english ~= name then name = ("%s (%s)"):format(name, english) end
    local info = zone and C_Map.GetMapInfo(zone)
    if info and info.name then name = name .. DOT .. info.name end
    return name
end

-- What a quest belongs to: dungeon (dungeon quests), zone, else class or profession.
-- long: for the tooltip (dungeon also in English)
function D.QuestBelongs(entry, long)
    if entry.dungeon then
        local place = DungeonPlace(entry.dungeon, long)
        if place then return place end
    end
    local info = entry.zone and C_Map.GetMapInfo(entry.zone)
    if info and info.name then return info.name end
    if entry.classID then return (GetClassInfo(entry.classID)) end
    if entry.skillLine then return D.professionNames[entry.skillLine] end
    return nil
end

function D.QuestState(entry)
    if C_QuestLog.IsOnQuest(entry.questID) == true then return "In your log" end
    if C_QuestLog.IsQuestFlaggedCompleted(entry.questID) == true then return "Done" end
    return nil
end

local function ItemName(itemID) return D.itemNamesEN[itemID] or ("#" .. itemID) end
local function NPCName(npcID) return D.npcNamesEN and D.npcNamesEN[npcID] or ("#" .. npcID) end
local function QuestName(questID) return D.questNamesEN and D.questNamesEN[questID] or ("#" .. questID) end
local function Count(name, count) return count > 1 and (name .. " ×" .. count) or name end

local OBJECTIVES = {
    n = function(id, count) return ("Defeat %s: %d"):format(NPCName(id), count) end,
    t = function(id) return ("Talk to %s"):format(NPCName(id)) end,
    i = function(id, count) return ("Collect %s: %d"):format(ItemName(id), count) end,
    o = function() return "Use an object" end,
    r = function() return "Reach a standing with a faction" end,
    m = function(_, count) return ("Bring %s"):format(D.Money(count)) end,
}

D.fields.quests.lines = function(entry)
    local lines = {}
    local head = D.QuestLevelText(entry)
    local tag = TAG_NAMES[entry.tag]
    if tag then head = head .. DOT .. tag end
    if entry.repeats then head = head .. DOT .. (entry.repeats == "daily" and "Daily" or "Weekly") end
    lines[#lines + 1] = { head }
    local belongs = D.QuestBelongs(entry, true)
    if belongs then lines[#lines + 1] = { belongs, "blue" } end
    if entry.side then lines[#lines + 1] = { ("%s only"):format(entry.side), "orange" } end
    local state = D.QuestState(entry)
    if state then lines[#lines + 1] = { state, "green" } end
    if #entry.objectives > 0 then
        lines[#lines + 1] = { " " }
        lines[#lines + 1] = { "Objectives", "gold" }
        for _, o in ipairs(entry.objectives) do
            -- Prefer the quest log's own text ("Speak with ...", "Explore ..."; it also names the
            -- real creature where the objective counts a stand-in), with the count if more than one
            local counted = o[3] > 1 and o[1] ~= "r" and o[1] ~= "m"
            local text = o[4] and (counted and ("%s: %d"):format(o[4], o[3]) or o[4])
                or OBJECTIVES[o[1]] and OBJECTIVES[o[1]](o[2], o[3])
            if text then lines[#lines + 1] = { text } end
        end
    end
    local gives = {}
    if (entry.xp or 0) > 0 then gives[#gives + 1] = ("%d XP"):format(entry.xp) end
    if (entry.money or 0) > 0 then gives[#gives + 1] = D.Money(entry.money) end
    if #gives > 0 or #entry.rewards > 0 or #entry.choices > 0 then
        lines[#lines + 1] = { " " }
        lines[#lines + 1] = { "Rewards", "gold" }
        if #gives > 0 then lines[#lines + 1] = { table.concat(gives, DOT) } end
        for _, r in ipairs(entry.rewards) do lines[#lines + 1] = { Count(ItemName(r[1]), r[2]) } end
        if #entry.choices > 0 then
            lines[#lines + 1] = { "Choose one:", "soft" }
            for _, r in ipairs(entry.choices) do lines[#lines + 1] = { "  " .. Count(ItemName(r[1]), r[2]) } end
        end
    end
    local kind, id, _, origin = D.QuestGiver(entry.questID)
    local takerKind, takerID, _, takerOrigin = D.QuestTaker(entry.questID)
    if kind or takerKind or entry.nextQuest then lines[#lines + 1] = { " " } end
    if kind == "npc" then lines[#lines + 1] = { Unchecked(("Given by %s"):format(NPCName(id)), origin), "soft" }
    elseif kind == "item" then lines[#lines + 1] = { ("Begins with %s"):format(ItemName(id)), "soft" } end
    if takerKind == "npc" then lines[#lines + 1] = { Unchecked(("Turned in at %s"):format(NPCName(takerID)), takerOrigin), "soft" } end
    if entry.nextQuest then lines[#lines + 1] = { ("Then: %s"):format(QuestName(entry.nextQuest)), "soft" } end
    return lines
end

D.DUNGEON_KINDS = { "Dungeon", "Raid" } -- entry.kind

local function DungeonZone(entry)
    local info = entry.zone > 0 and C_Map.GetMapInfo(entry.zone)
    return info and info.name or nil
end

-- Group browser range ("Level 15-24", or "Level 60"), else "From level 13"; nil if none
function D.DungeonLevelText(entry)
    if entry.maxLevel > entry.level then return ("Level %d-%d"):format(entry.level, entry.maxLevel) end
    if entry.maxLevel > 0 then return ("Level %d"):format(entry.level) end
    if entry.level > 0 then return ("From level %d"):format(entry.level) end
end

-- Raid size only; the client's Map table says 10 for most five-player dungeons (seen in game)
function D.DungeonPlayersText(entry)
    if entry.kind == 2 and entry.players > 0 then return ("%d players"):format(entry.players) end
end

D.fields.dungeons.lines = function(entry)
    local lines = {}
    local what = D.DUNGEON_KINDS[entry.kind]
    local players = D.DungeonPlayersText(entry)
    if players then what = what .. DOT .. players end
    lines[#lines + 1] = { what }
    local levels = D.DungeonLevelText(entry)
    if levels then lines[#lines + 1] = { levels } end
    local zone = DungeonZone(entry)
    if zone then
        -- the entrance is the 1.12 data's until you walked in (Dungeons.lua)
        lines[#lines + 1] = { Unchecked(("Entrance: %s"):format(zone), not entry.entranceSeen and "1.12" or nil), "blue" }
    end
    local bosses = D.DungeonBosses(entry)
    if #bosses > 0 then
        lines[#lines + 1] = { " " }
        lines[#lines + 1] = { "Bosses", "gold" }
        for _, boss in ipairs(bosses) do lines[#lines + 1] = { boss[1] } end
    end
    return lines
end
