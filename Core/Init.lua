local _, D = ...

-- The namespaces of the parts. D is the root namespace; Kit\Kit.lua and UI\Kit\Widgets.lua (first in the TOC)
-- have given it L, kit, widgets and, once the options are built, db, SetAlert and the minimap button.
--   D.search   the search's namespace   D.advice   the recommendations' namespace
-- A part reads the kit's names from the root and, for the recommendations, the engine's names as its own.

-- The global API: Options.lua fills in the rest, Bindings.xml calls it.
-- shortcut: internal exposes the whole root namespace because PylosDev (private) and the tests read it; narrow it to
-- the few names they use if another addon ever depends on it.
PylosCompass = { API = 1, internal = D }

local KIT = { L = true, db = true, kit = true, widgets = true, SetOption = true, minimapButton = true,
    SetAlert = true, GetColor = true, IsModifierHeld = true }

local function Part(fallback)
    return setmetatable({ data = D }, { __index = function(_, key)
        if KIT[key] then return D[key] end
        if key == "engine" then return D.engine end
        if fallback then return fallback(key) end
    end })
end

D.search = Part()
D.advice = Part(function(key)
    local engine = D.engine
    return engine and engine[key]
end)
