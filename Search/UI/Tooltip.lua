local ns = select(2, ...).search
local L = ns.L

-- An entry's tooltip: beside the list (ui.tip), or inside the detail view
-- (its own, Detail.lua).

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local tip = ui.tip

-- An item whose data is not loaded shows only the name or "retrieving item information" and does not update by
-- itself (waiting for GET_ITEM_INFO_RECEIVED did not help, confirmed in game): the tooltip is filled again
-- five times a second.
local REFILL_EVERY = 0.2
local REFILL_FOR = 2 * W.TOOLTIP_WAIT -- an item that never loads is left as it is after this long
local refilling -- the watcher is filling again (not a new fill: its time starts)
local function Retrieving(tooltip)
    if tooltip.pendingItem then return not C_Item.IsItemDataCachedByID(tooltip.pendingItem) end
    local first = _G[tooltip:GetName() .. "TextLeft1"]
    local text = first and first:GetText()
    return text ~= nil and RETRIEVING_ITEM_INFO ~= nil and text:find(RETRIEVING_ITEM_INFO, 1, true) ~= nil
end

-- the watcher: shown only while a tooltip waits for its item's data
local watch, nextCheck = CreateFrame("Frame", nil, ui.bar), 0
watch:Hide()
local function Watch() watch:Show() end

-- Blocks below an entry's own lines, the same in every category: "For you" (source.forYou: bags, learnable,
-- skill up, progress, hotkey) and "Why" (why a suggestion is listed). Where to get it is no block; the menu's
-- links list them all. Each under a gold heading, left out when empty. A source adds a line with
-- add(text, tone): an ns.TONES tone or a color.
local GOLD, WHITE = W.GOLD, W.WHITE
local blockLines = {}
local function Block(tooltip, heading, fill, entry)
    wipe(blockLines)
    fill(entry, function(text, tone)
        if text then
            blockLines[#blockLines + 1] = { text, ns.TONES[tone] or type(tone) == "table" and tone or WHITE }
        end
    end)
    if #blockLines == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(heading, GOLD[1], GOLD[2], GOLD[3])
    for _, line in ipairs(blockLines) do
        local color = line[2]
        tooltip:AddLine(line[1], color[1], color[2], color[3], true)
    end
end

-- For you, in every category: the hotkey of an item or spell on your bars (only here: it is no row state), or
-- that an active spell is on none
local function ForYou(entry, add)
    if entry.source and entry.source.forYou then entry.source.forYou(entry, add) end
    if not (entry.itemID or (entry.spellID and entry.type == "spell")) then return end
    local key = ns.ActionKey(entry)
    if key and key ~= "" then
        add(L["Hotkey: %s"]:format(key), "plain")
    elseif key == false and entry.type == "spell" and not ns.data.SpellPassive(entry.spellID) then
        add(L["Not on your bars"], "done")
    end
end

-- A recipe's tooltip has the item it makes below it (beside it where there is no room); not where the game's
-- recipe tooltip shows the item already (same item twice; then whether it is an upgrade stands under For you,
-- Sources\Professions.lua)
local made = CreateFrame("GameTooltip", "PylosCompassMadeTooltip", UIParent, "GameTooltipTemplate")
made:SetFrameStrata("TOOLTIP")
made.noGatherInfo = true
tip:HookScript("OnHide", function() made:Hide() end)
local function Shows(tooltip, text)
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line and line:GetText() == text then return true end
    end
    return false
end
local function ShowMade(entry)
    made:Hide()
    local recipe = entry.skillLine and entry.spellID and ns.data.RecipeOf(entry.spellID, entry.skillLine)
    local itemID = recipe and recipe[1]
    if not itemID or itemID == 0 then return end
    local item = ns.data.ItemByID(itemID)
    if item and Shows(tip, item.name) then return end
    made:SetOwner(tip, "ANCHOR_NONE")
    made:SetItemByID(itemID)
    made:ClearAllPoints()
    made:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -2)
    made:Show()
    if (tip:GetBottom() or 0) - made:GetHeight() < 0 then
        made:ClearAllPoints()
        made:SetPoint("TOPLEFT", tip, "TOPRIGHT", 2, 0)
    end
end

function ui.FillTooltip(tooltip, entry)
    if not refilling then tooltip.fillSince = GetTime() end
    tooltip.pendingItem = nil
    if entry.itemID then
        C_Item.RequestLoadItemDataByID(entry.itemID)
        tooltip:SetItemByID(entry.itemID)
        tooltip.pendingItem = not C_Item.IsItemDataCachedByID(entry.itemID) and entry.itemID or nil
        -- a trade good: where it is gathered, from Pylos GatherInfo if installed and the option is on
        -- (noGatherInfo stops its own hook)
        local gather = ns.db.gatherInfo and ns.GatherInfo()
        if gather and (not gather.Wanted or gather.Wanted()) then
            gather.AddLine(tooltip, entry.itemID)
        end
    elseif entry.spellID then
        tooltip:SetSpellByID(entry.spellID)
    else
        -- an entry of its own: its name (an NPC's in its reaction's color) and its lines (World\Lines.lua)
        W.EntryText(tooltip, entry)
    end
    Block(tooltip, L["For you"], ForYou, entry.target or entry)
    -- why it is here: every reason it has (strongest first; the row shows only the strongest) and your own use
    -- (Memory.lua), under "Why" in white as in the recommendations window; only where it was suggested, not in a
    -- link's list or the detail view
    if not (S.linked or S.detail) and entry.source then
        local why = {}
        for i, line in ipairs(ns.rec.Explain(entry)) do why[i] = line end
        local id = ns.EntryID(entry)
        if ns.rank.learnedNow[entry] and S.query ~= "" then
            why[#why + 1] = L["You chose this for this search before"]
        elseif id and ns.rank.UsedNow()(id) >= 0.15 then
            why[#why + 1] = L["You come back to this often"]
        end
        W.AddWhy(tooltip, why)
    end
    tooltip:Show()
    if Retrieving(tooltip) then Watch() end
end

-- The marked result shows (selection bar, tooltip) once there is a reason: text typed, a key or the mouse moved
-- over the list, a link's list. Otherwise the first entry of a page opened without text would be marked with no
-- mouse near; Enter still opens it after a key moved.
function ui.MarkVisible()
    return S.query ~= "" or S.navigated or S.hovered or S.linked ~= nil
end

-- Beside the list: the tooltip, or right of the filter window while it is open; when the window opens or
-- closes it slides there instead of jumping
local TIP_NEAR = W.TIP_GAP
ui.tipOffset = TIP_NEAR
function ui.PlaceTip()
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", ui.list, "TOPRIGHT", ui.tipOffset, 0)
end
local function Slide()
    if tip:IsShown() and tip:GetOwner() == ui.list then ui.PlaceTip() end
end
-- Where it goes now: beside the filter window (however wide) once the list stands and the window is wanted,
-- else beside the list; asked again whenever one of these changes (Filters.lua). atOnce: it jumps.
function ui.MoveTip(atOnce)
    local panel = ui.filterPanel
    local target = ui.filterWanted and ui.Since("list") and (ui.FILTER_GAP + panel:GetWidth() + W.TIP_GAP) or TIP_NEAR
    if atOnce then
        W.Follow(ui, "tipOffset", nil)
        ui.tipOffset = target
        Slide()
    else
        W.Follow(ui, "tipOffset", target, Slide)
    end
end

-- An item whose data the client has not loaded would show "retrieving item information": its tooltip waits for
-- the data (rows request it when they show, List.lua), at most TOOLTIP_WAIT, then shows what there is and fills
-- in later.
local TOOLTIP_WAIT = W.TOOLTIP_WAIT

function ui.ShowTooltip(entry)
    local list = ui.list
    list.tooltipWaiting = nil
    -- not while the search closes (a menu line that closes it would show the tooltip again, and it would stay)
    if not (entry and list:IsShown()) or entry.scope or entry.filter or not ui.MarkVisible()
        or S.closingAt or not ui.bar:IsShown() then
        tip:Hide()
        return
    end
    if tip:IsShown() and tip:GetOwner() == list and list.tooltipEntry == entry then return end
    list.tooltipEntry = entry
    local item = entry.itemID
    if item and not C_Item.IsItemDataCachedByID(item) then
        C_Item.RequestLoadItemDataByID(item)
        if (list.waitedFor ~= entry) or GetTime() - (list.waitingSince or 0) < TOOLTIP_WAIT then
            if list.waitedFor ~= entry then list.waitedFor, list.waitingSince = entry, GetTime() end
            list.tooltipWaiting = entry
            tip:Hide()
            Watch()
            return
        end
    end
    tip:SetOwner(list, "ANCHOR_NONE")
    ui.PlaceTip()
    ui.FillTooltip(tip, entry)
    ShowMade(entry.target or entry)
end

-- The watcher checks every frame (cheap) for a tooltip waiting for its item's data and shows it once it is there
-- or the wait is over; tooltips showing "retrieving" are refilled five times a second for a few seconds. It
-- hides itself when nothing waits.
watch:SetScript("OnUpdate", function(self)
    local list, now = ui.list, GetTime()
    local waiting = list.tooltipWaiting
    if waiting and (C_Item.IsItemDataCachedByID(waiting.itemID) or now - list.waitingSince >= TOOLTIP_WAIT) then
        ui.ShowTooltip(waiting)
    end
    if now < nextCheck then return end
    nextCheck = now + REFILL_EVERY
    local busy = list.tooltipWaiting ~= nil
    if tip:IsShown() and tip:GetOwner() == list and list.tooltipEntry and Retrieving(tip)
            and now - (tip.fillSince or 0) < REFILL_FOR then
        refilling = true
        ui.FillTooltip(tip, list.tooltipEntry)
        refilling = false
        busy = true
    end
    local detail = ui.detail
    if detail:IsShown() and S.detail and Retrieving(detail.tip) and now - (detail.tip.fillSince or 0) < REFILL_FOR then
        refilling = true
        ui.RefillDetail()
        refilling = false
        busy = true
    end
    if not busy then self:Hide() end
end)
