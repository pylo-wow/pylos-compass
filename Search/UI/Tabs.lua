local ns = select(2, ...).search
local L = ns.L

-- The tabs: the categories on top of the bar, the close tab at the end of their row, and the subcategories
-- left of the window below the bar.

local S = ns.state
local W = ns.widgets
local ui = ns.ui
local bar, tip = ui.bar, ui.tip
local LightTab = W.LightTab

-- Category tabs
-- On top of the bar, one per switched-on category, like the subcategory tabs: their lower end is under the
-- bar's frame. The one searched in stands out and lights up, the others are dimmed. A click picks one,
-- hovering names it. Made once per category, placed by RenderBar (ui.PlaceChips). They rise out from under
-- the bar one after another when it opens, the close tab last (shared with the recommendations window's tabs:
-- UI\Kit\Widgets.lua).
local TAB_SIZE, TAB_GAP, TAB_OUT = W.TAB_SIZE, W.TAB_GAP, W.TAB_OUT
local FADE_TIME, TAB_STAGGER, TAB_RISE = W.FADE_TIME, W.TAB_STAGGER, W.TAB_RISE
local TUCK = 2 -- the tab row sits this far under the bar's frame edge

local chips = CreateFrame("Frame", nil, bar)
chips:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", W.TAB_INSET, -TUCK)
chips:SetFrameLevel(math.max(bar:GetFrameLevel() - 3, 0))
chips:SetSize(1, TAB_SIZE)

local function Chip(source)
    local chip = W.IconTab(chips, TAB_SIZE)
    W.ShowIcon(chip.icon, source, TAB_SIZE - 14)
    chip.source = source
    chip.rise = 1
    chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    chip:SetScript("OnClick", function(_, button)
        if button == "RightButton" then return ui.ShowCategoryMenu(source) end
        ns.view.PickScope(source)
    end)
    chip:SetScript("OnEnter", function(self)
        W.ControlTip(tip, self, "ANCHOR_TOP", source.name, self.countText)
    end)
    chip:SetScript("OnLeave", function() tip:Hide() end)
    return chip
end

-- one per category, made at load so the windows get dressed with the others
for _, source in ipairs(ns.sources) do source.chip = Chip(source) end

-- a chip in its place (slot: its place in the row): rise 0 under the bar's frame, 1 out; the one searched in stands out
local function PlaceChip(chip)
    chip:SetAlpha(chip.rise)
    chip:ClearAllPoints()
    chip:SetPoint("BOTTOMLEFT", (chip.slot - 1) * (TAB_SIZE + TAB_GAP),
        (chip.on and TAB_OUT or 0) - TAB_RISE * (1 - chip.rise))
end
local function Rise(chip, value)
    chip.rise = value
    PlaceChip(chip)
end
local rising = { duration = FADE_TIME, apply = Rise }

local shownChips = {}
function ui.PlaceChips()
    wipe(shownChips)
    local active = {}
    for _, source in ipairs(ns.ActiveSources()) do active[source] = true end
    for _, source in ipairs(ns.sources) do
        local chip = source.chip
        chip:SetShown(active[source] == true)
        if active[source] then
            shownChips[#shownChips + 1] = chip
            chip.slot = #shownChips
            LightTab(chip, source == S.scope, chip.empty)
            PlaceChip(chip)
        end
    end
end

-- How many results each category has for the typed text (Index.lua's Count): in its tab's tooltip; a tab
-- without any is dimmed. counts nil (nothing typed, a detail view): no numbers. SEARCH_LIMIT or more: "50+".
-- passing (filters set): source -> how many of them pass, "5 of 42"
local function Number(count) return count >= ns.SEARCH_LIMIT and ns.SEARCH_LIMIT .. "+" or tostring(count) end
function ui.ShowCounts(counts, passing)
    for _, source in ipairs(ns.sources) do
        local chip = source.chip
        local count = counts and counts[source]
        local passed = count and passing and passing[source]
        chip.count = count and Number(count) or nil
        if passed then
            chip.countText = L["%s of %s"]:format(Number(passed), chip.count)
        elseif count then
            chip.countText = count == 0 and L["No results"] or count == 1 and L["1 result"]
                or L["%s results"]:format(chip.count)
        else
            chip.countText = nil
        end
        chip.empty = count == 0
        if chip:IsShown() then LightTab(chip, source == S.scope, chip.empty) end
    end
end

-- The close tab (UI\Kit\Widgets.lua): at the right end of the tabs' row, W.TAB_INSET in from the bar's
-- right edge; it rises last, W.CLOSE_TAB_DELAY after the filter window.
local closeTab = W.CloseTab(chips, TAB_SIZE, tip, function() ns.Close() end)
local function RiseClose(tab, value)
    tab:SetAlpha(value)
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -W.TAB_INSET, -TUCK - TAB_RISE * (1 - value))
end
local closeRising = { delay = W.CLOSE_TAB_DELAY, duration = W.CLOSE_TAB_TIME, apply = RiseClose }
ui.After("filters", function() W.Tween(closeTab, "rise", closeRising) end)

-- the search opens: the tabs rise again with the bar, the close tab waits
function ui.RaiseChips()
    for _, source in ipairs(ns.sources) do source.chip.rise = 1 end
    ui.PlaceChips()
    for i, chip in ipairs(shownChips) do
        rising.delay = (i - 1) * TAB_STAGGER
        W.Tween(chip, "rise", rising)
    end
    W.Tween(closeTab, "rise", nil)
    RiseClose(closeTab, 0)
end

-- Subcategory tabs
-- The subcategories of the category searched in (only those offered, e.g. your professions) as tabs on the left
-- edge of the window below the bar (list or detail view): W.SideTabs, as in the recommendations window. A click sets
-- one, or clears it if set. The window beside them is at least as tall as the tabs need; while it grows,
-- tabs below its edge fade in as it reaches them.
local TAB_INSET = W.TAB_INSET
local WINDOW_GAP = ui.WINDOW_GAP
local side = W.SideTabs(bar, {
    tip = tip,
    room = function()
        local window = ui.detail:IsShown() and ui.detail or ui.list
        return window:IsShown() and window:GetHeight() - TAB_INSET - WINDOW_GAP or 0
    end,
    onClick = function(f)
        ns.view.ToSearch()
        -- the text typed stays (a subcategory narrows the same search)
        if ns.view.Subcategory() == f then ns.view.RemoveFilter(1) else ns.view.AddFilter(f, true) end
    end,
})
-- below the windows' frame (their box is one level under them): the frame covers the tabs' open end, so they
-- come out from under it
side.frame:SetPoint("TOPRIGHT", bar, "BOTTOMLEFT", 2, -WINDOW_GAP - TAB_INSET)
side.frame:SetFrameLevel(math.max(bar:GetFrameLevel() - 3, 0))

function ui.PlaceTabs() side.Place() end

function ui.ShowSubTabs()
    local scope, sub = S.scope, ns.view.Subcategory()
    local list = scope and ns.Subcategories(scope) or {}
    side.Show(list, sub and sub.key)
    ui.tabsHeight = side.height
    -- the list shows as many rows as fit beside the tabs (and beside the filter window: as tall as it,
    -- filled with rows)
    ui.rowsShown = math.max(ns.MAX_RESULTS,
        math.ceil((math.max(ui.tabsHeight, ui.filterHeight or 0) - 12) / W.ROW_HEIGHT))
end
