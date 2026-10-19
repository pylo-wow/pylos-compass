local _, D = ...

-- Items you carry or wear; rescanned when the states "bags"/"gear" change, call D.RefreshOwned before reading.

D.ownedItems = {} -- item ID -> true: in your bags or worn
D.bagItems = {}   -- item ID -> true: in your bags
local scanned = D.Cache({ "bags", "gear" })

local function ScanOwned()
    wipe(D.ownedItems)
    wipe(D.bagItems)
    for bag = 0, 5 do -- backpack, four bags, reagent bag
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and id > 0 then D.ownedItems[id], D.bagItems[id] = true, true end
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
