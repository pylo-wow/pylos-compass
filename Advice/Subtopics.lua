local ns = select(2, ...).advice
if ns.off then return end
local D = ns.data
local L = ns.L

-- Subtopics of the window's tabs (side tabs, W.SideTabs): what a topic's list splits into.
-- Gear: Weapons (incl. shields/off-hands), Armor, Jewelry (neck, rings, trinkets, cloak). Professions: one per own profession.
-- Supplies: Food & drink, Ammo & reagents, Services (NPCs), Other. Dungeons: Dungeons, Raids. Class/Quests/Zones: none.
-- ns.Subtopics(topic, list) -> { { key, name, icon, test(entry) }, ... } for the subtopics that have something in the list.

local SLOTS = { INVTYPE_SHIELD = "weapons", INVTYPE_HOLDABLE = "weapons", INVTYPE_RELIC = "weapons",
    INVTYPE_NECK = "jewelry", INVTYPE_FINGER = "jewelry", INVTYPE_TRINKET = "jewelry", INVTYPE_CLOAK = "jewelry" }
local function GearKind(entry)
    if entry.itemClass == 2 then return "weapons" end
    if entry.itemClass ~= 4 then return nil end
    return SLOTS[entry.equipLoc] or "armor"
end

-- an NPC is a service; items by class
local function SupplyKind(entry)
    if entry.npcID then return "services" end
    if D.IsFood(entry) then return "food" end
    if entry.itemClass == 5 or entry.itemClass == 6 or entry.itemClass == 11 then return "ammo" end
    return "other"
end

local function Is(kindOf, kind) return function(entry) return kindOf(entry) == kind end end

local FIXED = {
    gear = {
        { key = "weapons", name = L["Weapons"], icon = 135274, test = Is(GearKind, "weapons") },  -- INV_Sword_04
        { key = "armor", name = L["Armor"], icon = 132736, test = Is(GearKind, "armor") },        -- INV_Chest_Plate01
        { key = "jewelry", name = L["Jewelry"], icon = 133345, test = Is(GearKind, "jewelry") },  -- INV_Jewelry_Ring_03
    },
    supplies = {
        { key = "food", name = L["Food & drink"], icon = 133947, test = Is(SupplyKind, "food") },        -- INV_Misc_Food_05
        { key = "ammo", name = L["Ammo & reagents"], icon = 132382, test = Is(SupplyKind, "ammo") },     -- INV_Ammo_Arrow_02
        { key = "services", name = L["Services"], icon = 133057, test = Is(SupplyKind, "services") },   -- INV_Hammer_20
        { key = "other", name = L["Other"], icon = 134400, test = Is(SupplyKind, "other") },             -- INV_Misc_QuestionMark
    },
    dungeons = {
        { key = "dungeon", name = L["Dungeons"], icon = 136334, test = function(e) return e.kind == 1 end }, -- LFGIcon-Dungeon
        { key = "raid", name = L["Raids"], icon = 136351, test = function(e) return e.kind == 2 end },      -- LFGIcon-Raid
    },
}

-- professions an entry is about: its skill line, a trainer's, those of recipes a vendor sells (skill line -> true)
local function Professions(entry)
    local lines = {}
    if entry.skillLine then lines[entry.skillLine] = true end
    local teaches = entry.npcID and D.npcTrainers and D.npcTrainers[entry.npcID]
    if teaches and teaches >= 100 then lines[teaches] = true end
    if entry.npcID then
        for item in (D.Sells(entry.npcID) or ""):gmatch("%d+") do
            local recipe = D.RecipeOfItem(tonumber(item))
            if recipe and recipe.skillLine then lines[recipe.skillLine] = true end
        end
    end
    return lines
end

local professionSubs = {} -- skill line -> subtopic (cached)
local function ProfessionSub(line)
    local sub = professionSubs[line]
    if not sub then
        sub = { key = "profession:" .. line, name = D.professionNames[line] or tostring(line),
            icon = D.professionIcons[line] or 134400,
            test = function(entry) return Professions(entry)[line] == true end }
        professionSubs[line] = sub
    end
    return sub
end

function ns.Subtopics(topic, list)
    local found = {}
    if topic == "professions" then
        local seen, yours = {}, D.ProfessionRanks()
        for _, item in ipairs(list) do
            for line in pairs(Professions(item.entry)) do
                if yours[line] then seen[line] = true end
            end
        end
        for line in pairs(seen) do found[#found + 1] = ProfessionSub(line) end
        table.sort(found, function(a, b) return a.name < b.name end)
        return found
    end
    for _, sub in ipairs(FIXED[topic] or {}) do
        for _, item in ipairs(list) do
            if sub.test(item.entry) then
                found[#found + 1] = sub
                break
            end
        end
    end
    return found
end
