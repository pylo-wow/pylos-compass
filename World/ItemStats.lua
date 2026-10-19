local _, D = ...
if D.off then return end

-- Stats of wearable items (Data\ItemStats.lua, from the client tables plus data collected in the game),
-- for valuing items by class and spec. Items with random stats ("of the Bear") have none here
-- (randomSuffix); their link does (D.LiveItemStats).
-- D.ItemStats(itemID) -> nil (unknown) or a shared table (do not change):
--   stats      { [key] = amount }, present keys only
--   dps, speed (seconds), minDamage, maxDamage   weapons only
--   procs      true: equip or chance-on-hit effect the stats do not show
--   randomSuffix  true: random stats, not in the data
-- Keys. Ratings are percent points at level 60 as the tooltip shows them ("+1.0%" = 1);
-- Forever's hit and crit work for spells too, so "+1% hit" gives HIT = 1 and SPELLHIT = 1.
--   STR AGI STA INT SPI     primary stats
--   ARMOR                   base plus bonus armor
--   DEF DODGE PARRY BLOCK BLOCKVALUE  defense skill points; dodge, parry, block %; block value
--   HIT CRIT                melee and ranged hit / crit %
--   SPELLHIT SPELLCRIT      spell hit / crit %
--   AP RAP                  attack power, ranged attack power
--   SP                      spell damage and healing, all schools
--   SPDMG                   spell damage only, all schools ("healing done by up to 58 and
--                           damage done by up to 10" gives HEAL 58, SPDMG 10)
--   SP_FIRE SP_FROST SP_ARCANE SP_SHADOW SP_NATURE SP_HOLY  damage of one school
--   HEAL                    healing only
--   MP5 HP5                 mana / health per 5 sec
--   SPELLPEN                spell penetration
--   RES_FIRE RES_FROST RES_ARCANE RES_SHADOW RES_NATURE  resistances
--   SKILL_2H_AXES SKILL_2H_MACES SKILL_2H_SWORDS SKILL_AXES SKILL_BOWS
--   SKILL_CROSSBOWS SKILL_DAGGERS SKILL_DUAL_WIELD SKILL_FIST SKILL_GUNS
--   SKILL_MACES SKILL_POLEARMS SKILL_STAVES SKILL_SWORDS SKILL_THROWN
--   SKILL_WANDS             weapon skill (+7 Swords: SKILL_SWORDS = 7)

-- item ID -> decoded stats, kept for the session (a weak table is collected and re-decoded every refresh)
local decoded = {}

function D.ItemStats(itemID)
    local s = decoded[itemID]
    if s then return s end
    local text = D.itemStats and D.itemStats[itemID]
    if not text then return nil end
    local statText, weapon, flags = text:match("^([^|]*)|?([^|]*)|?(.*)$")
    s = { stats = {} }
    for key, value in statText:gmatch("([%w_]+)=(%-?[%d%.]+)") do s.stats[key] = tonumber(value) end
    local speed, low, high = weapon:match("^(%d+):(%d+):(%d+)$")
    if speed then
        s.speed, s.minDamage, s.maxDamage = tonumber(speed) / 1000, tonumber(low), tonumber(high)
        s.dps = (s.minDamage + s.maxDamage) / 2 / s.speed
    end
    if flags:find("p", 1, true) then s.procs = true end
    if flags:find("r", 1, true) then s.randomSuffix = true end
    decoded[itemID] = s
    return s
end

-- Live stats
-- C_Item.GetItemStats names -> keys above. The data generator uses the same names (it strips ITEM_MOD_ and _SHORT and
-- converts ratings itself), so a worn item and the same item from the data are valued alike. Ratings are taken as
-- the game gives them.
D.LIVE_STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
    ITEM_MOD_PARRY_RATING_SHORT = "PARRY", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SPDMG",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "SP_HOLY", ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "SP_FIRE",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "SP_NATURE", ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "SP_FROST",
    ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "SP_SHADOW", ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "SP_ARCANE",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    RESISTANCE2_NAME = "RES_FIRE", RESISTANCE3_NAME = "RES_NATURE", RESISTANCE4_NAME = "RES_FROST",
    RESISTANCE5_NAME = "RES_SHADOW", RESISTANCE6_NAME = "RES_ARCANE",
    ITEM_MOD_TWOHANDED_AXES_SHORT = "SKILL_2H_AXES", ITEM_MOD_TWOHANDED_MACES_SHORT = "SKILL_2H_MACES",
    ITEM_MOD_TWOHANDED_SWORDS_SHORT = "SKILL_2H_SWORDS", ITEM_MOD_AXES_SHORT = "SKILL_AXES",
    ITEM_MOD_BOWS_SHORT = "SKILL_BOWS", ITEM_MOD_CROSSBOWS_SHORT = "SKILL_CROSSBOWS",
    ITEM_MOD_DAGGERS_SHORT = "SKILL_DAGGERS", ITEM_MOD_DUAL_WIELD_SHORT = "SKILL_DUAL_WIELD",
    ITEM_MOD_FIST_WEAPONS_SHORT = "SKILL_FIST", ITEM_MOD_GUNS_SHORT = "SKILL_GUNS",
    ITEM_MOD_MACES_SHORT = "SKILL_MACES",
    ITEM_MOD_POLEARMS_SHORT = "SKILL_POLEARMS", ITEM_MOD_STAVES_SHORT = "SKILL_STAVES",
    ITEM_MOD_SWORDS_SHORT = "SKILL_SWORDS", ITEM_MOD_THROWN_SHORT = "SKILL_THROWN",
    ITEM_MOD_WANDS_SHORT = "SKILL_WANDS",
}

local ALIASED = { MP5 = true, HP5 = true }

-- Stats of an item link from the game (also random "of the X" items), keyed as D.ItemStats:
-- { stats, dps }; nil if the client does not know the item yet
function D.LiveItemStats(link)
    if not link then return nil end
    local raw = C_Item.GetItemStats(link)
    if not raw then return nil end
    local stats = {}
    for name, amount in pairs(raw) do
        local key = D.LIVE_STAT_KEYS[name]
        if key then
            -- MP5 and HP5 have two client names each: one stat, not two
            stats[key] = ALIASED[key] and math.max(stats[key] or 0, amount) or (stats[key] or 0) + amount
        end
    end
    local result = { stats = stats }
    local dps = raw.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    if dps and dps > 0 then result.dps = dps end
    return result
end
