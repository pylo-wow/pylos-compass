local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Recipe links of items (Data, World\Professions.lua: D.RecipeOf, spell ID -> { created item, how many,
-- skill line, reagent, count, ... }; D.RecipesMaking / D.RecipesUsing): "used for" lists the items made
-- with an item, "made from" its reagents, "recipe" the recipes making it, "creates" a recipe's item.
-- Each item once; the profession and the count on the right.

local SKILLS = ns.professionNames -- skill line -> profession name (Sources\Professions.lua)
local ICON = "Interface\\Icons\\Trade_BlackSmithing"
local LinkedItem = ns.LinkedItem -- (Links\Common.lua)

-- the line below a linked item: the recipe's profession, how many ("Tailoring  ·  ×2")
local function Amount(recipe, count)
    local skill = SKILLS[recipe[3]]
    return (skill and skill .. ns.widgets.DOT or "") .. "×" .. count
end

ns.RegisterLink({
    key = "usedFor",
    label = L["Used for"],
    title = L["%s is used for:"],
    icon = ICON,
    entries = function(entry)
        if not entry.itemID then return {} end
        local list, seen = {}, {}
        for _, spellID in ipairs(D.RecipesUsing(entry.itemID)) do
            local recipe = D.Recipe(spellID)
            if recipe[1] ~= 0 and not seen[recipe[1]] then -- 0: an enchantment makes no item
                seen[recipe[1]] = true
                local need = 1
                for i = 4, #recipe, 2 do
                    if recipe[i] == entry.itemID then need = recipe[i + 1] end
                end
                -- the reagent stands in the bar already: only how many
                list[#list + 1] = LinkedItem(recipe[1], Amount(recipe, need))
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end,
})

ns.RegisterLink({
    key = "madeFrom",
    label = L["Made from"],
    title = L["%s is made from:"],
    icon = ICON,
    entries = function(entry)
        if not entry.itemID then return {} end
        local list, seen = {}, {}
        for _, spellID in ipairs(D.RecipesMaking(entry.itemID)) do
            local recipe = D.Recipe(spellID)
            for i = 4, #recipe, 2 do
                if not seen[recipe[i]] then
                    seen[recipe[i]] = true
                    list[#list + 1] = LinkedItem(recipe[i], Amount(recipe, recipe[i + 1]))
                end
            end
        end
        return list
    end,
})

-- "Recipe": the recipes that make the item, as the Professions category's entries (learned or not).
-- Only recipes of professions Data knows, and only while the Professions domain is built.
ns.RegisterLink({
    key = "recipe",
    label = L["Recipe"],
    direct = true, -- one recipe: straight to it
    title = L["Recipes for %s:"],
    icon = ICON,
    entries = function(entry)
        if not entry.itemID then return {} end
        local list = {}
        for _, spellID in ipairs(D.RecipesMaking(entry.itemID)) do
            local made = D.Recipe(spellID)
            local recipe = D.RecipeEntry(spellID, made and made[3]) -- of two professions
            local row = ns.LinkedEntry(recipe, "")
            if row then list[#list + 1] = row end
        end
        return list
    end,
})

-- "Creates": a recipe's finished item (straight to its detail view)
ns.RegisterLink({
    key = "creates",
    label = L["Creates"],
    title = L["%s creates:"],
    icon = ICON,
    direct = true,
    entries = function(entry)
        local recipe = entry.skillLine and entry.spellID and D.RecipeOf(entry.spellID, entry.skillLine)
        if not recipe or not recipe[1] or recipe[1] == 0 then return {} end
        return { LinkedItem(recipe[1], SKILLS[recipe[3]] or "") }
    end,
})
-- "Recipe item": the item a recipe is learned from (straight to its detail view)
ns.RegisterLink({
    key = "recipeItem",
    label = L["Recipe item"],
    title = L["%s is learned from:"],
    icon = ICON,
    direct = true,
    entries = function(entry)
        local item = entry.skillLine and entry.recipeItem
        if not item or item == 0 then return {} end
        return { LinkedItem(item, "") }
    end,
})