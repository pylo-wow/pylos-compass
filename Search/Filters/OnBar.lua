local ns = select(2, ...).search
local L = ns.L
local D = ns.data

-- Not on bars: your spells that no action button holds (also not through a macro), passives left out;
-- by name, so a lower rank on a bar counts too. Only in Spells. An open list follows when a button changes.

local spellsOnBar, itemsOnBar = {}, {} -- spell name -> action slot, item ID -> action slot (the first)
local dirty = true

-- The binding command of an action slot, as the game's bars have it: the
-- main bar 1-12 and its pages 13-24 and stances or forms 73-120 (the same
-- keys), right 25-36, left 37-48, bottom right 49-60, bottom left 61-72,
-- bars 5-7 145-180; nil for the rest
local BARS = { [3] = "MULTIACTIONBAR3BUTTON", [4] = "MULTIACTIONBAR4BUTTON", [5] = "MULTIACTIONBAR2BUTTON",
    [6] = "MULTIACTIONBAR1BUTTON", [13] = "MULTIACTIONBAR5BUTTON", [14] = "MULTIACTIONBAR6BUTTON",
    [15] = "MULTIACTIONBAR7BUTTON" }
local function Command(slot)
    local bar, button = math.floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1
    if bar <= 2 or (bar >= 7 and bar <= 10) then return "ACTIONBUTTON" .. button end
    return BARS[bar] and BARS[bar] .. button
end

local function HasKey(slot)
    local command = Command(slot)
    return command ~= nil and GetBindingKey(command) ~= nil
end

local function Better(old, new)
    return old == nil or (not HasKey(old) and HasKey(new))
end


local function Scan()
    wipe(spellsOnBar)
    wipe(itemsOnBar)
    for slot = 1, 180 do
        local kind, id, sub = GetActionInfo(slot)
        if kind == "macro" and id and sub == "spell" then
            kind = "spell" -- the client names the spell a macro button shows (id is the spell ID then)
        end
        if kind == "spell" and id then
            local name = C_Spell.GetSpellName(id)
            if name and Better(spellsOnBar[name], slot) then spellsOnBar[name] = slot end
        elseif kind == "item" and id and Better(itemsOnBar[id], slot) then
            itemsOnBar[id] = slot
        end
    end
    dirty = false
end


-- Where an entry lies on the action bars: false if on none; else the key of its button, shortened as on
-- the bar ("s-X"), or "" if the button has no key
function ns.ActionKey(entry)
    if dirty then Scan() end
    local slot
    if entry.itemID then
        slot = itemsOnBar[entry.itemID]
    elseif entry.spellID and not entry.hidden then
        slot = spellsOnBar[entry.name]
    end
    if not slot then return false end
    local command = Command(slot)
    local key = command and GetBindingKey(command)
    if not key then return "" end
    local ok, text = pcall(GetBindingText, key, true)
    return ok and text or key
end

local filter = ns.RegisterFilter({
    key = "notOnBar",
    name = L["Not on bars"],
    description = L["Your spells that no action button holds."],
    words = "not on bar action bar missing",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    sources = { "spells" },
    prepare = function()
        ns.rank.Prepare()
        if dirty then Scan() end
    end,
    test = function(entry)
        if entry.hidden or not entry.spellID or D.SpellPassive(entry.spellID) then return false end
        return not spellsOnBar[entry.name]
    end,
    -- only your spells can pass (the filter's pool is only read, never changed)
    pool = function() return D.Entries("spells") end,
})

-- a changed button: read again; an open list with this filter follows
local pending
local function Changed()
    dirty = true
    -- closed: read again when asked (no timer or closure per change while playing)
    if pending or not ns.ui.bar:IsShown() then return end
    pending = true
    C_Timer.After(0, function() -- several buttons change at once: once
        pending = false
        local S = ns.state
        if not ns.ui.bar:IsShown() or S.detail or S.linked or S.closingAt then return end
        for _, f in ipairs(S.filters) do
            if f == filter then return ns.view.Refresh({ marked = S.marked, top = S.top }) end
        end
        -- the rows' hotkeys follow
        if ns.ui.list:IsShown() then ns.ui.RenderRows() end
    end)
end
D.On("ACTIONBAR_SLOT_CHANGED", Changed)
D.On("UPDATE_MACROS", Changed)
