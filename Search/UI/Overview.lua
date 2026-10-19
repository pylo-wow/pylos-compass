local ns = select(2, ...).search

-- A category's page when opened without text (source.overview, only Professions): its overviewEntries() in
-- two columns, each with icon, name and a bar of entry.bar = { value, maximum, text, { r, g, b }, fill atlas }.
-- Hovering shows the tooltip, a click opens the subcategory (entry.filter) or the detail view. Cells fade in
-- one after another. More than OVERVIEW_LINES lines scroll (wheel, scroll bar) instead of growing the window.

local W = ns.widgets
local ui = ns.ui
local tip, list = ui.tip, ui.list
local Clamp = W.Clamp

-- Value bars
-- Like the game's skill window: dark ground, thin bronze border, the value as text in the middle
-- (bar.value). 15 px high: a lower bar cuts the text off at the bottom.
local VALUE_BAR_HEIGHT = 15
local GROUND_ALPHA = 0.6
local MIN_FILL_WIDTH = 0.01 -- keeps the fill's width above 0
local FILL = { 0.1, 0.32, 0.85 } -- the blue of the game's skill window
local function Bar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(VALUE_BAR_HEIGHT)
    -- the own fill follows the bar's width (it is placed before it is sized)
    bar:SetScript("OnSizeChanged", function(self)
        if self.fraction then self.art:SetWidth(math.max(self:GetWidth() * self.fraction, MIN_FILL_WIDTH)) end
    end)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local back = ui.Fill(bar, "BACKGROUND", 0, 0, 0, GROUND_ALPHA)
    back:SetAllPoints()
    ui.Border(bar, "OVERLAY", true)
    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.value:SetPoint("CENTER", 0, 0)
    bar.art = bar:CreateTexture(nil, "ARTWORK")
    bar.art:SetPoint("TOPLEFT")
    bar.art:SetPoint("BOTTOMLEFT")
    bar.art:Hide()
    return bar
end

-- data = { value, maximum, text, { r, g, b }, fill atlas }. A fill atlas is
-- one of the game's profession bars: an animation sheet of frames 856 x 34
-- in two columns (skillbar_fill_flipbook_*), or the plain blue one
-- (skillbar_fill_flipbook_defaultblue); its first frame, cut to the value,
-- stands in for the color.
local FLIPBOOK_FRAME_HEIGHT = 34
local FLIPBOOK_TWO_COLUMNS = 1500 -- a sheet this wide has two columns of frames
-- WoW Forever's own bars (*_c60): the client does not know these atlas names at run time, though they are in
-- its tables (as with the quest log's symbol, UI\Kit\Widgets.lua QUEST_PART): sheet and place from UiTextureAtlas
-- (file, size) and UiTextureAtlasMember (width, height, left, right, top, bottom in pixels), wago.tools build 70291
local SHEETS = {
    skillbar_fill_flipbook_firstaid_c60 = { 8215428, 2048, 1024, 1712, 1020, 1, 1713, 1, 1021 },
    skillbar_fill_flipbook_alchemy_c60 = { 8176600, 2048, 1024, 1712, 1020, 1, 1713, 1, 1021 },
    skillbar_fill_flipbook_skinning_c60 = { 8176596, 2048, 1024, 1712, 1020, 1, 1713, 1, 1021 },
    skillbar_fill_flipbook_enchanting_c60 = { 8176598, 2048, 2048, 1712, 1258, 1, 1713, 1, 1259 },
}
local function AtlasInfo(name)
    local info = name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if info then return info end
    local s = name and SHEETS[name]
    if not s then return nil end
    return { file = s[1], width = s[4], height = s[5], leftTexCoord = s[6] / s[2], rightTexCoord = s[7] / s[2],
        topTexCoord = s[8] / s[3], bottomTexCoord = s[9] / s[3] }
end
local function FillBar(bar, data)
    local value, maximum = data[1], math.max(data[2], 1)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(value)
    bar.value:SetText(data[3] or ns.Progress(data[1], data[2]))
    local info = AtlasInfo(data[5])
    if info then
        local fraction = Clamp(value / maximum)
        local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        -- an animation sheet: two columns of frames 34 px high; a plain bar
        -- (defaultblue, 880 x 33): one frame
        local rows = math.max(math.floor(info.height / FLIPBOOK_FRAME_HEIGHT + 0.5), 1)
        local columns = info.width >= FLIPBOOK_TWO_COLUMNS and 2 or 1
        local frameRight = left + (right - left) / columns
        bar.art:SetTexture(info.file or info.filename)
        bar.art:SetTexCoord(left, left + (frameRight - left) * fraction, top, top + (bottom - top) / rows)
        bar.art:SetWidth(math.max(bar:GetWidth() * fraction, MIN_FILL_WIDTH))
        bar.art:SetShown(fraction > 0)
        bar:SetStatusBarColor(0, 0, 0, 0)
        bar.fraction = fraction
    else
        bar.art:Hide()
        bar.fraction = nil
        local color = data[4] or FILL
        bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    end
end

local OVERVIEW_LINES = 6 -- lines of cells shown at once: about the list's height
ui.OVERVIEW_LINES = OVERVIEW_LINES
local CELL_HEIGHT, CELL_GAP, OVERVIEW_PAD = 46, 10, 10
local CELL_SPACING = 4 -- a cell is this much lower than its line
local CELL_ICON = 32
local CELL_TIME, CELL_STAGGER = 0.2, 0.025

local overview = CreateFrame("Frame", nil, list)
overview:SetPoint("TOPLEFT", OVERVIEW_PAD, -OVERVIEW_PAD)
overview:SetPoint("TOPRIGHT", -OVERVIEW_PAD, -OVERVIEW_PAD)
overview:SetHeight(1)
overview:Hide()
overview.count, overview.lines, overview.top = 0, 0, 0
ui.overview = overview
local cells = {}

-- a cell fades in (cell.ease) and shows only as far as the growing list reaches it
local function FadeCell(cell)
    cell:SetAlpha(cell.ease * Clamp((list:GetHeight() - cell.offset) / CELL_HEIGHT))
end
function ui.FadeCells()
    if not overview:IsShown() then return end
    for _, cell in ipairs(cells) do
        if cell:IsShown() then FadeCell(cell) end
    end
end
local fading = { duration = CELL_TIME, apply = function(cell, value)
    cell.ease = value
    FadeCell(cell)
end }

local function HoverCell(cell)
    cell.highlight:Show()
    cell.name:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    tip:SetOwner(list, "ANCHOR_NONE")
    ui.PlaceTip()
    ui.FillTooltip(tip, cell.entry)
end

local function Cell(i)
    local cell = cells[i]
    if cell then return cell end
    cell = CreateFrame("Button", nil, overview)
    cell:SetHeight(CELL_HEIGHT - CELL_SPACING)
    cell.ease, cell.offset = 1, 0
    cell.highlight = W.Highlight(cell)
    cell.highlight:Hide()
    cell.icon = W.Icon(cell, CELL_ICON)
    cell.icon:SetPoint("LEFT", 4, 0)
    cell.name = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.name:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", 8, 1)
    cell.name:SetPoint("RIGHT", -6, 0)
    cell.name:SetJustifyH("LEFT")
    cell.name:SetWordWrap(false)
    cell.name:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
    cell.bar = Bar(cell)
    cell.bar:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", 8, 1)
    cell.bar:SetPoint("RIGHT", -6, 0)
    cell:RegisterForClicks("LeftButtonUp")
    cell:SetScript("OnEnter", function(self) ui.Hover(self, HoverCell) end)
    cell:SetScript("OnLeave", function(self)
        ui.Unhover(self)
        self.highlight:Hide()
        self.name:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
        tip:Hide()
    end)
    cell:SetScript("OnClick", function(self)
        tip:Hide()
        if self.entry.filter then return ns.view.AddFilter(self.entry.filter) end
        ns.view.Open(self.entry)
    end)
    cells[i] = cell
    return cell
end

local function PlaceCells()
    local scrolls = overview.lines > OVERVIEW_LINES
    local columns = overview.columns
    local width = (W.WIDTH - 2 * OVERVIEW_PAD - (columns - 1) * CELL_GAP - (scrolls and ui.SCROLL_ROOM or 0)) / columns
    ui.NoteCursor()
    for i = 1, overview.count do
        local cell = cells[i]
        local column, line = (i - 1) % columns, math.floor((i - 1) / columns) - overview.top
        if line >= 0 and line < OVERVIEW_LINES then
            cell:SetWidth(width)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", column * (width + CELL_GAP), -line * CELL_HEIGHT)
            cell.offset = OVERVIEW_PAD + line * CELL_HEIGHT
            cell:Show()
            FadeCell(cell)
        else
            cell:Hide()
        end
    end
end

function ui.ScrollOverview(top)
    overview.top = top
    PlaceCells()
    ui.PlaceThumb()
end

function ui.RenderOverview(entries)
    if not entries then
        overview:Hide()
        return nil
    end
    local shown = 0
    for _, entry in ipairs(entries) do
        if entry.bar then
            shown = shown + 1
            local cell = Cell(shown)
            cell.entry = entry
            cell.icon:SetTexture(entry.icon)
            cell.name:SetText(entry.name)
            FillBar(cell.bar, entry.bar)
        end
    end
    for i = shown + 1, #cells do cells[i]:Hide() end
    -- freshly opened: from the top, the cells fade in; refreshed: where it was
    local fresh = not overview:IsShown()
    if fresh then overview.top = 0 end
    overview.columns = 2
    overview.count, overview.lines = shown, math.ceil(shown / overview.columns)
    overview.top = math.min(overview.top, math.max(overview.lines - OVERVIEW_LINES, 0))
    overview:Show()
    PlaceCells()
    if fresh then
        for i = 1, shown do
            fading.delay = (i - 1) * CELL_STAGGER
            W.Tween(cells[i], "fade", fading)
        end
    end
    return math.max(math.min(overview.lines, OVERVIEW_LINES), 1) * CELL_HEIGHT + 2 * OVERVIEW_PAD
end
