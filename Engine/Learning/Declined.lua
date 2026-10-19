local _, D = ...
local ns = D.engine

-- Suggestions on offer right there and passed: an active choice against them, which says more than a suggestion simply
-- not followed. Each counts a "chose" miss for the suggestion's reasons (learning.Declined), only if it was among the
-- suggestions then, and only what you could have done there:
--   trainer     a spell it offers you ("available") that you can afford, suggested (his spells wait with the trainer's
--               row, Reasons\TrainsYou.lua offers), not learned by the time the window closed
--   vendor      an item it sells that you can afford (no tokens), suggested, not bought
--   profession  a suggested recipe of the same profession you could make when the window opened, while you made another
--               one (only looking makes no choice)
--   quest       a suggested quest of your log abandoned (gone from the log, not turned in)
-- Learning, buying and making are noted as followed first (Memory.lua, Learning.lua), so what still waits when the
-- window closes was passed; the closing is looked at LATE seconds later, as a spell learned right before closing
-- arrives a moment after (SPELLS_CHANGED).
-- Trainer list API in Forever: GetNumTrainerServices, GetTrainerServiceInfo (2nd value "available"),
-- GetTrainerServiceCost, C_TooltipInfo.GetTrainerService(i).id (the spell).

local LATE = 2

local offered = {} -- entry ID -> what was on offer ("trainer", "vendor", ...), while a window is open
local crafted = {} -- skill line -> true: a recipe of it made while its window was open

local function Waiting(id) return ns.learning.Pending()[id] ~= nil end

local function Offer(id, where)
    if Waiting(id) then offered[id] = where end
end

-- passes what is still waiting of what was offered at a window, LATE
-- seconds after it closed; keep(id): true to let it be
local function Close(where, keep)
    local now = {}
    for id, at in pairs(offered) do
        if at == where then
            now[#now + 1] = id
            offered[id] = nil
        end
    end
    if #now == 0 then return end
    C_Timer.After(LATE, function()
        for _, id in ipairs(now) do
            if not (keep and keep(id)) then ns.learning.Declined(id, "passed at the " .. where) end
        end
    end)
end

local function Money() return GetMoney and GetMoney() or 0 end

local function TrainerShown()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return end
    for index = 1, GetNumTrainerServices() or 0 do
        local _, kind = GetTrainerServiceInfo(index)
        local cost = GetTrainerServiceCost and GetTrainerServiceCost(index) or 0
        local data = kind == "available" and cost <= Money() and C_TooltipInfo.GetTrainerService(index)
        if data and data.id then Offer("s:" .. data.id, "trainer") end
    end
end

local function VendorShown()
    if not (GetMerchantNumItems and GetMerchantItemLink) then return end
    for index = 1, GetMerchantNumItems() or 0 do
        local price, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then price, extended = info.price, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _
            _, _, price, _, _, _, _, extended = GetMerchantItemInfo(index)
        end
        local itemID = D.ItemIDFromLink(GetMerchantItemLink(index))
        if itemID and price and not D.Secret(price) and price <= Money() and not extended then Offer("i:" .. itemID, "vendor") end
    end
end

-- the recipes suggested that you can make now
local function ProfessionShown()
    wipe(crafted)
    for id in pairs(ns.learning.Pending()) do
        local entry = id:sub(1, 2) == "s:" and D.EntryByID(id)
        if entry and entry.domain == "professions" and D.CraftTimes(entry) > 0 then offered[id] = "profession" end
    end
end

-- only what lies beside a recipe made, in its profession
local function NotBeside(id)
    local entry = D.EntryByID(id)
    return not (entry and crafted[entry.skillLine])
end

local function On(event, fn)
    ns.On(event, function(_, ...)
        if ns.db then fn(...) end
    end)
end
On("TRAINER_SHOW", TrainerShown)
On("TRAINER_CLOSED", function()
    Close("trainer", function(id) return IsPlayerSpell and IsPlayerSpell(tonumber(id:sub(3))) end)
end)
On("MERCHANT_SHOW", VendorShown)
On("MERCHANT_CLOSED", function() Close("vendor") end)
On("TRADE_SKILL_SHOW", ProfessionShown)
On("TRADE_SKILL_CLOSE", function() Close("profession", NotBeside) end)
On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
    local recipe = spellID and not D.Secret(spellID) and D.RecipeEntry(spellID)
    if recipe then crafted[recipe.skillLine] = true end
end)
On("QUEST_REMOVED", function(questID)
    if not questID or D.Secret(questID) then return end
    C_Timer.After(LATE, function()
        if not C_QuestLog.IsQuestFlaggedCompleted(questID) then ns.learning.Declined("q:" .. questID, "abandoned") end
    end)
end)
