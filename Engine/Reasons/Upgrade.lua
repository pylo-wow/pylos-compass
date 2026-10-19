local _, D = ...
local ns = D.engine
local L = ns.L

-- Upgrade: armor or a weapon you can use (D.ItemForYou) worth more to you than what you wear in its place, as the item
-- valuer sees it (ItemValue\Value.lua). The strength is how much stronger you get: the gain in percent of all you wear
-- (share), growing but flattening: log2(1 + share / 2.5) / 2, so 4 % is 0.7, 20 % 1.6, from 37.5 % on 2, the most a
-- strength counts (Reasons.lua: MOST); a free slot counts FREE_SHARE of its share. Below MIN_SHARE no upgrade (small
-- change filled the lists). So a two-hander 10 % better comes before a ring 50 % better. What you wear is none, one in
-- your bags is Equip.lua's. How easy it is to get is its reach (reach.Item); one only luck brings (a world drop) is
-- none.
-- The row: "+12 Strength, +8 Stamina" (against what you wear there) or "Free slot  ·  ...".
-- ns.UpgradeOf is the one check of "an upgrade for you": this reason, Equip.lua, a quest's rewards (QuestLog.lua), the
-- learning (Learning\Upgrades.lua), the nudges and the search's rows ask it, with the same threshold.

local MIN_SHARE, FREE_SHARE = 0.5, 0.25
local TOP = 2 -- stats named on the row

local function IsGear(entry) return entry.itemClass == 2 or entry.itemClass == 4 end

-- an item you can use that is an upgrade for you (an item ID, or a link: only a link knows the stats of an item with
-- random ones, "of the Monkey"): the valuer's comparison (ItemValue.Compare: share, percent, top, ...), nil if not;
-- worn or not does not matter here
function ns.UpgradeOf(item)
    local itemID = type(item) == "string" and D.ItemIDFromLink(item) or item
    local entry = itemID and D.ItemByID(itemID)
    if not entry or not IsGear(entry) or not D.ItemForYou(entry) then return nil end
    local r = ns.ItemValue.Compare(item)
    if not r or r.gain <= 0 or r.share < MIN_SHARE then return nil end
    return r
end

-- how strong an upgrade is as a reason (r: ns.UpgradeOf's comparison)
function ns.UpgradeStrength(r)
    local share = r.free and r.share * FREE_SHARE or r.share
    return math.log(1 + share / 2.5) / math.log(2) / 2
end

-- what the item changes, in words: "+12 Strength, +8 Stamina" (the stats worth most first, in the stats' own units;
-- damage per second for a weapon), "Free slot  ·  ..." for an empty slot (the row's note and the item tooltip line)
local UNIT_NAMES = { DPS = "DPS", RDPS = "Ranged DPS" }
-- "+12", "+3.2"; nil where it rounds to nothing (a weapon 0.04 damage per second better)
local function Amount(amount)
    amount = math.floor(amount * 10 + 0.5) / 10
    if amount == 0 then return nil end
    return amount == math.floor(amount) and ("%+d"):format(amount) or ("%+.1f"):format(amount)
end
local function Stats(r)
    local parts = {}
    for i = 1, math.min(#r.top, TOP) do
        local key = r.top[i]
        local amount = r.topAmounts and r.topAmounts[key] and Amount(r.topAmounts[key])
        local name = UNIT_NAMES[key] or ns.STAT_NAMES[key] or key
        parts[i] = amount and ("%s %s"):format(amount, name) or name
    end
    return table.concat(parts, ", ")
end
function ns.UpgradeText(r)
    local stats = Stats(r)
    if r.free then return stats ~= "" and (L["Free slot"] .. ns.DOT .. stats) or L["Free slot"] end
    return stats ~= "" and stats or L["Better"]
end
-- the tooltip's reason: what it beats, "Better than your Linen Belt: +2 Strength, +2 Agility" (UpgradeText for a free
-- slot or a worn item the data does not name)
function ns.UpgradeWhy(r)
    local worn = not r.free and r.replaces and D.NameEN("item", r.replaces)
    if not worn then return ns.UpgradeText(r) end
    local stats = Stats(r)
    return stats ~= "" and L["Better than your %s: %s"]:format(worn, stats) or L["Better than your %s"]:format(worn)
end

ns.RegisterReason({
    key = "upgrade",
    -- weight 1: a clear upgrade is plain progress; its size is the strength
    stage = "progress", label = "Upgrade",
    learn = false, -- Learning\Upgrades.lua watches what you do with them
    sources = { "items" },
    -- worth the same wherever you stand (whether a way to it is known changes with the zone at most): the valuer's
    -- states, your bags, and the ways (quests, vendors, money, prices, zone, travel)
    depends = { "bags", "gear", "level", "talents", "spells", "rec:weights", "quests", "npcs", "money", "prices",
        "zone", "travel", "skills", "data" },
    topic = "gear",
    test = function(entry)
        if not IsGear(entry) then return nil end
        -- worn: none; in your bags: Equip.lua's (put on now, a stage above)
        if D.ownedItems[entry.itemID] then return nil end
        local r = ns.UpgradeOf(entry.itemID)
        -- no way to it known but luck (a world drop): no suggestion
        if not r or not ns.reach.Known(entry) then return nil end
        return ns.UpgradeStrength(r)
    end,
    reach = function(entry) return ns.reach.Item(entry) end,
    -- the quest of your log rewarding it: that quest's row stands for it in the list of all
    via = function(entry)
        local _, _, via = ns.reach.Item(entry)
        return via
    end,
    -- the rewards of one quest are one errand: the best stands for them
    group = function(entry)
        local _, _, _, source = ns.reach.Item(entry)
        return source
    end,
    note = function(entry)
        local r = ns.UpgradeOf(entry.itemID)
        return r and ns.UpgradeText(r) or nil
    end,
    why = function(entry)
        local r = ns.UpgradeOf(entry.itemID)
        return r and ns.UpgradeWhy(r) or nil
    end,
})
