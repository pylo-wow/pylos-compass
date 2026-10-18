local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- In bags: items in your bags (not worn). The pool is just those items, so the search skips the rest.

local pool = {}

ns.RegisterFilter({
    key = "inBags",
    name = L["In bags"],
    description = L["Only items you have in your bags."],
    words = "bags bag inventory carried",
    icon = "Interface\\Icons\\INV_Misc_Bag_07",
    sources = { "items" },
    prepare = ns.rank.Prepare, -- reads the bags again after a change
    test = function(entry) return D.bagItems[entry.itemID] == true end,
    -- the item entries of your bags (D.bagItems: item ID -> true)
    pool = function()
        wipe(pool)
        for id in pairs(D.bagItems) do pool[#pool + 1] = ns.index.ItemByID(id) end
        return pool
    end,
})
