local _, D = ...

-- Spells: active spell book spells, professions included, each once in its highest rank, plus
-- the trainer's not-yet-learned spells (hidden = true; hosts show them only on purpose).
-- Small: built at once behind the loading screen.

local KEY = "spells"

-- The three talent trees of each class in the game's order (classic; GetSpecialization is nil
-- in Forever and the Paladin's third tree is Retribution, both seen in game).
-- Your tree: D.PlayerSpec (You\Character.lua).
D.TALENT_TREES = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}

-- Spell book tabs (General, Holy, Protection, ...): { name, icon }, in book order; read with its spells
local bookTabs = {}

-- Tabs as last read (with the spells: a build or a check); shared list, do not change
function D.SpellBookTabs() return bookTabs end

function D.SpellKnown(spellID)
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID))
        or (IsSpellKnown ~= nil and IsSpellKnown(spellID))
end
local Known = D.SpellKnown

function D.SpellPassive(spellID)
    if C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(spellID) end
    return IsPassiveSpell ~= nil and IsPassiveSpell(spellID)
end

local function SpellBookEntries(list)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local meta = D.Meta(KEY)
    local bank, seen = Enum.SpellBookSpellBank.Player, {}
    wipe(bookTabs)
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide then
            -- first tab (General) shows the class icon, as in the game's spell book (the client
            -- returns a book icon again)
            local icon = info.iconID
            if #bookTabs == 0 then icon = "Interface\\Icons\\ClassIcon_" .. select(2, UnitClass("player")) end
            bookTabs[#bookTabs + 1] = { name = info.name, icon = icon }
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local lowRank = C_SpellBook.IsSpellBookItemLowRank and C_SpellBook.IsSpellBookItemLowRank(slot, bank)
                if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID and not lowRank
                    and not item.isPassive and not item.isOffSpec and not seen[item.name] then
                    seen[item.name] = true
                    list[#list + 1] = setmetatable({
                        name = item.name, icon = item.iconID or C_Spell.GetSpellTexture(item.spellID),
                        category = info.name, spellID = item.spellID, tab = info.name,
                    }, meta)
                end
            end
        end
    end
end

-- Unlearned trainer spells of your class (Data\ClassSpells.lua), hidden: only a filter like
-- "Available" shows them. Ranks are counted per name in level order; each rank knows the one
-- before it (a talent's later ranks need the talent). Race matters only for racial spells.
local function TrainerEntries(list)
    local _, classFile, classID = UnitClass("player")
    local data = D.classSpells and D.classSpells[classFile]
    if not data then return end
    local meta = D.Meta(KEY)
    -- race mask bit by arithmetic: Forever's Skyborne races (95, 96) have bits 32 and 33
    -- (ChrRaces.PlayableRaceBit), beyond bit.band's 32 bits; races 1-8 have bit raceID - 1
    local raceID = select(3, UnitRace("player")) or 1
    local raceBit = 2 ^ (raceID == 95 and 32 or raceID == 96 and 33 or raceID - 1)
    local function HasRace(mask) return math.floor(mask / raceBit) % 2 == 1 end
    local byName = {}
    for i = 1, #data, 5 do
        local id, level, race = data[i], data[i + 1], data[i + 2]
        -- the level a trainer was seen to ask wins (World\LearnTrainers.lua)
        level = D.TrainingLevel and D.TrainingLevel(id) or level
        local name = C_Spell.GetSpellName(id)
        if name and (race == 0 or HasRace(race)) then
            -- spell book tab = its skill line's name
            local line = D.classSkillLines and D.classSkillLines[data[i + 4]]
            byName[name] = byName[name] or {}
            table.insert(byName[name], { id = id, level = level, talent = data[i + 3] == 1, tab = line })
        end
    end
    for name, spells in pairs(byName) do
        table.sort(spells, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.id < b.id
        end)
        -- one rank per level: some ranks have several IDs (Fireball 60 twice); learned if any is
        local ranks = {}
        for _, spell in ipairs(spells) do
            local last = ranks[#ranks]
            if last and last.level == spell.level then
                last.known = last.known or Known(spell.id)
                last.talent = last.talent and spell.talent
            else
                spell.known = Known(spell.id)
                ranks[#ranks + 1] = spell
            end
        end
        -- nothing below the highest learned rank's level is offered
        local learnedLevel = 0
        for _, rank in ipairs(ranks) do
            if rank.known then learnedLevel = rank.level end
        end
        for i, rank in ipairs(ranks) do
            -- What your class's trainers were seen to list decides (World\LearnTrainers.lua): they
            -- teach a few level 1 spells (Battle Shout, Stealth, ...) and passives (Safe Fall,
            -- Omen of Clarity, ...), and not everything in the data.
            -- Before a trainer was seen: WhatsTraining's list of what Forever's trainers teach
            -- (Data\ClassSpells.lua, D.trainCosts; quest-given spells are not in it). Without it:
            -- no level 1 (known from the start; what remains are talent effects) and no passives
            -- (stances and forms come with them); talents come from the talent tree
            local listed = D.TrainerListed and D.TrainerListed(rank.id, classID)
            local offered = listed
            if listed == nil and D.trainCosts and #D.trainCosts > 0 then
                offered = D.TrainingCost(rank.id) ~= nil
            elseif listed == nil then
                offered = rank.level > 1 and not D.SpellPassive(rank.id)
            end
            if not rank.known and not rank.talent and rank.level > learnedLevel and offered then
                local category = ("Level %d"):format(rank.level)
                if #ranks > 1 then category = category .. "  ·  " .. ("Rank %d"):format(i) end
                list[#list + 1] = setmetatable({
                    name = name, icon = C_Spell.GetSpellTexture(rank.id), spellID = rank.id,
                    category = category, hidden = true, tab = rank.tab,
                    -- previous rank learned (any of its IDs), known at build; learning a spell rebuilds the list
                    trainLevel = rank.level, previousLearned = i == 1 or ranks[i - 1].known,
                    rankNumber = #ranks > 1 and i or nil,
                }, meta)
            end
        end
    end
end

-- Can a trainer teach you this spell now: your level reaches its trainer level and the rank
-- before it is learned (a talent's later ranks need the talent)
function D.SpellLearnableNow(entry)
    if not entry.hidden or not entry.trainLevel then return false end
    local level = D.TrainingLevel and D.TrainingLevel(entry.spellID) or entry.trainLevel
    if level > UnitLevel("player") then return false end
    return entry.previousLearned and true or false
end

D.RegisterDomain({
    key = KEY,
    collect = function(list)
        SpellBookEntries(list)
        TrainerEntries(list)
    end,
    events = { "SPELLS_CHANGED" },
    -- SPELLS_CHANGED also fires when nothing changed (right after the loading screen, seen in
    -- game): rebuild only when the spell IDs differ
    signature = function()
        local list = {}
        SpellBookEntries(list)
        for i, entry in ipairs(list) do list[i] = entry.spellID end
        return table.concat(list, ",")
    end,
})
