local ns = select(2, ...).search

-- Frames, drawing and animation, in the files of UI\ (loaded in this order):
--   Base.lua      shared: tooltip, opening order, building blocks, the bar's frame, hovering
--   Tooltip.lua   an entry's tooltip (beside the list, in the detail view)
--   Tabs.lua      category tabs on the bar, the close tab, subcategory tabs left of the window below the bar
--   Filters.lua   the filter window
--   List.lua      the results: rows, scroll bar, list height
--   Overview.lua  a category's page of bars (Professions)
--   Detail.lua    the detail view and its copy field
--   Menu.lua      the context menu
--   Bar.lua       the bar's contents (RenderBar), opening and closing
-- They draw ns.state; what the clicks do is in View.lua. What a file gives the others is a field of ns.ui.
-- Animations run on the driver of UI\Kit\Widgets.lua (W.Tween, W.Follow): nothing runs per frame while
-- nothing moves. Times and curves are the shared widgets' (W.Tween).

local W = ns.widgets
local ui = {}
ns.ui = ui

-- own tooltip next to the list: the GameTooltip adds the equipped-item comparison, which covered the list
local tip = CreateFrame("GameTooltip", "PylosCompassTooltip", UIParent, "GameTooltipTemplate")
tip:SetFrameStrata("TOOLTIP")
tip.noGatherInfo = true -- Pylos GatherInfo: we add its line ourselves (option)
ui.tip = tip

-- rows a list shows at once: MAX_RESULTS, more beside many subcategory tabs
-- or a tall filter window (set by Tabs.lua)
function ui.Rows() return ui.rowsShown or ns.MAX_RESULTS end

-- Opening order
-- Each step starts when the step it waits for has finished (plus a pause), so a longer one (a tall list)
-- moves the later ones back instead of overlapping them:
--   start    the bar grows (Bar.lua); the category tabs rise with it, one after another (Tabs.lua)
--   bar      the bar stands: the list folds open to its full height
--   list     the list stands (or the detail view shows): the pinned filter window slides out (Filters.lua)
--   filters  the filter window stands (or none is pinned): the close tab rises (Tabs.lua)
-- A step finishes once per opening (ui.Finished); ui.Since says how long ago, nil while it has not;
-- ui.After(step, fn): fn runs when it finishes.
local finished, after = {}, {}
function ui.Finished(step)
    if finished[step] then return end
    finished[step] = GetTime()
    if after[step] then after[step]() end
end
function ui.Since(step)
    return finished[step] and GetTime() - finished[step]
end
function ui.After(step, fn) after[step] = fn end
function ui.RestartOrder() wipe(finished) end

function ui.Fill(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

-- a thin bronze frame of four one-pixel lines: inside the frame's edge, or one pixel outside it (outside:
-- a bar's fill stays inside its frame; the other line-end offset made the fill stick out)
local BRONZE = W.BRONZE
function ui.Border(frame, layer, outside)
    local o = outside and 1 or 0
    for _, side in ipairs({
        { "TOPLEFT", -o, o, "TOPRIGHT", o, o }, { "BOTTOMLEFT", -o, -o, "BOTTOMRIGHT", o, -o },
        { "TOPLEFT", -o, o, "BOTTOMLEFT", -o, -o }, { "TOPRIGHT", o, o, "BOTTOMRIGHT", o, -o },
    }) do
        local line = ui.Fill(frame, layer, BRONZE[1], BRONZE[2], BRONZE[3], W.BRONZE_LINE)
        line:SetPoint(side[1], frame, side[1], side[2], side[3])
        line:SetPoint(side[4], frame, side[4], side[5], side[6])
        if side[1]:sub(1, 3) == side[4]:sub(1, 3) then line:SetHeight(1) else line:SetWidth(1) end
    end
end

-- the windows' background: option "backgroundAlpha" (background only, not border and text); windows
-- dress themselves when they first show (UI\Kit\Widgets.lua)
function ui.ApplyLook()
    W.SetBackground(ns.db.backgroundAlpha / 100)
end

-- Background art: a subcategory's picture behind the rows of a window (ui.SetArt, Detail.lua). The atlas
-- is cut to the window's shape, so nothing is stretched; refitted when the window's height changes.
function ui.FitArt(frame)
    local art, info = frame.art, frame.artInfo
    local width, height = frame:GetWidth() - 8, frame:GetHeight() - 8
    if not info or width <= 0 or height <= 0 then
        art:Hide()
        return
    end
    local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    -- the part of the picture shown (fractions): as much as fills the window without stretching, made
    -- smaller by the zoom, placed so the motif's centre (focus) sits in the middle where the picture allows
    local wanted, own = width / height, info.width / info.height
    local shownWidth, shownHeight = 1, 1
    if wanted > own then shownHeight = own / wanted else shownWidth = wanted / own end
    local zoom = frame.artZoom or 1
    shownWidth, shownHeight = shownWidth / zoom, shownHeight / zoom
    local Clamp = W.Clamp
    local x = Clamp(((frame.artFocusX or 0.5) - shownWidth / 2) / math.max(1 - shownWidth, 0.0001)) * (1 - shownWidth)
    local y = Clamp(((frame.artFocusY or 0.5) - shownHeight / 2) / math.max(1 - shownHeight, 0.0001)) * (1 - shownHeight)
    local spanX, spanY = right - left, bottom - top
    art:SetTexture(info.file or info.filename)
    art:SetTexCoord(left + spanX * x, left + spanX * (x + shownWidth), top + spanY * y, top + spanY * (y + shownHeight))
    art:SetAlpha(frame.artAlpha or 1)
    art:Show()
end

function ui.Art(frame)
    frame.art = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.art:SetPoint("TOPLEFT", 4, -4)
    frame.art:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.art:Hide()
    frame:HookScript("OnSizeChanged", ui.FitArt)
end

-- the windows take the mouse, so clicks on them do not reach the world behind
function ui.CatchMouse(frame)
    frame:EnableMouse(true)
end

-- The bar: its frame here, as the other windows hang from it; contents: Bar.lua

local bar = CreateFrame("Frame", "PylosCompassFrame", UIParent)
bar:SetSize(W.WIDTH, ns.BAR_HEIGHT)
bar:SetFrameStrata("FULLSCREEN_DIALOG")
bar:SetFrameLevel(10) -- room below for the window boxes
bar:Hide()
W.Panel(bar)
ui.CatchMouse(bar)
ui.bar = bar

-- Hovering: a row (or overview cell) marks itself only when the mouse really moves. Typing changes the
-- rows under a resting cursor, which marked whichever row it stood on: the cursor position when the rows
-- last changed is kept (ui.NoteCursor); a row entered with the cursor still there waits until it moves.
-- Only then something watches the cursor.
local stillX, stillY
local waiting = {} -- frame -> what hovering it does: action(frame)
local woken = {}

function ui.NoteCursor()
    stillX, stillY = GetCursorPosition()
end

local watcher = CreateFrame("Frame", nil, bar)
watcher:Hide()
watcher:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    if x == stillX and y == stillY then return end
    stillX, stillY = nil, nil
    self:Hide()
    wipe(woken)
    for frame, action in pairs(waiting) do woken[frame] = action end
    wipe(waiting)
    for frame, action in pairs(woken) do
        if frame:IsVisible() and frame:IsMouseOver() then action(frame) end
    end
end)

function ui.Hover(frame, action)
    local x, y = GetCursorPosition()
    if x ~= stillX or y ~= stillY then
        action(frame)
    else
        waiting[frame] = action
        watcher:Show()
    end
end

function ui.Unhover(frame)
    waiting[frame] = nil
end
