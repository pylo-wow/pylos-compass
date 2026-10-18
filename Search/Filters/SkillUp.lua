local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- Skill up: your learned recipes that still raise your skill (orange, yellow or green:
-- D.RecipeSkillChance above 0). Sorted by fit as always, so typed text decides.

-- your learned recipes: rebuilt only when Data rebuilt them
local pool = D.Cache({ "data:professions" })

ns.RegisterFilter({
    key = "skillUp",
    name = L["Skill up"],
    description = L["Your recipes that still raise your skill: orange, yellow or green."],
    words = "skill up points raise orange yellow green",
    icon = "Interface\\Icons\\INV_Scroll_03",
    sources = { "professions" },
    test = function(entry) return (D.RecipeSkillChance(entry) or 0) > 0 end,
    -- only learned recipes can pass: a few hundred instead of 2,666
    pool = function()
        local list, renewed = pool.Get()
        if not renewed then return list end
        for _, entry in ipairs(D.Entries("professions")) do
            if not entry.hidden then list[#list + 1] = entry end
        end
        return list
    end,
})
