local addonName, TCP = ...
TCP = TCP or {}
TCP.history = TCP.history or {}

-- Generate post-dungeon summary report with scorecard and side-by-side comparison
function TCP:GenerateCoachSummary()
  if not TCP.history or #TCP.history == 0 then
    print("No pulls recorded.")
    return
  end

  local summaryText = {}
  table.insert(summaryText, "───────────── TankCoachPlus Report ─────────────")
  table.insert(summaryText, string.format("Pulls Analyzed: %d", #TCP.history))

  -- Aggregate stat totals
  local statTotals = {Haste=0, Mastery=0, Versatility=0, Avoidance=0}
  local pullCount = #TCP.history
  for _, pull in ipairs(TCP.history) do
    if pull.statRecommendations then
      for _, statRec in ipairs(pull.statRecommendations) do
        for stat, val in pairs(statRec) do
          statTotals[stat] = (statTotals[stat] or 0) + val
        end
      end
    end
  end

  table.insert(summaryText, "Overall Stat Trend:")
  for stat, total in pairs(statTotals) do
    table.insert(summaryText, string.format("  %s = %.2f", stat, total / math.max(1, pullCount)))
  end

  -- Scorecard
  local function grade(value)
    if value >= 0.3 then return "A"
    elseif value >= 0.25 then return "B"
    elseif value >= 0.2 then return "C"
    else return "D" end
  end

  table.insert(summaryText, "\nScorecard:")
  table.insert(summaryText, string.format("  Cooldowns: %s", grade((statTotals.Versatility or 0) / math.max(1, pullCount))))
  table.insert(summaryText, string.format("  Damage Mitigation: %s", grade((statTotals.Haste or 0) / math.max(1, pullCount))))
  table.insert(summaryText, string.format("  Stat Focus: %s", grade((statTotals.Mastery or 0) / math.max(1, pullCount))))

  -- Pull-wise verdicts and short natural-language summaries
  table.insert(summaryText, "\nVerdicts by Pull:")
  for i, pull in ipairs(TCP.history) do
    table.insert(summaryText, string.format(" Pull %d:", i))
    if pull.verdicts then
      for _, verdictGroup in ipairs(pull.verdicts) do
        for _, verdict in ipairs(verdictGroup) do
          if verdict.text then
            table.insert(summaryText, string.format("  - %s", verdict.text))
          end
        end
      end
    else
      table.insert(summaryText, "  - No verdicts recorded.")
    end
  end

  table.insert(summaryText, "───────────── End of Report ─────────────")

  -- Print to chat
  for _, line in ipairs(summaryText) do
    print(line)
  end

  -- Refresh UI if open
  if TCP.HistoryUI and TCP.HistoryUI:IsShown() then
    if TCP.RefreshSummaryUI then
      TCP:RefreshSummaryUI()
    end
  end
end
