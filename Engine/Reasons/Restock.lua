local _, D = ...
local ns = D.engine
local L = ns.L

-- Restock: what you buy regularly and are running low on (ns.memory.RunningLow: what you buy and how many you usually
-- have after buying). Learned, no item list.
--   items  the item itself ("Running low: 12 left"), more when none are left; in the list of all its nearest vendor's
--          row carries it (via)
--   npcs   a vendor that sells one of them (its symbol on the row)

local low = {} -- item ID -> how many left; see prepare
local VENDOR = D.NPC_ROLE.VENDOR

-- the first item a vendor sells that you run low on
local function Sells(npcID)
    for item in (D.Sells(npcID) or ""):gmatch("%d+") do
        local itemID = tonumber(item)
        if low[itemID] then return itemID end
    end
    return nil
end

-- the nearest vendor selling an item (not hostile to you): factor, words, entry
local function Vendor(itemID)
    return ns.reach.Nearest(D.SoldBy(itemID), true)
end

local TESTS = {
    items = function(entry)
        local left = low[entry.itemID]
        if not left then return nil end
        return left == 0 and 1.5 or 1
    end,
    npcs = function(entry)
        if not next(low) or not D.NPCHasRole(entry, VENDOR) then return nil end
        return Sells(entry.npcID) ~= nil
    end,
}

ns.RegisterReason({
    key = "restock",
    -- weight 0.8: you can play on a while without it, unlike with broken gear or full bags (Service.lua)
    stage = "play", weight = 0.8, label = "Restock",
    sources = { "items", "npcs" },
    depends = { "bags", "rec:memory", "npcs", "data" },
    topic = "supplies",
    prepare = function() low = ns.memory.RunningLow() end,
    test = function(entry) return TESTS[entry.domain](entry) end,
    -- an item: the nearest vendor selling it; a vendor: its distance
    reach = function(entry)
        if entry.domain == "npcs" then return ns.reach.NPC(entry) end
        local factor, words, vendor = Vendor(entry.itemID)
        if not factor then return ns.reach.TRAVEL, nil end
        return factor, L["sold by %s"]:format(vendor.name) .. ", " .. words
    end,
    -- distance counts half (the square root); none left: less still
    urgent = function(_, strength) return strength > 1 and 0.65 or 0.5 end,
    -- an item: its vendor's row stands for it in the list of all
    via = function(entry)
        if entry.domain ~= "items" then return nil end
        local _, _, vendor = Vendor(entry.itemID)
        return vendor and D.EntryID(vendor) or nil
    end,
    note = function(entry)
        if entry.domain == "items" then return L["Running low: %d left"]:format(low[entry.itemID] or 0) end
        local itemID = Sells(entry.npcID)
        local item = itemID and D.ItemByID(itemID)
        return { icon = item and item.icon or "Interface\\Icons\\INV_Misc_Bag_10_Blue",
            tip = L["Sells %s, which you are running low on"]:format(item and item.name or "?") }
    end,
})
