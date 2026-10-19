local _, D = ...

-- What a trainer teaches, from its window (any state: available, too high, known), gathered
-- over visits; it beats the 1.12 data, whose trainers differ from Forever's.
-- PylosCompassWorldDB.npcs[npcID].teaches = "spellID,..." (LearnNPCs.lua), teachesFull = true once the
-- whole list was read. A filtered window lists only part, so the scan turns every filter on
-- (available, unavailable, used), reads, and restores them (SetTrainerServiceTypeFilter); once
-- per visit, since setting a filter fires TRAINER_UPDATE again.
-- A service's spell is C_TooltipInfo.GetTrainerService(i).id (as WhatsTraining reads it).
-- What a service asks, the same for every trainer:
-- PylosCompassWorldDB.training[spellID] = { level = level asked (GetTrainerServiceInfo's 4th value),
-- skill = skill rank asked (GetTrainerServiceSkillReq; the client data lacks it for profession
-- recipes), cost = copper without discount }. Cost is noted only when the trainer gives no
-- discount: standing below honored (10 % off from honored; PvP rank discounts are not told
-- apart). Seen beats the data (D.trainCosts from WhatsTraining, Data\ClassSpells.lua).

-- Class or profession a trainer teaches, taken from where most of its spells belong
-- (Data\ClassSpells.lua, ProfessionSpells.lua). Beats the 1.12 data's D.npcTrainers and covers
-- trainers new in Forever (which have no 1.12 data).
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
    MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11 }
local spellTeaches -- spell ID -> class ID or skill line, made on the first trainer
local function TeachesOf(list)
    if not spellTeaches then
        spellTeaches = {}
        for class, spells in pairs(D.classSpells or {}) do
            for i = 1, #spells, 5 do spellTeaches[spells[i]] = CLASS_IDS[class] end
        end
        for skillLine, spells in pairs(D.professionSpells or {}) do
            for i = 1, #spells, 5 do spellTeaches[spells[i]] = spellTeaches[spells[i]] or skillLine end
        end
    end
    local votes, best = {}, nil
    for spell in list:gmatch("%d+") do
        local what = spellTeaches[tonumber(spell)]
        if what then
            votes[what] = (votes[what] or 0) + 1
            if not best or votes[what] > votes[best] then best = what end
        end
    end
    return best
end

-- D.trainerListed[teaches] = { spellID = true }: spells listed by trainers seen for a class
-- (class ID) or profession (skill line, D.npcTrainers)
D.trainerListed = {}
local function ApplyTeaches(npcID, learned)
    if not (learned.teaches and learned.teachesFull) then return end
    local teaches = TeachesOf(learned.teaches) or D.npcTrainers[npcID]
    if not teaches then return end
    D.npcTrainers[npcID] = teaches
    local listed = D.trainerListed[teaches] or {}
    D.trainerListed[teaches] = listed
    for spell in learned.teaches:gmatch("%d+") do listed[tonumber(spell)] = true end
end

D.OnLoaded(function()
    for npcID, learned in pairs(D.world.npcs) do ApplyTeaches(npcID, learned) end
end)

local FILTERS = { "available", "unavailable", "used" }
local HONORED = 6 -- UnitReaction: a trainer gives a discount from here

local toggled = false -- the filters were set this visit (TRAINER_SHOW starts a visit)

-- Runs fn() with every trainer filter on, then restores them (also after an error in fn, which is raised again);
-- false if a filter stays off (cannot be set, or already set once this visit)
local function Unfiltered(fn)
    if not GetTrainerServiceTypeFilter then fn() return true end
    local off = {} -- the filters that were off: set off again at the end
    for _, kind in ipairs(FILTERS) do
        if not GetTrainerServiceTypeFilter(kind) then off[#off + 1] = kind end
    end
    if #off > 0 then
        if toggled or not SetTrainerServiceTypeFilter then return false end
        toggled = true
    end
    for _, kind in ipairs(off) do SetTrainerServiceTypeFilter(kind, true) end
    local all, ok, err = true, true, nil
    for _, kind in ipairs(FILTERS) do
        if not GetTrainerServiceTypeFilter(kind) then all = false break end
    end
    if all then ok, err = pcall(fn) end
    for _, kind in ipairs(off) do SetTrainerServiceTypeFilter(kind, false) end
    if not ok then error(err, 0) end
    return all
end

-- the spell book's hidden "Available" entries are made from what trainers listed and asked (World\Spells.lua)
local function RebuildSpells()
    if D.Built("spells") then D.Rebuild("spells") end
end

local function NoteService(index, spellID, discount)
    local _, _, _, level = GetTrainerServiceInfo(index)
    local skill, hasSkill
    if GetTrainerServiceSkillReq then skill, hasSkill = select(2, GetTrainerServiceSkillReq(index)) end
    local cost = not discount and GetTrainerServiceCost and GetTrainerServiceCost(index) or nil
    if D.Secret(level) or D.Secret(skill) or D.Secret(cost) then return false end
    local known = D.world.training[spellID] or {}
    local changed = false
    local function Set(key, value)
        if value ~= nil and known[key] ~= value then known[key], changed = value, true end
    end
    Set("level", level and level > 0 and level or nil)
    Set("skill", hasSkill and skill and skill > 0 and skill or nil)
    Set("cost", cost)
    if changed then D.world.training[spellID] = known end
    return changed
end

local scanning = false -- the scan's filter changes fire TRAINER_UPDATE

local function NoteTeaches(event)
    if event == "TRAINER_SHOW" then toggled = false end
    if scanning or not D.world or InCombatLockdown() then return end
    if not (GetNumTrainerServices and GetTrainerServiceInfo and C_TooltipInfo
            and C_TooltipInfo.GetTrainerService) then
        return
    end
    local npcID = D.NPCOf("npc")
    local learned = D.NoteNPC(npcID)
    if not learned then return end
    local reaction = UnitReaction("npc", "player")
    local discount = D.Secret(reaction) or not reaction or reaction >= HONORED
    local spells, added, costs = {}, false, false
    for spell in (learned.teaches or ""):gmatch("%d+") do spells[tonumber(spell)] = true end
    scanning = true
    local ran, whole = pcall(Unfiltered, function()
        for index = 1, GetNumTrainerServices() or 0 do
            local data = C_TooltipInfo.GetTrainerService(index)
            local spellID = data and data.id
            if not D.Secret(spellID) and spellID then
                if not spells[spellID] then spells[spellID], added = true, true end
                if NoteService(index, spellID, discount) then costs = true end
            end
        end
    end)
    scanning = false
    if not ran then geterrorhandler()(whole) return end -- an error must not keep the scan off for the session
    if not whole then return end
    if not added and learned.teachesFull then
        if costs then
            D.BumpState("npcs")
            RebuildSpells()
        end
        return
    end
    local list = {}
    for spellID in pairs(spells) do list[#list + 1] = spellID end
    table.sort(list)
    learned.teaches, learned.teachesFull = table.concat(list, ","), true
    ApplyTeaches(npcID, learned)
    D.BumpState("npcs")
    RebuildSpells()
end
D.On("TRAINER_SHOW", NoteTeaches)
D.On("TRAINER_UPDATE", NoteTeaches)

-- Does a trainer teach the spell: true/false if trainers of that class (class ID) or
-- profession (skill line) were seen, nil if none (then only the 1.12 data can tell)
function D.TrainerListed(spellID, teaches)
    local listed = D.trainerListed[teaches]
    if not listed then return nil end
    return listed[spellID] == true
end

-- What a trainer asks for a spell or recipe, as seen; nil if not seen.
-- TrainingLevel: level; TrainingSkill: skill rank.
function D.TrainingLevel(spellID)
    local known = D.world and D.world.training and D.world.training[spellID]
    return known and known.level or nil
end
function D.TrainingSkill(spellID)
    local known = D.world and D.world.training and D.world.training[spellID]
    return known and known.skill or nil
end

-- Cost in copper without discount: as seen, else D.trainCosts (WhatsTraining; pairs spell ID,
-- copper); nil if unknown
local dataCosts
function D.TrainingCost(spellID)
    local known = D.world and D.world.training and D.world.training[spellID]
    if known and known.cost then return known.cost end
    if not dataCosts then
        dataCosts = {}
        local list = D.trainCosts or {}
        for i = 1, #list, 2 do dataCosts[list[i]] = list[i + 1] end
    end
    return dataCosts[spellID]
end
