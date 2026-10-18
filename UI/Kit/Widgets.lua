-- Pylos UI Kit 1.1.0 (copied from pylos-dev\shared; do not edit here)
local _, ns = ...
if ns.off then return end

-- Shared building blocks of Pylos addon windows: service "widgets" 1.1
-- (ns.widgets, set here; 1.1 added W.Window); look in STYLEGUIDE.md. Nothing addon-specific:
-- differences come in as parameters.

local L = ns.L
local W = {}
ns.widgets = W

-- Animation curves

function W.Clamp(x) return x < 0 and 0 or x > 1 and 1 or x end
function W.EaseOutCubic(p) return 1 - (1 - p) ^ 3 end
local Clamp, EaseOutCubic = W.Clamp, W.EaseOutCubic

-- Tokens: sizes and times both addons share (STYLEGUIDE.md)

W.WIDTH = 460                -- search bar, suggestions window
W.ROW_HEIGHT = 34
W.NAME_X = 6 + W.ROW_HEIGHT + 6 -- where a row's name starts (RowParts)
W.TAB_SIZE, W.TAB_GAP = 40, 8
W.TAB_INSET = 14             -- tabs' row from the window's corner; the close tab from its other end
W.DOT = "  ·  "              -- between parts of a line
W.TIP_GAP = 10               -- tooltip beside a window
W.TOOLTIP_WAIT = 1.5         -- max seconds a tooltip waits for item data
-- seconds: in, out; a following height or place covers FOLLOW times the remaining distance per second
W.FADE_TIME, W.CLOSE_TIME = 0.18, 0.12
W.FOLLOW = 16
-- tabs rise from under the window one after another, the close tab last
W.TAB_RISE, W.TAB_STAGGER = 8, 0.04
W.CLOSE_TAB_TIME, W.CLOSE_TAB_DELAY = 0.22, 0.12

-- Colours { r, g, b } (STYLEGUIDE.md)
W.GOLD = { 1, 0.82, 0 }            -- marked, headings, notices
W.WHITE = { 1, 1, 1 }              -- tooltip text, control lines
W.LIGHT = { 0.88, 0.86, 0.8 }      -- names at rest
W.SUB = { 0.6, 0.58, 0.52 }        -- the line of details, secondary text
W.SOFT = { 0.8, 0.8, 0.8 }         -- secondary facts in a tooltip
W.DIM = { 0.55, 0.55, 0.55 }       -- dimmed names
W.PLACEHOLDER = { 0.8, 0.8, 0.82 } -- empty lists, the search bar's hint
W.GREEN = { 0.25, 1, 0.25 }        -- what a click does, upgrades, done
W.RED = { 1, 0.3, 0.3 }            -- errors
W.ORANGE = { 1, 0.5, 0.25 }        -- warnings, only for one side
W.BLUE = { 0.6, 0.85, 1 }          -- places, people to go to
W.BRONZE = { 0.62, 0.5, 0.3 }      -- thin lines: a frame (alpha 0.9), a rule (0.5)
W.BRONZE_LINE, W.BRONZE_RULE = 0.9, 0.5
local GOLD, WHITE, SUB = W.GOLD, W.WHITE, W.SUB
local STATUS_ON = { 0.85, 0.8, 0.7 } -- a marked row's status (MarkRow)
local ICON_REST = 0.85               -- an unmarked row's icon
local TAB_DIM, TAB_EMPTY = 0.6, 0.3  -- a tab not set; one with nothing in it

-- top-of-screen line: error in red, notice in gold
function W.Error(text) UIErrorsFrame:AddMessage(text, W.RED[1], W.RED[2], W.RED[3]) end
function W.Notice(text) UIErrorsFrame:AddMessage(text, GOLD[1], GOLD[2], GOLD[3]) end

-- Animation driver
-- All animations run on one hidden frame, shown only while something moves
-- (STYLEGUIDE.md section 10).
--   W.Tween(frame, key, spec)  spec is read at once (reusable): duration (default
--       FADE_TIME), delay, ease (default EaseOutCubic; false: linear),
--       apply(frame, value): value 0-1 through the curve, once at the start (0,
--       also while waiting), then every frame; done(frame) after the last apply.
--       Same frame and key replaces the running tween; duration 0 ends at once;
--       spec nil stops it.
--   W.Follow(obj, field, target, apply, near)  obj[field] (number) follows target,
--       covering FOLLOW times the remaining distance per second, then
--       apply(obj, value, arrived) every frame; within near (default 0.5) it
--       arrives. A new target takes over; target nil stops it.
local driver = CreateFrame("Frame")
driver:Hide()
local moving = {}                -- running tweens and followers, in start order
local tweens, follows = {}, {}   -- frame (object) -> key (field) -> its record
local spare = {}                 -- finished records, used again

local function Add(map, owner, key, record)
    local mine = map[owner]
    if not mine then
        mine = {}
        map[owner] = mine
    end
    if mine[key] then mine[key].dead = true end
    mine[key] = record
    record.map, record.owner, record.key, record.dead = map, owner, key, false
    moving[#moving + 1] = record
    driver:Show()
end

local function Remove(record)
    record.dead = true
    local mine = record.map[record.owner]
    if mine[record.key] == record then mine[record.key] = nil end
end

local function NewRecord()
    local record = table.remove(spare)
    if record then wipe(record) else record = {} end
    return record
end

-- one frame of a tween; true when it ended
local function StepTween(t, now)
    if now < t.start then return false end
    local p = t.duration > 0 and Clamp((now - t.start) / t.duration) or 1
    t.apply(t.owner, t.ease and t.ease(p) or p)
    if p < 1 then return false end
    Remove(t)
    if t.done then t.done(t.owner) end
    return true
end

local function StepFollow(f, elapsed)
    local obj = f.owner
    local value = obj[f.key]
    local d = f.target - value
    if math.abs(d) < f.near then value = f.target else value = value + d * math.min(1, elapsed * W.FOLLOW) end
    obj[f.key] = value
    local arrived = value == f.target
    if arrived then Remove(f) end
    f.apply(obj, value, arrived)
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    -- records added meanwhile wait for the next frame (they already applied their start)
    for i = 1, #moving do
        local record = moving[i]
        if not record.dead then
            if record.target then StepFollow(record, elapsed) else StepTween(record, now) end
        end
    end
    local kept = 0
    for i = 1, #moving do
        local record = moving[i]
        if record.dead then
            spare[#spare + 1] = record
        else
            kept = kept + 1
            moving[kept] = record
        end
    end
    for i = #moving, kept + 1, -1 do moving[i] = nil end
    if kept == 0 then self:Hide() end
end)

function W.Tween(frame, key, spec)
    if not spec then
        local old = tweens[frame] and tweens[frame][key]
        if old then Remove(old) end
        return
    end
    local t = NewRecord()
    t.duration, t.apply, t.done = spec.duration or W.FADE_TIME, spec.apply, spec.done
    t.start = GetTime() + (spec.delay or 0)
    if spec.ease ~= false then t.ease = spec.ease or EaseOutCubic end
    Add(tweens, frame, key, t)
    t.apply(frame, t.ease and t.ease(0) or 0)
    if t.duration <= 0 and (spec.delay or 0) <= 0 then StepTween(t, GetTime()) end
end

function W.Follow(obj, field, target, apply, near)
    local old = follows[obj] and follows[obj][field]
    if target == nil then
        if old then Remove(old) end
        return
    end
    if old then
        old.target, old.apply, old.near = target, apply, near or 0.5
        return
    end
    if obj[field] == target then return end
    local f = NewRecord()
    f.target, f.apply, f.near = target, apply, near or 0.5
    Add(follows, obj, field, f)
end

-- Tooltips (STYLEGUIDE.md section 8). anchor: a SetOwner anchor ("ANCHOR_TOP") or
-- a point beside a window { point, frame, relativePoint, x, y }
local function Own(tip, owner, anchor)
    if type(anchor) == "table" then
        tip:SetOwner(owner, "ANCHOR_NONE")
        tip:ClearAllPoints()
        tip:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    else
        tip:SetOwner(owner, anchor)
    end
end

-- name in white, optional second line in SUB ("12 suggestions")
function W.ControlTip(tip, owner, anchor, name, sub)
    Own(tip, owner, anchor)
    tip:SetText(name, WHITE[1], WHITE[2], WHITE[3])
    if sub then tip:AddLine(sub, SUB[1], SUB[2], SUB[3]) end
    tip:Show()
end

-- title in gold (or color), then one white sentence
function W.FeatureTip(tip, owner, anchor, title, text, color)
    Own(tip, owner, anchor)
    color = color or GOLD
    tip:SetText(title, color[1], color[2], color[3])
    tip:AddLine(text, WHITE[1], WHITE[2], WHITE[3], true)
    tip:Show()
end

-- An entry's name and lines (lines from Pylos Data, World\Lines.lua: { text,
-- role, wrap }). An NPC's name takes the colour of its reaction to you, as in
-- the game. Returns whether there were lines.
local REACTION = { { 1, 0.25, 0.2 }, { 1, 0.9, 0.2 }, { 0.3, 1, 0.3 } } -- hostile, neutral, friendly
local ROLE = { white = WHITE, soft = W.SOFT, sub = SUB, gold = GOLD, blue = W.BLUE, orange = W.ORANGE,
    green = W.GREEN }
function W.EntryText(tooltip, entry)
    local c = REACTION[entry.reaction or 0] or WHITE
    tooltip:SetText(entry.name, c[1], c[2], c[3])
    local lines = entry.lines
    for _, line in ipairs(lines or {}) do
        local color = ROLE[line[2] or "white"] or WHITE
        tooltip:AddLine(line[1], color[1], color[2], color[3], line[3])
    end
    return lines ~= nil and lines[1] ~= nil
end

-- Symbols

-- sets an atlas if the client has it; false otherwise
function W.Atlas(texture, name)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        texture:SetAtlas(name)
        return true
    end
    return false
end
local Atlas = W.Atlas

-- Part of a micro menu symbol shown: a square tight around it, shadow left out
-- (whole it was tiny). Measured in file 8200846 (wago.tools), in a symbol's
-- 64 x 82 pixels. Keyed by a word of the atlas name.
local ATLAS_CROPS = {
    spellbook = { 10.5 / 64, 50.5 / 64, 21.5 / 82, 61.5 / 82 },
    spectalents = { 13.5 / 64, 48.5 / 64, 23 / 82, 58 / 82 },
    -- bag bar backpack (atlas bags-up-c60, 215 x 226 in file 7960142): bag x 21-191, y 24-200
    ["bags-up"] = { 21 / 215, 191 / 215, 27 / 226, 197 / 226 },
    -- group finder eye: x 13-49, y 24-58
    groupfinder = { 14.5 / 64, 47.5 / 64, 24.5 / 82, 57.5 / 82 },
    -- quest log exclamation mark: x 23-40, y 14-67
    questlog = { 4.5 / 64, 58.5 / 64, 13.5 / 82, 67.5 / 82 },
}
function W.AtlasCrop(name)
    name = name:lower()
    for word, crop in pairs(ATLAS_CROPS) do
        if name:find(word, 1, true) then return crop end
    end
    return { 0, 1, 0, 1 }
end

-- Two micro menu symbols as { file, left, right, top, bottom }: by file, because
-- the client does not know the quest log's atlas at run time. File 8200846 is
-- 1024 x 512; cells from DB2 UiTextureAtlasMember (quest log x 397, y 169; group
-- finder x 133, y 421), cropped as above.
W.QUEST_PART = { 8200846, (397 + 4.5) / 1024, (397 + 58.5) / 1024, (169 + 13.5) / 512, (169 + 67.5) / 512 }
W.EYE_PART = { 8200846, (133 + 14.5) / 1024, (133 + 47.5) / 1024, (421 + 24.5) / 512, (421 + 57.5) / 512 }

-- Shows a thing's symbol: portrait, texture part, atlas (iconAtlas: micro menu
-- symbols, cut to their middle) or icon file with its painted border cut off.
-- fallback: icon for a thing without one (else the texture stays empty)
function W.ShowIcon(texture, thing, size, fallback)
    -- an NPC with a model: its portrait, as the target frame draws it (if the client has the function)
    if thing.displayID and SetPortraitTextureFromCreatureDisplayID then
        SetPortraitTextureFromCreatureDisplayID(texture, thing.displayID)
        texture:SetTexCoord(0, 1, 0, 1)
        if size then texture:SetSize(size, size) end
        return
    end
    -- part of a texture file { file, left, right, top, bottom } (micro menu symbol
    -- whose atlas the client lacks at run time). A quest without icon of its own
    -- gets the quest log's exclamation mark.
    local part = thing.iconPart or (thing.domain == "quests" and not thing.icon and W.QUEST_PART) or nil
    if part then
        texture:SetTexture(part[1])
        texture:SetTexCoord(part[2], part[3], part[4], part[5])
        if size then texture:SetSize(size, size) end
        return
    end
    local info = thing.iconAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(thing.iconAtlas)
    if info and info.file then
        local crop = W.AtlasCrop(thing.iconAtlas)
        local left, right = info.leftTexCoord, info.rightTexCoord
        local top, bottom = info.topTexCoord, info.bottomTexCoord
        texture:SetTexture(info.file)
        texture:SetTexCoord(left + (right - left) * crop[1], left + (right - left) * crop[2],
            top + (bottom - top) * crop[3], top + (bottom - top) * crop[4])
        if size then texture:SetSize(size, size) end
        return
    end
    texture:SetTexture(thing.icon or fallback)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if size then texture:SetSize(size, size) end
end

-- a text's full width, also where it is cut off
function W.TextWidth(fontString)
    return fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
end

-- Windows
-- A game window behind a frame, one level below so the text stays on top. Dressed
-- on first show (Style): darkened classic option window stone and the NineSlice
-- layout "Dialog", which takes the client's bronze style. The options window's
-- "ButtonFrameTemplateNoPortrait" is for big windows and sticks out around a narrow bar.
local panels, background = {}, 1

local function Style(box)
    if box.styled then return end
    box.styled = true
    box.bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    box.bg:SetHorizTile(true)
    box.bg:SetVertTile(true)
    box.bg:SetVertexColor(0.55, 0.55, 0.55)
    if NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout("Dialog") then
        NineSliceUtil.ApplyLayoutByName(box, "Dialog")
        -- a layout may bring its own background piece; it fades with ours
        if box.Center then
            table.insert(box.backgrounds, box.Center)
            box.Center:SetAlpha(background)
        end
    elseif box.SetBackdrop then
        box:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
    end
end

-- frame.box: the window behind the frame, dressed on its first show (the box's
-- OnShow; the frame's own OnShow stays the addon's)
function W.Panel(frame)
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", -6, 6)
    box:SetPoint("BOTTOMRIGHT", 6, -6)
    box:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetPoint("TOPLEFT", 4, -4)
    box.bg:SetPoint("BOTTOMRIGHT", -4, 4)
    box.bg:SetAlpha(background)
    box.backgrounds = { box.bg } -- what SetBackground fades
    box:SetScript("OnShow", Style)
    if box:IsVisible() then Style(box) end
    frame.box = box
    panels[#panels + 1] = frame
    return box
end

-- A movable window: a frame on the DIALOG strata with its panel (W.Panel), dragged with the left mouse button, kept on
-- screen. The addon keeps the place; tabs and the close tab are the addon's (W.SideTabs, W.CloseTab).
--   local window = W.Window(options)
--     options.name       frame name (optional)
--     options.width, options.height
--     options.saved      { left, top } the addon kept (TOPLEFT against the screen's bottom left), or nil
--     options.default    function(window) the first placement when nothing is saved (default: screen centre)
--     options.onMoved    function(left, top) after a drag, for the addon to keep
--     options.locked     function() -> true: no dragging (an option "Lock window")
-- A window with secure buttons is protected: in combat it can neither move nor be re-anchored, so a drag is refused
-- then, and a drag still going when combat starts is not reported.
function W.Window(options)
    local window = CreateFrame("Frame", options.name, UIParent)
    window:SetSize(options.width, options.height)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(10) -- room below for the panel and the tabs
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    local function Frozen() return InCombatLockdown() and window:IsProtected() end
    window:SetScript("OnDragStart", function()
        if Frozen() or (options.locked and options.locked()) then return end
        window.dragging = true
        window:StartMoving()
    end)
    window:SetScript("OnDragStop", function()
        if not window.dragging then return end
        window.dragging = nil
        window:StopMovingOrSizing()
        if Frozen() then return end
        -- StartMoving anchors anew: back to the top left corner, the form that is saved
        local left, top = window:GetLeft(), window:GetTop()
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        if options.onMoved then options.onMoved(left, top) end
    end)
    local saved = options.saved
    if type(saved) == "table" and type(saved[1]) == "number" and type(saved[2]) == "number" then
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved[1], saved[2])
    elseif options.default then
        options.default(window)
    else
        window:SetPoint("CENTER")
    end
    W.Panel(window)
    return window
end

-- background opacity (0-1) of every window; not border and text
function W.SetBackground(alpha)
    background = alpha
    for _, panel in ipairs(panels) do
        for _, texture in ipairs(panel.box.backgrounds) do texture:SetAlpha(alpha) end
    end
end

-- icon with its painted-in border cut off, in a modern action button frame (atlas; skipped if missing)
function W.Icon(parent, size, layer)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local frame = parent:CreateTexture(nil, "OVERLAY")
    frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
    Atlas(frame, "UI-HUD-ActionBar-IconFrame")
    icon.frame = frame
    return icon
end

-- selection bar of the options window's category list (atlas; else the dimmed quest log highlight)
function W.Highlight(parent)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    if not Atlas(texture, "Options_List_Active") then
        texture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        texture:SetBlendMode("ADD")
        texture:SetAlpha(0.45)
    end
    return texture
end

-- Tabs
-- Bronze window frame, glow when set, icon without the action button frame. The
-- set one stands out TAB_OUT px (placed by the addon).
W.TAB_OUT = 4

function W.IconTab(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    W.Panel(button)
    button.glow = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.glow:SetPoint("TOPLEFT", 3, -3)
    button.glow:SetPoint("BOTTOMRIGHT", -3, 3)
    if not Atlas(button.glow, "Options_List_Active") then button.glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2) end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(size - 14, size - 14)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- hovered, a dimmed tab shows its icon whole: the same icon in full colour in
    -- the HIGHLIGHT layer (no script: addons set the tabs' own). Copied by LightTab.
    button.hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.hover:SetAllPoints(button.icon)
    return button
end

-- set tab lit, others dimmed; empty: dimmed further. Call after the icon
-- changed: it copies the icon for hovering.
function W.LightTab(button, on, empty)
    button.on = on
    button.glow:SetShown(on)
    button.icon:SetDesaturated(not on)
    button.icon:SetAlpha(on and 1 or empty and TAB_EMPTY or TAB_DIM)
    -- atlas first: its file is the whole atlas sheet, copying file and coordinates showed other symbols
    local atlas = button.icon:GetAtlas()
    local file = button.icon:GetTextureFileID() or button.icon:GetTexture()
    if atlas then
        button.hover:SetAtlas(atlas)
    elseif file then
        button.hover:SetTexture(file)
        button.hover:SetTexCoord(button.icon:GetTexCoord())
    end
end

-- Close tab: the game's red × in a tab frame, dimmed like an unset tab, red when
-- hovered. Placed by the addon at the right end of the row, TAB_INSET from the
-- window's right edge.
function W.CloseTab(parent, size, tooltip, onClick)
    local tab = W.IconTab(parent, size)
    tab.icon:SetSize(size - 22, size - 22)
    if not Atlas(tab.icon, "common-icon-redx") then tab.icon:SetTexture("Interface\\Buttons\\UI-StopButton") end
    W.LightTab(tab, false)
    tab.glow:Hide()
    tab:RegisterForClicks("LeftButtonUp")
    tab:SetScript("OnClick", onClick)
    tab:SetScript("OnEnter", function(self) W.ControlTip(tooltip, self, "ANCHOR_TOP", CLOSE) end)
    tab:SetScript("OnLeave", function() tooltip:Hide() end)
    return tab
end

-- Subcategory tabs
-- Tabs on a window's left edge, one under the other, like the classic spell
-- book's skill line tabs. Right end under the window's frame; the set one stands
-- out TAB_OUT and lights up. Shown only as far down as the window reaches.
-- Changing the set: the old tabs slide back under the frame and fade, then the
-- new ones come out one after another.
--   local side = W.SideTabs(parent, options)
--     options.tip           tooltip naming a hovered tab
--     options.room()        how far the window reaches below the tabs' top (px)
--     options.onClick(item) a tab clicked
--   side.frame             placed by the addon: TOPRIGHT TAB_INSET below the
--                          window's top left corner, 2 px into it; frame level below the window's
--   side.Show(list, set)   list: { { key, name, icon }, ... }; set: the one lit
--   side.Place()           the window's height changed
--   side.height            window height the shown tabs need (0: none)
W.SIDE_SLIDE = 26                          -- px under the window's frame
W.SIDE_TIME, W.SIDE_STAGGER = 0.22, 0.045  -- seconds to come out, one after another

function W.SideTabs(parent, options)
    local SIZE, GAP, OUT = W.TAB_SIZE, W.TAB_GAP, W.TAB_OUT
    local side = { height = 0 }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(SIZE + OUT, 1)
    frame:Hide()
    side.frame = frame
    local tabs = {}

    local function Tab(i)
        local tab = tabs[i]
        if tab then return tab end
        tab = W.IconTab(frame, SIZE)
        tab.out, tab.top = 1, (i - 1) * (SIZE + GAP)
        tab:RegisterForClicks("LeftButtonUp")
        tab:SetScript("OnClick", function(self) options.onClick(self.item) end)
        tab:SetScript("OnEnter", function(self) W.ControlTip(options.tip, self, "ANCHOR_LEFT", self.item.name) end)
        tab:SetScript("OnLeave", function() options.tip:Hide() end)
        tabs[i] = tab
        return tab
    end

    -- a tab in its place: out 0 (under the window's frame) .. 1
    local function PlaceTab(tab)
        local room, out = options.room(), tab.out
        tab:ClearAllPoints()
        tab:SetPoint("TOPRIGHT", (tab.on and -OUT or 0) * out + W.SIDE_SLIDE * (1 - out), -tab.top)
        tab:SetAlpha(out * W.Clamp((room - tab.top) / SIZE))
    end
    function side.Place()
        if not frame:IsShown() then return end
        for _, tab in ipairs(tabs) do
            if tab:IsShown() then PlaceTab(tab) end
        end
    end
    local function Out(tab, value)
        tab.out = value
        PlaceTab(tab)
    end
    local coming = { duration = W.SIDE_TIME, apply = Out }

    local function Apply(list, set)
        for i, item in ipairs(list) do
            local tab = Tab(i)
            tab.item = item
            W.ShowIcon(tab.icon, item)
            W.LightTab(tab, item.key == set)
            tab:Show()
            PlaceTab(tab)
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
    end
    local function ComeOut()
        for i, tab in ipairs(tabs) do
            if tab:IsShown() then
                coming.delay = (i - 1) * W.SIDE_STAGGER
                W.Tween(tab, "out", coming)
            end
        end
    end
    -- the old set slides back (all at once), then the new one comes out
    local leaving = { duration = W.CLOSE_TIME,
        apply = function(_, value)
            for _, tab in ipairs(tabs) do
                if tab:IsShown() then Out(tab, 1 - value) end
            end
        end,
        done = function()
            local pending = side.pending
            side.leaving, side.pending = false, nil
            Apply(pending.list, pending.set)
            ComeOut()
        end,
    }

    function side.Show(list, set)
        local shown = #list
        local keys = {}
        for i, item in ipairs(list) do keys[i] = item.key end
        local which = table.concat(keys, ",")
        if shown > 0 and frame:IsShown() and side.which and side.which ~= which then
            -- another set: the old tabs leave first, the new ones follow
            side.pending = { list = list, set = set }
            if not side.leaving then
                side.leaving = true
                for _, tab in ipairs(tabs) do W.Tween(tab, "out", nil) end
                W.Tween(frame, "leave", leaving)
            end
        elseif shown > 0 and side.leaving then
            -- still leaving for this set (refreshed meanwhile): keep going
            side.pending = { list = list, set = set }
        else
            local fresh = shown > 0 and not frame:IsShown()
            if side.leaving then
                side.leaving = false
                W.Tween(frame, "leave", nil)
            end
            side.pending = nil
            frame:SetShown(shown > 0)
            Apply(list, set)
            if fresh then ComeOut() end
        end
        side.which = shown > 0 and which or nil
        -- same gap (TAB_INSET) below the last tab as above the first
        side.height = shown > 0 and shown * (SIZE + GAP) - GAP + 2 * W.TAB_INSET or 0
        frame:SetShown(shown > 0)
    end
    return side
end

-- Rows

-- centred "nothing here" line
function W.Empty(parent)
    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetTextColor(W.PLACEHOLDER[1], W.PLACEHOLDER[2], W.PLACEHOLDER[3])
    return empty
end

-- A row's parts (a frame of the given height, placed by the addon): left icon
-- (with carried count from 2, and quality frame), name, a grey details line (sub)
-- below it; right the state (status) and a reason's symbol with a count. The name
-- starts at 6 + height + 6.
function W.RowParts(row, height)
    row.highlight = W.Highlight(row)
    row.icon = W.Icon(row, height - 10)
    row.icon:SetPoint("CENTER", row, "LEFT", 6 + height / 2 - 4, 0)
    -- item quality as a tinted white item frame round the icon, as in the bags
    row.quality = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
    row.quality:SetAllPoints(row.icon)
    row.quality:Hide()
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.count:SetDrawLayer("OVERLAY", 2)
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 2)
    -- reason symbol on the right, its count on the symbol's corner
    row.reason = row:CreateTexture(nil, "OVERLAY")
    row.reason:SetSize(16, 16)
    row.reason:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.reason:Hide()
    row.reasonText = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.reasonText:SetPoint("BOTTOMRIGHT", row.reason, "BOTTOMRIGHT", 3, -3)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", -10, 0)
    -- a long name is cut off with "..." before the right side (it overlapped)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row, "LEFT", 6 + height + 6, -3)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.sub:SetTextColor(SUB[1], SUB[2], SUB[3])
    return row
end

-- quality frame round the icon (green and up); quality from the entry, else the client
function W.ShowQuality(texture, entry)
    local quality = entry.quality or (entry.itemID and C_Item.GetItemQualityByID(entry.itemID))
    local ok, r, g, b = false
    if quality and quality >= 2 then ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality) end
    texture:SetShown(ok == true)
    if ok then texture:SetVertexColor(r, g, b) end
end

-- marked (mouse, keys): selection bar, gold name, brighter right side; unmarked:
-- light name (dimmed: grey), slightly dimmed icon
function W.MarkRow(row, on, dimmed)
    row.highlight:SetShown(on and true or false)
    local name = on and GOLD or dimmed and W.DIM or W.LIGHT
    row.name:SetTextColor(name[1], name[2], name[3])
    local status = on and STATUS_ON or SUB
    row.status:SetTextColor(status[1], status[2], status[3])
    row.icon:SetAlpha(on and 1 or ICON_REST)
end

-- Reasons in a tooltip: "Why" in gold, reasons in white; a quest's "Still to do"
-- the same (needs: { text, from }, from in grey below); what a click does in
-- green. Each part only if non-empty.
function W.AddWhy(tooltip, why, needs, click)
    if why and why[1] then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Why"], GOLD[1], GOLD[2], GOLD[3])
        for _, line in ipairs(why) do tooltip:AddLine(line, WHITE[1], WHITE[2], WHITE[3], true) end
    end
    if needs and needs[1] then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Still to do"], GOLD[1], GOLD[2], GOLD[3])
        for _, need in ipairs(needs) do
            tooltip:AddLine(need.text, WHITE[1], WHITE[2], WHITE[3], true)
            if need.from then tooltip:AddLine("   " .. L["from %s"]:format(need.from), SUB[1], SUB[2], SUB[3], true) end
        end
    end
    if click then
        tooltip:AddLine(" ")
        tooltip:AddLine(click, W.GREEN[1], W.GREEN[2], W.GREEN[3])
    end
end

-- place = uiMapID * 1000000 + x * 1000 + y (x, y in thousandths); name for the message
function W.Waypoint(name, place)
    local mapID = math.floor(place / 1000000)
    local x, y = math.floor(place / 1000) % 1000 / 1000, place % 1000 / 1000
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        W.Error(L["No waypoint possible on this map."])
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    local info = C_Map.GetMapInfo(mapID)
    W.Notice(L["Waypoint: %s, %s %d, %d"]:format(name, info and info.name or "",
        math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5)))
end

-- Context menu
-- A small window at the cursor: what can be done with an entry. A click on a
-- line does it and closes the menu; a click elsewhere closes it too. Lines in
-- groups split by thin rules, each with a symbol; the main line first, in gold,
-- marked so Enter does it; feedback on a suggestion as a bar of symbols at the
-- bottom. Keys walk the lines, then the bar's symbols (menu.slots; Step, Confirm).

-- all in the client (DB2 ManifestInterfaceData, UiTextureAtlasMember)
W.SYMBOLS = {
    details = { file = 134442, crop = true },   -- Interface\Icons\INV_Misc_Spyglass_03
    -- the map's own waypoint pin
    waypoint = { atlas = "Waypoint-MapPin-Tracked", file = 134269, crop = true }, -- else INV_Misc_Map_01
    tryOn = { file = 135030, crop = true },     -- INV_Shirt_White_01
    chat = { file = 133471, crop = true },      -- INV_Letter_15
    tool = { file = 134520, crop = true },      -- INV_Misc_Wrench_01 (the book is the spell book's)
    good = { file = 456032, crop = true },      -- THUMBUP
    bad = { file = 456031, crop = true },       -- THUMBSDOWN
    hide = { atlas = "transmog-icon-hidden", file = 136813 },     -- else ReadyCheck-NotReady
    unhide = { atlas = "socialqueuing-icon-eye", file = 133884, crop = true }, -- else INV_Misc_Eye_01
    forget = { file = 851904 },                 -- Interface\Buttons\UI-RefreshButton
    questLog = { file = 133740, crop = true },  -- INV_Misc_Book_08
}

-- an atlas, or the file (Interface\Icons ones cropped of their frame) where the client lacks it
local function SetSymbol(texture, symbol)
    if symbol.atlas and C_Texture.GetAtlasInfo(symbol.atlas) then
        texture:SetAtlas(symbol.atlas)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    texture:SetTexture(symbol.file)
    if symbol.crop then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) else texture:SetTexCoord(0, 1, 0, 1) end
end

local MENU_ROW, MENU_MIN = 22, 140
local MENU_RULE, MENU_BAR, MENU_SYMBOL = 9, 30, 22
local MENU_ICON, MENU_TEXT_X = 16, 30 -- a line's symbol and where its text starts
local MENU_FADE = 0.1                 -- seconds it fades in
local MENU_GUARD = 0.05               -- the click that opened it does not close it

-- Makes a menu. options: parent (its windows: hidden with them), strata, level
-- (above the windows), tooltip (the addon's own, for the bar's symbols; hidden
-- when the menu opens, else the menu lies under it), onMark(slot) (marked line
-- or symbol, or nil), onHide. Returns the menu frame with:
--   menu.Open(groups, anchor, bar)  groups: lists of lines { text, run, spell,
--       icon = symbol, main = true }, split by rules; bar: symbols { symbol, tip,
--       run } at the bottom (or nil); symbols as in SYMBOLS. At the cursor, or
--       below anchor; the first line is marked. A line with a spell casts it (by
--       name, via a secure button over the line) on a click, then runs; macro =
--       text runs that macro text the same way (for a protected call no addon may
--       make, e.g. the group finder's search).
--   menu.Mark(index), menu.Step(step), menu.Confirm()   the keys
function W.Menu(options)
    local menu = CreateFrame("Frame", nil, options.parent)
    menu:SetFrameStrata(options.strata)
    menu:SetFrameLevel(options.level)
    menu:SetClampedToScreen(true)
    menu:Hide()
    W.Panel(menu)
    menu:EnableMouse(true) -- clicks on it do not reach what is behind
    menu.rows, menu.rules, menu.symbols, menu.slots = {}, {}, {}, {}
    local fade = { duration = MENU_FADE, apply = function(self, value) self:SetAlpha(value) end }

    -- A click elsewhere must only close the menu (it went through to what is below):
    -- an invisible layer over the screen, just below the menu, takes it (and the wheel)
    local blocker = CreateFrame("Button", nil, options.parent)
    blocker:SetFrameStrata(options.strata)
    blocker:SetFrameLevel(options.level - 1)
    blocker:SetAllPoints(UIParent)
    blocker:EnableMouse(true)
    blocker:EnableMouseWheel(true)
    blocker:SetScript("OnMouseDown", function() menu:Hide() end)
    blocker:SetScript("OnMouseWheel", function() end)
    blocker:Hide()
    local tooltip = options.tooltip
    -- the tooltip belongs to a symbol of this menu
    local function OwnTip()
        local owner = tooltip:GetOwner()
        return owner ~= nil and owner:GetParent() == menu
    end
    menu:SetScript("OnShow", function() blocker:Show() end)
    menu:SetScript("OnHide", function()
        blocker:Hide()
        if OwnTip() then tooltip:Hide() end
        if options.onHide then options.onHide() end
    end)

    -- marked line or symbol (keys and mouse): its highlight, a symbol's tooltip
    function menu.Mark(index)
        menu.marked = index
        for i, slot in ipairs(menu.slots) do slot.highlight:SetShown(i == index) end
        local slot = index and menu.slots[index]
        if slot and slot.tip then
            W.ControlTip(tooltip, slot, "ANCHOR_BOTTOM", slot.tip)
        elseif OwnTip() then
            tooltip:Hide()
        end
        if options.onMark then options.onMark(slot) end
    end

    local function Row(i)
        local row = menu.rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW)
        row.highlight = W.Highlight(row)
        row.highlight:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(MENU_ICON, MENU_ICON)
        row.icon:SetPoint("LEFT", 8, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", MENU_TEXT_X, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function() menu.Mark(row.slot) end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self)
            menu:Hide()
            self.run()
        end)
        -- A line that casts: a secure button over the line, shown only for such a
        -- line (opening a profession is protected; C_TradeSkillUI.OpenRecipe from
        -- addon code was blocked). It casts on the click, then the line runs. Needs
        -- press and release: with the release only it did nothing, as secure buttons
        -- act on the press by default ("action on key down").
        row.secure = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        row.secure:SetAllPoints()
        row.secure:RegisterForClicks("AnyDown", "AnyUp")
        row.secure:SetAttribute("useOnKeyDown", false)
        row.secure:SetAttribute("type", "spell")
        row.secure:SetScript("OnEnter", function() menu.Mark(row.slot) end)
        row.secure:SetScript("PostClick", function(_, _, down)
            if down then return end
            menu:Hide()
            row.run()
        end)
        row.secure:Hide()
        menu.rows[i] = row
        return row
    end

    -- a symbol of the bar
    local function Symbol(i)
        local button = menu.symbols[i]
        if button then return button end
        button = CreateFrame("Button", nil, menu)
        button:SetSize(MENU_SYMBOL, MENU_SYMBOL)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.highlight = W.Highlight(button)
        button.highlight:Hide()
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnEnter", function(self) menu.Mark(self.slot) end)
        button:SetScript("OnLeave", function(self)
            if tooltip:GetOwner() == self then tooltip:Hide() end
        end)
        button:SetScript("OnClick", function(self)
            menu:Hide()
            self.run()
        end)
        menu.symbols[i] = button
        return button
    end

    -- thin bronze rule between two groups, at y
    local rules = 0
    local function Rule(y)
        rules = rules + 1
        local rule = menu.rules[rules]
        if not rule then
            rule = menu:CreateTexture(nil, "ARTWORK")
            rule:SetHeight(1)
            rule:SetColorTexture(W.BRONZE[1], W.BRONZE[2], W.BRONZE[3], W.BRONZE_RULE)
            menu.rules[rules] = rule
        end
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", 12, y - 4)
        rule:SetPoint("TOPRIGHT", -12, y - 4)
        rule:Show()
        return y - MENU_RULE
    end

    function menu.Open(groups, anchor, bar)
        tooltip:Hide()
        wipe(menu.slots)
        rules = 0
        local width, y, rows = MENU_MIN, -8, 0
        for _, group in ipairs(groups) do
            if #group > 0 then
                if rows > 0 then y = Rule(y) end
                for _, item in ipairs(group) do
                    rows = rows + 1
                    local row = Row(rows)
                    row.text:SetFontObject(item.main and "GameFontNormal" or "GameFontHighlight")
                    row.text:SetText(item[1])
                    if item.icon then SetSymbol(row.icon, item.icon) end
                    row.icon:SetShown(item.icon ~= nil)
                    row.run = item[2]
                    row.spell = not InCombatLockdown() and item[3] or nil
                    row.macro = not InCombatLockdown() and item.macro or nil
                    if row.spell then
                        row.secure:SetAttribute("type", "spell")
                        row.secure:SetAttribute("spell", row.spell)
                    elseif row.macro then
                        row.secure:SetAttribute("type", "macro")
                        row.secure:SetAttribute("macrotext", row.macro)
                    end
                    if not InCombatLockdown() then row.secure:SetShown(row.spell ~= nil or row.macro ~= nil) end -- (a protected frame: no hiding in combat)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 6, y)
                    row:SetPoint("TOPRIGHT", -6, y)
                    row.highlight:Hide()
                    row:Show()
                    menu.slots[#menu.slots + 1] = row
                    row.slot = #menu.slots
                    width = math.max(width, W.TextWidth(row.text) + 48)
                    y = y - MENU_ROW
                end
            end
        end
        for i = rows + 1, #menu.rows do menu.rows[i]:Hide() end
        local symbols = bar and #bar or 0
        if symbols > 0 then
            if rows > 0 then y = Rule(y) end
            for i, item in ipairs(bar) do
                local button = Symbol(i)
                SetSymbol(button.icon, item[1])
                button.tip, button.run = item[2], item[3]
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 14 + (i - 1) * (MENU_SYMBOL + 10), y - (MENU_BAR - MENU_SYMBOL) / 2)
                button.highlight:Hide()
                button:Show()
                menu.slots[#menu.slots + 1] = button
                button.slot = #menu.slots
            end
            width = math.max(width, 28 + symbols * (MENU_SYMBOL + 10))
            y = y - MENU_BAR
        end
        for i = symbols + 1, #menu.symbols do menu.symbols[i]:Hide() end
        for i = rules + 1, #menu.rules do menu.rules[i]:Hide() end
        if #menu.slots == 0 then return end
        menu:SetSize(width, -y + 8)
        menu.count = #menu.slots
        menu:ClearAllPoints()
        if anchor then
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            local scale = UIParent:GetEffectiveScale()
            local x, cursorY = GetCursorPosition()
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cursorY / scale + 4)
        end
        menu.Mark(1)
        menu.shownAt = GetTime()
        menu:Show()
        W.Tween(menu, "fade", fade)
    end

    -- a click anywhere else closes it (global mouse event: also on frames not ours)
    local closer = CreateFrame("Frame")
    pcall(closer.RegisterEvent, closer, "GLOBAL_MOUSE_DOWN")
    closer:SetScript("OnEvent", function()
        if not menu:IsShown() or GetTime() - menu.shownAt < MENU_GUARD then return end
        local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
        while focus do
            if focus == menu then return end
            focus = focus.GetParent and focus:GetParent()
        end
        menu:Hide()
    end)

    -- keys: up/down (and Tab) move the mark, Enter does the marked line
    function menu.Step(step)
        local count = menu.count or 0
        if count == 0 then return end
        menu.Mark(((menu.marked or (step > 0 and 0 or 1)) - 1 + step) % count + 1)
    end
    function menu.Confirm()
        local slot = menu.marked and menu.slots[menu.marked]
        if not slot then return end
        menu:Hide()
        slot.run()
    end
    return menu
end
