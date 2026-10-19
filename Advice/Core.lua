local addonName, ns = ...; ns = ns.advice

-- Recommendations window with tabs plus nudges, on the engine in Engine\.
-- Files: Core (options), Subtopics + Window (window), Push/Pushes/Toast (nudges).
-- ns is Compass's D.advice: Init.lua gives it the kit's names (db, L, widgets) and falls back to the engine.
local D = ns.data

local L = ns.L

-- Compass.lua builds the options page (head, minimap button) from this: defaults, load step and rows
ns.options = {
    defaults = {
        windowTab = "", -- "": first tab with suggestions
        windowSub = {},    -- topic -> subtopic key
        window = {},       -- left, top
        pushes = {},          -- per character: nudge situations and outcomes
    },
    onLoad = function(db)
        ns.push.Prune()
    end,
}
