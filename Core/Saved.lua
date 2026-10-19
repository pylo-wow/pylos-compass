local addonName, D = ...
if D.off then return end

-- PylosCompassWorldDB: everything learned in the game, kept only on your computer.
--   met           zone an NPC was met in (World\LearnNPCs.lua)
--   vendorPrices  prices without discount where the data is wrong or missing, and each vendor's discount (World\Prices.lua)
--   npcs          NPCs seen while playing (World\LearnNPCs.lua), incl. the spells a trainer lists (LearnTrainers.lua)
--   training      what a trainer's service asks: level, skill, cost (World\LearnTrainers.lua)
--   quests        who gives and who takes each quest (World\LearnQuests.lua)
--   dungeons      dungeon entrances seen (World\Dungeons.lua)
--   crossings     walked crossings between zones (World\LearnCrossings.lua)
--   taxi          flight points each character knows (You\Taxi.lua)
--   travel        chars = each character's mount speed and hearthstone place (You\Hearth.lua)
-- Set up at addon load; then the learning files put their data into the data tables (D.OnLoaded).

local loaded = {} -- functions to call once PylosCompassWorldDB is set up
function D.OnLoaded(fn) loaded[#loaded + 1] = fn end

D.On("ADDON_LOADED", function(_, name)
    if name ~= addonName or D.world then return end
    PylosCompassWorldDB = PylosCompassWorldDB or {}
    local db = PylosCompassWorldDB
    db.version = db.version or 1
    db.met = db.met or {}
    db.vendorPrices = db.vendorPrices or {}
    for _, key in ipairs({ "items", "vendors", "reactions", "pending" }) do
        db.vendorPrices[key] = db.vendorPrices[key] or {}
    end
    -- obsolete: prices now come without discount from Data\ItemPrices.lua
    db.prices = nil
    db.npcs = db.npcs or {}
    db.quests = db.quests or {}
    db.training = db.training or {}
    db.dungeons = db.dungeons or {}
    db.taxi = db.taxi or {}
    db.travel = db.travel or {}
    db.travel.chars = db.travel.chars or {}
    -- "seen" was never read: drop it, also from older saved data
    for _, list in ipairs({ db.npcs, db.quests }) do
        for _, learned in pairs(list) do
            if type(learned) == "table" then learned.seen = nil end
        end
    end
    db.crossings = db.crossings or {}
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
local copies = {} -- list -> key -> the copy's text as put in

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

-- a value as text, its keys sorted (to tell a copy changed)
local function Text(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i, k in ipairs(keys) do keys[i] = tostring(k) .. "=" .. Text(value[k]) end
    return "{" .. table.concat(keys, ",") .. "}"
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
                    put[key] = Text(value)
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
        for key, text in pairs(put) do
            if mine[key] ~= nil and Text(mine[key]) == text then mine[key] = nil end
        end
    end
end)
