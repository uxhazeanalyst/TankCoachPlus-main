local addonName, TCP = ...

TCP.mobCount = TCP.mobCount or 0
TCP.totalForces = TCP.totalForces or 0
TCP.bestRunTotal = TCP.bestRunTotal or 0
TCP.prevForces = TCP.prevForces or 0

-- Defaults, pulled from SavedVariables
local function initSavedVars()
  TankCoachPlusDB = TankCoachPlusDB or {}
  TankCoachPlusDB.nameplates = TankCoachPlusDB.nameplates or {}
  TankCoachPlusDB.nameplates.show = TankCoachPlusDB.nameplates.show ~= false -- default ON
  TankCoachPlusDB.nameplates.style = TankCoachPlusDB.nameplates.style or "single"

  TCP.showNameplates = TankCoachPlusDB.nameplates.show
  TCP.floatStyle = TankCoachPlusDB.nameplates.style
end

-- Utility
local function updateBestRun()
  if TCP.totalForces > TCP.bestRunTotal then
    TCP.bestRunTotal = TCP.totalForces
  end
end

-- Attach overlay text
local function createNameplateText(frame)
  if frame.TCPText then return end
  frame.TCPText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.TCPText:SetPoint("TOP", frame, "BOTTOM", 0, -5)
  frame.TCPText:SetTextColor(1, 1, 0)
  frame.TCPText:SetText("")
end

local function updateNameplateText(frame, mobNum, mobPercent, totalForces, bestRunTotal)
  if not frame.TCPText then createNameplateText(frame) end
  local text = string.format("#%d (%.1f%%) [%d/%d]", mobNum, mobPercent, totalForces, bestRunTotal)
  frame.TCPText:SetText(text)
end

-- Pull Mythic+ forces info
local function getForcesInfo()
  local name, _, numCriteria = C_Scenario.GetStepInfo()
  if not name then return 0, 100 end
  for i = 1, numCriteria do
    local _, _, _, cur, final = C_Scenario.GetCriteriaInfo(i)
    if final and final > 0 then
      return cur, final
    end
  end
  return 0, 100
end

-- Mob death logic
local function OnMobDeath(destGUID)
  local cur, final = getForcesInfo()
  local mobPercent = ((cur - TCP.prevForces) / final) * 100
  if mobPercent < 0 then mobPercent = 0 end

  TCP.mobCount = TCP.mobCount + 1
  TCP.totalForces = cur
  TCP.prevForces = cur
  updateBestRun()

  -- Floating combat text
  local msg
  if TCP.floatStyle == "stacked" then
    msg = string.format("[+1 Mob #%d]\n[%.1f%% total]\n[%d/%d]",
      TCP.mobCount, mobPercent, TCP.totalForces, TCP.bestRunTotal)
  else
    msg = string.format("[+1 Mob #%d] [%.1f%% total] [%d/%d]",
      TCP.mobCount, mobPercent, TCP.totalForces, TCP.bestRunTotal)
  end
  TCP:ShowCombatText(msg, 0, 1, 0)

  -- Update nameplate
  if TCP.showNameplates then
    local nameplate = C_NamePlate.GetNamePlateForUnit(destGUID)
    if nameplate then
      updateNameplateText(nameplate, TCP.mobCount, mobPercent, TCP.totalForces, TCP.bestRunTotal)
    end
  end
end

-- Event frame
local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("CHALLENGE_MODE_START")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    initSavedVars()
  elseif event == "CHALLENGE_MODE_START" then
    TCP.mobCount, TCP.totalForces, TCP.prevForces = 0, 0, 0
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent == "UNIT_DIED" and destGUID then
      OnMobDeath(destGUID)
    end
  end
end)

-- Slash toggle
SLASH_TCPNAMEPLATES1 = "/tcpnameplates"
SlashCmdList["TCPNAMEPLATES"] = function(msg)
  msg = msg and msg:lower() or ""
  if msg == "style" then
    TCP.floatStyle = (TCP.floatStyle == "single") and "stacked" or "single"
    TankCoachPlusDB.nameplates.style = TCP.floatStyle
    print("TankCoachPlus Floating Text Style:", TCP.floatStyle)
  else
    TCP.showNameplates = not TCP.showNameplates
    TankCoachPlusDB.nameplates.show = TCP.showNameplates
    print("TankCoachPlus Nameplate Overlays:", TCP.showNameplates and "ON" or "OFF")
    print("Use '/tcpnameplates style' to toggle float text style.")
  end
end
