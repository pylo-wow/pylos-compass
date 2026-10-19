local _, D = ...
local ns = D.engine
local L = ns.L

-- Service: an NPC you need because of the state of your gear and bags (D.NPCHasRole).
--   repair  your most worn piece is below 30 %: 0.5, below 10 %: 1, broken: 2 (a broken piece gives you nothing)
--   bags    two free slots or fewer: any vendor, to sell; 0.5, full: 1
-- Urgent: distance hurts it less, the worse it is (Reasons.lua). The row shows the minimap's repair symbol or a bag.

local WORN, BADLY = 0.3, 0.1 -- durability shares
local FULL = 2     -- free bag slots at which selling is due
local ROLE = D.NPC_ROLE
local repair, sell = nil, nil -- strengths, nil: not due

-- the share of durability of your most worn piece (1: none worn)
local function Worst()
    local worst = 1
    if not GetInventoryItemDurability then return worst end
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then worst = math.min(worst, current / maximum) end
    end
    return worst
end

-- free slots of the plain bags (bag family 0: not quivers, ammo pouches, soul or herb bags, whose room is no room for
-- loot)
local function FreeSlots()
    local free = 0
    for bag = 0, 4 do
        local count, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (count or 0) end
    end
    return free
end

-- the nudges read the same (Pushes.lua)
ns.service = { Worst = Worst, FreeSlots = FreeSlots }

-- what this NPC is due for: the repair and the selling strength (0: not due or not his role); a repairer who also
-- sells is worth the larger
local function Due(entry)
    return repair and D.NPCHasRole(entry, ROLE.REPAIR) and repair or 0,
        sell and D.NPCHasRole(entry, ROLE.VENDOR) and sell or 0
end

ns.RegisterReason({
    key = "service",
    -- weight 1: the plain need of the first stage (a repairer when gear is worn, a vendor when bags are full)
    stage = "play", label = "Service",
    sources = { "npcs" },
    depends = { "durability", "gear", "bags", "npcs", "data" },
    topic = "supplies",
    prepare = function()
        local worst = Worst()
        repair = worst <= 0 and 2 or worst < BADLY and 1 or worst < WORN and 0.5 or nil
        local free = FreeSlots()
        sell = free <= 0 and 1 or free <= FULL and 0.5 or nil
    end,
    test = function(entry)
        local mend, sale = Due(entry)
        local strength = math.max(mend, sale)
        return strength > 0 and strength or nil
    end,
    -- the worse, the less distance counts: worn 0.45, badly worn or full bags 0.6, broken 0.9 (a broken piece gives you
    -- nothing)
    urgent = function(_, strength) return math.min(0.9, 0.3 + 0.3 * strength) end,
    note = function(entry)
        local mend, sale = Due(entry)
        if mend >= sale then
            return { icon = 136465, tip = L["Repairs: your gear is badly worn"] } -- Interface\Minimap\Tracking\Repair
        end
        return { icon = 133633, tip = L["Buys: your bags are almost full"] } -- Interface\Icons\INV_Misc_Bag_08
    end,
})
