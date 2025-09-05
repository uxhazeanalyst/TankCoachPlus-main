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

-- Class symbols for display
MR.CLASS_SYMBOLS = {
    WARRIOR = "🛡️",
    PALADIN = "⚔️",
    HUNTER = "🏹",
    ROGUE = "🗡️",
    PRIEST = "✨",
    SHAMAN = "⚡",
    MAGE = "🔮",
    WARLOCK = "🔥",
    MONK = "👊",
    DRUID = "🌿",
    DEMONHUNTER = "😈",
    DEATHKNIGHT = "💀",
    EVOKER = "🐲"
}

-- Fallback text symbols for better compatibility
MR.CLASS_ICONS = {
    WARRIOR = "W",
    PALADIN = "P", 
    HUNTER = "H",
    ROGUE = "R",
    PRIEST = "Pr",
    SHAMAN = "S",
    MAGE = "M",
    WARLOCK = "Wl",
    MONK = "Mn",
    DRUID = "D",
    DEMONHUNTER = "DH",
    DEATHKNIGHT = "DK",
    EVOKER = "E"
}

function MR:Initialize()
    self:CreateMapFrame()
    self:CreateControlPanel()
    
    -- Hook into pull analyzer for automatic recording
    if TCP.PullAnalyzer then
        self:HookPullAnalyzer()
    end
end

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
    self.mapDisplay = CreateFrame("Frame", nil, self.mapFrame)
    self.mapDisplay:SetPoint("TOPLEFT", 15, -35)
    self.mapDisplay:SetPoint("BOTTOMRIGHT", -35, 50)
    self.mapDisplay:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    self.mapDisplay:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
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
