local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- NPCs: every NPC of the server, with the title on the right ("Blacksmithing Trainer"), or the creature
-- type where there is none. Entries and facts come from Data (World\NPCs.lua). Opened without
-- text: the NPCs of the zone you are in. No action.

-- creature type names, tooltip lines and level text: Data (World\Lines.lua), shared with Recommendations
local TYPES = D.NPC_TYPE_NAMES
local ZoneNames, LevelText = D.NPCZoneNames, D.NPCLevelText

-- Subcategories (tabs beside the list): vendors, class trainers and profession trainers (D.npcTrainers)
local function HasRole(bit)
    return function(entry) return D.NPCHasRole(entry, bit) end
end
local function Teaches(what)
    return function(entry)
        local teaches = D.npcTrainers and D.npcTrainers[entry.npcID]
        return teaches ~= nil and (teaches < 100) == what
    end
end
local TABS = {
    { "vendors", L["Vendors"], "INV_Misc_Coin_01", HasRole(D.NPC_ROLE.VENDOR) },
    { "classtrainers", L["Class trainers"], "INV_Misc_Book_09", Teaches(true) },
    { "professiontrainers", L["Profession trainers"], "Trade_BlackSmithing", Teaches(false) },
}
for _, tab in ipairs(TABS) do
    ns.RegisterFilter({
        key = "npcs:" .. tab[1], name = tab[2], icon = "Interface\\Icons\\" .. tab[3],
        subcategory = true, sources = { "npcs" }, test = tab[4], static = true,
    })
end

-- Line below the name: its title, else its type and, if attackable, its rank; then its first zone ("+2"
-- for more). Its level is the row's state.
local RANKS = { [1] = L["Elite"], [2] = L["Rare elite"], [3] = L["Boss"], [4] = L["Rare"] }
local function Describe(entry)
    local names = ZoneNames(entry)
    local zone = names[1] and (#names > 1 and ("%s +%d"):format(names[1], #names - 1) or names[1])
    if entry.title ~= "" then return { entry.title, zone } end
    local attackable = entry.reaction == 1 or entry.reaction == 2
    return { TYPES[entry.creatureType], attackable and RANKS[entry.npcRank] or nil, zone }
end

-- Row state (UI\List.lua): an NPC with a service (vendor, trainer, quest giver ...) stands at its spot:
-- how far it is. One you can attack spawns in many places (a single spot said "170 yd" for the mob you
-- target): its level in the colour of how hard it is for you. One present only during a world event not
-- running now: the event, grey (D.EventAway).
local function State(entry)
    local away = D.EventAway(entry)
    if away then return away, "done" end
    if entry.roles ~= 0 and entry.reaction ~= 1 then
        local yards = D.NPCDistance(entry)
        if not yards then return nil end
        return L["%d yd"]:format(math.floor(yards / 5 + 0.5) * 5), "plain"
    end
    if (entry.reaction == 1 or entry.reaction == 2) and entry.levelMax > 0 then
        return LevelText(entry), ns.ConColor(entry.levelMax)
    end
    return nil
end

-- Tooltip's For you (UI\Tooltip.lua): how far it is, its quests for you (to take, to turn in, ready),
-- what it can teach you now
local function ForYou(entry, add)
    local where = entry.roles ~= 0 and entry.reaction ~= 1 and D.NPCDistance(entry)
    if where then add(L["%d yd away"]:format(math.floor(where / 5 + 0.5) * 5), "plain") end
    local given, taken = D.QuestsOfNPC(entry.npcID, true)
    local toTake, toTurnIn, ready = 0, 0, 0
    for _, questID in ipairs(given or {}) do
        local quest = D.EntryByID("q:" .. questID)
        if quest and not C_QuestLog.IsOnQuest(questID) and not C_QuestLog.IsQuestFlaggedCompleted(questID)
                and D.QuestForYou(quest) then
            toTake = toTake + 1
        end
    end
    for _, questID in ipairs(taken or {}) do
        if C_QuestLog.IsOnQuest(questID) == true then
            if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then ready = ready + 1 else toTurnIn = toTurnIn + 1 end
        end
    end
    if ready > 0 then add(L["Quests ready to turn in here: %d"]:format(ready), "good") end
    if toTake > 0 then add(L["Quests for you: %d"]:format(toTake), "good") end
    if toTurnIn > 0 then add(L["Quests of your log turned in here: %d"]:format(toTurnIn), "active") end
    local teaches = D.npcTrainers and D.npcTrainers[entry.npcID]
    if not teaches then return end
    local count = 0
    if teaches < 100 then
        if teaches ~= select(3, UnitClass("player")) then return end
        for _, spell in ipairs(D.Entries("spells")) do
            if D.SpellLearnableNow(spell) then count = count + 1 end
        end
        if count > 0 then add(L["Can teach you %d spells now"]:format(count), "good") end
    elseif D.ProfessionRanks()[teaches] then
        for _, recipe in ipairs(D.Entries("professions")) do
            if recipe.skillLine == teaches and (recipe.recipeItem or 0) == 0 and D.RecipeLearnable(recipe) == "now" then
                count = count + 1
            end
        end
        if count > 0 then add(L["Can teach you %d recipes now"]:format(count), "good") end
    end
end

-- the zone you are in (a city district or cave resolves to its zone, see Data's You\Zone.lua); nil if the
-- client does not know
local function CurrentZone() return D.PlayerZone(true) end

local zoneNow
ns.RegisterFilter({
    key = "npcsZone", name = L["In your zone"], sources = { "npcs" },
    description = L["NPCs of the zone you are in."],
    words = "zone area here nearby",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    prepare = function() zoneNow = CurrentZone() end,
    test = function(entry) return zoneNow ~= nil and D.NPCInZone(entry, zoneNow) end,
})

ns.RegisterFilter({
    key = "npcsRare", name = L["Rare"], sources = { "npcs" },
    description = L["Rare NPCs and rare elites."],
    words = "rare silver elite",
    icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
    static = true, -- the NPC's own facts (Index.lua keeps what passes)
    test = function(entry) return entry.npcRank == 2 or entry.npcRank == 4 end,
})

-- mobs of your level: no role, up to three levels above you and five below (for farming)
local playerLevel = 1
ns.RegisterFilter({
    key = "npcsLevel", name = L["Your level"], sources = { "npcs" },
    description = L["Hostile NPCs from five levels below you to three above."],
    words = "level farm mobs enemies",
    icon = "Interface\\Icons\\Achievement_Level_10",
    prepare = function() playerLevel = UnitLevel("player") end,
    test = function(entry)
        local reaction = entry.reaction
        local hostile = reaction == 1 or (reaction == 0 and entry.roles == 0)
        return hostile and entry.levelMax > 0
            and entry.levelMin <= playerLevel + 3 and entry.levelMax >= playerLevel - 5
    end,
})

local ROLE = D.NPC_ROLE
ns.RegisterFilter({
    key = "npcsServices", name = L["Services"], sources = { "npcs" },
    description = L["Innkeepers, bankers, flight masters and auctioneers."],
    words = "services innkeeper inn bank banker flight master auction auctioneer",
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    static = true,
    test = function(entry)
        return D.NPCHasRole(entry, ROLE.FLIGHT_MASTER) or D.NPCHasRole(entry, ROLE.INNKEEPER)
            or D.NPCHasRole(entry, ROLE.BANKER) or D.NPCHasRole(entry, ROLE.AUCTIONEER)
    end,
})

ns.RegisterFilter({
    key = "npcsFriendly", name = L["Friendly"], sources = { "npcs" },
    description = L["NPCs friendly to you."],
    words = "friendly friend",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    static = true,
    test = function(entry) return entry.reaction == 3 end,
})
ns.RegisterFilter({
    key = "npcsHostile", name = L["Hostile"], sources = { "npcs" },
    description = L["NPCs that attack you."],
    words = "hostile enemy",
    icon = "Interface\\Icons\\Ability_Warrior_Challange",
    static = true,
    test = function(entry) return entry.reaction == 1 end,
})

-- the pool: rebuilt when Data rebuilt its NPCs or professions (a recipe learned), drops were learned, or
-- your professions changed (not on every skill point)
local recipeCache, recipeProfessions = D.Cache({ "data:npcs", "data:professions", "drops" }), nil
-- a recipe item whose recipe you could learn, now or later (D.RecipeLearnable decides)
local function UnknownRecipeItem(itemID, ranks)
    local recipe = D.RecipeOfItem(itemID)
    return recipe ~= nil and D.RecipeLearnable(recipe, ranks) ~= nil
end
ns.RegisterFilter({
    key = "npcsRecipes", name = L["Recipes for you"], sources = { "npcs" },
    description = L["NPCs that sell or drop recipes of your professions you do not know yet."],
    words = "recipe recipes pattern formula plans schematic",
    icon = "Interface\\Icons\\INV_Scroll_03",
    test = function() return true end, -- the pool says it all
    pool = function()
        local ranks = D.ProfessionRanks()
        local lines = {}
        for line in pairs(ranks) do lines[#lines + 1] = line end
        table.sort(lines)
        local professions = table.concat(lines, ",")
        local recipePool, renewed = recipeCache.Get()
        if not renewed and recipeProfessions == professions then return recipePool end
        wipe(recipePool)
        recipeProfessions = professions
        if not D.Built("npcs") then return recipePool end
        local seen = {}
        for _, map in ipairs({ D.npcSells or {}, D.npcDrops or {} }) do
            for npcID, items in pairs(map) do
                if not seen[npcID] then
                    for item in items:gmatch("(%d+)") do
                        if UnknownRecipeItem(tonumber(item), ranks) then
                            seen[npcID] = true
                            local entry = D.NPCByID(npcID)
                            if entry then recipePool[#recipePool + 1] = entry end
                            break
                        end
                    end
                end
            end
        end
        return recipePool
    end,
})

-- Opened without text, one list without headings: the NPCs you use (talked to, chosen; wherever they
-- are) and the NPCs of the zone you are in that do something for you (a role: vendor, trainer, flight
-- master, ...; not hostile), by what you would look up (your target first) and use, then the nearest;
-- the others only by typing. In a tab (vendors, class trainers, profession trainers) all of that kind
-- in the zone too, after them, A-Z.
local reasons = ns.rec
local useful, rest = {}, {}
local distances = {}
local function Nearer(a, b)
    local da, db = distances[a], distances[b]
    if da ~= db then
        if not da then return false end
        if not db then return true end
        return da < db
    end
    return nil
end
local LOOKUPS = 30
local NPCS = { npcs = true }
-- Not a pass over all NPCs (14,000: the tab lagged): the zone's NPCs (D.NPCsInZone, kept per zone), the
-- ones to look up (the reasons' own candidates) and the ones you used (the memories' lists).
local taken = {}
local function Browse(take)
    reasons.Prepare()
    local zone = CurrentZone()
    wipe(useful)
    wipe(rest)
    wipe(distances)
    wipe(taken)
    local function Useful(entry)
        if entry and not taken[entry] then
            taken[entry] = true
            useful[#useful + 1] = entry
            distances[entry] = D.NPCDistance(entry)
        end
    end
    for _, item in ipairs(reasons.Relevant(LOOKUPS, LOOKUPS, NPCS) or {}) do Useful(item.entry) end
    for _, id in ipairs(reasons.UsedIDs("n:")) do Useful(D.EntryByID(id)) end
    for _, id in ipairs(ns.memory.Recent()) do
        if id:sub(1, 2) == "n:" then Useful(D.EntryByID(id)) end
    end
    for _, entry in ipairs(zone and D.NPCsInZone(zone) or {}) do
        if entry.roles ~= 0 and entry.reaction ~= 1 then
            Useful(entry)
        elseif not taken[entry] then
            rest[#rest + 1] = entry
        end
    end
    for _, entry in ipairs(reasons.Sort(useful, Nearer)) do take(entry) end
    if ns.view.Subcategory() then
        table.sort(rest, function(a, b) return a.key < b.key end)
        for _, entry in ipairs(rest) do take(entry) end
    end
end

ns.RegisterSource({
    key = "npcs",
    domain = "npcs",
    name = L["NPCs"],
    hint = L["Search NPCs"],
    emptyHint = L["Nobody useful near you. Type a name."],
    icon = (function()
        -- a portrait of your own race (Achievement_Character_<race>_<sex>, the
        -- client has them for the ten classic races), else the group icon
        local _, race = UnitRace("player")
        local RACES = { Scourge = "Undead", NightElf = "Nightelf", BloodElf = "Bloodelf" }
        race = RACES[race] or race
        local known = { Human = 1, Dwarf = 1, Gnome = 1, Nightelf = 1, Orc = 1, Troll = 1, Tauren = 1, Undead = 1,
            Bloodelf = 1, Draenei = 1 }
        if not race or not known[race] then return "Interface\\Icons\\INV_Misc_GroupNeedMore" end
        return ("Interface\\Icons\\Achievement_Character_%s_%s"):format(race, UnitSex("player") == 3 and "Female" or "Male")
    end)(),
    browse = Browse,
    describe = Describe,
    state = State,
    forYou = ForYou,
})
