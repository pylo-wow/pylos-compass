local _, D = ...
local ns = D.engine
local L = ns.L

-- Linked in chat (knowing): an item, quest, spell or recipe someone linked in chat a moment ago: what is that?
-- Strongest right after the link, fading to nothing within FRESH; your own links are left out. Only the IDs and who
-- linked them are kept, for this session; a message hidden from addons (secret value) is passed over.

local FRESH = 5 * 60 -- seconds a link counts
local linked = {}    -- entry ID -> { time(), who }
local MAX = 200      -- more than this many: the faded ones go (on write, so a busy channel cannot grow it for hours)

local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
-- the link kinds and the entry IDs they stand for (i:, q:, s:)
local KINDS = { item = "i:", quest = "q:", spell = "s:", enchant = "s:" }

local function Heard(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if D.Secret(text) or D.Secret(sender) or D.Secret(guid) then return end
    if type(text) ~= "string" or not text:find("|H", 1, true) then return end
    if guid and guid == UnitGUID("player") then return end
    local now, any = time(), false
    for kind, id in text:gmatch("|H(%a+):(%d+)") do
        local prefix = KINDS[kind]
        if prefix then
            -- who linked it, without the realm
            linked[prefix .. id] = { now, type(sender) == "string" and sender:match("^[^-]+") or nil }
            any = true
        end
    end
    if any then
        local count = 0
        for _ in pairs(linked) do count = count + 1 end
        if count > MAX then
            for id, link in pairs(linked) do
                if now - link[1] >= FRESH then linked[id] = nil end
            end
        end
        D.BumpState("rec:linked")
    end
end
for _, event in ipairs(EVENTS) do ns.On(event, Heard) end

-- how fresh: 1 right after the link, 0 after FRESH; nil if not linked
local function Freshness(id)
    local link = id and linked[id]
    return link and ns.Fade(linked, id, link[1], FRESH)
end

ns.RegisterReason({
    key = "linked",
    -- weight 1: as plain as what you just looted
    stage = "know", label = "Linked in chat",
    kind = "know",
    sources = { "items", "quests", "spells", "professions" },
    depends = { "rec:linked" }, -- fades with time: kept at most STALE seconds (Reasons.lua)
    candidates = function(add)
        for id in pairs(linked) do add(D.EntryByID(id)) end
    end,
    test = function(entry)
        local share = Freshness(D.EntryID(entry))
        return share and (0.3 + 0.7 * share) or nil
    end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["Linked in chat"] end,
    why = function(entry)
        local link = linked[D.EntryID(entry)]
        return link and link[2] and L["Linked in chat by %s"]:format(link[2]) or L["Linked in chat"]
    end,
})
