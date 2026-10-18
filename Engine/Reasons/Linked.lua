local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Linked in chat (knowing): an item, quest, spell or recipe someone linked in chat a moment ago: what is that?
-- Strongest right after the link, fading to nothing within FRESH; your own links are left out. Only the IDs and who
-- linked them are kept, for this session; a message hidden from addons (secret value) is passed over.

local FRESH = 5 * 60 -- seconds a link counts
local linked = {}    -- entry ID -> { time(), who }

local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
-- the link kinds and the entry IDs they stand for (Data: i:, q:, s:)
local KINDS = { item = "i:", quest = "q:", spell = "s:", enchant = "s:" }

local function Heard(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender) or issecretvalue(guid)) then return end
    if type(text) ~= "string" or not text:find("|H", 1, true) then return end
    if guid and guid == UnitGUID("player") then return end
    local now, any = time(), false
    for kind, id in text:gmatch("|H(%a+):(%d+)") do
        local prefix = KINDS[kind]
        if prefix then
            -- (who linked it, without the realm)
            linked[prefix .. id] = { now, type(sender) == "string" and sender:match("^[^-]+") or nil }
            any = true
        end
    end
    if any then D.BumpState("rec:linked") end
end
for _, event in ipairs(EVENTS) do ns.On(event, Heard) end

-- how fresh: 1 right after the link, 0 after FRESH; nil if not linked
local function Freshness(id)
    local link = id and linked[id]
    if not link then return nil end
    local share = 1 - (time() - link[1]) / FRESH
    if share <= 0 then
        linked[id] = nil
        return nil
    end
    return share
end

ns.RegisterReason({
    key = "linked",
    -- weight 1: as plain as what you just looted
    stage = "know", label = "Linked in chat",
    kind = "know",
    sources = { "items", "quests", "spells", "professions" },
    depends = { "rec:linked" }, -- (fading with time: kept at most STALE seconds, Reasons.lua)
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
