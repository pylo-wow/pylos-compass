local ns = select(2, ...).search
local L = ns.L

-- Quality: one filter per quality, named and coloured as in the game ("Epic" in purple), found by its
-- colour too ("purple"). One group: two qualities set show both.

local WORDS = {
    [0] = "grey gray poor junk",
    [1] = "white common",
    [2] = "green uncommon",
    [3] = "blue rare",
    [4] = "purple epic",
    [5] = "orange legendary",
}

for quality = 0, 5 do
    local ok, r, g, b, hex = pcall(C_Item.GetItemQualityColor, quality)
    ns.RegisterFilter({
        key = "quality" .. quality,
        name = _G["ITEM_QUALITY" .. quality .. "_DESC"],
        words = "quality " .. WORDS[quality],
        icon = "Interface\\Icons\\INV_Misc_Gem_Diamond_01", -- white, tinted in the quality's colour
        iconColor = ok and { r, g, b } or nil,
        color = ok and hex or nil,
        group = "quality", groupName = L["Quality"], -- one section of the filter window
        description = L["Items of this quality."],
        sources = { "items" },
        static = true, -- the item's own fact (Index.lua keeps what passes)
        refines = true, -- no filter of its own (Index.lua: alone the list stays empty)
        test = function(entry) return entry.quality == quality end,
    })
end
