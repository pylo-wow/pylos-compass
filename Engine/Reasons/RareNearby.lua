local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Rare nearby (doing): a rare NPC (rare or rare elite) came up near you, its name plate showed or you pointed at it: a
-- chance to take its loot while it is there. Strongest right after it was seen, fading to nothing within FRESH; a dead
-- one is left out. What the game keeps secret from addons (in instances) is passed over.

local FRESH = 3 * 60 -- seconds a rare counts after it was seen
local seen = {}      -- NPC ID -> time() it was seen last

local function Look(unit)
    if not unit or not UnitExists(unit) then return end
    local class = UnitClassification(unit)
    if issecretvalue and issecretvalue(class) then return end
    if class ~= "rare" and class ~= "rareelite" then return end
    local npcID = D.NPCOf(unit)
    if not npcID then return end
    -- (its corpse targeted or pointed at: killed, no chance left)
    if UnitIsDeadOrGhost(unit) then
        if not seen[npcID] then return end
        seen[npcID] = nil
    else
        seen[npcID] = time()
    end
    D.BumpState("rec:rare")
end
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Look(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() Look("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Look("mouseover") end)

-- how fresh: 1 right after it was seen, 0 after FRESH; nil if not seen
local function Freshness(npcID)
    local at = seen[npcID]
    if not at then return nil end
    local share = 1 - (time() - at) / FRESH
    if share <= 0 then
        seen[npcID] = nil
        return nil
    end
    return share
end

-- the rares seen lately, alive: NPC ID -> time() seen last (the nudges, Pushes.lua; do not change it)
function ns.RaresSeen()
    for npcID in pairs(seen) do Freshness(npcID) end -- (the stale ones go)
    return seen
end

ns.RegisterReason({
    key = "rareNearby",
    -- weight 1.4 (the heaviest of its stage): a rare is gone soon; not learned from (killing it leaves no sure sign)
    stage = "opportunity", weight = 1.4, label = "Rare nearby", learn = false,
    sources = { "npcs" },
    depends = { "rec:rare", "npcs" }, -- (fading with time: kept at most STALE seconds, Reasons.lua)
    candidates = function(add)
        for npcID in pairs(seen) do add(D.NPCByID(npcID)) end
    end,
    test = function(entry)
        local share = Freshness(entry.npcID)
        return share and (0.4 + 0.6 * share) or nil
    end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["Rare nearby"] end,
})
