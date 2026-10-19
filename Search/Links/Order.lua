local ns = select(2, ...).search
local D = ns.data

-- Which links come first for which kind of entry. The detail view previews the first ones that have rows
-- (UI\Detail.lua), the menu lists them in this order; links not named here follow in registration order.

local ROLE = D.NPC_ROLE
local ORDERS = {
    gathered   = { "gatheredIn", "usedFor", "soldBy", "itemQuests" },
    material   = { "droppedBy", "usedFor", "soldBy", "itemQuests" },
    gear       = { "droppedBy", "soldBy", "itemQuests", "recipe" },
    consumable = { "soldBy", "recipe", "droppedBy", "itemQuests" },
    recipeItem = { "teaches", "soldBy", "droppedBy" },
    questItem  = { "itemQuests", "droppedBy" },
    item       = { "droppedBy", "soldBy", "recipe", "usedFor", "itemQuests" },
    vendor     = { "sells", "npcQuests", "npcZones" },
    trainer    = { "trainerTeaches", "npcQuests", "npcZones" },
    questGiver = { "npcQuests", "npcZones" },
    foe        = { "drops", "npcQuests", "npcZones" },
    npc        = { "npcQuests", "npcZones" },
    spell      = { "taughtBy", "ranks" },
    recipe     = { "madeFrom", "creates", "taughtBy", "recipeItem" },
    quest      = { "questObjectives", "questRewards", "questGiver", "questTaker", "questBefore", "questNext" },
    dungeon    = { "bosses", "dungeonLoot", "dungeonQuests" },
}

-- the kind of an entry, as the orders above name them
local function Kind(entry)
    if entry.itemID then
        local gathering = D.Gathering(entry.itemID)
        if gathering and (gathering.kind == "mine" or gathering.kind == "herb") then return "gathered" end
        if gathering then return "material" end -- skinned or dropped
        local class = entry.itemClass
        if class == 2 or class == 4 then return "gear" end
        if class == 9 then return "recipeItem" end
        if class == 12 then return "questItem" end
        if class == 0 then return "consumable" end
        return "item"
    end
    if entry.npcID then
        if D.npcTrainers and D.npcTrainers[entry.npcID] then return "trainer" end
        if D.NPCHasRole(entry, ROLE.VENDOR) then return "vendor" end
        if D.NPCHasRole(entry, ROLE.QUEST_GIVER) then return "questGiver" end
        if entry.reaction == 1 or entry.reaction == 2 then return "foe" end
        return "npc"
    end
    if entry.questID then return "quest" end
    if entry.mapID then return "dungeon" end
    if entry.domain == "professions" then return "recipe" end
    if entry.domain == "spells" then return "spell" end
    return nil
end

-- link key -> its place for this entry (lower first; not named: after all)
local rank = {}
function ns.LinkRank(entry)
    wipe(rank)
    for i, key in ipairs(ORDERS[Kind(entry)] or {}) do rank[key] = i end
    return rank
end
