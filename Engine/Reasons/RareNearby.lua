local _, D = ...
local ns = D.engine
local L = ns.L

-- Rare nearby: a rare NPC (rare or rare elite) came up near you, its name plate showed or you pointed at it: a
-- chance to take its loot while it is there. Strongest right after it was seen, fading to nothing within FRESH; a dead
-- one is left out. What the game keeps secret from addons (in instances) is passed over.

local FRESH = 3 * 60 -- seconds a rare counts after it was seen
local seen = {}    -- NPC ID -> time() it was seen last
local MAX = 100    -- more than this many: the faded ones go

local function Look(unit)
    if not unit or not UnitExists(unit) then return end
    local class = UnitClassification(unit)
    if D.Secret(class) then return end
    if class ~= "rare" and class ~= "rareelite" then return end
    local npcID = D.NPCOf(unit)
    if not npcID then return end
    -- its corpse targeted or pointed at: killed, no chance left
    if UnitIsDeadOrGhost(unit) then
        if not seen[npcID] then return end
        seen[npcID] = nil
    else
        local now = time()
        seen[npcID] = now
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        if count > MAX then
            for id, at in pairs(seen) do
                if now - at >= FRESH then seen[id] = nil end
            end
        end
    end
    D.BumpState("rec:rare")
end
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Look(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() Look("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Look("mouseover") end)

-- how fresh: 1 right after it was seen, 0 after FRESH; nil if not seen
local function Freshness(npcID)
    return ns.Fade(seen, npcID, seen[npcID], FRESH)
end

-- the rares seen lately, alive: NPC ID -> time() seen last (for the nudges, Pushes.lua; do not change it)
function ns.RaresSeen()
    for npcID in pairs(seen) do Freshness(npcID) end -- (the stale ones go)
    return seen
end

ns.RegisterReason({
    key = "rareNearby",
    -- weight 1.4: the heaviest of its stage, a rare is gone soon
    stage = "opportunity", weight = 1.4, label = "Rare nearby",
    learn = false, -- killing it leaves no sure sign
    sources = { "npcs" },
    depends = { "rec:rare", "npcs" }, -- fades with time: kept at most STALE seconds (Reasons.lua)
    candidates = function(add)
        for npcID in pairs(seen) do add(D.NPCByID(npcID)) end
    end,
    test = function(entry)
        local share = Freshness(entry.npcID)
        return share and (0.4 + 0.6 * share) or nil
    end,
    reach = function() return ns.reach.NOW, nil end,
    errand = false, -- every rare is its own errand
    note = function() return L["Rare nearby"] end,
})
