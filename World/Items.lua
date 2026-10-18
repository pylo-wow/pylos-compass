local _, D = ...
if D.off then return end

-- Items: all game items (English names, Data\ItemNames_enUS.lua) with facts (Data\ItemFacts.lua)
-- and GetItemInfoInstant data. Built in the background (19,224 entries).
-- Also: kinds worth suggesting, items near a level, and whether you can use an item (D.ItemForYou).

-- item ID -> packed facts (Data\ItemFacts.lua); freed after the build
local facts

-- Memory: an entry keeps only name, item ID and packed facts (plus the build key), four fields
-- = exactly four table slots (six fields took eight; 0.55 KB per item, measured in game).
-- The rest is computed on demand via the domain metatable, from the packed facts or
-- GetItemInfoInstant. Storing all seventeen sized every entry for 32 fields (up to 70 MB).
local function Instant(entry, n) return (select(n, C_Item.GetItemInfoInstant(entry.itemID))) end

-- D.fields.items exists before the domain registers (RegisterDomain keeps it)
local fields = D.fields.items or {}
D.fields.items = fields
-- quality, required level, class mask (0: all), starts a quest (writs, letters: never suggested), item level
fields.quality = function(entry) return entry.packed % 8 end
fields.requiredLevel = function(entry) return math.floor(entry.packed / 8) % 128 end
fields.classMask = function(entry) return math.floor(entry.packed / 1024) % 4096 end
fields.startsQuest = function(entry) return math.floor(entry.packed / 4194304) % 2 == 1 end
fields.itemLevel = function(entry) return math.floor(entry.packed / 8388608) end
fields.knownRecipe = function(entry) return D.RecipeKnownForItem(entry.itemID) end
fields.recipeState = function(entry) return D.RecipeState(entry.itemID) end
fields.category = function(entry) return Instant(entry, 3) end -- subtype
fields.equipLoc = function(entry) return Instant(entry, 4) end
fields.icon = function(entry) return Instant(entry, 5) end
fields.itemClass = function(entry) return Instant(entry, 6) end
fields.itemSubClass = function(entry) return Instant(entry, 7) end

local meta -- D.Meta("items"), once the domain is registered

local function AddItem(list, id, name)
    list[#list + 1] = setmetatable({ name = name, itemID = id, packed = facts[id] or 0 }, meta)
end

local function Facts(Pause)
    if facts then return end
    facts = {}
    local list = D.itemFacts or {}
    for i = 1, #list, 2 do
        facts[list[i]] = list[i + 1]
        if i % 256 == 1 then Pause() end
    end
end

D.RegisterDomain({
    key = "items",
    background = true,
    collect = function(list, Pause)
        meta = meta or D.Meta("items")
        Facts(Pause)
        local count = 0
        for id, english in pairs(D.itemNamesEN or {}) do
            AddItem(list, id, english)
            count = count + 1
            if count % 32 == 0 then Pause() end
        end
        facts = nil -- the entries hold their facts now
    end,
})

-- Kinds worth suggesting
-- Weapons, armour and some consumables; not explosives, devices, "Other" (Forever's sealed
-- writs and crates of crafting orders show up there), reagents, trade goods, recipes, quest
-- items, keys, miscellaneous, bags, quivers or ammunition.
-- item class -> true (all subclasses) or subclass -> true; IDs from DB2 ItemSubClass (build
-- 1.60.1.70245): consumables 1 potions, 2 elixirs, 3 flasks, 4 scrolls, 5 food & drink,
-- 6 permanent, 7 bandages, 13 draught, 15 temporary (0 explosives, 8 other, 14 device excluded)
local SUGGESTED = {
    [0] = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
        [13] = true, [15] = true },
    [2] = true, [4] = true,
}
function D.ItemSuggestedKind(entry)
    local kinds = SUGGESTED[entry.itemClass]
    return kinds == true or (kinds and kinds[entry.itemSubClass]) or false
end

-- Does a food or drink give a buff beyond restoring health/mana? Plain food is not suggested.
-- Matches "well fed" / "increase" in the item spell's description (English client only).
-- true / false, nil while the text is not loaded yet (requested; a later call knows it).
-- Cached per item.
local FOOD, DRINK_FOOD = 0, 5 -- item class, subclass
local buffs = {}
function D.FoodBuffs(entry)
    local id = entry.itemID
    local known = buffs[id]
    if known ~= nil then return known end
    local GetSpell = C_Item.GetItemSpell or GetItemSpell
    local _, spellID = GetSpell(id)
    if not spellID then
        if C_Item.IsItemDataCachedByID(id) then buffs[id] = false return false end
        C_Item.RequestLoadItemDataByID(id)
        return nil
    end
    local text = C_Spell.GetSpellDescription(spellID)
    if not text or text == "" then
        if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
        return nil
    end
    text = text:lower()
    known = text:find("well fed", 1, true) ~= nil or text:find("increase", 1, true) ~= nil
    buffs[id] = known
    return known
end
function D.IsFood(entry) return entry.itemClass == FOOD and entry.itemSubClass == DRINK_FOOD end

local LEVEL_WINDOW = 5 -- required level from the level - 5 up to the level
-- Items without a required level (most quest rewards) use an item level from level - ITEM_BELOW
-- to level + ITEM_ABOVE instead (otherwise they all dropped out)
local ITEM_BELOW, ITEM_ABOVE = 3, 5

-- Suggestable items near a level, built once per level and build (one pass over all items):
-- SUGGESTED kinds, required level within LEVEL_WINDOW below the level (or item level near it if none),
-- not junk, not quest starters, armour and weapons green or better.
-- Shared: do not change. Built in the background after the items are built and after each
-- level up, else on first ask.
local near, nearLevel, nearVersion = {}, nil, nil -- nearVersion: state "data:items" at build time
local function NoPause() end
local function Near(level, Pause)
    local version = D.State("data:items")
    local list = {}
    local lowest = math.max(level - LEVEL_WINDOW, 0)
    for i, entry in ipairs(D.Entries("items")) do
        local required = entry.requiredLevel
        local fits = (required >= lowest and required <= level and required > 0)
            or (required <= 1 and entry.itemLevel >= level - ITEM_BELOW and entry.itemLevel <= level + ITEM_ABOVE)
        if fits and entry.quality >= 1 and D.ItemSuggestedKind(entry)
                and not entry.startsQuest and (entry.quality >= 2 or (entry.itemClass ~= 2 and entry.itemClass ~= 4)) then
            list[#list + 1] = entry
        end
        if i % 256 == 0 then Pause() end
    end
    if version ~= D.State("data:items") then return end -- items rebuilt meanwhile
    near, nearLevel, nearVersion = list, level, version
end
function D.ItemsNearLevel(level)
    if nearLevel ~= level or nearVersion ~= D.State("data:items") then Near(level, NoPause) end
    return near
end
local function Soon()
    if D.Built("items") then
        D.Background("items near your level", function(Pause)
            local level = UnitLevel("player")
            if nearLevel ~= level or nearVersion ~= D.State("data:items") then Near(level, Pause) end
        end)
    end
end
D.OnBuilt(function(key) if key == "items" then Soon() end end)
D.OnState("level", Soon)

-- For you
-- Usable now: level reached, class allowed (Data\ItemFacts.lua), armour/weapon kind learned.
-- Kinds come from known proficiency spells (Plate Mail, Swords, ...), so untrained weapon
-- skills do not count. If none of these spells exist in the client, kinds are not checked.

local ARMOR, WEAPON = 4, 2 -- item classes
local ARMOR_SPELLS = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 } -- cloth .. shield
local WEAPON_SPELLS = {
    [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201, [8] = 202,
    [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009,
}
-- relics belong to one class each: libram, idol, totem
local RELICS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

local level, classBit, classFile
local known, checkKinds = {}, false -- spell ID -> true; are the kinds checked
local prepared = D.Cache({ "frame" }) -- renewed: not prepared yet this frame

local function SpellKnown(spellID)
    return IsPlayerSpell(spellID) or (IsSpellKnown ~= nil and IsSpellKnown(spellID))
end

local function KindAllowed(entry)
    local spells = entry.itemClass == ARMOR and ARMOR_SPELLS or entry.itemClass == WEAPON and WEAPON_SPELLS
    if not spells then return true end
    local sub = entry.itemSubClass
    if entry.itemClass == ARMOR then
        if RELICS[sub] then return RELICS[sub] == classFile end
        if entry.equipLoc == "INVTYPE_CLOAK" then return true end -- cloaks are cloth for everyone
    end
    local spell = spells[sub]
    return not spell or not checkKinds or known[spell] == true
end

-- Reads level, class and learned kinds; D.ItemForYou does this once per frame, so callers
-- need it only after a change within a frame
function D.ItemForYouPrepare()
    prepared.Get() -- marks this frame as prepared
    level = UnitLevel("player")
    local classID
    classFile, classID = select(2, UnitClass("player"))
    classBit = 2 ^ ((classID or 1) - 1)
    wipe(known)
    checkKinds = false
    for _, spells in ipairs({ ARMOR_SPELLS, WEAPON_SPELLS }) do
        for _, spell in pairs(spells) do
            if SpellKnown(spell) then
                known[spell] = true
                checkKinds = true
            end
        end
    end
end

-- Can you use the item now (level, class, armour/weapon kind)
function D.ItemForYou(entry)
    local _, renewed = prepared.Get()
    if renewed then D.ItemForYouPrepare() end
    if (entry.requiredLevel or 0) > level then return false end
    local mask = entry.classMask or 0
    if mask ~= 0 and bit.band(mask, classBit) == 0 then return false end
    return KindAllowed(entry)
end
