local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- For me: items your character can use now (level, class, armor and weapon kinds learned); D.ItemForYou
-- decides.

ns.RegisterFilter({
    key = "forMe",
    name = L["For me"],
    description = L["Items your character can use now: level, class, armor and weapon kinds."],
    words = "for me usable wearable my class",
    icon = "Interface\\Icons\\INV_Shirt_White_01",
    sources = { "items" },
    prepare = function() D.ItemForYouPrepare() end,
    test = function(entry) return D.ItemForYou(entry) end,
})
