local _, D = ...
if D.off then return end
local ns = D.engine

-- Learns whether the item valuer's upgrades are right for you, not from following within half an hour (most upgrades
-- cannot be put on that soon) but from what you do with upgrades you get or are offered. Each counts for the reason
-- "upgrade" (Learning.lua: EVIDENCE):
--   chose    a quest reward: the best upgrade among the choices taken is a hit; one taken that is no upgrade at all while
--            an upgrade was on offer, a miss (a smaller upgrade taken over the best says the weights are off, not the
--            reason: not counted). A loot roll on an upgrade: need a hit, pass or greed a miss. An upgrade in your bags
--            sold or destroyed without having worn it: a miss
--   did      an upgrade from your bags put on
-- Keeping one unworn counts nothing: it may wait for a level or a second look (and the player can skew waiting time).
-- Gone to the bank, a letter, a trade or the auction house: no decision seen.
-- Unlike other reasons these need not have been shown as a suggestion (Learning.lua counts only what was shown): each
-- is an active choice of yours about an upgrade, wherever it came from.
-- Each item is judged once per character (saved in upgradesJudged, so a login does not count it again; JUDGED_DAYS long).
-- An upgrade you cannot put on yet (level) waits until you can.
-- Blizzard source (forever): QuestFrame.lua calls GetQuestReward(choice); QuestInfo.lua reads the choices with
-- GetQuestItemInfo("choice", i) (6th value the item ID); GroupLootFrame.lua rolls with RollOnLoot(rollID, 0 pass,
-- 1 need, 2 greed, 4 transmog).

local AWAY = 2         -- seconds after a bank, mail, trade or auction window closed: an item gone then went there
local JUDGED_DAYS = 90 -- days an item stays judged (the learning has halved three times by then)

local watched = {} -- item ID -> true: in your bags as an upgrade you can wear
local offered = {} -- quest reward choices on show: index -> item ID
local open = {}    -- window ("merchant", "elsewhere") -> true while open, else GetTime() it closed

-- this character's judged items: item ID -> time() judged
local function Judged()
    local db = ns.db
    if not db then return nil end
    local key = ns.Character()
    db.upgradesJudged[key] = db.upgradesJudged[key] or {}
    return db.upgradesJudged[key]
end

local function Observe(itemID, hit, evidence, words)
    local judged = Judged()
    if judged then judged[itemID] = time() end
    watched[itemID] = nil
    ns.learning.Observe("upgrade", hit, evidence, "i:" .. itemID, words)
end

local function Recently(window)
    local state = open[window]
    return state == true or (state and GetTime() - state <= AWAY)
end

-- an item that is no armour or weapon is never an upgrade: told once per item (900 looks took 4 ms in the search's bench)
local notGear = {} -- item ID -> true or false
local function NotGear(itemID)
    local known = notGear[itemID]
    if known == nil then
        local entry = D.ItemByID(itemID)
        known = entry ~= nil and entry.itemClass ~= 2 and entry.itemClass ~= 4
        if entry then notGear[itemID] = known end -- (not built yet: asked again)
    end
    return known
end

local function Look()
    local judged = Judged()
    if not judged or InCombatLockdown() then return end
    D.RefreshOwned()
    for itemID in pairs(watched) do
        if not D.bagItems[itemID] then
            if D.ownedItems[itemID] then
                Observe(itemID, true, "did", "put on")
            elseif Recently("elsewhere") then
                watched[itemID] = nil -- to the bank, a letter, a trade or an auction: no decision seen
            else
                Observe(itemID, false, "chose", Recently("merchant") and "sold" or "destroyed")
            end
        elseif not ns.UpgradeOf(itemID) then
            watched[itemID] = nil -- something better came, or it is no upgrade any more
        end
    end
    for itemID in pairs(D.bagItems) do
        if not watched[itemID] and not judged[itemID] and not NotGear(itemID) and ns.UpgradeOf(itemID) then
            watched[itemID] = true
        end
    end
end

local function Rewarded(choice)
    local best, bestShare = nil, 0
    for index, itemID in pairs(offered) do
        local r = ns.UpgradeOf(itemID)
        if r and r.share > bestShare then best, bestShare = index, r.share end
    end
    local taken = offered[choice]
    wipe(offered)
    if not best or not taken then return end
    if choice == best then
        Observe(taken, true, "chose", "quest reward")
    elseif not ns.UpgradeOf(taken) then
        Observe(taken, false, "chose", "quest reward, another taken")
    end
end

local function Rolled(rollID, rollType)
    local itemID = D.ItemIDFromLink(GetLootRollItemLink and GetLootRollItemLink(rollID))
    local judged = Judged()
    if not itemID or not judged or judged[itemID] or not ns.UpgradeOf(itemID) then return end
    Observe(itemID, rollType == 1, "chose", rollType == 1 and "need" or "roll passed")
end

-- where an item may go without a decision about it: a merchant (sold),
-- elsewhere (the bank, a letter, a trade, the auction house)
local WINDOWS = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    BANKFRAME_OPENED = { "elsewhere", true }, BANKFRAME_CLOSED = { "elsewhere", false },
    MAIL_SHOW = { "elsewhere", true }, MAIL_CLOSED = { "elsewhere", false },
    TRADE_SHOW = { "elsewhere", true }, TRADE_CLOSED = { "elsewhere", false },
    AUCTION_HOUSE_SHOW = { "elsewhere", true }, AUCTION_HOUSE_CLOSED = { "elsewhere", false },
}
for event in pairs(WINDOWS) do
    ns.On(event, function()
        local window = WINDOWS[event]
        open[window[1]] = window[2] or GetTime()
    end)
end
ns.On("QUEST_COMPLETE", function()
    wipe(offered)
    for index = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do
        local itemID = select(6, GetQuestItemInfo("choice", index))
        if itemID then offered[index] = itemID end
    end
end)
D.OnState({ "bags", "gear", "level" }, Look)
if GetQuestReward then hooksecurefunc("GetQuestReward", function(choice) pcall(Rewarded, choice) end) end
if RollOnLoot then hooksecurefunc("RollOnLoot", function(rollID, rollType) pcall(Rolled, rollID, rollType) end) end

-- the judged items older than JUDGED_DAYS go (at login: Learning.lua)
function ns.learning.PruneJudged()
    local db = ns.db
    if not db then return end
    local oldest = time() - JUDGED_DAYS * 86400
    for key, judged in pairs(db.upgradesJudged) do
        for itemID, at in pairs(judged) do
            if at < oldest then judged[itemID] = nil end
        end
        if next(judged) == nil then db.upgradesJudged[key] = nil end
    end
end
