local ns = select(2, ...).advice

-- The recommendations: a window with tabs plus nudges, on the engine in Engine\.
-- Files: Core (options), Subtopics + Window (window), Push/Pushes/Toast (nudges).
-- ns is D.advice (Core\Init.lua): the kit's names (db, L, widgets) and, as a fallback, the engine's names.

-- Does a box fit on the screen? Its right and top edge, width and height in the screen's units (UIParent's), and what
-- hangs beyond it (to its left, above it: tabs). Nil edges (a frame not placed yet) do not fit. The window and the
-- message use it to see whether the minimap leaves room beside it (Window.lua, Toast.lua).
function ns.FitsScreen(right, top, width, height, left, above)
    return right ~= nil and top ~= nil
        and right <= UIParent:GetWidth() and right - width - (left or 0) >= 0
        and top + (above or 0) <= UIParent:GetHeight() and top - height >= 0
end

-- Core\Options.lua builds the options page (head, minimap button) from this: defaults, load step and rows
ns.options = {
    defaults = {
        windowTab = "",    -- "": first tab with suggestions
        windowSub = {},    -- topic -> subtopic key
        window = {},       -- left, top
        pushes = {},       -- per character: nudge situations and outcomes
    },
    onLoad = function()
        ns.push.Prune()
    end,
}

-- rows put in order by Core\Options.lua: nudges and rules (Pushes.lua), reset (here)
local L = ns.L
StaticPopupDialogs["PYLOSCOMPASS_RESET_LEARNING"] = {
    text = L["Reset what the recommendations learned? It forgets what you did and bought, which suggestions you " ..
        "followed and which it passed over. \"Don't suggest\" and what the search learned stay."],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.memory.ForgetDone()
        ns.learning.Forget("do")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
ns.rows = { reset = { type = "button", label = L["Learned by the recommendations"], text = L["Reset"],
    tooltip = L["The recommendations forget what you did and bought and how you answered their suggestions. " ..
        "\"Don't suggest\" and what the search learned stay."],
    func = function() StaticPopup_Show("PYLOSCOMPASS_RESET_LEARNING") end } }
