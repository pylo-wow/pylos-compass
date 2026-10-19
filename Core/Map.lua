local _, D = ...

-- Places, maps and small shared helpers.
--   D.Place(mapID, x, y)    uiMapID * 1000000 + x * 1000 + y, x and y the map's 0..1 in thousandths; nil off the map
--   D.PlaceParts(place)     uiMapID, x, y (0..1)
--   D.PlaceDistance(place)  yards from you to a place
--   D.PlaceGap(a, b)        yards between two places on the same map
--   D.PlayerPlace(mapID)    your place on a map (default: your zone's)
--   D.PositionXY(pos)       x, y of a client position; nil if secret
--   D.MapUp(mapID, mapType) the map of a type (3 zone, 2 continent) a map lies in, climbing up from a district or cave
--   D.ZoneOfMap(mapID)      the zone a map lies in (cached)
--   D.Decay(value, seconds, halfLife)  value after seconds, halving every halfLife seconds
--   D.YardsMinutes(yards, speed)  minutes to walk that far (straight line * DETOUR), at RUN speed unless one is given
-- Walking numbers: RUN 7 yd/s (vmangos baseMoveSpeed; GetUnitSpeed("player") in game); DETOUR 1.3 is a guess
-- (nothing measures foot paths, and walked times must not be learned: the player can skew them).

local RUN, DETOUR = 7, 1.3
D.RUN_SPEED = RUN -- (World\Routes.lua, You\Hearth.lua: faster than this is riding)

local Secret = D.Secret

-- Places

function D.Place(mapID, x, y)
    if not mapID or not x or not y or Secret(mapID) or Secret(x) or Secret(y) then return nil end
    x, y = math.floor(x * 1000), math.floor(y * 1000)
    if x < 0 or x > 999 or y < 0 or y > 999 then return nil end
    return mapID * 1000000 + x * 1000 + y
end

function D.PlaceParts(place)
    return math.floor(place / 1000000), math.floor(place / 1000) % 1000 / 1000, place % 1000 / 1000
end

-- your place on a map (default: your zone's); nil where the client tells none (instances, another continent)
function D.PlayerPlace(mapID)
    mapID = mapID or D.PlayerZone(true)
    if not mapID or Secret(mapID) then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    return D.Place(mapID, D.PositionXY(pos))
end

-- x, y of a client position (a vector; a { x, y } pair also works); nil if none or secret (hence not "pos.x or pos[1]")
function D.PositionXY(pos)
    local x, y = pos.x, pos.y
    if Secret(x) or Secret(y) then return nil end
    if x == nil then x, y = pos[1], pos[2] end
    if Secret(x) or Secret(y) or x == nil or y == nil then return nil end
    return x, y
end

-- Distances
-- Yards from you to a place: its spot on its map vs. yours there, with the map's size from the client
-- (C_Map.GetMapWorldSize, else the corners' world positions); nil if you are not on that map or no size is known.
local mapSizes = {} -- uiMapID -> { width, height } or false
local function MapSize(mapID)
    local size = mapSizes[mapID]
    if size ~= nil then return size end
    size = false
    local width, height = C_Map.GetMapWorldSize(mapID)
    if width and width > 0 and height and height > 0 then size = { width, height } end
    if not size then
        local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if a and b then
            width, height = math.abs(a.y - b.y), math.abs(a.x - b.x)
            if width > 0 and height > 0 then size = { width, height } end
        end
    end
    mapSizes[mapID] = size
    return size
end

-- your position per map asked, this frame: uiMapID -> client position or false
local here = D.Cache({ "frame" })
function D.PlaceDistance(place)
    if not place then return nil end
    local mapID, x, y = D.PlaceParts(place)
    local positions = here.Get()
    local pos = positions[mapID]
    if pos == nil then
        pos = C_Map.GetPlayerMapPosition(mapID, "player") or false
        positions[mapID] = pos
    end
    local size = pos and MapSize(mapID)
    if not size then return nil end
    local px, py = D.PositionXY(pos)
    if not px then return nil end
    local dx, dy = (px - x) * size[1], (py - y) * size[2]
    return math.sqrt(dx * dx + dy * dy)
end

function D.PlaceGap(a, b)
    if not a or not b then return nil end
    local mapID, ax, ay = D.PlaceParts(a)
    local other, bx, by = D.PlaceParts(b)
    if other ~= mapID then return nil end
    local size = MapSize(mapID)
    if not size then return nil end
    local dx, dy = (ax - bx) * size[1], (ay - by) * size[2]
    return math.sqrt(dx * dx + dy * dy)
end

-- Maps

-- the map of that type a map lies in (nil if none), and the map info where the climb stopped (You\Zone.lua)
function D.MapUp(mapID, mapType)
    if not mapID or Secret(mapID) then return nil end
    local info = C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType > mapType and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info and info.mapType == mapType and info.mapID or nil, info
end

-- cached: the route planner asks it for every place
local zoneOfMap = {} -- mapID -> zone or false
function D.ZoneOfMap(mapID)
    if not mapID then return nil end
    local zone = zoneOfMap[mapID]
    if zone == nil then
        zone = D.MapUp(mapID, 3) or false
        zoneOfMap[mapID] = zone
    end
    return zone or nil
end

-- Other helpers

local character
function D.CharacterKey()
    if not character then
        local name, realm = UnitName("player"), GetRealmName()
        if not name or not realm then return nil end
        character = name .. "-" .. realm
    end
    return character
end

function D.ItemIDFromLink(link)
    if not link or Secret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function D.Decay(value, seconds, halfLife)
    return value * 0.5 ^ (math.max(seconds, 0) / halfLife)
end

function D.YardsMinutes(yards, speed)
    return yards * DETOUR / (speed or RUN) / 60
end
