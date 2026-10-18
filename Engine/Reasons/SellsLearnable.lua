local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Sells learnable: a vendor with recipe items of your professions whose recipe you can learn now (D.RecipeLearnable;
-- recipes for later are no next step). Strength 1 for one recipe, +0.5 for each doubling, at most 2 (Reasons.lua: Grow).
-- The row shows a recipe scroll with how many. A recipe item you already have (in your bags, not learned yet) does not
-- count: no need to buy it again.

local function Count(npcID)
    local now = 0
    for item in (D.Sells(npcID) or ""):gmatch("%d+") do
        local itemID = tonumber(item)
        local recipe = not D.ownedItems[itemID] and D.RecipeOfItem(itemID)
        if recipe and D.RecipeLearnable(recipe) == "now" then now = now + 1 end
    end
    return now
end

ns.RegisterReason({
    key = "sellsLearnable",
    -- weight 1.25: a recipe to learn now opens new skill ups
    stage = "professions", weight = 1.25, label = "Sells learnable",
    sources = { "npcs" },
    depends = { "bags", "gear", "skills", "spells", "level", "npcs", "data" },
    topic = "professions",
    test = function(entry)
        local now = Count(entry.npcID)
        if now == 0 then return nil end
        return ns.reasons.Grow(now, 1)
    end,
    profession = true,
    note = function(entry)
        local now = Count(entry.npcID)
        return { icon = "Interface\\Icons\\INV_Scroll_03", count = now,
            tip = L["Sells %d recipes you can learn now"]:format(now) }
    end,
})
