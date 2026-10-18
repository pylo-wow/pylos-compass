local ns = select(2, ...).search
if ns.off then return end
local D = ns.data
local L = ns.L

-- Quest links (Data: the client's quest cache, and who gives and takes a quest as learned in play):
--   a quest   its objectives (NPCs to defeat or talk to, items to collect), rewards, giver, taker, next one
--   an item   the quests that need it, reward it or that it begins
--   an NPC    the quests that need it, and that it gives or takes
-- Linked entries come from the categories' indexes: one switched off or not built shows nothing.

local QUEST_ICON = 134327 -- INV_Misc_Note_01
local LinkedItem, LinkedNPC = ns.LinkedItem, ns.LinkedNPC -- (Links\Common.lua)

-- a quest in a link's list: its entry stands behind it, info on the right
local function LinkedQuest(questID, info)
    local target = ns.index.EntryByID("q:" .. questID)
    if not target then return nil end
    -- lines are resolved lazily (ns.LINKED_ROW, Links\Common.lua)
    return setmetatable({ name = target.name, icon = target.icon, iconAtlas = target.iconAtlas, category = info,
        target = target }, ns.LINKED_ROW)
end

local function Add(list, item)
    if item then list[#list + 1] = item end
end

ns.RegisterLink({
    key = "questObjectives",
    label = L["Objectives"],
    title = L["%s asks for:"],
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    entries = function(entry)
        local list = {}
        if not entry.questID then return list end
        for _, o in ipairs(entry.objectives) do
            local kind, id, count = o[1], o[2], o[3]
            if kind == "n" then Add(list, LinkedNPC(id, L["defeat %d"]:format(count)))
            elseif kind == "t" then Add(list, LinkedNPC(id, L["talk to"]))
            elseif kind == "i" then Add(list, LinkedItem(id, L["collect %d"]:format(count))) end
        end
        return list
    end,
})

ns.RegisterLink({
    key = "questRewards",
    label = L["Rewards"],
    title = L["%s rewards:"],
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    entries = function(entry)
        local list = {}
        if not entry.questID then return list end
        for _, r in ipairs(entry.rewards) do Add(list, LinkedItem(r[1], r[2] > 1 and ("×" .. r[2]) or "")) end
        for _, r in ipairs(entry.choices) do Add(list, LinkedItem(r[1], L["to choose"])) end
        if entry.providedItem then Add(list, LinkedItem(entry.providedItem, L["given when taken"])) end
        return list
    end,
})

-- who gives it (an NPC or the item that begins it) and who takes it back:
-- straight to its detail view (direct)
ns.RegisterLink({
    key = "questGiver",
    label = L["Given by"],
    title = L["%s is given by:"],
    icon = "Interface\\GossipFrame\\AvailableQuestIcon",
    direct = true,
    entries = function(entry)
        local list = {}
        if not entry.questID then return list end
        local kind, id = D.QuestGiver(entry.questID)
        if kind == "npc" then Add(list, LinkedNPC(id, ""))
        elseif kind == "item" then Add(list, LinkedItem(id, L["begins it"])) end
        return list
    end,
})
ns.RegisterLink({
    key = "questTaker",
    label = L["Turned in at"],
    title = L["%s is turned in at:"],
    icon = "Interface\\GossipFrame\\ActiveQuestIcon",
    direct = true,
    entries = function(entry)
        local list = {}
        if not entry.questID then return list end
        local kind, id = D.QuestTaker(entry.questID)
        if kind == "npc" then Add(list, LinkedNPC(id, "")) end
        return list
    end,
})
ns.RegisterLink({
    key = "questNext",
    label = L["Next quest"],
    title = L["After %s:"],
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    direct = true,
    entries = function(entry)
        local list = {}
        if entry.questID and entry.nextQuest then Add(list, LinkedQuest(entry.nextQuest, "")) end
        return list
    end,
})

-- an item's quests: needed for, reward of, begins (each quest once)
ns.RegisterLink({
    key = "itemQuests",
    label = L["Quests"],
    title = L["Quests with %s:"],
    icon = QUEST_ICON,
    entries = function(entry)
        local list, seen = {}, {}
        local itemID = entry.itemID
        if not itemID or entry.questID then return list end
        local function Each(quests, info)
            for _, questID in ipairs(quests) do
                if not seen[questID] then
                    seen[questID] = true
                    Add(list, LinkedQuest(questID, info))
                end
            end
        end
        Each(D.QuestsStartedByItem(itemID), L["begins it"])
        Each(D.QuestsNeedingItem(itemID), L["needs it"])
        Each(D.QuestsRewardingItem(itemID), L["rewards it"])
        return list
    end,
})

-- an NPC's quests: given, taken back (learned), needing it (to defeat, to talk to)
ns.RegisterLink({
    key = "npcQuests",
    label = L["Quests"],
    title = L["Quests with %s:"],
    icon = QUEST_ICON,
    entries = function(entry)
        local list, seen = {}, {}
        local npcID = entry.npcID
        if not npcID or entry.questID then return list end
        local function Each(quests, info)
            for _, questID in ipairs(quests) do
                if not seen[questID] then
                    seen[questID] = true
                    Add(list, LinkedQuest(questID, info))
                end
            end
        end
        local given, taken = D.QuestsOfNPC(npcID)
        Each(given, L["gives it"])
        Each(taken, L["takes it"])
        Each(D.QuestsNeedingNPC(npcID), L["needs it"])
        return list
    end,
})
