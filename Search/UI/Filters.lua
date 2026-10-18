local ns = select(2, ...).search
if ns.off then return end
local L = ns.L

-- The filter window: right of the window below the bar (bronze frame), with the filters that fit the category
-- searched in, each a row with a check box; the qualities in a section of their own. The funnel (Bar.lua)
-- opens and closes it; a click on a row sets or clears the filter (the text stays). The list beside it is at
-- least as tall (ui.filterHeight, List.lua), so both end together; the tooltip moves right of it. Shown in
-- lists only. The width follows its lines (measured on every draw, gliding to it): narrow with the categories
-- folded, wider with the qualities open in two columns. FILTER_WIDTH: the narrowest it gets.

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local bar, tip = ui.bar, ui.tip
local TextWidth = W.TextWidth

local FILTER_WIDTH, FILTER_ROW = 150, 24
local CATEGORY_ROW = FILTER_ROW + 2
local CHECK = 20
-- gap to the list as between the bar and the list; it slides out this far, in this time
local FILTER_GAP, FILTER_SLIDE, FILTER_TIME = 6, 14, 0.18
local FILTER_TOP = 6 -- below the bar, as the list
ui.FILTER_GAP = FILTER_GAP
ui.filterHeight = 0

local filterPanel = CreateFrame("Frame", nil, bar)
filterPanel:SetPoint("TOPLEFT", bar, "BOTTOMRIGHT", FILTER_GAP, -FILTER_TOP)
filterPanel:SetWidth(FILTER_WIDTH)
filterPanel:Hide()
W.Panel(filterPanel)
ui.CatchMouse(filterPanel)
ui.filterPanel = filterPanel
filterPanel.title = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
filterPanel.title:SetPoint("TOPLEFT", 14, -12)
filterPanel.title:SetText(L["Filter"])

local BESIDE = { "TOPLEFT", filterPanel, "TOPRIGHT", W.TIP_GAP, 0 }

-- The pin (top right): pinned, the window opens with the search every time (PylosCompassDB.filtersOpen)
local PIN = 14
local pin = CreateFrame("Button", nil, filterPanel)
pin:SetSize(PIN, PIN)
pin:SetPoint("TOPRIGHT", -11, -11)
pin.icon = pin:CreateTexture(nil, "ARTWORK")
pin.icon:SetSize(PIN, PIN)
pin.icon:SetPoint("CENTER")

-- A click animates it: pinned, the pin drops in from above, tilted, pricks
-- in past its place, springs back upright and settles (with a little pop of
-- size); unpinned, it jumps out, tips over and falls back. PIN_TIME seconds.
local PIN_TIME = 0.42
local PIN_DROP, PIN_TILT, PIN_POP = 9, -0.6, 4  -- pinned: from above, tilted, growing
local PIN_HOP, PIN_TIP, PIN_SWELL = 7, 0.5, 2   -- unpinned: up, tipping over, growing
local function Spring(p)
    -- 0 -> 1 with an overshoot that dies away (a damped spring)
    return 1 - math.exp(-6 * p) * math.cos(11 * p)
end
local function Prick(self, p)
    local y, angle, size = 0, 0, PIN
    if p >= 1 then
        -- (at rest)
    elseif self.pinned then
        local s = Spring(p)
        y = PIN_DROP * (1 - s)          -- from above into its place (past it, back)
        angle = PIN_TILT * (1 - s)      -- tilted, then upright
        size = PIN + PIN_POP * math.sin(math.pi * math.min(p * 2, 1)) -- a pop as it pricks in
    else
        local hop = math.sin(math.pi * math.min(p * 1.6, 1)) -- up and down again
        y = PIN_HOP * hop
        angle = PIN_TIP * hop * (1 - p)  -- tips over while up
        size = PIN + PIN_SWELL * hop
    end
    self.icon:ClearAllPoints()
    self.icon:SetPoint("CENTER", 0, y)
    self.icon:SetSize(size, size)
    self.icon:SetRotation(angle)
end
local pricking = { duration = PIN_TIME, ease = false, apply = Prick }

local PIN_REST = 0.55 -- unpinned, not hovered
local function ShowPin()
    local pinned = ns.db and ns.db.filtersOpen == true
    if not W.Atlas(pin.icon, "friendslist-recentallies-pin-yellow") then W.Atlas(pin.icon, "friends-icon-pinned") end
    pin.icon:SetDesaturated(not pinned)
    pin.icon:SetAlpha(pinned and 1 or PIN_REST)
end
local function PinTip(self)
    self.icon:SetAlpha(1)
    local pinned = ns.db and ns.db.filtersOpen
    W.FeatureTip(tip, filterPanel, BESIDE, pinned and L["Pinned"] or L["Pin"],
        pinned and L["The filter window opens with the search. Click to unpin."]
        or L["Click to open the filter window with the search every time."])
end
pin:SetScript("OnShow", ShowPin)
pin:SetScript("OnClick", function(self)
    ns.SetOption("filtersOpen", not (ns.db and ns.db.filtersOpen))
    ShowPin()
    self.pinned = ns.db and ns.db.filtersOpen == true
    W.Tween(self, "prick", pricking)
    -- the tooltip says the new state (its owner is the window: it stands beside it)
    if self:IsMouseOver() then PinTip(self) end
end)
pin:SetScript("OnEnter", PinTip)
pin:SetScript("OnLeave", function()
    ShowPin()
    ui.FilterTipGone()
end)

local filterRows, filterHeaders = {}, {}

local function FilterRow(i)
    local row = filterRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, filterPanel)
    row:SetHeight(FILTER_ROW)
    row.highlight = W.Highlight(row)
    row.highlight:Hide()
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(CHECK, CHECK)
    row.check:SetPoint("LEFT", 6, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetAllPoints(row.check)
    row.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return ui.ShowFilterMenu(self.filter) end
        ns.view.ToggleFilter(self.filter)
    end)
    -- hovering: what the filter does, where the result's tooltip stands; that tooltip returns when the mouse leaves
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        ui.FilterTip(self.filter)
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        ui.FilterTipGone()
    end)
    filterRows[i] = row
    return row
end

local function FilterHeader(i)
    local header = filterHeaders[i]
    if header then return header end
    header = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetJustifyH("LEFT")
    filterHeaders[i] = header
    return header
end

function ui.ColoredName(f)
    return f.color and ("|c" .. f.color .. f.name .. "|r") or f.name
end
local ColoredName = ui.ColoredName

-- the filter's tooltip (a feature's): name in gold (a quality in its colour), what it does in white
function ui.FilterTip(f)
    if not f.description then return end
    W.FeatureTip(tip, filterPanel, BESIDE, ColoredName(f), f.description)
end
function ui.FilterTipGone()
    if tip:GetOwner() == filterPanel then
        tip:Hide()
        ui.list.tooltipEntry = nil
        ui.ShowTooltip(S.results[S.marked])
    end
end

-- In the search over everything the filters stand under their categories, folded: a line per category with its
-- symbol and how many of its filters are set; a click opens it (and closes the one open). A category with a
-- filter set stays open.
local categoryRows = {}
local CHEVRON = 14
-- a plain chevron pointing right, the first the client has (the options list's arrow is not in WoW Forever)
local CHEVRONS = { { "friendslist-categorybutton-arrow-right", 9, 13 },
    { "uitools-icon-chevron-right", CHEVRON, CHEVRON }, { "common-dropdown-icon-next", CHEVRON, CHEVRON } }
local function CategoryRow(i)
    local row = categoryRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, filterPanel)
    row:SetHeight(CATEGORY_ROW)
    row.highlight = W.Highlight(row)
    row.highlight:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.arrow = row:CreateTexture(nil, "OVERLAY")
    row.arrow:SetPoint("RIGHT", -8, 0)
    local found = false
    for _, c in ipairs(CHEVRONS) do
        if W.Atlas(row.arrow, c[1]) then
            row.arrow:SetSize(c[2], c[3])
            found = true
            break
        end
    end
    if not found then
        row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        row.arrow:SetSize(CHEVRON, CHEVRON)
    end
    row.arrowAngle = 0
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row.arrow, "LEFT", -6, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        ui.filterCategory = ui.filterCategory ~= self.key and self.key or nil
        ns.view.Refresh({ marked = S.marked, top = S.top })
    end)
    row:SetScript("OnEnter", function(self) self.highlight:Show() end)
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
    categoryRows[i] = row
    return row
end

-- The window's lines move instead of jumping when a category folds open or shut: each line has a place
-- (targetY) it glides to; a coming line fades in from a little above, a going line fades out where it is,
-- the window's size follows. Not while the window itself opens (it slides in whole). A category's arrow turns.
local LINE_FADE = 0.16
local LINE_GONE = 0.1 -- a going line fades this fast; the others wait for it
local LINE_DROP = 10  -- a coming line comes from this far above
local layoutFrames = {} -- every line the window ever placed
local animateLayout = false
local unfoldFrom -- while placing an opened category's lines: the y they unfold from (its own line)
local holdUntil = 0 -- lines and size wait until the going lines are gone

local function ApplyPlace(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", frame.left, frame.curY)
    if frame.width then
        frame:SetWidth(frame.width)
    elseif frame.right then
        frame:SetPoint("TOPRIGHT", frame.right, frame.curY)
    end
end
local function Fade(frame, value) frame:SetAlpha(value) end
local fadingIn = { duration = LINE_FADE, apply = Fade }
local fadingOut = { duration = LINE_GONE, ease = false,
    apply = function(frame, p) frame:SetAlpha(1 - p) end,
    done = function(frame)
        frame.leavingAt = nil
        frame:Hide()
    end,
}

local function PlaceAt(frame, left, right, y)
    if not frame.inLayout then
        frame.inLayout = true
        layoutFrames[#layoutFrames + 1] = frame
    end
    frame.left, frame.right, frame.targetY, frame.width = left, right, y, nil
    local coming = not frame:IsShown() or frame.leavingAt ~= nil
    frame.leavingAt = nil
    if not animateLayout or frame.curY == nil then
        W.Follow(frame, "curY", nil)
        W.Tween(frame, "line", nil)
        frame.curY, frame.coming = y, nil
        frame:SetAlpha(1)
    elseif coming then
-- comes from above (or its category's line), see-through; fades in when the going lines are gone (Glide)
        W.Follow(frame, "curY", nil)
        W.Tween(frame, "line", nil)
        frame.curY, frame.coming = unfoldFrom or (y + LINE_DROP), true
        frame:SetAlpha(0)
    end
    frame.placed = true
    frame:Show()
end

local function ApplyWidth(self, width)
    self:SetWidth(width)
    ui.MoveTip()
end
local function ApplyHeight(self, height)
    local list = ui.list
    if list:IsShown() and list:GetHeight() > height then height = list:GetHeight() end
    self:SetHeight(height)
end
function ui.FitFilterHeight()
    if filterPanel:IsShown() and filterPanel.height then ApplyHeight(filterPanel, filterPanel.height) end
end

local function Glide()
    for _, frame in ipairs(layoutFrames) do
        if frame:IsShown() and not frame.leavingAt then
            W.Follow(frame, "curY", frame.targetY, ApplyPlace)
            if frame.coming then
                frame.coming = nil
                W.Tween(frame, "line", fadingIn)
            end
        end
    end
    W.Follow(filterPanel, "width", filterPanel.targetWidth, ApplyWidth)
    W.Follow(filterPanel, "height", filterPanel.targetHeight, ApplyHeight)
end
local holding = { ease = false, apply = function() end, done = Glide }

local function Turn(row, angle) row.arrow:SetRotation(angle) end
local TURN_NEAR = 0.01

-- draws the filter window (shown: open, filters fit, a list below the bar); sets ui.filterHeight for the list beside it
function ui.RenderFilterPanel(show)
    ui.filterHeight = 0
    ui.filterWanted = show and true or false
    if not show then
        -- slides back and fades out (hides at the end); the list may shrink again
        if filterPanel:IsShown() and not filterPanel.closingAt then
            filterPanel.closingAt = GetTime()
            W.Tween(filterPanel, "slide", ui.closingPanel)
            ui.FitList()
        end
        ui.MoveTip()
        return
    end
    local set = {}
    for _, f in ipairs(S.filters) do set[f] = true end

    -- the sections: one without a heading in a category; over everything one per category (each filter under the first it belongs to)
    local sections = {}
    if S.scope then
        sections[1] = { filters = {} }
        for _, f in ipairs(ns.filters) do
            if not f.subcategory and ns.filter.AppliesTo(f, S.scope) then table.insert(sections[1].filters, f) end
        end
    else
        local placed = {}
        for _, source in ipairs(ns.ActiveSources()) do
            local section = { source = source, filters = {}, count = 0 }
            for _, f in ipairs(ns.filters) do
                if not f.subcategory and not placed[f] and f.sources and ns.filter.AppliesTo(f, source) then
                    placed[f] = true
                    section.filters[#section.filters + 1] = f
                    if set[f] then section.count = section.count + 1 end
                end
            end
            if #section.filters > 0 then sections[#sections + 1] = section end
        end
    end

    animateLayout = filterPanel:IsShown() and not filterPanel.closingAt
        and GetTime() - (filterPanel.shownAt or 0) > FILTER_TIME
    for _, frame in ipairs(layoutFrames) do frame.placed = false end
    local y, rowCount, headerCount, categoryCount = -34, 0, 0, 0
    local needed = math.max(FILTER_WIDTH, 14 + TextWidth(filterPanel.title) + 40)
    local ROW_EXTRA = 6 + 6 + CHECK + 4 + 10 -- inset, box, gap, room on the right
    local function Place(f)
        rowCount = rowCount + 1
        local row = FilterRow(rowCount)
        row.filter = f
        row.text:SetText(ColoredName(f))
        row.mark:SetShown(set[f] == true)
        PlaceAt(row, 6, -6, y)
        needed = math.max(needed, ROW_EXTRA + TextWidth(row.text))
        y = y - FILTER_ROW
    end
    -- a group (the qualities): its name, then its filters as the other rows (box and coloured name) in two
    -- columns as wide as their longest name, three lines instead of six
    local function PlaceGroup(list)
        headerCount = headerCount + 1
        local header = FilterHeader(headerCount)
        header:SetText(list[1].groupName or list[1].group)
        PlaceAt(header, 14, nil, y - 6)
        y = y - 22
        local rows, column = {}, 0
        for i, f in ipairs(list) do
            rowCount = rowCount + 1
            local row = FilterRow(rowCount)
            row.filter = f
            row.text:SetText(ColoredName(f))
            row.mark:SetShown(set[f] == true)
            column = math.max(column, 6 + CHECK + 4 + TextWidth(row.text) + 8)
            rows[i] = row
        end
        needed = math.max(needed, 12 + 2 * column)
        for i, row in ipairs(rows) do
            local side = (i - 1) % 2
            PlaceAt(row, 6 + side * column, nil, y)
            row.width = column
            if side == 1 or i == #rows then y = y - FILTER_ROW end
        end
        y = y - 4
    end
    local function PlaceFilters(filters)
        local groups, order = {}, {}
        for _, f in ipairs(filters) do
            if f.group then
                if not groups[f.group] then
                    groups[f.group] = {}
                    order[#order + 1] = f.group
                end
                table.insert(groups[f.group], f)
            else
                Place(f)
            end
        end
        for _, key in ipairs(order) do PlaceGroup(groups[key]) end
    end

    for _, section in ipairs(sections) do
        if section.source then
            categoryCount = categoryCount + 1
            local row = CategoryRow(categoryCount)
            local source = section.source
            row.key = source.key
            W.ShowIcon(row.icon, source.entry, 18)
            local open = ui.filterCategory == source.key or section.count > 0
            row.name:SetText(source.name)
            local color = open and W.GOLD or W.WHITE
            row.name:SetTextColor(color[1], color[2], color[3])
            local angle = open and -math.pi / 2 or 0
            if animateLayout then
                W.Follow(row, "arrowAngle", angle, Turn, TURN_NEAR)
            else
                W.Follow(row, "arrowAngle", nil)
                row.arrowAngle = angle
                Turn(row, angle)
            end
            row.count:SetText(section.count > 0 and tostring(section.count) or "")
            PlaceAt(row, 6, -6, y)
            -- inset, symbol, name, the count, the arrow, room on the right
            needed = math.max(needed, 6 + 8 + 18 + 6 + TextWidth(row.name)
                + (section.count > 0 and (TextWidth(row.count) + 6) or 0) + CHEVRON + 8 + 16)
            local rowY = row.curY
            y = y - CATEGORY_ROW
            if open then
                unfoldFrom = rowY
                PlaceFilters(section.filters)
                unfoldFrom = nil
                y = y - 4
            end
        else
            PlaceFilters(section.filters)
        end
    end
    local now = GetTime()
    for _, frame in ipairs(layoutFrames) do
        if not frame.placed and frame:IsShown() then
            if animateLayout then
                if not frame.leavingAt then
                    frame.leavingAt = now
                    holdUntil = math.max(holdUntil, now + LINE_GONE)
                    W.Follow(frame, "curY", nil)
                    W.Tween(frame, "line", fadingOut)
                end
            else
                frame.leavingAt = nil
                W.Tween(frame, "line", nil)
                frame:Hide()
            end
        end
    end
    filterPanel.targetHeight = -y + 10
    filterPanel.targetWidth = math.ceil(needed)
    if animateLayout then
        if holdUntil > now then
            for _, frame in ipairs(layoutFrames) do W.Follow(frame, "curY", nil) end
            W.Follow(filterPanel, "width", nil)
            W.Follow(filterPanel, "height", nil)
            holding.duration = holdUntil - now
            W.Tween(filterPanel, "hold", holding)
        else
            W.Tween(filterPanel, "hold", nil)
            Glide()
        end
    else
        W.Tween(filterPanel, "hold", nil)
        W.Follow(filterPanel, "width", nil)
        W.Follow(filterPanel, "height", nil)
        filterPanel.width, filterPanel.height = filterPanel.targetWidth, filterPanel.targetHeight
        filterPanel:SetWidth(filterPanel.width)
    end
    -- every line where it stands now (new in its place, coming at its start, two-column at its width); gliding moves them on
    for _, frame in ipairs(layoutFrames) do
        if frame:IsShown() then ApplyPlace(frame) end
    end
    ui.filterHeight = -y + 10
    -- the list beside it as tall (the window came after the list's height was set when the search opened
    -- with the window open); the window at least as tall as the list
    ui.FitList()
    if not animateLayout then ApplyHeight(filterPanel, filterPanel.height) end
    ui.MoveTip()
    -- while the search opens it waits for the list (opening order: step "list"); coming out together with
    -- the growing list looked restless
    if not ui.Since("list") then return end
    if not filterPanel:IsShown() or filterPanel.closingAt then ui.OpenFilterPanel() end
end

-- It slides out from the list's edge and fades in when it opens, back and out when it closes (leaving faster)
local function Slide(self, value)
    self:SetAlpha(value)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", bar, "BOTTOMRIGHT", FILTER_GAP - FILTER_SLIDE * (1 - value), -FILTER_TOP)
end
local opening = { duration = FILTER_TIME, apply = Slide, done = function() ui.Finished("filters") end }
ui.closingPanel = { duration = W.CLOSE_TIME,
    apply = function(self, value) Slide(self, 1 - value) end,
    done = function(self)
        self.closingAt = nil
        self:Hide()
        ui.Finished("filters") -- closed while opening: the close tab still comes
    end,
}

-- shows the window where its animation starts: see-through, at the list's edge (shown as it was left, it stood
-- there whole for one frame before the animation took it back to its start)
function ui.OpenFilterPanel()
    filterPanel.shownAt, filterPanel.closingAt = GetTime(), nil
    W.Tween(filterPanel, "slide", opening)
    filterPanel:Show()
end

-- the search opens: the window starts closed, nothing of it moving
function ui.ResetFilterPanel()
    W.Tween(filterPanel, "slide", nil)
    W.Tween(filterPanel, "hold", nil)
    filterPanel.closingAt = nil
    filterPanel:Hide()
end

-- opening order: once the list stands (or the detail view shows), the pinned window comes out (the tooltip
-- slides aside with it); with none pinned that step is done as well
ui.After("list", function()
    if ui.filterWanted then ui.OpenFilterPanel() else ui.Finished("filters") end
    ui.MoveTip()
end)
