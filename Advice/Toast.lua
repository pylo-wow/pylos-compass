local ns = select(2, ...).advice
local L = ns.L
local W = ns.widgets
local push = ns.push

-- Nudge display (Push.lua decides when and how loud).
--   quiet   minimap button glows until the window opens; the topic's tab gets a dot until viewed
--   note    message left of the minimap; fades after MEDIUM_FOR s unless hovered (answer "ignored")
--   alert   the same message, with a sound unless switched off
--   quiet, asked for: a click on the glowing minimap button shows the newest quiet nudge as the same message (ASKED_FOR s)
-- A click equips the item / targets the rare (secure button, out of combat) / sets a waypoint; combat hides the note
-- (a secure button cannot stay).

local MEDIUM_FOR = 8
local ASKED_FOR = 20 -- a message asked for with a click on the glowing button stays longer
local WIDTH = 320
local ICON = 36

local note -- built on first use
local current -- { rule, c, level, shownAt }

local CLICK = { item = L["Click: put it on"], macro = L["Click: target it"], waypoint = L["Click: set a waypoint"] }

local function Hide(instantly)
    if not note then return end
    current = nil
    if instantly then
        W.Tween(note, "fade", nil)
        note:Hide()
    else
        W.Tween(note, "fade", { duration = W.CLOSE_TIME, apply = function(self, value) self:SetAlpha(1 - value) end,
            done = function(self) self:Hide() end })
    end
end

local function Answer(answer)
    local c = current
    if not c then return end
    Hide(answer == "interrupted")
    push.Answer(c.rule, c.c, c.level, answer)
end

-- Small icon button with a tooltip; setup(texture) gives the icon its picture.
local ICON_BUTTON = 18
local function IconButton(parent, text, setup, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ICON_BUTTON, ICON_BUTTON)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    setup(button.icon)
    button.icon:SetAlpha(0.8)
    button:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text())
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", onClick)
    return button
end

-- the three symbols, from the game's atlas if it has it, else from its files
local function CheckSymbol(texture)
    if not W.Atlas(texture, "common-icon-checkmark") then
        texture:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
end
local function SleepSymbol(texture) -- the "Zzz" of the rested state on the player frame's sheet
    texture:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    texture:SetTexCoord(0, 0.5, 0, 0.421875)
end
local function CrossSymbol(texture)
    if not W.Atlas(texture, "common-icon-redx") then texture:SetTexture("Interface\\Buttons\\UI-StopButton") end
end

-- what a click on the message does: its action, or it only dismisses it
local function Clicked(_, button, down)
    if down or button ~= "LeftButton" or not current then return end
    local action = current.c.action
    if action and action.kind == "waypoint" then W.Waypoint(action.name, action.value) end
    -- a note without an action is only dismissed: that is no sign of interest for the level
    Answer(action and "clicked" or "dismissed")
end

-- a secure button (equips, targets): the action of the message in its attributes
local function SecureButton(parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PostClick", Clicked)
    return button
end
local function Arm(button, action)
    local kind = action and action.kind
    button:SetAttribute("type1", (kind == "item" or kind == "macro") and kind or nil)
    button:SetAttribute("item", kind == "item" and action.value or nil)
    button:SetAttribute("macrotext", kind == "macro" and action.value or nil)
end
local function Build()
    note = CreateFrame("Frame", "PylosCompassNudge", UIParent)
    note:SetFrameStrata("DIALOG")
    note:SetFrameLevel(20)
    note:SetClampedToScreen(true)
    note:Hide()
    W.Panel(note)
    note.icon = W.Icon(note, ICON)
    note.icon:SetPoint("TOPLEFT", 14, -14)
    note.title = note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    note.title:SetPoint("TOPLEFT", note.icon, "TOPRIGHT", 10, 0)
    note.title:SetJustifyH("LEFT")
    note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note.text:SetPoint("TOPLEFT", note.title, "BOTTOMLEFT", 0, -4)
    note.text:SetJustifyH("LEFT")
    note.click = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note.click:SetPoint("TOPLEFT", note.text, "BOTTOMLEFT", 0, -4)
    note.click:SetJustifyH("LEFT") -- flush with the text above (a font string is centered otherwise)
    note.click:SetTextColor(W.GREEN[1], W.GREEN[2], W.GREEN[3])
    -- at the bottom, right to left: never for this (the red cross), later (the sleeper), useful (the check)
    note.never = IconButton(note, function() return L["Never for this"] end, CrossSymbol, function() Answer("never") end)
    note.never:SetPoint("BOTTOMRIGHT", -10, 8)
    note.later = IconButton(note, function() return L["Later"] end, SleepSymbol, function() Answer("later") end)
    note.later:SetPoint("RIGHT", note.never, "LEFT", -8, 0)
    -- the check: "more like this" (the message itself, when clicked, does what it says)
    note.accept = IconButton(note, function() return L["Useful: more like this"] end, CheckSymbol,
        function() Answer("liked") end)
    note.accept:SetPoint("RIGHT", note.later, "LEFT", -8, 0)
    -- the game's own close cross on top: closes the message (answer: dismissed)
    note.close = CreateFrame("Button", nil, note, "UIPanelCloseButton")
    note.close:SetPoint("TOPRIGHT", 2, 2)
    note.close:SetScale(0.8)
    note.close:SetFrameLevel(note:GetFrameLevel() + 5) -- above the secure area
    note.close:SetScript("OnClick", function() Answer("dismissed") end)
    -- secure click area over icon and texts (not the buttons)
    local secure = SecureButton(note)
    secure:SetPoint("TOPLEFT", 6, -6)
    secure:SetPoint("BOTTOMRIGHT", -6, 26)
    secure:SetFrameLevel(note:GetFrameLevel() + 1)
    note.secure = secure
    note:SetScript("OnUpdate", function(self)
        local c = current
        if not c then return end
        if self:IsMouseOver() then
            c.shownAt = GetTime()
        elseif c.level == push.QUIET then
            if GetTime() - c.shownAt >= ASKED_FOR then Answer("faded") end
        elseif GetTime() - c.shownAt >= MEDIUM_FOR then
            Answer("ignored")
        end
    end)
end

-- Left of the minimap, level with its top edge. With no room there (a minimap at the left or top edge: the screen
-- would push the message over the minimap) it stands at a fixed place at the top of the screen.
local MINIMAP_GAP, FIXED_TOP = 14, -140
local function Place(height)
    local left, top = Minimap:GetLeft(), Minimap:GetTop()
    local toScreen = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local size = note:GetEffectiveScale() / UIParent:GetEffectiveScale() -- (the note's scale is set)
    note:ClearAllPoints()
    if left and top and ns.FitsScreen(left * toScreen - MINIMAP_GAP * size, top * toScreen, WIDTH * size, height * size) then
        note:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -MINIMAP_GAP, 0)
    else
        note:SetPoint("TOP", UIParent, "TOP", 0, FIXED_TOP / size)
    end
end

function push.Toast(rule, c, level)
    if not note then Build() end
    if current then push.Answer(current.rule, current.c, current.level, "replaced") end
    current = { rule = rule, c = c, level = level, shownAt = GetTime() }
    W.ShowIcon(note.icon, c.icon or c.entry or {}, nil, 134400)
    note.title:SetText(c.title or "")
    note.text:SetText(c.text or "")
    local action = c.action
    note.click:SetText(action and CLICK[action.kind] or "")
    for _, line in ipairs({ note.title, note.text, note.click }) do line:SetWidth(WIDTH - ICON - 60) end
    local height = 14 + math.max(ICON, note.title:GetStringHeight() + 4 + note.text:GetStringHeight()
        + (action and (4 + note.click:GetStringHeight()) or 0)) + 34
    note:SetScale((ns.db.adviceScale or 100) / 100)
    note:SetSize(WIDTH, height)
    Place(height)
    Arm(note.secure, action)
    note:SetAlpha(0)
    note:Show()
    W.Tween(note, "fade", { duration = W.FADE_TIME, apply = function(self, value) self:SetAlpha(value) end })
    if level == push.ALERT and ns.db.pushSound ~= false and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- the size of the windows (option "adviceScale", percent) for a message on screen
function push.ApplyScale()
    if note and not InCombatLockdown() then note:SetScale((ns.db.adviceScale or 100) / 100) end
end

-- a note at this level or louder is on screen: the new one waits
function push.Busy(level)
    return current ~= nil and current.level >= level
end
-- reason went away (Push.lua Watch)
function push.Gone(situation)
    if current and current.c.situation == situation then Hide() end
end
function push.Interrupt()
    if current then Answer("interrupted") end
end

-- Quiet: minimap button glow (ns.SetAlert)
local openedAt = 0
-- Window opened (Window.lua): the glow is done. Returns the topic of the newest quiet nudge so the window opens at
-- its tab.
function push.WindowOpened()
    local topic = push.NewestQuietTopic(openedAt)
    openedAt = time()
    push.QuietChanged()
    return topic
end
function push.QuietChanged()
    if not ns.SetAlert then return end -- core button not built yet (ADDON_LOADED)
    local fresh = false
    for _, q in pairs(push.quiet) do fresh = fresh or (q.at > openedAt and not q.seen) end
    ns.SetAlert(fresh)
    if ns.WindowDots then ns.WindowDots() end
end

-- A test nudge for the options page and the developer tools. With a rule and its candidate (Pushes.lua gives a random
-- kind with real data) it is that nudge as it would show: quiet glows for SAMPLE_QUIET_FOR s (a click on the button
-- shows the message), a note and an alert show the message (the alert with the sound), with the same buttons. It is
-- marked as a sample, so nothing is remembered of what you do with it (Push.lua Answer). Without them: a plain message.
local SAMPLE_QUIET_FOR = 10
function push.Sample(level, real, c)
    if InCombatLockdown() then
        print(("|cffffd100Pylos Compass|r: %s"):format(L["A test hint cannot show in combat."]))
        return
    end
    local rule = setmetatable({ sample = true },
        { __index = real or { key = "sample", label = "Sample", level = level, topic = "gear" } })
    c = c or { title = L["Test hint"], icon = { icon = 134400 },
        text = level == push.ALERT and L["A short message by the minimap, with a sound."]
            or L["A short message by the minimap."] }
    c.situation = ("sample:%d:%d:%d"):format(level, time(), math.random(100000))
    if level == push.QUIET then
        local situation = c.situation
        push.quiet[situation] = { topic = rule.topic or "gear", rule = rule.key, ruleObj = rule, at = time(),
            entry = c.entry, c = c }
        push.QuietChanged()
        C_Timer.After(SAMPLE_QUIET_FOR, function()
            if push.quiet[situation] then
                push.quiet[situation] = nil
                push.QuietChanged()
            end
        end)
    else
        push.Toast(rule, c, level)
    end
end

-- A click on the glowing minimap button: the newest quiet nudge you have not seen is shown as a message (the same as
-- a note, with the same buttons), so you know what it is and can say whether it was useful. Returns false if there
-- is none to show (nothing glows, or combat: the message has a secure button).
function push.ShowQuiet()
    if InCombatLockdown() then return false end
    local newest, situation
    for key, q in pairs(push.quiet) do
        if q.c and q.at > openedAt and not q.seen and (not newest or q.at > newest.at) then newest, situation = q, key end
    end
    if not newest then return false end
    local rule = newest.ruleObj
    if not rule then return false end
    newest.seen = true
    push.QuietChanged()
    push.Toast(rule, newest.c, push.QUIET)
    return situation ~= nil
end

-- The left click of the minimap button: a quiet nudge to show first, else the recommendations window
function ns.LeftClick()
    if not push.ShowQuiet() then ns.ToggleWindow() end
end

-- a quiet nudge glows that has not been looked at (the minimap button's tooltip says so)
function push.Glowing()
    for _, q in pairs(push.quiet) do
        if q.c and q.at > openedAt and not q.seen then return true end
    end
    return false
end
