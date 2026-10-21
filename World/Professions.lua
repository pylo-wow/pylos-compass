local _, D = ...

-- Professions: recipes of every profession (Data\ProfessionSpells.lua). Learned ones are plain
-- entries, the others hidden = true. Icon is the made item's if any. Built in the background.
-- Also: your professions and skill (D.ProfessionRanks), what a recipe makes and needs
-- (D.RecipeOf, D.RecipesMaking, D.RecipesUsing), learnability (D.RecipeLearnable, D.LearnableNow),
-- skill color and skill-up chance (D.RecipeSkillColor, D.RecipeSkillChance), and how often
-- your bags can make it (D.CraftTimes).

local KEY = "professions"

local SKILLS = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking",
    [171] = "Alchemy", [182] = "Herbalism", [185] = "Cooking", [186] = "Mining",
    [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
    [356] = "Fishing", [393] = "Skinning", [40] = "Poisons",
}
D.professionNames = SKILLS

D.professionIcons = {
    [129] = 135966, [164] = 136241, [165] = 136247, [171] = 136240, [182] = 136246, [185] = 133971,
    [186] = 136248, [197] = 136249, [202] = 136243, [333] = 136244, [356] = 136245, [393] = 134366,
    [40] = 136242,
}

-- A skill line you have (weapon skills and professions): { name, rank, max, modifier, description }, else nil
function D.SkillLineInfo(id)
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
    if not ok or type(info) ~= "table" or not info.name or (info.maxRank or 0) == 0 then return nil end
    return { name = info.name, rank = info.rank or 0, max = info.maxRank, modifier = info.modifier or 0,
        description = info.description }
end

-- Your professions: skill line -> rank (plus a second table skill line -> maximum).
-- GetProfessions if available, else the skill window's data; rogue Poisons always from the
-- skill window (GetProfessions knows only professions, First Aid, Cooking and Fishing).
-- Cached until the skills change, at most a second (skill window data can arrive late);
-- it is asked on every key press by every profession tab and suggestion.
local ranksCache = D.Cache({ "skills" }, 1)
function D.ProfessionRanks()
    local cached = ranksCache.Get()
    if cached.ranks then return cached.ranks, cached.maxima end
    local ranks, maxima = {}, {}
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local _, _, rank, maximum, _, _, skillLine = GetProfessionInfo(index)
            if skillLine then ranks[skillLine], maxima[skillLine] = rank, maximum end
        end
    end
    if next(ranks) == nil then
        for skillLine in pairs(SKILLS) do
            local skill = D.SkillLineInfo(skillLine)
            if skill then ranks[skillLine], maxima[skillLine] = skill.rank, skill.max end
        end
    elseif not ranks[40] then
        local skill = D.SkillLineInfo(40)
        if skill then ranks[40], maxima[40] = skill.rank, skill.max end
    end
    cached.ranks, cached.maxima = ranks, maxima
    return ranks, maxima
end

-- Recipes

-- What a spell makes and needs, from C_TradeSkillUI.GetRecipeSchematic(spellID, false), also
-- for recipes you do not know (four Forever recipes name no item there).
-- D.recipes[spellID] = { made item (0: none, an enchantment), how many, skill line (0: none),
-- reagent, count, reagent, count, ... }, filled on demand. Recipes that make or need an item
-- the data does not know (test items) are left out.
D.recipes = {}
-- spell ID -> true: the client answered (a recipe, or one left out); a GetTime(): no answer
-- then, asked again after RETRY seconds (recipe data may not be loaded yet)
local asked = {}
local RETRY = 60
local function ItemKnown(itemID) return D.itemNamesEN == nil or D.itemNamesEN[itemID] ~= nil end
function D.RecipeOf(spellID, skillLine)
    local recipe = D.recipes[spellID]
    if recipe then return recipe end
    local at = asked[spellID]
    if at == true or (at and GetTime() - at < RETRY) then return nil end
    asked[spellID] = GetTime()
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
    if not ok or not schematic then return nil end
    asked[spellID] = true
    local made = schematic.outputItemID or 0
    if made ~= 0 and not ItemKnown(made) then return nil end
    recipe = { made, schematic.quantityMin or 1, skillLine or 0 }
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID and slot.required ~= false then
            if not ItemKnown(reagent.itemID) then return nil end
            recipe[#recipe + 1] = reagent.itemID
            recipe[#recipe + 1] = slot.quantityRequired or 1
        end
    end
    if made == 0 and #recipe == 3 then return nil end -- makes nothing, needs nothing
    D.recipes[spellID] = recipe
    return recipe
end
-- Loads every recipe: professions' plus other item-making spells (Data\OtherRecipes.lua); for the reverse maps below
local allAsked = false
function D.AllRecipes(Pause)
    if allAsked then return D.recipes end
    Pause = Pause or D.NoPause
    for skillLine, data in pairs(D.professionSpells or {}) do
        for i = 1, #data, 5 do
            D.RecipeOf(data[i], skillLine)
            if i % 160 == 1 then Pause() end
        end
    end
    for i, spellID in ipairs(D.otherRecipeSpells or {}) do
        D.RecipeOf(spellID, 0)
        if i % 32 == 0 then Pause() end
    end
    allAsked = true
    return D.recipes
end
-- A spell's recipe as known so far, without asking the client: nil if not asked yet or no recipe
function D.Recipe(spellID)
    return D.recipes[spellID]
end

-- Reverse maps: item ID -> recipes (spell IDs) making / using it. Built once in the background
-- after the professions (or on first use if that comes first); recipes with a profession first,
-- then by spell ID.
local usedFor, madeFrom
local NONE = {}
local function Maps(Pause)
    if usedFor then return end
    Pause = Pause or D.NoPause
    local used, made = {}, {}
    local recipes = D.AllRecipes(Pause)
    local function Note(map, itemID, spellID)
        local list = map[itemID] or {}
        map[itemID] = list
        if list[#list] ~= spellID then list[#list + 1] = spellID end
    end
    -- collect spells first: a pause may let others add recipes (D.RecipeOf), and adding a key
    -- during pairs() is an error in WoW's Lua
    local spells = {}
    for spellID in pairs(recipes) do spells[#spells + 1] = spellID end
    for i, spellID in ipairs(spells) do
        local recipe = recipes[spellID]
        if recipe[1] ~= 0 then
            Note(made, recipe[1], spellID)
            for k = 4, #recipe, 2 do Note(used, recipe[k], spellID) end
        end
        if i % 128 == 0 then Pause() end
    end
    local count
    local function Order(a, b)
        local skillA, skillB = SKILLS[recipes[a][3]] ~= nil, SKILLS[recipes[b][3]] ~= nil
        if skillA ~= skillB then return skillA end
        return a < b
    end
    for _, map in ipairs({ used, made }) do
        count = 0
        for _, list in pairs(map) do
            table.sort(list, Order)
            count = count + 1
            if count % 128 == 0 then Pause() end
        end
    end
    if usedFor then return end -- built by a use meanwhile
    usedFor, madeFrom = used, made
end
D.OnBuilt(function(key)
    if key == "professions" and not usedFor then D.Background("recipe links", Maps) end
end)
function D.RecipesMaking(itemID)
    Maps()
    return madeFrom[itemID] or NONE
end
function D.RecipesUsing(itemID)
    Maps()
    return usedFor[itemID] or NONE
end

-- Recipe to open in a profession window for an entry: a recipe of a profession you have, or for
-- an item a recipe of yours that makes it (learned first). Returns spell ID, skill line; nil if none.
function D.CraftingRecipe(entry)
    local ranks = D.ProfessionRanks()
    if entry.skillLine and entry.spellID then
        if ranks[entry.skillLine] then return entry.spellID, entry.skillLine end
        return nil
    end
    if not entry.itemID then return nil end
    local fallback
    for _, spellID in ipairs(D.RecipesMaking(entry.itemID)) do
        local recipe = D.recipes[spellID]
        local line = recipe and recipe[3]
        if line and ranks[line] then
            if D.SpellKnown(spellID) then return spellID, line end
            fallback = fallback or { spellID, line }
        end
    end
    if fallback then return fallback[1], fallback[2] end
    return nil
end

-- Name of the spell that opens a profession's window: the profession's own spell ("Blacksmithing");
-- Mining's window is Smelting (spell 2656). Cast it from a secure button: opening from addon code
-- (C_TradeSkillUI.OpenRecipe / OpenTradeSkill) is blocked in Forever ("Interface action failed
-- because of an AddOn", seen in game). nil for professions without a window (Herbalism, Skinning, Fishing).
local WINDOW_SPELL = { [186] = 2656 }
local NO_WINDOW = { [182] = true, [393] = true, [356] = true }
function D.ProfessionWindowSpell(skillLine)
    if NO_WINDOW[skillLine] then return nil end
    local spell = WINDOW_SPELL[skillLine]
    if spell then return C_Spell.GetSpellName(spell) end
    return SKILLS[skillLine]
end

-- A recipe's entry in this domain (learned or not); nil while not built. Own map because
-- D.EntryByID would return a spell book entry of the same spell first.
function D.RecipeEntry(spellID, skillLine)
    local domain = D.domains[KEY]
    local byID = domain and domain.byEntryID
    if not byID then return nil end
    return byID["s:" .. spellID] or (skillLine and byID["s:" .. spellID .. ":" .. skillLine]) or nil
end

-- The entries

local function Collect(list, Pause)
    local meta = D.Meta(KEY)
    local count = 0
    -- A recipe of two professions (Synthetic Gordok Ogre Suit: leatherworking and tailoring) is
    -- two entries, each with an ID that includes its skill line
    local seen, twice = {}, {}
    for _, data in pairs(D.professionSpells or {}) do
        for i = 1, #data, 5 do
            if seen[data[i]] then twice[data[i]] = true end
            seen[data[i]] = true
        end
    end
    for skillLine, data in pairs(D.professionSpells or {}) do
        local profession = SKILLS[skillLine]
        -- Learned spells of the same name once: a profession's ranks (Apprentice, Journeyman, ...)
        -- are same-name spells, all known (three times "Mining", seen in game); first one's icon,
        -- highest learned rank cast
        local learned = {}
        for i = 1, #data, 5 do
            local id = data[i]
            local name = C_Spell.GetSpellName(id)
            local known = name and D.SpellKnown(id)
            if known and learned[name] then
                local entry = learned[name]
                if id > entry.spellID then entry.spellID = id end
            elseif name then
                local recipe = D.RecipeOf(id, skillLine)
                local made = recipe and recipe[1] ~= 0 and recipe[1]
                local icon = made and select(5, C_Item.GetItemInfoInstant(made)) or C_Spell.GetSpellTexture(id)
                local skill = data[i + 1]
                -- skill to learn it: the recipe item's where it differs (Data\ProfessionSpells.lua), else the
                -- yellow rank
                local learn = data[i + 3] ~= 0 and D.recipeLearnRanks and D.recipeLearnRanks[id] or skill
                list[#list + 1] = setmetatable({
                    name = name, icon = icon, spellID = id,
                    category = known and profession or ("%s  ·  %d"):format(profession or "", learn),
                    hidden = not known,
                    skillLine = skillLine, skill = skill, learn = learn, acquire = data[i + 2],
                    recipeItem = data[i + 3], grey = data[i + 4],
                    entryID = twice[id] and ("s:" .. id .. ":" .. skillLine) or nil,
                }, meta)
                if known then learned[name] = list[#list] end
            end
            count = count + 1
            if count % 32 == 0 then Pause() end
        end
    end
end

D.RegisterDomain({
    key = KEY,
    background = true,
    collect = Collect,
    events = { "SPELLS_CHANGED", "SKILL_LINES_CHANGED" },
    signature = function()
        local known = 0
        for _, data in pairs(D.professionSpells or {}) do
            for i = 1, #data, 5 do
                if D.SpellKnown(data[i]) then known = known + 1 end
            end
        end
        return tostring(known)
    end,
})

-- The recipe an item teaches (recipeItem); nil if none or the domain is not built.
-- Cached until the professions are rebuilt.
local recipeOfItem = D.Cache({ "data:" .. KEY })
function D.RecipeOfItem(itemID)
    local map, renewed = recipeOfItem.Get()
    if renewed then
        for _, recipe in ipairs(D.Entries(KEY)) do
            if recipe.recipeItem and recipe.recipeItem > 0 then map[recipe.recipeItem] = recipe end
        end
    end
    return map[itemID]
end

function D.RecipeKnownForItem(itemID)
    local recipe = itemID and D.RecipeOfItem(itemID)
    return recipe ~= nil and recipe ~= false and not recipe.hidden
end

-- Spell ID of the specialisation a recipe needs and you lack (Gnomish Engineer, Armorsmith,
-- Dragonscale Leatherworking, ...), else nil. Data\ProfessionSpells.lua takes it from the recipe
-- item, or for trainer recipes from the 1.12 trainers (unchecked).
function D.RecipeSpecializationMissing(spellID)
    local need = D.recipeSpecializations and D.recipeSpecializations[spellID]
    if not need then return nil end
    if type(need) == "number" then
        if D.SpellKnown(need) then return nil end
        return need
    end
    for _, spell in ipairs(need) do
        if D.SpellKnown(spell) then return nil end
    end
    return need[1]
end

-- Why an item's recipe is useless to you now: "known", "profession" (not yours),
-- "specialization" (needs another one), "skill" (skill too low); nil if you could learn it or
-- the item teaches nothing
function D.RecipeState(itemID)
    local recipe = itemID and D.RecipeOfItem(itemID)
    if not recipe then return nil end
    if not recipe.hidden then return "known" end
    local rank = D.ProfessionRanks()[recipe.skillLine]
    if rank == nil then return "profession" end
    if D.RecipeSpecializationMissing(recipe.spellID) then return "specialization" end
    if (recipe.learn or recipe.skill) > rank then return "skill" end
    return nil
end

-- Where a recipe's item comes from (Data\NPCLinks.lua): the first vendor ("sold", NPC entry),
-- else the best drop ("drop", NPC entry, chance in whole percent, 0: small share); nil if no
-- known NPC sells or drops it (or the NPCs domain is not built)
function D.RecipeItemFrom(recipe)
    local item = recipe.recipeItem
    if not item or item == 0 then return nil end
    local sold = D.itemSoldBy and D.itemSoldBy[item]
    local vendor = sold and sold:match("%d+")
    if vendor then
        local npc = D.NPCByID(tonumber(vendor))
        if npc then return "sold", npc end
    end
    local dropped = D.itemDroppedBy and D.itemDroppedBy[item]
    -- (`dropped and dropped:match(...)` would keep only the first result)
    local npcID, chance
    if dropped then npcID, chance = dropped:match("(%d+):(%d+)") end
    if npcID then
        local npc = D.NPCByID(tonumber(npcID))
        if npc then return "drop", npc, tonumber(chance) or 0 end
    end
    return nil
end

-- Color of a learned recipe in the profession window by your skill: "orange" below the yellow
-- rank, "yellow" up to halfway to grey, then "green", "grey" from the grey rank (no skill up).
-- Nil without a skill to compare (specialisations, profession ranks) or if not learned.
function D.RecipeSkillColor(entry)
    local rank = D.ProfessionRanks()[entry.skillLine]
    local yellow, grey = entry.skill, entry.grey
    if entry.hidden or not rank or not grey or grey <= 0 or not yellow or yellow <= 0 then return nil end
    if rank >= grey then return "grey" end
    -- halfway rounded down (client's integer thresholds; unchecked in game)
    if rank >= math.floor((yellow + grey) / 2) then return "green" end
    if rank >= yellow then return "yellow" end
    return "orange"
end

-- Chance 0..1 that making a learned recipe raises your skill: sure up to the yellow rank, then
-- falling linearly to none at the grey rank. An estimate: Blizzard never published the numbers (only orange
-- 100 % and grey 0 % are certain). Nil as the color.
function D.RecipeSkillChance(entry)
    if not D.RecipeSkillColor(entry) then return nil end
    local rank = D.ProfessionRanks()[entry.skillLine]
    local yellow, grey = entry.skill, entry.grey
    if rank <= yellow then return 1 end
    if rank >= grey then return 0 end
    return (grey - rank) / (grey - yellow)
end

-- Learning

-- Can you learn a recipe you do not know yet: "now" (skill reaches it), "later" (your
-- profession, skill not reached) or nil (known, not your profession, not learnable).
-- The skill asked (learn) is the recipe item's (ItemSparse.RequiredSkillRank), else the yellow
-- rank (the trainer's is not in the client data; it lies at or a little below, so a recipe is
-- left out rather than promised too early). Requires: acquire 0, a skill to reach
-- (quest specialisations such as Armorsmith have none; seen in game), taught by a trainer or by a
-- recipe item that an NPC sells or drops, and no missing specialisation (D.RecipeSpecializationMissing).
-- ranks: skill line -> your skill (default D.ProfessionRanks()).
-- The single place this is decided (filter, vendor recipe count, NPC filter "Recipes for you").
function D.RecipeLearnable(recipe, yourRanks)
    local rank = (yourRanks or D.ProfessionRanks())[recipe.skillLine]
    if not recipe.hidden or rank == nil or recipe.acquire ~= 0 or (recipe.skill or 0) <= 0 then return nil end
    if recipe.recipeItem ~= 0 and D.RecipeItemFrom(recipe) == nil then return nil end
    if D.RecipeSpecializationMissing(recipe.spellID) then return nil end
    -- trainer recipes: once a trainer of the profession was seen, only what one listed
    -- (World\LearnTrainers.lua; e.g. the 1.12 data lets a fisherman teach Find Fish, Forever's does not)
    if recipe.recipeItem == 0 and D.TrainerListed and D.TrainerListed(recipe.spellID, recipe.skillLine) == false then
        return nil
    end
    local skill = recipe.recipeItem == 0 and D.TrainingSkill and D.TrainingSkill(recipe.spellID)
    return (skill or recipe.learn or recipe.skill) <= rank and "now" or "later"
end

-- Can you learn it right now: a recipe item in your bags whose recipe is learnable now, a
-- trainer spell (D.SpellLearnableNow) or a recipe whose skill you reach (D.RecipeLearnable "now")
function D.LearnableNow(entry)
    if entry.itemID then
        D.RefreshOwned()
        if not D.bagItems[entry.itemID] then return false end
        local recipe = D.RecipeOfItem(entry.itemID)
        return recipe ~= nil and D.RecipeLearnable(recipe) == "now"
    end
    if not entry.hidden then return false end
    if entry.trainLevel then return D.SpellLearnableNow(entry) end
    if entry.skillLine then return D.RecipeLearnable(entry) == "now" end
    return false
end

local GetCount = C_Item.GetItemCount
local countsCache = D.Cache({ "frame" }) -- item ID -> count in your bags; per frame

local function Count(itemID)
    local counts = countsCache.Get()
    local count = counts[itemID]
    if not count then
        count = GetCount(itemID)
        counts[itemID] = count
    end
    return count
end

-- How often your bags can make a recipe (entry with spellID and skillLine); 0 if not or if it needs nothing
function D.CraftTimes(entry)
    local recipe = entry.spellID and D.RecipeOf(entry.spellID, entry.skillLine)
    if not recipe or not recipe[4] then return 0 end
    local times
    for i = 4, #recipe, 2 do
        local need = recipe[i + 1] or 1
        local can = math.floor(Count(recipe[i]) / math.max(need, 1))
        if not times or can < times then times = can end
        if times == 0 then return 0 end
    end
    return times or 0
end
