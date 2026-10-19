local _, D = ...
if D.off then return end

-- Where gathered materials come from (Data\Gathering.lua: one source per item, surest first)
-- and herb/ore nodes (Data\Nodes.lua, in the addons that have it).
--   D.Gathering(itemID)  nil if unknown, else (built on first ask, shared, do not change):
--     { kind = "mine" | "herb" | "skin" | "drop",
--       skill = number,            mine/herb: required Mining/Herbalism skill
--       zones = { uiMapID, ... },  mine/herb: zones with the most nodes, fullest first; else empty
--       low, high = number,        skin/drop: mobs' level range
--       creatureType = number }    drop: mobs' main type (1 beast, 2 dragonkin, 3 demon,
--                                  4 elemental, 5 giant, 6 undead, 7 humanoid, 8 critter,
--                                  9 mechanical; 0 mixed)
--   D.Node(name)  node by its English in-game name, nil if unknown (shared, do not change):
--     { skill line (182 Herbalism, 186 Mining), required skill, yields "itemID:chance,..." best first }
--   D.GatheringCount(), D.NodeCount()  number of known materials / nodes

local KINDS = { m = "mine", h = "herb", s = "skin", d = "drop" }
local made = {}

function D.Gathering(itemID)
    local info = made[itemID]
    if info then return info end
    local row = D.gathering and D.gathering[itemID]
    local kind = row and KINDS[row[1]]
    if not kind then return nil end
    info = { kind = kind, zones = {} }
    if kind == "mine" or kind == "herb" then
        info.skill = row[2]
        for i = 3, #row do info.zones[#info.zones + 1] = row[i] end
    else
        info.low, info.high = row[2], row[3]
        if kind == "drop" then info.creatureType = row[4] end
    end
    made[itemID] = info
    return info
end

function D.Node(name)
    local nodes = D.nodes
    if not nodes or not name then return nil end
    return nodes[name]
end

function D.GatheringCount()
    local count = 0
    for _ in pairs(D.gathering or {}) do count = count + 1 end
    return count
end

function D.NodeCount()
    local count = 0
    for _ in pairs(D.nodes or {}) do count = count + 1 end
    return count
end
