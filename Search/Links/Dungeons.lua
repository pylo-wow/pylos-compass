local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- "Bosses": a dungeon's bosses as NPC entries, in order (only those the NPCs category knows; while it
-- is switched off or not built, the tooltip still lists them all)

ns.RegisterLink({
    key = "bosses",
    label = L["Bosses"],
    title = L["Bosses of %s:"],
    icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
    entries = function(entry)
        local list = {}
        if not entry.mapID then return list end
        for i, boss in ipairs(D.DungeonBosses(entry)) do
            local linked = boss[2] and ns.LinkedNPC(boss[2], ("%d."):format(i))
            if linked then list[#list + 1] = linked end
        end
        return list
    end,
})
