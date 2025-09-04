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
    self.summaryFrame = CreateFrame("Frame", "TCPPullSummary", UIParent)
    self.summaryFrame:SetSize(350, 200)
    self.summaryFrame:SetPoint("CENTER", 300, 0)
    self.summaryFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
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