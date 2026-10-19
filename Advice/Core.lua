local ns = select(2, ...).advice

-- The recommendations: a window with tabs plus nudges, on the engine in Engine\.
-- Files: Core (options), Subtopics + Window (window), Push/Pushes/Toast (nudges).
-- ns is D.advice (Core\Init.lua): the kit's names (db, L, widgets) and, as a fallback, the engine's names.

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
