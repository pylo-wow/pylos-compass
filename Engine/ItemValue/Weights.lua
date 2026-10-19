local _, D = ...
if D.off then return end
local ns = D.engine

-- Stat weights of the item valuer (Value.lua): per class and talent tree (in the game's classic order), one table for
-- leveling and one for the end game (level 60): what one point of a stat is worth against the main stat (1).
-- Own values, from the classic formulas and usual guide values:
--   * conversions: a warrior's Strength is 2 attack power, 20 Agility 1 % crit at 60; a rogue's Agility 1 AP and crit;
--     a hunter's Agility ranged AP and crit; casters' Intellect mana and spell crit
--   * leveling: Stamina and Spirit (regeneration between fights) count more, hit less (small cap), a good weapon a lot
--   * HIT, CRIT, SPELLHIT, SPELLCRIT are per percent point; HIT, SPELLHIT and DEF have caps (Value.lua), above which
--     they count little or nothing
--   * DPS: a melee weapon's damage per second (main hand; the off hand counts half for dual wielders), RDPS: the ranged
--     slot's (bow, gun, wand); druids fight in forms: their weapon's damage counts nothing
-- Keys: those of D.ItemStats, plus DPS and RDPS. An addon can let the player change each table (Value.lua: UseSettings)

local WEIGHTS = {}
ns.ITEM_WEIGHTS = WEIGHTS

-- a few shared shapes, adjusted per spec below
local function Melee(t)
    local base = { STA = 0.3, ARMOR = 0.01, HP5 = 0.5, RDPS = 0.5 }
    for k, v in pairs(t) do base[k] = v end
    return base
end
local function Caster(t)
    local base = { STA = 0.3, ARMOR = 0.003, RDPS = 0.3 }
    for k, v in pairs(t) do base[k] = v end
    return base
end

-- Warrior
WEIGHTS.WARRIOR = {
    { -- Arms
        leveling = Melee({ STR = 1, AGI = 0.6, STA = 0.5, AP = 0.5, CRIT = 10, HIT = 7, DPS = 9, ARMOR = 0.02,
            SPI = 0.1 }),
        endgame = Melee({ STR = 1, AGI = 0.7, AP = 0.5, CRIT = 13, HIT = 15, DPS = 8 }),
    },
    { -- Fury
        leveling = Melee({ STR = 1, AGI = 0.6, STA = 0.5, AP = 0.5, CRIT = 10, HIT = 8, DPS = 8, ARMOR = 0.02,
            SPI = 0.1 }),
        endgame = Melee({ STR = 1, AGI = 0.75, AP = 0.5, CRIT = 13, HIT = 16, DPS = 7 }),
    },
    { -- Protection
        leveling = Melee({ STR = 0.8, STA = 1, AGI = 0.5, AP = 0.3, ARMOR = 0.05, DEF = 0.8, DODGE = 10, PARRY = 8,
            BLOCK = 5, BLOCKVALUE = 0.3, CRIT = 5, HIT = 6, DPS = 5 }),
        endgame = Melee({ STA = 1, DEF = 1.5, ARMOR = 0.1, DODGE = 15, PARRY = 13, BLOCK = 6, BLOCKVALUE = 0.4,
            AGI = 0.6, STR = 0.5, AP = 0.15, HIT = 5, CRIT = 3, DPS = 2 }),
    },
}

-- Paladin
WEIGHTS.PALADIN = {
    { -- Holy
        leveling = Caster({ INT = 1, STA = 0.6, SPI = 0.4, HEAL = 0.6, SP = 0.6, SP_HOLY = 0.6, MP5 = 1.5,
            SPELLCRIT = 6, STR = 0.4, DPS = 3 }),
        endgame = Caster({ INT = 1, HEAL = 0.7, SP = 0.7, SP_HOLY = 0.2, MP5 = 1.8, SPELLCRIT = 9, SPI = 0.2 }),
    },
    { -- Protection
        leveling = Melee({ STA = 1, STR = 0.7, INT = 0.4, ARMOR = 0.05, DEF = 0.8, SP = 0.4, SP_HOLY = 0.4,
            BLOCKVALUE = 0.4, BLOCK = 5, DODGE = 10, PARRY = 8, AGI = 0.4, DPS = 4 }),
        endgame = Melee({ STA = 1, DEF = 1.2, ARMOR = 0.08, SP = 0.5, SP_HOLY = 0.5, BLOCKVALUE = 0.5, BLOCK = 5,
            DODGE = 12, PARRY = 10, INT = 0.4, STR = 0.3, AGI = 0.4, SPELLHIT = 3, DPS = 1 }),
    },
    { -- Retribution
        leveling = Melee({ STR = 1, STA = 0.5, INT = 0.3, AGI = 0.5, AP = 0.5, CRIT = 8, HIT = 6, DPS = 9,
            ARMOR = 0.02, SPI = 0.2, MP5 = 0.5 }),
        endgame = Melee({ STR = 1, AGI = 0.6, AP = 0.5, CRIT = 11, HIT = 12, INT = 0.3, SP = 0.2, SP_HOLY = 0.2,
            MP5 = 0.5, DPS = 8 }),
    },
}

-- Hunter
local function Hunter(leveling, agi)
    if leveling then
        return Melee({ AGI = 1, STA = 0.5, INT = 0.4, SPI = 0.2, RAP = 0.5, CRIT = 10 * agi, HIT = 6, RDPS = 14,
            DPS = 0.5, AP = 0.05, STR = 0.05, MP5 = 0.6 })
    end
    return Melee({ AGI = 1, RAP = 0.45, CRIT = 15 * agi, HIT = 15, INT = 0.4, STA = 0.3, MP5 = 1, RDPS = 12,
        DPS = 0.5, AP = 0.05, STR = 0.05 })
end
WEIGHTS.HUNTER = {
    { leveling = Hunter(true, 1), endgame = Hunter(false, 1) },      -- Beast Mastery
    { leveling = Hunter(true, 1), endgame = Hunter(false, 1.05) },   -- Marksmanship
    { leveling = Hunter(true, 1.1), endgame = Hunter(false, 1.1) },  -- Survival (Lightning Reflexes: more from Agility)
}

-- Rogue
local function Rogue(leveling, crit)
    if leveling then
        return Melee({ AGI = 1, STR = 0.5, STA = 0.5, AP = 0.45, CRIT = 8 * crit, HIT = 7, DPS = 8, ARMOR = 0.02 })
    end
    return Melee({ AGI = 1, STR = 0.45, AP = 0.45, CRIT = 10 * crit, HIT = 14, STA = 0.25, DPS = 6 })
end
WEIGHTS.ROGUE = {
    { leveling = Rogue(true, 1), endgame = Rogue(false, 1.1) },   -- Assassination
    { leveling = Rogue(true, 1), endgame = Rogue(false, 1) },     -- Combat
    { leveling = Rogue(true, 1), endgame = Rogue(false, 1) },     -- Subtlety
}

-- Priest
local PRIEST_LEVEL = Caster({ INT = 0.8, SPI = 1, STA = 0.6, SP = 0.6, SP_SHADOW = 0.6, HEAL = 0.2, MP5 = 0.6,
    SPELLCRIT = 3, SPELLHIT = 4, RDPS = 3 })
WEIGHTS.PRIEST = {
    { -- Discipline
        leveling = PRIEST_LEVEL,
        endgame = Caster({ INT = 1, SPI = 0.6, HEAL = 0.75, SP = 0.75, MP5 = 2, SPELLCRIT = 6 }),
    },
    { -- Holy
        leveling = PRIEST_LEVEL,
        endgame = Caster({ INT = 0.9, SPI = 0.8, HEAL = 0.8, SP = 0.8, MP5 = 2, SPELLCRIT = 6 }),
    },
    { -- Shadow
        leveling = Caster({ SP = 1, SP_SHADOW = 1, SPI = 0.8, INT = 0.6, STA = 0.6, MP5 = 0.6, SPELLHIT = 5,
            SPELLCRIT = 2, RDPS = 3 }),
        endgame = Caster({ SP = 1, SP_SHADOW = 1, INT = 0.4, SPI = 0.3, SPELLHIT = 12, SPELLCRIT = 3, STA = 0.4,
            MP5 = 1 }),
    },
}

-- Shaman
WEIGHTS.SHAMAN = {
    { -- Elemental
        leveling = Caster({ SP = 1, SP_NATURE = 0.9, SP_FIRE = 0.2, INT = 0.6, STA = 0.5, SPI = 0.3, MP5 = 1,
            SPELLCRIT = 6, SPELLHIT = 5 }),
        endgame = Caster({ SP = 1, SP_NATURE = 0.9, SP_FIRE = 0.2, INT = 0.4, SPELLCRIT = 10, SPELLHIT = 12,
            MP5 = 1, SPI = 0.1 }),
    },
    { -- Enhancement
        leveling = Melee({ STR = 1, AGI = 0.5, STA = 0.5, INT = 0.4, AP = 0.5, CRIT = 8, HIT = 6, DPS = 9,
            SPI = 0.2, MP5 = 0.6 }),
        endgame = Melee({ STR = 1, AGI = 0.7, AP = 0.5, CRIT = 11, HIT = 12, INT = 0.3, SP = 0.1, DPS = 8 }),
    },
    { -- Restoration
        leveling = Caster({ INT = 1, STA = 0.5, SPI = 0.4, HEAL = 0.6, SP = 0.6, MP5 = 1.5, SPELLCRIT = 4,
            STR = 0.3, DPS = 3 }),
        endgame = Caster({ HEAL = 1, SP = 1, INT = 0.7, MP5 = 2, SPELLCRIT = 6, SPI = 0.2 }),
    },
}

-- Mage
local function Mage(school, level, crit)
    local t
    if level then
        t = Caster({ SP = 1, INT = 0.7, SPI = 0.6, STA = 0.6, MP5 = 1, SPELLCRIT = 6 * crit, SPELLHIT = 5, RDPS = 2 })
    else
        t = Caster({ SP = 1, INT = 0.45, SPI = 0.2, SPELLCRIT = 10 * crit, SPELLHIT = 13, MP5 = 0.8 })
    end
    for _, s in ipairs({ "SP_FIRE", "SP_FROST", "SP_ARCANE" }) do t[s] = s == school and 1 or 0.2 end
    return t
end
WEIGHTS.MAGE = {
    { leveling = Mage("SP_ARCANE", true, 1), endgame = Mage("SP_ARCANE", false, 1) },
    { leveling = Mage("SP_FIRE", true, 1.1), endgame = Mage("SP_FIRE", false, 1.2) },
    { leveling = Mage("SP_FROST", true, 0.9), endgame = Mage("SP_FROST", false, 0.9) },
}
WEIGHTS.MAGE[1].endgame.SPI = 0.4 -- Arcane Meditation

-- Warlock
local WARLOCK_LEVEL = Caster({ SP = 1, SP_SHADOW = 0.9, SP_FIRE = 0.2, STA = 0.8, SPI = 0.4, INT = 0.5, MP5 = 0.6,
    SPELLHIT = 5, SPELLCRIT = 3, RDPS = 2 })
WEIGHTS.WARLOCK = {
    { -- Affliction
        leveling = WARLOCK_LEVEL,
        endgame = Caster({ SP = 1, SP_SHADOW = 1, SP_FIRE = 0.1, INT = 0.3, STA = 0.5, SPELLHIT = 13, SPELLCRIT = 3,
            SPI = 0.1, MP5 = 0.5 }),
    },
    { -- Demonology
        leveling = WARLOCK_LEVEL,
        endgame = Caster({ SP = 1, SP_SHADOW = 0.9, SP_FIRE = 0.3, STA = 0.6, INT = 0.4, SPELLHIT = 12,
            SPELLCRIT = 6 }),
    },
    { -- Destruction
        leveling = WARLOCK_LEVEL,
        endgame = Caster({ SP = 1, SP_SHADOW = 1, SP_FIRE = 0.4, INT = 0.3, SPELLCRIT = 11, SPELLHIT = 13, STA = 0.4 }),
    },
}

-- Druid
WEIGHTS.DRUID = {
    { -- Balance
        leveling = Caster({ SP = 1, SP_ARCANE = 0.7, SP_NATURE = 0.6, INT = 0.6, SPI = 0.5, STA = 0.5, MP5 = 1,
            SPELLCRIT = 6, SPELLHIT = 5, RDPS = 0 }),
        endgame = Caster({ SP = 1, SP_ARCANE = 0.7, SP_NATURE = 0.6, INT = 0.5, SPELLCRIT = 9, SPELLHIT = 12,
            MP5 = 1, SPI = 0.3, RDPS = 0 }),
    },
    { -- Feral Combat (forms: the weapon's damage counts nothing)
        leveling = Melee({ STR = 1, AGI = 0.9, STA = 0.6, AP = 0.5, CRIT = 8, HIT = 5, ARMOR = 0.03, INT = 0.2,
            SPI = 0.3, DPS = 0, RDPS = 0 }),
        endgame = Melee({ AGI = 1, STR = 1.2, AP = 0.6, CRIT = 12, HIT = 12, STA = 0.5, ARMOR = 0.03, DEF = 0.5,
            DODGE = 6, DPS = 0, RDPS = 0 }),
    },
    { -- Restoration
        leveling = Caster({ INT = 1, SPI = 0.6, STA = 0.5, HEAL = 0.6, SP = 0.6, MP5 = 1.5, SPELLCRIT = 4, RDPS = 0 }),
        endgame = Caster({ HEAL = 1, SP = 1, INT = 0.7, SPI = 0.6, MP5 = 2, SPELLCRIT = 4, RDPS = 0 }),
    },
}

-- Spell damage only (SPDMG: Forever's "damage done by up to X", apart from healing): worth what spell power is to a
-- damage dealer; next to nothing to a healer (healing weighed as much as spell power)
for _, trees in pairs(WEIGHTS) do
    for _, tree in ipairs(trees) do
        for _, t in pairs(tree) do
            if t.SPDMG == nil and t.SP then
                local healer = (t.HEAL or 0) >= 0.9 * t.SP
                t.SPDMG = healer and 0.1 * t.SP or t.SP
            end
        end
    end
end

-- Before talents (below level 10, or no talent data): the class's leveling
-- table of the tree most players take while leveling
ns.ITEM_WEIGHTS_DEFAULT_TREE = {
    WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2,
}

-- the stats' names for notes and the options
ns.STAT_NAMES = {
    STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit", ARMOR = "Armor",
    DEF = "Defense", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", BLOCKVALUE = "Block value",
    HIT = "Hit", CRIT = "Crit", SPELLHIT = "Spell hit", SPELLCRIT = "Spell crit", AP = "Attack power",
    RAP = "Ranged attack power", SP = "Spell power", SP_FIRE = "Fire power", SP_FROST = "Frost power",
    SP_ARCANE = "Arcane power", SP_SHADOW = "Shadow power", SP_NATURE = "Nature power", SP_HOLY = "Holy power",
    HEAL = "Healing", SPDMG = "Spell damage", MP5 = "Mana regen", HP5 = "Health regen", DPS = "Weapon damage",
    RDPS = "Ranged damage",
    SPELLPEN = "Spell piercing", -- (Forever's name: ITEM_MOD_SPELL_PENETRATION_SHORT)
    RES_FIRE = "Fire resistance", RES_FROST = "Frost resistance", RES_ARCANE = "Arcane resistance",
    RES_SHADOW = "Shadow resistance", RES_NATURE = "Nature resistance",
}
