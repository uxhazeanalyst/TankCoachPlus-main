-- StatisticsDashboard.lua - Advanced Statistics Dashboard
local addonName, TCP = ...

TCP.StatisticsDashboard = {}
local SD = TCP.StatisticsDashboard

-- Statistics storage
SD.sessionStats = {
    startTime = GetTime(),
    totalPulls = 0,
    totalDamageTaken = 0,
    totalHealingReceived = 0,
    cooldownsUsed = {},
    deathCount = 0,
    keystoneLevel = 0,
    dungeonTime = 0
}

SD.performanceMetrics = {}
SD.comparisonData = {}

function SD:Initialize()
    self:CreateDashboardFrame()
    self:LoadSavedData()
    
    -- Update timer for real-time metrics
    self.updateTimer = C_Timer.NewTicker(1.0, function()
        self:UpdateRealTimeMetrics()
    end)
end

function SD:CreateDashboardFrame()
    -- Main dashboard frame
    self.dashFrame = CreateFrame("Frame", "TCPDashboard", UIParent, "BasicFrameTemplate")
    self.dashFrame:SetSize(600, 450)
    self.dashFrame:SetPoint("CENTER")
    self.dashFrame:SetMovable(true)
    self.dashFrame:EnableMouse(true)
    self.dashFrame:RegisterForDrag("LeftButton")
    self.dashFrame:SetScript("OnDragStart", self.dashFrame.StartMoving)
    self.dashFrame:SetScript("OnDragStop", self.dashFrame.StopMovingOrSizing)
    self.dashFrame:Hide()
    
    -- Title
    self.dashFrame.title = self.dashFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.dashFrame.title:SetPoint("TOP", 0, -8)
    self.dashFrame.title:SetText("TankCoachPlus Dashboard")
    
    -- Tab system for different views
    self:CreateTabSystem()
    
    -- Content area
    self.contentFrame = CreateFrame("ScrollFrame", nil, self.dashFrame, "UIPanelScrollFrameTemplate")
    self.contentFrame:SetPoint("TOPLEFT", 10, -60)
    self.contentFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    self.contentChild = CreateFrame("Frame", nil, self.contentFrame)
    self.contentChild:SetSize(550, 1)
    self.contentFrame:SetScrollChild(self.contentChild)
    
    -- Store reference
    TCP.DashboardUI = self.dashFrame
end

function SD:CreateTabSystem()
    self.tabs = {}
    local tabData = {
        {name = "Overview", key = "overview"},
        {name = "Performance", key = "performance"},
        {name = "Cooldowns", key = "cooldowns"},
        {name = "Comparison", key = "comparison"}
    }
    
    for i, data in ipairs(tabData) do
        local tab = CreateFrame("Button", nil, self.dashFrame, "ChatTabTemplate")
        tab:SetPoint("TOPLEFT", 10 + (i-1) * 120, -30)
        tab:SetSize(120, 25)
        tab:SetText(data.name)
        tab.key = data.key
        tab:SetScript("OnClick", function() self:ShowTab(data.key) end)
        self.tabs[data.key] = tab
    end
    
    self.activeTab = "overview"
end

function SD:ShowTab(tabKey)
    -- Update tab appearance
    for key, tab in pairs(self.tabs) do
        if key == tabKey then
            tab:SetScript("OnEnter", nil)
            tab:SetScript("OnLeave", nil)
        else
            tab:SetScript("OnEnter", ChatTab_OnEnter)
            tab:SetScript("OnLeave", ChatTab_OnLeave)
        end
    end
    
    self.activeTab = tabKey
    self:RefreshContent()
end

function SD:RefreshContent()
    local content = ""
    
    if self.activeTab == "overview" then
        content = self:GenerateOverviewContent()
    elseif self.activeTab == "performance" then
        content = self:GeneratePerformanceContent()
    elseif self.activeTab == "cooldowns" then
        content = self:GenerateCooldownContent()
    elseif self.activeTab == "comparison" then
        content = self:GenerateComparisonContent()
    end
    
    self:SetContentText(content)
end

function SD:SetContentText(content)
    if not self.contentText then
        self.contentText = self.contentChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self.contentText:SetPoint("TOPLEFT", 10, -10)
        self.contentText:SetWidth(520)
        self.contentText:SetJustifyH("LEFT")
        self.contentText:SetJustifyV("TOP")
    end
    
    self.contentText:SetText(content)
    local textHeight = self.contentText:GetStringHeight()
    self.contentChild:SetHeight(math.max(textHeight + 50, self.contentFrame:GetHeight()))
end

function SD:GenerateOverviewContent()
    local lines = {}
    local stats = self.sessionStats
    local currentTime = GetTime()
    local sessionDuration = currentTime - stats.startTime
    
    table.insert(lines, "|cFFFFD700=== Session Overview ===|r")
    table.insert(lines, string.format("Session Duration: %s", self:FormatTime(sessionDuration)))
    table.insert(lines, string.format("Total Pulls: %d", stats.totalPulls))
    
    if stats.totalPulls > 0 then
        table.insert(lines, string.format("Average Damage/Pull: %.0f", stats.totalDamageTaken / stats.totalPulls))
        table.insert(lines, string.format("Average Healing/Pull: %.0f", stats.totalHealingReceived / stats.totalPulls))
    end
    
    table.insert(lines, string.format("Deaths: %d", stats.deathCount))
    
    -- Current keystone info
    if stats.keystoneLevel > 0 then
        table.insert(lines, string.format("Current Key: +%d", stats.keystoneLevel))
    end
    
    table.insert(lines, "")
    table.insert(lines, "|cFFFFD700=== Live Metrics ===|r")
    
    -- Get live data from other modules
    if TCP.CooldownTracker then
        local cdStats = TCP.CooldownTracker:GetCooldownStats()
        table.insert(lines, string.format("Defensives Used: %d", cdStats.totalDefensivesUsed))
    end
    
    if TCP.ThreatAnalyzer then
        local threatStats = TCP.ThreatAnalyzer:GetThreatStats()
        table.insert(lines, string.format("Aggro Losses: %d", threatStats.aggroLosses))
        table.insert(lines, string.format("Threat Actions: %d", threatStats.totalThreatActions))
    end
    
    if TCP.PullAnalyzer then
        local pullStats = TCP.PullAnalyzer:GetPullStats()
        table.insert(lines, string.format("Pull Grade Average: %s", self:CalculateAverageGrade(pullStats.gradeDistribution)))
        table.insert(lines, string.format("Average Pull Time: %.1fs", pullStats.averageDuration))
    end
    
    -- Real-time status
    table.insert(lines, "")
    table.insert(lines, "|cFFFFD700=== Current Status ===|r")
    table.insert(lines, "Health: " .. UnitHealth("player") .. "/" .. UnitHealthMax("player"))
    
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        table.insert(lines, "Instance: " .. (GetInstanceInfo() or "Unknown"))
        table.insert(lines, "Type: " .. instanceType)
    else
        table.insert(lines, "Location: Open World")
    end
    
    return table.concat(lines, "\n")
end

function SD:GeneratePerformanceContent()
    local lines = {}
    
    table.insert(lines, "|cFFFFD700=== Performance Analysis ===|r")
    
    -- Damage taken over time graph (text representation)
    table.insert(lines, "\n|cFF87CEEBDamage Taken Over Time:|r")
    if TCP.PullAnalyzer and #TCP.PullAnalyzer.pullHistory > 0 then
        local recent = {}
        for i = math.max(1, #TCP.PullAnalyzer.pullHistory - 9), #TCP.PullAnalyzer.pullHistory do
            table.insert(recent, TCP.PullAnalyzer.pullHistory[i])
        end
        
        local maxDamage = 0
        for _, pull in ipairs(recent) do
            if pull.damageTaken > maxDamage then
                maxDamage = pull.damageTaken
            end
        end
        
        for i, pull in ipairs(recent) do
            local barLength = maxDamage > 0 and math.floor((pull.damageTaken / maxDamage) * 20) or 0
            local bar = string.rep("█", barLength) .. string.rep("░", 20 - barLength)
            local grade = pull.analysis and pull.analysis.grade or "?"
            table.insert(lines, string.format("Pull %d: %s [%s] %.0f dmg", 
                pull.pullNumber, bar, grade, pull.damageTaken))
        end
    else
        table.insert(lines, "No pull data available")
    end
    
    -- Cooldown efficiency
    table.insert(lines, "\n|cFF87CEEBCooldown Usage Efficiency:|r")
    if TCP.CooldownTracker then
        local recentCooldowns = self:GetRecentCooldownUsage()
        if #recentCooldowns > 0 then
            for _, cd in ipairs(recentCooldowns) do
                table.insert(lines, string.format("• %s: Used %d times", cd.name, cd.count))
            end
        else
            table.insert(lines, "No recent cooldown usage data")
        end
    end
    
    -- Threat performance
    table.insert(lines, "\n|cFF87CEEBThreat Management:|r")
    if TCP.ThreatAnalyzer then
        local threatStats = TCP.ThreatAnalyzer:GetThreatStats()
        local efficiency = threatStats.totalThreatActions > 0 and 
            (1 - (threatStats.aggroLosses / threatStats.totalThreatActions)) or 0
        table.insert(lines, string.format("Threat Efficiency: %.1f%%", efficiency * 100))
        table.insert(lines, string.format("Average Threat/Action: %.1f", threatStats.averageThreatPerAction))
    end
    
    -- Positioning analysis
    table.insert(lines, "\n|cFF87CEEBPositioning:|r")
    if TCP.PositioningAnalyzer then
        local posStats = TCP.PositioningAnalyzer:GetPositioningStats()
        if posStats.averageHealerDistance > 0 then
            table.insert(lines, string.format("Avg Healer Distance: %.1fy", posStats.averageHealerDistance))
        end
        if posStats.averageGroupDistance > 0 then
            table.insert(lines, string.format("Avg Group Distance: %.1fy", posStats.averageGroupDistance))
        end
        table.insert(lines, string.format("Positioning Issues: %d", posStats.positioningIssues))
    end
    
    return table.concat(lines, "\n")
end

function SD:GenerateCooldownContent()
    local lines = {}
    
    table.insert(lines, "|cFFFFD700=== Cooldown Analysis ===|r")
    
    if TCP.CooldownTracker then
        local _, class = UnitClass("player")
        local defensives = TCP.CooldownTracker.MAJOR_DEFENSIVES[class] or {}
        
        table.insert(lines, "\n|cFF87CEEBAvailable Defensive Cooldowns:|r")
        for spellName, data in pairs(defensives) do
            local status = "Ready"
            local cooldownData = TCP.CooldownTracker.activeCooldowns[spellName]
            if cooldownData then
                local remaining = cooldownData.cooldownEnd - GetTime()
                if remaining > 0 then
                    status = string.format("Cooldown: %.0fs", remaining)
                elseif GetTime() < cooldownData.endTime then
                    status = "Active"
                end
            end
            
            table.insert(lines, string.format("• %s: %s (%.0f%% DR, %ds duration)", 
                spellName, status, data.reduction * 100, data.duration))
        end
        
        -- Usage statistics
        table.insert(lines, "\n|cFF87CEEBUsage Statistics:|r")
        local usage = self:CalculateCooldownUsageStats()
        for spellName, stats in pairs(usage) do
            table.insert(lines, string.format("• %s: %d uses, %.1f avg time between", 
                spellName, stats.uses, stats.avgTimeBetween))
        end
        
        -- Recommendations
        table.insert(lines, "\n|cFF87CEEBRecommendations:|r")
        local recommendations = self:GetCooldownRecommendations()
        for _, rec in ipairs(recommendations) do
            table.insert(lines, "• " .. rec)
        end
    else
        table.insert(lines, "Cooldown Tracker not available")
    end
    
    return table.concat(lines, "\n")
end

function SD:GenerateComparisonContent()
    local lines = {}
    
    table.insert(lines, "|cFFFFD700=== Performance Comparison ===|r")
    
    -- Compare with previous sessions
    table.insert(lines, "\n|cFF87CEEBSession vs Previous:|r")
    local comparison = self:CompareWithPrevious()
    if comparison then
        local damageDiff = comparison.damageTakenDiff
        local colorCode = damageDiff > 0 and "|cFFFF6B6B" or "|cFF6BCF7F"
        table.insert(lines, string.format("Damage Taken: %s%.0f%% vs last session|r", 
            colorCode, math.abs(damageDiff)))
        
        local deathDiff = comparison.deathDiff
        colorCode = deathDiff > 0 and "|cFFFF6B6B" or "|cFF6BCF7F"
        table.insert(lines, string.format("Deaths: %s%+d vs last session|r", colorCode, deathDiff))
        
        local gradeDiff = comparison.avgGradeDiff
        colorCode = gradeDiff > 0 and "|cFF6BCF7F" or "|cFFFF6B6B"
        table.insert(lines, string.format("Average Grade: %s%.1f vs last session|r", colorCode, gradeDiff))
    else
        table.insert(lines, "No previous session data for comparison")
    end
    
    -- Spec comparison (if data available)
    table.insert(lines, "\n|cFF87CEEBSpec Performance:|r")
    local specData = self:GetSpecPerformanceData()
    if specData then
        table.insert(lines, string.format("Your %s Performance:", specData.specName))
        table.insert(lines, string.format("• Damage Taken: %.0f (Avg: %.0f)", 
            specData.yourDamage, specData.avgDamage))
        table.insert(lines, string.format("• Cooldown Usage: %.1f/min (Avg: %.1f/min)", 
            specData.yourCDRate, specData.avgCDRate))
        table.insert(lines, string.format("• Threat Losses: %d (Avg: %.1f)", 
            specData.yourThreatLosses, specData.avgThreatLosses))
    else
        table.insert(lines, "Building performance baseline...")
    end
    
    -- Key level progression
    table.insert(lines, "\n|cFF87CEEBProgression Tracking:|r")
    local progression = self:GetProgressionData()
    if #progression > 0 then
        table.insert(lines, "Recent Key Levels:")
        for i, data in ipairs(progression) do
            if i <= 5 then -- Show last 5
                local success = data.success and "✓" or "✗"
                table.insert(lines, string.format("• +%d %s %s - Grade: %s", 
                    data.level, data.dungeon, success, data.grade))
            end
        end
    else
        table.insert(lines, "No keystone progression data yet")
    end
    
    return table.concat(lines, "\n")
end

function SD:UpdateRealTimeMetrics()
    if not UnitExists("player") then return end
    
    -- Update session stats from other modules
    if TCP.PullAnalyzer then
        self.sessionStats.totalPulls = #TCP.PullAnalyzer.pullHistory
        
        local totalDamage = 0
        local totalHealing = 0
        local deaths = 0
        
        for _, pull in ipairs(TCP.PullAnalyzer.pullHistory) do
            totalDamage = totalDamage + pull.damageTaken
            totalHealing = totalHealing + pull.healingReceived
            if pull.died then deaths = deaths + 1 end
        end
        
        self.sessionStats.totalDamageTaken = totalDamage
        self.sessionStats.totalHealingReceived = totalHealing
        self.sessionStats.deathCount = deaths
    end
    
    -- Update keystone level if in M+
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local keystoneInfo = C_ChallengeMode.GetActiveKeystoneInfo()
        if keystoneInfo then
            local level = keystoneInfo.level or keystoneInfo[1]
            if level then
                self.sessionStats.keystoneLevel = level
            end
        end
    end
    
    -- Store performance snapshot every minute
    if GetTime() - (self.lastSnapshot or 0) > 60 then
        self:TakePerformanceSnapshot()
        self.lastSnapshot = GetTime()
    end
end

function SD:TakePerformanceSnapshot()
    local snapshot = {
        timestamp = GetTime(),
        totalPulls = self.sessionStats.totalPulls,
        totalDamage = self.sessionStats.totalDamageTaken,
        totalHealing = self.sessionStats.totalHealingReceived,
        deaths = self.sessionStats.deathCount,
        keystoneLevel = self.sessionStats.keystoneLevel
    }
    
    table.insert(self.performanceMetrics, snapshot)
    
    -- Keep only last 100 snapshots
    while #self.performanceMetrics > 100 do
        table.remove(self.performanceMetrics, 1)
    end
end

function SD:GetRecentCooldownUsage()
    local usage = {}
    
    if TCP.PullAnalyzer then
        local cooldownCount = {}
        local recentPulls = TCP.PullAnalyzer:GetPullHistory(10) -- Last 10 pulls
        
        for _, pull in ipairs(recentPulls) do
            for _, cd in ipairs(pull.cooldownsUsed) do
                cooldownCount[cd.spell] = (cooldownCount[cd.spell] or 0) + 1
            end
        end
        
        for spell, count in pairs(cooldownCount) do
            table.insert(usage, {name = spell, count = count})
        end
        
        table.sort(usage, function(a, b) return a.count > b.count end)
    end
    
    return usage
end

function SD:CalculateCooldownUsageStats()
    local stats = {}
    
    if TCP.PullAnalyzer then
        local cooldownTimes = {}
        
        for _, pull in ipairs(TCP.PullAnalyzer.pullHistory) do
            for _, cd in ipairs(pull.cooldownsUsed) do
                if not cooldownTimes[cd.spell] then
                    cooldownTimes[cd.spell] = {}
                end
                table.insert(cooldownTimes[cd.spell], cd.timestamp)
            end
        end
        
        for spell, times in pairs(cooldownTimes) do
            if #times > 1 then
                table.sort(times)
                local totalTime = 0
                for i = 2, #times do
                    totalTime = totalTime + (times[i] - times[i-1])
                end
                stats[spell] = {
                    uses = #times,
                    avgTimeBetween = totalTime / (#times - 1)
                }
            else
                stats[spell] = {
                    uses = #times,
                    avgTimeBetween = 0
                }
            end
        end
    end
    
    return stats
end

function SD:GetCooldownRecommendations()
    local recommendations = {}
    
    -- Analyze cooldown usage patterns and suggest improvements
    local usage = self:CalculateCooldownUsageStats()
    
    for spell, stats in pairs(usage) do
        if stats.avgTimeBetween > 300 then -- 5+ minutes between uses
            table.insert(recommendations, 
                string.format("%s used infrequently - consider more aggressive usage", spell))
        end
    end
    
    -- Check for unused cooldowns
    if TCP.CooldownTracker then
        local _, class = UnitClass("player")
        local defensives = TCP.CooldownTracker.MAJOR_DEFENSIVES[class] or {}
        
        for spellName, _ in pairs(defensives) do
            if not usage[spellName] or usage[spellName].uses == 0 then
                table.insert(recommendations, 
                    string.format("%s never used - consider adding to rotation", spellName))
            end
        end
    end
    
    return recommendations
end

function SD:CompareWithPrevious()
    if #self.performanceMetrics < 2 then return nil end
    
    local current = self.performanceMetrics[#self.performanceMetrics]
    local previous = self.performanceMetrics[#self.performanceMetrics - 1]
    
    local damageDiff = current.totalDamage > 0 and previous.totalDamage > 0 and 
        ((current.totalDamage - previous.totalDamage) / previous.totalDamage) * 100 or 0
    
    return {
        damageTakenDiff = damageDiff,
        deathDiff = current.deaths - previous.deaths,
        avgGradeDiff = 0 -- Would need grade tracking over time
    }
end

function SD:GetSpecPerformanceData()
    local _, class = UnitClass("player")
    local spec = TCP.activeSpec or "Unknown"
    
    -- This would ideally pull from a larger dataset or online comparison
    -- For now, return mock comparative data
    return {
        specName = spec,
        yourDamage = self.sessionStats.totalDamageTaken,
        avgDamage = self.sessionStats.totalDamageTaken * 0.9, -- 10% better than average
        yourCDRate = 2.5,
        avgCDRate = 2.0,
        yourThreatLosses = TCP.ThreatAnalyzer and TCP.ThreatAnalyzer:GetThreatStats().aggroLosses or 0,
        avgThreatLosses = 1.5
    }
end

function SD:GetProgressionData()
    -- Return recent keystone completions
    -- This would be stored separately in a full implementation
    return {}
end

function SD:CalculateAverageGrade(gradeDistribution)
    local gradeValues = {A = 4, B = 3, C = 2, D = 1, F = 0}
    local totalPoints = 0
    local totalGrades = 0
    
    for grade, count in pairs(gradeDistribution) do
        if gradeValues[grade] then
            totalPoints = totalPoints + (gradeValues[grade] * count)
            totalGrades = totalGrades + count
        end
    end
    
    if totalGrades == 0 then return "N/A" end
    
    local avgValue = totalPoints / totalGrades
    for grade, value in pairs(gradeValues) do
        if avgValue >= value - 0.5 then
            return grade
        end
    end
    
    return "F"
end

function SD:FormatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

function SD:LoadSavedData()
    -- Load persistent data from saved variables
    -- This would be implemented with SavedVariables in the TOC file
end

function SD:SaveData()
    -- Save current session data for future comparison
end

function SD:ExportData()
    -- Export performance data for external analysis
    local exportData = {
        sessionStats = self.sessionStats,
        performanceMetrics = self.performanceMetrics,
        timestamp = GetTime(),
        playerName = UnitName("player"),
        realm = GetRealmName(),
        class = select(2, UnitClass("player")),
        spec = TCP.activeSpec
    }
    
    return exportData
end

function SD:ResetSessionData()
    self.sessionStats = {
        startTime = GetTime(),
        totalPulls = 0,
        totalDamageTaken = 0,
        totalHealingReceived = 0,
        cooldownsUsed = {},
        deathCount = 0,
        keystoneLevel = 0,
        dungeonTime = 0
    }
    
    self.performanceMetrics = {}
    
    if TCP.debug then
        print("TCP: Dashboard session data reset")
    end
end

-- Initialize
SD:Initialize()
