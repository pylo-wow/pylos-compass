local ns = select(2, ...).advice
local L = ns.L
local W = ns.widgets
local push = ns.push

-- Nudge display (Push.lua decides when and how loud).
--   quiet   minimap button glows until the window opens; the topic's tab gets a dot until viewed
--   medium  note left of the minimap; fades after MEDIUM_FOR s unless hovered (answer "ignored")
--   loud    same note at the top of the screen with a sound, until answered or its reason goes
-- A click equips the item / targets the rare (secure button, out of combat) / sets a waypoint; combat hides the note (a secure button cannot stay).

local MEDIUM_FOR = 8
local WIDTH = { [push.MEDIUM] = 320, [push.LOUD] = 380 }
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

local function TextButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.text:SetPoint("CENTER")
    button.text:SetText(label)
    button:SetSize(W.TextWidth(button.text) + 8, 16)
    button:SetScript("OnEnter", function(self) self.text:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3]) end)
    button:SetScript("OnLeave", function(self) self.text:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3]) end)
    button.text:SetTextColor(W.SUB[1], W.SUB[2], W.SUB[3])
    button:SetScript("OnClick", onClick)
    return button
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
    note.click:SetTextColor(W.GREEN[1], W.GREEN[2], W.GREEN[3])
    note.never = TextButton(note, L["Never for this"], function() Answer("never") end)
    note.never:SetPoint("BOTTOMRIGHT", -10, 8)
    note.later = TextButton(note, L["Later"], function() Answer("later") end)
    note.later:SetPoint("RIGHT", note.never, "LEFT", -6, 0)
    -- secure click area over icon and texts (not the answer buttons)
    local secure = CreateFrame("Button", nil, note, "SecureActionButtonTemplate")
    secure:SetPoint("TOPLEFT", 6, -6)
    secure:SetPoint("BOTTOMRIGHT", -6, 26)
    secure:RegisterForClicks("AnyDown", "AnyUp")
    secure:SetAttribute("useOnKeyDown", false)
    secure:SetScript("PostClick", function(_, button, down)
        if down or button ~= "LeftButton" or not current then return end
        local action = current.c.action
        if action and action.kind == "waypoint" then W.Waypoint(action.name, action.value) end
        -- a note without an action is only dismissed: that is no sign of interest for the level
        Answer(action and "clicked" or "dismissed")
    end)
    note.secure = secure
    note:SetScript("OnUpdate", function(self)
        local c = current
        if not c or c.level ~= push.MEDIUM then return end
        if self:IsMouseOver() then
            c.shownAt = GetTime()
        elseif GetTime() - c.shownAt >= MEDIUM_FOR then
            Answer("ignored")
        end
    end)
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
    local width = WIDTH[level] or WIDTH[push.MEDIUM]
    for _, line in ipairs({ note.title, note.text, note.click }) do line:SetWidth(width - ICON - 38) end
    local height = 14 + math.max(ICON, note.title:GetStringHeight() + 4 + note.text:GetStringHeight()
        + (action and (4 + note.click:GetStringHeight()) or 0)) + 34
    note:SetSize(width, height)
    note:ClearAllPoints()
    if level == push.LOUD then
        note:SetPoint("TOP", UIParent, "TOP", 0, -140)
    else
        note:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 0)
    end
    local secure = note.secure
    local kind = action and action.kind
    secure:SetAttribute("type1", (kind == "item" or kind == "macro") and kind or nil)
    secure:SetAttribute("item", kind == "item" and action.value or nil)
    secure:SetAttribute("macrotext", kind == "macro" and action.value or nil)
    note:SetAlpha(0)
    note:Show()
    W.Tween(note, "fade", { duration = W.FADE_TIME, apply = function(self, value) self:SetAlpha(value) end })
    if level == push.LOUD and ns.db.pushSound ~= false and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
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
-- Window opened (Window.lua): the glow is done. Returns the topic of the newest quiet nudge so the window opens at its tab.
function push.WindowOpened()
    local topic = push.NewestQuietTopic(openedAt)
    openedAt = time()
    push.QuietChanged()
    return topic
end
function push.QuietChanged()
    if not ns.SetAlert then return end -- core button not built yet (ADDON_LOADED)
    local fresh = false
    for _, q in pairs(push.quiet) do fresh = fresh or q.at > openedAt end
    ns.SetAlert(fresh)
    if ns.WindowDots then ns.WindowDots() end
end

-- sample nudge per level (debug window)
function push.Sample(level)
    local rule = { key = "sample", label = "Sample", level = level, sample = true }
    local c = { situation = "sample:" .. level .. ":" .. time(), title = L["Rare nearby: %s"]:format("Sample"),
        text = "A sample note at level " .. push.LEVEL_NAMES[level], icon = { icon = 134400 },
        action = { kind = "waypoint", value = 1429500500, name = "Sample" } }
    if level == push.QUIET then
        push.quiet[c.situation] = { topic = "gear", rule = "sample", at = time() }
        push.QuietChanged()
    else
        push.Toast(rule, c, level)
    end
end
