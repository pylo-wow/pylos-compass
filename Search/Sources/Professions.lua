local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Professions: the recipes of every profession, with the profession on the right. Learned ones show
-- (Ctrl+Enter casts them); the others are hidden: typing finds those of your professions (grayed, with the
-- skill they need), a filter like "Available" shows the ones you can learn now. Entries and recipe facts
-- come from the data layer (World\Professions.lua); here only how they are shown.

-- fields the rows and the action need (a learned recipe is cast)
D.AddField("professions", "type", function(entry) if not entry.hidden then return "spell" end end)
D.AddField("professions", "value", function(entry) if not entry.hidden then return entry.spellID end end)

-- skill line -> profession name, in the client's language; ns.professionNames is read by Links\Recipes.lua
-- (loaded after this file)
local SKILLS = {}
for skillLine, name in pairs(D.professionNames) do SKILLS[skillLine] = L[name] end
ns.professionNames = SKILLS
local SKILL_ICONS = D.professionIcons

local skillLines = {}
for skillLine in pairs(SKILLS) do skillLines[#skillLines + 1] = skillLine end
table.sort(skillLines, function(a, b) return SKILLS[a] < SKILLS[b] end)
-- Background of the game's recipe window per profession (atlas names from DB2 UiTextureAtlasMember);
-- First Aid has none: its card from the professions overview. { atlas, focus x, focus y, zoom }: the
-- motif's centre in the picture (cooking pot is right of the middle; the others are estimated).
local function Recipe(name, x) return { "professions-recipe-background-" .. name, x or 0.5, 0.6, 1.15 } end
local BACKGROUNDS = {
    [129] = { "profession-background-card-firstaid-c60", 0.5, 0.7, 1 }, [164] = Recipe("blacksmithing"),
    [165] = Recipe("leatherworking"), [171] = Recipe("alchemy"), [182] = Recipe("herbalism"),
    [185] = Recipe("cooking", 0.6), [186] = Recipe("mining"), [197] = Recipe("tailoring"),
    [202] = Recipe("engineering"), [333] = Recipe("enchanting"), [356] = Recipe("fishing"),
    [393] = Recipe("skinning"),
}
local subcategories = {}
for _, skillLine in ipairs(skillLines) do
    subcategories[skillLine] = ns.RegisterFilter({
        key = "profession" .. skillLine,
        name = SKILLS[skillLine],
        icon = SKILL_ICONS[skillLine],
        background = BACKGROUNDS[skillLine],
        subcategory = true,
        sources = { "professions" },
        static = true,
        offered = function() return D.ProfessionRanks()[skillLine] ~= nil end,
        test = function(entry) return entry.skillLine == skillLine end,
    })
end

-- The overview (opened without text): your professions with a bar in the game's own fill
-- (skillbar_fill_flipbook_*, the Forever version where there is one), main professions first, then
-- the secondary ones (Cooking, Fishing, First Aid). A click opens the profession's subcategory.
local FILLS = {
    [129] = "skillbar_fill_flipbook_firstaid_c60", [164] = "skillbar_fill_flipbook_blacksmithing",
    [165] = "skillbar_fill_flipbook_leatherworking", [171] = "skillbar_fill_flipbook_alchemy_c60",
    [182] = "skillbar_fill_flipbook_herbalism", [185] = "skillbar_fill_flipbook_cooking",
    [186] = "skillbar_fill_flipbook_mining", [197] = "skillbar_fill_flipbook_tailoring",
    [202] = "skillbar_fill_flipbook_engineering", [333] = "skillbar_fill_flipbook_enchanting_c60",
    [356] = "skillbar_fill_flipbook_fishing", [393] = "skillbar_fill_flipbook_skinning_c60",
}
local SECONDARY = { [129] = true, [185] = true, [356] = true }

local function OverviewEntries()
    local ranks, maxima = D.ProfessionRanks()
    local list = {}
    for skillLine, rank in pairs(ranks) do
        if SKILLS[skillLine] then
            local maximum = maxima[skillLine] or 0
            local text = ns.Progress(rank, maximum)
            list[#list + 1] = {
                name = SKILLS[skillLine], icon = SKILL_ICONS[skillLine], filter = subcategories[skillLine],
                secondary = SECONDARY[skillLine] == true,
                bar = { rank, maximum, text, nil, FILLS[skillLine] },
                lines = { { text } },
            }
        end
    end
    table.sort(list, function(a, b)
        if a.secondary ~= b.secondary then return b.secondary end
        return a.name < b.name
    end)
    for i, entry in ipairs(list) do entry.order = i end
    return list
end

local yours = {}

-- Where a recipe to come is learned: a trainer, or its recipe item (D.RecipeItemFrom): "Sold by X" /
-- "Drops from X 2 %"; nil if nobody sells or drops it
local function LearnedFrom(entry)
    if (entry.recipeItem or 0) == 0 then return L["Trainer"] end
    -- not "local how, npc, chance = x and f()": "and" keeps only the first result
    local how, npc, chance = D.RecipeItemFrom(entry)
    if how == "sold" then return L["Sold by %s"]:format(npc.name) end
    if how == "drop" then
        return L["Drops from %s"]:format(npc.name) .. (chance > 0 and (" " .. chance .. " %") or "")
    end
    return nil
end

local function Describe(entry)
    local profession = SKILLS[entry.skillLine]
    if entry.hidden and entry.skill > 0 then
        return { profession, LearnedFrom(entry) }
    end
    return { profession }
end

-- The color a learned recipe has in the game's profession window (D.RecipeSkillColor) as RGB with its
-- kind ("orange", ...); the row state and the tooltip's "For you" use it
local SKILL_UP = {
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 },
}
for kind, color in pairs(SKILL_UP) do color.kind = kind end
local function SkillUp(entry)
    local kind = D.RecipeSkillColor(entry)
    return kind and SKILL_UP[kind] or nil
end

-- Row state (UI\List.lua): a learned recipe how often you can make it with what you carry, in its skill
-- color; one to come learnable now, or the skill it needs
local function State(entry)
    if not entry.hidden then
        local recipe = D.RecipeOf(entry.spellID, entry.skillLine)
        if not (recipe and recipe[4]) then return nil end
        local times = D.CraftTimes(entry)
        return times > 0 and L["Can make %d"]:format(times) or L["Missing reagents"], SkillUp(entry) or "plain"
    end
    local learnable = D.RecipeLearnable(entry)
    if learnable == "now" then return L["Learnable now"], "good" end
    if learnable == "later" then return L["Skill %d"]:format(entry.learn or entry.skill), "no" end
    if D.RecipeSpecializationMissing(entry.spellID) then return L["Other specialization"], "no" end
    return nil
end

-- Tooltip's For you (UI\Tooltip.lua): whether the item it makes is an upgrade; a learned recipe's chance
-- to raise your skill, in its skill color
local function ForYou(entry, add)
    local made = D.RecipeOf(entry.spellID, entry.skillLine)
    local upgrade = made and (made[1] or 0) ~= 0 and ns.rec.Upgrade(made[1])
    if upgrade then add(L["Makes an upgrade: %s"]:format(upgrade), "good") end
    if not entry.hidden then
        local color = SkillUp(entry)
        local chance = D.RecipeSkillChance(entry)
        if color and color.kind == "grey" then
            add(L["Raises your skill no more"], color)
        elseif chance then
            add(L["Skill up: %d %%"]:format(math.floor(chance * 100 + 0.5)), color)
        end
    end
end

-- A profession's tab opened without text: your recipes of it, what you would look up most first, then
-- by color (orange, yellow, green, grey) as the game's profession window, then A-Z.
local COLOR_ORDER = { orange = 1, yellow = 2, green = 3, grey = 4 }
local source
local learned, colors = {}, {}
local function ByColor(a, b)
    local ca, cb = colors[a], colors[b]
    if ca ~= cb then return ca < cb end
    return nil
end
local function Browse(take)
    ns.rec.Prepare()
    wipe(learned)
    wipe(colors)
    for _, entry in ipairs(source.index.entries) do
        if not entry.hidden then
            learned[#learned + 1] = entry
            colors[entry] = COLOR_ORDER[D.RecipeSkillColor(entry) or ""] or 5
        end
    end
    for _, entry in ipairs(ns.rec.Sort(learned, ByColor)) do take(entry) end
end

-- The profession's own spells that open its window (its ranks, named like the profession:
-- "Blacksmithing"; Smelting for Mining; Fishing too): no recipes, out of lists and search (the menu
-- opens the window: "Open <profession>").
local SMELTING = 2656
local function WindowSpell(entry)
    return entry.spellID == SMELTING or entry.name == SKILLS[entry.skillLine]
        or entry.name == D.professionNames[entry.skillLine]
end

source = ns.RegisterSource({
    key = "professions",
    domain = "professions",
    name = L["Professions"],
    icon = 2447783, -- the crossed tools of WoW Forever's character window tabs (seen in game)
    actionLabel = L["cast"],
    owned = function(entry) return not entry.hidden end,
    -- an unlearned recipe: findable by typing if you have the profession; specialisations (skill 0) are no
    -- recipes, but one a recipe item teaches is (Forever's Fishing recipes have no skill in the data)
    findable = function(entry)
        return yours[entry.skillLine] ~= nil and (entry.skill > 0 or (entry.recipeItem or 0) ~= 0)
    end,
    leaveOut = WindowSpell,
    beforeSearch = function() yours = D.ProfessionRanks() end,
    overview = "bars",
    overviewEntries = OverviewEntries,
    browse = Browse,
    describe = Describe,
    state = State,
    forYou = ForYou,
})
