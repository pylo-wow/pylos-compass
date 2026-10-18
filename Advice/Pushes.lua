local ns = select(2, ...).advice
if ns.off then return end
local D = ns.data
local L = ns.L

-- Nudge rules (chain, levels, log: Push.lua). Each judges per candidate whether it is big, missable and sure, with words for the log.
--   equip: upgrade in bags, big from BIG_SHARE % (medium). trainer: class trainer with new spells within NEAR yd (medium).
--   skillcap: profession at its rank cap (75, 150), its trainer within NEAR yd (medium). repair: worst piece below WORN, repairer within NEAR yd; loud before a dungeon entrance.
--   bags: few free slots, vendor within NEAR yd (quiet at LOW, medium at FULL). rare: rare nearby, loud, own budget, click targets it.
-- "sure" needs places seen in WoW Forever or game-given trainer data; the 1.12 data's spots are unchecked.

local NEAR = 400       -- yards
local ENTRANCE = 150   -- yards from a dungeon's entrance
local BIG_SHARE = 2    -- % stronger: an upgrade worth a nudge
local WORN = 0.2       -- durability share
local LOW, FULL = 4, 2 -- free bag slots
local RARE_AGAIN = 30 * 60
local ROLE = D.NPC_ROLE

-- NPC spot and whether it was seen in WoW Forever (else the 1.12 data's)
local function Spot(entry)
    local place = D.npcPlaces and D.npcPlaces[entry.npcID]
    return place, D.NPCOrigin(entry, "place") == "seen"
end

-- the nearest NPC of your zone with a role, not hostile: entry, yards
local function NearestWith(role)
    local zone = D.PlayerZone()
    local best, bestYards
    for _, entry in ipairs(zone and D.NPCsInZone(zone) or {}) do
        if entry.reaction ~= 1 and D.NPCHasRole(entry, role) then
            local yards = D.NPCDistance(entry)
            if yards and (not bestYards or yards < bestYards) then best, bestYards = entry, yards end
        end
    end
    return best, bestYards
end

local function Waypoint(entry)
    local place = Spot(entry)
    return place and { kind = "waypoint", value = place, name = entry.name } or nil
end

local function Yards(yards) return yards and ("%d yd"):format(yards) or "far" end

-- Equip
ns.RegisterPush({
    key = "equip", label = L["Upgrades in your bags"], level = ns.push.MEDIUM, topic = "gear",
    states = { "bags", "gear", "level", "rec:weights" },
    candidates = function(add)
        for itemID in pairs(D.bagItems) do
            local entry = D.ItemByID(itemID)
            local r = entry and (entry.itemClass == 2 or entry.itemClass == 4) and ns.UpgradeOf(itemID)
            if r then
                add({
                    situation = "equip:" .. itemID, entry = entry, icon = entry,
                    title = L["Put it on: %s"]:format(entry.name),
                    text = L["In your bags: makes you %.1f %% stronger"]:format(r.share),
                    action = { kind = "item", value = "item:" .. itemID },
                    big = { r.share >= BIG_SHARE, ("%.1f%%"):format(r.share) },
                    missable = { true, "in your bags" },
                    sure = { C_Item.IsItemDataCachedByID(itemID), "item data" },
                })
            end
        end
    end,
})

-- Trainer
ns.RegisterPush({
    key = "trainer", label = L["New spells at your trainer nearby"], level = ns.push.MEDIUM, topic = "class",
    states = { "level", "spells", "zone", "npcs" },
    candidates = function(add)
        local trainer = ns.reach.Trainer(select(3, UnitClass("player")))
        if not trainer then return end
        local reason = ns.reasons.All().trainsYou
        if not ns.reasons.Test("trainsYou", trainer) then return end
        local note = reason.note(trainer)
        local ids = reason.renew(trainer)
        local place, seen = Spot(trainer)
        local yards = D.NPCDistance(trainer)
        add({
            situation = "trainer:" .. table.concat(ids, "."), entry = trainer, icon = trainer,
            title = note.count == 1 and L["A new spell to learn"] or L["%d new spells to learn"]:format(note.count or 0),
            text = L["%s is %d yd away"]:format(trainer.name, yards or 0),
            action = Waypoint(trainer),
            big = { reason.affordable(trainer) > 0, ("%d spells, %d affordable"):format(note.count or 0, reason.affordable(trainer)) },
            missable = { yards ~= nil and yards <= NEAR, Yards(yards) },
            sure = { place ~= nil and (seen or D.NPCOrigin(trainer, "trains") == "seen"), seen and "spot seen" or "1.12 spot" },
        })
    end,
})

-- Skill cap
-- level needed for the next rank (Journeyman 10, Expert 20); Artisan only at few trainers: not sure
local NEXT_LEVEL = { [75] = 10, [150] = 20 }
ns.RegisterPush({
    key = "skillcap", label = L["A profession at its cap, its trainer nearby"], level = ns.push.MEDIUM,
    topic = "professions",
    states = { "skills", "level", "zone", "npcs" },
    candidates = function(add)
        local ranks, maxima = D.ProfessionRanks()
        for line, rank in pairs(ranks) do
            local maximum = maxima[line] or 0
            if maximum > 0 and rank >= maximum and maximum < 300 then
                local trainer = ns.reach.Trainer(line)
                local yards = trainer and D.NPCDistance(trainer)
                local needs = NEXT_LEVEL[maximum]
                local name = D.professionNames[line] or tostring(line)
                add({
                    situation = ("skillcap:%d:%d"):format(line, maximum), entry = trainer,
                    icon = { icon = D.professionIcons[line] },
                    title = L["%s %d/%d: learn the next rank"]:format(name, rank, maximum),
                    text = trainer and L["%s is %d yd away"]:format(trainer.name, yards or 0) or "",
                    action = trainer and Waypoint(trainer),
                    big = { true, ("%d/%d"):format(rank, maximum) },
                    missable = { yards ~= nil and yards <= NEAR, Yards(yards) },
                    sure = { needs ~= nil and UnitLevel("player") >= needs, needs and ("from level %d"):format(needs) or "artisan" },
                })
            end
        end
    end,
})

-- Repair
ns.RegisterPush({
    key = "repair", label = L["Worn gear, a repairer nearby or a dungeon ahead"], level = ns.push.LOUD,
    topic = "supplies",
    states = { "durability", "gear", "zone", "npcs" },
    candidates = function(add)
        local worst = ns.service.Worst()
        if worst >= WORN then return end
        local percent = math.floor(worst * 100 + 0.5)
        -- before a dungeon: loud
        for _, dungeon in ipairs(D.Entries("dungeons")) do
            local yards = dungeon.place and D.PlaceDistance(dungeon.place)
            if yards and yards <= ENTRANCE then
                add({
                    situation = ("repair:d%d:%d"):format(dungeon.mapID or 0, math.floor(percent / 10)), entry = dungeon, icon = dungeon,
                    anyway = true, level = ns.push.LOUD,
                    title = L["Repair before %s"]:format(dungeon.name),
                    text = L["Your gear is at %d %%; inside there is no repairer"]:format(percent),
                    big = { true, percent .. "%" }, missable = { true, "entrance " .. Yards(yards) },
                    sure = { true, "durability" },
                })
                return
            end
        end
        local repairer, yards = NearestWith(ROLE.REPAIR)
        if not repairer then return end
        local _, seen = Spot(repairer)
        add({
            situation = ("repair:%d:%d"):format(repairer.npcID, math.floor(percent / 10)), entry = repairer, icon = repairer,
            level = ns.push.MEDIUM,
            title = L["Repair: your gear is at %d %%"]:format(percent),
            text = L["%s is %d yd away"]:format(repairer.name, yards),
            action = Waypoint(repairer),
            big = { true, percent .. "%" }, missable = { yards <= NEAR, Yards(yards) },
            sure = { seen or D.NPCRoleOrigin(repairer, ROLE.REPAIR) == "seen", seen and "spot seen" or "1.12 spot" },
        })
    end,
})

-- Bags
ns.RegisterPush({
    key = "bags", label = L["Bags nearly full, a vendor nearby"], level = ns.push.MEDIUM, topic = "supplies",
    states = { "bags", "zone", "npcs" },
    candidates = function(add)
        local free = ns.service.FreeSlots()
        if free > LOW then return end
        local vendor, yards = NearestWith(ROLE.VENDOR)
        if not vendor then return end
        local _, seen = Spot(vendor)
        add({
            situation = ("bags:%s:%d"):format(free <= FULL and "full" or "low", vendor.npcID), entry = vendor, icon = vendor,
            level = free <= FULL and ns.push.MEDIUM or ns.push.QUIET,
            title = free == 1 and L["1 free bag slot"] or L["%d free bag slots"]:format(free),
            text = L["Sell at %s, %d yd away"]:format(vendor.name, yards),
            action = Waypoint(vendor),
            big = { true, free .. " free" }, missable = { yards <= NEAR, Yards(yards) },
            sure = { seen or D.NPCRoleOrigin(vendor, ROLE.VENDOR) == "seen", seen and "spot seen" or "1.12 spot" },
        })
    end,
})

-- Rare nearby
ns.RegisterPush({
    key = "rare", label = L["A rare nearby"], level = ns.push.LOUD, ownBudget = true,
    states = { "rec:rare" },
    candidates = function(add)
        for npcID in pairs(ns.RaresSeen()) do
            local entry = D.NPCByID(npcID)
            if entry then
                add({
                    situation = "rare:" .. npcID, again = RARE_AGAIN, entry = entry, icon = entry, anyway = true,
                    title = L["Rare nearby: %s"]:format(entry.name),
                    text = entry.levelMax > 0 and L["Level %d"]:format(entry.levelMax) or "",
                    -- secure macro, out of combat
                    action = { kind = "macro", value = "/targetexact " .. entry.name },
                    big = { true, "rare" }, missable = { true, "seen now" }, sure = { true, "seen" },
                })
            end
        end
    end,
})

-- Options rows (Compass.lua puts them on the page): nudges on/off, each level, the sound, each rule ("Never for this" switches its rule off here)
local options = ns.options
options[#options + 1] = { type = "header", label = L["Nudges"] }
options[#options + 1] = { type = "checkbox", key = "push", label = L["Nudge me when something important comes up"], default = true,
    tooltip = L["Speaks up by itself, rarely: only when something is worth a lot, may be missed now, rests on sure facts and is new to you, and only in a pause (not in a fight)."] }
options[#options + 1] = { type = "checkbox", key = "pushQuiet", label = L["Quiet: the minimap button glows"], default = true,
    tooltip = L["The suggestions window's tab gets a dot until you look at it."] }
options[#options + 1] = { type = "checkbox", key = "pushMedium", label = L["Medium: a short note by the minimap"], default = true,
    tooltip = L["It fades after a few seconds. Switched off, these nudges come quietly."] }
options[#options + 1] = { type = "checkbox", key = "pushLoud", label = L["Loud: a note on the screen"], default = true,
    tooltip = L["Only for what is now or never (a rare nearby, repairing before a dungeon). Switched off, these come as a medium note."] }
options[#options + 1] = { type = "checkbox", key = "pushSound", label = L["Loud nudges with a sound"], default = true }
for _, rule in ipairs(ns.push.rules) do
    options[#options + 1] = { type = "checkbox", key = "push_" .. rule.key, label = rule.label, default = true }
end

ns.push.Start()
