-- ThreatAnalyzer.lua - Threat & Aggro Analysis
local addonName, TCP = ...

TCP.ThreatAnalyzer = {}
local TA = TCP.ThreatAnalyzer

-- Threat tracking data
TA.threatEvents = {}
TA.aggroLosses = {}
TA.mobTargets = {}
TA.lastThreatUpdate = 0

-- Threat generation abilities by class
TA.THREAT_ABILITIES = {
    WARRIOR = {
        ["Thunder Clap"] = {threat = 1.5, aoe = true},
        ["Revenge"] = {threat = 2.0, aoe = false},
        ["Shield Slam"] = {threat = 1.8, aoe = false},
        ["Taunt"] = {threat = 999, taunt = true},
    },
    PALADIN = {
        ["Consecration"] = {threat = 1.3, aoe = true},
        ["Hammer of Wrath"] = {threat = 1.5, aoe = false},
        ["Shield of the Righteous"] = {threat = 1.7, aoe = false},
        ["Hand of Reckoning"] = {threat = 999, taunt = true},
    },
    DEATHKNIGHT = {
        ["Death and Decay"] = {threat = 1.4, aoe = true},
        ["Heart Strike"] = {threat = 1.6, aoe = true},
        ["Death Grip"] = {threat = 999, taunt = true},
        ["Dark Command"] = {threat = 999, taunt = true},
    },
    MONK = {
        ["Keg Smash"] = {threat = 1.5, aoe = true},
        ["Tiger Palm"] = {threat = 1.2, aoe = false},
        ["Blackout Kick"] = {threat = 1.4, aoe = false},
        ["Provoke"] = {threat = 999, taunt = true},
    },
    DRUID = {
        ["Thrash"] = {threat = 1.4, aoe = true},
        ["Mangle"] = {threat = 1.6, aoe = false},
        ["Swipe"] = {threat = 1.3, aoe = true},
        ["Growl"] = {threat = 999, taunt = true},
    },
    EVOKER = {
        ["Azure Strike"] = {threat = 1.2, aoe = true},
        ["Living Flame"] = {threat = 1.3, aoe = false},
        ["Rescue"] = {threat = 999, taunt = true},
    }
}

function TA:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:HandleCombatEvent()
        elseif event == "PLAYER_TARGET_CHANGED" then
            self:UpdateThreatInfo()
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            self:UpdateThreatInfo()
        end
    end)
    
    -- Create threat warning frame
    self:CreateThreatFrame()
    
    -- Start threat monitoring timer
    C_Timer.NewTicker(0.5, function() self:MonitorThreat() end)
end

function TA:CreateThreatFrame()
    -- Try modern approach first, fallback to older method
    local template = nil
    if BackdropTemplateMixin then
        template = "BackdropTemplate"
    end
    
    self.threatFrame = CreateFrame("Frame", "TCPThreatFrame", UIParent, template)
    self.threatFrame:SetSize(300, 150)
    self.threatFrame:SetPoint("TOPRIGHT", -20, -100)
    
    -- Apply backdrop with compatibility check
    local backdropInfo = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    
    if self.threatFrame.SetBackdrop then
        self.threatFrame:SetBackdrop(backdropInfo)
    elseif BackdropTemplateMixin then
        -- Use mixin directly
        Mixin(self.threatFrame, BackdropTemplateMixin)
        self.threatFrame:SetBackdrop(backdropInfo)
    end
    
    self.threatFrame:Hide()
    
    -- Title
    self.threatFrame.title = self.threatFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.threatFrame.title:SetPoint("TOP", 0, -10)
    self.threatFrame.title:SetText("Threat Analysis")
    
    -- Content
    self.threatFrame.content = self.threatFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.threatFrame.content:SetPoint("TOPLEFT", 10, -30)
    self.threatFrame.content:SetPoint("BOTTOMRIGHT", -10, 10)
    self.threatFrame.content:SetJustifyH("LEFT")
    self.threatFrame.content:SetJustifyV("TOP")
end

function TA:HandleCombatEvent()
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    
    local playerGUID = UnitGUID("player")
    if not playerGUID then return end
    
    -- Track threat-generating abilities
    if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
        self:TrackThreatAbility(spellName, destGUID, timestamp)
    end
    
    -- Track when mobs switch targets
    if subEvent == "SPELL_DAMAGE" or subEvent == "SWING_DAMAGE" then
        if destGUID and UnitExists("player") then
            self:TrackMobTarget(sourceGUID, destGUID, timestamp)
        end
    end
    
    -- Track taunt usage and effectiveness
    if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
        local _, class = UnitClass("player")
        local abilities = self.THREAT_ABILITIES[class] or {}
        if abilities[spellName] and abilities[spellName].taunt then
            self:TrackTauntUsage(spellName, destGUID, timestamp)
        end
    end
end

function TA:TrackThreatAbility(spellName, targetGUID, timestamp)
    local _, class = UnitClass("player")
    local abilities = self.THREAT_ABILITIES[class] or {}
    
    if abilities[spellName] then
        table.insert(self.threatEvents, {
            spell = spellName,
            target = targetGUID,
            timestamp = timestamp,
            threat = abilities[spellName].threat,
            aoe = abilities[spellName].aoe
        })
        
        -- Keep only recent events (last 30 seconds)
        for i = #self.threatEvents, 1, -1 do
            if timestamp - self.threatEvents[i].timestamp > 30 then
                table.remove(self.threatEvents, i)
            end
        end
    end
end

function TA:TrackMobTarget(mobGUID, targetGUID, timestamp)
    if not self.mobTargets[mobGUID] then
        self.mobTargets[mobGUID] = {
            currentTarget = targetGUID,
            lastChange = timestamp,
            changes = 0
        }
    else
        local mobData = self.mobTargets[mobGUID]
        if mobData.currentTarget ~= targetGUID then
            mobData.changes = mobData.changes + 1
            mobData.currentTarget = targetGUID
            mobData.lastChange = timestamp
            
            -- Check if this is aggro loss from tank
            local playerGUID = UnitGUID("player")
            if mobData.currentTarget == playerGUID then
                -- Tank gained aggro
            elseif targetGUID ~= playerGUID and UnitExists("player") then
                -- Tank lost aggro
                self:RecordAggroLoss(mobGUID, targetGUID, timestamp)
            end
        end
    end
end

function TA:RecordAggroLoss(mobGUID, newTargetGUID, timestamp)
    local targetName = "Unknown"
    for i = 1, 40 do
        if UnitGUID("raid" .. i) == newTargetGUID or UnitGUID("party" .. i) == newTargetGUID then
            targetName = UnitName("raid" .. i) or UnitName("party" .. i) or "Unknown"
            break
        end
    end
    
    table.insert(self.aggroLosses, {
        mob = mobGUID,
        newTarget = newTargetGUID,
        targetName = targetName,
        timestamp = timestamp,
        playerThreatActions = self:GetRecentThreatActions(timestamp, 5) -- Last 5 seconds
    })
    
    -- Alert for aggro loss
    if TCP.debug then
        print(string.format("TCP: Aggro lost to %s", targetName))
    end
    
    self:SuggestThreatRecovery(mobGUID)
end

function TA:GetRecentThreatActions(timestamp, seconds)
    local actions = {}
    for _, event in ipairs(self.threatEvents) do
        if timestamp - event.timestamp <= seconds then
            table.insert(actions, event)
        end
    end
    return actions
end

function TA:TrackTauntUsage(spellName, targetGUID, timestamp)
    -- Track taunt effectiveness
    C_Timer.After(1, function()
        local mobData = self.mobTargets[targetGUID]
        if mobData and mobData.currentTarget == UnitGUID("player") then
            if TCP.debug then
                print("TCP: Taunt successful -", spellName)
            end
        else
            if TCP.debug then
                print("TCP: Taunt failed or target immune -", spellName)
            end
        end
    end)
end

function TA:MonitorThreat()
    if not UnitAffectingCombat("player") then
        self.threatFrame:Hide()
        return
    end
    
    local threats = {}
    local hasLowThreat = false
    
    -- Check threat on current target and nearby enemies
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) then
            local isTanking, status, threatpct, rawthreatpct, threatvalue = UnitDetailedThreatSituation("player", unit)
            
            if threatpct then
                local mobName = UnitName(unit) or "Unknown"
                table.insert(threats, {
                    name = mobName,
                    percent = threatpct,
                    status = status,
                    isTanking = isTanking
                })
                
                -- Check for low threat situations
                if not isTanking and threatpct < 110 then
                    hasLowThreat = true
                end
            end
        end
    end
    
    if #threats > 0 then
        self:UpdateThreatDisplay(threats, hasLowThreat)
    else
        self.threatFrame:Hide()
    end
end

function TA:UpdateThreatDisplay(threats, hasLowThreat)
    local lines = {}
    table.insert(lines, "Current Threats:")
    
    table.sort(threats, function(a, b) return a.percent > b.percent end)
    
    for i, threat in ipairs(threats) do
        if i <= 5 then -- Show top 5 threats
            local color = "|cff00ff00" -- Green
            if not threat.isTanking then
                color = "|cffff0000" -- Red
            elseif threat.percent < 130 then
                color = "|cffffff00" -- Yellow
            end
            
            table.insert(lines, string.format("%s%s: %.0f%%|r", 
                color, threat.name, threat.percent))
        end
    end
    
    if hasLowThreat then
        table.insert(lines, "|cffff0000WARNING: Low threat detected!|r")
        self:SuggestThreatActions()
    end
    
    self.threatFrame.content:SetText(table.concat(lines, "\n"))
    self.threatFrame:Show()
end

function TA:UpdateThreatInfo()
    -- Update threat information when target changes
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        return
    end
    
    local isTanking, status, threatpct, rawthreatpct, threatvalue = UnitDetailedThreatSituation("player", "target")
    
    if threatpct then
        -- Store threat information for analysis
        local currentTime = GetTime()
        table.insert(self.threatEvents, {
            target = UnitGUID("target"),
            targetName = UnitName("target"),
            threatPercent = threatpct,
            isTanking = isTanking,
            status = status,
            timestamp = currentTime
        })
        
        -- Clean old threat events (keep last 30 seconds)
        for i = #self.threatEvents, 1, -1 do
            if currentTime - self.threatEvents[i].timestamp > 30 then
                table.remove(self.threatEvents, i)
            end
        end
        
        -- Check for threat issues
        if not isTanking and UnitAffectingCombat("player") then
            self:CheckThreatWarnings(threatpct, UnitName("target"))
        end
    end
end

function TA:CheckThreatWarnings(threatPercent, targetName)
    -- Warn if threat is getting low
    if threatPercent < 110 and threatPercent > 0 then
        if TCP.debug then
            print(string.format("TCP: Low threat on %s (%.0f%%)", targetName, threatPercent))
        end
        
        -- Suggest threat actions if threat is very low
        if threatPercent < 105 then
            self:SuggestThreatActions()
        end
    end
end
    local _, class = UnitClass("player")
    local abilities = self.THREAT_ABILITIES[class] or {}
    
    local suggestions = {}
    for spellName, data in pairs(abilities) do
        if data.taunt then
            table.insert(suggestions, spellName)
        elseif data.aoe and data.threat > 1.3 then
            table.insert(suggestions, spellName)
        end
    end
    
    if #suggestions > 0 then
        local message = "Consider using: " .. table.concat(suggestions, ", ")
        TCP.CooldownTracker:TriggerAlert("Aggro Lost!", message)
    end
end

function TA:SuggestThreatActions()
    local _, class = UnitClass("player")
    local abilities = self.THREAT_ABILITIES[class] or {}
    
    local aoeAbilities = {}
    for spellName, data in pairs(abilities) do
        if data.aoe and data.threat > 1.2 then
            table.insert(aoeAbilities, spellName)
        end
    end
    
    if #aoeAbilities > 0 and TCP.CooldownTracker then
        local message = "Use AoE threat: " .. aoeAbilities[1]
        TCP.CooldownTracker:TriggerAlert("Low Threat!", message)
    end
end

function TA:GetThreatStats()
    local stats = {
        aggroLosses = #self.aggroLosses,
        totalThreatActions = #self.threatEvents,
        averageThreatPerAction = 0
    }
    
    if #self.threatEvents > 0 then
        local total = 0
        for _, event in ipairs(self.threatEvents) do
            total = total + event.threat
        end
        stats.averageThreatPerAction = total / #self.threatEvents
    end
    
    return stats
end

-- Initialize
TA:Initialize()
