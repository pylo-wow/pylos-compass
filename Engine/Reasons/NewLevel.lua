local _, D = ...
local ns = D.engine
local L = ns.L

-- New level (knowing): you just reached a level that brings new spells: where is your class trainer? Your trainer (the
-- nearest, reach.Trainer) for FRESH after the level up, while he has spells for you that the new level brought. The
-- spells themselves stand with him (Learnable's covered). Levels this session only; the first look takes the level you
-- log in with.

local FRESH = 15 * 60 -- seconds after the level up
local before, cameAt  -- your level before the last level up, and when it came
local known           -- your level as last seen

local function Look()
    local level = UnitLevel("player")
    if known and level > known then before, cameAt = known, time() end
    known = level
end
-- your level changed (state; UnitLevel may still be the old level while PLAYER_LEVEL_UP is told: the poll tells again,
-- and every search looks too)
D.OnState("level", Look)

local function Fresh() return cameAt ~= nil and time() - cameAt < FRESH end

local classID = 0
local new = {} -- names of the spells the new level brought (per search), sorted
local function NewSpells()
    wipe(new)
    for _, entry in ipairs(D.Entries("spells")) do
        if entry.hidden and entry.trainLevel and entry.trainLevel > before and ns.reasons.Test("learnable", entry) then
            new[#new + 1] = entry.name
        end
    end
    table.sort(new)
    return #new
end

local NAMES = 5 -- spell names its tooltip lists

ns.RegisterReason({
    key = "newLevel",
    -- weight 1.1: what a level up brings is what you look up next
    stage = "know", weight = 1.1, label = "New level",
    kind = "know",
    sources = { "npcs" },
    depends = { "level", "spells", "npcs", "data" }, -- (fading with time: kept at most STALE seconds, Reasons.lua)
    prepare = function()
        Look()
        classID = select(3, UnitClass("player")) or 0
        if Fresh() then NewSpells() else wipe(new) end
    end,
    candidates = function(add)
        Look()
        if Fresh() then add(ns.reach.Trainer(classID)) end
    end,
    test = function(entry)
        if not Fresh() or #new == 0 then return nil end
        return ns.reach.Trainer(classID) == entry and 1 or nil
    end,
    note = function() return #new == 1 and L["New level: 1 spell"] or L["New level: %d spells"]:format(#new) end,
    why = function()
        return (#new == 1 and L["New level: a new spell to learn"] or L["New level: %d new spells to learn"]:format(#new)) .. ": "
            .. table.concat(new, ", ", 1, math.min(#new, NAMES)) .. (#new > NAMES and ", ..." or "")
    end,
})
