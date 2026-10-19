local _, D = ...
local ns = D.engine
local L = ns.L

-- Quest need: what an open objective of your quest log asks for.
--   items  an item to collect ("Linen Cloth: 3/10")
--   npcs   one to defeat ("Kobold Vermin slain: 3/10"), or one that drops an item to collect (Data\NPCLinks.lua)
-- Objective texts are read with the client's own formats (QUEST_ITEMS_NEEDED, QUEST_MONSTERS_KILLED; they differ by
-- language: "%2$d/%3$d %1$s slain"), the name compared with the entries' names. The row shows the quest symbol, its
-- tooltip the quest.

local QUEST_ICON = 132049 -- Interface\GossipFrame\AvailableQuestIcon

-- the client's formats as patterns that catch the name ("%1$s") only
local ITEM_PATTERN = ns.FormatPattern(QUEST_ITEMS_NEEDED, false, true)
local MONSTER_PATTERN = ns.FormatPattern(QUEST_MONSTERS_KILLED, false, true)

local items, monsters, drops = {}, {}, {} -- name key -> quest; name key -> quest; item ID -> quest
local progress = {} -- name key -> "3/10", of the objectives above
local npcsNeeded = {} -- NPC ID -> true: to defeat, or it drops a quest item (worked out with the log)
local questOfTitle = {} -- quest title -> quest ID, of your log
local open = {} -- quest ID -> list of { kind, text }: its open objectives
local itemOfKey = {} -- name key -> item ID, of the items to collect
local dirty = true -- read again (also while the items or NPCs are not built yet)
local readAt -- the state "quests" it was read at

local EachQuest = D.EachLoggedQuest

-- a quest's open objectives: list of { kind, text }, or nil while the game
-- has not loaded them yet (a text starting with a space, or none)
local function Objectives(questID, index)
    local list = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives and questID > 0 then
        local objectives = C_QuestLog.GetQuestObjectives(questID)
        if not objectives then return nil end
        for _, objective in ipairs(objectives) do
            local text = objective.text
            if not text or text == "" or text:sub(1, 1) == " " then return nil end
            if not objective.finished then list[#list + 1] = { objective.type, text } end
        end
        return list
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for objective = 1, GetNumQuestLeaderBoards(index) do
            local text, kind, finished = GetQuestLogLeaderBoard(objective, index)
            if not text or text:sub(1, 1) == " " then return nil end
            if not finished then list[#list + 1] = { kind, text } end
        end
    end
    return list
end

-- per quest the last objectives read completely: a quest whose data is not loaded yet (after a loading screen) keeps
-- them instead of losing its needs for a moment
local lastGood = {} -- quest ID -> list of { kind, text }

-- what the passes below were made for: the names needed with their quests (as one text), the builds of the two lists
-- read (states "data:items", "data:npcs"), the NPCs' learned drops (state "drops"; "npcs" would redo the pass over all
-- drop lists with every NPC met)
local madeFor, madeItems, madeNPCs, madeDrops
local function Signature()
    local parts = {}
    for key, title in pairs(items) do parts[#parts + 1] = "i" .. key .. "\1" .. title end
    for key, title in pairs(monsters) do parts[#parts + 1] = "m" .. key .. "\1" .. title end
    table.sort(parts)
    return table.concat(parts, "\2")
end

-- the entries of a list sorted by key (Data's domains) whose key is
-- key, in their order: for _, entry in EachNamed(list, key)
local function Named(state, i)
    i = i + 1
    local entry = state[1][i]
    if entry and entry.key == state[2] then return i, entry end
    return nil
end
local function EachNamed(list, key)
    local low, high = 1, #list + 1 -- the first entry with a key not below key
    while low < high do
        local middle = math.floor((low + high) / 2)
        if list[middle].key < key then low = middle + 1 else high = middle end
    end
    return Named, { list, key }, low - 1
end

local function Read()
    dirty = false
    wipe(items)
    wipe(monsters)
    wipe(progress)
    wipe(questOfTitle)
    wipe(open)
    local inLog = {}
    EachQuest(function(questID, title, index)
        inLog[questID] = true
        questOfTitle[title] = questID
        if C_QuestLog and C_QuestLog.IsComplete and questID > 0 and C_QuestLog.IsComplete(questID) then return end
        local list = Objectives(questID, index)
        if list then lastGood[questID] = list else list = lastGood[questID] or {} end
        open[questID] = list
        for _, objective in ipairs(list) do
            local kind, text = objective[1], objective[2]
            if kind == "item" and ITEM_PATTERN then
                local name = text:match(ITEM_PATTERN)
                if name then
                    items[D.SearchKey(name)] = title
                    progress[D.SearchKey(name)] = text:match("%d+/%d+")
                end
            elseif kind == "monster" and MONSTER_PATTERN then
                local name = text:match(MONSTER_PATTERN)
                if name then
                    monsters[D.SearchKey(name)] = title
                    progress[D.SearchKey(name)] = text:match("%d+/%d+")
                end
            end
        end
    end)
    for questID in pairs(lastGood) do
        if not inLog[questID] then lastGood[questID] = nil end
    end
    -- built later (the first look after login): looked at again then
    if not (D.Built("items") and D.Built("npcs")) then dirty = true end
    -- the passes below only when what is needed changed: the log changes with every kill and loot (QUEST_LOG_UPDATE), the
    -- names seldom (two passes over 19,000 items and 13,000 NPCs took 8 ms of the first window)
    local signature = Signature()
    local itemsBuilt, npcsBuilt, learned = D.State("data:items"), D.State("data:npcs"), D.State("drops")
    if signature == madeFor and itemsBuilt == madeItems and npcsBuilt == madeNPCs and learned == madeDrops
            and not dirty then
        return
    end
    madeFor, madeItems, madeNPCs, madeDrops = signature, itemsBuilt, npcsBuilt, learned
    wipe(drops)
    wipe(itemOfKey)
    -- the items' IDs, for the NPCs that drop them (looked up by name in the sorted list, not a pass over 19,000 items)
    for key, quest in pairs(items) do
        for _, entry in EachNamed(D.Entries("items"), key) do
            drops[entry.itemID], itemOfKey[key] = quest, entry.itemID
        end
    end
    -- the NPCs needed: the ones to defeat (by name, as the items) and the droppers of the items (their lists); asking
    -- every NPC each time made the search's NPC tab lag
    wipe(npcsNeeded)
    for key in pairs(monsters) do
        for _, entry in EachNamed(D.Entries("npcs"), key) do npcsNeeded[entry.npcID] = true end
    end
    -- from the NPCs' drop lists, not an item's list of droppers (it keeps only the best ones: Hogger was not among Linen
    -- Cloth's); raw table: a pass over all NPCs, no accessor for that
    if next(drops) then
        for npcID, list in pairs(D.npcDrops or {}) do
            for item in list:gmatch("(%d+):") do
                if drops[tonumber(item)] then
                    npcsNeeded[npcID] = true
                    break
                end
            end
        end
    end
end
local function Fresh()
    local quests = D.State("quests")
    if dirty or readAt ~= quests then
        readAt = quests
        Read()
    end
end

local function Drops(npcID)
    if not next(drops) then return nil end
    for item in (D.DropsOf(npcID) or ""):gmatch("(%d+):") do
        local itemID = tonumber(item)
        if drops[itemID] then return itemID, drops[itemID] end
    end
    return nil
end

-- the quest of your log an entry is needed for: quest ID (nil if the log names none), title; nil if none (the
-- suggestions window's menu opens it in the quest log)
function ns.QuestNeedOf(entry)
    Fresh()
    local title
    if entry.domain == "items" then
        title = items[entry.key]
    elseif entry.domain == "npcs" then
        title = monsters[entry.key]
        if not title then title = select(2, Drops(entry.npcID)) end
    end
    if not title then return nil end
    return questOfTitle[title], title
end

-- what is still to do for a quest of your log: list of { text, from } - the objective as the game words it ("A Simple
-- Compass: 0/1"), and for an item the nearest NPC known to drop it ("Kobold Miner, 120 yards"; nil if none is known).
-- Empty for a quest done or not in your log.
function ns.QuestNeeds(questID)
    Fresh()
    local list = {}
    for _, objective in ipairs(open[questID] or {}) do
        local kind, text = objective[1], objective[2]
        local from
        local name = kind == "item" and ITEM_PATTERN and text:match(ITEM_PATTERN)
        local item = name and itemOfKey[D.SearchKey(name)]
        if item then
            local _, words, npc = ns.reach.Nearest(D.DroppedBy(item))
            if npc then from = words and (npc.name .. ", " .. words) or npc.name end
        end
        list[#list + 1] = { text = text, from = from }
    end
    return list
end

local TESTS = {
    items = function(entry) return items[entry.key] ~= nil end,
    npcs = function(entry) return npcsNeeded[entry.npcID] == true end,
}

ns.RegisterReason({
    key = "questNeed",
    -- weight 1.1: what your quests ask for is what you look up most
    stage = "know", weight = 1.1, label = "Quest need", learn = false, -- killing and looting leave no sure sign
    -- to know (where is it): the search's start page. Not "do": in the suggestions window an item or foe of a quest only
    -- repeated the quest's own row, which lists them (ns.QuestNeeds)
    kind = "know",
    sources = { "items", "npcs" },
    depends = { "quests", "npcs", "drops", "data" },
    prepare = function()
        Fresh()
    end,
    -- for knowing: the items to collect and the NPCs to defeat or that drop
    -- them (one pass over the NPCs, only with a quest that needs something)
    candidates = function(add)
        Fresh()
        for itemID in pairs(drops) do add(D.ItemByID(itemID)) end
        for npcID in pairs(npcsNeeded) do add(D.NPCByID(npcID)) end
    end,
    test = function(entry) return TESTS[entry.domain](entry) end,
    -- an item: the nearest NPC dropping it (quest areas lie around you: the
    -- zone's reach without one known); an NPC: its distance
    reach = function(entry)
        if entry.domain == "npcs" then return ns.reach.NPC(entry) end
        -- no words: which NPC to get it from is the tooltip's Where, one answer in one place
        local factor = ns.reach.Nearest(D.DroppedBy(entry.itemID))
        if not factor then return ns.reach.ZONE, nil end
        return factor, nil
    end,
    -- the row: "Quest 3/10" (the objective's count), its tooltip the quest
    note = function(entry)
        -- the count on the row only where it counts this entry: an NPC that drops the item gets none (its three droppers
        -- would all say "0/3")
        local tip, key, own = nil, nil, true
        if entry.domain == "items" then
            -- (or "?": the quest log read anew since the strongest were kept)
            tip, key = L["For a quest: %s"]:format(items[entry.key] or "?"), entry.key
        elseif monsters[entry.key] then
            tip, key = L["For a quest: to defeat for %s"]:format(monsters[entry.key]), entry.key
        else
            local itemID, dropQuest = Drops(entry.npcID)
            local item = itemID and D.ItemByID(itemID)
            tip = L["For a quest: drops %s for %s"]:format(item and item.name or "?", dropQuest or "?")
            key, own = item and item.key, false
        end
        local count = key and progress[key]
        if count then tip = tip .. " (" .. count .. ")" end
        return { icon = QUEST_ICON, tip = tip, text = count and own and L["Quest %s"]:format(count) or L["For a quest"] }
    end,
})
