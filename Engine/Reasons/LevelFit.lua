local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Level fit: meant for your level.
--   items     consumables of the kinds worth suggesting (potions, elixirs, flasks, scrolls, food with a buff, bandages,
--             enhancements; armour and weapons are Upgrade's), not junk, none that begins a quest, one you can use
--             (D.ItemForYou), not yours yet, needing your level or up to five below (at level 3 it fitted 8,265 items)
--   dungeons  your level or your group's (D.DungeonLevelFit; in a group as strong as the share it fits)

local ITEM_WINDOW = 5     -- levels below yours an item still fits
local SWEET = 0.4         -- where in a dungeon's level range it fits best
local level = 1

local TESTS = {
    items = function(entry)
        if entry.itemClass ~= 0 or not D.ItemSuggestedKind(entry) or entry.startsQuest
            or (entry.quality or 0) < 1 or D.ownedItems[entry.itemID] then return nil end
        local required = entry.requiredLevel or 0
        if required < level - ITEM_WINDOW or not D.ItemForYou(entry) then return nil end
        -- food and drink only with a buff (D.FoodBuffs; plain food fills nothing up); not known yet: not yet
        if D.IsFood(entry) and not D.FoodBuffs(entry) then return nil end
        -- only with a way to it (not a world drop alone)
        if not ns.reach.Known(entry) then return nil end
        return true
    end,
    -- how well your level sits in its range: best a little in (SWEET of the way up: the first levels are hard, the last
    -- bring little), 1.2 there, 0.6 at the far end; in a group times the share that fits. Your own level may lie outside
    -- the range when your group's fits: counted as at its edge (else negative)
    dungeons = function(entry)
        local fit = D.DungeonLevelFit(entry)
        if not fit then return nil end
        local low, top = D.DungeonLevelRange(entry)
        local way = math.min(1, math.max(0, (level - low) / math.max(1, top - low)))
        return (fit == true and 1 or fit) * (1.2 - math.abs(way - SWEET))
    end,
}

ns.RegisterReason({
    key = "levelFit",
    -- weight 1: the plain opportunity (consumables, dungeons for your level)
    stage = "opportunity", label = "Level fit",
    sources = { "items", "dungeons" },
    -- your level and group; the items yours and the ways to them
    depends = { "level", "group", "bags", "gear", "quests", "npcs", "money", "prices", "zone", "travel", "skills",
        "data" },
    topic = function(entry) return entry.domain == "dungeons" and "dungeons" or "supplies" end,
    prepare = function() level = UnitLevel("player") end,
    test = function(entry) return TESTS[entry.domain](entry) end,
    -- an item: how easy it is to get; a dungeon: with your group at hand,
    -- else a group to find and a way to go
    reach = function(entry)
        if entry.domain == "items" then return ns.reach.Item(entry) end
        if #D.GroupLevels() > 1 then return ns.reach.HERE, L["with your group"] end
        -- a group to find and the way to the entrance (the run itself is the
        -- suggestion, not its effort)
        local factor, words = ns.reach.Place(entry.place, ns.reach.GROUP_MINUTES)
        return factor, L["needs a group"] .. (words and (", " .. words) or "")
    end,
    note = function(entry)
        if entry.domain == "items" then return L["Fits your level"] end
        return nil
    end,
    why = function(entry)
        if entry.domain == "dungeons" and #D.GroupLevels() > 1 then return L["Fits your group"] end
        return L["Fits your level"]
    end,
})
