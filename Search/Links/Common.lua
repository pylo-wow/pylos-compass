local ns = select(2, ...).search
local D = ns.data

-- Rows of a link's list (Links\*.lua): an item or NPC with the entry behind it (target: a click opens
-- it, the tooltip is its own) and the link's info on the right (category).

-- A linked row's tooltip lines (and reaction: the name color, UI\Kit\Widgets.lua EntryText) are its
-- target's, worked out when first read: building them for every row would make a menu that only counts
-- rows (an item dropped by 40 NPCs) build 40 tooltips.
ns.LINKED_ROW = { __index = function(row, field)
    if field == "lines" or field == "reaction" then return row.target[field] end
end }

-- an item: its entry from the item index if built (name in the client's language)
function ns.LinkedItem(itemID, info)
    local target = ns.index.ItemByID(itemID)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    return { name = target and target.name or D.NameEN("item", itemID) or ("#" .. itemID),
        icon = icon, category = info, itemID = itemID, target = target,
        type = "item", value = "item:" .. itemID,
        knownRecipe = D.RecipeKnownForItem(itemID),
        recipeState = D.RecipeState(itemID) }
end

-- any entry of a category: its row in a link's list, info on the right
function ns.LinkedEntry(target, info)
    if not target then return nil end
    return setmetatable({ name = target.name, icon = target.icon, iconAtlas = target.iconAtlas,
        iconPart = target.iconPart, category = info, target = target }, ns.LINKED_ROW)
end

-- an NPC: only one the NPCs category knows (nil while it is switched off or not built yet)
function ns.LinkedNPC(npcID, info)
    local target = ns.index.EntryByID("n:" .. npcID)
    if not target then return nil end
    return setmetatable({ name = target.name, icon = target.icon, displayID = target.displayID, category = info,
        target = target, npcID = npcID }, ns.LINKED_ROW)
end
