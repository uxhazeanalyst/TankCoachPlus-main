-- PullAnalyzer.lua - Smart Pull Analysis
local addonName, TCP = ...

TCP.PullAnalyzer = {}
local PA = TCP.PullAnalyzer

-- Pull tracking data
PA.currentPull = nil
PA.pullHistory = {}
PA.pullStartTime = nil
PA.combatStarted = false
PA.lastCombatEvent = 0

-- Pull statistics
PA.PULL_THRESHOLDS = {
    damage_taken_high = 0.8, -- 80% of max HP in a pull is high
    damage_taken_critical = 1.2, -- 120% of max HP is critical
    pull_duration_long = 60, -- 60+ seconds is a long pull
    healing_required_high = 0.6 -- 60% of max HP healing required
}

function PA:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Enter combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leave combat
    self.frame:RegisterEvent("PLAYER_DEAD")
    self.frame:RegisterEvent("ENCOUNTER_START")
    self.frame:RegisterEvent("ENCOUNTER_END")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:HandleCombatEvent()
        elseif event == "PLAYER_REGEN_DISABLED" then
            self:StartPull()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:EndPull()
        elseif event == "PLAYER_DEAD" then
            self:HandlePlayerDeath()
        elseif event == "ENCOUNTER_START" then
            self:StartBossEncounter(...)
        elseif event == "ENCOUNTER_END" then
            self:EndBossEncounter(...)
        end
    end)
    
    -- Create pull summary frame
    self:CreatePullSummaryFrame()
end

function PA:CreatePullSummaryFrame()
    -- Try modern approach first, fallback to older method
    local template = nil
    if BackdropTemplateMixin then
        template = "BackdropTemplate"
    end
    
    self.summaryFrame = CreateFrame("Frame", "TCPPullSummary", UIParent, template)
    self.summaryFrame:SetSize(350, 200)
    self.summaryFrame:SetPoint("CENTER", 300, 0)
    
    -- Apply backdrop with compatibility check
    local backdropInfo = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    
    if self.summaryFrame.SetBackdrop then
        self.summaryFrame:SetBackdrop(backdropInfo)
    elseif BackdropTemplateMixin then
        -- Use mixin directly
        Mixin(self.summaryFrame, BackdropTemplateMixin)
        self.summaryFrame:SetBackdrop(backdropInfo)
    end
    
    self.summaryFrame:Hide()
    
    -- Title
    self.summaryFrame.title = self.summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.summaryFrame.title:SetPoint("TOP", 0, -10)
    self.summaryFrame.title:SetText("Pull Analysis")
    
    -- Content
    self.summaryFrame.content = self.summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.summaryFrame.content:SetPoint("TOPLEFT", 10, -30)
    self.summaryFrame.content:SetPoint("BOTTOMRIGHT", -10, 30)
    self.summaryFrame.content:SetJustifyH("LEFT")
    self.summaryFrame.content:SetJustifyV("TOP")
    
    -- Close button
    self.summaryFrame.closeBtn = CreateFrame("Button", nil, self.summaryFrame, "UIPanelCloseButton")
    self.summaryFrame.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    self.summaryFrame.closeBtn:SetScript("OnClick", function()
        self.summaryFrame:Hide()
    end)
end

function PA:StartPull()
    if self.currentPull then
        -- Already in a pull, don't start new one
        return
    end
    
    self.pullStartTime = GetTime()
    self.combatStarted = true
    self.lastCombatEvent = self.pullStartTime
    
    self.currentPull = {
        startTime = self.pullStartTime,
        endTime = nil,
        duration = 0,
        damageTaken = 0,
        healingReceived = 0,
        mobsKilled = {},
        deathEvents = {},
        cooldownsUsed = {},
        threatEvents = {},
        maxHealthPercent = 1.0,
        minHealthPercent = 1.0,
        damageEvents = {},
        isBossEncounter = false,
        encounterID = nil,
        pullNumber = #self.pullHistory + 1
    }
    
    if TCP.debug then
        print("TCP: Pull started #" .. self.currentPull.pullNumber)
    end
end

function PA:EndPull()
    if not self.currentPull then
        return
    end
    
    self.currentPull.endTime = GetTime()
    self.currentPull.duration = self.currentPull.endTime - self.currentPull.startTime
    self.combatStarted = false
    
    -- Analyze the completed pull
    self:AnalyzePull(self.currentPull)
    
    -- Store in history
    table.insert(self.pullHistory, self.currentPull)
    
    -- Update TCP main history for compatibility
    table.insert(TCP.history, self.currentPull.damageEvents)
    
    -- Show summary if it was a significant pull
    if self.currentPull.duration > 10 or #self.currentPull.damageEvents > 5 then
        self:ShowPullSummary(self.currentPull)
    end
    
    if TCP.debug then
        print("TCP: Pull ended #" .. self.currentPull.pullNumber .. 
              " - Duration: " .. string.format("%.1fs", self.currentPull.duration))
    end
    
    self.currentPull = nil
end

function PA:HandleCombatEvent()
    if not self.currentPull then
        return
    end
    
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName, _, amount, absorbed, critical = CombatLogGetCurrentEventInfo()
    local playerGUID = UnitGUID("player")
    
    self.lastCombatEvent = timestamp
    
    -- Track damage taken by player
    if (subEvent == "SPELL_DAMAGE" or subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE") 
        and destGUID == playerGUID then
        local totalDamage = (amount or 0) + (absorbed or 0)
        self.currentPull.damageTaken = self.currentPull.damageTaken + totalDamage
        
        local currentHP = UnitHealth("player")
        local maxHP = UnitHealthMax("player")
        local healthPercent = currentHP / maxHP
        
        if healthPercent < self.currentPull.minHealthPercent then
            self.currentPull.minHealthPercent = healthPercent
        end
        
        table.insert(self.currentPull.damageEvents, {
            timestamp = timestamp,
            source = sourceName or "Unknown",
            spell = spellName or "Melee",
            amount = totalDamage,
            critical = critical,
            healthAfter = healthPercent
        })
    end
    
    -- Track healing received by player
    if (subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL") 
        and destGUID == playerGUID then
        local healAmount = amount or 0
        self.currentPull.healingReceived = self.currentPull.healingReceived + healAmount
    end
    
    -- Track mob deaths
    if subEvent == "UNIT_DIED" and destGUID then
        table.insert(self.currentPull.mobsKilled, {
            guid = destGUID,
            name = destName or "Unknown",
            timestamp = timestamp
        })
    end
    
    -- Track cooldown usage
    if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
        if TCP.CooldownTracker then
            local _, class = UnitClass("player")
            local defensives = TCP.CooldownTracker.MAJOR_DEFENSIVES[class] or {}
            if defensives[spellName] then
                table.insert(self.currentPull.cooldownsUsed, {
                    spell = spellName,
                    timestamp = timestamp
                })
            end
        end
    end
end

function PA:HandlePlayerDeath()
    if not self.currentPull then
        return
    end
    
    table.insert(self.currentPull.deathEvents, {
        timestamp = GetTime(),
        damageTaken = self.currentPull.damageTaken,
        healingReceived = self.currentPull.healingReceived
    })
    
    self.currentPull.died = true
end

function PA:StartBossEncounter(encounterID, encounterName, difficultyID, groupSize)
    if self.currentPull then
        self.currentPull.isBossEncounter = true
        self.currentPull.encounterID = encounterID
        self.currentPull.encounterName = encounterName
    end
end

function PA:EndBossEncounter(encounterID, encounterName, difficultyID, groupSize, success)
    if self.currentPull and self.currentPull.isBossEncounter then
        self.currentPull.bossKilled = success
    end
end

function PA:AnalyzePull(pull)
    local maxHP = UnitHealthMax("player") or 1
    local analysis = {
        grade = "A",
        issues = {},
        suggestions = {},
        metrics = {}
    }
    
    -- Calculate damage taken as percentage of max HP
    local damageTakenPercent = pull.damageTaken / maxHP
    analysis.metrics.damageTakenPercent = damageTakenPercent
    
    -- Analyze damage taken
    if damageTakenPercent > self.PULL_THRESHOLDS.damage_taken_critical then
        analysis.grade = "D"
        table.insert(analysis.issues, "Excessive damage taken (" .. string.format("%.0f", damageTakenPercent * 100) .. "% of max HP)")
        table.insert(analysis.suggestions, "Use more defensive cooldowns")
    elseif damageTakenPercent > self.PULL_THRESHOLDS.damage_taken_high then
        if analysis.grade == "A" then analysis.grade = "C" end
        table.insert(analysis.issues, "High damage taken")
        table.insert(analysis.suggestions, "Consider using a defensive cooldown")
    end
    
    -- Analyze pull duration
    if pull.duration > self.PULL_THRESHOLDS.pull_duration_long then
        if analysis.grade == "A" then analysis.grade = "B" end
        table.insert(analysis.issues, "Long pull duration (" .. string.format("%.1fs", pull.duration) .. ")")
        table.insert(analysis.suggestions, "Focus on threat generation and positioning")
    end
    
    -- Analyze healing required
    local healingPercent = pull.healingReceived / maxHP
    if healingPercent > self.PULL_THRESHOLDS.healing_required_high then
        if analysis.grade == "A" then analysis.grade = "C" end
        table.insert(analysis.issues, "High healing required (" .. string.format("%.0f", healingPercent * 100) .. "% of max HP)")
        table.insert(analysis.suggestions, "Improve damage mitigation")
    end
    
    -- Analyze cooldown usage
    local damagePerSecond = pull.damageTaken / math.max(pull.duration, 1)
    local expectedCooldowns = math.floor(damagePerSecond / (maxHP * 0.1)) -- Rough estimate
    if #pull.cooldownsUsed < expectedCooldowns and expectedCooldowns > 0 then
        if analysis.grade == "A" then analysis.grade = "B" end
        table.insert(analysis.issues, "Underused defensive cooldowns")
        table.insert(analysis.suggestions, "Use defensive abilities more frequently")
    end
    
    -- Check for death
    if pull.died then
        analysis.grade = "F"
        table.insert(analysis.issues, "Player death occurred")
        table.insert(analysis.suggestions, "Review damage spikes and cooldown timing")
    end
    
    -- Analyze damage spikes
    local spikes = self:FindDamageSpikes(pull.damageEvents)
    if #spikes > 0 then
        if analysis.grade == "A" then analysis.grade = "B" end
        table.insert(analysis.issues, string.format("%d damage spikes detected", #spikes))
        table.insert(analysis.suggestions, "Prepare defensives for incoming damage")
    end
    
    pull.analysis = analysis
    return analysis
end

function PA:FindDamageSpikes(damageEvents)
    local spikes = {}
    local maxHP = UnitHealthMax("player") or 1
    
    for i = 1, #damageEvents do
        local event = damageEvents[i]
        local damagePercent = event.amount / maxHP
        
        if damagePercent > 0.3 then -- 30%+ damage in one hit
            table.insert(spikes, {
                timestamp = event.timestamp,
                amount = event.amount,
                percent = damagePercent,
                source = event.source,
                spell = event.spell
            })
        end
    end
    
    return spikes
end

function PA:ShowPullSummary(pull)
    if not pull.analysis then
        return
    end
    
    local lines = {}
    table.insert(lines, string.format("Pull #%d - Grade: %s", pull.pullNumber, pull.analysis.grade))
    table.insert(lines, string.format("Duration: %.1fs", pull.duration))
    table.insert(lines, string.format("Damage Taken: %.0f (%.0f%% of max HP)", 
        pull.damageTaken, pull.analysis.metrics.damageTakenPercent * 100))
    table.insert(lines, string.format("Healing Received: %.0f", pull.healingReceived))
    table.insert(lines, string.format("Mobs Killed: %d", #pull.mobsKilled))
    table.insert(lines, string.format("Cooldowns Used: %d", #pull.cooldownsUsed))
    table.insert(lines, string.format("Lowest Health: %.0f%%", pull.minHealthPercent * 100))
    
    if #pull.analysis.issues > 0 then
        table.insert(lines, "\nIssues:")
        for _, issue in ipairs(pull.analysis.issues) do
            table.insert(lines, "• " .. issue)
        end
    end
    
    if #pull.analysis.suggestions > 0 then
        table.insert(lines, "\nSuggestions:")
        for _, suggestion in ipairs(pull.analysis.suggestions) do
            table.insert(lines, "• " .. suggestion)
        end
    end
    
    self.summaryFrame.content:SetText(table.concat(lines, "\n"))
    self.summaryFrame:Show()
    
    -- Auto-hide after 10 seconds
    C_Timer.After(10, function()
        if self.summaryFrame:IsShown() then
            self.summaryFrame:Hide()
        end
    end)
end

function PA:GetPullStats()
    local stats = {
        totalPulls = #self.pullHistory,
        averageDuration = 0,
        averageDamageTaken = 0,
        gradeDistribution = {A = 0, B = 0, C = 0, D = 0, F = 0},
        deaths = 0
    }
    
    if #self.pullHistory > 0 then
        local totalDuration = 0
        local totalDamage = 0
        
        for _, pull in ipairs(self.pullHistory) do
            totalDuration = totalDuration + pull.duration
            totalDamage = totalDamage + pull.damageTaken
            
            if pull.analysis and pull.analysis.grade then
                stats.gradeDistribution[pull.analysis.grade] = 
                    stats.gradeDistribution[pull.analysis.grade] + 1
            end
            
            if pull.died then
                stats.deaths = stats.deaths + 1
            end
        end
        
        stats.averageDuration = totalDuration / #self.pullHistory
        stats.averageDamageTaken = totalDamage / #self.pullHistory
    end
    
    return stats
end

function PA:GetPullHistory(count)
    count = count or 10
    local recent = {}
    local start = math.max(1, #self.pullHistory - count + 1)
    
    for i = start, #self.pullHistory do
        table.insert(recent, self.pullHistory[i])
    end
    
    return recent
end

function PA:ResetPullHistory()
    self.pullHistory = {}
    if TCP.debug then
        print("TCP: Pull history cleared")
    end
end

-- Initialize
PA:Initialize()
