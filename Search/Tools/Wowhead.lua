local ns = select(2, ...).search
local L = ns.L

-- Wowhead link: the game cannot open a browser, so the address is shown in a text field of the detail view,
-- ready for Ctrl+C. Wowhead's Forever section (/forever/item=..., /forever/spell=...), English only.

local BASE = "https://www.wowhead.com/forever/"

local function Address(entry)
    if entry.itemID then return BASE .. "item=" .. entry.itemID end
    if entry.spellID then return BASE .. "spell=" .. entry.spellID end
    if entry.npcID then return BASE .. "npc=" .. entry.npcID end
    if entry.questID then return BASE .. "quest=" .. entry.questID end
    -- a dungeon: Wowhead's search for its name (its zone IDs are not in our data)
    if entry.mapID then
        return BASE .. "search?q=" .. entry.name:gsub("[^%w%-%.]", function(c) return ("%%%02X"):format(c:byte()) end)
    end
end

ns.RegisterTool({
    key = "wowhead",
    label = L["Wowhead link"],
    available = function(entry) return Address(entry) ~= nil end,
    run = function(entry) ns.ui.ShowCopy(Address(entry)) end,
})
