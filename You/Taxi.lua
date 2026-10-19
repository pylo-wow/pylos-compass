local _, D = ...

-- Known flight points, learned at the flight master: C_TaxiMap.GetTaxiNodesForMap reports all nodes
-- as known (confirmed in game), so use GetAllTaxiNodes(uiMapID) there: state 0 (current) and
-- 1 (reachable) count as known (Enum.FlightPathState; 2 = unreachable).
-- Stored per character in PylosCompassWorldDB.taxi["Name-Realm"] = { nodeID = true }; never forgotten.
-- A newly learned node bumps the state "travel".
-- Unchecked: whether "unreachable" in Forever also covers known nodes without a route (left out then).

local function Known()
    local db, key = D.world, D.CharacterKey()
    if not db or not key then return nil end
    db.taxi[key] = db.taxi[key] or {}
    return db.taxi[key]
end

-- Is the flight point (TaxiNodes ID) known?
function D.TaxiKnown(nodeID)
    local known = Known()
    return known ~= nil and known[nodeID] == true
end

-- The flight map shows the continent you are on
D.On("TAXIMAP_OPENED", function()
    local known = Known()
    local mapID = D.MapUp(C_Map.GetBestMapForUnit("player"), 2)
    if not known or not mapID then return end
    local learned = false
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
        local id, state = node.nodeID, node.state
        if not D.Secret(id) and not D.Secret(state) and id and (state == 0 or state == 1) and not known[id] then
            known[id], learned = true, true
        end
    end
    if learned then D.BumpState("travel") end
end)
