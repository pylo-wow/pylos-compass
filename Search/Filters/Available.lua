local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- Available: what a trainer would teach you now and you have not learned (D.LearnableNow decides). Shows hidden entries (reveals).

-- the hidden spells and recipes: rebuilt only when Data rebuilt them
local pool = D.Cache({ "data:spells", "data:professions" })

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
