local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Learn later: what you cannot learn yet: your class's spells from a level above yours, and recipes of your
-- professions your skill is too low for (D.RecipeLearnable "later"). Rows show the level or skill needed; without
-- text they come in that order, the next first (order). Shows hidden entries (reveals), as Available does.

ns.RegisterFilter({
    key = "learnLater",
    name = L["Learn later"],
    description = L["Spells and recipes you cannot learn yet, the next first: your level or your skill is too low."],
    words = "later learn future upcoming next level skill",
    icon = "Interface\\Icons\\INV_Scroll_04",
    sources = { "spells", "professions" },
    reveals = true,
    test = function(entry)
        if entry.trainLevel then return ns.LearnNeeds(entry) > UnitLevel("player") end
        return D.RecipeLearnable(entry) == "later"
    end,
    order = function(a, b)
        local na, nb = ns.LearnNeeds(a), ns.LearnNeeds(b)
        if na ~= nb then return na < nb end
        return a.key < b.key
    end,
    -- only hidden entries can pass
    pool = ns.HiddenLearnables,
})
