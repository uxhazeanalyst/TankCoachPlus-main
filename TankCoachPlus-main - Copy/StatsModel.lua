--- StatsModel.lua
local addonName, TCP = ...

-- Ensure TCP table exists
if not TCP then TCP = {} end

-- Base stat weights for Protection Warrior (expandable per spec)
TCP.STAT_WEIGHTS = TCP.STAT_WEIGHTS or {}
TCP.STAT_WEIGHTS.WARRIOR_Protection = {Haste=0.3, Mastery=0.25, Versatility=0.2, Avoidance=0.25}

-- RecommendStats: adapt stat weights based on danger windows
function TCP:RecommendStats()
  local spec = TCP.activeSpec or "WARRIOR_Protection"
  local base = TCP.STAT_WEIGHTS[spec] or {}
  local adaptive = {}

  local spikeCount, deathCount = 0, 0
  if TCP.dangerWindows then
    for _, e in ipairs(TCP.dangerWindows) do
      if e.type == "death" then deathCount = deathCount+1 end
      if e.type == "lowHP" then spikeCount = spikeCount+1 end
    end
  end

  for stat, val in pairs(base) do adaptive[stat] = val end
  if spikeCount > 2 and adaptive["Mastery"] then
    adaptive["Mastery"] = math.min(1.0, adaptive["Mastery"] + 0.05)
  end
  if deathCount > 0 and adaptive["Versatility"] then
    adaptive["Versatility"] = math.min(1.0, adaptive["Versatility"] + 0.05)
  end

  if TCP.debugStats then
    print("[TankCoachPlus] Adaptive Stat Weights:")
    for stat, val in pairs(adaptive) do
      print(string.format("  %s: %.2f", stat, val))
    end
  end

  return adaptive
end

-- AnalyzePull: builds a detailed report of the pull
function TCP:AnalyzePull()
  local dangerT = TCP:adaptiveThreshold() or 0.4
  local report = {events={}, cooldowns={}, resources={}, statRecommendations={}, verdicts={}}

  -- Track danger windows and generate per-event data
  if TCP.dangerWindows then
    for _, event in ipairs(TCP.dangerWindows) do
      table.insert(report.events, event)

      -- Per-event stat recommendation
      local statRec = TCP:RecommendStats()
      table.insert(report.statRecommendations, statRec)

      -- Natural-language verdict
      local verdictText
      if event.type == "death" then
        verdictText = "Player death occurred; consider using major cooldowns earlier."
      elseif event.type == "lowHP" then
        verdictText = "Multiple players low HP; check mitigation cooldowns."
      elseif event.type == "highDamage" then
        verdictText = "High incoming damage detected; consider pre-mitigation."
      end
      if verdictText then
        table.insert(report.verdicts, {t=event.t, text=verdictText})
      end
    end
  end

  -- Resource snapshot
  if UnitPower then
    local resourceSnapshot = UnitPower("player", 0)
    table.insert(report.resources, {t=GetTime(), value=resourceSnapshot})
  end

  -- Cooldown usage
  local cdUsage = {}
  local cds = TCP.DEFAULT_CD_BY_SPEC and (TCP.DEFAULT_CD_BY_SPEC[TCP.activeSpec] or {}) or {}
  for _, cd in ipairs(cds) do
    local start, duration, enabled = GetSpellCooldown(cd)
    local remaining = (enabled == 1 and duration > 1) and (start+duration-GetTime()) or 0
    local used = remaining > 0
    table.insert(cdUsage, {spell=cd, used=used, needed=remaining <= 0})
  end
  report.cooldowns = cdUsage

  TCP.lastReport = report
  return report
end

-- Slash command to toggle debug stat output
SLASH_TCPDEBUGSTATS1 = "/tcpdebugstats"
SlashCmdList["TCPDEBUGSTATS"] = function()
  TCP.debugStats = not TCP.debugStats
  print("[TankCoachPlus] Debug Stats mode:", TCP.debugStats and "ON" or "OFF")
end
