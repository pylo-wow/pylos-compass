local _, D = ...
local ns = D.engine
local L = ns.L

-- Learnable: what a trainer would teach you now and you have not learned (the spells' list opened without text starts with it).
--   spells   your class (and race), your level reaches the trainer level, the rank before it is learned
--   recipes  D.RecipeLearnable says "now" (D.LearnableNow)
--   items    a recipe item in your bags whose recipe you can learn now: use it
-- The reach is the way to your trainer (reach.Trainer) or to the recipe item. Where a trainer of yours is known, his own
-- row (TrainsYou.lua) stands for his spells and carries the way for all; with none known they stand on their own.

local classID = 0

-- the way to a trainer: factor, "Trainer Name, 120 yd away"
local function ToTrainer(teaches)
    local trainer, factor, words = ns.reach.Trainer(teaches)
    if not trainer then return ns.reach.TRAVEL, L["no trainer known"] end
    return factor, trainer.name .. (words and (", " .. words) or "")
end

-- what a trainer teaches it: your class, or its profession (nil: a recipe item teaches it)
local function Teaches(entry)
    if entry.trainLevel then return classID end
    if entry.skillLine and (entry.recipeItem or 0) == 0 then return entry.skillLine end
    return nil
end

ns.RegisterReason({
    key = "learnable",
    -- weight 0.7, the least of a stage: one spell or recipe is a small step; the trainer's row (trainsYou) stands for all
    stage = "progress", weight = 0.7, label = "Learnable",
    sources = { "spells", "professions", "items" },
    -- wherever you stand: your spells, level, skills, bags, the trainers' lists seen ("npcs")
    depends = { "spells", "level", "skills", "bags", "npcs", "data" },
    topic = function(entry) return entry.trainLevel ~= nil and "class" or "professions" end,
    prepare = function() classID = select(3, UnitClass("player")) or 0 end,
    test = function(entry) return D.LearnableNow(entry) or nil end,
    reach = function(entry)
        if entry.itemID then return ns.reach.NOW, nil end
        if entry.trainLevel then return ToTrainer(classID) end
        if (entry.recipeItem or 0) ~= 0 then return ns.reach.Item({ itemID = entry.recipeItem }) end
        return ToTrainer(entry.skillLine)
    end,
    profession = function(entry) return entry.itemID ~= nil or entry.skillLine ~= nil end,
    -- a trainer of yours is known: his row stands for it
    covered = function(entry)
        local teaches = Teaches(entry)
        return teaches ~= nil and ns.reach.Trainer(teaches) ~= nil
    end,
    why = function(entry)
        if entry.itemID then return L["Use it to learn the recipe"] end
        if (entry.recipeItem or 0) ~= 0 then return L["You can learn it now from its recipe"] end
        return L["A trainer can teach it to you now"]
    end,
})
