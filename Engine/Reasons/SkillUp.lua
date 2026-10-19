local _, D = ...
local ns = D.engine
local L = ns.L

-- Skill up: a recipe you know that still raises your skill: orange, yellow or green in the profession window
-- (D.RecipeSkillColor). As strong as the chance of a point (D.RecipeSkillChance: orange sure, yellow 100 to 50 %, green
-- 50 to 0 %), as a green recipe is seldom worth its materials. Without the materials in your bags its reach is the
-- zone's: they are still to be got. The search's filter "Skill up" uses the chance alone (above 0).
--
-- What a point costs: of the recipes you can make now, the one using the least materials for a point comes first.
-- The materials are valued at what a vendor pays for them (the client's sell price), so different materials compare
-- too; one whose value the client does not know is left out of the comparison. A recipe making something you would
-- wear (the reason "upgrade" on its item) is worth its cost.
--   strength = chance x (CHEAPEST_SHARE + the rest x cheapest cost / its cost)

local CHEAPEST_SHARE = 0.4 -- what the dearest way to a point keeps

local costs = {}     -- entry -> cost of a point (copper) or false; see prepare
local cheapest = {}  -- skill line -> lowest cost of a point among the recipes you can make now; see prepare

-- what one of an item fetches at a vendor, nil if the client does not know
local function Worth(itemID)
    local sellPrice = select(11, C_Item.GetItemInfo(itemID))
    return sellPrice and sellPrice > 0 and sellPrice or nil
end

-- the item a recipe makes is an upgrade for you
local function MakesUpgrade(entry)
    local recipe = D.RecipeOf(entry.spellID, entry.skillLine)
    local item = recipe and recipe[1] ~= 0 and D.ItemByID(recipe[1])
    return item ~= nil and item ~= false and ns.reasons.Test("upgrade", item) ~= nil
end

-- the materials' worth for one point (false: not known)
local function Cost(entry)
    local known = costs[entry]
    if known ~= nil then return known end
    local recipe = D.RecipeOf(entry.spellID, entry.skillLine)
    local chance = D.RecipeSkillChance(entry)
    local cost = recipe and recipe[4] and chance and chance > 0 and 0 or false
    if cost then
        for i = 4, #recipe, 2 do
            local worth = Worth(recipe[i])
            if not worth then
                cost = false
                break
            end
            cost = cost + worth * (recipe[i + 1] or 1)
        end
        if cost then cost = cost / chance end
    end
    costs[entry] = cost
    return cost
end

-- the lowest cost of a point among the recipes of a profession you can make now (once per prepare)
local function Cheapest(skillLine)
    local known = cheapest[skillLine]
    if known ~= nil then return known end
    local best = false
    for _, entry in ipairs(D.Entries("professions")) do
        -- the color asked directly: the reason's own test would come back here
        local chance = entry.skillLine == skillLine and not entry.hidden and D.RecipeSkillChance(entry)
        if chance and chance > 0 and D.CraftTimes(entry) > 0 and not MakesUpgrade(entry) then
            local cost = Cost(entry)
            if cost and (not best or cost < best) then best = cost end
        end
    end
    cheapest[skillLine] = best
    return best
end

-- how much of the color's strength is left for what the point costs (1: the cheapest way, or its cost not known, or it
-- makes an upgrade)
local function Economy(entry)
    if not D.CraftTimes or D.CraftTimes(entry) == 0 or MakesUpgrade(entry) then return 1 end
    local cost, best = Cost(entry), Cheapest(entry.skillLine)
    if not cost or not best or cost <= best then return 1 end
    return CHEAPEST_SHARE + (1 - CHEAPEST_SHARE) * best / cost
end

ns.RegisterReason({
    key = "skillUp",
    -- weight 1.25: a point of skill is what working on a profession is for
    stage = "professions", weight = 1.25, label = "Skill up",
    sources = { "professions" },
    -- your skills and bags; whether it makes an upgrade (Upgrade.lua's states)
    depends = { "skills", "bags", "spells", "gear", "level", "talents", "rec:weights", "quests", "npcs", "money",
        "zone", "travel", "data" },
    topic = "professions",
    prepare = function()
        wipe(costs)
        wipe(cheapest)
    end,
    test = function(entry)
        local chance = not entry.hidden and D.RecipeSkillChance(entry)
        if not chance or chance <= 0 then return nil end
        return chance * Economy(entry)
    end,
    reach = function(entry)
        if D.CraftTimes(entry) > 0 then return ns.reach.NOW, nil end
        return ns.reach.ZONE, L["needs materials"]
    end,
    profession = true,
    -- the tooltip's line on it, with the color and what a point costs
    why = function(entry)
        local color = D.RecipeSkillColor(entry)
        local text = L["Still raises your skill (%s, %d %% chance)"]:format(L[color],
            math.floor(D.RecipeSkillChance(entry) * 100 + 0.5))
        if D.CraftTimes(entry) > 0 then
            if MakesUpgrade(entry) then
                text = text .. "\n" .. L["and you can wear it"]
            else
                local cost, best = Cost(entry), Cheapest(entry.skillLine)
                if cost and best and cost > best then
                    text = text .. "\n" .. L["a point costs %d %% more than with the cheapest recipe"]:format(
                        math.floor((cost / best - 1) * 100 + 0.5))
                end
            end
        end
        return text
    end,
})
