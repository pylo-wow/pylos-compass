local _, D = ...
local ns = D.engine
local L = ns.L

-- Quest log: each quest of your log is itself a suggestion (a quest to turn in has no item or foe to suggest). What it
-- is worth (D.QuestOf, the client's quest cache):
--   experience  its XP as a share of your level: XP_PER_LEVEL a whole level
--   reward      the best upgrade for you among its rewards and choices: REWARD of its strength as an upgrade
--               (ns.UpgradeOf: class and armour checked, strength flattening); half, as the quest brings more than the item
--   chain       the quests it opens (D.QuestOf.nextQuest; the cache gives the next one, not what comes before): CHAIN
--               for each one not above your level + 3, up to CHAIN_MAX
--   turn in     done, only the way back left: x READY
-- All of it counts at most MOST (Reasons.lua: twice a plain quest).
-- Its reach: how far where it is to be done (or turned in) is, and what is left of it to do (QUEST_MINUTES for all of
-- it: 9/10 comes before 0/10).

-- BASE: a quest of your log is progress in itself, at least as much as a clear upgrade
local BASE, XP_PER_LEVEL, REWARD = 1, 2, 0.5
local CHAIN, CHAIN_MAX, CHAIN_ABOVE = 0.15, 5, 3
local READY = 1.3

local inLog = {} -- quest ID -> true; per search
local ready = {} -- quest ID -> true: complete

-- the quests it opens one after another, not too high for you
local function Chain(quest)
    local count, level = 0, UnitLevel("player")
    local next = quest.nextQuest
    while next and count < CHAIN_MAX do
        local q = D.QuestOf(next)
        if not q or q.level > level + CHAIN_ABOVE then break end
        count = count + 1
        next = q.nextQuest
    end
    return count
end

-- the best of its rewards as an upgrade for you: its strength (0: none),
-- the comparison, the item
local function Reward(quest)
    local best, compared, item = 0, nil, nil
    for _, list in ipairs({ quest.rewards, quest.choices }) do
        for _, reward in ipairs(list) do
            local r = ns.UpgradeOf(reward[1])
            local strength = r and ns.UpgradeStrength(r) or 0
            if strength > best then best, compared, item = strength, r, reward[1] end
        end
    end
    return best, compared, item
end

-- what the game gives of a quest's XP 6, 7, 8, 9 levels above it, 10 % from 10 on (vmangos Quest::XPValue; the data's xp is in full)
local LESS = { 0.8, 0.6, 0.4, 0.2 }
local LEAST = 0.1

-- the XP as a share of your level (0 at the highest level)
local function Experience(quest)
    local need = UnitXPMax("player")
    if not need or need <= 0 or (quest.xp or 0) <= 0 then return 0 end
    local above = (quest.level or 0) > 0 and UnitLevel("player") - quest.level - 5 or 0
    return quest.xp * (above <= 0 and 1 or LESS[above] or LEAST) / need
end

-- How much of a quest of your log is still to do: 0 (done) to 1 (nothing done), from its objectives' counts
-- (QuestObjectiveInfo numFulfilled, numRequired); nil while the game has not told (Reach.lua asks it too)
function ns.QuestRest(questID)
    if questID <= 0 or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    if C_QuestLog.IsComplete(questID) then return 0 end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives or #objectives == 0 then return nil end
    local left = 0
    for _, objective in ipairs(objectives) do
        local need = objective.numRequired or 0
        if not objective.finished then
            left = left + (need > 0 and 1 - math.min(objective.numFulfilled or 0, need) / need or 1)
        end
    end
    return left / #objectives
end

ns.RegisterReason({
    key = "questLog",
    -- weight 1.1: the progress you took on yourself, a little above an upgrade or a trainer of the same size
    stage = "progress", weight = 1.1, label = "Quest log",
    sources = { "quests" },
    depends = { "quests", "level", "gear", "talents", "spells", "rec:weights", "data" },
    topic = "quests",
    prepare = function()
        wipe(inLog)
        wipe(ready)
        D.EachLoggedQuest(function(questID)
            inLog[questID] = true
            if questID > 0 and C_QuestLog.IsComplete(questID) then ready[questID] = true end
        end)
    end,
    test = function(entry)
        if not inLog[entry.questID] then return nil end
        local quest = D.QuestOf(entry.questID)
        if not quest then return BASE end
        local reward = Reward(quest)
        local strength = BASE + XP_PER_LEVEL * Experience(quest) + REWARD * reward + CHAIN * Chain(quest)
        if ready[entry.questID] then strength = strength * READY end
        return strength
    end,
    -- how far: done, the NPC who takes it (learned) or where the map marks it; else where the map marks what is left to
    -- do; a quest to turn in right next to you comes first; without a mark: its zone, or a journey
    reach = function(entry)
        local questID = entry.questID
        local reach = ns.reach
        if ready[questID] then
            local kind, npcID = D.QuestTaker(questID)
            local npc = kind == "npc" and D.NPCByID(npcID)
            if npc and D.NPCDistance(npc) then return reach.NPC(npc) end
        end
        -- the doing left (half a quest when the game has not told yet)
        local doing = ready[questID] and 0 or reach.QUEST_MINUTES * (ns.QuestRest(questID) or 0.5)
        -- where the map marks it, by the route planner (as every place)
        local marked = D.QuestPlace(questID)
        if marked and D.TravelMinutes(marked) ~= nil then return reach.Place(marked, doing) end
        local quest = D.QuestOf(questID)
        if quest and quest.zone and quest.zone == D.PlayerZone() then
            return reach.Minutes(reach.ZONE_MINUTES + doing), L["in this zone"]
        end
        -- elsewhere: the way to its zone
        if quest and quest.zone and quest.zone > 0 then return reach.Place(D.ZonePlace(quest.zone), doing) end
        return reach.Minutes(reach.UNKNOWN_MINUTES + doing), nil
    end,
    note = function(entry)
        if ready[entry.questID] then return L["Ready to turn in"] end
        local quest = D.QuestOf(entry.questID)
        local chain = quest and Chain(quest) or 0
        if chain > 0 then return L["Opens %d more"]:format(chain) end
        return nil
    end,
    why = function(entry)
        local quest = D.QuestOf(entry.questID)
        if not quest then return L["In your quest log"] end
        local parts = {}
        local xp = Experience(quest)
        if xp > 0 then parts[#parts + 1] = L["%d %% of a level"]:format(xp * 100 + 0.5) end
        local _, r, item = Reward(quest)
        if r then
            parts[#parts + 1] = L["%s makes you %.1f %% stronger"]:format(D.NameEN("item", item) or "?", r.share)
        end
        local chain = Chain(quest)
        if chain > 0 then parts[#parts + 1] = L["opens %d more quests"]:format(chain) end
        if ready[entry.questID] then table.insert(parts, 1, L["ready to turn in"]) end
        return #parts > 0 and table.concat(parts, ", ") or L["In your quest log"]
    end,
})
