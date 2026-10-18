local ns = select(2, ...).search
if ns.off then return end

-- Keys while the bar is open. The bar is no EditBox: a focused EditBox swallows Enter, and spells
-- can only be cast by a key binding or a click on a secure button. So a frame passing every key on
-- reads typed characters (OnChar), and override bindings take the keys: control keys click a plain
-- button, Enter and Ctrl+Enter click secure buttons, typing keys are bound to nothing (no walking,
-- quiet action bars). Override bindings are not allowed in combat, so the bar only opens out of
-- combat. The search key stays bound and closes the bar. What the keys do: View.lua.

local S = ns.state
local input = {}
ns.input = input

-- Secure buttons
-- Enter only casts or uses when the detail view's action is chosen, Ctrl+Enter always; both act on release.

local function SecureKey(name)
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    return button
end
local enter = SecureKey("PylosCompassEnter")
local quick = SecureKey("PylosCompassQuick")

enter:SetScript("PostClick", function(_, _, down)
    if not down then ns.view.Confirm() end
end)
quick:SetScript("PostClick", function(_, _, down)
    if not down then ns.view.AfterAction() end
end)

-- writes an entry's action into a secure button (out of combat only): type
-- "spell" with the spell ID, type "item" with "item:ID", or nothing
function input.ArmAction(button, entry)
    local kind = entry and entry.type
    button:SetAttribute("type", kind)
    if kind then button:SetAttribute(kind == "macro" and "macrotext" or kind, entry.value) end
end

function input.ArmEnter(entry)
    input.ArmAction(enter, entry)
end

function input.ArmQuick(entry)
    input.ArmAction(quick, ns.view.HasAction(entry) and entry or nil)
end

-- Key names as the client reports them ("." and NUMPADPLUS seen in game); a key not listed still
-- types, it only reaches the game as well.
local SWALLOW = { "SPACE", "MINUS", ".", ",", "#", "+", "<", "'", "^",
    "NUMPADPLUS", "NUMPADMINUS", "NUMPADMULTIPLY", "NUMPADDIVIDE", "NUMPADDECIMAL",
    "Ä", "Ö", "Ü", "ß" }
for byte = string.byte("A"), string.byte("Z") do SWALLOW[#SWALLOW + 1] = string.char(byte) end
for digit = 0, 9 do
    SWALLOW[#SWALLOW + 1] = tostring(digit)
    SWALLOW[#SWALLOW + 1] = "NUMPAD" .. digit
end
-- BUTTON4/BUTTON5 (mouse side buttons) did not work in game
local CONTROL = { "BACKSPACE", "ESCAPE", "UP", "DOWN", "TAB", "LEFT", "RIGHT" }

-- Held keys repeat like in Windows: after a short wait, then quickly (bindings only report down and up)
local REPEATING = { BACKSPACE = true, UP = true, DOWN = true, TAB = true }
local REPEAT_DELAY, REPEAT_RATE = 0.45, 0.04
local held, heldNext -- the held key, time of its next repeat
local repeater       -- the frame that repeats it (below), shown while a key is held

-- repeated: a repeat of the held key, not a press of its own
local function Press(key, repeated)
    local view = ns.view
    local shift = IsShiftKeyDown()
    if ns.ui.MenuShown() then
        if key == "DOWN" or (key == "TAB" and not shift) then return ns.ui.MenuStep(1) end
        if key == "UP" or (key == "TAB" and shift) then return ns.ui.MenuStep(-1) end
    end
    if key == "ESCAPE" then
        -- without the keyboard (a click outside) it closes at once
        if S.unfocused then return ns.Close() end
        view.Escape()
    elseif key == "CTRL-TAB" then
        held = nil
        view.CycleScope(shift and -1 or 1)
    elseif key == "TAB" then
        -- an empty bar: the categories; else the results (also a category or filter result)
        if S.query == "" and not S.detail and not S.linked then
            held = nil
            view.CycleScope(shift and -1 or 1)
        else
            view.Step(shift and -1 or 1)
        end
    elseif key == "DOWN" then
        view.Step(1)
    elseif key == "UP" then
        view.Step(-1)
    elseif key == "RIGHT" then
        view.Deeper()
    elseif key == "LEFT" then
        -- with text typed Left does nothing (Backspace erases)
        if S.query ~= "" and not S.detail and not S.linked then return end
        view.Back()
    elseif key == "BACKSPACE" then
        if not view.Erase() then
            -- empty bar: one step back, only on a press of its own (a held key would run back to the start)
            held = nil
            if not repeated then view.Back() end
        end
    end
end

-- plain button the control keys click; the binding hands over the key name
-- as the mouse button. Typing keys click it too and are ignored.
local keys = CreateFrame("Button", "PylosCompassKeys", UIParent)
keys:RegisterForClicks("AnyDown", "AnyUp")
keys:SetScript("OnClick", function(_, key, down)
    if not down then
        if key == held then held = nil end
        return
    end
    Press(key)
    if REPEATING[key] then
        held, heldNext = key, GetTime() + REPEAT_DELAY
        repeater:Show()
    end
end)

-- repeats the held key: shown only while a key is held (on the key button it ran every frame);
-- a hidden bar counts as let go
repeater = CreateFrame("Frame", nil, ns.ui.bar)
repeater:Hide()
repeater:SetScript("OnHide", function() held = nil end)
repeater:SetScript("OnUpdate", function(self)
    -- let go (or the release never arrived: IsKeyDown, if the client has it)
    if not held or (IsKeyDown and not IsKeyDown(held)) then
        self:Hide()
        return
    end
    local now = GetTime()
    while held and now >= heldNext do
        Press(held, true)
        heldNext = heldNext + REPEAT_RATE
    end
end)

-- Passing keys on must be enabled before the key comes: too late inside OnKeyDown (tried in game).
-- EnableKeyboard and SetPropagateKeyboardInput only here at load, never in combat; the frame
-- only listens while the bar is shown.
local typing = CreateFrame("Frame", nil, ns.ui.bar)
typing:EnableKeyboard(true)
typing:SetPropagateKeyboardInput(true)
typing:SetScript("OnChar", function(_, text)
    if S.closingAt or S.unfocused or IsAltKeyDown() or IsControlKeyDown() or text:byte() < 32 then return end
    if ns.ui.copy:HasFocus() then return end
    if input.Waiting(text) then return end -- a key still held for the game (walking)
    -- detail view: Space opens the entry's menu; while a menu is open keys do not type
    if ns.ui.MenuShown() then return end
    if S.detail and text == " " then return ns.ui.ShowMenu(S.detail, true, true) end
    ns.view.Type(text)
end)

-- binds a key and its Shift variant, so capitals type too; unknown key names are skipped
local function Bind(key, button, mouseButton)
    for _, combo in ipairs({ key, "SHIFT-" .. key }) do
        pcall(SetOverrideBindingClick, ns.ui.bar, true, combo, button, mouseButton)
    end
end

-- Keys held when the bar opens (walking, turning) stay the game's until let go: bound at once,
-- their release went to the search and the character walked on. Then the search takes them.
local waiting = {} -- key -> mouse button name for PylosCompassKeys
-- watches held keys; shown only while one waits
local free = CreateFrame("Frame", nil, ns.ui.bar)
free:Hide()
local function BindWhenFree(key)
    if IsKeyDown and IsKeyDown(key) then
        waiting[key] = key
        free:Show()
    else
        Bind(key, "PylosCompassKeys", key)
    end
end
free:SetScript("OnUpdate", function(self)
    for key in pairs(waiting) do
        if not IsKeyDown(key) then
            waiting[key] = nil
            if not S.unfocused and not InCombatLockdown() then Bind(key, "PylosCompassKeys", key) end
        end
    end
    if next(waiting) == nil then self:Hide() end
end)

function input.Waiting(text)
    return waiting[text == " " and "SPACE" or text:upper()] ~= nil
end

function input.BindKeys()
    wipe(waiting)
    for _, key in ipairs(SWALLOW) do BindWhenFree(key) end
    for _, key in ipairs(CONTROL) do BindWhenFree(key) end
    Bind("ENTER", "PylosCompassEnter", "LeftButton")
    Bind("NUMPADENTER", "PylosCompassEnter", "LeftButton")
    pcall(SetOverrideBindingClick, ns.ui.bar, true, "CTRL-ENTER", "PylosCompassQuick", "LeftButton")
    pcall(SetOverrideBindingClick, ns.ui.bar, true, "CTRL-NUMPADENTER", "PylosCompassQuick", "LeftButton")
    -- next/previous category (the key name arrives as the mouse button; Shift is read on press)
    pcall(SetOverrideBindingClick, ns.ui.bar, true, "CTRL-TAB", "PylosCompassKeys", "CTRL-TAB")
    pcall(SetOverrideBindingClick, ns.ui.bar, true, "CTRL-SHIFT-TAB", "PylosCompassKeys", "CTRL-TAB")
end

function input.ClearKeys()
    wipe(waiting)
    if not InCombatLockdown() then ClearOverrideBindings(ns.ui.bar) end
end

-- Without the keyboard (click outside, option "clickOutside"): keys go back to the game, only Escape
-- still closes; a click into the bar or the search key takes the keyboard back
function input.Unfocus()
    if S.unfocused or InCombatLockdown() then return end
    input.ClearKeys()
    pcall(SetOverrideBindingClick, ns.ui.bar, true, "ESCAPE", "PylosCompassKeys", "ESCAPE")
    S.unfocused = true
    ns.ui.HideMenu()
    ns.ui.RenderBar()
end
function input.Focus()
    if not S.unfocused or InCombatLockdown() then return end
    input.ClearKeys()
    input.BindKeys()
    S.unfocused = false
    ns.ui.RenderBar()
end
