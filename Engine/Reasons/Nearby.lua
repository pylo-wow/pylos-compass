local _, D = ...
local ns = D.engine
local L = ns.L

-- Nearby (knowing): what is around you, lightly so that real reasons stand above: NPCs whose name plates show, NPCs
-- with a role (vendor, repairer, ...) whose spot lies within NEAR yards, a dungeon entrance within NEAR_ENTRANCE
-- yards. Always below every other reason (at most SCALE, the lightest weight: below a fading lookup); nearer is a
-- little stronger.

local NEAR, NEAR_ENTRANCE = 80, 300 -- yards
local SCALE = 0.06 -- a repeated lookup starts at 0.08 (LookedUp.lua)
local PLATE = 0.6 -- a name plate's share of SCALE (no distance known)

local plates = {} -- name plate unit -> NPC ID
local shown = {}  -- NPC ID -> plates showing it

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    local npcID = D.NPCOf(unit)
    if not npcID then return end
    plates[unit] = npcID
    shown[npcID] = (shown[npcID] or 0) + 1
    D.BumpState("rec:nearby")
end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    local npcID = plates[unit]
    if not npcID then return end
    plates[unit] = nil
    shown[npcID] = shown[npcID] > 1 and shown[npcID] - 1 or nil
    D.BumpState("rec:nearby")
end)
-- a new world (a loading screen): no plates left
ns.On("PLAYER_ENTERING_WORLD", function()
    wipe(plates)
    wipe(shown)
end)

-- entry -> strength, worked out again when one of its states changed
local cache = D.Cache({ "rec:nearby", "position", "zone", "npcs", "data" })

local function Closeness(yards, within)
    return yards and yards <= within and SCALE * (0.4 + 0.6 * (1 - yards / within)) or nil
end

local function Near()
    local near, renewed = cache.Get()
    if not renewed then return near end
    for npcID in pairs(shown) do
        local entry = D.NPCByID(npcID)
        if entry then near[entry] = SCALE * PLATE end
    end
    local zone = D.PlayerZone()
    for _, entry in ipairs(zone and D.NPCsInZone(zone) or {}) do
        if entry.roles ~= 0 and entry.reaction ~= 1 then
            local strength = Closeness(D.NPCDistance(entry), NEAR)
            if strength and strength > (near[entry] or 0) then near[entry] = strength end
        end
    end
    for _, entry in ipairs(D.Entries("dungeons")) do
        local strength = entry.place and Closeness(D.PlaceDistance(entry.place), NEAR_ENTRANCE)
        if strength then near[entry] = strength end
    end
    return near
end

ns.RegisterReason({
    key = "nearby",
    -- weight 0.7: the lightest, strength at most SCALE; it only fills in below the real reasons
    stage = "know", weight = 0.7, label = "Nearby",
    learn = false, -- a background hint, not a suggestion to follow
    kind = "know",
    sources = { "npcs", "dungeons" },
    depends = { "rec:nearby", "position", "zone", "npcs", "data" },
    candidates = function(add)
        for entry in pairs(Near()) do add(entry) end
    end,
    test = function(entry) return Near()[entry] end,
    reach = function() return ns.reach.NOW, nil end,
    errand = false,
    note = function() return L["Nearby"] end,
})
