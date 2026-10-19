local _, D = ...
if D.off then return end

-- Character facts for valuing items: specialisation (tree with the most points), hit and defense.

-- Tree of a talent node by posX (Forever has one TraitTree per class; the three
-- trees are column groups at posX 1020-2820, 5020-6820, 9080-10880)
local function TreeOf(posX)
    if posX < 4000 then return 1 end
    if posX < 8000 then return 2 end
    return 3
end

-- Points spent per tree: { a, b, c }, nil if the client gives none
local function Points()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then
        return nil
    end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local points = { 0, 0, 0 }
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local node = C_Traits.GetNodeInfo(configID, nodeID)
        local rank = node and (node.activeRank or node.currentRank) or 0
        if rank > 0 and node.posX then
            local tree = TreeOf(node.posX)
            points[tree] = points[tree] + rank
        end
    end
    return points
end

-- Returns class file ("WARRIOR"), tree (1-3) with the most points (nil without points:
-- below level 10 or no talent data), points per tree. Re-read on states "talents"/"spells".
local spec = D.Cache({ "talents", "spells" })
function D.PlayerSpec()
    local known = spec.Get()
    if not known.class then
        local _, class = UnitClass("player")
        local points = Points()
        local tree, most = nil, 0
        for i, n in ipairs(points or {}) do
            if n > most then tree, most = i, n end
        end
        known.class, known.tree, known.points = class, tree, points or { 0, 0, 0 }
    end
    return known.class, known.tree, known.points
end

-- Melee hit %, spell hit % and defense skill (base + bonus) from gear and talents;
-- 0 where the client gives none or the value is secret (in combat in Forever)
local function Number(value)
    if D.Secret(value) or not value then return 0 end
    return value
end
function D.PlayerRatings()
    local hit = Number(GetHitModifier and GetHitModifier())
    local spellHit = Number(GetSpellHitModifier and GetSpellHitModifier())
    local defense = 0
    local defenseSkill = UnitDefenseSkill or UnitDefense -- UnitDefenseSkill is the client's name (UnitDocumentation.lua)
    if defenseSkill then
        local base, bonus = defenseSkill("player")
        defense = Number(base) + Number(bonus)
    end
    return { hit = hit, spellHit = spellHit, defense = defense }
end
