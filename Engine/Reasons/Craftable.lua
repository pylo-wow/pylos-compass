local _, D = ...
local ns = D.engine
local L = ns.L

-- Craftable: a recipe you know whose reagents are all in your bags (D.RecipeOf: spell ID -> { item, how many, skill line,
-- reagent, count, ... }; enchantments too). The row says how often ("Can make 3", D.CraftTimes). With "skillUp" a
-- recipe that raises your skill and can be made now comes first.

ns.RegisterReason({
    key = "craftable",
    -- weight 0.7, the least of a stage: being able to make something says
    -- little by itself (with "skillUp" it comes first)
    stage = "professions", weight = 0.7, label = "Craftable",
    sources = { "professions" },
    depends = { "bags", "spells", "skills", "data" },
    topic = "professions",
    profession = true,
    test = function(entry)
        if entry.hidden then return nil end
        return D.CraftTimes(entry) > 0
    end,
    note = function(entry) return L["Can make %d"]:format(D.CraftTimes(entry)) end,
    why = function(entry) return L["Your bags hold everything to make it %d times"]:format(D.CraftTimes(entry)) end,
})
