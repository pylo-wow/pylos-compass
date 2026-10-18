local _, D = ...
if D.off then return end

-- Routes: minutes to get somewhere by the way you would really go. A route planner over the
-- game's travel net and the walkable crossings between zones:
--   on foot      within a zone the straight line between world positions
--                (C_Map.GetWorldPosFromMapPos) x DETOUR at your speed (D.YardsMinutes,
--                Core\Map.lua); into another zone only through its crossings (Data\Paths.lua,
--                Carbonite's), since straight lines run through mountains and over the sea
--   portals      the same, instant
--   hearthstone  to your inn when the stone is ready, about half a minute (You\Hearth.lua: D.Hearth)
--   flights      only between known flight points (You\Taxi.lua); the path's flown length
--                (Data\TravelNet.lua) at FLIGHT_SPEED (take-off and landing included); a flight on
--                from a flight saves the yards the second one joins early (D.taxiTransitions, else
--                the hub's D.taxiHubSavings: vmangos' taxi_path_transitions, checked against
--                Leatrix' measured flights); FLIGHT_START once per journey
--   transports   boats, zeppelins, ferries and the Deeprun Tram: mean wait at a stop
--                (Data\TravelNet.lua: half a round, a quarter for the tram's two trains), then the
--                rides to your stop (server path model incl. acceleration and braking), docks in
--                between; only your faction's (D.transportSides)
-- One search from where you are to every point of the net (kept while you stay near), then for
-- each destination the best of the points in its zone.
-- D.TravelMinutes: minutes; nil where it cannot be told (instance, no position), false where no way
-- is known (another continent without a transport, an island without a crossing).
-- A point's zone: crossings name theirs; flight points and transport stops have theirs in
-- Data\Paths.lua (by name, by Carbonite's connections); else asked of the client once
-- (C_Map.GetMapPosFromWorldPos + GetMapInfoAtPosition; unchecked in game for a dock in the
-- water); a point with no zone may be walked to from anywhere on its continent.
-- Constants (walking RUN and DETOUR: Core\Map.lua):
--   riding 1.6 / 2.0   Forever's MountCapability: +60 % with Riding 75 (spell 33388), +100 % with 150 (33391)
--   FLIGHT_SPEED 30    Leatrix Plus' measured flight times (Leatrix_Plus_Flight_Alliance/Horde.lua,
--                      click to landing) vs these paths' flown lengths: 185 direct flights, median
--                      29.96 yd/s, 90 % within 29.8-30.1 (vmangos says 32)
--   FLIGHT_START 0.25  talking to the flight master: a guess
--   PORTAL 0.2         stepping through a portal: a guess
--   DANGER 2 above +5  walking through a zone whose foes (median level of NPCs hostile to you,
--                      D.ZoneMobLevel) are more than DANGER_LEVELS above yours counts DANGER times;
--                      a judgment, no source; zones have no level in the game data (AreaTable's
--                      ContentTuning is empty for all of them)

local RUN = D.RUN_SPEED
local DANGER, DANGER_LEVELS = 2, 5
local FLIGHT_SPEED = 30
local FLIGHT_START = 0.25  -- minutes
local PORTAL = 0.2         -- minutes
local MOVED = 50           -- yards you move before the search is done again
local KEEP = 10            -- seconds the search is kept at most

local function World(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not continent or not pos or D.Secret(continent) then return nil end
    return continent, pos.x, pos.y
end

local ZoneOf = D.ZoneOfMap

-- A place's world position (continent, x, y), cached per place (places do not move; each
-- query allocates two tables)
local placeContinent, placeX, placeY = {}, {}, {}
local function PlaceWorld(place)
    local continent = placeContinent[place]
    if continent == nil then
        local x, y
        continent, x, y = World(D.PlaceParts(place))
        placeContinent[place], placeX[place], placeY[place] = continent or false, x, y
    end
    if not continent then return nil end
    return continent, placeX[place], placeY[place]
end

local function ZoneAt(continent, x, y)
    if not (C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfoAtPosition and CreateVector2D) then return nil end
    local top, pos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y))
    local info = top and pos and C_Map.GetMapInfoAtPosition(top, pos.x, pos.y)
    return info and ZoneOf(info.mapID)
end

-- Your world position and zone this frame: continent, x, y, zone; nil where unknown
local youCache = D.Cache({ "frame" }) -- [1..4]: continent, x, y, zone; .none: unknown
local function You()
    local you, renewed = youCache.Get()
    if renewed then
        you.none = true
        local mapID = not IsInInstance() and C_Map.GetBestMapForUnit("player")
        local pos = not D.Secret(mapID) and mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local px, py
        if pos then px, py = D.PositionXY(pos) end
        local continent, x, y
        if px then continent, x, y = World(mapID, px, py) end
        if continent then you[1], you[2], you[3], you[4], you.none = continent, x, y, D.PlayerZone(), nil end
    end
    if you.none then return nil end
    return you[1], you[2], you[3], you[4]
end

-- Your speed in yards/second: your mount's now if mounted, else your riding skill's (you
-- would mount for a long way)
local function Speed()
    if IsMounted and IsMounted() and GetUnitSpeed then
        local _, run = GetUnitSpeed("player")
        if not D.Secret(run) and run and run > RUN then return run end
    end
    local riding = IsPlayerSpell and (IsPlayerSpell(33391) and 2 or IsPlayerSpell(33388) and 1.6)
    if not riding then return RUN end
    -- mount speed as seen (You\Hearth.lua), else the riding skill's
    return D.MountSpeed and D.MountSpeed() or RUN * riding
end

local function Side()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Alliance" and 2 or faction == "Horde" and 4 or 6
end

local function Walk(ax, ay, bx, by, speed)
    return D.YardsMinutes(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2), speed)
end

-- Walking cost factor for a zone: DANGER where its foes are far above your level, else 1
-- (cached per level and NPC build)
local dangerCache = D.Cache({ "level", "data:npcs" }) -- zone -> factor
local function Danger(zone)
    if not zone or not D.Built("npcs") then return 1 end
    local dangers = dangerCache.Get()
    local danger = dangers[zone]
    if not danger then
        local foes = D.ZoneMobLevel(zone)
        danger = (foes and foes > UnitLevel("player") + DANGER_LEVELS) and DANGER or 1
        dangers[zone] = danger
    end
    return danger
end

local function Walkable(a, b)
    return a[1] == b[1] and (a.zone == nil or b.zone == nil or a.zone == b.zone)
end

-- Yards saved by flying on over a hub (from, over, to: taxi node IDs): the D.taxiTransitions
-- row, else the hub's median, else 0. Rows are keyed by one number (node IDs are below 8192), built once.
local transitions
local function Saved(from, over, to)
    if not transitions then
        transitions = {}
        local rows = D.taxiTransitions or {}
        for i = 1, #rows, 4 do
            transitions[(rows[i] * 8192 + rows[i + 1]) * 8192 + rows[i + 2]] = rows[i + 3]
        end
    end
    return transitions[(from * 8192 + over) * 8192 + to] or (D.taxiHubSavings and D.taxiHubSavings[over]) or 0
end

-- The net's points: { continent, x, y, zone = uiMapID or nil, kind, edges =
-- { { to, minutes or false (walked: computed from your speed), label, side, yards } } }
-- byArea: continent -> zone (0: none known) -> points, and .all -> its points
local points, built, byArea
local function Build()
    points = {}
    local byNode = {}
    local function Point(continent, x, y, zone, kind)
        local point = { continent, x, y, zone = zone, kind = kind, edges = {} }
        points[#points + 1] = point
        return point
    end
    for nodeID, node in pairs(D.taxiNodes or {}) do
        local zone = D.nodeZones and D.nodeZones[nodeID] or ZoneAt(node[1], node[2], node[3])
        local point = Point(node[1], node[2], node[3], zone, "taxi")
        point.node, point.name = nodeID, node[4]
        byNode[nodeID] = point
    end
    local paths = D.taxiPaths or {}
    for i = 1, #paths, 4 do
        local from, to = byNode[paths[i]], byNode[paths[i + 1]]
        if from and to then
            table.insert(from.edges, { to = to, minutes = paths[i + 2] / FLIGHT_SPEED / 60,
                label = "flight to " .. (to.name:match("^([^,]+)") or to.name), flight = true })
        end
    end
    for _, transport in ipairs(D.transports or {}) do
        local side = D.transportSides and D.transportSides[transport.name] or 6
        local function Dock(i) return transport.docks and transport.docks[i] or transport.dock or 0 end
        local function Leg(i) return transport.seconds[i] or 0 end
        local list, round = {}, 0
        local zones = D.stopZones and D.stopZones[transport.name]
        for i, s in ipairs(transport.stops) do
            list[i] = Point(s[1], s[2], s[3], zones and zones[i] or ZoneAt(s[1], s[2], s[3]), "transport")
            round = round + Leg(i) + Dock(i)
        end
        -- from each stop to every other: the wait, the legs between, the docks on the way
        local wait = transport.wait or round / 2
        for i, from in ipairs(list) do
            local ride, j = 0, i
            for _ = 1, #list - 1 do
                ride = ride + Leg(j)
                j = j % #list + 1
                table.insert(from.edges, { to = list[j], minutes = (wait + ride) / 60, label = transport.name, side = side })
                ride = ride + Dock(j)
            end
        end
    end
    -- crossings between zones: a point on each side, walked or stepped through (one way only
    -- where the flags say so); the data's, then those learned in play (World\LearnCrossings.lua, same layout)
    local crossings = {}
    for _, list in ipairs({ D.zonePaths or {}, D.learnedPaths or {} }) do
        for i = 1, #list do crossings[#crossings + 1] = list[i] end
    end
    for i = 1, #crossings, 10 do
        local a = Point(crossings[i + 1], crossings[i + 2], crossings[i + 3], crossings[i], "crossing")
        local b = Point(crossings[i + 5], crossings[i + 6], crossings[i + 7], crossings[i + 4], "crossing")
        local flags, portal = crossings[i + 8], crossings[i + 9] == 0
        local side = bit.band(flags, 6)
        local yards = math.sqrt((b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        local function Edge(from, to)
            local edge = { to = to, side = side }
            if portal then edge.minutes = PORTAL else edge.minutes, edge.yards = false, yards end
            table.insert(from.edges, edge)
        end
        Edge(a, b)
        if bit.band(flags, 1) == 1 then Edge(b, a) end
    end
    -- precompute the points each one may walk to (asking Walkable of every pair each round was costly)
    for _, point in ipairs(points) do
        local near = {}
        for _, other in ipairs(points) do
            if other ~= point and Walkable(point, other) then near[#near + 1] = other end
        end
        point.near = near
    end
    -- points a place may be walked to from, by continent and zone (0: points of no known zone);
    -- avoids walking all reached points per place (D.TravelMinutes)
    byArea = {}
    for _, point in ipairs(points) do
        local continent = byArea[point[1]] or { all = {} }
        byArea[point[1]] = continent
        local zone = point.zone or 0
        continent[zone] = continent[zone] or {}
        table.insert(continent[zone], point)
        table.insert(continent.all, point)
    end
    built = true
end

-- The search from you: minutes to each point and the rides on the way. answers: place ->
-- { minutes, overseas, words } or false, until the next search (rough is enough: the same
-- answer while you stay within MOVED yards; recomputing per NPC took half a refresh). Per point
-- only the previous point and edge are kept (via, viaEdge) and the rides are assembled for a
-- place answered (copying the ride list per better way produced most of the garbage).
local reached, via, viaEdge, searchedAt, from, answers
local hearthPoint -- your hearthstone's inn in this search, if ready (not one of the net's points)

-- Rides on the way to a point as words: "flight to Lakeshire, Redridge", a transport's name;
-- consecutive flights merge into one (to the last); nil if none
local function Rides(point)
    local edges, root = {}, point
    while point do
        local edge = viaEdge[point]
        if edge and edge.label then edges[#edges + 1] = edge end
        root, point = point, via[point]
    end
    local names, lastFlight = {}, false
    if root.kind == "hearth" then names[1] = "Hearthstone" end
    for i = #edges, 1, -1 do
        local edge = edges[i]
        if lastFlight and edge.flight then names[#names] = edge.label else names[#names + 1] = edge.label end
        lastFlight = edge.flight
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

local searchSpeed -- your speed at the search, reused for the last leg to each place
local function Search(continent, x, y, zone)
    local now = GetTime()
    local hearth, hearthMinutes = nil, nil
    if D.Hearth then hearth, hearthMinutes = D.Hearth() end
    -- state "travel": a flight point learned, your mount's speed seen
    local travel = D.State("travel")
    if from and from[1] == continent and (from[2] - x) ^ 2 + (from[3] - y) ^ 2 < MOVED * MOVED
        and now - searchedAt < KEEP and travel == from[4] and hearth == from[5] then
        return
    end
    if not built then Build() end
    from, searchedAt = { continent, x, y, travel, hearth }, now
    reached, via, viaEdge, answers, hearthPoint = {}, {}, {}, {}, nil
    local speed, side = Speed(), Side()
    searchSpeed = speed
    local known = D.TaxiKnown
    local function Usable(point) return point.kind ~= "taxi" or (known and known(point.node)) end
    local start = { continent, x, y, zone = zone }
    local open = {}
    for _, point in ipairs(points) do
        if Usable(point) and Walkable(start, point) then
            reached[point] = Walk(x, y, point[2], point[3], speed) * Danger(zone or point.zone)
            open[#open + 1] = point
        end
    end
    -- your hearthstone, if ready: its inn after cast and loading (You\Hearth.lua)
    if hearth then
        local mapID = D.PlaceParts(hearth)
        local c, hx, hy = World(D.PlaceParts(hearth))
        if c then
            local point = { c, hx, hy, zone = ZoneOf(mapID), kind = "hearth", edges = {} }
            reached[point] = hearthMinutes -- its rides begin with "Hearthstone" (see Rides)
            open[#open + 1] = point
            hearthPoint = point
        end
    end
    -- Dijkstra over the few hundred points: the nearest open one each round
    local done = {}
    local best
    local function Reach(to, minutes, edge)
        if done[to] or not Usable(to) then return end
        local total = reached[best] + minutes
        if not reached[to] or total < reached[to] then
            if not reached[to] then open[#open + 1] = to end
            reached[to] = total
            via[to], viaEdge[to] = best, edge
        end
    end
    while true do
        local bestIndex
        best = nil
        for i, point in ipairs(open) do
            if not done[point] and (not best or reached[point] < reached[best]) then best, bestIndex = point, i end
        end
        if not best then break end
        done[best] = true
        table.remove(open, bestIndex)
        for _, edge in ipairs(best.edges) do
            if not edge.side or bit.band(edge.side, side) ~= 0 then
                local minutes = edge.minutes or (D.YardsMinutes(edge.yards, speed) * Danger(edge.to.zone))
                -- flight master once per journey: a flight on from a flight is booked with it
                -- (one ride over several hops) and joins the next path early
                if edge.flight then
                    if viaEdge[best] and viaEdge[best].flight then
                        minutes = math.max(0, minutes - Saved(via[best].node, best.node, edge.to.node) / FLIGHT_SPEED / 60)
                    else
                        minutes = minutes + FLIGHT_START
                    end
                end
                Reach(edge.to, minutes, edge)
            end
        end
        -- on foot to the other points of this zone (landing, walking to a dock)
        if best.near then
            for _, other in ipairs(best.near) do
                Reach(other, Walk(best[2], best[3], other[2], other[3], speed) * Danger(best.zone or other.zone))
            end
        else -- your hearthstone's inn is not one of the net's points
            for _, other in ipairs(points) do
                if other ~= best and Walkable(best, other) then
                    Reach(other, Walk(best[2], best[3], other[2], other[3], speed) * Danger(best.zone or other.zone))
                end
            end
        end
    end
end

-- The net changed (a crossing learned): rebuilt at the next search
function D.RoutesChanged()
    built, from = false, nil
end

function D.ZonePlace(zoneID)
    return D.Place(zoneID, 0.5, 0.5)
end

local function Nearest(list, tx, ty, speed, danger, best, bestPoint)
    if not list then return best, bestPoint end
    for i = 1, #list do
        local point = list[i]
        local minutes = reached[point]
        if minutes then
            local total = minutes + Walk(point[2], point[3], tx, ty, speed) * danger
            if not best or total < best then best, bestPoint = total, point end
        end
    end
    return best, bestPoint
end

-- Minutes from you to a place (uiMapID * 1000000 + x * 1000 + y); true if the way crosses to
-- another continent; the rides as words ("Deeprun Tram, Menethil Harbor - Theramore"; nil on
-- foot). Nil if it cannot be told, false if no way is known.
function D.TravelMinutes(place)
    if not place then return nil end
    local continent, x, y, zone = You()
    if not continent then return nil end
    Search(continent, x, y, zone)
    local known = answers[place]
    if known ~= nil then
        if not known then return false end
        return known[1], known[2], known[3]
    end
    local there, tx, ty = PlaceWorld(place)
    if not there then return nil end
    local targetZone = ZoneOf((D.PlaceParts(place)))
    local speed = searchSpeed
    local danger = Danger(targetZone)
    local best, bestPoint
    if continent == there and (zone == nil or targetZone == nil or zone == targetZone) then
        best = Walk(x, y, tx, ty, speed) * danger
    end
    -- reached points that may walk there: on its continent, in its zone or of no known zone
    -- (all of them if its zone is unknown), plus your hearthstone's inn
    local area = byArea[there]
    if area then
        if targetZone == nil then
            best, bestPoint = Nearest(area.all, tx, ty, speed, danger, best, bestPoint)
        else
            best, bestPoint = Nearest(area[targetZone], tx, ty, speed, danger, best, bestPoint)
            best, bestPoint = Nearest(area[0], tx, ty, speed, danger, best, bestPoint)
        end
    end
    local inn = hearthPoint
    if inn and inn[1] == there and (inn.zone == nil or targetZone == nil or inn.zone == targetZone) then
        local total = reached[inn] + Walk(inn[2], inn[3], tx, ty, speed) * danger
        if not best or total < best then best, bestPoint = total, inn end
    end
    if not best then
        answers[place] = false
        return false
    end
    local words = bestPoint and Rides(bestPoint)
    answers[place] = { best, there ~= continent, words }
    return best, there ~= continent, words
end
