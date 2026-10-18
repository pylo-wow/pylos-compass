local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Trains you: a trainer of your class or one of your professions (D.npcTrainers, Data\NPCFacts.lua: what the 1.12 data
-- says it teaches; titles alone missed "Journeyman Leatherworker" and "Cook"). Strong when it has something new for you
-- (spells you can learn now, or recipes), more the more it has. Your trainer of each kind (the nearest, reach.Trainer)
-- is always at least "here" away; "Don't suggest" hides one until something new comes up (renew: the spells' IDs, so
-- one learned does not bring him back). Other trainers of the same kind count by their own way there; a list shows one
-- per errand (Relevant.lua). Without anything new no reason at all.
-- What you can pay counts (D.TrainingCost, cheapest first; a cost not known counts as paid): the strength by those;
-- none: out of reach for now, as an item you cannot pay.
-- Shown as a suggestion, his spells wait with him (offers, Learning.lua): learned, or passed at his window
-- (Learning\Declined.lua). The row shows your class symbol or the profession's.

local classID, classFile, ranks = 0, "WARRIOR", {}
local pending = {} -- class ID or skill line -> { count, spell IDs (sorted), names, affordable, cheapest }; per search
local NAMES = 5     -- spell names its tooltip lists

-- "class" or "profession", and what it teaches; nil if not yours
local function Trains(entry)
    local teaches = D.npcTrainers and D.npcTrainers[entry.npcID]
    if not teaches then return nil end
    if teaches < 100 then return teaches == classID and "class" or nil, teaches end
    return ranks[teaches] ~= nil and "profession" or nil, teaches
end

-- what a trainer of yours could teach you now: count, spell IDs (sorted),
-- the first names (A-Z), how many of them you can pay, the cheapest cost
local function Pending(kind, teaches)
    local known = pending[teaches]
    if known then return known[1], known[2], known[3], known[4], known[5] end
    local count, ids, names, costs = 0, {}, {}, {}
    for _, entry in ipairs(D.Entries(kind == "class" and "spells" or "professions")) do
        local fits = kind == "class" and entry.trainLevel ~= nil
            or (entry.skillLine == teaches and (entry.recipeItem or 0) == 0)
        if fits and entry.hidden and ns.reasons.Test("learnable", entry) then
            count = count + 1
            ids[#ids + 1] = entry.spellID or 0
            names[#names + 1] = entry.name
            costs[#costs + 1] = entry.spellID and D.TrainingCost and D.TrainingCost(entry.spellID) or 0
        end
    end
    table.sort(ids)
    table.sort(names)
    table.sort(costs)
    local money, affordable, spent = GetMoney and GetMoney() or math.huge, 0, 0
    for _, cost in ipairs(costs) do
        if spent + cost > money then break end
        spent, affordable = spent + cost, affordable + 1
    end
    pending[teaches] = { count, ids, names, affordable, costs[1] }
    return count, ids, names, affordable, costs[1]
end

local function Yours(entry, teaches)
    return ns.reach.Trainer(teaches) == entry
end

ns.RegisterReason({
    key = "trainsYou",
    -- weight 1.1: new spells or recipes are progress you only need to go and get, a little above an upgrade of the same size
    stage = "progress", weight = 1.1, label = "Trains you",
    sources = { "npcs" },
    -- what he can teach: Learnable.lua's states (which one is yours is his reach, computed each time)
    depends = { "spells", "level", "skills", "bags", "npcs", "money", "data" },
    topic = function(entry) return Trains(entry) == "class" and "class" or "professions" end,
    prepare = function()
        classFile, classID = select(2, UnitClass("player"))
        classFile, classID = classFile or "WARRIOR", classID or 0
        ranks = D.ProfessionRanks()
        wipe(pending)
    end,
    test = function(entry)
        local kind, teaches = Trains(entry)
        if not kind then return nil end
        local count, _, _, affordable = Pending(kind, teaches)
        -- nothing new: no reason (a trace would mark trainers with nothing to teach, e.g. your trainer in the Class tab)
        if count == 0 then return nil end
        -- more the more it has that you can pay, flattening (1 spell 1, 2:
        -- 1.5, 4: 2); none you can pay: as many, out of reach (below)
        return ns.reasons.Grow(affordable > 0 and affordable or count, 1)
    end,
    reach = function(entry)
        local kind, teaches = Trains(entry)
        local _, _, _, affordable, cheapest = Pending(kind, teaches)
        if affordable == 0 then
            return ns.reach.LUCK + 0.01, L["training costs %s, more than you have"]:format(D.Money(cheapest))
        end
        local factor, words = ns.reach.NPC(entry)
        if Yours(entry, teaches) then factor = math.max(factor, ns.reach.HERE) end
        return factor, words
    end,
    -- how many of his spells you can pay (the nudge, Pushes.lua)
    affordable = function(entry)
        local kind, teaches = Trains(entry)
        if not kind then return 0 end
        local _, _, _, affordable = Pending(kind, teaches)
        return affordable
    end,
    profession = function(entry) return Trains(entry) == "profession" end,
    renew = function(entry)
        local kind, teaches = Trains(entry)
        local _, ids = Pending(kind, teaches)
        return ids
    end,
    -- his spells: they wait to be learned with him (Learning.lua)
    offers = function(entry)
        local kind, teaches = Trains(entry)
        local _, ids = Pending(kind, teaches)
        local list = {}
        for i, id in ipairs(ids) do list[i] = "s:" .. id end
        return list
    end,
    note = function(entry)
        local kind, teaches = Trains(entry)
        local count, _, names = Pending(kind, teaches)
        local icon = kind == "class" and ("Interface\\Icons\\ClassIcon_" .. classFile)
            or D.professionIcons and D.professionIcons[teaches] or "Interface\\Icons\\INV_Misc_Book_09"
        local tip
        if count > 0 then
            if count == 1 then
                tip = kind == "class" and L["Can teach you a new spell"] or L["Can teach you a new recipe"]
            else
                tip = (kind == "class" and L["Can teach you %d new spells"] or L["Can teach you %d new recipes"]):format(count)
            end
            tip = tip .. ": " .. table.concat(names, ", ", 1, math.min(#names, NAMES)) .. (#names > NAMES and ", ..." or "")
        else
            tip = kind == "class" and L["Trains your class"] or L["Trains one of your professions"]
        end
        return { icon = icon, count = count > 0 and count or nil, tip = tip }
    end,
})
