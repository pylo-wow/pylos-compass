local ns = select(2, ...).advice
local D = ns.data
local L = ns.L

-- Nudge rules (chain, levels, log: Push.lua). Each judges per candidate whether it is big, missable and sure, with
-- words for the log.
--   Default levels (changed in the options): equip quiet, trainer, skillcap, repair and bags note, rare alert.
--   equip: upgrade in the bags for UPGRADE_AFTER s, big from BIG_SHARE %. trainer: class trainer with new spells
--   within NEAR yd. skillcap: profession at its rank cap (75, 150), its trainer within NEAR yd.
--   repair: worst piece below WORN, repairer within NEAR yd.
--   bags: few free slots, vendor within NEAR yd (only quiet at LOW, what is set at FULL).
--   rare: rare nearby, own budget, click targets it.
-- "sure" needs places seen in WoW Forever or game-given trainer data; the 1.12 data's spots are unchecked.

local NEAR = 400       -- yards
local BIG_SHARE = 2    -- % stronger: an upgrade worth a nudge
local UPGRADE_AFTER = 2 * 60 -- seconds an upgrade lies in the bags before it nudges
local WORTH_SHARE = 8   -- % stronger: an upgrade clearly worth it (its rule is then dampened one step less)
local WORN = 0.2       -- durability share
local LOW, FULL = 4, 2 -- free bag slots
local RARE_AGAIN = 30 * 60
local ROLE = D.NPC_ROLE

-- What you did, for the rules' done(c, shownAt): when you last opened a trainer window, when you last targeted each rare
local trainerAt, targetedAt = 0, {}
ns.On("TRAINER_SHOW", function()
    trainerAt = time()
    ns.push.Recheck()
end)
ns.On("PLAYER_TARGET_CHANGED", function()
    local id = D.NPCOf("target")
    if id and ns.RaresSeen()[id] then
        targetedAt[id] = time()
        ns.push.Recheck()
    end
end)
local function TrainerSince(_, at) return trainerAt >= at end
local function RepairOver() return ns.service.Worst() >= WORN end
local function BagsOver() return ns.service.FreeSlots() > LOW end

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

-- Test nudges (the options page): a random kind with real data from the game, shown as a real one is, by the same
-- messages the rules build (rule.example gives the candidate); nothing of it is remembered (Toast.lua Sample).
local function Random(entries, accept)
    local pick, count = nil, 0
    for _, entry in ipairs(entries) do
        if accept(entry) then
            count = count + 1
            if math.random(count) == 1 then pick = entry end
        end
    end
    return pick
end
local function NPCWith(accept)
    return Random(D.Entries("npcs"), function(entry) return entry.reaction ~= 1 and Spot(entry) and accept(entry) end)
end
local function SomeYards(entry) return D.NPCDistance(entry) or math.random(60, NEAR) end

-- Equip
local function EquipMessage(entry, share, action)
    return { situation = "equip:" .. entry.itemID, entry = entry, icon = entry,
        title = L["Put it on: %s"]:format(entry.name),
        text = L["In your bags: makes you %.1f %% stronger"]:format(share),
        action = action and { kind = "item", value = "item:" .. entry.itemID } or nil }
end
ns.RegisterPush({
    key = "equip", label = L["Upgrades in your bags"], level = ns.push.QUIET, topic = "gear", holdFor = UPGRADE_AFTER,
    done = function(c) return C_Item.IsEquippedItem and c.entry and C_Item.IsEquippedItem(c.entry.itemID) or false end,
    states = { "bags", "gear", "level", "rec:weights" },
    candidates = function(add)
        for itemID in pairs(D.bagItems) do
            local entry = D.ItemByID(itemID)
            local r = entry and (entry.itemClass == 2 or entry.itemClass == 4) and ns.UpgradeOf(itemID)
            if r then
                local c = EquipMessage(entry, r.share, true)
                c.worth = r.share >= WORTH_SHARE
                c.big = { r.share >= BIG_SHARE, ("%.1f%%"):format(r.share) }
                c.missable = { true, "in your bags" }
                c.sure = { C_Item.IsItemDataCachedByID(itemID), "item data" }
                add(c)
            end
        end
    end,
    -- an item you can use (not one of yours: a click would put it on)
    example = function()
        local entry = Random(D.Entries("items"), function(e)
            return (e.itemClass == 2 or e.itemClass == 4) and D.ItemForYou(e)
        end)
        return entry and EquipMessage(entry, 2 + math.random() * 10, false)
    end,
})

-- Trainer
local function TrainerMessage(trainer, count, yards, ids)
    return { situation = "trainer:" .. table.concat(ids, "."), entry = trainer, icon = trainer,
        title = count == 1 and L["A new spell to learn"] or L["%d new spells to learn"]:format(count),
        text = L["%s is %d yd away"]:format(trainer.name, yards or 0), action = Waypoint(trainer) }
end
ns.RegisterPush({
    key = "trainer", label = L["New spells at your trainer nearby"], level = ns.push.MEDIUM, topic = "class",
    done = TrainerSince,
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
        local c = TrainerMessage(trainer, note.count or 0, yards, ids)
        c.big = { reason.affordable(trainer) > 0,
            ("%d spells, %d affordable"):format(note.count or 0, reason.affordable(trainer)) }
        c.missable = { yards ~= nil and yards <= NEAR, Yards(yards) }
        c.sure = { place ~= nil and (seen or D.NPCOrigin(trainer, "trains") == "seen"),
            seen and "spot seen" or "1.12 spot" }
        add(c)
    end,
    example = function()
        local trainer = NPCWith(function(e) return D.NPCHasRole(e, ROLE.TRAINER) end)
        return trainer and TrainerMessage(trainer, math.random(1, 4), SomeYards(trainer), { "example" })
    end,
})

-- Skill cap
-- level needed for the next rank (Journeyman 10, Expert 20); Artisan only at few trainers: not sure
local NEXT_LEVEL = { [75] = 10, [150] = 20 }
local function SkillcapMessage(line, rank, maximum, trainer, yards)
    return { situation = ("skillcap:%d:%d"):format(line, maximum), entry = trainer,
        icon = { icon = D.professionIcons[line] },
        title = L["%s %d/%d: learn the next rank"]:format(D.professionNames[line] or tostring(line), rank, maximum),
        text = trainer and L["%s is %d yd away"]:format(trainer.name, yards or 0) or "",
        action = trainer and Waypoint(trainer) }
end
ns.RegisterPush({
    key = "skillcap", label = L["A profession at its cap, its trainer nearby"], level = ns.push.MEDIUM,
    topic = "professions",
    done = TrainerSince,
    states = { "skills", "level", "zone", "npcs" },
    candidates = function(add)
        local ranks, maxima = D.ProfessionRanks()
        for line, rank in pairs(ranks) do
            local maximum = maxima[line] or 0
            if maximum > 0 and rank >= maximum and maximum < 300 then
                local trainer = ns.reach.Trainer(line)
                local yards = trainer and D.NPCDistance(trainer)
                local needs = NEXT_LEVEL[maximum]
                local c = SkillcapMessage(line, rank, maximum, trainer, yards)
                c.big = { true, ("%d/%d"):format(rank, maximum) }
                c.missable = { yards ~= nil and yards <= NEAR, Yards(yards) }
                c.sure = { needs ~= nil and UnitLevel("player") >= needs,
                    needs and ("from level %d"):format(needs) or "artisan" }
                add(c)
            end
        end
    end,
    example = function()
        local lines = {}
        for line in pairs(D.professionNames or {}) do
            if D.professionIcons[line] then lines[#lines + 1] = line end
        end
        local line = lines[math.random(#lines)]
        if not line then return nil end
        local maximum = math.random(2) == 1 and 75 or 150
        local trainer = ns.reach.Trainer(line)
        return SkillcapMessage(line, maximum, maximum, trainer, trainer and SomeYards(trainer))
    end,
})

-- Repair
local function RepairMessage(repairer, percent, yards)
    return { situation = ("repair:%d"):format(math.floor(percent / 10)), entry = repairer, icon = repairer,
        title = L["Repair: your gear is at %d %%"]:format(percent),
        text = L["%s is %d yd away"]:format(repairer.name, yards), action = Waypoint(repairer) }
end
ns.RegisterPush({
    key = "repair", label = L["Worn gear, a repairer nearby"], level = ns.push.MEDIUM,
    topic = "supplies",
    states = { "durability", "gear", "zone", "npcs" },
    resolved = RepairOver, done = RepairOver, -- repaired: the next time nudges again, and it was followed
    candidates = function(add)
        local worst = ns.service.Worst()
        if worst >= WORN then return end
        local percent = math.floor(worst * 100 + 0.5)
        local repairer, yards = NearestWith(ROLE.REPAIR)
        if not repairer then return end
        local _, seen = Spot(repairer)
        local c = RepairMessage(repairer, percent, yards)
        c.worth = percent <= 5
        c.big = { true, percent .. "%" }
        c.missable = { yards <= NEAR, Yards(yards) }
        c.sure = { seen or D.NPCRoleOrigin(repairer, ROLE.REPAIR) == "seen", seen and "spot seen" or "1.12 spot" }
        add(c)
    end,
    example = function()
        local repairer = NPCWith(function(e) return D.NPCHasRole(e, ROLE.REPAIR) end)
        return repairer and RepairMessage(repairer, math.random(3, 19), SomeYards(repairer))
    end,
})

-- Bags
local function BagsMessage(vendor, free, yards)
    return { situation = "bags:" .. (free <= FULL and "full" or "low"), entry = vendor, icon = vendor,
        title = free == 1 and L["1 free bag slot"] or L["%d free bag slots"]:format(free),
        text = L["Sell at %s, %d yd away"]:format(vendor.name, yards), action = Waypoint(vendor) }
end
ns.RegisterPush({
    key = "bags", label = L["Bags nearly full, a vendor nearby"], level = ns.push.MEDIUM, topic = "supplies",
    states = { "bags", "zone", "npcs" },
    resolved = BagsOver, done = BagsOver, -- emptied: the next time nudges again, and it was followed
    candidates = function(add)
        local free = ns.service.FreeSlots()
        if free > LOW then return end
        local vendor, yards = NearestWith(ROLE.VENDOR)
        if not vendor then return end
        local _, seen = Spot(vendor)
        local c = BagsMessage(vendor, free, yards)
        c.worth = free <= 0
        c.level = free > FULL and ns.push.QUIET or nil -- full bags: what the user set
        c.big = { true, free .. " free" }
        c.missable = { yards <= NEAR, Yards(yards) }
        c.sure = { seen or D.NPCRoleOrigin(vendor, ROLE.VENDOR) == "seen", seen and "spot seen" or "1.12 spot" }
        add(c)
    end,
    example = function()
        local vendor = NPCWith(function(e) return D.NPCHasRole(e, ROLE.VENDOR) end)
        return vendor and BagsMessage(vendor, math.random(0, LOW), SomeYards(vendor))
    end,
})

-- Rare nearby
local function RareMessage(entry)
    return { situation = "rare:" .. entry.npcID, again = RARE_AGAIN, entry = entry, icon = entry, anyway = true,
        title = L["Rare nearby: %s"]:format(entry.name),
        text = entry.levelMax > 0 and L["Level %d"]:format(entry.levelMax) or "",
        -- secure macro, out of combat
        -- the data names are English: the macro finds the rare only in the English client
        action = GetLocale() == "enUS" and { kind = "macro", value = "/targetexact " .. entry.name } or nil }
end
ns.RegisterPush({
    key = "rare", label = L["A rare nearby"], level = ns.push.ALERT, ownBudget = true,
    done = function(c, at)
        local id = c.entry and c.entry.npcID
        return id ~= nil and (targetedAt[id] or 0) >= at
    end,
    states = { "rec:rare" },
    candidates = function(add)
        for npcID in pairs(ns.RaresSeen()) do
            local entry = D.NPCByID(npcID)
            if entry then
                local c = RareMessage(entry)
                c.big, c.missable, c.sure = { true, "rare" }, { true, "seen now" }, { true, "seen" }
                add(c)
            end
        end
    end,
    example = function()
        local entry = Random(D.Entries("npcs"), function(e) return e.npcRank == 4 and e.levelMax > 0 end)
        return entry and RareMessage(entry)
    end,
})

-- the test buttons: a random kind that has data
local function Example(level)
    local kinds = {}
    for _, rule in ipairs(ns.push.rules) do
        if rule.example then kinds[#kinds + 1] = rule end
    end
    local start = math.random(#kinds)
    for i = 0, #kinds - 1 do
        local rule = kinds[(start + i - 1) % #kinds + 1]
        local c = rule.example()
        if c then return ns.push.Sample(level, rule, c) end
    end
    ns.push.Sample(level) -- the data is not built yet: the plain test message
end

-- Options (Core\Options.lua puts the page entry on the page): the subpage "Nudges" with the master switch, one row per
-- kind of nudge with the level it may show at, the sound and the test buttons. "Never for this" on a message sets its
-- rule to off.
local rows = {}
local function Silence(on)
    if on then return end
    ns.push.Interrupt()
    wipe(ns.push.quiet)
    ns.push.QuietChanged()
end
rows[#rows + 1] = { type = "checkbox", key = "push",
    label = L["Show me hints when something important comes up"], default = true, onChange = Silence,
    tooltip = L["Speaks up by itself, rarely: only when something is worth a lot, may be missed now, rests on " ..
        "sure facts and is new to you, and only in a pause (not in a fight)."] }
rows[#rows + 1] = { type = "text", height = 70,
    text = L["Off: never. Quiet: the minimap button glows and the tab gets a dot. Note: a short message by the " ..
        "minimap. Alert: the same message with a sound. A kind you keep waving away becomes quieter by itself, " ..
        "never beyond the level you set, and comes back when you act on it or press the check."] }
rows[#rows + 1] = { type = "header", label = L["Which hints, and how"] }
local STYLES = { { "off", L["Off"] }, { "quiet", L["Quiet"] }, { "note", L["Note"] }, { "alert", L["Alert"] } }
local DEFAULT_OF = { [ns.push.QUIET] = "quiet", [ns.push.MEDIUM] = "note", [ns.push.ALERT] = "alert" }
for _, rule in ipairs(ns.push.rules) do
    local key = rule.key
    rows[#rows + 1] = { type = "dropdown", key = "nudge_" .. key, label = rule.label, values = STYLES,
        default = DEFAULT_OF[rule.level], dependsOn = "push", enabledWhen = true,
        onChange = function(style)
            ns.push.Interrupt() -- a message on screen goes
            if style == "off" then
                for situation, q in pairs(ns.push.quiet) do
                    if q.rule == key then ns.push.quiet[situation] = nil end
                end
                ns.push.QuietChanged()
            end
        end }
end
rows[#rows + 1] = { type = "checkbox", key = "pushSound", label = L["Sound with alerts"], default = true,
    dependsOn = "push", enabledWhen = true,
    tooltip = L["An alert plays a sound with its message."] }
rows[#rows + 1] = { type = "header", label = L["Try the hints"] }
-- the glow lasts a few seconds, the message fades as usual (Toast.lua Sample)
rows[#rows + 1] = { type = "button", label = L["Quiet: the button glows"], text = L["Test"], dependsOn = "push",
    enabledWhen = true, func = function() Example(ns.push.QUIET) end }
rows[#rows + 1] = { type = "button", label = L["Note: a short message"], text = L["Test"], dependsOn = "push",
    enabledWhen = true, func = function() Example(ns.push.MEDIUM) end }
rows[#rows + 1] = { type = "button", label = L["Alert: with a sound"], text = L["Test"], dependsOn = "push",
    enabledWhen = true, tooltip = L["Plays the sound too, if it is switched on above."],
    func = function() Example(ns.push.ALERT) end }
ns.rows.nudges = { type = "page", label = L["Hints"], entries = rows }

ns.push.Start()
