local ns = select(2, ...).search
local D = ns.data
local L = ns.L

-- NPC links (Data: D.DropsOf, D.Sells and the reverse; 1.12 data plus what was learned in play): what an
-- NPC drops (with chance) and sells, and for an item which NPCs drop or sell it. NPCs come from the NPCs
-- category's index: while it is switched off or not built, these links show nothing.

local LinkedItem, LinkedNPC = ns.LinkedItem, ns.LinkedNPC

local function Chance(text)
    local chance = tonumber(text)
    if chance and chance > 0 then return chance .. " %" end
    return L["< 1 %"]
end

-- What only the 1.12 data says, not seen in WoW Forever yet, stands below a heading (D.NPCOriginByID).
-- An NPC's own list is all one or the other: the heading on top.
local function Unchecked() return { header = true, name = L["Unchecked (1.12 data)"], key = "" } end
local function FromData(npcID, what) return D.NPCOriginByID(npcID, what) == "1.12" end
local function SeenFirst(seen, unchecked)
    if #unchecked == 0 then return seen end
    seen[#seen + 1] = Unchecked()
    for _, row in ipairs(unchecked) do seen[#seen + 1] = row end
    return seen
end

ns.RegisterLink({
    key = "drops",
    label = L["Drops"],
    title = L["%s drops:"],
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    entries = function(entry)
        local list = {}
        local text = entry.npcID and D.DropsOf(entry.npcID)
        for id, chance in (text or ""):gmatch("(%d+):(%d+)") do
            list[#list + 1] = LinkedItem(tonumber(id), Chance(chance))
        end
        if #list > 0 and FromData(entry.npcID, "drops") then table.insert(list, 1, Unchecked()) end
        return list
    end,
})

ns.RegisterLink({
    key = "sells",
    label = L["Sells"],
    title = L["%s sells:"],
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    -- what few vendors sell comes first, what every vendor sells last; the same count A-Z
    entries = function(entry)
        local list, vendors = {}, {}
        local text = entry.npcID and D.Sells(entry.npcID)
        for id in (text or ""):gmatch("%d+") do
            local itemID = tonumber(id)
            local count = 0
            for _ in (D.SoldBy(itemID) or ""):gmatch("%d+") do count = count + 1 end
            -- price for one (below on the right), with this vendor's discount where known
            local price = D.PriceAt and D.PriceAt(itemID, entry.npcID)
            local item = LinkedItem(itemID, price and D.Money(price) or "")
            vendors[item] = count
            list[#list + 1] = item
        end
        table.sort(list, function(a, b)
            if vendors[a] ~= vendors[b] then return vendors[a] < vendors[b] end
            return a.name < b.name
        end)
        -- a thin line (a heading without a label) after what only this vendor sells
        for i = 1, #list - 1 do
            if vendors[list[i]] <= 1 and vendors[list[i + 1]] > 1 then
                table.insert(list, i + 1, { header = true, name = "", key = "" })
                break
            end
        end
        if #list > 0 and FromData(entry.npcID, "sells") then table.insert(list, 1, Unchecked()) end
        return list
    end,
})

ns.RegisterLink({
    key = "droppedBy",
    label = L["Dropped by"],
    title = L["%s is dropped by:"],
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    entries = function(entry)
        local list, unchecked = {}, {}
        local text = entry.itemID and D.DroppedBy(entry.itemID)
        for id, chance in (text or ""):gmatch("(%d+):(%d+)") do
            local npc = LinkedNPC(tonumber(id), Chance(chance))
            if npc then
                local into = FromData(npc.npcID, "drops") and unchecked or list
                into[#into + 1] = npc
            end
        end
        return SeenFirst(list, unchecked)
    end,
})

ns.RegisterLink({
    key = "soldBy",
    label = L["Sold by"],
    title = L["%s is sold by:"],
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    entries = function(entry)
        local list, unchecked = {}, {}
        local text = entry.itemID and D.SoldBy(entry.itemID)
        for id in (text or ""):gmatch("%d+") do
            local price = D.PriceAt and D.PriceAt(entry.itemID, tonumber(id))
            local npc = LinkedNPC(tonumber(id), price and D.Money(price) or "")
            if npc then
                local into = FromData(npc.npcID, "sells") and unchecked or list
                into[#into + 1] = npc
            end
        end
        local function ByName(a, b) return a.name < b.name end
        table.sort(list, ByName)
        table.sort(unchecked, ByName)
        return SeenFirst(list, unchecked)
    end,
})

-- "Taught by": a spell or a trainer's recipe you have not learned, its trainers (D.npcTrainers: your
-- class's, the profession's), not hostile to you, the nearest first, then A-Z. The tooltip names none.
ns.RegisterLink({
    key = "taughtBy",
    label = L["Taught by"],
    title = L["%s is taught by:"],
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    entries = function(entry)
        local teaches
        if entry.hidden and entry.trainLevel then
            teaches = select(3, UnitClass("player"))
        elseif entry.hidden and entry.skillLine and (entry.recipeItem or 0) == 0 then
            teaches = entry.skillLine
        end
        local list, yards = {}, {}
        for _, npcID in ipairs(teaches and ns.TrainersOf(teaches) or {}) do
            local npc = LinkedNPC(npcID, "")
            if npc and npc.target.reaction ~= 1 then
                yards[npc] = D.NPCDistance(npc.target) or math.huge
                list[#list + 1] = npc
            end
        end
        table.sort(list, function(a, b)
            if yards[a] ~= yards[b] then return yards[a] < yards[b] end
            return a.name < b.name
        end)
        return list
    end,
})
