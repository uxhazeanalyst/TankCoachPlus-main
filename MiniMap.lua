-- MinimapButton.lua - Minimap Icon and Quick Access Menu
local addonName, TCP = ...

TCP.MinimapButton = {}
local MB = TCP.MinimapButton

-- Button settings
MB.settings = {
    hide = false,
    position = 45, -- Degrees around minimap
    showTooltip = true
}

function MB:Initialize()
    self:CreateMinimapButton()
    self:CreateDropdownMenu()
    self:LoadSettings()
end

function MB:CreateMinimapButton()
    -- Create the minimap button frame
    self.button = CreateFrame("Button", "TCPMinimapButton", Minimap)
    self.button:SetSize(31, 31)
    self.button:SetFrameStrata("MEDIUM")
    self.button:SetFrameLevel(8)
    self.button:RegisterForClicks("AnyUp")
    self.button:RegisterForDrag("LeftButton")
    self.button:SetMovable(true)
    
    -- Button texture (tank shield icon)
    self.button.icon = self.button:CreateTexture(nil, "BACKGROUND")
    self.button.icon:SetSize(20, 20)
    self.button.icon:SetPoint("CENTER", 0, 1)
    self.button.icon:SetTexture("Interface\\Icons\\Ability_Defend")
    
    -- Border texture
    self.button.border = self.button:CreateTexture(nil, "OVERLAY")
    self.button.border:SetSize(52, 52)
    self.button.border:SetPoint("TOPLEFT", -10, 10)
    self.button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Highlight texture
    self.button.highlight = self.button:CreateTexture(nil, "HIGHLIGHT")
    self.button.highlight:SetSize(31, 31)
    self.button.highlight:SetPoint("CENTER")
    self.button.highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Set scripts
    self.button:SetScript("OnClick", function(_, button) self:OnClick(button) end)
    self.button:SetScript("OnDragStart", function() self:OnDragStart() end)
    self.button:SetScript("OnDragStop", function() self:OnDragStop() end)
    self.button:SetScript("OnEnter", function() self:OnEnter() end)
    self.button:SetScript("OnLeave", function() self:OnLeave() end)
    
    -- Position the button
    self:UpdatePosition()
end

function MB:CreateDropdownMenu()
    -- Create dropdown menu frame
    self.menu = CreateFrame("Frame", "TCPMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    
    -- Menu items configuration
    self.menuItems = {
        {
            text = "TankCoachPlus",
            isTitle = true,
            notCheckable = true
        },
        {
            text = "Dashboard",
            func = function() 
                if TCP.DashboardUI then 
                    TCP.DashboardUI:Show() 
                end 
            end,
            notCheckable = true
        },
        {
            text = "History Browser",
            func = function() 
                if TCP.HistoryUI then 
                    TCP.HistoryUI:Show() 
                end 
            end,
            notCheckable = true
        },
        {
            text = "Generate Summary",
            func = function() 
                if TCP.GenerateCoachSummary then
                    TCP:GenerateCoachSummary()
                else
                    print("TCP: No summary data available")
                end
            end,
            notCheckable = true
        },
        {
            text = "Map Recorder",
            func = function() 
                if TCP.MapRecorderUI then 
                    TCP.MapRecorderUI:Show() 
                end 
            end,
            notCheckable = true
        },
        {
            text = "Combat Analytics",
            func = function() 
                if TCP.CombatAnalyticsUI then 
                    if TCP.CombatAnalyticsUI:IsShown() then
                        TCP.CombatAnalyticsUI:Hide()
                    else
                        TCP.CombatAnalyticsUI:Show()
                    end
                end 
            end,
            notCheckable = true
        },
        {
            text = "", -- Separator
            disabled = true,
            notCheckable = true
        },
        {
            text = "Module Displays",
            hasArrow = true,
            menuList = {
                {
                    text = "Cooldown Alerts",
                    func = function() self:ToggleModule("cooldowns") end,
                    checked = function() return self:IsModuleVisible("cooldowns") end
                },
                {
                    text = "Threat Display",
                    func = function() self:ToggleModule("threat") end,
                    checked = function() return self:IsModuleVisible("threat") end
                },
                {
                    text = "Positioning Analysis", 
                    func = function() self:ToggleModule("positioning") end,
                    checked = function() return self:IsModuleVisible("positioning") end
                },
                {
                    text = "Affix Coaching",
                    func = function() self:ToggleModule("affixes") end,
                    checked = function() return self:IsModuleVisible("affixes") end
                }
            },
            notCheckable = true
        },
        {
            text = "Settings",
            hasArrow = true,
            menuList = {
                {
                    text = "Mythic+ Only Mode",
                    func = function() 
                        TCP.settings.onlyMythicPlus = not TCP.settings.onlyMythicPlus
                        print("TCP Mode:", TCP.settings.onlyMythicPlus and "Mythic+ Only" or "All Content")
                    end,
                    checked = function() return TCP.settings and TCP.settings.onlyMythicPlus end
                },
                {
                    text = "Enable Open World",
                    func = function() 
                        TCP.settings.enableOpenWorld = not TCP.settings.enableOpenWorld
                        print("TCP Open World:", TCP.settings.enableOpenWorld and "ENABLED" or "DISABLED")
                    end,
                    checked = function() return TCP.settings and TCP.settings.enableOpenWorld end
                },
                {
                    text = "Debug Mode",
                    func = function() 
                        TCP.debug = not TCP.debug
                        print("TCP Debug:", TCP.debug and "ON" or "OFF")
                    end,
                    checked = function() return TCP.debug end
                },
                {
                    text = "Hide Minimap Button",
                    func = function() self:ToggleButton() end,
                    notCheckable = true
                }
            },
            notCheckable = true
        },
        {
            text = "", -- Separator
            disabled = true,
            notCheckable = true
        },
        {
            text = "Reset All Data",
            func = function() 
                if TCP.PullAnalyzer then TCP.PullAnalyzer:ResetPullHistory() end
                if TCP.StatisticsDashboard then TCP.StatisticsDashboard:ResetSessionData() end
                if TCP.PositioningAnalyzer then TCP.PositioningAnalyzer:ResetPositionData() end
                print("TCP: All tracking data reset")
            end,
            notCheckable = true
        },
        {
            text = "Show Status",
            func = function() 
                local inInstance, instanceType = IsInInstance()
                local _, _, difficulty = GetInstanceInfo()
                print("TCP Status:")
                print("  Location:", inInstance and instanceType or "Open World")
                print("  Tracking:", TCP.settings and TCP.settings.onlyMythicPlus and "M+ Only" or "All Content")
                print("  Debug:", TCP.debug and "ON" or "OFF")
            end,
            notCheckable = true
        }
    }
end

function MB:OnClick(mouseButton)
    if mouseButton == "LeftButton" then
        self:ToggleDropdown()
    elseif mouseButton == "RightButton" then
        -- Quick action - open dashboard
        if TCP.DashboardUI then
            if TCP.DashboardUI:IsShown() then
                TCP.DashboardUI:Hide()
            else
                TCP.DashboardUI:Show()
            end
        end
    elseif mouseButton == "MiddleButton" then
        -- Quick reset
        if TCP.PullAnalyzer then TCP.PullAnalyzer:ResetPullHistory() end
        print("TCP: Pull history reset")
    end
end

function MB:ToggleDropdown()
    if UIDROPDOWNMENU_OPEN_MENU == self.menu then
        CloseDropDownMenus()
    else
        self:ShowDropdown()
    end
end

function MB:ShowDropdown()
    -- Create a simple dropdown menu manually since EasyMenu isn't always available
    if not self.dropdownFrame then
        self:CreateSimpleDropdown()
    end
    
    -- Position near the minimap button
    self.dropdownFrame:ClearAllPoints()
    self.dropdownFrame:SetPoint("TOPLEFT", self.button, "BOTTOMLEFT", 0, -5)
    self.dropdownFrame:Show()
    
    -- Hide after 10 seconds or when clicking elsewhere
    C_Timer.After(10, function()
        if self.dropdownFrame and self.dropdownFrame:IsShown() then
            self.dropdownFrame:Hide()
        end
    end)
end

function MB:CreateSimpleDropdown()
    -- Create a simple dropdown frame
    self.dropdownFrame = CreateFrame("Frame", "TCPSimpleDropdown", UIParent, "BackdropTemplate")
    self.dropdownFrame:SetSize(180, 300)
    self.dropdownFrame:SetFrameStrata("TOOLTIP")
    
    -- Backdrop
    if self.dropdownFrame.SetBackdrop then
        self.dropdownFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        self.dropdownFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    elseif BackdropTemplateMixin then
        Mixin(self.dropdownFrame, BackdropTemplateMixin)
        self.dropdownFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        self.dropdownFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    end
    
    self.dropdownFrame:Hide()
    
    -- Create menu buttons
    local yOffset = -10
    local buttonHeight = 20
    
    -- Title
    local title = self.dropdownFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -8)
    title:SetText("TankCoachPlus")
    yOffset = yOffset - 25
    
    -- Dashboard button
    local dashBtn = CreateFrame("Button", nil, self.dropdownFrame)
    dashBtn:SetSize(160, buttonHeight)
    dashBtn:SetPoint("TOP", 0, yOffset)
    dashBtn.text = dashBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dashBtn.text:SetPoint("CENTER")
    dashBtn.text:SetText("Dashboard")
    dashBtn:SetScript("OnClick", function() 
        if TCP.DashboardUI then TCP.DashboardUI:Show() end
        self.dropdownFrame:Hide()
    end)
    dashBtn:SetScript("OnEnter", function() dashBtn.text:SetTextColor(1, 1, 0) end)
    dashBtn:SetScript("OnLeave", function() dashBtn.text:SetTextColor(1, 1, 1) end)
    yOffset = yOffset - buttonHeight - 2
    
    -- History button
    local histBtn = CreateFrame("Button", nil, self.dropdownFrame)
    histBtn:SetSize(160, buttonHeight)
    histBtn:SetPoint("TOP", 0, yOffset)
    histBtn.text = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histBtn.text:SetPoint("CENTER")
    histBtn.text:SetText("History Browser")
    histBtn:SetScript("OnClick", function() 
        if TCP.HistoryUI then TCP.HistoryUI:Show() end
        self.dropdownFrame:Hide()
    end)
    histBtn:SetScript("OnEnter", function() histBtn.text:SetTextColor(1, 1, 0) end)
    histBtn:SetScript("OnLeave", function() histBtn.text:SetTextColor(1, 1, 1) end)
    yOffset = yOffset - buttonHeight - 2
    
    -- Map Recorder button
    local mapBtn = CreateFrame("Button", nil, self.dropdownFrame)
    mapBtn:SetSize(160, buttonHeight)
    mapBtn:SetPoint("TOP", 0, yOffset)
    mapBtn.text = mapBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mapBtn.text:SetPoint("CENTER")
    mapBtn.text:SetText("Map Recorder")
    mapBtn:SetScript("OnClick", function() 
        if TCP.MapRecorderUI then TCP.MapRecorderUI:Show() end
        self.dropdownFrame:Hide()
    end)
    mapBtn:SetScript("OnEnter", function() mapBtn.text:SetTextColor(1, 1, 0) end)
    mapBtn:SetScript("OnLeave", function() mapBtn.text:SetTextColor(1, 1, 1) end)
    yOffset = yOffset - buttonHeight - 2
    
    -- Analytics button
    local analyticsBtn = CreateFrame("Button", nil, self.dropdownFrame)
    analyticsBtn:SetSize(160, buttonHeight)
    analyticsBtn:SetPoint("TOP", 0, yOffset)
    analyticsBtn.text = analyticsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    analyticsBtn.text:SetPoint("CENTER")
    analyticsBtn.text:SetText("Combat Analytics")
    analyticsBtn:SetScript("OnClick", function() 
        if TCP.CombatAnalyticsUI then 
            if TCP.CombatAnalyticsUI:IsShown() then
                TCP.CombatAnalyticsUI:Hide()
            else
                TCP.CombatAnalyticsUI:Show()
            end
        end
        self.dropdownFrame:Hide()
    end)
    analyticsBtn:SetScript("OnEnter", function() analyticsBtn.text:SetTextColor(1, 1, 0) end)
    analyticsBtn:SetScript("OnLeave", function() analyticsBtn.text:SetTextColor(1, 1, 1) end)
    yOffset = yOffset - buttonHeight - 5
    
    -- Separator line
    local separator = self.dropdownFrame:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    separator:SetPoint("LEFT", 10, 0)
    separator:SetPoint("RIGHT", -10, 0)
    separator:SetPoint("TOP", 0, yOffset)
    yOffset = yOffset - 10
    
    -- Settings toggle
    local settingsBtn = CreateFrame("Button", nil, self.dropdownFrame)
    settingsBtn:SetSize(160, buttonHeight)
    settingsBtn:SetPoint("TOP", 0, yOffset)
    settingsBtn.text = settingsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsBtn.text:SetPoint("CENTER")
    settingsBtn.text:SetText("Toggle M+ Only Mode")
    settingsBtn:SetScript("OnClick", function() 
        TCP.settings.onlyMythicPlus = not TCP.settings.onlyMythicPlus
        print("TCP Mode:", TCP.settings.onlyMythicPlus and "Mythic+ Only" or "All Content")
        self.dropdownFrame:Hide()
    end)
    settingsBtn:SetScript("OnEnter", function() settingsBtn.text:SetTextColor(1, 1, 0) end)
    settingsBtn:SetScript("OnLeave", function() settingsBtn.text:SetTextColor(1, 1, 1) end)
    yOffset = yOffset - buttonHeight - 2
    
    -- Reset button
    local resetBtn = CreateFrame("Button", nil, self.dropdownFrame)
    resetBtn:SetSize(160, buttonHeight)
    resetBtn:SetPoint("TOP", 0, yOffset)
    resetBtn.text = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetBtn.text:SetPoint("CENTER")
    resetBtn.text:SetText("Reset All Data")
    resetBtn.text:SetTextColor(1, 0.5, 0.5) -- Reddish color for destructive action
    resetBtn:SetScript("OnClick", function() 
        if TCP.PullAnalyzer then TCP.PullAnalyzer:ResetPullHistory() end
        if TCP.StatisticsDashboard then TCP.StatisticsDashboard:ResetSessionData() end
        if TCP.PositioningAnalyzer then TCP.PositioningAnalyzer:ResetPositionData() end
        print("TCP: All tracking data reset")
        self.dropdownFrame:Hide()
    end)
    resetBtn:SetScript("OnEnter", function() resetBtn.text:SetTextColor(1, 0.2, 0.2) end)
    resetBtn:SetScript("OnLeave", function() resetBtn.text:SetTextColor(1, 0.5, 0.5) end)
    
    -- Hide on click outside
    self.dropdownFrame:SetScript("OnShow", function()
        self.dropdownFrame:SetScript("OnUpdate", function(_, elapsed)
            if not MouseIsOver(self.dropdownFrame) and not MouseIsOver(self.button) then
                if GetTime() - (self.dropdownFrame.showTime or 0) > 1 then -- 1 second grace period
                    self.dropdownFrame:Hide()
                    self.dropdownFrame:SetScript("OnUpdate", nil)
                end
            else
                self.dropdownFrame.showTime = GetTime()
            end
        end)
        self.dropdownFrame.showTime = GetTime()
    end)
end

function MB:OnEnter()
    if not self.settings.showTooltip then return end
    
    GameTooltip:SetOwner(self.button, "ANCHOR_LEFT")
    GameTooltip:SetText("TankCoachPlus", 1, 1, 1)
    GameTooltip:AddLine("Left Click: Open Menu", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right Click: Toggle Dashboard", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Middle Click: Reset Data", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: Move Button", 0.8, 0.8, 0.8)
    
    -- Show current status
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        GameTooltip:AddLine(" ", 1, 1, 1) -- Empty line
        GameTooltip:AddLine("Status: " .. instanceType, 0.6, 1, 0.6)
        if TCP.settings and TCP.settings.onlyMythicPlus then
            GameTooltip:AddLine("Mode: Mythic+ Only", 0.6, 1, 0.6)
        end
    else
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Status: Open World", 1, 1, 0.6)
    end
    
    GameTooltip:Show()
end

function MB:OnLeave()
    GameTooltip:Hide()
end

function MB:OnDragStart()
    self.button:SetScript("OnUpdate", function() self:OnDragUpdate() end)
    self.isDragging = true
end

function MB:OnDragStop()
    self.button:SetScript("OnUpdate", nil)
    self.isDragging = false
    self:SavePosition()
end

function MB:OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    
    local angle = math.atan2(py - my, px - mx)
    angle = math.deg(angle)
    if angle < 0 then angle = angle + 360 end
    
    self.settings.position = angle
    self:UpdatePosition()
end

function MB:UpdatePosition()
    local angle = math.rad(self.settings.position)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MB:ToggleModule(moduleName)
    if moduleName == "cooldowns" then
        if TCP.CooldownTracker and TCP.CooldownTracker.alertFrame then
            if TCP.CooldownTracker.alertFrame:IsShown() then
                TCP.CooldownTracker.alertFrame:Hide()
            else
                TCP.CooldownTracker.alertFrame:Show()
            end
        end
    elseif moduleName == "threat" then
        if TCP.ThreatAnalyzer and TCP.ThreatAnalyzer.threatFrame then
            if TCP.ThreatAnalyzer.threatFrame:IsShown() then
                TCP.ThreatAnalyzer.threatFrame:Hide()
            else
                TCP.ThreatAnalyzer.threatFrame:Show()
            end
        end
    elseif moduleName == "positioning" then
        if TCP.PositioningAnalyzer and TCP.PositioningAnalyzer.posFrame then
            if TCP.PositioningAnalyzer.posFrame:IsShown() then
                TCP.PositioningAnalyzer.posFrame:Hide()
            else
                TCP.PositioningAnalyzer.posFrame:Show()
            end
        end
    elseif moduleName == "affixes" then
        if TCP.AffixCoach and TCP.AffixCoach.affixFrame then
            if TCP.AffixCoach.affixFrame:IsShown() then
                TCP.AffixCoach.affixFrame:Hide()
            else
                TCP.AffixCoach.affixFrame:Show()
            end
        end
    end
end

function MB:IsModuleVisible(moduleName)
    if moduleName == "cooldowns" then
        return TCP.CooldownTracker and TCP.CooldownTracker.alertFrame and TCP.CooldownTracker.alertFrame:IsShown()
    elseif moduleName == "threat" then
        return TCP.ThreatAnalyzer and TCP.ThreatAnalyzer.threatFrame and TCP.ThreatAnalyzer.threatFrame:IsShown()
    elseif moduleName == "positioning" then
        return TCP.PositioningAnalyzer and TCP.PositioningAnalyzer.posFrame and TCP.PositioningAnalyzer.posFrame:IsShown()
    elseif moduleName == "affixes" then
        return TCP.AffixCoach and TCP.AffixCoach.affixFrame and TCP.AffixCoach.affixFrame:IsShown()
    end
    return false
end

function MB:ToggleButton()
    self.settings.hide = not self.settings.hide
    if self.settings.hide then
        self.button:Hide()
        print("TCP: Minimap button hidden. Use '/tcp minimap' to show it again.")
    else
        self.button:Show()
        print("TCP: Minimap button shown.")
    end
    self:SaveSettings()
end

function MB:SavePosition()
    -- This would save to SavedVariables in a full implementation
    if TCP.debug then
        print("TCP: Minimap button position saved:", string.format("%.1f", self.settings.position))
    end
end

function MB:LoadSettings()
    -- This would load from SavedVariables in a full implementation
    -- For now, use defaults
    if self.settings.hide then
        self.button:Hide()
    end
end

function MB:SaveSettings()
    -- This would save to SavedVariables in a full implementation
end

-- Initialize the minimap button
MB:Initialize()
