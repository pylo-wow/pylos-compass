local _, D = ...
local ns = D.engine
local L = ns.L

-- Quest zone: a zone with many quests for your level that you have not done (D.ZoneQuests). Quests from two levels
-- below yours to three above (yellow and orange ones, a little green); at least FEW of them, strength by how many
-- (MANY: 1). Your own zone is at hand, another one a journey.

local BELOW, ABOVE = 2, 3
local FEW, MANY = 3, 8

local counts = {} -- zone ID -> open quests for your level; see prepare

local function Count(entry)
    local count = counts[entry.zoneID]
    if not count then
        local level = UnitLevel("player")
        count = D.ZoneQuests(entry.zoneID, level - BELOW, level + ABOVE)
        counts[entry.zoneID] = count
    end
    return count
end

ns.RegisterReason({
    key = "questZone",
    -- weight 0.75: a place to level, not a step itself (quests of your log and trainers come first)
    stage = "progress", weight = 0.75, label = "Quest zone",
    sources = { "zones" },
    depends = { "level", "quests", "data" },
    topic = "zones",
    prepare = function() wipe(counts) end,
    test = function(entry)
        local count = Count(entry)
        if count < FEW then return nil end
        -- more the more, flattening (MANY: 1, twice as many: 1.5); not capped (zones would stand alike at the cap)
        return math.max(0.25, ns.reasons.Grow(count, MANY))
    end,
    reach = function(entry)
        if entry.zoneID == D.PlayerZone() then return ns.reach.NOW, L["you are there"] end
        -- the way to its middle (another continent: overseas)
        return ns.reach.Place(D.ZonePlace(entry.zoneID))
    end,
    note = function(entry) return L["%d quests for your level"]:format(Count(entry)) end,
})
