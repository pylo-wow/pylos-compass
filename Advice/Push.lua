local ns = select(2, ...).advice
local D = ns.data

-- Nudges: unprompted alerts with a rule set of their own (Pushes.lua), on the same facts as the window (reasons,
-- reach, memory). A wrong nudge costs more trust than a right one earns. Every candidate passes a chain of gates:
--   big (large gain), missable (now much cheaper than later), sure (hard facts only, no unchecked 1.12 data),
--   new (not nudged for this situation, not just done, not "Don't suggest"),
--   moment (a pause: after combat/loot/landing, new zone, resting, loading screen; never in combat, on a flight,
--   in an instance group),
--   budget (a note at most every NOTE_EVERY; a rule may own its budget)
-- Levels (Toast.lua): 1 quiet (button glow, tab dot), 2 note (short message by the minimap, at a moment), 3 alert (the
-- same message with a sound, shown at once unless in a fight or on a flight). Options: per rule off, quiet, note or alert
-- (its default is the rule's level); a candidate may only lower it (bags: quiet while the bags are not yet full). One
-- lower when 2 of the last 3 were ignored/"Later"; quiet over budget. "Never for this" switches the rule off.
-- While push.trace is set (developer tools, tests), every decision, near miss (one gate failed) and outcome goes to
-- ns.Log (a no-op unless something replaces it) and to push.history.
--   ns.RegisterPush(rule): rule = { key, label, level, topic (tab for the dot, or nil), states (State names to
--   re-evaluate on), ownBudget, holdFor (seconds a candidate must have been there before it nudges), resolved()
--   (true when what it nudged about is over: the next time nudges again), candidates(add) }
--   add(c): c = { situation (identity: nudges once per AGAIN seconds), entry, title, text, icon, level, again, anyway,
--   action = { kind = "item" | "macro" | "waypoint", value, name }, big/missable/sure = { ok, words } }

local push = {}
ns.push = push

local QUIET, MEDIUM, ALERT = 1, 2, 3 -- MEDIUM is the note
push.QUIET, push.MEDIUM, push.ALERT = QUIET, MEDIUM, ALERT
local LEVEL_NAMES = { "quiet", "note", "alert" }
push.LEVEL_NAMES = LEVEL_NAMES
local NOTE_EVERY = 15 * 60
local AGAIN = 24 * 3600     -- seconds before the same situation may nudge again
local LATER = 10 * 60       -- seconds "Later" holds
local FOLLOW = 30 * 60      -- seconds a shown nudge waits to be followed
local MOMENT = 30           -- seconds a pause lasts after its event
local JUST_DONE = 30 * 60   -- an entry acted on within this is not new
local HISTORY = 80          -- decisions kept in push.history
local MAX_SESSION = 500     -- entries in pushedAt / nearLogged before they restart

local rules, byKey = {}, {}
push.rules = rules
local pushedAt = {}   -- situation -> time() nudged (also saved per character)
local laterUntil = {} -- situation -> time() before which "Later" holds
local nearLogged = {} -- situation -> true once a near miss is logged
local sizes = {}
-- the two session caches stay bounded; pushedAt is only a cache of the saved times, a restart costs nothing
local function Put(t, key, value)
    if t[key] == nil then
        sizes[t] = (sizes[t] or 0) + 1
        if sizes[t] > MAX_SESSION then wipe(t); sizes[t] = 1 end
    end
    t[key] = value
end
local waiting = {}    -- situation -> { c, rule, level }: waits for a moment
local quiet = {}      -- situation -> { topic, rule key, at }
push.quiet = quiet    -- shared with Toast.lua; do not replace
local shown = {}      -- nudges shown, watched for being followed
local lastAt = { [MEDIUM] = 0, [ALERT] = 0 }
push.history = {}     -- the latest decisions, newest first; filled only while push.trace is set (dev tools, tests)

function ns.RegisterPush(rule)
    rules[#rules + 1] = rule
    byKey[rule.key] = rule
end

-- The level the user set for a rule (options "nudge_<rule>": off, quiet, note, alert); not set: the rule's own level
local STYLES = { off = 0, quiet = QUIET, note = MEDIUM, alert = ALERT }
function push.Style(rule)
    local choice = ns.db and ns.db["nudge_" .. rule.key]
    return STYLES[choice] or rule.level
end

local function Enabled(rule)
    return ns.db and ns.db.push ~= false and push.Style(rule) > 0
end

-- Log and history (only while push.trace is set)

local function Gates(c, moment)
    local parts = {}
    for _, gate in ipairs({ "big", "missable", "sure" }) do
        local g = c[gate] or { false, "?" }
        parts[#parts + 1] = ("%s=%s %s"):format(gate, tostring(g[2] or ""), g[1] and "ok" or "NO")
    end
    if c.new ~= nil then parts[#parts + 1] = ("new=%s %s"):format(c.newWords or "", c.new and "ok" or "NO") end
    if moment ~= nil then parts[#parts + 1] = "moment=" .. (moment and "ok" or "wait") end
    return table.concat(parts, " ")
end

local function Note(outcome, rule, c, level, moment, extra)
    if not push.trace then return end
    local id = c and c.entry and D.EntryID(c.entry) or "-"
    local gates = c and Gates(c, moment) or ""
    ns.Log("push", outcome, rule.key, id, level and LEVEL_NAMES[level] or "-", gates,
        c and c.situation or "-", extra or "")
    table.insert(push.history, 1, { at = time(), outcome = outcome, rule = rule.key,
        name = c and (c.entry and c.entry.name or c.title) or "", level = level, gates = gates, extra = extra })
    push.history[HISTORY + 1] = nil
end

-- Saved per character: situations nudged (time) and how receptive you are to each rule (mood)
local function Saved()
    local db = ns.db
    if not db then return nil end
    local key = ns.Character()
    if not key then return nil end
    local saved = db.pushes[key] or {}
    db.pushes[key] = saved
    saved.at = saved.at or {}
    saved.mood = saved.mood or {}
    return saved
end

-- How the nudges adapt without asking. Every rule has a mood per character: a score that sinks a little when its
-- messages are ignored or snoozed again and again, and rises when you act on them (or say a message was useful).
-- It fades with time (half-life MOOD_HALF_LIFE), so nothing is held against you for long. A low score makes the rule
-- one or two levels quieter, never below the glow and never above what you set. What you did anyway shortly after
-- a message you waved away takes the penalty back (Watch). Learning off: the score does not change.
--   mood[rule] = { score, time it was last brought to now, steps (levels lower) }
local MOOD_HALF_LIFE = 3 * 24 * 3600
local SCORE_MIN, SCORE_MAX = -3.5, 1 -- bounds: recovery stays short, credit does not shield for long
local STEP_DOWN = { -1, -2.5 }        -- at or below: one, two levels lower
local STEP_UP = { -0.5, -1.75 }       -- above: back one step (the gap keeps it from flickering)
local WEIGHT = { ignored = -0.25, dismissed = 0, clicked = 1, liked = 1.5, followed = 1, forgiven = 0.5 }
local SNOOZE = { -0.05, -0.3, -0.5 }  -- the first, second, third and later "Later" for one situation
local TIRED = { ignored = 1, later = 0.6, dismissed = 0.5 } -- this session's fatigue (below)
local TIRED_HALF_LIFE, TIRED_AT = 30 * 60, 1.5 -- two in a row within half an hour

local function Mood(ruleKey)
    local saved = Saved()
    if not saved then return nil end
    local record = saved.mood[ruleKey]
    local now = time()
    if not record then
        record = { 0, now, 0 }
        saved.mood[ruleKey] = record
    end
    record[1], record[2] = D.Decay(record[1], now - record[2], MOOD_HALF_LIFE), now
    return record
end

-- levels lower for a rule now (0, 1 or 2)
function push.Steps(rule)
    local record = Mood(rule.key)
    if not record then return 0 end
    local score, steps = record[1], record[3]
    if steps < 2 and score <= STEP_DOWN[2] then
        steps = 2
    elseif steps < 1 and score <= STEP_DOWN[1] then
        steps = 1
    end
    if steps == 2 and score > STEP_UP[2] then steps = 1 end
    if steps == 1 and score > STEP_UP[1] then steps = 0 end
    record[3] = steps
    return steps
end

-- the score now (developer tools, tests)
function push.Score(rule)
    local record = Mood(rule.key)
    return record and record[1] or 0
end

local function Credit(rule, weight)
    if rule.sample or not D.Learns() then return end
    local record = Mood(rule.key)
    if not record then return end
    record[1] = math.max(SCORE_MIN, math.min(SCORE_MAX, record[1] + weight))
    push.Steps(rule)
end

-- Fatigue: messages waved away in a row, across the rules, make the next one quieter for a while (the session only,
-- nothing is kept); acting on a message, or calling it useful, ends it. A rule with a budget of its own is left out.
local tired, tiredAt = 0, 0
local function Tire(amount)
    local now = GetTime()
    tired, tiredAt = D.Decay(tired, now - tiredAt, TIRED_HALF_LIFE) + amount, now
end
local function Rested() tired = 0 end
push.Rest = Rested -- (the tests)
local function Fatigued() return D.Decay(tired, GetTime() - tiredAt, TIRED_HALF_LIFE) >= TIRED_AT end

-- Moments

local momentUntil = 0
local function Blocked()
    if InCombatLockdown() then return "combat" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "flight" end
    if IsInInstance() and IsInGroup() then return "group instance" end
    return nil
end
function push.Moment()
    return GetTime() < momentUntil and Blocked() == nil
end

local Evaluate
local pauseDue, pauseTimer -- when the pause evaluation is due; whether its timer runs
local function Pause(delay)
    pauseDue = math.max(pauseDue or 0, GetTime() + (delay or 0))
    if pauseTimer then return end
    local function Fire()
        local wait = pauseDue - GetTime()
        if wait > 0.001 then return C_Timer.After(wait, Fire) end
        pauseTimer, pauseDue = false, nil
        momentUntil = GetTime() + MOMENT
        Evaluate("moment")
    end
    pauseTimer = true
    C_Timer.After(delay or 0, Fire)
end
ns.On("PLAYER_REGEN_ENABLED", function() Pause(2) end)
ns.On("LOOT_CLOSED", function() Pause(0.5) end)
ns.On("PLAYER_CONTROL_GAINED", function() Pause(1) end) -- landed after a flight
ns.On("ZONE_CHANGED_NEW_AREA", function() Pause(1) end)
ns.On("ZONE_CHANGED", function() Pause(1) end)
ns.On("PLAYER_UPDATE_RESTING", function() Pause(1) end)
ns.On("PLAYER_ENTERING_WORLD", function() Pause(3) end)
-- combat: hide the note (its secure button cannot stay)
ns.On("PLAYER_REGEN_DISABLED", function()
    momentUntil = 0
    push.Interrupt()
end)

-- Quiet

-- topic has a quiet nudge (tab dot)
function push.QuietTopic(topic)
    for _, q in pairs(quiet) do
        if q.topic == topic then return true end
    end
    return false
end
-- Window opened or tab looked at: clears the dots. Returns the entries of the quiet nudges seen (entry -> true);
-- the window shows them first, with the dot (Window.lua).
function push.SeenTopic(topic)
    local entries = {}
    for situation, q in pairs(quiet) do
        if q.topic == topic or topic == nil then
            if q.entry then entries[q.entry] = true end
            quiet[situation] = nil
        end
    end
    if push.QuietChanged then push.QuietChanged() end
    return entries
end
-- topic of the newest quiet nudge newer than since (last window open): the window opens there
function push.NewestQuietTopic(since)
    local best
    for _, q in pairs(quiet) do
        if q.topic and q.at > since and (not best or q.at > best.at) then best = q end
    end
    return best and best.topic
end

-- A rule may say when what it nudged about is over (rule.resolved: gear repaired, bags emptied): what was nudged for it
-- is forgotten then, so the next time counts anew instead of waiting out AGAIN. Situations are named "<rule>:...".
local function ForgetNudged(rule)
    local prefix = rule.key .. ":"
    local function Forget(list)
        for situation in pairs(list) do
            if situation:sub(1, #prefix) == prefix then list[situation] = nil end
        end
    end
    Forget(pushedAt)
    local saved = Saved()
    if saved then Forget(saved.at) end
end

-- Deciding

local function New(c)
    local saved = Saved()
    local at = pushedAt[c.situation] or (saved and saved.at[c.situation])
    if at and time() - at < (c.again or AGAIN) then return false, "nudged before" end
    if laterUntil[c.situation] and time() < laterUntil[c.situation] then return false, "later" end
    local entry = c.entry
    if entry then
        local id = D.EntryID(entry)
        if id and ns.reasons.Hidden(entry, id) then return false, "don't suggest" end
        if not c.anyway then
            local since = id and ns.memory.SinceActed(id)
            if since and since < JUST_DONE then return false, "just done" end
            -- another NPC of the same errand counts as done (Reasons.lua Satisfied)
            if entry.npcID and ns.reasons.Satisfied(id, entry) < 0.5 then return false, "errand done" end
        end
    end
    return true, "yes"
end

-- level of a candidate: what the user set for its rule, lower if the candidate says so, then the steps its mood and
-- the fatigue take off (a candidate that is clearly worth it, c.worth, one step less); never below the glow, which
-- asks nothing of you
local function Level(rule, c)
    local level = math.min(push.Style(rule), c.level or ALERT)
    local steps = push.Steps(rule)
    if c.worth then steps = math.max(steps - 1, 0) end
    if Fatigued() and not rule.ownBudget then steps = math.max(steps, 1) end
    return math.max(level - steps, QUIET)
end

local laterCount = {} -- situation -> how often it was snoozed (the session)

local function Show(rule, c, level)
    Put(pushedAt, c.situation, time())
    local saved = Saved()
    if saved then saved.at[c.situation] = time() end
    waiting[c.situation] = nil
    if level == QUIET then
        quiet[c.situation] = { topic = rule.topic, rule = rule.key, ruleObj = rule, at = time(), entry = c.entry, c = c }
        if push.QuietChanged then push.QuietChanged() end
    else
        if not rule.ownBudget then lastAt[level] = time() end
        push.Toast(rule, c, level)
    end
    -- shown again (after Later): the earlier one is replaced, what it still may take back is kept
    local refund
    for i = #shown, 1, -1 do
        if shown[i].c.situation == c.situation then
            refund = shown[i].refund
            table.remove(shown, i)
        end
    end
    shown[#shown + 1] = { rule = rule, c = c, level = level, at = time(), refund = refund,
        id = c.entry and D.EntryID(c.entry) or nil }
    Note("shown", rule, c, level, level == QUIET or push.Moment())
end

-- candidates held back by a rule's holdFor: situation -> GetTime() it was first there; one timer evaluates again when
-- the first is due
local firstSeen, heldDue = {}, nil
local function EvaluateAt(when)
    if heldDue and heldDue <= when then return end
    heldDue = when
    C_Timer.After(math.max(when - GetTime(), 0) + 0.5, function()
        if heldDue ~= when then return end
        heldDue = nil
        Evaluate("held")
    end)
end

local function Decide(rule, c, present)
    present[c.situation] = true
    local new, words = New(c)
    c.new, c.newWords = new, words
    local failed, failedGate = 0, nil
    for _, gate in ipairs({ "big", "missable", "sure", "new" }) do
        local ok = gate == "new" and new or (c[gate] and c[gate][1])
        if not ok then
            failed = failed + 1
            failedGate = gate
        end
    end
    if failed > 0 then
        -- near miss: one gate short (except "nudged before")
        if failed == 1 and not (failedGate == "new" and words == "nudged before") and not nearLogged[c.situation] then
            Put(nearLogged, c.situation, true)
            Note("near", rule, c, nil, nil, failedGate)
        end
        return
    end
    -- a rule may ask a candidate to be there for a while first (an upgrade just looted may be gone in a moment)
    if rule.holdFor then
        local now = GetTime()
        local since = firstSeen[c.situation]
        if not since then
            since = now
            Put(firstSeen, c.situation, now)
        end
        if now - since < rule.holdFor then
            Note("held", rule, c, nil, nil, ("%d s to go"):format(since + rule.holdFor - now))
            EvaluateAt(since + rule.holdFor)
            return
        end
    end
    local level = Level(rule, c)
    if level <= 0 then return end
    -- over the budget: quiet instead
    if level > QUIET and not rule.ownBudget
            and time() - lastAt[level] < NOTE_EVERY then
        Note("budget", rule, c, level)
        level = QUIET
    end
    -- a note waits for a pause, an alert only for the end of a fight; one note at a time
    local blocked = Blocked()
    local ready = level == QUIET or push.Moment() or (level == ALERT and blocked ~= "combat" and blocked ~= "flight")
    if ready and level > QUIET and push.Busy and push.Busy(level) then ready = false end
    if not ready then
        if not waiting[c.situation] then
            waiting[c.situation] = { c = c, rule = rule, level = level }
            Note("waited", rule, c, level, false, blocked or "no pause")
        end
        return
    end
    Show(rule, c, level)
end

-- did you do what the message was about since it showed? The rule knows best (rule.done(c, shownAt): the gear is
-- repaired, whichever repairer, a trainer window opened, the rare targeted, the item worn); else: you used the entry
local function Done(s, now)
    local rule = s.rule
    if rule.done and rule.done(s.c, s.at) then return true end
    local since = s.id and ns.memory.SinceActed(s.id)
    return since ~= nil and since <= now - s.at
end

-- followed (entry acted on since) or gone (reason went away); also prunes waiting and quiet
local function Watch(present)
    local now = time()
    for i = #shown, 1, -1 do
        local s = shown[i]
        if Done(s, now) then
            -- acted on: credit, and what a Later or a fade took off comes back with a little more
            Credit(s.rule, s.refund and s.refund > 0 and s.refund + WEIGHT.forgiven or WEIGHT.followed)
            Rested()
            laterCount[s.c.situation] = nil
            Note("followed", s.rule, s.c, s.level, nil, ("%d s"):format(now - s.at))
            table.remove(shown, i)
        elseif not present[s.c.situation] then
            Note("gone", s.rule, s.c, s.level, nil, ("%d s"):format(now - s.at))
            if push.Gone then push.Gone(s.c.situation) end
            table.remove(shown, i)
        elseif now - s.at > FOLLOW then
            table.remove(shown, i)
        end
    end
    for situation, w in pairs(waiting) do
        if not present[situation] then
            Note("dropped", w.rule, w.c, w.level)
            waiting[situation] = nil
        end
    end
    for situation in pairs(quiet) do
        if not present[situation] then quiet[situation] = nil end
    end
    for situation in pairs(firstSeen) do
        if not present[situation] then firstSeen[situation] = nil end
    end
end

local running = false
local ranAt = -math.huge -- GetTime() of the last start
function Evaluate(why)
    if running or not ns.db or ns.db.push == false or ns.db.adviceOn == false or InCombatLockdown() then return end
    running = true
    ranAt = GetTime()
    local present = {}
    local ok, problem = pcall(function()
        D.RefreshOwned()
        ns.reasons.Refresh() -- rules read current reasons
    end)
    if ok then
        local allRan = true
        for _, rule in ipairs(rules) do
            if Enabled(rule) then
                if rule.resolved and rule.resolved() then ForgetNudged(rule) end
                local done, err = pcall(rule.candidates, function(c) Decide(rule, c, present) end)
                if not done then
                    allRan = false
                    geterrorhandler()(err)
                end
            end
        end
        if allRan then
            ok, problem = pcall(function()
                Watch(present)
                if push.QuietChanged then push.QuietChanged() end
            end)
        end
    end
    running = false
    if not ok then geterrorhandler()(problem) end
end
push.Evaluate = Evaluate

-- re-evaluate once shortly after rule states change (batches changes)
local due = false
local function Soon()
    if due then return end
    due = true
    C_Timer.After(1, function()
        due = false
        -- a loot also pauses (0.5 s) and changes the bags: one full evaluation is enough
        if GetTime() - ranAt > 0.6 then Evaluate("state") end
    end)
end
-- a rule's own event (a trainer window opened, a rare targeted) may have finished what a message was about: look again
function push.Recheck() Soon() end

-- Call after the rules are registered (end of Pushes.lua).
function push.Start()
    local states, seen = {}, {}
    for _, rule in ipairs(rules) do
        for _, state in ipairs(rule.states or {}) do
            if not seen[state] then
                seen[state] = true
                states[#states + 1] = state
            end
        end
    end
    if #states > 0 then D.OnState(states, Soon) end
end

-- Answers from the note (Toast.lua)

function push.Answer(rule, c, level, answer)
    if rule.sample then
        -- a test nudge (the options): it behaves as shown, but nothing of it is kept: no score, no fatigue, no snooze,
        -- no switch, no budget
        if level == QUIET then
            if answer ~= "later" and answer ~= "dismissed" and answer ~= "faded" then quiet[c.situation] = nil end
            if push.QuietChanged then push.QuietChanged() end
        end
        Note(answer, rule, c, level, nil, "test nudge")
        return
    end
    -- shown but not taken in: the budget slot is free again
    if (answer == "later" or answer == "interrupted" or answer == "replaced") and not rule.ownBudget then
        lastAt[level] = 0
    end
    if answer == "later" then
        laterUntil[c.situation] = time() + LATER
        pushedAt[c.situation] = nil
        local saved = Saved()
        if saved then saved.at[c.situation] = nil end
    elseif answer == "never" then
        ns.db["nudge_" .. rule.key] = "off"
    elseif answer == "interrupted" or answer == "replaced" then
        -- combat or another note: may come again later
        pushedAt[c.situation] = nil
        local saved = Saved()
        if saved then saved.at[c.situation] = nil end
    end
    -- what the answer says about your interest: the score (not for samples; learning off: unchanged) and the fatigue
    local weight
    -- (a message you asked for with a click on the glowing button, level quiet, interrupted nothing: no fatigue)
    local asked = level == QUIET
    if answer == "ignored" then
        weight = WEIGHT.ignored
        Tire(TIRED.ignored)
    elseif answer == "dismissed" then
        weight = WEIGHT.dismissed -- only closed: neutral for the score
        if not asked then Tire(TIRED.dismissed) end
    elseif answer == "faded" then
        weight = 0 -- an asked-for message that was left alone
    elseif answer == "later" then
        local count = math.min((laterCount[c.situation] or 0) + 1, #SNOOZE)
        Put(laterCount, c.situation, count)
        weight = SNOOZE[count] -- the first snooze is a deferral, repeated ones say more
        if not asked then Tire(TIRED.later) end
    elseif answer == "clicked" or answer == "liked" then
        weight = WEIGHT[answer]
        Rested()
    end
    if weight then Credit(rule, weight) end
    -- watched for FOLLOW: if you do it anyway, what this took off comes back (Watch)
    local refund = weight and weight < 0 and -weight or nil
    -- answered: no longer watched, except what only faded, was snoozed or closed (acting on it later still counts)
    for i = #shown, 1, -1 do
        if shown[i].c == c then
            if refund and (answer == "ignored" or answer == "later" or answer == "dismissed") then
                shown[i].refund = (shown[i].refund or 0) + refund
            elseif answer ~= "ignored" and answer ~= "later" and answer ~= "dismissed" and answer ~= "faded" then
                table.remove(shown, i)
            end
        end
    end
    -- an asked-for quiet message: acting on it, praising it or switching it off ends its glow and dot
    if asked then
        if answer == "liked" or answer == "clicked" or answer == "never" then quiet[c.situation] = nil end
        if push.QuietChanged then push.QuietChanged() end
    end
    Note(answer, rule, c, level, nil, ("score %.2f, %d lower"):format(push.Score(rule), push.Steps(rule)))
end

-- drop saved situations older than AGAIN (at load)
function push.Prune()
    local now = time()
    for _, saved in pairs(ns.db.pushes) do
        saved.outcomes = nil -- the earlier, simpler memory
        for rule, record in pairs(saved.mood or {}) do -- a mood that has faded is forgotten
            if math.abs(D.Decay(record[1], now - record[2], MOOD_HALF_LIFE)) < 0.05 then saved.mood[rule] = nil end
        end
        for situation, at in pairs(saved.at or {}) do
            if now - at > AGAIN then saved.at[situation] = nil end
        end
    end
end
