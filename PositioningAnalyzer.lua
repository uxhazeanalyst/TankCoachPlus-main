-- PositioningAnalyzer.lua - Route & Positioning Feedback
local addonName, TCP = ...

TCP.PositioningAnalyzer = {}
local PA = TCP.PositioningAnalyzer

-- Positioning tracking data
PA.playerPositions = {}
PA.groupPositions = {}
PA.mobPositions = {}
PA.positioningEvents = {}
PA.lastPositionUpdate = 0
PA.updateInterval = 0.5 -- Update every 0.5 seconds

-- Positioning thresholds
PA.POSITIONING_RULES = {
    maxHealerDistance = 30, -- Max distance from healer
    maxGroupSpread = 40,    -- Max distance from group center
    minMobDistance = 8,     -- Min distance between mob groups
    optimalTankPosition = 15, -- Optimal distance from group center
    wallDistance = 5,       -- Distance to maintain from walls
    dangerZoneRadius = 8    -- Radius around dangerous ground effects
}

function PA:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    -- Start position tracking timer
    self.positionTimer = C_Timer.NewTicker(self.updateInterval, function()
        self:UpdatePositions()
    end)
    
    self:CreatePositioningFrame()
end

function PA:CreatePositioningFrame()
    self.posFrame = CreateFrame("Frame", "TCPPositioningFrame", UIParent, "BackdropTemplate")
    self.posFrame:SetSize(280, 120)
    self.posFrame:SetPoint("BOTTOMRIGHT", -20, 100)
    
    -- Set backdrop (using the modern API)
    if self.posFrame.SetBackdrop then
        self.posFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    else
        -- Fallback for older API
        self.posFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
    end
    
    self.posFrame:Hide()
    
    -- Title
    self.posFrame.title = self.posFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.posFrame.title:SetPoint("TOP", 0, -8)
    self.posFrame.title:SetText("Positioning Analysis")
    
    -- Content
    self.posFrame.content = self.posFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.posFrame.content:SetPoint("TOPLEFT", 8, -25)
    self.posFrame.content:SetPoint("BOTTOMRIGHT", -8, 8)
    self.posFrame.content:SetJustifyH("LEFT")
    self.posFrame.content:SetJustifyV("TOP")
end

function PA:UpdatePositions()
    if not UnitExists("player") then return end
    
    local currentTime = GetTime()
    self.lastPositionUpdate = currentTime
    
    -- Get player position
    local playerX, playerY = UnitPosition("player")
    if not playerX then return end
    
    -- Store player position
    table.insert(self.playerPositions, {
        x = playerX,
        y = playerY,
        time = currentTime,
        inCombat = UnitAffectingCombat("player")
    })
    
    -- Clean old positions (keep last 30 seconds)
    for i = #self.playerPositions, 1, -1 do
        if currentTime - self.playerPositions[i].time > 30 then
            table.remove(self.playerPositions, i)
        end
    end
    
    -- Update group positions
    self:UpdateGroupPositions(currentTime)
    
    -- Update mob positions
    self:UpdateMobPositions(currentTime)
    
    -- Analyze positioning if in combat
    if UnitAffectingCombat("player") then
        self:AnalyzePositioning()
    else
        self.posFrame:Hide()
    end
end

function PA:UpdateGroupPositions(currentTime)
    local groupData = {
        time = currentTime,
        members = {}
    }
    
    -- Check party/raid members
    local groupSize = GetNumGroupMembers()
    if groupSize > 0 then
        for i = 1, groupSize do
            local unit = (IsInRaid() and "raid" or "party") .. i
            if UnitExists(unit) then
                local x, y = UnitPosition(unit)
                if x and y then
                    local role = UnitGroupRolesAssigned(unit)
                    table.insert(groupData.members, {
                        unit = unit,
                        name = UnitName(unit),
                        x = x,
                        y = y,
                        role = role,
                        hp = UnitHealth(unit) / math.max(UnitHealthMax(unit), 1)
                    })
                end
            end
        end
    end
    
    table.insert(self.groupPositions, groupData)
    
    -- Clean old group positions
    for i = #self.groupPositions, 1, -1 do
        if currentTime - self.groupPositions[i].time > 30 then
            table.remove(self.groupPositions, i)
        end
    end
end

function PA:UpdateMobPositions(currentTime)
    local mobData = {
        time = currentTime,
        mobs = {}
    }
    
    -- Check nameplate units (enemies)
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) then
            local x, y = UnitPosition(unit)
            if x and y then
                table.insert(mobData.mobs, {
                    unit = unit,
                    name = UnitName(unit),
                    x = x,
                    y = y,
                    hp = UnitHealth(unit) / math.max(UnitHealthMax(unit), 1),
                    guid = UnitGUID(unit)
                })
            end
        end
    end
    
    table.insert(self.mobPositions, mobData)
    
    -- Clean old mob positions
    for i = #self.mobPositions, 1, -1 do
        if currentTime - self.mobPositions[i].time > 30 then
            table.remove(self.mobPositions, i)
        end
    end
end

function PA:AnalyzePositioning()
    if #self.playerPositions == 0 or #self.groupPositions == 0 then
        return
    end
    
    local currentPlayer = self.playerPositions[#self.playerPositions]
    local currentGroup = self.groupPositions[#self.groupPositions]
    local currentMobs = #self.mobPositions > 0 and self.mobPositions[#self.mobPositions] or nil
    
    local analysis = {
        issues = {},
        suggestions = {},
        metrics = {}
    }
    
    -- Analyze distance from healer
    local healerDistance = self:GetDistanceToHealer(currentPlayer, currentGroup)
    if healerDistance then
        analysis.metrics.healerDistance = healerDistance
        if healerDistance > self.POSITIONING_RULES.maxHealerDistance then
            table.insert(analysis.issues, string.format("Far from healer (%.1fy)", healerDistance))
            table.insert(analysis.suggestions, "Move closer to healer for better support")
        end
    end
    
    -- Analyze group spread
    local groupCenter = self:CalculateGroupCenter(currentGroup)
    if groupCenter then
        local distanceFromCenter = self:CalculateDistance(currentPlayer.x, currentPlayer.y, groupCenter.x, groupCenter.y)
        analysis.metrics.groupDistance = distanceFromCenter
        
        if distanceFromCenter > self.POSITIONING_RULES.maxGroupSpread then
            table.insert(analysis.issues, "Too far from group")
            table.insert(analysis.suggestions, "Stay closer to group for coordination")
        end
    end
    
    -- Analyze mob positioning
    if currentMobs and #currentMobs.mobs > 1 then
        local mobCleaveAnalysis = self:AnalyzeMobCleavePositioning(currentPlayer, currentMobs)
        if mobCleaveAnalysis.canImprove then
            table.insert(analysis.suggestions, "Reposition mobs for better cleave damage")
        end
        
        -- Check for mob spread
        local mobSpread = self:CalculateMobSpread(currentMobs)
        analysis.metrics.mobSpread = mobSpread
        if mobSpread > 15 then
            table.insert(analysis.issues, "Mobs too spread out for cleave")
            table.insert(analysis.suggestions, "Group mobs closer together")
        end
    end
    
    -- Check for movement patterns (kiting analysis)
    local movementAnalysis = self:AnalyzeMovementPattern()
    if movementAnalysis.isKiting and movementAnalysis.efficiency < 0.7 then
        table.insert(analysis.suggestions, "Optimize kiting path - move more efficiently")
    end
    
    -- Check for wall positioning
    local wallProximity = self:EstimateWallProximity(currentPlayer)
    if wallProximity and wallProximity < self.POSITIONING_RULES.wallDistance then
        table.insert(analysis.issues, "Too close to walls")
        table.insert(analysis.suggestions, "Move to open area for better mobility")
    end
    
    self:UpdatePositioningDisplay(analysis)
end

function PA:GetDistanceToHealer(playerPos, groupData)
    local closestHealerDist = nil
    
    for _, member in ipairs(groupData.members) do
        if member.role == "HEALER" then
            local dist = self:CalculateDistance(playerPos.x, playerPos.y, member.x, member.y)
            if not closestHealerDist or dist < closestHealerDist then
                closestHealerDist = dist
            end
        end
    end
    
    return closestHealerDist
end

function PA:CalculateGroupCenter(groupData)
    if #groupData.members == 0 then return nil end
    
    local sumX, sumY = 0, 0
    local count = 0
    
    for _, member in ipairs(groupData.members) do
        sumX = sumX + member.x
        sumY = sumY + member.y
        count = count + 1
    end
    
    return {
        x = sumX / count,
        y = sumY / count
    }
end

function PA:CalculateDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function PA:AnalyzeMobCleavePositioning(playerPos, mobData)
    if #mobData.mobs < 2 then
        return {canImprove = false}
    end
    
    local mobCenter = {x = 0, y = 0}
    for _, mob in ipairs(mobData.mobs) do
        mobCenter.x = mobCenter.x + mob.x
        mobCenter.y = mobCenter.y + mob.y
    end
    mobCenter.x = mobCenter.x / #mobData.mobs
    mobCenter.y = mobCenter.y / #mobData.mobs
    
    -- Check if player is positioned well for cleave
    local distanceFromMobCenter = self:CalculateDistance(playerPos.x, playerPos.y, mobCenter.x, mobCenter.y)
    
    -- Calculate how tightly grouped the mobs are
    local maxMobDistance = 0
    for _, mob in ipairs(mobData.mobs) do
        local distFromCenter = self:CalculateDistance(mob.x, mob.y, mobCenter.x, mobCenter.y)
        if distFromCenter > maxMobDistance then
            maxMobDistance = distFromCenter
        end
    end
    
    return {
        canImprove = maxMobDistance > 10, -- Mobs are spread > 10 yards
        distanceFromCenter = distanceFromMobCenter,
        mobSpread = maxMobDistance
    }
end

function PA:CalculateMobSpread(mobData)
    if #mobData.mobs < 2 then return 0 end
    
    local maxDist = 0
    for i = 1, #mobData.mobs do
        for j = i + 1, #mobData.mobs do
            local dist = self:CalculateDistance(
                mobData.mobs[i].x, mobData.mobs[i].y,
                mobData.mobs[j].x, mobData.mobs[j].y
            )
            if dist > maxDist then
                maxDist = dist
            end
        end
    end
    
    return maxDist
end

function PA:AnalyzeMovementPattern()
    if #self.playerPositions < 5 then
        return {isKiting = false, efficiency = 1.0}
    end
    
    local recentPositions = {}
    local currentTime = GetTime()
    
    -- Get last 5 seconds of positions
    for i = #self.playerPositions, 1, -1 do
        if currentTime - self.playerPositions[i].time <= 5 then
            table.insert(recentPositions, self.playerPositions[i])
        end
    end
    
    if #recentPositions < 3 then
        return {isKiting = false, efficiency = 1.0}
    end
    
    -- Calculate total distance moved
    local totalDistance = 0
    for i = 2, #recentPositions do
        totalDistance = totalDistance + self:CalculateDistance(
            recentPositions[i-1].x, recentPositions[i-1].y,
            recentPositions[i].x, recentPositions[i].y
        )
    end
    
    -- Calculate direct distance (efficiency)
    local directDistance = self:CalculateDistance(
        recentPositions[1].x, recentPositions[1].y,
        recentPositions[#recentPositions].x, recentPositions[#recentPositions].y
    )
    
    local efficiency = totalDistance > 0 and (directDistance / totalDistance) or 1.0
    local isKiting = totalDistance > 20 -- Moved more than 20 yards in 5 seconds
    
    return {
        isKiting = isKiting,
        efficiency = efficiency,
        totalDistance = totalDistance,
        directDistance = directDistance
    }
end

function PA:EstimateWallProximity(playerPos)
    -- This is a simplified wall detection
    -- In a full implementation, you'd need zone-specific boundary data
    -- For now, we'll use a heuristic based on player movement constraints
    
    -- Check if player has been "stuck" in a direction recently
    if #self.playerPositions < 3 then return nil end
    
    local recent = {}
    local currentTime = GetTime()
    for i = #self.playerPositions, 1, -1 do
        if currentTime - self.playerPositions[i].time <= 2 then
            table.insert(recent, self.playerPositions[i])
        end
    end
    
    if #recent < 3 then return nil end
    
    -- Simple heuristic: if player hasn't moved much but is trying to move
    -- (indicated by combat activity), they might be near a wall
    local totalMovement = 0
    for i = 2, #recent do
        totalMovement = totalMovement + self:CalculateDistance(
            recent[i-1].x, recent[i-1].y, recent[i].x, recent[i].y
        )
    end
    
    if totalMovement < 3 and recent[1].inCombat then
        return 3 -- Estimate 3 yards from wall if not moving much in combat
    end
    
    return nil
end

function PA:UpdatePositioningDisplay(analysis)
    if #analysis.issues == 0 and #analysis.suggestions == 0 then
        self.posFrame:Hide()
        return
    end
    
    local lines = {}
    
    -- Show metrics
    if analysis.metrics.healerDistance then
        table.insert(lines, string.format("Healer: %.1fy", analysis.metrics.healerDistance))
    end
    if analysis.metrics.groupDistance then
        table.insert(lines, string.format("Group: %.1fy", analysis.metrics.groupDistance))
    end
    if analysis.metrics.mobSpread then
        table.insert(lines, string.format("Mob spread: %.1fy", analysis.metrics.mobSpread))
    end
    
    -- Show issues
    if #analysis.issues > 0 then
        table.insert(lines, "|cFFFF6B6BIssues:|r")
        for _, issue in ipairs(analysis.issues) do
            table.insert(lines, "• " .. issue)
        end
    end
    
    -- Show suggestions
    if #analysis.suggestions > 0 then
        table.insert(lines, "|cFF6BCF7FSuggestions:|r")
        for i, suggestion in ipairs(analysis.suggestions) do
            if i <= 2 then -- Show max 2 suggestions to avoid clutter
                table.insert(lines, "• " .. suggestion)
            end
        end
    end
    
    self.posFrame.content:SetText(table.concat(lines, "\n"))
    self.posFrame:Show()
end

function PA:GetPositioningStats()
    local stats = {
        totalPositions = #self.playerPositions,
        averageHealerDistance = 0,
        averageGroupDistance = 0,
        timeSpentKiting = 0,
        positioningIssues = 0
    }
    
    -- Calculate averages and issues over recent history
    local recentAnalyses = {}
    -- This would store results of recent analyses
    
    return stats
end

function PA:ResetPositionData()
    self.playerPositions = {}
    self.groupPositions = {}
    self.mobPositions = {}
    self.positioningEvents = {}
end

-- Initialize
PA:Initialize()
