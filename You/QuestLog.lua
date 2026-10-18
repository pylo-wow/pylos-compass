local _, D = ...
if D.off then return end

-- Calls take(questID, title, index) for each logged quest, headers skipped. Prefers C_QuestLog;
-- the old globals are a fallback (questID is then -index where they give none).
function D.EachLoggedQuest(take)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID and info.questID > 0 then take(info.questID, info.title, index) end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if title and not isHeader then take(questID or -index, title, index) end
        end
    end
end
