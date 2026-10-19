local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- More links: where an ore or herb is gathered, an NPC's zones, what a recipe item and a trainer teach,
-- a spell's ranks, the quest before, a dungeon's loot and quests. Which links come first: Links\Order.lua.

local LinkedItem, LinkedEntry = ns.LinkedItem, ns.LinkedEntry
local ZONE_ICON = 134269

-- A zone as a row: its name, the continent below, its levels on the right colored by how hard it is
-- for you (as a dungeon's), info below on the right; Enter opens the world map at it
local function ZoneRow(zoneID, info)
    local map = C_Map.GetMapInfo(zoneID)
    if not (map and map.name) then return nil end
    local parent = map.parentMapID and C_Map.GetMapInfo(map.parentMapID)
    local row = { name = map.name, icon = ZONE_ICON, key = D.SearchKey(map.name), zoneID = zoneID,
        details = parent and parent.name or nil, category = info or "" }
    local low, high = D.ZoneLevels(zoneID)
    if low then
        row.stateText = low == high and L["Level %d"]:format(low) or L["Level %d-%d"]:format(low, high)
        local yours = UnitLevel("player")
        row.stateTone = ns.ConColor(yours < low and low or yours > high and high or yours)
    end
    -- the map would open behind the search
    row.open = function()
        ns.Close()
        if OpenWorldMap then OpenWorldMap(zoneID) end
    end
    row.low, row.high = low, high
    return row
end

-- Zones in the order that suits you: the one you are in, then those of your continent, then by how near
-- their levels are to yours; the given order (the fullest first) breaks ties.
local function OrderZones(rows)
    local here = D.PlayerZone()
    local map = here and C_Map.GetMapInfo(here)
    local continent = map and map.parentMapID
    local level = UnitLevel("player")
    local score, at = {}, {}
    for i, row in ipairs(rows) do
        at[row] = i
        local zone = C_Map.GetMapInfo(row.zoneID)
        local gap = row.low
            and (level < row.low and row.low - level or level > row.high and level - row.high or 0) or 30
        score[row] = (row.zoneID == here and 0 or 1000) + (zone and zone.parentMapID == continent and 0 or 100) + gap
    end
    table.sort(rows, function(a, b)
        if score[a] ~= score[b] then return score[a] < score[b] end
        return at[a] < at[b]
    end)
    return rows
end

-- "Gathered in": zones with the most nodes of an ore or herb (D.Gathering), in OrderZones' order, with the
-- skill it needs
ns.RegisterLink({
    key = "gatheredIn",
    label = L["Gathered in"],
    title = L["%s is gathered in:"],
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    entries = function(entry)
        local list = {}
        local gathering = entry.itemID and D.Gathering(entry.itemID)
        if not gathering or not (gathering.kind == "mine" or gathering.kind == "herb") then return list end
        local skill = (gathering.kind == "mine" and L["Mining %d"] or L["Herbalism %d"]):format(gathering.skill or 1)
        for _, zoneID in ipairs(gathering.zones or {}) do
            local row = ZoneRow(zoneID, skill)
            if row then list[#list + 1] = row end
        end
        return OrderZones(list)
    end,
})

-- "Zones": where an NPC stands, the zone you met it in first, the 1.12 data's after it
ns.RegisterLink({
    key = "npcZones",
    label = L["Zones"],
    title = L["%s is in:"],
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    entries = function(entry)
        local list = {}
        if not entry.npcID then return list end
        local met = D.MetZone(entry.npcID)
        for _, zoneID in ipairs(D.NPCZones(entry)) do
            -- "unchecked" is not shown on the row; the zone's tooltip says it
            local row = ZoneRow(zoneID, zoneID == met and L["met here"] or "")
            if row then
                row.lines = { zoneID == met and { L["You met it here."], "sub", true }
                    or { L["From the 1.12 data, not seen in WoW Forever yet."] .. " " .. D.UNCHECKED, "sub", true } }
                list[#list + 1] = row
            end
        end
        return list
    end,
})

-- "Teaches" of a recipe item: the recipe it teaches (straight to it)
ns.RegisterLink({
    key = "teaches",
    label = L["Teaches"],
    title = L["%s teaches:"],
    icon = "Interface\\Icons\\INV_Scroll_03",
    direct = true,
    entries = function(entry)
        local list = {}
        local recipe = entry.itemID and D.RecipeOfItem(entry.itemID)
        if recipe then list[1] = LinkedEntry(recipe, "") end
        return list
    end,
})

-- "Teaches" of a trainer: what it teaches you, learnable now first, then by the level or skill it needs
-- (your class's spells, or trainer recipes of your professions; not what you know)
ns.RegisterLink({
    key = "trainerTeaches",
    label = L["Teaches"],
    title = L["%s teaches:"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    entries = function(entry)
        local list, now = {}, {}
        local teaches = entry.npcID and D.npcTrainers and D.npcTrainers[entry.npcID]
        if not teaches then return list end
        local found = {}
        for i, e in ipairs(ns.TrainerTeaches(teaches) or {}) do found[i] = e end -- (the list is shared; sorted here)
        for _, e in ipairs(found) do now[e] = D.LearnableNow(e) end
        table.sort(found, function(a, b)
            if now[a] ~= now[b] then return now[a] end
            local na, nb = ns.LearnNeeds(a), ns.LearnNeeds(b)
            if na ~= nb then return na < nb end
            return a.key < b.key
        end)
        for _, e in ipairs(found) do list[#list + 1] = LinkedEntry(e, "") end
        return list
    end,
})

-- "Ranks": the ranks of a spell, lowest first (only a spell with more than one)
ns.RegisterLink({
    key = "ranks",
    label = L["Ranks"],
    title = L["Ranks of %s:"],
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    entries = function(entry)
        local list = {}
        if not (entry.spellID and entry.domain == "spells") then return list end
        local ranks = {}
        for _, spell in ipairs(D.Entries("spells")) do
            if spell.name == entry.name then ranks[#ranks + 1] = spell end
        end
        if #ranks < 2 then return list end
        table.sort(ranks, function(a, b) return (a.trainLevel or 0) < (b.trainLevel or 0) end)
        for _, spell in ipairs(ranks) do
            list[#list + 1] = LinkedEntry(spell, spell.rankNumber and L["Rank %d"]:format(spell.rankNumber) or "")
        end
        return list
    end,
})

-- "Before": the quests a quest needs done first (the 1.12 data, unchecked)
ns.RegisterLink({
    key = "questBefore",
    label = L["Before"],
    title = L["Before %s:"],
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    entries = function(entry)
        local list = {}
        local before = entry.questID and D.QuestPrevious(entry.questID)
        if not before then return list end
        local function Add(questID, info)
            local row = LinkedEntry(D.EntryByID("q:" .. questID), info)
            if row then list[#list + 1] = row end
        end
        -- all 1.12 data: shown under a heading (as the NPC links), not per row
        for _, id in ipairs(before.anyOf) do Add(id, #before.anyOf > 1 and L["one of them"] or "") end
        for _, id in ipairs(before.allOf) do Add(id, "") end
        if #list > 0 then table.insert(list, 1, { header = true, name = L["Unchecked (1.12 data)"], key = "" }) end
        return list
    end,
})

-- "Loot": what a dungeon's bosses drop, upgrades for you first, then the better quality, then A-Z; the
-- boss and its chance below on the right
ns.RegisterLink({
    key = "dungeonLoot",
    label = L["Loot"],
    title = L["Loot of %s:"],
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    entries = function(entry)
        local list, seen, upgrade, quality = {}, {}, {}, {}
        if not entry.mapID then return list end
        for _, boss in ipairs(D.DungeonBosses(entry)) do
            for id, chance in (boss[2] and D.DropsOf(boss[2]) or ""):gmatch("(%d+):(%d+)") do
                local itemID = tonumber(id)
                if not seen[itemID] then
                    seen[itemID] = true
                    local chanceText = tonumber(chance) > 0 and (chance .. " %") or L["< 1 %"]
                    local row = LinkedItem(itemID, boss[1] .. ", " .. chanceText)
                    upgrade[row] = ns.rec.Upgrade(itemID) ~= nil
                    quality[row] = C_Item.GetItemQualityByID(itemID) or 0
                    list[#list + 1] = row
                end
            end
        end
        table.sort(list, function(a, b)
            if upgrade[a] ~= upgrade[b] then return upgrade[a] end
            if quality[a] ~= quality[b] then return quality[a] > quality[b] end
            return a.name < b.name
        end)
        return list
    end,
})

-- "Quests" of a dungeon: those you can take first, then by level
ns.RegisterLink({
    key = "dungeonQuests",
    label = L["Quests"],
    title = L["Quests of %s:"],
    icon = "Interface\\GossipFrame\\AvailableQuestIcon",
    entries = function(entry)
        local list, quests, open = {}, {}, {}
        if not entry.mapID then return list end
        for _, quest in ipairs(D.Entries("quests")) do
            if quest.dungeon == entry.mapID then
                quests[#quests + 1] = quest
                open[quest] = D.QuestForYou(quest) and not C_QuestLog.IsQuestFlaggedCompleted(quest.questID)
            end
        end
        table.sort(quests, function(a, b)
            if open[a] ~= open[b] then return open[a] end
            if a.level ~= b.level then return a.level < b.level end
            return a.key < b.key
        end)
        for _, quest in ipairs(quests) do list[#list + 1] = LinkedEntry(quest, "") end
        return list
    end,
})
