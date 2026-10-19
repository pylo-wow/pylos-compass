local _, D = ...

-- Zone crossings learned while walking; Data\Paths.lua misses some and the route planner
-- (World\Routes.lua) enters another zone only through a crossing. Every EVERY seconds the
-- world position and zone are read; if the zone changed on the same continent and you moved
-- at most NEAR yards (not a flight, loading screen, portal or teleport), the two spots are a
-- crossing. Not in instances. A crossing within WITHIN yards of a known one between the same
-- zones (either direction) is not stored again.
-- PylosCompassWorldDB.crossings["zoneA>zoneB@x,y"] = { continent, ax, ay, bx, by }
-- (world yards; key x, y = zone A's spot in steps of WITHIN yards). Added to D.learnedPaths in
-- Data\Paths.lua's layout (groups of 10) as two-way, both factions (flags 7), on foot.

local EVERY = 1     -- seconds between readings
local NEAR = 60     -- yards moved at most between two readings (a fast mount: about 20)
local WITHIN = 150  -- yards: a crossing this near one known is the same

D.learnedPaths = {}

local function Add(a, b, c)
    local list = D.learnedPaths
    for _, v in ipairs({ a, c[1], c[2], c[3], b, c[1], c[4], c[5], 7, 1 }) do list[#list + 1] = v end
end

local function Zones(key)
    local a, b = key:match("^(%d+)>(%d+)@")
    return tonumber(a), tonumber(b)
end

local function Known(continent, a, b, x, y)
    for _, list in ipairs({ D.zonePaths or {}, D.learnedPaths }) do
        for i = 1, #list, 10 do
            local za, zb = list[i], list[i + 4]
            if ((za == a and zb == b) or (za == b and zb == a)) and list[i + 1] == continent then
                local px, py = list[i + 2], list[i + 3]
                if za == b then px, py = list[i + 6], list[i + 7] end
                if (px - x) ^ 2 + (py - y) ^ 2 < WITHIN * WITHIN then return true end
            end
        end
    end
    return false
end

D.OnLoaded(function()
    D.world.crossings = D.world.crossings or {}
    for key, c in pairs(D.world.crossings) do
        local a, b = Zones(key)
        if a then Add(a, b, c) end
    end
end)

-- Returns continent, world x, y, zone; nil where unknown
local function Here()
    if IsInInstance() or (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if D.Secret(mapID) or not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos then x, y = D.PositionXY(pos) end
    if not x or not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    local zone = D.PlayerZone()
    if D.Secret(continent) or not continent or not world or not zone then return nil end
    return continent, world.x, world.y, zone
end

local last -- the last reading: { continent, x, y, zone }

local function Read()
    if not D.world or InCombatLockdown() then last = nil return end
    local continent, x, y, zone = Here()
    if not continent then last = nil return end
    local before = last
    last = { continent, x, y, zone }
    if not before or before[4] == zone or before[1] ~= continent then return end
    if (before[2] - x) ^ 2 + (before[3] - y) ^ 2 > NEAR * NEAR then return end
    local a, b = before[4], zone
    if Known(continent, a, b, before[2], before[3]) then return end
    local key = ("%d>%d@%d,%d"):format(a, b, math.floor(before[2] / WITHIN), math.floor(before[3] / WITHIN))
    local c = { continent, math.floor(before[2] * 10 + 0.5) / 10, math.floor(before[3] * 10 + 0.5) / 10,
        math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10 }
    D.world.crossings[key] = c
    Add(a, b, c)
    if D.RoutesChanged then D.RoutesChanged() end
    D.BumpState("travel")
end

-- A loading screen between two readings is no crossing
D.On("PLAYER_ENTERING_WORLD", function() last = nil end)
D.OnLoaded(function() C_Timer.NewTicker(EVERY, Read) end)
