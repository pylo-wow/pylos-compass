local _, D = ...

-- Items you carry or wear; rescanned when the states "bags"/"gear" change, call D.RefreshOwned before reading.

D.ownedItems = {} -- item ID -> true: in your bags or worn
D.bagItems = {}   -- item ID -> true: in your bags
-- item ID -> its link in your bags (only a link carries random stats, "of the Wolf").
-- shortcut: one stack's link per ID, upgrade to a list if two stacks of one ID with different random stats matter
D.bagLinks = {}
local scanned = D.Cache({ "bags", "gear" })

local function ScanOwned()
    wipe(D.ownedItems)
    wipe(D.bagItems)
    wipe(D.bagLinks)
    for bag = 0, 5 do -- backpack, four bags, reagent bag
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and id > 0 then
                D.ownedItems[id], D.bagItems[id], D.bagLinks[id] = true, true, info.hyperlink
            end
        end
    end
    -- slot 0 (ammunition) may answer 0 for "no item"
    for slot = 0, 19 do
        local id = GetInventoryItemID("player", slot)
        if id and id > 0 then D.ownedItems[id] = true end
    end
end

-- Rescans if bags/gear changed; call before reading D.ownedItems / D.bagItems
function D.RefreshOwned()
    local _, renewed = scanned.Get()
    if renewed then ScanOwned() end
end
