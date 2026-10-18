local _, D = ...
if D.off then return end

-- World events (Data\Events.lua): which NPCs and quests only exist during one, and whether it runs now.
--   D.EventOf(entry)    event key of an NPC or quest, nil if none
--   D.EventName(key)    name ("Feast of Winter Veil")
--   D.EventActive(key)  the calendar lists it today, or one of its NPCs was seen within SEEN_FOR
--                       (covers events the calendar lacks, e.g. Scourge Invasion, or an empty calendar)
--   D.EventAway(entry)  event name if the entry belongs to an event that is not running, else nil
-- State "events": calendar re-read, or an event's NPC seen for the first time.
-- PylosCompassWorldDB.eventsSeen[key] = time() an NPC of it was last seen.
-- Calendar: today's C_Calendar day events of type "HOLIDAY", matched by Holidays ID or title
-- (unchecked whether Forever's server fills in holidays).

local SEEN_FOR = 2 * 24 * 3600 -- seconds an event counts as running after one of its NPCs was seen

local today = {} -- event key -> true: the calendar lists it today

function D.EventOf(entry)
    if entry.npcID then return D.npcEvents and D.npcEvents[entry.npcID] end
    if entry.questID then return D.questEvents and D.questEvents[entry.questID] end
    return nil
end

function D.EventName(key)
    local event = D.events and D.events[key]
    return event and event[1]
end

function D.EventActive(key)
    if today[key] then return true end
    local seen = D.world and D.world.eventsSeen and D.world.eventsSeen[key]
    return seen ~= nil and time() - seen < SEEN_FOR
end

function D.EventAway(entry)
    local key = D.EventOf(entry)
    if not key or D.EventActive(key) then return nil end
    return D.EventName(key)
end

-- An event's NPC was met (called from World\LearnNPCs.lua)
function D.EventSeen(npcID)
    local key = D.npcEvents and D.npcEvents[npcID]
    if not (key and D.world) then return end
    local seen = D.world.eventsSeen
    local first = not D.EventActive(key)
    seen[key] = time()
    if first then D.BumpState("events") end
end

local byHoliday, byName, madeFor -- holiday ID / lower-case name -> event key; built for that D.events
local function Read()
    -- not while the calendar window is open: setting its month would turn the page
    if CalendarFrame and CalendarFrame:IsShown() then return end
    if madeFor ~= D.events then
        byHoliday, byName, madeFor = {}, {}, D.events
        for key, event in pairs(D.events or {}) do
            byName[event[1]:lower()] = key
            for i = 2, #event do byHoliday[event[i]] = key end
        end
    end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if not now then return end
    -- Set the month only if another is shown: setting it fires CALENDAR_UPDATE_EVENT_LIST at
    -- once, which re-reads and sets it again (C stack overflow, seen in game)
    local shown = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
    if C_Calendar.SetAbsMonth and not (shown and shown.month == now.month and shown.year == now.year) then
        pcall(C_Calendar.SetAbsMonth, now.month, now.year)
    end
    local found = {}
    local ok, count = pcall(C_Calendar.GetNumDayEvents, 0, now.monthDay)
    for i = 1, ok and count or 0 do
        local got, event = pcall(C_Calendar.GetDayEvent, 0, now.monthDay, i)
        if got and type(event) == "table" and event.calendarType == "HOLIDAY" then
            local key = byHoliday[event.eventID] or (type(event.title) == "string" and byName[event.title:lower()])
            if key then found[key] = true end
        end
    end
    local changed = false
    for key in pairs(found) do changed = changed or not today[key] end
    for key in pairs(today) do changed = changed or not found[key] end
    today = found
    if changed then D.BumpState("events") end
end
-- Not re-entrant: Read may fire the calendar event again
local reading = false
local function ReadCalendar()
    if reading or not (C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent and C_DateAndTime
            and C_DateAndTime.GetCurrentCalendarTime) then return end
    reading = true
    local ok, problem = pcall(Read)
    reading = false
    if not ok then error(problem, 0) end
end

D.OnLoaded(function() D.world.eventsSeen = D.world.eventsSeen or {} end)
D.On("PLAYER_ENTERING_WORLD", function()
    if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    ReadCalendar()
end)
-- Calendar data arrives after OpenCalendar; D.On skips events the client does not know
D.On("CALENDAR_UPDATE_EVENT_LIST", ReadCalendar)
