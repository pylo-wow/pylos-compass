local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- Learn later: what you cannot learn yet: your class's spells from a level above yours, and recipes of your
-- professions your skill is too low for (D.RecipeLearnable "later"). Rows show the level or skill needed; without
-- text they come in that order, the next first (order). Shows hidden entries (reveals), as Available does.

-- the hidden spells and recipes: rebuilt only when Data rebuilt them
local pool = D.Cache({ "data:spells", "data:professions" })

-- level a spell is learned at (a trainer seen since the list was built counts), skill a recipe needs
local function Needs(entry)
    if entry.trainLevel then return D.TrainingLevel and D.TrainingLevel(entry.spellID) or entry.trainLevel end
    return entry.learn or entry.skill or 0
end

ns.RegisterFilter({
    key = "learnLater",
    name = L["Learn later"],
    description = L["Spells and recipes you cannot learn yet, the next first: your level or your skill is too low."],
    words = "later learn future upcoming next level skill",
    icon = "Interface\\Icons\\INV_Scroll_04",
    sources = { "spells", "professions" },
    reveals = true,
    test = function(entry)
        if entry.trainLevel then return Needs(entry) > UnitLevel("player") end
        return D.RecipeLearnable(entry) == "later"
    end,
    order = function(a, b)
        local na, nb = Needs(a), Needs(b)
        if na ~= nb then return na < nb end
        return a.key < b.key
    end,
    -- only hidden entries can pass
    pool = function()
        local list, renewed = pool.Get()
        if not renewed then return list end
        for _, key in ipairs({ "spells", "professions" }) do
            for _, entry in ipairs(D.Entries(key)) do
                if entry.hidden then list[#list + 1] = entry end
            end
        end
        return list
    end,
})
