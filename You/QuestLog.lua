local _, D = ...

-- Calls take(questID, title, index) for each logged quest, headers skipped.
function D.EachLoggedQuest(take)
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            take(info.questID, info.title, index)
        end
    end
end
