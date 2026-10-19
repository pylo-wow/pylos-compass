local _, D = ...
local ns = D.engine
local L = ns.L

-- Equip: an upgrade already in your bags (ns.UpgradeOf, Upgrade.lua: the one check, same threshold). Putting it on
-- costs nothing and only helps, so it is always something to do now: stage "play", the heaviest weight, at least a
-- plain strength however small the gain (a bigger one counts more). An upgrade still to get is Upgrade.lua's.

-- the link of the stack in your bags: only a link knows the stats of an "of the Wolf" item
local function Upgrade(entry) return ns.UpgradeOf(D.bagLinks[entry.itemID] or entry.itemID) end

ns.RegisterReason({
    key = "equip",
    -- weight 1.4: the heaviest, free and only good
    stage = "play", weight = 1.4, label = "Equip",
    learn = false, -- Learning\Upgrades.lua watches what you do with upgrades
    sources = { "items" },
    depends = { "bags", "gear", "level", "talents", "spells", "rec:weights", "data" },
    topic = "gear",
    prepare = D.RefreshOwned, -- D.bagItems is read below: as they are now
    test = function(entry)
        if not (entry.itemClass == 2 or entry.itemClass == 4) or not D.bagItems[entry.itemID] then return nil end
        local r = Upgrade(entry)
        if not r then return nil end
        return math.max(1, ns.UpgradeStrength(r))
    end,
    reach = function() return ns.reach.NOW, L["in your bags"] end,
    note = function(entry)
        local r = Upgrade(entry)
        return r and (L["Equip"] .. ": " .. ns.UpgradeText(r)) or nil
    end,
    why = function(entry)
        local r = Upgrade(entry)
        return r and ns.UpgradeWhy(r) or nil
    end,
})
