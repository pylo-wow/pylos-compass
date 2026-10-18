local _, D = ...
if D.off then return end
local ns = D.engine
local L = ns.L

-- Target (knowing): the NPC you target. Who it is, what it sells, drops or teaches is the first thing you might want to
-- look up about it. Strength 1 while it is your target.

local targetID -- the NPC ID of your target; per search

ns.RegisterReason({
    key = "target",
    -- weight 1.25: what you look at right now is the first thing to know
    stage = "know", weight = 1.25, label = "Target",
    kind = "know",
    sources = { "npcs" },
    depends = { "target" },
    prepare = function() targetID = D.NPCOf("target") end,
    candidates = function(add)
        targetID = D.NPCOf("target")
        if targetID then add(D.NPCByID(targetID)) end
    end,
    test = function(entry) return targetID ~= nil and entry.npcID == targetID end,
    reach = function() return ns.reach.NOW, nil end,
    note = function() return L["Your target"] end,
})
