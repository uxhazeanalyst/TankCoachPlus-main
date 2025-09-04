-- CooldownTracker.lua - Real-time Cooldown Tracking & Alerts
local addonName, TCP = ...

TCP.CooldownTracker = {}
local CT = TCP.CooldownTracker

-- Cooldown data storage
CT.activeCooldowns = {}
CT.recentDamage = {}
CT.lastAlertTime = 0
CT.alertCooldown = 3 -- seconds between alerts

-- Major defensive cooldowns by spec
CT.MAJOR_DEFENSIVES = {
    WARRIOR = {
        ["Shield Wall"] = {cd = 240, reduction = 0.4, duration = 8},
        ["Last Stand"] = {cd = 180, reduction = 0.3, duration = 15},
        ["Shield Block"] = {cd = 16, reduction = 0.3, duration = 6},
    },
    PALADIN = {
        ["Ardent Defender"] = {cd = 120, reduction = 0.2, duration = 8},
        ["Guardian of Ancient Kings"] = {cd = 300, reduction = 0.5, duration = 8},
        ["Divine Shield"] = {cd = 300, reduction = 1.0, duration = 8},
    },
    DEATHKNIGHT = {
        ["Vampiric Blood"] = {cd = 60, reduction = 0.3, duration = 10},
        ["Icebound Fortitude"] = {cd = 180, reduction = 0.3, duration = 8},
        ["Anti-Magic Shell"] = {cd = 60, reduction = 0.3, duration = 5},
    },
    MONK = {
        ["Fortifying Brew"] = {cd = 420, reduction = 0.2, duration = 15},
        ["Zen Meditation"] = {cd = 300, reduction = 0.6, duration = 8},
        ["Celestial Brew"] = {cd = 60, reduction = 0.25, duration = 8},
    },
    DRUID = {
        ["Survival Instincts"] = {cd = 240, reduction = 0.5, duration = 6},
        ["Barkskin"] = {cd = 60, reduction = 0.2, duration = 8},
        ["Frenzied Regeneration"] = {cd = 36, reduction = 0, duration = 3},
    },
    EVOKER = {
        ["Obsidian Scales"] = {cd = 150, reduction = 0.3, duration = 12},
        ["Renewing Blaze"] = {cd = 90, reduction = 0.3, duration = 8},
    }
}

-- Initialize cooldown tracking
function CT:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("UNIT_HEALTH")
    self.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:HandleCombatEvent(...)
        elseif event == "UNIT_HEALTH" then
            self:CheckHealthThresholds(...)
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            self:UpdateCooldowns()
        end
    end)
    
    self:CreateAlertFrame()
end

-- Create alert frame for warnings
function CT:CreateAlertFrame()
    self.alertFrame = CreateFrame("Frame", "TCPCooldownAlert", UIParent)
    self.alertFrame:SetSize(400, 80)
    self.alertFrame:SetPoint("CENTER", 0, 200)
    self.alertFrame:Hide()
    
    -- Background
    self.alertFrame.bg = self.alertFrame:CreateTexture(nil, "BACKGROUND")
    self.alertFrame.bg:SetAllPoints()
    self.alertFrame.bg:SetColorTexture(1, 0.2, 0.2, 0.8)
    
    -- Warning text
    self.alertFrame.text = self.alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.alertFrame.text:SetPoint("CENTER")
    self.alertFrame.text:SetTextColor(1, 1, 1)
    
    -- Auto-hide animation
    self.alertFrame.fadeOut = self.alertFrame:CreateAnimationGroup()
    local fade = self.alertFrame.fadeOut:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(1)
    fade:SetStartDelay(2)
    self.alertFrame.fadeOut:SetScript("OnFinished", function()
        self.alertFrame:Hide()
    end)
end

-- Handle combat log events
function CT:HandleCombatEvent()
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName, _, amount, absorbed = CombatLogGetCurrentEventInfo()
    
    local playerGUID = UnitGUID("player")
    if not playerGUID then return end
    
    -- Track defensive cooldown usage
    if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
        self:TrackCooldownUsage(spellName, timestamp)
    end
    
    -- Track damage taken
    if (subEvent == "SPELL_DAMAGE" or subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE") 
        and destGUID == playerGUID then
        self:TrackDamageTaken(amount or 0, absorbed or 0, timestamp)
    end
end

-- Track when player uses defensive cooldowns
function CT:TrackCooldownUsage(spellName, timestamp)
    local _, class = UnitClass("player")
    local defensives = self.MAJOR_DEFENSIVES[class]
    
    if defensives and defensives[spellName] then
        local cooldownData = defensives[spellName]
        self.activeCooldowns[spellName] = {
            endTime = timestamp + cooldownData.duration,
            reduction = cooldownData.reduction,
            cooldownEnd = timestamp + cooldownData.cd
        }
        
        if TCP.debug then
            print("TCP: Used defensive -", spellName)
        end
    end
end

-- Track damage taken and analyze if defensive was needed
function CT:TrackDamageTaken(amount, absorbed, timestamp)
    local totalDamage = amount + absorbed
    local playerMaxHP = UnitHealthMax("player") or 1
    local damagePercent = totalDamage / playerMaxHP
    
    -- Store recent damage
    table.insert(self.recentDamage, {
        amount = totalDamage,
        percent = damagePercent,
        timestamp = timestamp,
        hasDefensive = self:HasActiveDefensive(timestamp)
    })
    
    -- Clean old damage entries (keep last 5 seconds)
    for i = #self.recentDamage, 1, -1 do
        if timestamp - self.recentDamage[i].timestamp > 5 then
            table.remove(self.recentDamage, i)
        end
    end
    
    -- Check for dangerous damage without defensive
    if damagePercent > 0.4 and not self:HasActiveDefensive(timestamp) then
        self:TriggerAlert("High damage taken without defensive!", "Consider using a cooldown")
    end
    
    -- Check for spike damage patterns
    local recentTotal = 0
    local recentCount = 0
    for _, damage in ipairs(self.recentDamage) do
        if timestamp - damage.timestamp < 3 then
            recentTotal = recentTotal + damage.percent
            recentCount = recentCount + 1
        end
    end
    
    if recentCount >= 3 and recentTotal > 0.8 and not self:HasActiveDefensive(timestamp) then
        self:TriggerAlert("Spike damage detected!", "Use defensive cooldown now")
    end
end

-- Check if player has an active defensive
function CT:HasActiveDefensive(timestamp)
    for spellName, data in pairs(self.activeCooldowns) do
        if timestamp < data.endTime then
            return true
        end
    end
    return false
end

-- Get active defensive reduction
function CT:GetActiveReduction(timestamp)
    local totalReduction = 0
    for spellName, data in pairs(self.activeCooldowns) do
        if timestamp < data.endTime then
            totalReduction = totalReduction + data.reduction
        end
    end
    return math.min(totalReduction, 0.9) -- Cap at 90% reduction
end

-- Check health thresholds for alerts
function CT:CheckHealthThresholds(unit)
    if unit ~= "player" then return end
    
    local currentHP = UnitHealth("player")
    local maxHP = UnitHealthMax("player")
    local healthPercent = currentHP / maxHP
    
    -- Critical health without defensive
    if healthPercent < 0.3 and not self:HasActiveDefensive(GetTime()) then
        local availableDefensives = self:GetAvailableDefensives()
        if #availableDefensives > 0 then
            self:TriggerAlert("Critical Health!", "Use " .. availableDefensives[1] .. " now!")
        end
    end
end

-- Get list of available defensive cooldowns
function CT:GetAvailableDefensives()
    local _, class = UnitClass("player")
    local defensives = self.MAJOR_DEFENSIVES[class] or {}
    local available = {}
    local currentTime = GetTime()
    
    for spellName, data in pairs(defensives) do
        local cooldownData = self.activeCooldowns[spellName]
        if not cooldownData or currentTime > cooldownData.cooldownEnd then
            table.insert(available, spellName)
        end
    end
    
    return available
end

-- Update cooldown tracking
function CT:UpdateCooldowns()
    local currentTime = GetTime()
    
    -- Clean expired cooldowns
    for spellName, data in pairs(self.activeCooldowns) do
        if currentTime > data.endTime then
            self.activeCooldowns[spellName] = nil
        end
    end
end

-- Trigger alert message
function CT:TriggerAlert(title, message)
    local currentTime = GetTime()
    if currentTime - self.lastAlertTime < self.alertCooldown then
        return -- Don't spam alerts
    end
    
    self.lastAlertTime = currentTime
    
    -- Show visual alert
    self.alertFrame.text:SetText(title .. "\n" .. (message or ""))
    self.alertFrame:Show()
    self.alertFrame:SetAlpha(1)
    self.alertFrame.fadeOut:Stop()
    self.alertFrame.fadeOut:Play()
    
    -- Audio alert
    PlaySound(8959) -- Warning sound
    
    -- Chat message if debug enabled
    if TCP.debug then
        print("TCP Alert:", title, message or "")
    end
end

-- Get cooldown usage statistics
function CT:GetCooldownStats()
    local stats = {
        totalDefensivesUsed = 0,
        damageMitigated = 0,
        availableUptime = 0
    }
    
    -- This would be expanded with actual tracking over time
    return stats
end

-- Initialize on load
CT:Initialize()
