local addonName, D = ...

-- PylosCompassWorldDB: everything learned in the game, kept only on your computer.
--   met           zone an NPC was met in (World\LearnNPCs.lua)
--   vendorPrices  prices without discount where the data is wrong or missing, and each vendor's discount
--                 (World\Prices.lua)
--   npcs          NPCs seen while playing (World\LearnNPCs.lua), incl. the spells a trainer lists (LearnTrainers.lua)
--   training      what a trainer's service asks: level, skill, cost (World\LearnTrainers.lua)
--   quests        who gives and who takes each quest (World\LearnQuests.lua)
--   dungeons      dungeon entrances seen (World\Dungeons.lua)
--   crossings     walked crossings between zones (World\LearnCrossings.lua)
--   taxi          flight points each character knows (You\Taxi.lua)
--   travel        chars = each character's mount speed and hearthstone place (You\Hearth.lua)
--   eventsSeen    event key -> time an NPC of it was last seen (World\Events.lua creates it)
-- Set up at ADDON_LOADED; then the functions given to D.OnLoaded run (the learning files fill the tables).

local loaded = {} -- functions to call once PylosCompassWorldDB is set up
function D.OnLoaded(fn) loaded[#loaded + 1] = fn end

D.On("ADDON_LOADED", function(_, name)
    if name ~= addonName or D.world then return end
    local db = D.kit.Saved("PylosCompassWorldDB")
    -- a missing or wrong-typed table is replaced, so the learners can rely on them
    local function Table(parent, key)
        if type(parent[key]) ~= "table" then parent[key] = {} end
        return parent[key]
    end
    for _, key in ipairs({ "met", "npcs", "quests", "training", "dungeons", "taxi", "crossings" }) do Table(db, key) end
    for _, key in ipairs({ "items", "vendors", "reactions", "pending" }) do Table(Table(db, "vendorPrices"), key) end
    Table(Table(db, "travel"), "chars")
    D.SeedSeen(db)
    D.world = db
    -- one failing learner does not keep the others from starting
    for _, fn in ipairs(loaded) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Data\Seen.lua ships what the author's game learned and counts as seen, before the 1.12 data.
-- At load its facts missing from your saved data are copied in, so readers and learners use one table;
-- at logout unchanged copies are removed again (your file keeps only what you saw yourself).
local SEEN_LISTS = { "npcs", "met", "quests", "training", "dungeons", "crossings" }
local copies = {} -- list -> key -> the shipped value the copy was made from (never changed)

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function D.SeedSeen(db)
    local seen = D.seen
    if not seen then return end
    for _, name in ipairs(SEEN_LISTS) do
        local mine, theirs = db[name], seen[name]
        if mine and theirs then
            local put = {}
            for key, value in pairs(theirs) do
                if mine[key] == nil then
                    mine[key] = Copy(value)
                    put[key] = value
                end
            end
            copies[name] = put
        end
    end
    D.seen = nil -- in your saved data now
end

D.On("PLAYER_LOGOUT", function()
    local db = D.world
    if not db then return end
    for name, put in pairs(copies) do
        local mine = db[name]
        for key, shipped in pairs(put) do
            if mine[key] ~= nil and Same(mine[key], shipped) then mine[key] = nil end
        end
    end
end)
