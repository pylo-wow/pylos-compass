local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Items: all items of the game, with the item's subtype on the right (searchable; how many you carry is
-- added when shown). Entries and facts come from the data layer (World\Items.lua). Action: use the item,
-- if you carry it.

-- what the list's rows and the action need (the search's own fields)
D.AddField("items", "type", function() return "item" end)
D.AddField("items", "value", function(entry) return "item:" .. entry.itemID end)

-- Subcategories (tabs beside the list): item kinds by the game's item class (GetItemInfoInstant, known
-- for every item at once), merged into seven: classic has about twelve, too many for the window.
--   0 consumable, 1 container, 2 weapon, 3 gem, 4 armor, 5 reagent,
--   6 projectile, 7 trade goods, 8 item enhancement, 9 recipe, 11 quiver,
--   12 quest, 13 key, 15 miscellaneous
local KINDS = {
    { "weapons", L["Weapons"], "INV_Sword_04", { [2] = true } },
    { "armor", L["Armor"], "INV_Chest_Plate01", { [4] = true } },
    { "consumables", L["Consumables"], "INV_Potion_51", { [0] = true } },
    { "crafting", L["Crafting"], "INV_Ingot_02", { [3] = true, [5] = true, [7] = true, [8] = true, [9] = true } },
    { "quest", L["Quest"], "INV_Misc_Note_01", { [12] = true } },
    { "bags", L["Bags"], "INV_Misc_Bag_08", { [1] = true, [6] = true, [11] = true } },
}
local known = {}
for _, kind in ipairs(KINDS) do
    for class in pairs(kind[4]) do known[class] = true end
end
for _, kind in ipairs(KINDS) do
    local classes = kind[4]
    ns.RegisterFilter({
        key = "items:" .. kind[1], name = kind[2], icon = "Interface\\Icons\\" .. kind[3],
        subcategory = true, sources = { "items" }, static = true,
        test = function(entry) return classes[entry.itemClass] == true end,
    })
end
-- the rest (keys, miscellaneous, ...)
ns.RegisterFilter({
    key = "items:other", name = L["Miscellaneous"], icon = "Interface\\Icons\\INV_Misc_QuestionMark",
    subcategory = true, sources = { "items" }, static = true,
    test = function(entry) return not known[entry.itemClass] end,
})

-- Line below an item's name: armor its slot and material ("Hands · Mail"; rings, necks and cloaks only
-- the slot), else its subtype ("Two-Handed Maces"); the slot name is the game's own (INVTYPE_HAND).
local function Describe(entry)
    local parts = {}
    if entry.itemClass == 4 and entry.equipLoc and entry.equipLoc ~= "" then
        parts[1] = _G[entry.equipLoc]
        if entry.itemSubClass ~= 0 and entry.equipLoc ~= "INVTYPE_CLOAK" then parts[2] = entry.category end
    else
        parts[1] = entry.category
    end
    return parts
end

-- Row state (UI\List.lua): a recipe item of no use now (known, other profession or specialization, skill
-- too low) or learnable now, the level it needs while above yours, an upgrade for you; else none (the
-- hotkey shows there)
local RECIPE_STATES = { known = { L["Already known"], "done" }, profession = { L["Profession not learned"], "no" },
    specialization = { L["Other specialization"], "no" }, skill = { L["Skill too low"], "no" } }
ns.RECIPE_STATES = RECIPE_STATES -- (UI\List.lua)
local function State(entry)
    local recipe = RECIPE_STATES[entry.recipeState]
    if recipe then return recipe[1], recipe[2] end
    if D.LearnableNow(entry) then return L["Learnable now"], "good" end
    if (entry.requiredLevel or 0) > UnitLevel("player") then
        return L["From level %d"]:format(entry.requiredLevel), "no"
    end
    local upgrade = ns.rec.Upgrade(entry.itemID)
    if upgrade then return upgrade, "good" end
    return nil
end

-- Tooltip's For you (UI\Tooltip.lua): how many you have, the recipes it goes into
local function ForYou(entry, add)
    local itemID = entry.itemID
    local bags = C_Item.GetItemCount(itemID)
    local all = C_Item.GetItemCount(itemID, true)
    if bags > 0 then add(L["In your bags: %d"]:format(bags), "plain") end
    if all > bags then add(L["In the bank: %d"]:format(all - bags), "plain") end
    local using = D.RecipesUsing(itemID)
    if #using > 0 then
        local ranks, yours = D.ProfessionRanks(), 0
        for _, spellID in ipairs(using) do
            local recipe = D.Recipe(spellID)
            if recipe and ranks[recipe[3]] then yours = yours + 1 end
        end
        local text = #using == 1 and L["Used in 1 recipe"] or L["Used in %d recipes"]:format(#using)
        if yours > 0 then text = text .. ", " .. (yours == #using and L["yours"] or L["%d of yours"]:format(yours)) end
        add(text, "plain")
    end
end

local pool = {}

-- Opened without text: "In bags" set (defaultFilters) and what passes it; with no filter (a tab or a
-- quality alone is none, Index.lua) an empty list with the hint.
local HINT = L["Type to search, or pick a filter."]
local function Browse() return HINT end

ns.RegisterSource({
    key = "items",
    domain = "items",
    name = L["Items"],
    hint = L["Search items"],
    emptyHint = HINT,
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    iconAtlas = "bags-up-c60", -- WoW Forever's backpack of the bag bar (icon is the fallback)
    actionLabel = L["use"],
    owned = function(entry) return D.ownedItems[entry.itemID] end,
    pool = function()
        wipe(pool)
        D.RefreshOwned()
        for id in pairs(D.ownedItems) do pool[#pool + 1] = D.ItemByID(id) end
        return pool
    end,
    defaultFilters = { "inBags" },
    browse = Browse,
    describe = Describe,
    state = State,
    forYou = ForYou,
})
