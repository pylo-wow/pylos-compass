local ns = select(2, ...).search
if ns.off then return end
local L = ns.L
local D = ns.data

-- Context menu: a right click on a result (or the detail view's symbol, or a filter) opens the menu
-- (UI\Kit\Widgets.lua) at the cursor: what can be done with the entry without opening it first.
-- Casting and using are not in it (protected: only the detail view's and Ctrl+Enter's secure buttons can);
-- opening a profession window is, as a casting line. Escape or a new list close it too; the keys walk it
-- (Input.lua).

local W = ns.widgets
local ui = ns.ui
local bar = ui.bar
local MENU_LEVEL = 40 -- above the bar and its windows

local function Disarm()
    if not InCombatLockdown() then ns.input.ArmEnter(nil) end
end
local menu = W.Menu({
    parent = bar, strata = "FULLSCREEN_DIALOG", level = bar:GetFrameLevel() + MENU_LEVEL, tooltip = ui.tip,
    onMark = function(slot)
        if not InCombatLockdown() then
            ns.input.ArmEnter(slot and (slot.spell and { type = "spell", value = slot.spell }
                or slot.macro and { type = "macro", value = slot.macro }) or nil)
        end
    end,
    onHide = Disarm,
})
local OpenMenu = menu.Open

function ui.MenuShown() return menu:IsShown() end
function ui.HideMenu()
    menu:Hide()
    Disarm()
end
ui.MenuStep, ui.MenuConfirm = menu.Step, menu.Confirm

local SYMBOLS = W.SYMBOLS
local function SymbolOf(file) return file and { file = file, crop = true } or nil end

-- The group finder's activities of an instance (its wings: Scarlet Monastery has four), nil if it has none or
-- the client lacks the finder. Forever's is vanilla-style (Blizzard_GroupFinder_VanillaStyle, loaded on demand
-- by GroupFinderVanillaStyle_LoadUI; LFGBrowseFrame:ShowSearchForActivities opens its browse tab and
-- searches); categories: 2 dungeons, 114 raids (DB2 GroupFinderCategory); map from C_LFGList.GetActivityInfoTable.
local GROUP_CATEGORIES = { 2, 114 }
local function GroupActivities(mapID)
    if not (GroupFinderVanillaStyle_LoadUI and C_LFGList and C_LFGList.GetAvailableActivities
            and C_LFGList.GetActivityInfoTable) then
        return nil
    end
    local found = {}
    for _, category in ipairs(GROUP_CATEGORIES) do
        for _, activityID in ipairs(C_LFGList.GetAvailableActivities(category) or {}) do
            local info = C_LFGList.GetActivityInfoTable(activityID)
            if info and info.mapID == mapID then found[#found + 1] = activityID end
        end
    end
    return #found > 0 and found or nil
end

-- the menu of an entry (fromDetail: its detail view is open already; byKey: opened with the space bar,
-- below the detail view's symbol). The same groups for every kind (empty ones left out):
--   open   the main line first (its profession window, the quest log, else Details)
--   lists  its links in the order its kind needs them (Links\Order.lua)
--   do     tools, waypoint, trying on, the action bar, the chat
--   bar    your word on it as a suggestion, forgetting your choices
function ui.ShowMenu(entry, fromDetail, byKey)
    if not entry or entry.header then return end
    local target = entry.target or entry
    local plain = not target.scope and not target.filter
    local look, lists, act, rate = {}, {}, {}, {}
    -- a recipe of yours, or an item one of your professions makes: its profession window, at that recipe; the
    -- main line. (Not "x and f()": "and" keeps only the first of the two results.)
    local recipeID, skillLine = D.CraftingRecipe(target)
    local window = recipeID and D.ProfessionWindowSpell(skillLine)
    if window then
        look[#look + 1] = { L["Open %s"]:format(window), function() ns.Close() end, window,
            icon = SymbolOf(ns.professionIcons[skillLine]), main = true }
    end
    -- a quest of your log: the quest log at it (Forever's is the world map's: QuestMapFrame_OpenToQuestDetails);
    -- the main line
    local questID = target.questID
    local inLog = questID and QuestMapFrame_OpenToQuestDetails and C_QuestLog.IsOnQuest(questID)
    if inLog then
        look[#look + 1] = { L["Open in quest log"], function()
            ns.Close()
            QuestMapFrame_OpenToQuestDetails(questID)
        end, icon = SYMBOLS.questLog, main = not window }
    end
    if not fromDetail and plain then
        look[#look + 1] = { L["Details"], function() ns.view.Open(target) end, icon = SYMBOLS.details,
            main = not window and not inLog }
    end
    if plain then
        for _, option in ipairs(ns.view.Options(target)) do
            if option.kind == "link" then
                lists[#lists + 1] = { option.text, function() ns.view.OpenLink(target, option.link) end,
                    icon = SymbolOf(option.link.icon) }
            elseif option.kind == "tool" then
                act[#act + 1] = { option.text, function() ns.view.RunTool(target, option.tool) end,
                    icon = option.tool.icon and SymbolOf(option.tool.icon) or SYMBOLS.tool }
            end
        end
    end
    -- a waypoint on the map where the NPC stands or the dungeon's entrance
    -- is (place = uiMapID * 1000000 + x * 1000 + y, x and y in thousandths)
    local place = target.place
    if place and C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        act[#act + 1] = { L["Set waypoint"], function() W.Waypoint(target.name, place) end, icon = SYMBOLS.waypoint }
    end
    local activities = target.mapID and GroupActivities(target.mapID)
    -- C_LFGList.Search is protected: called from addon code it was blocked and the finder hung at "Searching...";
    -- so the line is a secure button running it as a macro on your click, as a line that casts does
    if activities and not InCombatLockdown() then
        local macro = ("/run GroupFinderVanillaStyle_LoadUI() LFGBrowseFrame:ShowSearchForActivities({%s})")
            :format(table.concat(activities, ","))
        act[#act + 1] = { L["Find a group"], function() ns.Close() end, macro = macro,
            icon = SymbolOf(136334) } -- LFGIcon-Dungeon
    end
    if target.itemID and (target.itemClass == 2 or target.itemClass == 4) and DressUpItemLink then
        act[#act + 1] = { L["Try on"], function() DressUpItemLink(ui.EntryLink(target)) end, icon = SYMBOLS.tryOn }
    end
    -- onto an action bar: the cursor takes it, as from the spell book (its own icon: that is what lands on the bar)
    local spellID = target.type == "spell" and target.value
    local onBar = (target.itemID and C_Item.GetItemCount(target.itemID) > 0)
        or (spellID and not D.SpellPassive(spellID))
    if onBar and not InCombatLockdown() then
        act[#act + 1] = { L["Put on action bar"], function() ui.Pickup(target) end, icon = SymbolOf(target.icon) }
    end
    local link = ui.EntryLink(target)
    if link then
        act[#act + 1] = { L["Link in chat"], function()
            ns.Close()
            if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(link)
            elseif ChatFrame_OpenChat then
                ChatFrame_OpenChat(link)
            end
        end, icon = SYMBOLS.chat }
    end
    -- a suggestion: your word on it (its reasons rise or sink for you), never again or again
    local id = plain and target.source and ns.EntryID(target)
    if id and ns.rec.IsHidden(id) then
        rate[#rate + 1] = { SYMBOLS.unhide, L["Suggest again"], function() ns.view.HideSuggestion(target, false) end }
    elseif id and ns.rec.Fit(target) > 0 then
        rate[#rate + 1] = { SYMBOLS.good, L["Good suggestion"], function() ns.view.Feedback(target, true) end }
        rate[#rate + 1] = { SYMBOLS.bad, L["Bad suggestion"], function() ns.view.Feedback(target, false) end }
        rate[#rate + 1] = { SYMBOLS.hide, L["Don't suggest"], function() ns.view.HideSuggestion(target, true) end }
    end
    local known = plain and ns.EntryID(target)
    if known and (ns.memory.Knows(known) or ns.rec.Knows(known)) then
        rate[#rate + 1] = { SYMBOLS.forget, L["Forget my choices"], function() ns.view.Forget(target) end }
    end
    ui.menuGroups = { look, lists, act } -- (the last menu's lines: the test harness reads them)
    -- anchored to the icon's button (a frame): the menu holds secure buttons, and a protected frame's anchors
    -- cannot lead to a texture (UI\Detail.lua)
    OpenMenu(ui.menuGroups, byKey and ui.detail.iconButton or nil, rate)
end

function ui.ShowFilterMenu(f)
    OpenMenu({ { { L["Only this filter"], function() ns.view.OnlyFilter(f) end, icon = SymbolOf(f.icon) } } })
end

-- the menu of a category tab: hide it (the options' switch brings it back)
function ui.ShowCategoryMenu(source)
    OpenMenu({ { { L["Hide category"], function() ns.SetOption("source_" .. source.key, false) end } } })
end
