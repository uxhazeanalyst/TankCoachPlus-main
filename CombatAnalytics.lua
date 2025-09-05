-- CombatAnalytics.lua - Live Combat Damage Trendline and Predictive Analytics
local addonName, TCP = ...

TCP.CombatAnalytics = {}
local CA = TCP.CombatAnalytics

-- Analytics data
CA.combatData = {
    currentSession = {},
    damageHistory = {},
    cooldownHistory = {},
    pullMetrics = {}
}

CA.displayData = {
    damagePoints = {},
    cooldownMarkers = {},
    timeWindow = 30, -- seconds to display
    maxDataPoints = 150 -- maximum points on graph
}

CA.predictions = {
    estimatedTimeToComplete = 0,
    suggestedCooldowns = {},
    statWeightRecommendations = {},
    skipOpportunities = {}
}

function CA:Initialize()
    self:CreateAnalyticsFrame()
    self:SetupEventHandlers()
    self:InitializePredictionEngine()
end

function CA:CreateAnalyticsFrame()
    -- Main analytics frame (appears in combat, fades out after)
    self.analyticsFrame = CreateFrame("Frame", "TCPCombatAnalytics", UIParent)
    self.analyticsFrame:SetSize(600, 300)
    self.analyticsFrame:SetPoint("TOP", 0, -100)
    self.analyticsFrame:SetFrameStrata("HIGH")
    self.analyticsFrame:Hide()
    
    -- Background with slight transparency
    self.analyticsFrame.bg = self.analyticsFrame:CreateTexture(nil, "BACKGROUND")
    self.analyticsFrame.bg:SetAllPoints()
    self.analyticsFrame.bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Border
    self.analyticsFrame.border = CreateFrame("Frame", nil, self.analyticsFrame, "BackdropTemplate")
    self.analyticsFrame.border:SetAllPoints()
    if self.analyticsFrame.border.SetBackdrop then
        self.analyticsFrame.border:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        self.analyticsFrame.border:SetBackdropBorderColor(0.8, 0.6, 0, 0.8)
    end
    
    -- Title
    self.title = self.analyticsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.title:SetPoint("TOP", 0, -10)
    self.title:SetText("Combat Analytics")
    
    -- Create graph area
    self:CreateTrendGraph()
    
    -- Create prediction panel
    self:CreatePredictionPanel()
    
    -- Create controls
    self:CreateControls()
    
    -- Fade animation
    self.fadeGroup = self.analyticsFrame:CreateAnimationGroup()
    self.fadeOut = self.fadeGroup:CreateAnimation("Alpha")
    self.fadeOut:SetFromAlpha(1)
    self.fadeOut:SetToAlpha(0)
    self.fadeOut:SetDuration(3)
    self.fadeOut:SetStartDelay(5) -- Wait 5 seconds after combat ends
    
    self.fadeGroup:SetScript("OnFinished", function()
        self.analyticsFrame:Hide()
    end)
    
    -- Store reference
    TCP.CombatAnalyticsUI = self.analyticsFrame
end

function CA:CreateTrendGraph()
    -- Graph container
    self.graphFrame = CreateFrame("Frame", nil, self.analyticsFrame)
    self.graphFrame:SetPoint("TOPLEFT", 20, -30)
    self.graphFrame:SetSize(360, 180)
    
    -- Graph background
    self.graphFrame.bg = self.graphFrame:CreateTexture(nil, "BACKGROUND")
    self.graphFrame.bg:SetAllPoints()
    self.graphFrame.bg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
    
    -- Grid lines (simplified)
    self.gridLines = {}
    for i = 1, 4 do
        local line = self.graphFrame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        line:SetPoint("LEFT", 5, 0)
        line:SetPoint("RIGHT", -5, 0)
        line:SetPoint("TOP", 0, -(i * 36)) -- Every 25% of graph height
        table.insert(self.gridLines, line)
    end
    
    -- Time axis labels
    self.timeLabels = {}
    for i = 0, 6 do
        local label = self.graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", (i * 60) - 180, -15)
        label:SetText(string.format("-%ds", 30 - (i * 5)))
        label:SetTextColor(0.7, 0.7, 0.7)
        table.insert(self.timeLabels, label)
    end
    
    -- Y-axis label
    self.yAxisLabel = self.graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.yAxisLabel:SetPoint("LEFT", -15, 90)
    self.yAxisLabel:SetText("DPS")
    self.yAxisLabel:SetTextColor(0.7, 0.7, 0.7)
    
    -- Damage trendline data points
    self.damagePoints = {}
    self.cooldownMarkers = {}
end

function CA:CreatePredictionPanel()
    -- Prediction panel on the right
    self.predictionPanel = CreateFrame("Frame", nil, self.analyticsFrame)
    self.predictionPanel:SetPoint("TOPRIGHT", -20, -30)
    self.predictionPanel:SetSize(200, 180)
    
    -- Panel background
    self.predictionPanel.bg = self.predictionPanel:CreateTexture(nil, "BACKGROUND")
    self.predictionPanel.bg:SetAllPoints()
    self.predictionPanel.bg:SetColorTexture(0.15, 0.1, 0.1, 0.8)
    
    -- Prediction title
    self.predTitle = self.predictionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.predTitle:SetPoint("TOP", 0, -5)
    self.predTitle:SetText("Predictions")
    
    -- Prediction content
    self.predictionContent = self.predictionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.predictionContent:SetPoint("TOPLEFT", 10, -25)
    self.predictionContent:SetPoint("BOTTOMRIGHT", -10, 10)
    self.predictionContent:SetJustifyH("LEFT")
    self.predictionContent:SetJustifyV("TOP")
    self.predictionContent:SetTextColor(0.9, 0.9, 0.9)
end

function CA:CreateControls()
    -- Control panel at bottom
    self.controlPanel = CreateFrame("Frame", nil, self.analyticsFrame)
    self.controlPanel:SetPoint("BOTTOM", 0, 10)
    self.controlPanel:SetSize(580, 30)
    
    -- Toggle button
    self.toggleBtn = CreateFrame("Button", nil, self.controlPanel, "GameMenuButtonTemplate")
    self.toggleBtn:SetSize(80, 20)
    self.toggleBtn:SetPoint("LEFT", 10, 0)
    self.toggleBtn:SetText("Hide")
    self.toggleBtn:SetScript("OnClick", function() self:ToggleVisibility() end)
    
    -- Time window slider
    self.timeSlider = CreateFrame("Slider", nil, self.controlPanel, "OptionsSliderTemplate")
    self.timeSlider:SetPoint("LEFT", 100, 0)
    self.timeSlider:SetSize(150, 20)
    self.timeSlider:SetMinMaxValues(10, 60)
    self.timeSlider:SetValue(30)
    self.timeSlider:SetValueStep(5)
    self.timeSlider.Text:SetText("30s Window")
    self.timeSlider:SetScript("OnValueChanged", function(_, value)
        self.displayData.timeWindow = value
        self.timeSlider.Text:SetText(string.format("%.0fs Window", value))
        self:UpdateTimeLabels()
    end)
    
    -- Current status
    self.statusText = self.controlPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.statusText:SetPoint("RIGHT", -10, 0)
    self.statusText:SetTextColor(1, 1, 0)
end

function CA:SetupEventHandlers()
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Enter combat
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leave combat
    self.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            self:StartCombatAnalytics()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:EndCombatAnalytics()
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:ProcessCombatEvent(...)
        end
    end)
end

function CA:InitializePredictionEngine()
    -- Initialize machine learning-like prediction algorithms
    self.predictionEngine = {
        damagePatterns = {},
        cooldownEffectiveness = {},
        timeToKillModels = {},
        statWeightCorrelations = {}
    }
end

function CA:StartCombatAnalytics()
    -- Reset for new combat session
    self.combatData.currentSession = {
        startTime = GetTime(),
        damageEvents = {},
        cooldownEvents = {},
        dpsWindow = {}
    }
    
    self.displayData.damagePoints = {}
    self.displayData.cooldownMarkers = {}
    
    -- Show the analytics frame
    self.analyticsFrame:Show()
    self.analyticsFrame:SetAlpha(1)
    self.fadeGroup:Stop()
    
    -- Start data collection timer
    self.updateTimer = C_Timer.NewTicker(0.2, function() -- Update 5 times per second
        self:UpdateAnalytics()
    end)
    
    if TCP.debug then
        print("TCP: Combat analytics started")
    end
end

function CA:EndCombatAnalytics()
    -- Stop data collection
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Finalize combat session
    if self.combatData.currentSession then
        self.combatData.currentSession.endTime = GetTime()
        self.combatData.currentSession.duration = 
            self.combatData.currentSession.endTime - self.combatData.currentSession.startTime
        
        -- Store session for analysis
        table.insert(self.combatData.pullMetrics, self.combatData.currentSession)
        
        -- Generate final predictions
        self:GenerateFinalPredictions()
    end
    
    -- Start fade out animation
    self.fadeGroup:Play()
    
    if TCP.debug then
        print("TCP: Combat analytics ended. Duration:", 
              string.format("%.1fs", self.combatData.currentSession.duration))
    end
end

function CA:ProcessCombatEvent()
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName, _, amount = CombatLogGetCurrentEventInfo()
    
    local playerGUID = UnitGUID("player")
    if not playerGUID or not self.combatData.currentSession then return end
    
    -- Track damage taken by player
    if (subEvent == "SPELL_DAMAGE" or subEvent == "SWING_DAMAGE" or subEvent == "RANGE_DAMAGE") 
        and destGUID == playerGUID then
        
        local damageEvent = {
            timestamp = timestamp,
            amount = amount or 0,
            source = sourceName or "Unknown",
            spell = spellName or "Melee"
        }
        
        table.insert(self.combatData.currentSession.damageEvents, damageEvent)
    end
    
    -- Track cooldown usage by player
    if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
        if TCP.CooldownTracker then
            local _, class = UnitClass("player")
            local defensives = TCP.CooldownTracker.MAJOR_DEFENSIVES[class] or {}
            if defensives[spellName] then
                local cooldownEvent = {
                    timestamp = timestamp,
                    spell = spellName,
                    reduction = defensives[spellName].reduction,
                    duration = defensives[spellName].duration
                }
                
                table.insert(self.combatData.currentSession.cooldownEvents, cooldownEvent)
            end
        end
    end
end

function CA:UpdateAnalytics()
    if not self.combatData.currentSession then return end
    
    local currentTime = GetTime()
    local combatDuration = currentTime - self.combatData.currentSession.startTime
    
    -- Calculate current DPS window (last 3 seconds)
    local windowDPS = self:CalculateWindowDPS(3)
    
    -- Add to display data
    table.insert(self.displayData.damagePoints, {
        time = combatDuration,
        dps = windowDPS,
        timestamp = currentTime
    })
    
    -- Limit data points for performance
    while #self.displayData.damagePoints > self.displayData.maxDataPoints do
        table.remove(self.displayData.damagePoints, 1)
    end
    
    -- Update visual display
    self:UpdateTrendGraph()
    
    -- Generate real-time predictions
    self:UpdatePredictions()
    
    -- Update status
    self.statusText:SetText(string.format("DPS: %.0f | Time: %.1fs", windowDPS, combatDuration))
end

function CA:CalculateWindowDPS(windowSeconds)
    if not self.combatData.currentSession.damageEvents then return 0 end
    
    local currentTime = GetTime()
    local windowStart = currentTime - windowSeconds
    local totalDamage = 0
    
    for _, event in ipairs(self.combatData.currentSession.damageEvents) do
        if event.timestamp >= windowStart then
            totalDamage = totalDamage + event.amount
        end
    end
    
    return totalDamage / windowSeconds
end

function CA:UpdateTrendGraph()
    -- Clear previous graph points
    for _, point in pairs(self.damagePoints) do
        if point.texture then
            point.texture:Hide()
        end
    end
    
    -- Clear previous cooldown markers
    for _, marker in pairs(self.cooldownMarkers) do
        if marker.texture then
            marker.texture:Hide()
        end
    end
    
    if #self.displayData.damagePoints < 2 then return end
    
    -- Find max DPS for scaling
    local maxDPS = 0
    for _, point in ipairs(self.displayData.damagePoints) do
        if point.dps > maxDPS then
            maxDPS = point.dps
        end
    end
    
    if maxDPS == 0 then return end
    
    -- Draw damage trendline
    local graphWidth = self.graphFrame:GetWidth() - 10
    local graphHeight = self.graphFrame:GetHeight() - 20
    
    for i, point in ipairs(self.displayData.damagePoints) do
        -- Create or reuse point texture
        if not self.damagePoints[i] then
            self.damagePoints[i] = {}
            self.damagePoints[i].texture = self.graphFrame:CreateTexture(nil, "OVERLAY")
            self.damagePoints[i].texture:SetSize(3, 3)
            self.damagePoints[i].texture:SetColorTexture(1, 0.8, 0, 0.8) -- Yellow points
        end
        
        local texture = self.damagePoints[i].texture
        
        -- Calculate position
        local timePercent = math.min(point.time / self.displayData.timeWindow, 1)
        local dpsPercent = point.dps / maxDPS
        
        local x = timePercent * graphWidth
        local y = dpsPercent * graphHeight
        
        texture:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", x, y + 10)
        texture:Show()
        
        -- Connect points with lines (simplified)
        if i > 1 then
            self:DrawLineBetweenPoints(i - 1, i)
        end
    end
    
    -- Draw cooldown markers
    self:DrawCooldownMarkers()
end

function CA:DrawLineBetweenPoints(fromIndex, toIndex)
    -- Simplified line drawing between data points
    local lineKey = string.format("line_%d_%d", fromIndex, toIndex)
    
    -- This would be more complex in a full implementation
    -- For now, we'll rely on the point density to show the trend
end

function CA:DrawCooldownMarkers()
    if not self.combatData.currentSession.cooldownEvents then return end
    
    local currentTime = GetTime()
    local combatStart = self.combatData.currentSession.startTime
    local graphWidth = self.graphFrame:GetWidth() - 10
    local graphHeight = self.graphFrame:GetHeight() - 20
    
    for i, cooldown in ipairs(self.combatData.currentSession.cooldownEvents) do
        local relativeTime = cooldown.timestamp - combatStart
        
        -- Only show cooldowns within our time window
        if relativeTime <= self.displayData.timeWindow then
            -- Create or reuse cooldown marker
            if not self.cooldownMarkers[i] then
                self.cooldownMarkers[i] = {}
                self.cooldownMarkers[i].texture = self.graphFrame:CreateTexture(nil, "OVERLAY")
                self.cooldownMarkers[i].texture:SetSize(2, graphHeight)
                self.cooldownMarkers[i].texture:SetColorTexture(0, 1, 0, 0.6) -- Green vertical line
            end
            
            local marker = self.cooldownMarkers[i].texture
            local timePercent = relativeTime / self.displayData.timeWindow
            local x = timePercent * graphWidth
            
            marker:SetPoint("BOTTOMLEFT", self.graphFrame, "BOTTOMLEFT", x, 10)
            marker:Show()
        end
    end
end

function CA:UpdatePredictions()
    if not self.combatData.currentSession then return end
    
    -- Generate predictions based on current data
    self:PredictTimeToComplete()
    self:SuggestOptimalCooldowns()
    self:AnalyzeStatWeights()
    self:IdentifySkipOpportunities()
    
    -- Update prediction display
    self:UpdatePredictionDisplay()
end

function CA:PredictTimeToComplete()
    -- Analyze damage patterns and predict time to kill current pull
    local currentDPS = self:CalculateWindowDPS(5) -- 5-second window
    if currentDPS <= 0 then return end
    
    -- Estimate remaining mob HP (simplified)
    local estimatedRemainingHP = 100000 -- This would be calculated from nameplate data
    self.predictions.estimatedTimeToComplete = estimatedRemainingHP / currentDPS
end

function CA:SuggestOptimalCooldowns()
    -- Analyze damage spikes and suggest when to use cooldowns
    self.predictions.suggestedCooldowns = {}
    
    if not self.combatData.currentSession.damageEvents then return end
    
    -- Look for damage spike patterns
    local recentDamage = self:GetRecentDamageSpikes(10) -- Last 10 seconds
    local averageDamage = self:CalculateWindowDPS(10)
    
    -- If damage is spiking, suggest defensive cooldowns
    for _, spike in ipairs(recentDamage) do
        if spike.amount > averageDamage * 2 then
            table.insert(self.predictions.suggestedCooldowns, {
                type = "defensive",
                urgency = "high",
                reason = "Damage spike detected"
            })
            break
        end
    end
end

function CA:AnalyzeStatWeights()
    -- Analyze current combat effectiveness and suggest stat priorities
    self.predictions.statWeightRecommendations = {}
    
    -- Look at damage taken vs healing received patterns
    local damageRate = self:CalculateWindowDPS(30)
    local survivalMargin = UnitHealth("player") / UnitHealthMax("player")
    
    if damageRate > 50000 and survivalMargin < 0.6 then
        table.insert(self.predictions.statWeightRecommendations, {
            stat = "Versatility",
            priority = "high",
            reason = "High damage intake detected"
        })
    end
end

function CA:IdentifySkipOpportunities()
    -- Analyze mob positioning and damage to suggest potential skips
    self.predictions.skipOpportunities = {}
    
    -- This would analyze the current pull efficiency
    local combatTime = GetTime() - self.combatData.currentSession.startTime
    local dps = self:CalculateWindowDPS(combatTime)
    
    if combatTime > 30 and dps < 100000 then
        table.insert(self.predictions.skipOpportunities, {
            type = "slow_pull",
            suggestion = "Consider skipping similar packs",
            efficiency = "low"
        })
    end
end

function CA:UpdatePredictionDisplay()
    local lines = {}
    
    -- Time to complete
    if self.predictions.estimatedTimeToComplete > 0 then
        table.insert(lines, string.format("|cFFFFFF00ETC: %.1fs|r", self.predictions.estimatedTimeToComplete))
    end
    
    -- Cooldown suggestions
    for _, suggestion in ipairs(self.predictions.suggestedCooldowns) do
        local color = suggestion.urgency == "high" and "|cFFFF4444" or "|cFFFFAA00"
        table.insert(lines, color .. "Use Defensive!|r")
    end
    
    -- Stat recommendations
    for _, rec in ipairs(self.predictions.statWeightRecommendations) do
        local color = rec.priority == "high" and "|cFF44FF44" or "|cFFAAFFAA"
        table.insert(lines, color .. "Focus: " .. rec.stat .. "|r")
    end
    
    -- Skip opportunities
    for _, skip in ipairs(self.predictions.skipOpportunities) do
        table.insert(lines, "|cFFFF8844" .. skip.suggestion .. "|r")
    end
    
    if #lines == 0 then
        table.insert(lines, "|cFFAAAAAACombat data building...|r")
    end
    
    self.predictionContent:SetText(table.concat(lines, "\n"))
end

function CA:GetRecentDamageSpikes(seconds)
    local spikes = {}
    local currentTime = GetTime()
    local cutoff = currentTime - seconds
    
    for _, event in ipairs(self.combatData.currentSession.damageEvents or {}) do
        if event.timestamp >= cutoff and event.amount > 20000 then -- Arbitrary spike threshold
            table.insert(spikes, event)
        end
    end
    
    return spikes
end

function CA:GenerateFinalPredictions()
    -- Generate comprehensive analysis after combat ends
    if not self.combatData.currentSession then return end
    
    local session = self.combatData.currentSession
    local totalDamage = 0
    local highestSpike = 0
    
    for _, event in ipairs(session.damageEvents or {}) do
        totalDamage = totalDamage + event.amount
        if event.amount > highestSpike then
            highestSpike = event.amount
        end
    end
    
    local avgDPS = totalDamage / session.duration
    local cooldownsUsed = #session.cooldownEvents
    
    -- Store analysis for future predictions
    table.insert(self.combatData.pullMetrics, {
        duration = session.duration,
        totalDamage = totalDamage,
        avgDPS = avgDPS,
        highestSpike = highestSpike,
        cooldownsUsed = cooldownsUsed,
        timestamp = session.endTime
    })
    
    if TCP.debug then
        print("TCP: Final combat analysis:")
        print("  Avg DPS:", string.format("%.0f", avgDPS))
        print("  Highest Spike:", string.format("%.0f", highestSpike))
        print("  Cooldowns Used:", cooldownsUsed)
    end
end

function CA:ToggleVisibility()
    if self.analyticsFrame:GetAlpha() > 0.5 then
        -- Fade to semi-transparent
        self.analyticsFrame:SetAlpha(0.3)
        self.toggleBtn:SetText("Show")
    else
        -- Restore full visibility
        self.analyticsFrame:SetAlpha(1)
        self.toggleBtn:SetText("Hide")
    end
end

function CA:UpdateTimeLabels()
    local timeWindow = self.displayData.timeWindow
    for i, label in ipairs(self.timeLabels) do
        local timeValue = timeWindow - ((i-1) * (timeWindow / 6))
        label:SetText(string.format("-%ds", timeValue))
    end
end

function CA:GetAnalyticsData()
    return {
        currentSession = self.combatData.currentSession,
        predictions = self.predictions,
        pullMetrics = self.combatData.pullMetrics
    }
end

-- Initialize
CA:Initialize()
