local _, D = ...
local ns = D.engine
local L = ns.L

-- You are here (knowing): the dungeon or raid you are in. Its bosses, quests and drops are what you look up inside.
-- The instance's map ID from the client (GetInstanceInfo), the same as the dungeons' entries (entry.mapID).

local mapID -- the instance you are in; per search

local function Here()
    if not IsInInstance() then return nil end
    return select(8, GetInstanceInfo())
end

ns.RegisterReason({
    key = "youAreHere",
    -- weight 1.2: where you are right now, close to your target
    stage = "know", weight = 1.2, label = "You are here",
    kind = "know",
    sources = { "dungeons" },
    depends = { "zone", "data" },
    prepare = function() mapID = Here() end,
    candidates = function(add)
        mapID = Here()
        if not mapID then return end
        for _, entry in ipairs(D.Entries("dungeons")) do
            if entry.mapID == mapID then add(entry) end
        end
    end,
    test = function(entry) return mapID ~= nil and entry.mapID == mapID and 1 or nil end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["You are here"] end,
})
