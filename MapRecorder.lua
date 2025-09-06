-- MapRecorder.lua - Live Map Position Recording and Playback
local addonName, TCP = ...

TCP.MapRecorder = {}
local MR = TCP.MapRecorder

-- Recording data
MR.isRecording = false
MR.currentRecording = nil
MR.recordings = {}
MR.playbackData = nil
MR.playbackIndex = 1
MR.isPlaying = false
MR.recordingTimer = nil
MR.continuousRecording = false

-- Trail visual system
MR.trailPoints = {}
MR.trailLines = {}
MR.maxTrailPoints = 500
MR.trailFadeTime = 30 -- seconds

function MR:Initialize()
    self:CreateMapFrame()
    self:CreateControlPanel()
    
    -- Start continuous recording by default
    self:StartContinuousRecording()
end

function MR:CreateMapFrame()
    -- Main map recording frame
    self.mapFrame = CreateFrame("Frame", "TCPMapRecorder", UIParent, "BasicFrameTemplate")
    self.mapFrame:SetSize(600, 500)
    self.mapFrame:SetPoint("CENTER", 200, 0)
    self.mapFrame:SetMovable(true)
    self.mapFrame:SetResizable(true)
    self.mapFrame:EnableMouse(true)
    self.mapFrame:RegisterForDrag("LeftButton")
    self.mapFrame:SetScript("OnDragStart", self.mapFrame.StartMoving)
    self.mapFrame:SetScript("OnDragStop", self.mapFrame.StopMovingOrSizing)
    self.mapFrame:SetMinResize(300, 250)
    self.mapFrame:SetMaxResize(1200, 900)
    self.mapFrame:Hide()
    
    -- Create resize handle in bottom-right corner
    self.resizeHandle = CreateFrame("Button", nil, self.mapFrame)
    self.resizeHandle:SetSize(16, 16)
    self.resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    self.resizeHandle:EnableMouse(true)
    self.resizeHandle:RegisterForDrag("LeftButton")
    
    -- Resize handle texture (corner grip)
    self.resizeHandle.texture = self.resizeHandle:CreateTexture(nil, "OVERLAY")
    self.resizeHandle.texture:SetAllPoints()
    self.resizeHandle.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    
    -- Resize handle hover effect
    self.resizeHandle.highlight = self.resizeHandle:CreateTexture(nil, "HIGHLIGHT")
    self.resizeHandle.highlight:SetAllPoints()
    self.resizeHandle.highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    
    -- Resize functionality
    self.resizeHandle:SetScript("OnDragStart", function()
        self.mapFrame:StartSizing("BOTTOMRIGHT")
        self.mapFrame:SetScript("OnSizeChanged", function()
            self:OnFrameResized()
        end)
    end)
    
    self.resizeHandle:SetScript("OnDragStop", function()
        self.mapFrame:StopMovingOrSizing()
        self.mapFrame:SetScript("OnSizeChanged", nil)
    end)
    
    -- Title
    self.mapFrame.title = self.mapFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.mapFrame.title:SetPoint("TOP", 0, -8)
    self.mapFrame.title:SetText("Map Recorder")
    
    -- Minimize/Restore button
    self.minimizeBtn = CreateFrame("Button", nil, self.mapFrame)
    self.minimizeBtn:SetSize(20, 20)
    self.minimizeBtn:SetPoint("TOPRIGHT", -25, -5)
    self.minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    self.minimizeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    self.minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    
    -- Store original size for restore
    self.originalSize = {width = 600, height = 500}
    self.isMinimized = false
    
    self.minimizeBtn:SetScript("OnClick", function()
        self:ToggleMinimize()
    end)
    
    -- Minimize button tooltip
    self.minimizeBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(self.minimizeBtn, "ANCHOR_LEFT")
        GameTooltip:SetText(self.isMinimized and "Restore Window" or "Minimize Window")
        GameTooltip:Show()
    end)
    self.minimizeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Map display area with actual map background
    self.mapDisplay = CreateFrame("Frame", nil, self.mapFrame, "BackdropTemplate")
    self.mapDisplay:SetPoint("TOPLEFT", 15, -35)
    self.mapDisplay:SetPoint("BOTTOMRIGHT", -35, 60)
    
    -- Create map background texture
    self.mapBackground = self.mapDisplay:CreateTexture(nil, "BACKGROUND")
    self.mapBackground:SetAllPoints()
    self.mapBackground:SetColorTexture(0.1, 0.15, 0.2, 1) -- Default dark blue-gray
    
    -- Border around map
    local backdropInfo = {
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }
    
    if self.mapDisplay.SetBackdrop then
        self.mapDisplay:SetBackdrop(backdropInfo)
        self.mapDisplay:SetBackdropBorderColor(0.8, 0.6, 0, 0.8)
    elseif BackdropTemplateMixin then
        Mixin(self.mapDisplay, BackdropTemplateMixin)
        self.mapDisplay:SetBackdrop(backdropInfo)
        self.mapDisplay:SetBackdropBorderColor(0.8, 0.6, 0, 0.8)
    end
    
    -- Map info text
    self.mapInfoText = self.mapDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.mapInfoText:SetPoint("TOPLEFT", 10, -10)
    self.mapInfoText:SetTextColor(1, 1, 1)
    
    -- Recording status
    self.statusText = self.mapDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.statusText:SetPoint("TOP", 0, -10)
    self.statusText:SetTextColor(0, 1, 0)
    self.statusText:SetText("● CONTINUOUS RECORDING")
    
    -- Trail storage
    self.trailPoints = {}
    self.trailLines = {}
    
    -- Update map background when shown
    self.mapFrame:SetScript("OnShow", function()
        self:UpdateMapBackground()
    end)
    
    -- Store reference
    TCP.MapRecorderUI = self.mapFrame
end

function MR:OnFrameResized()
    -- Clear existing trail visuals since coordinates need to be recalculated
    for _, element in ipairs(self.trailLines) do
        if element.texture then
            element.texture:Hide()
            element.texture = nil
        end
        if element.connectionLine then
            element.connectionLine:Hide()
            element.connectionLine = nil
        end
    end
    self.trailLines = {}
    
    -- Redraw the trail with new dimensions
    self:RedrawTrail()
    
    -- Update control panel layout if needed
    self:UpdateControlPanelLayout()
end

function MR:RedrawTrail()
    -- Redraw all trail points with current window dimensions
    for i, point in ipairs(self.trailPoints) do
        self:CreateTrailVisual(point, i)
    end
end

function MR:ToggleMinimize()
    if self.isMinimized then
        -- Restore window
        self.mapFrame:SetSize(self.originalSize.width, self.originalSize.height)
        self.mapDisplay:Show()
        self.controlPanel:Show()
        self.resizeHandle:Show()
        
        -- Update button texture
        self.minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        self.minimizeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        self.minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        
        self.isMinimized = false
        
        -- Redraw trail
        self:RedrawTrail()
        
    else
        -- Store current size
        self.originalSize.width = self.mapFrame:GetWidth()
        self.originalSize.height = self.mapFrame:GetHeight()
        
        -- Minimize window
        self.mapFrame:SetSize(250, 40)
        self.mapDisplay:Hide()
        self.controlPanel:Hide()
        self.resizeHandle:Hide()
        
        -- Update button texture to restore icon
        self.minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
        self.minimizeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Highlight")
        self.minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Down")
        
        self.isMinimized = true
    end
end
    -- Adjust control panel based on window width
    local frameWidth = self.mapFrame:GetWidth()
    
    if frameWidth < 400 then
        -- Compact layout for small windows
        self.continuousBtn:SetSize(80, 20)
        self.manualBtn:SetSize(70, 20)
        self.clearBtn:SetSize(60, 20)
        self.opacitySlider:SetSize(80, 15)
        
        -- Stack controls in two rows if very narrow
        if frameWidth < 350 then
            self.manualBtn:ClearAllPoints()
            self.manualBtn:SetPoint("LEFT", 5, -5)
            self.clearBtn:ClearAllPoints()
            self.clearBtn:SetPoint("LEFT", self.manualBtn, "RIGHT", 5, 0)
        end
    else
        -- Normal layout for larger windows
        self.continuousBtn:SetSize(120, 25)
        self.manualBtn:SetSize(100, 25)
        self.clearBtn:SetSize(80, 25)
        self.opacitySlider:SetSize(120, 20)
        
        -- Reset to single row
        self.manualBtn:ClearAllPoints()
        self.manualBtn:SetPoint("LEFT", self.continuousBtn, "RIGHT", 5, 0)
        self.clearBtn:ClearAllPoints()
        self.clearBtn:SetPoint("LEFT", self.manualBtn, "RIGHT", 5, 0)
    end
end

function MR:UpdateMapBackground()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    
    -- Get map texture file
    local mapInfo = C_Map.GetMapInfo(mapID)
    if mapInfo then
        -- Try to load the actual map texture
        local mapTexture = "Interface\\WorldMap\\" .. (mapInfo.name or ""):gsub(" ", "") .. "\\" .. (mapInfo.name or ""):gsub(" ", "")
        
        -- Update map info display
        local zoneName = GetZoneText() or mapInfo.name or "Unknown Zone"
        local subzoneName = GetSubZoneText() or ""
        local coords = self:GetPlayerMapCoordinates()
        
        self.mapInfoText:SetText(string.format("%s\n%s\nCoords: %.1f, %.1f", 
            zoneName, subzoneName, coords.x * 100, coords.y * 100))
        
        -- Set map background color based on zone type
        if mapInfo.mapType == 1 then -- Dungeon
            self.mapBackground:SetColorTexture(0.2, 0.1, 0.3, 1) -- Purple for dungeons
        elseif mapInfo.mapType == 2 then -- Raid
            self.mapBackground:SetColorTexture(0.3, 0.1, 0.1, 1) -- Dark red for raids
        else -- Outdoor zones
            self.mapBackground:SetColorTexture(0.1, 0.2, 0.1, 1) -- Dark green for outdoor
        end
    end
end

function MR:GetPlayerMapCoordinates()
    local position = C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
    if position then
        return {x = position.x, y = position.y}
    end
    return {x = 0, y = 0}
end

function MR:CreateControlPanel()
    -- Control panel at bottom of map frame
    self.controlPanel = CreateFrame("Frame", nil, self.mapFrame)
    self.controlPanel:SetPoint("BOTTOMLEFT", 15, 10)
    self.controlPanel:SetPoint("BOTTOMRIGHT", -35, 10)
    self.controlPanel:SetHeight(45)
    
    -- Continuous recording toggle
    self.continuousBtn = CreateFrame("Button", nil, self.controlPanel, "GameMenuButtonTemplate")
    self.continuousBtn:SetSize(120, 25)
    self.continuousBtn:SetPoint("LEFT", 5, 10)
    self.continuousBtn:SetText("Stop Recording")
    self.continuousBtn:SetScript("OnClick", function() self:ToggleContinuousRecording() end)
    
    -- Manual recording button
    self.manualBtn = CreateFrame("Button", nil, self.controlPanel, "GameMenuButtonTemplate")
    self.manualBtn:SetSize(100, 25)
    self.manualBtn:SetPoint("LEFT", self.continuousBtn, "RIGHT", 5, 0)
    self.manualBtn:SetText("Manual Record")
    self.manualBtn:SetScript("OnClick", function() self:StartManualRecording() end)
    
    -- Clear trail button
    self.clearBtn = CreateFrame("Button", nil, self.controlPanel, "GameMenuButtonTemplate")
    self.clearBtn:SetSize(80, 25)
    self.clearBtn:SetPoint("LEFT", self.manualBtn, "RIGHT", 5, 0)
    self.clearBtn:SetText("Clear Trail")
    self.clearBtn:SetScript("OnClick", function() self:ClearTrail() end)
    
    -- Trail opacity slider
    self.opacitySlider = CreateFrame("Slider", nil, self.controlPanel, "OptionsSliderTemplate")
    self.opacitySlider:SetPoint("LEFT", self.clearBtn, "RIGHT", 20, 0)
    self.opacitySlider:SetSize(120, 20)
    self.opacitySlider:SetMinMaxValues(0.1, 1.0)
    self.opacitySlider:SetValue(0.8)
    self.opacitySlider:SetValueStep(0.1)
    self.opacitySlider.Text:SetText("Trail: 80%")
    self.opacitySlider:SetScript("OnValueChanged", function(_, value)
        self.opacitySlider.Text:SetText(string.format("Trail: %.0f%%", value * 100))
        self:UpdateTrailOpacity(value)
    end)
    
    -- Trail length info
    self.trailInfo = self.controlPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.trailInfo:SetPoint("BOTTOM", 0, 5)
    self.trailInfo:SetTextColor(0.8, 0.8, 0.8)
end

function MR:StartContinuousRecording()
    if self.continuousRecording then return end
    
    self.continuousRecording = true
    self.continuousBtn:SetText("Stop Recording")
    self.statusText:SetText("● CONTINUOUS RECORDING")
    self.statusText:SetTextColor(0, 1, 0)
    
    -- Start continuous position tracking
    self.recordingTimer = C_Timer.NewTicker(0.5, function() -- Every 0.5 seconds
        self:RecordTrailPoint()
    end)
    
    if TCP.debug then
        print("TCP: Started continuous map recording")
    end
end

function MR:StopContinuousRecording()
    if not self.continuousRecording then return end
    
    self.continuousRecording = false
    self.continuousBtn:SetText("Start Recording")
    self.statusText:SetText("Recording stopped")
    self.statusText:SetTextColor(1, 1, 0)
    
    if self.recordingTimer then
        self.recordingTimer:Cancel()
        self.recordingTimer = nil
    end
    
    if TCP.debug then
        print("TCP: Stopped continuous map recording")
    end
end

function MR:ToggleContinuousRecording()
    if self.continuousRecording then
        self:StopContinuousRecording()
    else
        self:StartContinuousRecording()
    end
end

function MR:RecordTrailPoint()
    local coords = self:GetPlayerMapCoordinates()
    if coords.x == 0 and coords.y == 0 then return end
    
    local currentTime = GetTime()
    local inCombat = UnitAffectingCombat("player")
    local healthPercent = UnitHealth("player") / math.max(UnitHealthMax("player"), 1)
    
    local trailPoint = {
        x = coords.x,
        y = coords.y,
        time = currentTime,
        inCombat = inCombat,
        health = healthPercent
    }
    
    table.insert(self.trailPoints, trailPoint)
    
    -- Limit trail points for performance
    while #self.trailPoints > self.maxTrailPoints do
        table.remove(self.trailPoints, 1)
        -- Also remove corresponding visual elements
        if #self.trailLines > 0 then
            local oldLine = table.remove(self.trailLines, 1)
            if oldLine and oldLine.texture then
                oldLine.texture:Hide()
                oldLine.texture = nil
            end
        end
    end
    
    -- Create visual trail point
    self:CreateTrailVisual(trailPoint, #self.trailPoints)
    
    -- Update trail info
    self:UpdateTrailInfo()
end

function MR:CreateTrailVisual(point, index)
    if not self.mapDisplay then return end
    
    -- Convert map coordinates to display coordinates
    local displayWidth = self.mapDisplay:GetWidth()
    local displayHeight = self.mapDisplay:GetHeight()
    local displayX = point.x * displayWidth
    local displayY = (1 - point.y) * displayHeight -- Flip Y coordinate
    
    -- Create small dot for this position
    local dot = self.mapDisplay:CreateTexture(nil, "OVERLAY")
    dot:SetSize(3, 3)
    dot:SetPoint("BOTTOMLEFT", self.mapDisplay, "BOTTOMLEFT", displayX - 1.5, displayY - 1.5)
    
    -- Color based on combat and health
    if point.inCombat then
        -- Red trail in combat, intensity based on health
        local intensity = 1 - point.health
        dot:SetColorTexture(1, intensity * 0.3, intensity * 0.1, 0.8)
    else
        -- Blue trail out of combat
        dot:SetColorTexture(0.2, 0.6, 1, 0.6)
    end
    
    -- Store the dot for cleanup
    local trailElement = {
        texture = dot,
        time = point.time,
        point = point
    }
    
    table.insert(self.trailLines, trailElement)
    
    -- Connect to previous point if exists
    if index > 1 and self.trailLines[index - 1] then
        self:CreateTrailConnection(self.trailLines[index - 1], trailElement)
    end
    
    -- Fade old trail points
    self:FadeOldTrailPoints()
end

function MR:CreateTrailConnection(fromElement, toElement)
    if not fromElement or not toElement or not fromElement.point or not toElement.point then return end
    
    local fromPoint = fromElement.point
    local toPoint = toElement.point
    
    -- Calculate distance to determine if we should draw a line
    local distance = math.sqrt((toPoint.x - fromPoint.x)^2 + (toPoint.y - fromPoint.y)^2)
    
    -- Only connect nearby points (avoid long lines when teleporting/loading)
    if distance > 0.1 then return end -- 10% of map width/height
    
    -- Create a line texture between the points
    local line = self.mapDisplay:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    
    -- Color based on combat status
    if fromPoint.inCombat or toPoint.inCombat then
        line:SetColorTexture(1, 0.3, 0.1, 0.4) -- Red combat trail
    else
        line:SetColorTexture(0.2, 0.6, 1, 0.3) -- Blue peaceful trail
    end
    
    -- Position the line (simplified line drawing)
    local displayWidth = self.mapDisplay:GetWidth()
    local displayHeight = self.mapDisplay:GetHeight()
    
    local fromX = fromPoint.x * displayWidth
    local fromY = (1 - fromPoint.y) * displayHeight
    local toX = toPoint.x * displayWidth
    local toY = (1 - toPoint.y) * displayHeight
    
    local lineDistance = math.sqrt((toX - fromX)^2 + (toY - fromY)^2)
    line:SetWidth(lineDistance)
    
    local centerX = (fromX + toX) / 2
    local centerY = (fromY + toY) / 2
    
    line:SetPoint("CENTER", self.mapDisplay, "BOTTOMLEFT", centerX, centerY)
    
    -- Store line for cleanup
    toElement.connectionLine = line
end

function MR:FadeOldTrailPoints()
    local currentTime = GetTime()
    local fadeStartTime = currentTime - self.trailFadeTime
    
    for _, element in ipairs(self.trailLines) do
        if element.texture and element.time then
            local age = currentTime - element.time
            local alpha = 1 - (age / self.trailFadeTime)
            alpha = math.max(0.1, math.min(1, alpha))
            
            element.texture:SetAlpha(alpha)
            if element.connectionLine then
                element.connectionLine:SetAlpha(alpha * 0.5)
            end
        end
    end
end

function MR:UpdateTrailOpacity(opacity)
    for _, element in ipairs(self.trailLines) do
        if element.texture then
            local currentAlpha = element.texture:GetAlpha()
            element.texture:SetAlpha(currentAlpha * opacity)
        end
        if element.connectionLine then
            local currentAlpha = element.connectionLine:GetAlpha()
            element.connectionLine:SetAlpha(currentAlpha * opacity)
        end
    end
end

function MR:ClearTrail()
    -- Hide all trail visuals
    for _, element in ipairs(self.trailLines) do
        if element.texture then
            element.texture:Hide()
            element.texture = nil
        end
        if element.connectionLine then
            element.connectionLine:Hide()
            element.connectionLine = nil
        end
    end
    
    -- Clear data
    self.trailPoints = {}
    self.trailLines = {}
    
    self:UpdateTrailInfo()
    
    if TCP.debug then
        print("TCP: Trail cleared")
    end
end

function MR:UpdateTrailInfo()
    local pointCount = #self.trailPoints
    local timeSpan = 0
    
    if pointCount > 1 then
        timeSpan = self.trailPoints[pointCount].time - self.trailPoints[1].time
    end
    
    self.trailInfo:SetText(string.format("Trail: %d points | %.1f minutes", 
        pointCount, timeSpan / 60))
end

function MR:StartManualRecording(name)
    -- Manual recording for specific events (keeping original functionality)
    local recordingName = name or ("Manual Recording " .. (#self.recordings + 1))
    
    local recording = {
        name = recordingName,
        startTime = GetTime(),
        trailPoints = {},
        mapID = C_Map.GetBestMapForUnit("player"),
        zoneName = GetZoneText() or "Unknown Zone"
    }
    
    -- Copy current trail points to manual recording
    for _, point in ipairs(self.trailPoints) do
        table.insert(recording.trailPoints, {
            x = point.x,
            y = point.y,
            time = point.time - recording.startTime,
            inCombat = point.inCombat,
            health = point.health
        })
    end
    
    recording.endTime = GetTime()
    recording.duration = recording.endTime - recording.startTime
    
    table.insert(self.recordings, recording)
    
    print("TCP: Manual recording saved:", recordingName)
    print("  Points:", #recording.trailPoints)
    print("  Duration:", string.format("%.1f minutes", recording.duration / 60))
end

-- Initialize
MR:Initialize()

function MR:CreateMapFrame()
    -- Main map recording frame
    self.mapFrame = CreateFrame("Frame", "TCPMapRecorder", UIParent, "BasicFrameTemplate")
    self.mapFrame:SetSize(500, 400)
    self.mapFrame:SetPoint("CENTER", 200, 0)
    self.mapFrame:SetMovable(true)
    self.mapFrame:EnableMouse(true)
    self.mapFrame:RegisterForDrag("LeftButton")
    self.mapFrame:SetScript("OnDragStart", self.mapFrame.StartMoving)
    self.mapFrame:SetScript("OnDragStop", self.mapFrame.StopMovingOrSizing)
    self.mapFrame:Hide()
    
    -- Title
    self.mapFrame.title = self.mapFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.mapFrame.title:SetPoint("TOP", 0, -8)
    self.mapFrame.title:SetText("Map Recorder")
    
    -- Map display area
    self.mapDisplay = CreateFrame("Frame", nil, self.mapFrame, "BackdropTemplate")
    self.mapDisplay:SetPoint("TOPLEFT", 15, -35)
    self.mapDisplay:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local backdropInfo = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    }
    
    if self.mapDisplay.SetBackdrop then
        self.mapDisplay:SetBackdrop(backdropInfo)
        self.mapDisplay:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    elseif BackdropTemplateMixin then
        -- Use mixin directly
        Mixin(self.mapDisplay, BackdropTemplateMixin)
        self.mapDisplay:SetBackdrop(backdropInfo)
        self.mapDisplay:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    end
    
    -- Map coordinates text
    self.coordText = self.mapDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.coordText:SetPoint("TOPLEFT", 10, -10)
    self.coordText:SetTextColor(1, 1, 1)
    
    -- Recording status
    self.statusText = self.mapDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.statusText:SetPoint("TOP", 0, -10)
    self.statusText:SetTextColor(1, 0.8, 0)
    
    -- Player position markers storage
    self.positionMarkers = {}
    
    -- Store reference
    TCP.MapRecorderUI = self.mapFrame
end

function MR:CreateControlPanel()
    -- Control panel at bottom of map frame
    local panel = CreateFrame("Frame", nil, self.mapFrame)
    panel:SetPoint("BOTTOMLEFT", 15, 10)
    panel:SetPoint("BOTTOMRIGHT", -35, 10)
    panel:SetHeight(35)
    
    -- Record button
    self.recordBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    self.recordBtn:SetSize(80, 25)
    self.recordBtn:SetPoint("LEFT", 5, 0)
    self.recordBtn:SetText("Record")
    self.recordBtn:SetScript("OnClick", function() self:ToggleRecording() end)
    
    -- Stop button
    self.stopBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    self.stopBtn:SetSize(60, 25)
    self.stopBtn:SetPoint("LEFT", self.recordBtn, "RIGHT", 5, 0)
    self.stopBtn:SetText("Stop")
    self.stopBtn:SetEnabled(false)
    self.stopBtn:SetScript("OnClick", function() self:StopRecording() end)
    
    -- Play button
    self.playBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    self.playBtn:SetSize(60, 25)
    self.playBtn:SetPoint("LEFT", self.stopBtn, "RIGHT", 5, 0)
    self.playBtn:SetText("Play")
    self.playBtn:SetEnabled(false)
    self.playBtn:SetScript("OnClick", function() self:PlayRecording() end)
    
    -- Save button
    self.saveBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    self.saveBtn:SetSize(60, 25)
    self.saveBtn:SetPoint("LEFT", self.playBtn, "RIGHT", 5, 0)
    self.saveBtn:SetText("Save")
    self.saveBtn:SetEnabled(false)
    self.saveBtn:SetScript("OnClick", function() self:SaveRecording() end)
    
    -- Clear button
    self.clearBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    self.clearBtn:SetSize(60, 25)
    self.clearBtn:SetPoint("LEFT", self.saveBtn, "RIGHT", 5, 0)
    self.clearBtn:SetText("Clear")
    self.clearBtn:SetScript("OnClick", function() self:ClearDisplay() end)
    
    -- Speed slider for playback
    self.speedSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    self.speedSlider:SetPoint("RIGHT", -10, 0)
    self.speedSlider:SetSize(100, 20)
    self.speedSlider:SetMinMaxValues(0.5, 4.0)
    self.speedSlider:SetValue(1.0)
    self.speedSlider:SetValueStep(0.1)
    self.speedSlider.Text:SetText("Speed: 1.0x")
    self.speedSlider:SetScript("OnValueChanged", function(_, value)
        self.speedSlider.Text:SetText(string.format("Speed: %.1fx", value))
    end)
end

function MR:HookPullAnalyzer()
    -- Auto-start recording when pull begins
    local originalStartPull = TCP.PullAnalyzer.StartPull
    TCP.PullAnalyzer.StartPull = function(pa)
        originalStartPull(pa)
        if TCP.settings and TCP.settings.autoRecordMap then
            MR:StartRecording("Auto: Pull #" .. (pa.currentPull and pa.currentPull.pullNumber or "?"))
        end
    end
    
    -- Auto-stop recording when pull ends
    local originalEndPull = TCP.PullAnalyzer.EndPull
    TCP.PullAnalyzer.EndPull = function(pa)
        originalEndPull(pa)
        if MR.isRecording then
            MR:StopRecording()
        end
    end
end

function MR:ToggleRecording()
    if self.isRecording then
        self:StopRecording()
    else
        self:StartRecording()
    end
end

function MR:StartRecording(name)
    if self.isRecording then
        self:StopRecording()
    end
    
    local recordingName = name or ("Recording " .. (#self.recordings + 1))
    
    self.currentRecording = {
        name = recordingName,
        startTime = GetTime(),
        positions = {},
        events = {},
        mapID = C_Map.GetBestMapForUnit("player"),
        zoneName = GetZoneText() or "Unknown Zone"
    }
    
    self.isRecording = true
    self.recordBtn:SetText("Recording...")
    self.recordBtn:SetEnabled(false)
    self.stopBtn:SetEnabled(true)
    self.statusText:SetText("● RECORDING: " .. recordingName)
    
    -- Start position tracking timer
    self.recordingTimer = C_Timer.NewTicker(0.2, function() -- Record every 0.2 seconds
        self:RecordPosition()
    end)
    
    if TCP.debug then
        print("TCP: Started map recording:", recordingName)
    end
end

function MR:StopRecording()
    if not self.isRecording then return end
    
    self.isRecording = false
    
    if self.recordingTimer then
        self.recordingTimer:Cancel()
        self.recordingTimer = nil
    end
    
    if self.currentRecording then
        self.currentRecording.endTime = GetTime()
        self.currentRecording.duration = self.currentRecording.endTime - self.currentRecording.startTime
        
        -- Store the completed recording
        table.insert(self.recordings, self.currentRecording)
        
        self.playBtn:SetEnabled(true)
        self.saveBtn:SetEnabled(true)
        
        if TCP.debug then
            print("TCP: Stopped recording. Duration:", string.format("%.1fs", self.currentRecording.duration))
            print("TCP: Positions recorded:", #self.currentRecording.positions)
        end
    end
    
    self.recordBtn:SetText("Record")
    self.recordBtn:SetEnabled(true)
    self.stopBtn:SetEnabled(false)
    self.statusText:SetText("Recording stopped. Ready for playback.")
end

function MR:RecordPosition()
    if not self.isRecording or not self.currentRecording then return end
    
    local x, y = UnitPosition("player")
    if not x or not y then return end
    
    local _, class = UnitClass("player")
    local currentTime = GetTime()
    local relativeTime = currentTime - self.currentRecording.startTime
    
    local positionData = {
        x = x,
        y = y,
        time = relativeTime,
        hp = UnitHealth("player") / math.max(UnitHealthMax("player"), 1),
        inCombat = UnitAffectingCombat("player"),
        class = class
    }
    
    table.insert(self.currentRecording.positions, positionData)
    
    -- Update coordinate display
    self.coordText:SetText(string.format("Position: %.1f, %.1f\nTime: %.1fs\nPoints: %d", 
        x, y, relativeTime, #self.currentRecording.positions))
end

function MR:PlayRecording()
    local recording = self.currentRecording or self.recordings[#self.recordings]
    if not recording or #recording.positions == 0 then
        print("TCP: No recording data to play")
        return
    end
    
    self:ClearDisplay()
    self.playbackData = recording
    self.playbackIndex = 1
    self.isPlaying = true
    
    self.statusText:SetText("▶ PLAYING: " .. recording.name)
    self.playBtn:SetText("Playing...")
    self.playBtn:SetEnabled(false)
    
    local speed = self.speedSlider:GetValue()
    local interval = 0.1 / speed -- Base interval adjusted by speed
    
    self.playbackTimer = C_Timer.NewTicker(interval, function()
        self:UpdatePlayback()
    end)
    
    if TCP.debug then
        print("TCP: Started playback at", string.format("%.1fx speed", speed))
    end
end

function MR:UpdatePlayback()
    if not self.isPlaying or not self.playbackData then
        self:StopPlayback()
        return
    end
    
    if self.playbackIndex > #self.playbackData.positions then
        self:StopPlayback()
        return
    end
    
    local position = self.playbackData.positions[self.playbackIndex]
    self:DisplayPositionMarker(position, self.playbackIndex)
    
    self.playbackIndex = self.playbackIndex + 1
end

function MR:StopPlayback()
    self.isPlaying = false
    
    if self.playbackTimer then
        self.playbackTimer:Cancel()
        self.playbackTimer = nil
    end
    
    self.playBtn:SetText("Play")
    self.playBtn:SetEnabled(true)
    self.statusText:SetText("Playback complete")
end

function MR:DisplayPositionMarker(position, index)
    -- Create or reuse position marker
    local marker = self.positionMarkers[index]
    if not marker then
        marker = CreateFrame("Frame", nil, self.mapDisplay)
        marker:SetSize(8, 8)
        
        -- Class symbol or icon
        marker.icon = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        marker.icon:SetPoint("CENTER")
        marker.icon:SetTextColor(1, 1, 1)
        
        -- Combat indicator (red border when in combat)
        marker.combatBorder = marker:CreateTexture(nil, "BACKGROUND")
        marker.combatBorder:SetAllPoints()
        marker.combatBorder:SetColorTexture(1, 0, 0, 0.3)
        marker.combatBorder:Hide()
        
        self.positionMarkers[index] = marker
    end
    
    -- Set class symbol
    local classSymbol = self.CLASS_ICONS[position.class] or "?"
    marker.icon:SetText(classSymbol)
    
    -- Position on map (simplified coordinate conversion)
    local displayX = (position.x % 1000) / 1000 * self.mapDisplay:GetWidth()
    local displayY = (position.y % 1000) / 1000 * self.mapDisplay:GetHeight()
    marker:SetPoint("CENTER", self.mapDisplay, "BOTTOMLEFT", displayX, displayY)
    
    -- Color based on health
    local healthColor = {1 - position.hp, position.hp, 0} -- Red when low health, green when high
    marker.icon:SetTextColor(healthColor[1], healthColor[2], healthColor[3])
    
    -- Show combat border
    if position.inCombat then
        marker.combatBorder:Show()
    else
        marker.combatBorder:Hide()
    end
    
    marker:Show()
    
    -- Create trail line to previous position
    if index > 1 and self.positionMarkers[index - 1] then
        self:CreateTrailLine(self.positionMarkers[index - 1], marker, position.inCombat)
    end
end

function MR:CreateTrailLine(fromMarker, toMarker, inCombat)
    -- Simple line creation using textures
    local line = CreateFrame("Frame", nil, self.mapDisplay)
    line:SetFrameLevel(self.mapDisplay:GetFrameLevel() - 1)
    
    local lineTexture = line:CreateTexture(nil, "BACKGROUND")
    lineTexture:SetColorTexture(inCombat and 1 or 0.5, inCombat and 0.2 or 0.5, 0.2, 0.6)
    lineTexture:SetHeight(2)
    
    -- Position line between markers (simplified)
    local fromX, fromY = fromMarker:GetCenter()
    local toX, toY = toMarker:GetCenter()
    
    if fromX and fromY and toX and toY then
        local distance = math.sqrt((toX - fromX)^2 + (toY - fromY)^2)
        lineTexture:SetWidth(distance)
        
        local centerX, centerY = (fromX + toX) / 2, (fromY + toY) / 2
        line:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
        
        lineTexture:SetAllPoints(line)
    end
end

function MR:ClearDisplay()
    -- Hide all position markers
    for _, marker in pairs(self.positionMarkers) do
        marker:Hide()
    end
    
    -- Clear trails would go here in a more complete implementation
    
    self.coordText:SetText("")
end

function MR:SaveRecording()
    if not self.currentRecording then return end
    
    -- In a full implementation, this would save to SavedVariables
    local recording = self.currentRecording
    print("TCP: Recording saved:", recording.name)
    print("  Duration:", string.format("%.1fs", recording.duration))
    print("  Zone:", recording.zoneName)
    print("  Positions:", #recording.positions)
    print("  Use '/tcp recordings' to manage saved recordings")
end

function MR:GetRecordings()
    return self.recordings
end

function MR:ExportRecording(recordingIndex)
    local recording = self.recordings[recordingIndex]
    if not recording then return nil end
    
    -- Create exportable data structure
    local exportData = {
        name = recording.name,
        zoneName = recording.zoneName,
        duration = recording.duration,
        positionCount = #recording.positions,
        created = date("%Y-%m-%d %H:%M:%S", recording.startTime)
    }
    
    return exportData
end

-- Initialize
MR:Initialize()
