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
-- The row: "+14 %  ·  Strength, Crit" (against what you wear there) or "Free slot  ·  ...".
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

-- a comparison in words: "+14 %  ·  Strength, Crit" or "Free slot  ·  ..." (the row's note and the item tooltip line)
function ns.UpgradeText(r)
    local names = {}
    for i = 1, math.min(#r.top, TOP) do names[i] = ns.STAT_NAMES[r.top[i]] or r.top[i] end
    local head = r.free and L["Free slot"] or r.percent and ("+%d %%"):format(r.percent + 0.5) or L["Better"]
    return #names > 0 and (head .. ns.DOT .. table.concat(names, ", ")) or head
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
        if not r then return nil end
        return L["Makes you %.1f %% stronger"]:format(r.share)
    end,
})
