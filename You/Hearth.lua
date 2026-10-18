local _, D = ...
if D.off then return end

-- Travel facts per character in PylosCompassWorldDB.travel.chars["Name-Realm"]:
--   mount      last seen mount run speed, yards/s (GetUnitSpeed while mounted)
--   hearth     bind place (uiMapID * 1000000 + x * 1000 + y), taken where you stand on HEARTHSTONE_BOUND
--   hearthName inn name (GetBindLocation); if it differs now, hearth is unused
-- D.Hearth(): place and HEARTH minutes if the stone is in your bags and off cooldown, else nil.
-- HEARTH is rough: 10 s cast (spell 8690) plus loading.

local HEARTHSTONE = 6948
local HEARTH = 0.5 -- minutes

local function Mine()
    local db, key = D.world, D.CharacterKey()
    if not db or not key then return nil end
    db.travel.chars[key] = db.travel.chars[key] or {}
    return db.travel.chars[key]
end

-- Mount speed (yards/s), nil if never seen
function D.MountSpeed()
    local mine = Mine()
    return mine and mine.mount
end

function D.Hearth()
    local mine = Mine()
    if not mine or not mine.hearth then return nil end
    if (GetBindLocation and GetBindLocation()) ~= mine.hearthName then return nil end
    if not (C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE) > 0) then return nil end
    local start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
    if start and start > 0 and start + (duration or 0) > GetTime() then return nil end
    return mine.hearth, HEARTH
end

local function Ride()
    if not (IsMounted and IsMounted() and GetUnitSpeed) then return end
    local _, run = GetUnitSpeed("player")
    local mine = Mine()
    if mine and not D.Secret(run) and run and run > D.RUN_SPEED and mine.mount ~= run then
        mine.mount = run
        D.BumpState("travel")
    end
end

-- Not recorded in instances
D.On("HEARTHSTONE_BOUND", function()
    local mine = Mine()
    if not mine or IsInInstance() then return end
    local place = D.PlayerPlace(C_Map.GetBestMapForUnit("player"))
    if place then mine.hearth, mine.hearthName = place, GetBindLocation and GetBindLocation() or nil end
end)
D.On("PLAYER_MOUNT_DISPLAY_CHANGED", function()
    if D.world then C_Timer.After(1, Ride) end -- speed follows a moment after mounting
end)
