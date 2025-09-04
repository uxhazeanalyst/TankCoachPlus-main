--- SuggestionEngine.lua
local addonName, TCP = ...

function TCP:AnalyzePull()
  local dangerT = TCP:adaptiveThreshold()
  local report = {}

  for _, event in ipairs(TCP.dangerWindows) do
    table.insert(report, event)
  end

  local resourceSnapshot = UnitPower("player", 0)
  table.insert(report, {t=GetTime(), type="resources", detail=resourceSnapshot})

  local cdUsage = {}
  local cds = TCP.DEFAULT_CD_BY_SPEC[TCP.activeSpec] or {}
  for _, cd in ipairs(cds) do
    local start, duration, enabled = GetSpellCooldown(cd)
    local remaining = (enabled == 1 and duration > 1) and (start+duration-GetTime()) or 0
    local used = remaining > 0
    table.insert(cdUsage, {spell=cd, used=used, needed=remaining <= 0})
  end
  table.insert(report, {t=GetTime(), type="cooldowns", detail=cdUsage})

  local statRec = TCP:RecommendStats()
  table.insert(report, {t=GetTime(), type="stat_recommendation", detail=statRec})

  local verdicts = {}
  for _, e in ipairs(TCP.dangerWindows) do
    if e.type == "death" then
      table.insert(verdicts, {t=e.t, text="Player death occurred; consider using major cooldowns earlier."})
    elseif e.type == "lowHP" then
      table.insert(verdicts, {t=e.t, text="Multiple players low HP; check mitigation cooldowns."})
    end
  end
  table.insert(report, {t=GetTime(), type="verdicts", detail=verdicts})

  TCP.lastReport = report
  return report
end
