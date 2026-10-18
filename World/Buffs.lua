local _, D = ...
if D.off then return end

-- Buffs: the families of Data\Buffs.lua (D.buffFamilies, fields described there), for Pylos Buffs.
-- D.BuffFamilies(class file name) -> { [key] = family } of that class; shared tables, do not change
-- D.BuffFamilyOf(spell ID of any rank, single or group) -> key, family; nil if no buff of the list

local byClass, bySpell
local NONE = {}

local function Index()
    byClass, bySpell = {}, {}
    for key, family in pairs(D.buffFamilies or NONE) do
        byClass[family.class] = byClass[family.class] or {}
        byClass[family.class][key] = family
        for _, ranks in ipairs({ family.single, family.group }) do
            for i = 1, #ranks, 3 do bySpell[ranks[i]] = key end -- spell ID, level, seconds
        end
    end
end

function D.BuffFamilies(class)
    if not byClass then Index() end
    return byClass[class] or NONE
end

function D.BuffFamilyOf(spellID)
    if not bySpell then Index() end
    local key = bySpell[spellID]
    if key then return key, D.buffFamilies[key] end
end
