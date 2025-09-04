--- Core.lua
local addonName, TCP = ...
TCP.defaults = {}

TCP.DEFAULT_CD_BY_SPEC = {
  WARRIOR_Protection = {"Shield Wall", "Shield Block", "Avatar", "Demoralizing Shout", "Last Stand"},
  PALADIN_Protection = {"Avenging Wrath", "Ardent Defender", "Guardian of Ancient Kings", "Blessing of Sacrifice", "Divine Shield"},
  DK_Blood = {"Bone Shield", "Vampiric Blood", "Dancing Rune Weapon", "Icebound Fortitude", "Anti-Magic Shell"},
  MONK_Brewmaster = {"Guard", "Fortifying Brew", "Celestial Brew", "Elusive Brew", "Summon Black Ox Statue"},
  DRUID_Guardian = {"Barkskin", "Ironfur", "Survival Instincts", "Frenzied Regeneration", "Stampeding Roar"},
  EVOKER_Preservation = {"Dream Flight", "Rewind", "Zephyr", "Emerald Communion", "Stasis"}
}

-- Initialize tables
TCP.activeCooldowns, TCP.dangerWindows, TCP.events = {}, {}, {}
TCP.history = TCP.history or {}

-- Settings
TCP.settings = TCP.settings or {
  onlyMythicPlus = true,  -- Only track in M+ dungeons
  enableOpenWorld = false, -- Allow open world tracking
  resetOnNewInstance = true -- Auto-reset when entering new instance
}

-- Helper function for safe function calls
local function SafeCall(func, ...)
  if func and type(func) == "function" then
    return func(...)
  end
end

-- Initialize core tables
local function EnsureInitialized()
  TCP.activeCooldowns = TCP.activeCooldowns or {}
  TCP.dangerWindows = TCP.dangerWindows or {}
  TCP.events = TCP.events or {}
  TCP.history = TCP.history or {}
end

-- Check if we should track events in current content
local function ShouldTrackEvents()
  local inInstance, instanceType = IsInInstance()
  
  if TCP.settings.onlyMythicPlus then
    -- Only track in Mythic+ dungeons
    if inInstance and instanceType == "party" then
      local inTimeWalking, inTimewalkingInstance = C_QuestLog.IsQuestFlaggedCompleted(0)
      local _, _, difficulty = GetInstanceInfo()
      return difficulty == 8 -- Mythic+ difficulty ID
    end
    return false
  elseif not TCP.settings.enableOpenWorld then
    -- Track in any instance but not open world
    return inInstance
  else
    -- Track everywhere
    return true
  end
end

-- Reset tracking data
local function ResetTracking()
  TCP.events = {}
  TCP.dangerWindows = {}
  TCP.activeCooldowns = {}
  if TCP.debug then
    print("TCP: Tracking data reset")
  end
end

local function getActiveAffixes()
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    local keystoneInfo = C_ChallengeMode.GetActiveKeystoneInfo()
    if keystoneInfo then
      local _, affixes = keystoneInfo
      return affixes or {}
    end
  end
  return {}
end

TCP.baseThreshold = 0.4
function TCP:adaptiveThreshold()
  local affixes = getActiveAffixes()
  for _, affixID in ipairs(affixes) do
    if affixID == 9 then return 0.3 elseif affixID == 10 then return 0.5 end
  end
  return TCP.baseThreshold
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- Only track if we should be tracking in current content
    if not ShouldTrackEvents() then
      return
    end
    
    if not CombatLogGetCurrentEventInfo then
      return -- API not ready yet
    end
    local timestamp, subEvent, _, _, _, _, _, destGUID, _, _, _, spellID, spellName, _, amount = CombatLogGetCurrentEventInfo()
    if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" then
      table.insert(TCP.events, {t=GetTime(), spell=spellName, amount=amount, target=destGUID})
    elseif subEvent == "UNIT_DIED" and destGUID then
      table.insert(TCP.dangerWindows, {t=GetTime(), type="death", detail=destGUID})
      SafeCall(TCP.OnMobDeath, TCP, destGUID)
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    EnsureInitialized()
    local specIndex = GetSpecialization()
    if specIndex then 
      local _, specName = GetSpecializationInfo(specIndex)
      TCP.activeSpec = specName or "Unknown"
    end
    
    -- Reset tracking when entering new content if enabled
    if TCP.settings.resetOnNewInstance then
      ResetTracking()
    end
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- Reset when changing zones if auto-reset is enabled
    if TCP.settings.resetOnNewInstance then
      ResetTracking()
    end
  elseif event == "CHALLENGE_MODE_COMPLETED" then
    TCP:GenerateCoachSummary()
  end
end)

SLASH_TCP1 = "/tcp"
SlashCmdList["TCP"] = function(msg)
  if msg == "recommend" then
    local rec = TCP:RecommendStats()
    print("TankCoachPlus Stat Recommendation:")
    for stat, val in pairs(rec) do print(string.format("  %s: %.2f", stat, val)) end
  elseif msg:match("^history") then
    local n = tonumber(msg:match("history (%d+)") or 5)
    TCP:PrintHistory(n)
  elseif msg == "ui" then
    if TCP.HistoryUI then TCP.HistoryUI:Show() end
  elseif msg == "summary" then
    TCP:GenerateCoachSummary()
  elseif msg == "nameplates" then
    TCP.nameplatesEnabled = not TCP.nameplatesEnabled
    print("TCP Nameplates:", TCP.nameplatesEnabled and "ON" or "OFF")
  elseif msg == "debug" then
    TCP.debug = not TCP.debug
    print("TCP Debug:", TCP.debug)
  elseif msg == "reset" then
    ResetTracking()
    print("TCP: Tracking data reset")
  elseif msg == "mode" then
    TCP.settings.onlyMythicPlus = not TCP.settings.onlyMythicPlus
    print("TCP Mode:", TCP.settings.onlyMythicPlus and "Mythic+ Only" or "All Content")
  elseif msg == "openworld" then
    TCP.settings.enableOpenWorld = not TCP.settings.enableOpenWorld
    print("TCP Open World:", TCP.settings.enableOpenWorld and "ENABLED" or "DISABLED")
  elseif msg == "status" then
    local inInstance, instanceType = IsInInstance()
    local _, _, difficulty = GetInstanceInfo()
    local shouldTrack = ShouldTrackEvents()
    print("TCP Status:")
    print("  In Instance:", inInstance and instanceType or "No")
    print("  Difficulty:", difficulty or "N/A")
    print("  Currently Tracking:", shouldTrack and "YES" or "NO")
    print("  Mode:", TCP.settings.onlyMythicPlus and "M+ Only" or "All Content")
    print("  Events Recorded:", #TCP.events)
  else
    print("TankCoachPlus Commands:")
    print("/tcp recommend - show stat recommendations")
    print("/tcp history <n> - show last n pull summaries")
    print("/tcp ui - open history browser")
    print("/tcp summary - post-dungeon summary report")
    print("/tcp nameplates - toggle mob overlay")
    print("/tcp reset - clear all tracking data")
    print("/tcp mode - toggle M+ only vs all content")
    print("/tcp openworld - toggle open world tracking")
    print("/tcp status - show current tracking status")
    print("/tcp debug - toggle debug mode")
  end
end
