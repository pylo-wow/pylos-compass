local ns = select(2, ...).advice
local D = ns.data
local L = ns.L
local W = ns.widgets -- shared with the search window

-- Recommendations window (minimap middle click or key), built from the widgets shared with the search (Widgets.lua).
--   tabs: one per topic (Reasons.lua), always one set (no all-in-one list: what is important now comes as a nudge,
--   Push.lua). Each counts its suggestions; empty ones are dimmed; close tab at the right end.
--   subtopics: side tabs (Subtopics.lua, W.SideTabs); the set one narrows the list, clicking it again clears it.
--   list: best first (ns.RelevantByTopic); row = icon, name, category, strongest reason's note (text, or symbol with
--   count). Hover shows the game's tooltip with every reason beside the window.
--   click: uses/equips an item, casts a spell, opens a recipe's profession window (secure: left click, out of
--   combat), sets a waypoint, or (Quests tab) opens the quest in the quest log.
--   right click: the search's menu (quest log, search, waypoint, good/bad/don't suggest).
-- Draggable (rows too), anchored at its top left so a shorter list shrinks upwards. Updates on open and soon after
-- changes (events, no timer), not while the mouse is over it.
-- Animation as the search's; rows do not slide in (they change on each update). Closes before combat: secure
-- buttons cannot change in combat.

local ROWS = 10
local SCROLL_STEP = 2   -- rows one tick of the mouse wheel moves
local SEEN_AFTER = 1.5  -- seconds the wheel rests before the rows it stopped on count as seen
local ALL = 999           -- a topic's list in full (its tab counts it)
local PER_DOMAIN = 4      -- at most this many of one kind per list
local AWAY = 10 * 60      -- seconds closed: then it opens at the tab worth most, else where you were
-- shared with the search (Widgets.lua)
local WIDTH, ROW_HEIGHT, NAME_X = W.WIDTH, W.ROW_HEIGHT, W.NAME_X
local TAB, TAB_GAP = W.TAB_SIZE, W.TAB_GAP
local DOT = W.DOT
local SOON = 0.5          -- seconds after something changed
local BACKGROUND = 0.85   -- opacity when the search window's is not there
local TOOLTIP_WAIT = W.TOOLTIP_WAIT
local NONE = {}

-- tabs: one per topic in Reasons.lua's TOPICS order. Symbol: an icon (file ID or path), optionally a part of a file
-- (micro menu symbols); same symbols as the search's category tabs. A topic without one gets a question mark.
local SYMBOLS = {
    class = {},                                     -- your class's symbol
    gear = { icon = 132627 },                       -- INV_Chest_Chain_05
    -- crossed tools of Forever's character window tabs
    professions = { icon = 2447783 },
    quests = { icon = 134327, part = W.QUEST_PART }, -- the quest log's exclamation mark
    supplies = { icon = 133641 },                   -- INV_Misc_Bag_10_Blue
    dungeons = { icon = 136334, part = W.EYE_PART }, -- the group finder's green eye
    zones = { icon = 134269 },                      -- INV_Misc_Map_01
}
local TABS = {}
for _, topic in ipairs(ns.reasons.TOPICS) do TABS[#TABS + 1] = { key = topic.key, name = topic.name } end
for _, tab in ipairs(TABS) do
    local symbol = SYMBOLS[tab.key] or { icon = 134400 } -- INV_Misc_QuestionMark
    tab.icon, tab.part = symbol.icon, symbol.part
end

local window

-- background opacity 0..1: the search's "Background" option, else 85 %
local function Background()
    local alpha = tonumber(D.search.BackgroundAlpha())
    if not alpha then return BACKGROUND end
    return alpha > 1 and alpha / 100 or alpha
end

-- What a click does
-- kind ("item", "spell": secure; "quest", "waypoint", "map"), its value, the tooltip's words

-- opens a quest of the log (the search's rule, Search\UI\Menu.lua)
local function OpenQuest(questID)
    if D.search.QuestInLog(questID) then
        QuestMapFrame_OpenToQuestDetails(questID)
    else
        W.Error(L["This quest is not in your quest log."])
    end
end

-- world map at a zone (OpenWorldMap, Blizzard_WorldMap, loaded first if needed)
local function OpenMap(zoneID)
    if not OpenWorldMap and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    if OpenWorldMap then OpenWorldMap(zoneID) end
end

-- returns kind, value and tooltip text for an entry's click
local function Action(entry)
    if entry.domain == "quests" then return "quest", entry.questID, L["Click: open the quest"] end
    local itemID = entry.itemID
    if itemID and C_Item.GetItemCount(itemID) > 0 then
        if entry.itemClass == 2 or entry.itemClass == 4 then return "item", "item:" .. itemID, L["Click: put it on"] end
        local GetSpell = C_Item.GetItemSpell
        if entry.itemClass == 9 or (GetSpell and GetSpell(itemID)) then
            return "item", "item:" .. itemID, L["Click: use it"]
        end
    end
    if entry.domain == "spells" and not entry.hidden and entry.spellID and not D.SpellPassive(entry.spellID) then
        return "spell", entry.spellID, L["Click: cast it"]
    end
    -- recipe, or item made by one of your recipes: its profession window (casting the recipe does nothing
    -- without it open)
    if entry.domain == "professions" or (itemID and entry.domain == "items") then
        local spell = D.search.ProfessionWindow(entry)
        if spell then return "spell", spell, L["Click: open %s"]:format(spell) end
    end
    if entry.place and C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        return "waypoint", entry.place, L["Click: set a waypoint"]
    end
    if entry.zoneID then return "map", entry.zoneID, L["Click: open the map"] end
    return nil
end

-- Tooltip
-- Own tooltip beside the list as the search's (GameTooltip would add the equipped-item comparison, covering the list)

local tip = CreateFrame("GameTooltip", "PylosCompassWindowTooltip", UIParent, "GameTooltipTemplate")
-- Item-tooltip addons that honour this flag skip the tooltip (it already has the "Why" lines)
tip.noUpgradeLines = true
tip:SetFrameStrata("TOOLTIP")

-- Gear: with the compare key held (IsModifiedClick "COMPAREITEMS") show what you wear beside it
-- (GameTooltip_ShowCompareItem, Blizzard_GameTooltip). The comparison needs tooltip.shoppingTooltips, which only the
-- GameTooltip gets at load (a nil there is a Lua error in the game): ours borrows the game's two, as only one
-- tooltip shows at a time.
if ShoppingTooltip1 and ShoppingTooltip2 then tip.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 } end

local function Compare(entry)
    if not tip.shoppingTooltips then return end
    local gear = entry.itemID and (entry.itemClass == 2 or entry.itemClass == 4)
    if gear and IsModifiedClick and IsModifiedClick("COMPAREITEMS") and GameTooltip_ShowCompareItem then
        GameTooltip_ShowCompareItem(tip, tip)
    elseif GameTooltip_HideShoppingTooltips then
        GameTooltip_HideShoppingTooltips(tip)
    end
end

local hovered -- the row the mouse is over (its tooltip follows the compare key)

-- row whose tooltip waits for its item's data, and since when (an unloaded item's tooltip would say "Retrieving
-- item information")
local waiting, waitingSince

local function Tooltip(row, waited)
    waiting = nil
    local item = row.item
    if not item then return end
    local entry, list = item.entry, row:GetParent()
    if entry.itemID and not waited and not C_Item.IsItemDataCachedByID(entry.itemID) then
        C_Item.RequestLoadItemDataByID(entry.itemID)
        waiting, waitingSince = row, GetTime()
        tip:Hide()
        return
    end
    tip:SetOwner(list, "ANCHOR_NONE")
    tip:ClearAllPoints()
    -- beside the window, on the side with room
    -- (the window may be scaled: its right edge in the screen's units)
    local toScreen = list:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if (list:GetRight() or 0) * toScreen + 330 > (UIParent:GetRight() or 0) then
        tip:SetPoint("TOPRIGHT", list, "TOPLEFT", -W.TIP_GAP, 0)
    else
        tip:SetPoint("TOPLEFT", list, "TOPRIGHT", W.TIP_GAP, 0)
    end
    if entry.itemID then
        tip:SetItemByID(entry.itemID)
    elseif entry.spellID and entry.domain ~= "npcs" then
        tip:SetSpellByID(entry.spellID)
    else
        -- NPC, quest, dungeon: name and lines as in the search (World\Lines.lua), else its category
        if not W.EntryText(tip, entry) and entry.category then
            tip:AddLine(entry.category, W.SUB[1], W.SUB[2], W.SUB[3])
        end
    end
    -- why (incl. what the row carries), a quest's still-to-do and the click text: format shared with the search
    -- (Widgets.lua)
    local why = ns.Explain(entry)
    for _, carried in ipairs(item.carries or NONE) do
        local note = ns.reasons.NoteText(ns.Note(carried))
        why[#why + 1] = note and L["%s: %s"]:format(carried.name, note) or carried.name
    end
    W.AddWhy(tip, why, entry.domain == "quests" and ns.QuestNeeds(entry.questID) or nil, row.actionText)
    tip:Show()
    Compare(entry)
end

-- compare key changed over a row: redraw its tooltip
ns.On("MODIFIER_STATE_CHANGED", function()
    if hovered and hovered:IsVisible() and hovered.secure:IsMouseOver() and not waiting then Tooltip(hovered, true) end
end)

-- Rows

-- row under the mouse: lit, name in gold; unlearned entries (trainer spell, recipe) dimmed, as in the search
local function Mark(row, on)
    local entry = row.item and row.item.entry
    W.MarkRow(row, on, entry and entry.hidden == true)
end

-- Right-click menu, the search's wording and order: quest log first (own quest, or the quest an item/NPC is needed
-- for), entry and quest in the search, waypoint, then your rating.
local function Menu(row)
    local entry = row.item and row.item.entry
    if not entry then return end
    local ICONS = W.SYMBOLS
    local own = entry.domain == "quests" -- the row is the quest itself
    local questID, title
    if own then questID, title = entry.questID, entry.name else questID, title = ns.QuestNeedOf(entry) end
    local function Then(action)
        return function()
            action()
            window.Update(true)
        end
    end
    -- the search takes over: the window closes (in combat the search does not open, so it stays)
    local function InSearch(id, name)
        if not InCombatLockdown() then window.Close() end
        D.search.Show(id, name)
    end
    local look, act, rate = {}, {}, {}
    if questID then
        look[#look + 1] = { own and L["Open in quest log"] or L["Open %s in quest log"]:format(title),
            function() OpenQuest(questID) end, icon = ICONS.questLog }
    end
    if ns.db.searchOn ~= false then
        look[#look + 1] = { L["Search"], function() InSearch(D.EntryID(entry), entry.name) end,
            icon = ICONS.details }
        if questID and not own then
            look[#look + 1] = { L["Find the quest in the search"], function() InSearch("q:" .. questID, title) end,
                icon = ICONS.details }
        end
    end
    if look[1] then look[1].main = true end
    if entry.place and C_Map.SetUserWaypoint and UiMapPoint then
        act[#act + 1] = { L["Set waypoint"], function() W.Waypoint(entry.name, entry.place) end, icon = ICONS.waypoint }
    end
    -- rating, confirmed at the top of the screen as in the search
    rate[1] = { ICONS.good, L["Good suggestion"], Then(function()
        ns.Feedback(entry, true)
        W.Notice(L["Noted: suggestions like this count more for you."])
    end) }
    rate[2] = { ICONS.bad, L["Bad suggestion"], Then(function()
        ns.Feedback(entry, false)
        W.Notice(L["Noted: suggestions like this count less for you."])
    end) }
    rate[3] = { ICONS.hide, L["Don't suggest"], Then(function() ns.Hide(entry) end) }
    window.menu.Open({ look, act }, nil, rate)
end

-- a row's place; right: room kept free at its right (the scroll bar's, while the list scrolls)
local function AnchorRow(row, right)
    local top = -(6 + (row.index - 1) * ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 6, top)
    row:SetPoint("TOPRIGHT", -6 - right, top)
end

local function Row(list, i)
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row.index = i
    AnchorRow(row, 0)
    -- icon, quality, count, note symbol, status, name, category (Widgets.lua)
    W.RowParts(row, ROW_HEIGHT)
    -- dot for quiet-nudged entries (Push.lua)
    row.nudge = row:CreateTexture(nil, "OVERLAY", nil, 7)
    row.nudge:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    row.nudge:SetSize(14, 14)
    row.nudge:SetPoint("CENTER", row.icon, "TOPLEFT", 1, -1)
    row.nudge:Hide()
    row.highlight:Hide()
    -- the whole row is a secure button (casting and using need one), acting on left-click release
    local secure = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    secure:SetAllPoints()
    secure:RegisterForClicks("AnyDown", "AnyUp")
    secure:SetAttribute("useOnKeyDown", false)
    row.secure = secure
    -- dragging a row moves the window
    secure:RegisterForDrag("LeftButton")
    secure:EnableMouseWheel(true)
    secure:SetScript("OnMouseWheel", function(_, delta) window.Scroll(window, delta) end)
    secure:SetScript("OnDragStart", function() window:GetScript("OnDragStart")(window) end)
    secure:SetScript("OnDragStop", function() window:GetScript("OnDragStop")(window) end)
    secure:SetScript("OnEnter", function()
        hovered = row
        Mark(row, true)
        Tooltip(row)
    end)
    secure:SetScript("OnLeave", function()
        if hovered == row then hovered = nil end
        if waiting == row then waiting = nil end
        if tip.shoppingTooltips and GameTooltip_HideShoppingTooltips then GameTooltip_HideShoppingTooltips(tip) end
        tip:Hide()
        Mark(row, false)
    end)
    secure:SetScript("PostClick", function(self, button, down)
        if down or not row.item then return end
        if button == "RightButton" then return Menu(row) end
        if button ~= "LeftButton" then return end
        -- not noted as chosen: that counts as done and the row stepped back at once; real actions are noted by the
        -- memory (Memory.lua Did)
        if row.kind == "waypoint" then W.Waypoint(row.item.entry.name, row.value) end
        if row.kind == "quest" then OpenQuest(row.value) end
        if row.kind == "map" then OpenMap(row.value) end
    end)
    return row
end

-- grey line below the name: the category; dungeons as in the search: kind, levels, entrance zone if known
local DUNGEON_KINDS = D.DUNGEON_KINDS
local function Describe(entry)
    -- quest: level, then first open objective ("+2" for more; the tooltip lists all), else its zone
    if entry.domain == "quests" then
        local needs = ns.QuestNeeds(entry.questID)
        if needs[1] then
            local more = #needs > 1 and (" +" .. (#needs - 1)) or ""
            return L["Level %d"]:format(entry.level) .. DOT .. needs[1].text .. more
        end
        local info = entry.zone and C_Map.GetMapInfo(entry.zone)
        return table.concat({ L["Level %d"]:format(entry.level), info and info.name or nil }, DOT)
    end
    -- a zone: its continent and the levels of most of its quests
    if entry.domain == "zones" then
        local low, high = D.ZoneLevels(entry.zoneID)
        local levels = low and (low < high and L["Level %d-%d"]:format(low, high) or L["Level %d"]:format(low))
        return table.concat({ entry.category or "", levels }, DOT)
    end
    if entry.domain ~= "dungeons" then return entry.category or "" end
    local parts = { DUNGEON_KINDS[entry.kind] }
    if entry.maxLevel > entry.level then
        parts[#parts + 1] = L["Level %d-%d"]:format(entry.level, entry.maxLevel)
    elseif entry.level > 0 then
        parts[#parts + 1] = L["Level %d"]:format(entry.level)
    end
    local info = entry.zone and entry.zone > 0 and C_Map.GetMapInfo(entry.zone)
    if info and info.name then parts[#parts + 1] = info.name end
    return table.concat(parts, DOT)
end

-- shown to you: Learning watches whether you follow it (only what you saw counts), also what the row carries
local function MarkSeen(row)
    local item = row.item
    if not item then return end
    ns.Shown(item.entry, nil, row.rank)
    for _, carried in ipairs(item.carries or NONE) do ns.Shown(carried, nil, row.rank) end
end

-- fills a row: the item or nothing; arms its secure button. scrolling: the rows only pass by, they count as seen
-- once the wheel rests (Scroll)
local function Fill(row, item, rank, scrolling)
    row.item, row.rank = item, rank
    row:SetShown(item ~= nil)
    if not item then return end
    local entry = item.entry
    if not scrolling then MarkSeen(row) end
    if entry.itemID and not C_Item.IsItemDataCachedByID(entry.itemID) then
        C_Item.RequestLoadItemDataByID(entry.itemID)
    end
    W.ShowIcon(row.icon, entry, nil, 134400)
    row.icon:SetDesaturated(entry.hidden == true)
    W.ShowQuality(row.quality, entry)
    local count = entry.itemID and C_Item.GetItemCount(entry.itemID) or 0
    row.count:SetText(count > 1 and count or "")
    row.name:SetText(entry.name)
    row.nudge:SetShown(window.nudged[entry] == true)
    -- right, from the edge: the note's symbol, the text
    local note = ns.Note(entry)
    local noteText = type(note) == "string" and note or nil
    local symbol = type(note) == "table" and note.icon and note or nil
    row.reason:SetShown(symbol ~= nil)
    if symbol then row.reason:SetTexture(symbol.icon) end
    row.reasonText:SetText(symbol and symbol.count and tostring(symbol.count) or "")
    row.reason:ClearAllPoints()
    row.reason:SetPoint("RIGHT", -10, 0)
    row.status:ClearAllPoints()
    if symbol then row.status:SetPoint("RIGHT", row.reason, "LEFT", -8, 0) else row.status:SetPoint("RIGHT", -10, 0) end
    row.status:SetText(noteText or "")
    -- name and category end before the right side
    local used = 10 + (symbol and 22 or 0) + (noteText and row.status:GetStringWidth() + 8 or 0)
    local right = -(used + 12)
    -- the name in the middle, or above its category
    local sub = Describe(entry)
    row.sub:SetText(sub)
    row.sub:SetPoint("RIGHT", row, "RIGHT", right, 0)
    row.name:ClearAllPoints()
    if sub ~= "" then
        row.name:SetPoint("BOTTOMLEFT", row, "LEFT", NAME_X, 1)
    else
        row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    end
    row.name:SetPoint("RIGHT", row, "RIGHT", right, 0)
    local kind, value, text = Action(entry)
    row.kind, row.value, row.actionText = kind, value, text
    local secure = kind == "item" or kind == "spell"
    row.secure:SetAttribute("type1", secure and kind or nil)
    row.secure:SetAttribute("item", kind == "item" and value or nil)
    row.secure:SetAttribute("spell", kind == "spell" and value or nil)
    Mark(row, row.secure:IsMouseOver())
end

-- Window

-- tabs in their row: the set one stands out; on open they rise from under the window in turn, the close tab last
-- (Widgets.lua times). Returns whether they still move.
local function PlaceTabs(now)
    local since = now - (window.tabsAt or 0)
    for i, tab in ipairs(window.tabs) do
        local ease = W.EaseOutCubic(W.Clamp((since - (i - 1) * W.TAB_STAGGER) / W.FADE_TIME))
        tab:SetAlpha(ease)
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", (i - 1) * (TAB + TAB_GAP), (tab.on and W.TAB_OUT or 0) - W.TAB_RISE * (1 - ease))
    end
    local tabsDone = (#window.tabs - 1) * W.TAB_STAGGER + W.FADE_TIME
    local ease = W.EaseOutCubic(W.Clamp((since - tabsDone - W.CLOSE_TAB_DELAY) / W.CLOSE_TAB_TIME))
    window.close:SetAlpha(ease)
    window.close:ClearAllPoints()
    window.close:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", -W.TAB_INSET, -2 - W.TAB_RISE * (1 - ease))
    return ease < 1
end

-- height follows the list (grows/shrinks downwards from the top); rows below the edge show as it reaches them.
-- Returns whether it still moves.
local function FollowHeight(elapsed)
    local target, height = window.targetHeight, window:GetHeight()
    local moving = math.abs(target - height) >= 0.5
    height = moving and height + (target - height) * math.min(1, elapsed * W.FOLLOW) or target
    window:SetHeight(height)
    for i, row in ipairs(window.rows) do
        row:SetAlpha(W.Clamp((height - 6 - (i - 1) * ROW_HEIGHT) / ROW_HEIGHT))
    end
    window.side.Place() -- subtopic tabs below the edge show as it reaches them
    return moving
end

-- the rows from the scroll offset (the list is longer than the rows: the wheel or the scroll bar scrolls it)
local function FillRows(scrolling)
    local list, offset = window.list or NONE, window.offset or 0
    -- the rows leave room for the scroll bar while it shows (not in combat: the rows hold secure buttons)
    local more = #list > ROWS
    if window.scroll:IsShown() ~= more and not InCombatLockdown() then
        window.scroll:SetShown(more)
        for _, row in ipairs(window.rows) do AnchorRow(row, more and W.SCROLL_ROOM or 0) end
    end
    for i, row in ipairs(window.rows) do Fill(row, list[offset + i], offset + i, scrolling) end
    window.scroll.Place()
end

local function Show()
    if InCombatLockdown() then return end -- secure buttons are locked
    D.RefreshOwned()
    -- whole lists so the tabs can count them (Relevant.lua's: read only, never change); the first ROWS show
    local lists = ns.RelevantByTopic(ALL, PER_DOMAIN)
    window.lists = lists
    -- always one tab set: the kept one, else the first with suggestions
    local current = ns.db.windowTab
    local known = false
    for _, tab in ipairs(window.tabs) do known = known or tab.key == current end
    if not known then
        current = window.tabs[1].key
        for _, tab in ipairs(window.tabs) do
            if #(lists[tab.key] or NONE) > 0 then current = tab.key break end
        end
        ns.db.windowTab = current
    end
    local list = lists[current] or NONE
    -- the tab's subtopics at the left (Subtopics.lua); the set one narrows the list
    local subs = ns.Subtopics(current, list)
    local set
    for _, sub in ipairs(subs) do
        if sub.key == ns.db.windowSub[current] then set = sub end
    end
    if set then
        local narrowed = {}
        for _, item in ipairs(list) do
            if set.test(item.entry) then narrowed[#narrowed + 1] = item end
        end
        list = narrowed
    end
    window.side.Show(subs, set and set.key)
    -- quiet-nudged entries of the tab looked at come first, with the dot, until the window closes
    for entry in pairs(ns.push.SeenTopic(current)) do window.nudged[entry] = true end
    local first, rest = {}, {}
    for _, item in ipairs(list) do
        if window.nudged[item.entry] then first[#first + 1] = item else rest[#rest + 1] = item end
    end
    if #first > 0 then
        for _, item in ipairs(rest) do first[#first + 1] = item end
        list = first
    end
    -- a new tab or subtopic starts at the top; a list that grew or shrank keeps the place as far as it can
    local view = current .. "/" .. (set and set.key or "")
    if window.view ~= view then window.view, window.offset = view, 0 end
    window.list = list
    window.offset = math.max(0, math.min(window.offset or 0, #list - ROWS))
    FillRows()
    window.empty:SetShown(#list == 0)
    for _, tab in ipairs(window.tabs) do
        tab.count = #(lists[tab.key] or NONE)
        W.LightTab(tab, tab.key == current, tab.count == 0)
        -- count on the icon; a very long list shows as "99+"
        local number = tab.count > 99 and "99+" or tab.count > 0 and tostring(tab.count) or ""
        tab.number:SetText(number)
        tab.dot:SetShown(ns.push.QuietTopic(tab.key))
    end
    window.tabsMoving = true -- OnUpdate places the tabs
    -- list height: followed in OnUpdate, at once on open (at least the subtopic tabs' height)
    window.targetHeight = math.max(12 + math.max(math.min(#list, ROWS), 1) * ROW_HEIGHT, window.side.height)
    if window.snapHeight then
        window.snapHeight = nil
        window:SetHeight(window.targetHeight)
    end
    window.heightMoving = true
end

-- shows the rows from a first one (0-based): the wheel and the scroll bar come here
local function ScrollTo(first)
    local list = window.list or NONE
    first = math.max(0, math.min(first, #list - ROWS))
    if first == (window.offset or 0) then return end
    window.offset = first
    hovered = nil
    tip:Hide()
    FillRows(true)
    -- the rows the wheel stops on were seen, those that flew by were not
    local scrolledAt = GetTime()
    window.scrolledAt = scrolledAt
    C_Timer.After(SEEN_AFTER, function()
        if window.scrolledAt ~= scrolledAt or not window:IsShown() then return end
        window.scrolledAt = nil
        for _, row in ipairs(window.rows) do MarkSeen(row) end
    end)
    for _, row in ipairs(window.rows) do -- the row under the mouse changed: its tooltip follows
        if row:IsShown() and row.secure:IsMouseOver() then
            hovered = row
            Mark(row, true)
            Tooltip(row)
        end
    end
end

-- the wheel moves the rows over the list (the rows and the window both take it: a row is under the mouse)
local function Scroll(_, delta) ScrollTo((window.offset or 0) - delta * SCROLL_STEP) end

-- re-anchor at the top left corner after moving (StartMoving anchors anew)
local function StartMoving() window:StartMoving() end
local function StopMoving()
    window:StopMovingOrSizing()
    local left, top = window:GetLeft(), window:GetTop()
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.window = { left, top }
end

-- where the window stands until it is dragged: its top right corner at the top left corner of the minimap button's
-- default spot (the kit puts the button on the minimap's rim at the angle of options.defaults.minimapAngle, default
-- 200 degrees, 31 units wide); the spot, not the button, so a dragged button does not move it. With no room there
-- (the minimap moved to an edge or a corner: the window, its tabs above and the subtopic tabs left of it would not
-- be all on the screen) it stands at a fixed place instead, from the top right corner of the screen.
local BUTTON_SIZE, BUTTON_GAP = 31, 2
local TABS_ABOVE, TABS_LEFT = TAB + 4, TAB + W.TAB_OUT + 4
local FIXED_RIGHT, FIXED_TOP = -260, -120

local function Placed()
    local saved = ns.db.window
    return saved ~= nil and type(saved[1]) == "number"
end

local function DefaultPlace()
    local angle = math.rad(D.options.defaults.minimapAngle or 200)
    local radius = Minimap:GetWidth() / 2 + 5
    local x = math.cos(angle) * radius - BUTTON_SIZE / 2 - BUTTON_GAP
    local y = math.sin(angle) * radius + BUTTON_SIZE / 2
    -- in the screen's units (UIParent's), the window at its own size; offsets count in the window's own scale
    local toScreen = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local size = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    local right, top = centerX and (centerX + x) * toScreen, centerY and (centerY + y) * toScreen
    window:ClearAllPoints()
    if ns.FitsScreen(right, top, WIDTH * size, (12 + ROWS * ROW_HEIGHT) * size, TABS_LEFT * size, TABS_ABOVE * size) then
        window:SetPoint("TOPRIGHT", Minimap, "CENTER", x * toScreen / size, y * toScreen / size)
    else
        window:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", FIXED_RIGHT / size, FIXED_TOP / size)
    end
end

-- the options' button: forget where it was dragged to, an open window moves back at once. In combat the window
-- cannot move (its row buttons are secure); it is closed then, and the next opening puts it at its default place.
function ns.ResetPosition()
    ns.db.window = {}
    if window and not InCombatLockdown() then DefaultPlace() end
end

-- the size of the window (option "adviceScale", percent); its top left corner stays where it is on the screen (the
-- default place counts anew: its corner stays at the button). Not in combat (as above): the next opening applies it.
function ns.ApplyScale()
    if not window or InCombatLockdown() then return end
    local old, new = window:GetScale(), (ns.db.adviceScale or 100) / 100
    if math.abs(old - new) < 0.001 then return end
    if not Placed() then
        window:SetScale(new)
        DefaultPlace()
        return
    end
    local left, top = window:GetLeft(), window:GetTop()
    window:SetScale(new)
    if left and top then
        left, top = left * old / new, top * old / new
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        ns.db.window = { left, top }
    end
end

local function Build()
    window = CreateFrame("Frame", "PylosCompassWindow", UIParent)
    window:SetSize(WIDTH, 12 + ROWS * ROW_HEIGHT)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(10) -- room below for its frame and the tabs
    window:SetClampedToScreen(true)
    window:SetScale((ns.db.adviceScale or 100) / 100)
    window:SetMovable(true)
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", Scroll)
    window.Scroll = Scroll
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", StartMoving)
    window:SetScript("OnDragStop", StopMoving)
    if Placed() then
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.window[1], ns.db.window[2])
    else
        DefaultPlace()
    end
    W.SetBackground(Background())
    window.background = Background()
    W.Panel(window)

    -- tabs on top of the window, below its frame, so they come out from under it
    local tabs = CreateFrame("Frame", nil, window)
    tabs:SetPoint("BOTTOMLEFT", window, "TOPLEFT", W.TAB_INSET, -2)
    tabs:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, -2)
    tabs:SetHeight(TAB)
    tabs:SetFrameLevel(math.max(window:GetFrameLevel() - 3, 0))
    window.tabs = {}
    for i, info in ipairs(TABS) do
        local tab = W.IconTab(tabs, TAB)
        tab.key = info.key
        local icon = info.icon
        if info.key == "class" then
            icon = "Interface\\Icons\\ClassIcon_" .. (select(2, UnitClass("player")) or "WARRIOR")
        end
        W.ShowIcon(tab.icon, { iconPart = info.part, icon = icon })
        -- count on its own layer above the icon (hovered tabs show in full, W.IconTab)
        local top = CreateFrame("Frame", nil, tab)
        top:SetAllPoints()
        top:SetFrameLevel(tab:GetFrameLevel() + 1)
        tab.number = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        tab.number:SetPoint("BOTTOMRIGHT", tab.icon, "BOTTOMRIGHT", 1, 0)
        -- dot for a quiet nudge of the topic, until the tab is looked at (Push.lua)
        tab.dot = top:CreateTexture(nil, "OVERLAY")
        tab.dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
        tab.dot:SetSize(14, 14)
        tab.dot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 2, 2)
        tab.dot:Hide()
        tab:SetScript("OnClick", function()
            ns.db.windowTab = info.key
            window.Update(true)
        end)
        tab:SetScript("OnEnter", function(self)
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText(info.name, W.WHITE[1], W.WHITE[2], W.WHITE[3])
            tip:AddLine(L["%d suggestions"]:format(self.count or 0), W.SUB[1], W.SUB[2], W.SUB[3])
            tip:Show()
        end)
        tab:SetScript("OnLeave", function() tip:Hide() end)
        window.tabs[i] = tab
    end
    -- close tab (placed by PlaceTabs)
    window.close = W.CloseTab(tabs, TAB, tip, function() window.Close() end)
    PlaceTabs(GetTime())

    -- subtopic tabs at the left edge as the search's subcategories; a click sets one for this tab, or clears it
    window.side = W.SideTabs(window, {
        tip = tip,
        room = function() return window:GetHeight() - W.TAB_INSET end,
        onClick = function(sub)
            local topic = ns.db.windowTab
            ns.db.windowSub[topic] = ns.db.windowSub[topic] ~= sub.key and sub.key or nil
            window.Update(true)
        end,
    })
    -- below the window's frame so the tabs come out from under it
    window.side.frame:SetPoint("TOPRIGHT", window, "TOPLEFT", 2, -W.TAB_INSET)
    window.side.frame:SetFrameLevel(math.max(window:GetFrameLevel() - 3, 0))

    window.rows = {}
    for i = 1, ROWS do window.rows[i] = Row(window, i) end
    -- the scroll bar of a list longer than the rows, the search's (Widgets.lua); the rows leave room for it (FillRows)
    window.scroll = W.ScrollBar(window, {
        state = function() return #(window.list or NONE), ROWS, window.offset or 0 end,
        scrollTo = ScrollTo,
    })
    window.empty = W.Empty(window)
    window.empty:SetText(L["Nothing to suggest here right now"])

    -- row menu, above the window (no keys)
    window.menu = W.Menu({ parent = window, strata = "DIALOG", level = window:GetFrameLevel() + 40, tooltip = tip })

    -- Escape fades it out: UISpecialFrames hides frames at once, so a stand-in is listed, shown while the window is;
    -- its hiding starts the fade. No parent: hiding the UI (Alt+Z) must not close the window.
    local escape = CreateFrame("Frame", "PylosCompassWindowEscape")
    escape:Hide()
    -- (a failed Build is tried again on the next toggle: listed once)
    if not tContains(UISpecialFrames, "PylosCompassWindowEscape") then
        tinsert(UISpecialFrames, "PylosCompassWindowEscape")
    end

    -- called by Toast.lua QuietChanged
    function ns.WindowDots()
        for _, tab in ipairs(window.tabs) do tab.dot:SetShown(ns.push.QuietTopic(tab.key)) end
    end
    window.nudged = {} -- entry -> true: quiet-nudged, shown first with the dot
    -- open: fades in, tabs rise, height set at once (a cut-short close resumes from its alpha)
    function window.Open()
        if not window:IsShown() then window.offset = 0 end -- opened again: from the top
        -- the glow told of a quiet nudge: open at its tab, no subtopic hiding it
        local topic = ns.push.WindowOpened()
        if topic then
            ns.db.windowTab = topic
            ns.db.windowSub[topic] = nil
            if window:IsShown() then window.Update(true) end
        elseif not window:IsShown() and (not window.closedAt or time() - window.closedAt > AWAY) then
            -- away a while (or first time this session): the tab whose best suggestion is worth most; back soon:
            -- where you were
            local best, bestScore = nil, 0
            local lists = ns.RelevantByTopic(ALL, PER_DOMAIN)
            for _, tab in ipairs(window.tabs) do
                local top = (lists[tab.key] or NONE)[1]
                if top and top.score > bestScore then best, bestScore = tab.key, top.score end
            end
            if best then
                ns.db.windowTab = best
                ns.db.windowSub[best] = nil -- a narrowed list may not hold the row that made it the best tab
            end
        end
        window.closingAt = nil
        local back = window:IsShown()
        if not back then
            ns.ApplyScale() -- a size set in combat
            if not Placed() then DefaultPlace() end -- the minimap may have moved
        end
        window.openFrom = back and window:GetAlpha() or 0
        window.openedAt = GetTime()
        if not back then
            window.tabsAt = window.openedAt
            window.snapHeight = true
        end
        window.tabsMoving = true
        window:SetAlpha(window.openFrom)
        window:Show()
        escape:Show()
    end
    -- close: fades out; instantly: at once (before combat)
    function window.Close(instantly)
        if instantly then
            window.closingAt = nil
            window:Hide()
        elseif window:IsShown() and not window.closingAt then
            window.closingAt, window.closeFrom = GetTime(), window:GetAlpha()
            tip:Hide()
            window.menu:Hide()
        end
        escape:Hide()
    end
    escape:SetScript("OnHide", function()
        if window:IsShown() and not window.closingAt then window.Close() end
    end)

    -- updates: now (force), or SOON after a change, never while the mouse is over it (then once it leaves).
    -- No timer: one recompute takes ~50 ms.
    local dueAt
    function window.Update(force)
        if not force and window:IsMouseOver() then return end
        dueAt = nil
        local ok, err = pcall(Show)
        if not ok then geterrorhandler()(err) end
    end
    function window.Soon() dueAt = dueAt or GetTime() + SOON end
    window:SetScript("OnUpdate", function(_, delta)
        local now = GetTime()
        if window.closingAt then
            -- leaving: faster, curve reversed
            local done = W.Clamp((now - window.closingAt) / W.CLOSE_TIME)
            window:SetAlpha(window.closeFrom * (1 - W.EaseOutCubic(done)))
            if done >= 1 then
                window.closingAt = nil
                window:Hide()
            end
            return
        end
        if window:GetAlpha() < 1 then
            local from = window.openFrom or 0
            window:SetAlpha(from + (1 - from) * W.EaseOutCubic(W.Clamp((now - (window.openedAt or 0)) / W.FADE_TIME)))
        end
        -- tabs and height move only while they have to
        if window.tabsMoving then window.tabsMoving = PlaceTabs(now) end
        if window.heightMoving and window.targetHeight then window.heightMoving = FollowHeight(delta) end
        -- follows the search's "Background" slider
        local background = Background()
        if background ~= window.background then
            window.background = background
            W.SetBackground(background)
        end
        -- tooltip waiting for item data: shown when it arrives, or after TOOLTIP_WAIT with what there is
        if waiting and not waiting.item then waiting = nil end
        if waiting and (C_Item.IsItemDataCachedByID(waiting.item.entry.itemID)
                or now - waitingSince >= TOOLTIP_WAIT) then
            local row = waiting
            if row:IsVisible() and row.secure:IsMouseOver() then Tooltip(row, true) else waiting = nil end
        end
        if dueAt and now >= dueAt then window.Update() end
    end)
    window:SetScript("OnShow", function() window.Update(true) end)
    window:SetScript("OnHide", function()
        wipe(window.nudged)
        window.closedAt = time()
        tip:Hide()
        waiting = nil
        window.menu:Hide()
        escape:Hide()
    end)
    window:Hide()
    return window
end

-- recompute soon after a state the suggestions depend on changes (Reasons.lua reasons.STATES; State.lua batches
-- them to one call per frame)
D.OnState(ns.reasons.STATES, function()
    if window and window:IsShown() then window.Soon() end
end)
-- close at once before combat (secure buttons cannot change in combat)
ns.On("PLAYER_REGEN_DISABLED", function()
    if window and window:IsShown() then window.Close(true) end
end)

-- the minimap button's middle click and the key (Options.lua)
function ns.ToggleWindow()
    if not ns.db then return end
    if ns.db.adviceOn == false then
        print(("|cffffd100Pylos Compass|r: %s"):format(
            L["the recommendations are switched off (right-click the minimap button for the options)."]))
        return
    end
    if InCombatLockdown() then
        W.Error(L["The recommendations open after combat."])
        return
    end
    if not window then
        -- Build assigns the shared upvalue early (its helpers use it): a failed build must not stay
        local ok, err = pcall(Build)
        if not ok then
            if window then window:Hide() end
            window = nil
            geterrorhandler()(err)
            return
        end
    end
    if window:IsShown() and not window.closingAt then window.Close() else window.Open() end
end

-- the switch "Recommendations" went off
function ns.CloseWindow()
    if window and window:IsShown() then window.Close(true) end
end
