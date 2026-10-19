local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Available: what a trainer would teach you now and you have not learned (D.LearnableNow decides).
-- Shows hidden entries (reveals).

ns.RegisterFilter({
    key = "available",
    name = L["Available"],
    description = L["Spells and recipes a trainer can teach you now."],
    words = "available learnable trainer new",
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    sources = { "spells", "professions" },
    reveals = true,
    test = D.LearnableNow,
    -- only hidden entries can pass
    pool = ns.HiddenLearnables,
})
