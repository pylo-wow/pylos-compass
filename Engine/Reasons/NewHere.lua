local _, D = ...
local ns = D.engine
local L = ns.L

-- New here (knowing): you just came to a zone this character has never been in: where is the flight master, the inn, a
-- repairer? The useful NPCs of the zone for FRESH after arriving, the nearest of each kind first (one per kind on the
-- start page: one per errand), and the dungeons whose entrance lies in the zone. Zones ever been in are kept per
-- character (PylosCompassEngineDB.seenZones); a character's first look only takes in the zone it stands in.

local FRESH = 15 * 60 -- seconds after arriving
local ROLE = D.NPC_ROLE
-- the kinds worth looking up in a new zone, and how much
local DUNGEON = 0.7 -- a dungeon whose entrance lies in the zone
local KINDS = {
    { ROLE.FLIGHT_MASTER, 1, L["flight master"] },
    { ROLE.INNKEEPER, 0.8, L["innkeeper"] },
    { ROLE.REPAIR, 0.6, L["repairs"] },
    { ROLE.BANKER, 0.5, L["banker"] },
    { ROLE.AUCTIONEER, 0.5, L["auctioneer"] },
}

local arrived = {} -- zone -> time() you came the first time (this session)
local zone        -- your zone; per search

local function Look()
    local db = ns.db
    local here = D.PlayerZone()
    if not db or not here then return end
    local key = ns.Character()
    local first = db.seenZones[key] == nil
    local seen = db.seenZones[key] or {}
    db.seenZones[key] = seen
    if not seen[here] then
        seen[here] = true
        if not first then arrived[here] = time() end
    end
end

-- your zone changed (state, also at entering the world)
D.OnState("zone", Look)

-- the kind of a useful NPC: { role, strength, words }, nil if none
local function Kind(entry)
    for _, kind in ipairs(KINDS) do
        if D.NPCHasRole(entry, kind[1]) then return kind end
    end
    return nil
end

local function New()
    local came = zone and arrived[zone]
    return came ~= nil and time() - came < FRESH
end

ns.RegisterReason({
    key = "newHere",
    -- weight 0.9: where things are in a new zone, a little below what you just looted or target
    stage = "know", weight = 0.9, label = "New zone",
    kind = "know",
    sources = { "npcs", "dungeons" },
    depends = { "zone", "npcs", "data" }, -- (fading with time: kept at most STALE seconds, Reasons.lua)
    -- (the zone looked at here too: the state's listener runs a frame later)
    prepare = function()
        Look()
        zone = D.PlayerZone()
    end,
    candidates = function(add)
        zone = D.PlayerZone()
        if not New() then return end
        for _, entry in ipairs(D.NPCsInZone(zone)) do
            if entry.reaction ~= 1 and Kind(entry) then add(entry) end
        end
        for _, entry in ipairs(D.Entries("dungeons")) do
            if entry.zone == zone then add(entry) end
        end
    end,
    test = function(entry)
        if entry.domain == "dungeons" then return New() and entry.zone == zone and DUNGEON or nil end
        if not New() or entry.reaction == 1 or not D.NPCInZone(entry, zone) then return nil end
        local kind = Kind(entry)
        return kind and kind[2] or nil
    end,
    note = function(entry)
        if entry.domain == "dungeons" then return L["New zone: entrance here"] end
        return L["New zone: %s"]:format(Kind(entry)[3])
    end,
})
