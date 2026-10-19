local ns = select(2, ...).search
local L = ns.L

-- The detail view: where the list is: icon and head (the entry's row in large), below it previews of its
-- most needed links and a line with the keys; its full tooltip stays beside the window. What can be done
-- with the entry is in its menu. Also the copy field (a web address to copy).

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local bar, tip, list = ui.bar, ui.tip, ui.list
local DOT, ROW_HEIGHT = W.DOT, W.ROW_HEIGHT

local DETAIL_TOP, DETAIL_FOOT, DETAIL_ICON = 14, 66, 40
local DETAIL_FADE = 0.15 -- seconds it fades in
local WINDOW_GAP = ui.WINDOW_GAP
local detail = CreateFrame("Frame", nil, bar)
detail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -WINDOW_GAP)
detail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -WINDOW_GAP)
detail:SetHeight(120)
detail:Hide()
W.Panel(detail)
ui.Art(detail)
ui.CatchMouse(detail)
detail:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and S.detail then ui.ShowMenu(S.detail, true) end
end)
ui.detail = detail

-- background art of list and detail view: { atlas, focusX, focusY, zoom, alpha } (focus: the motif's centre
-- as fractions of the picture; alpha for colorful pictures so the text stays readable), nil: none
function ui.SetArt(art)
    local info = art and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art[1])
    for _, frame in ipairs({ list, detail }) do
        frame.artInfo = info
        frame.artFocusX, frame.artFocusY, frame.artZoom = art and art[2], art and art[3], art and art[4]
        frame.artAlpha = art and art[5]
        ui.FitArt(frame)
    end
end

detail.icon = W.Icon(detail, DETAIL_ICON)
detail.icon:SetPoint("TOPLEFT", 16, -DETAIL_TOP)

-- an entry's chat link: an item's (its "item:ID" stand-in while the item is not cached) or a spell's
function ui.EntryLink(entry)
    if entry.itemID then
        return select(2, C_Item.GetItemInfo(entry.itemID)) or ("item:" .. entry.itemID)
    end
    local spellID = entry.spellID or (entry.type == "spell" and entry.value)
    if spellID and C_Spell and C_Spell.GetSpellLink then return C_Spell.GetSpellLink(spellID) end
end

detail.iconButton = CreateFrame("Button", nil, detail)
-- anchored to the window, not the icon texture: the menu hangs below it and holds secure buttons, and a
-- protected frame's anchors must lead to frames only
detail.iconButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -DETAIL_TOP)
detail.iconButton:SetSize(DETAIL_ICON, DETAIL_ICON)
detail.iconButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
-- hovered: the action button's mouseover frame round the icon (atlas from UiTextureAtlasMember); the square
-- glow (it draws a blue frame) only where the client lacks the atlas
local iconHover = detail.iconButton:CreateTexture(nil, "HIGHLIGHT")
iconHover:SetPoint("TOPLEFT", detail.icon, "TOPLEFT", -2, 2)
iconHover:SetPoint("BOTTOMRIGHT", detail.icon, "BOTTOMRIGHT", 3, -3)
if not W.Atlas(iconHover, "UI-HUD-ActionBar-IconFrame-Mouseover") then
    iconHover:SetAllPoints(detail.icon)
    iconHover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    iconHover:SetBlendMode("ADD")
end
-- the icon takes the game's modified clicks like a bag icon (Ctrl+click tries on, Shift+click links into
-- chat: HandleModifiedItemClick); a right click opens its menu
detail.iconButton:RegisterForDrag("LeftButton")
detail.iconButton:SetScript("OnDragStart", function() ui.Pickup(S.detail) end)
detail.iconButton:SetScript("OnClick", function(_, button)
    if GetCursorInfo() then return end -- the release of a drag
    if button == "RightButton" then return ui.ShowMenu(S.detail, true) end
    local link = S.detail and ui.EntryLink(S.detail)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end)

detail.tip = CreateFrame("GameTooltip", "PylosCompassDetailTooltip", detail, "GameTooltipTemplate")
detail.tip:SetFrameStrata("TOOLTIP")
detail.tip.noGatherInfo = true

detail.id = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
detail.id:SetPoint("BOTTOMRIGHT", -18, 39)

detail.keys = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
detail.keys:SetPoint("BOTTOM", 0, 14)

-- The head: the entry's row in large: right of the icon its details with the kind first ("Item · Metal & Stone"),
-- on the right its state for you in its color and below it the reason (UI\List.lua ui.RowTexts); two lines
-- with a reason, so it never covers the previews
local HEAD_HEIGHT, HEAD_TWO = 20, 34
detail.headHeight = HEAD_HEIGHT
detail.kind = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail.kind:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 10, -2)
detail.kind:SetJustifyH("LEFT")
detail.kind:SetWordWrap(false)
detail.kind:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3])
detail.state = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
detail.state:SetPoint("TOPRIGHT", -18, -DETAIL_TOP)
detail.why = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail.why:SetPoint("TOPRIGHT", detail.state, "BOTTOMRIGHT", 0, -2)
detail.why:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3])
detail.kind:SetPoint("RIGHT", detail.state, "LEFT", -12, 0)

local function PlaceTooltip()
    local tooltip = detail.tip
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", detail, "TOPRIGHT", W.TIP_GAP, 0)
end

-- Previews of the entry's links: the first PREVIEW_LINKS links that have rows, in the order its kind needs
-- them (Links\Order.lua), each with its heading, "all" (the whole list) and its first PREVIEW_ROWS rows
-- (UI\List.lua ui.FillRow); the others as one line "Also: ...". A row opens its entry (Enter on one marked
-- with Up/Down too), a right click its menu.
local PREVIEW_LINKS, PREVIEW_ROWS = 2, 3
local HEADING_HEIGHT, SECTION_GAP, ALSO_HEIGHT = 20, 6, 20
local previews = CreateFrame("Frame", nil, detail)
previews:SetPoint("LEFT", 10, 0)
previews:SetPoint("RIGHT", -10, 0)
previews:SetHeight(1)
detail.previews = previews
local headings, previewRows, alsoButtons = {}, {}, {}
detail.previewRows = previewRows

local function Heading(i)
    local heading = headings[i]
    if heading then return heading end
    heading = CreateFrame("Button", nil, previews)
    heading:SetHeight(HEADING_HEIGHT)
    heading.label = heading:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading.label:SetPoint("LEFT", 6, 0)
    heading.all = heading:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heading.all:SetPoint("RIGHT", -10, 0)
    heading.all:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3])
    heading:SetScript("OnEnter", function(self) self.all:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3]) end)
    heading:SetScript("OnLeave", function(self) self.all:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3]) end)
    heading:SetScript("OnClick", function(self) ns.view.OpenLink(S.detail, self.link) end)
    headings[i] = heading
    return heading
end

local function MarkPreview(index)
    detail.previewMarked = index
    for i, row in ipairs(previewRows) do
        if row:IsShown() then
            W.MarkRow(row, i == index, row.dimmed)
            local tone = row.tone
            if tone then row.status:SetTextColor(tone[1], tone[2], tone[3]) end
        end
    end
end
ui.MarkPreview = MarkPreview

local function PreviewRow(i)
    local row = previewRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, previews)
    row:SetHeight(ROW_HEIGHT)
    ui.RowParts(row, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- hovered: marked, its tooltip next to the entry's: right of it, below it where the screen ends
    row:SetScript("OnEnter", function(self)
        MarkPreview(self.index)
        local beside = detail.tip:IsShown() and detail.tip or detail
        tip:SetOwner(detail, "ANCHOR_NONE")
        ui.FillTooltip(tip, self.entry)
        tip:ClearAllPoints()
        if beside == detail.tip and (beside:GetRight() or 0) + 2 + tip:GetWidth() > UIParent:GetRight() then
            tip:SetPoint("TOPLEFT", beside, "BOTTOMLEFT", 0, -2)
        else
            tip:SetPoint("TOPLEFT", beside, "TOPRIGHT", beside == detail and W.TIP_GAP or 2, 0)
        end
    end)
    row:SetScript("OnLeave", function() tip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return ui.ShowMenu(self.entry) end
        ns.view.OpenPreview(self.entry)
    end)
    row.index = i
    previewRows[i] = row
    return row
end

local function AlsoButton(i)
    local button = alsoButtons[i]
    if button then return button end
    button = CreateFrame("Button", nil, previews)
    button:SetHeight(ALSO_HEIGHT)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT")
    button:SetScript("OnEnter", function(self) self.text:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3]) end)
    button:SetScript("OnLeave", function(self) self.text:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3]) end)
    button:SetScript("OnClick", function(self) ns.view.OpenLink(S.detail, self.link) end)
    alsoButtons[i] = button
    return button
end

local rowOpts = { linked = true }
local function RenderPreviews(entry)
    local y, shownRows, shownHeadings, sections = 0, 0, 0, 0
    local also = {}
    for _, option in ipairs(ns.view.Options(entry)) do
        if option.kind == "link" then
            if sections < PREVIEW_LINKS then
                sections = sections + 1
                shownHeadings = shownHeadings + 1
                local heading = Heading(shownHeadings)
                heading.link = option.link
                heading.label:SetText(option.text)
                heading.all:SetText(option.count > PREVIEW_ROWS and L["all"] .. " ›" or "")
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", 0, -y)
                heading:SetPoint("TOPRIGHT", 0, -y)
                heading:Show()
                y = y + HEADING_HEIGHT
                local taken = 0
                for _, linked in ipairs(option.entries) do
                    if taken >= PREVIEW_ROWS then break end
                    if not linked.header then
                        taken = taken + 1
                        shownRows = shownRows + 1
                        local row = PreviewRow(shownRows)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", 0, -y)
                        row:SetPoint("TOPRIGHT", 0, -y)
                        ui.ItemDetails(linked)
                        ui.FillRow(row, linked, rowOpts)
                        row.name:SetText(linked.name)
                        -- state text is written directly (the list sets it when marking its rows)
                        row.status:SetText(row.state or "")
                        row:Show()
                        for _, part in ipairs({ row.icon, row.name, row.sub, row.status, row.why }) do part:Show() end
                        y = y + ROW_HEIGHT
                    end
                end
                y = y + SECTION_GAP
            else
                also[#also + 1] = option
            end
        end
    end
    for i = shownRows + 1, #previewRows do previewRows[i]:Hide() end
    for i = shownHeadings + 1, #headings do headings[i]:Hide() end
    -- the others: "Also: Sold by (2)  Quests (1)", on a new line where the window's width ends
    local x, room = 6, W.WIDTH - 20 - 12
    for i, option in ipairs(also) do
        local button = AlsoButton(i)
        button.link = option.link
        button.text:SetText((i == 1 and (L["Also"] .. ":  ") or "") .. option.text)
        button.text:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
        button:SetWidth(W.TextWidth(button.text) + 4)
        if i > 1 and x + button:GetWidth() > room then
            x, y = 6, y + ALSO_HEIGHT
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, -y)
        button:Show()
        x = x + button:GetWidth() + 12
    end
    for i = #also + 1, #alsoButtons do alsoButtons[i]:Hide() end
    if #also > 0 then y = y + ALSO_HEIGHT end
    detail.previewCount = shownRows
    MarkPreview(nil)
    previews:SetHeight(math.max(y, 1))
    return y
end

-- The window as tall as its head and previews, and the subcategory tabs beside it; with a background
-- picture as tall as the full list
function ui.FitDetail()
    local top = math.max(detail.headHeight, DETAIL_ICON) + DETAIL_TOP
    previews:ClearAllPoints()
    previews:SetPoint("TOPLEFT", 10, -(top + 8))
    previews:SetPoint("TOPRIGHT", -10, -(top + 8))
    local previewHeight = detail.previewHeight or 0
    local height = math.max(top + (previewHeight > 1 and previewHeight + 8 or 0) + DETAIL_FOOT - 6, ui.tabsHeight or 0)
    if detail.artInfo then height = math.max(height, ui.Rows() * ROW_HEIGHT + 12) end
    if height ~= detail:GetHeight() then
        detail:SetHeight(height)
        ui.PlaceTabs()
    end
end

local fading = { duration = DETAIL_FADE, apply = function(self, value)
    self:SetAlpha(value)
    ui.FitDetail()
end }

function ui.RefillDetail()
    ui.FillTooltip(detail.tip, S.detail)
    PlaceTooltip()
end

local HideCopy -- the copy field's (below)

local headOpts = { mixed = true }
function ui.RenderDetail(entry)
    HideCopy()
    ui.ItemDetails(entry)
    list:Hide()
    -- a list waiting for the opening bar (RenderList) must not fold open over the detail view (opened straight
    -- at an entry: PylosCompass.Show)
    list.pending = nil
    tip:Hide()
    W.ShowIcon(detail.icon, entry)
    headOpts.note = ns.rec.Mark(entry)
    local details, state, color, why, dimmed = ui.RowTexts(entry, headOpts)
    detail.kind:SetText(details)
    detail.state:SetText(state)
    local c = color or W.LIGHT
    detail.state:SetTextColor(c[1], c[2], c[3])
    detail.why:SetText(why or "")
    detail.headHeight = why and HEAD_TWO or HEAD_HEIGHT
    detail.icon:SetDesaturated(dimmed and true or false)
    detail.tip:SetOwner(detail, "ANCHOR_NONE")
    ui.FillTooltip(detail.tip, entry)
    PlaceTooltip()

    detail.previewHeight = RenderPreviews(entry)

    local id = entry.itemID or entry.spellID or entry.npcID or entry.questID or entry.mapID
    detail.id:SetText(id and ("ID " .. id) or "")

    local keys = {}
    if ns.view.HasAction(entry) then
        local label = entry.itemID and L["use"] or (entry.source and entry.source.actionLabel) or L["cast"]
        keys[#keys + 1] = L["Ctrl+Enter: %s"]:format(label)
    end
    if (detail.previewCount or 0) > 0 then keys[#keys + 1] = L["Enter: open"] end
    keys[#keys + 1] = L["Space: menu"]
    keys[#keys + 1] = L["Typing: new search"]
    keys[#keys + 1] = L["Esc: back"]
    detail.keysText = table.concat(keys, DOT)
    detail.keys:SetText(detail.keysText)

    if not detail:IsShown() then W.Tween(detail, "fade", fading) end
    detail:Show()
    ui.FitDetail()
    ui.PlaceTabs()
    ui.CheckList() -- opening order: the detail view stands instead of the list
end

-- Copy field: a text to copy (a web address) stands marked in a field over the keys line, with the
-- keyboard focus; Ctrl+C copies it and the field goes, Esc, Enter or a click elsewhere close it. Typing cannot
-- change it.
local COPIED_FOR = 0.6 -- seconds "Link copied" shows before the field goes
local copy = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
copy:SetHeight(22)
copy:SetPoint("BOTTOMLEFT", 22, 34)
copy:SetPoint("BOTTOMRIGHT", -18, 34)
copy:SetAutoFocus(false)
copy:SetFontObject("GameFontHighlightSmall")
copy:Hide()
ui.copy = copy

function HideCopy()
    if not copy:IsShown() then return end
    copy:Hide() -- first: losing the focus calls this again
    copy:ClearFocus()
    detail.id:Show()
    detail.keys:SetText(detail.keysText)
end

function ui.ShowCopy(text)
    copy.text = text
    copy:SetText(text)
    copy:Show()
    copy:SetFocus()
    copy:SetCursorPosition(0)
    copy:HighlightText()
    detail.id:Hide()
    detail.keys:SetText(L["Ctrl+C: copy"] .. DOT .. L["Esc: close"])
end

copy:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        self:SetText(self.text)
        self:HighlightText()
    end
end)
copy:SetScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() then
        detail.keys:SetText(L["Link copied"])
        -- the copying happens after this key script: the field goes a moment later
        C_Timer.After(COPIED_FOR, function()
            if copy:IsShown() then HideCopy() end
        end)
    end
end)
copy:SetScript("OnEscapePressed", HideCopy)
copy:SetScript("OnEnterPressed", HideCopy)
copy:SetScript("OnEditFocusLost", HideCopy)
detail:HookScript("OnHide", HideCopy)
