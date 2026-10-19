local _, D = ...

-- D.PlayerZone(inInstances): your zone (uiMapID), the best map climbed up to its zone. In a cave or at a dungeon
-- entrance the game names only the continent, so the zone text is matched against the continent's zones.
-- In an instance: nil unless inInstances is set.
-- Cached until the state "zone" changes (called per name plate; the climb allocates tables).
local function Find()
    local zone, info = D.MapUp(C_Map.GetBestMapForUnit("player"), 3)
    if zone then return zone end
    if info and info.mapType == 2 then
        local name = GetRealZoneText()
        for _, child in ipairs(C_Map.GetMapChildrenInfo(info.mapID, Enum.UIMapType.Zone) or {}) do
            if child.name == name then return child.mapID end
        end
    end
    return nil
end

local zone, zoneVersion -- cached zone (false: none) and the "zone" version it was found at
function D.PlayerZone(inInstances)
    local version = D.State("zone")
    if zoneVersion ~= version then
        zoneVersion = version
        zone = Find() or false
    end
    if not inInstances and IsInInstance() then return nil end
    return zone or nil
end
