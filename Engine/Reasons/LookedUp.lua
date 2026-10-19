local _, D = ...
local ns = D.engine
local L = ns.L

-- Looked up (knowing): what you chose in the search again and again (the search tells it: R.Chose), more what you
-- chose in the situation you are in now (resting, instance, group, alone: Memory.lua), e.g. looking up the flight
-- master after landing. Weak by design: one choice is no reason, only a repeated one, and even then it comes after
-- every other reason (at most SCALE: below what you just looted, fading). Both fade with the memory's half-life;
-- doing something in the game is no lookup and does not count here.

local REPEATED = 0.65 -- a choice's memory from this on (about two recent choices: 1 -> 0.5, 2 -> 0.67)
local SCALE = 0.25    -- the strongest habit's strength (Looted starts at 0.3)
local HERE, ANYWHERE = 1, 0.5

local function Parts(entry)
    local chosen, here = ns.memory.UsedParts(D.EntryID(entry))
    return chosen, here
end

ns.RegisterReason({
    key = "lookedUp",
    -- weight 0.7: the lightest, a habit is no recommendation
    stage = "know", weight = 0.7, label = "Looked up",
    learn = false, -- choosing one again is the lookup itself
    kind = "know",
    sources = { "items", "npcs", "spells", "professions", "dungeons" },
    depends = { "rec:chosen", "rec:memory", "zone", "group" }, -- your choices and the situation: Memory.lua
    candidates = function(add)
        for i, id in ipairs(ns.memory.Recent()) do
            if i > ns.RECENT then break end
            add(D.EntryByID(id))
        end
    end,
    test = function(entry)
        local chosen, here = Parts(entry)
        if chosen < REPEATED and here < REPEATED then return nil end
        return SCALE * math.max(HERE * here, ANYWHERE * chosen)
    end,
    reach = function() return ns.reach.NOW, nil end,
    errand = false,
    note = function() return L["Looked up before"] end,
    why = function(entry)
        local chosen, here = Parts(entry)
        return HERE * here >= ANYWHERE * chosen and L["Looked up before, in this situation"] or L["Looked up before"]
    end,
})
