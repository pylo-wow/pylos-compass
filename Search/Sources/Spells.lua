local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Spells: the active spells of the spell book, professions included, each once in its highest rank;
-- hidden: the trainer's spells not learned yet. Entries come from Data (World\Spells.lua).

-- fields the rows and the action need (a learned spell is cast)
D.AddField("spells", "type", function(entry) if not entry.hidden then return "spell" end end)
D.AddField("spells", "value", function(entry) if not entry.hidden then return entry.spellID end end)

local source

-- The spell book's tabs as subcategories (they differ per class): one filter per tab name, kept so
-- a set one stays the same
local tabFilters = {}
local function Subcategories()
    local list = {}
    for _, tab in ipairs(D.SpellBookTabs()) do
        local f = tabFilters[tab.name]
        if not f then
            local name = tab.name
            f = ns.MakeFilter({
                key = "spellTab:" .. name, name = name, icon = tab.icon, subcategory = true,
                sources = { "spells" }, static = true, test = function(entry) return entry.tab == name end,
            })
            tabFilters[name] = f
        end
        list[#list + 1] = f
    end
    return list
end

-- Opened without text: first the spells a trainer can teach you now (D.SpellLearnableNow, greyed),
-- then your spells, both in the common order (engine fit, then A-Z)
local learnable, yours = {}, {}
local function Browse(take)
    local reasons = ns.rec
    reasons.Prepare()
    wipe(learnable)
    wipe(yours)
    for _, entry in ipairs(source.index.entries) do
        if not entry.hidden then
            yours[#yours + 1] = entry
        elseif D.SpellLearnableNow(entry) then -- a fact, not a suggestion (the search is no advisor)
            learnable[#learnable + 1] = entry
        end
    end
    local shown = 0
    for _, entry in ipairs(reasons.Sort(learnable)) do
        if take(entry, L["Learnable at a trainer"]) then shown = shown + 1 end
    end
    local heading = shown > 0 and L["Your spells"] or nil
    for _, entry in ipairs(reasons.Sort(yours)) do take(entry, heading) end
end

local symbolAtlas, symbolFile = ns.MicroMenuSymbol("SpellbookMicroButton", "SpellBookMicroButton")

source = ns.RegisterSource({
    key = "spells",
    domain = "spells",
    browse = Browse,
    subcategories = Subcategories,
    owned = function(entry) return not entry.hidden end,
    -- a trainer's spell of your class not learned yet: found by typing, greyed with its level; only the
    -- next rank of each (the rank before it learned)
    findable = function(entry) return entry.trainLevel ~= nil and entry.previousLearned == true end,
    name = L["Spells"],
    hint = L["Search spells"],
    icon = symbolFile or "Interface\\Icons\\INV_Misc_Book_09",
    iconAtlas = symbolAtlas,
    actionLabel = L["cast"],
    -- line below the name: spell book tab and rank
    describe = function(entry)
        if entry.hidden then
            return { entry.tab, entry.rankNumber and L["Rank %d"]:format(entry.rankNumber) }
        end
        if entry.subtext == nil then
            -- empty while the spell data is not loaded: asked again until there is a text; false once
            -- the data is loaded and there is none
            local text = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(entry.spellID)
            if text and text ~= "" then
                entry.subtext = text
            elseif C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(entry.spellID) then
                entry.subtext = false
            end
        end
        return { entry.tab, entry.subtext or nil }
    end,
    -- row state (UI\List.lua): learnable now or from which level; none for a learned spell (its hotkey shows there)
    state = function(entry)
        if not entry.hidden then return nil end
        if D.SpellLearnableNow(entry) then return L["Learnable now"], "good" end
        local level = D.TrainingLevel and D.TrainingLevel(entry.spellID) or entry.trainLevel
        if level and level > UnitLevel("player") then return L["From level %d"]:format(level), "no" end
        return nil
    end,
    forYou = function(entry, add)
        if not entry.hidden then return end
        local cost = D.TrainingCost and D.TrainingCost(entry.spellID)
        if cost and cost > 0 then add(L["Training cost: %s"]:format(D.Money(cost)), "plain") end
    end,
})
