-- AffixCoach.lua - Affix-Specific Coaching
local addonName, TCP = ...

TCP.AffixCoach = {}
local AC = TCP.AffixCoach

-- Affix definitions and coaching data
AC.AFFIX_DATA = {
    [4] = { -- Necrotic
        name = "Necrotic",
        type = "Tank",
        maxStacks = 40,
        dangerStacks = 30,
        coaching = {
            ["low"] = "Necrotic stacks building - consider kiting soon",
            ["medium"] = "HIGH NECROTIC STACKS - kite now!",
            ["high"] = "CRITICAL NECROTIC - must kite immediately!"
        }
    },
    [7] = { -- Bolstering
        name = "Bolstering",
        type = "DPS/Tank",
        coaching = {
            ["uneven_hp"] = "Uneven mob HP detected - focus fire needed",
            ["low_hp_mobs"] = "Some mobs very low - coordinate kill timing"
        }
    },
    [8] = { -- Sanguine
        name = "Sanguine",
        type = "Tank",
        coaching = {
            ["pool_created"] = "Sanguine pool created - move mobs away",
            ["in_pool"] = "Mobs in sanguine - reposition immediately"
        }
    },
    [9] = { -- Tyrannical
        name = "Tyrannical",
        type = "All",
        coaching = {
            ["boss_start"] = "Tyrannical week - extra boss mechanics and damage",
            ["high_boss_damage"] = "High boss damage - use major cooldowns"
        }
    },
    [10] = { -- Fortified
        name = "Fortified",
        type = "All",
        coaching = {
            ["trash_damage"] = "Fortified - trash hits harder, use cooldowns",
            ["large_pull"] = "Large fortified pull - high damage incoming"
        }
    },
    [11] = { -- Bursting
        name = "Bursting",
        type = "All",
        coaching = {
            ["stacks_building"] = "Bursting stacks: %d - slow down kills",
            ["high_stacks"] = "High bursting stacks - stop DPS momentarily"
        }
    },
    [12] = { -- Grievous
        name = "Grievous",
        type = "Healer",
        coaching = {
            ["low_health"] = "Below 90% HP - grievous will apply",
            ["grievous_stacks"] = "Grievous stacks: %d - need healing"
        }
    },
    [13] = { -- Explosive
        name = "Explosive",
        type = "DPS",
        coaching = {
            ["orb_spawned"] = "Explosive orb spawned - kill quickly",
            ["multiple_orbs"] = "%d explosive orbs active - prioritize"
        }
    },
    [14] = { -- Quaking
        name = "Quaking",
        type = "All",
        coaching = {
            ["quake_soon"] = "Quaking in %d seconds - spread out",
            ["quaking_active"] = "Quaking active - avoid interrupts"
        }
    }
}

-- Current affix states
AC.currentAffixes = {}
AC.affixStates = {}
AC.lastWarning = {}

function AC:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("UNIT_AURA")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("CHALLENGE_MODE_START")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:HandleCombatEvent()
        elseif event == "UNIT_AURA" then
            self:HandleAuraEvent(...)
        elseif event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" then
            self:UpdateActiveAffixes()
        end
    end)
    
    self:CreateAffixFrame()
end

function AC:CreateAffixFrame()
    -- Try modern approach first, fallback to older method
    local template = nil
    if BackdropTemplateMixin then
        template = "BackdropTemplate"
    end
    
    self.affixFrame = CreateFrame("Frame", "TCPAffixFrame", UIParent, template)
    self.affixFrame:SetSize(250, 100)
    self.affixFrame:SetPoint("TOPLEFT", 20, -100)
    
    -- Apply backdrop with compatibility check
    local backdropInfo = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    
    if self.affixFrame.SetBackdrop then
        self.affixFrame:SetBackdrop(backdropInfo)
    elseif BackdropTemplateMixin then
        -- Use mixin directly
        Mixin(self.affixFrame, BackdropTemplateMixin)
        self.affixFrame:SetBackdrop(backdropInfo)
    end
    
    self.affixFrame:Hide()
    
    -- Title
    self.affixFrame.title = self.affixFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.affixFrame.title:SetPoint("TOP", 0, -8)
    self.affixFrame.title:SetText("Active Affixes")
    
    -- Content
    self.affixFrame.content = self.affixFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.affixFrame.content:SetPoint("TOPLEFT", 8, -25)
    self.affixFrame.content:SetPoint("BOTTOMRIGHT", -8, 8)
    self.affixFrame.content:SetJustifyH("LEFT")
    self.affixFrame.content:SetJustifyV("TOP")
end

function AC:UpdateActiveAffixes()
    self.currentAffixes = {}
    
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local keystoneInfo = C_ChallengeMode.GetActiveKeystoneInfo()
        if keystoneInfo and type(keystoneInfo) == "table" then
            local _, affixes = keystoneInfo
            if affixes and type(affixes) == "table" then
                for _, affixInfo in ipairs(affixes) do
                    local affixID = affixInfo.id or affixInfo
                    if self.AFFIX_DATA[affixID] then
                        table.insert(self.currentAffixes, affixID)
                        self.affixStates[affixID] = {}
                    end
                end
            end
        end
    end
    
    self:UpdateAffixDisplay()
end

function AC:UpdateAffixDisplay()
    if #self.currentAffixes == 0 then
        self.affixFrame:Hide()
        return
    end
    
    local lines = {}
    for _, affixID in ipairs(self.currentAffixes) do
        local affixData = self.AFFIX_DATA[affixID]
        local state = self.affixStates[affixID] or {}
        
        local line = affixData.name
        if affixID == 4 and state.stacks then -- Necrotic
            line = line .. " (" .. state.stacks .. " stacks)"
        elseif affixID == 11 and state.stacks then -- Bursting
            line = line .. " (" .. state.stacks .. " stacks)"
        elseif affixID == 12 and state.stacks then -- Grievous
            line = line .. " (" .. state.stacks .. " stacks)"
        elseif affixID == 13 and state.orbCount then -- Explosive
            line = line .. " (" .. state.orbCount .. " orbs)"
        end
        
        table.insert(lines, line)
    end
    
    self.affixFrame.content:SetText(table.concat(lines, "\n"))
    self.affixFrame:Show()
end

function AC:HandleCombatEvent()
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    
    -- Handle affix-specific events
    for _, affixID in ipairs(self.currentAffixes) do
        if affixID == 8 then -- Sanguine
            self:HandleSanguine(subEvent, sourceGUID, destGUID, spellID)
        elseif affixID == 7 then -- Bolstering
            self:HandleBolstering(subEvent, sourceGUID, destGUID)
        elseif affixID == 13 then -- Explosive
            self:HandleExplosive(subEvent, sourceGUID, destGUID, spellID)
        end
    end
end

function AC:HandleAuraEvent(unit)
    if not UnitExists(unit) then return end
    
    local playerGUID = UnitGUID("player")
    
    for _, affixID in ipairs(self.currentAffixes) do
        if affixID == 4 then -- Necrotic
            self:TrackNecrotic(unit, playerGUID)
        elseif affixID == 11 then -- Bursting
            self:TrackBursting(unit)
        elseif affixID == 12 then -- Grievous
            self:TrackGrievous(unit, playerGUID)
        end
    end
end

function AC:TrackNecrotic(unit, playerGUID)
    if UnitGUID(unit) ~= playerGUID then return end
    
    -- Look for Necrotic Wound debuff (spell ID 209858)
    local stacks = 0
    for i = 1, 40 do
        local name, _, count, _, _, _, _, _, _, spellId = UnitDebuff(unit, i)
        if spellId == 209858 then -- Necrotic Wound
            stacks = count or 0
            break
        end
    end
    
    self.affixStates[4].stacks = stacks
    
    -- Provide coaching based on stack count
    if stacks >= self.AFFIX_DATA[4].dangerStacks then
        self:GiveAffixAdvice(4, "high", string.format("NECROTIC: %d stacks - KITE NOW!", stacks))
    elseif stacks >= 20 then
        self:GiveAffixAdvice(4, "medium", string.format("Necrotic: %d stacks - consider kiting", stacks))
    elseif stacks >= 10 then
        self:GiveAffixAdvice(4, "low", string.format("Necrotic building: %d stacks", stacks))
    end
    
    self:UpdateAffixDisplay()
end

function AC:TrackBursting(unit)
    -- Look for Burst debuff
    local stacks = 0
    for i = 1, 40 do
        local name, _, count, _, _, _, _, _, _, spellId = UnitDebuff(unit, i)
        if spellId == 240559 then -- Burst
            stacks = count or 0
            break
        end
    end
    
    if stacks > 0 then
        self.affixStates[11].stacks = stacks
        
        if stacks >= 8 then
            self:GiveAffixAdvice(11, "high", string.format("HIGH BURSTING: %d stacks - stop DPS!", stacks))
        elseif stacks >= 5 then
            self:GiveAffixAdvice(11, "medium", string.format("Bursting: %d stacks - slow kills", stacks))
        end
        
        self:UpdateAffixDisplay()
    end
end

function AC:TrackGrievous(unit, playerGUID)
    if UnitGUID(unit) ~= playerGUID then return end
    
    -- Look for Grievous Wound
    local stacks = 0
    for i = 1, 40 do
        local name, _, count, _, _, _, _, _, _, spellId = UnitDebuff(unit, i)
        if spellId == 240559 then -- Grievous Wound (placeholder ID)
            stacks = count or 0
            break
        end
    end
    
    self.affixStates[12].stacks = stacks
    
    if stacks > 0 then
        self:GiveAffixAdvice(12, "active", string.format("Grievous: %d stacks - need healing", stacks))
        self:UpdateAffixDisplay()
    end
end

function AC:HandleSanguine(subEvent, sourceGUID, destGUID, spellID)
    -- Track sanguine pool creation and positioning
    if subEvent == "SPELL_SUMMON" and spellID == 218674 then -- Sanguine Ichor
        self:GiveAffixAdvice(8, "pool_created", "Sanguine pool created - reposition mobs")
    end
end

function AC:HandleBolstering(subEvent, sourceGUID, destGUID)
    if subEvent == "UNIT_DIED" then
        -- Check for nearby low-HP mobs that will get bolstered
        local nearbyMobs = {}
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if UnitExists(unit) and UnitCanAttack("player", unit) then
                local hp = UnitHealth(unit)
                local maxHP = UnitHealthMax(unit)
                if hp > 0 and maxHP > 0 then
                    table.insert(nearbyMobs, {unit = unit, hpPercent = hp / maxHP})
                end
            end
        end
        
        if #nearbyMobs > 1 then
            table.sort(nearbyMobs, function(a, b) return a.hpPercent < b.hpPercent end)
            local lowest = nearbyMobs[1].hpPercent
            local highest = nearbyMobs[#nearbyMobs].hpPercent
            
            if highest - lowest > 0.3 then -- 30% HP difference
                self:GiveAffixAdvice(7, "uneven_hp", "Bolstering: Uneven mob HP - focus fire needed")
            end
        end
    end
end

function AC:HandleExplosive(subEvent, sourceGUID, destGUID, spellID)
    if subEvent == "SPELL_SUMMON" and spellID == 240446 then -- Explosive Orb
        if not self.affixStates[13].orbCount then
            self.affixStates[13].orbCount = 0
        end
        self.affixStates[13].orbCount = self.affixStates[13].orbCount + 1
        
        if self.affixStates[13].orbCount == 1 then
            self:GiveAffixAdvice(13, "orb_spawned", "Explosive orb spawned - kill quickly")
        else
            self:GiveAffixAdvice(13, "multiple_orbs", 
                string.format("%d explosive orbs - prioritize", self.affixStates[13].orbCount))
        end
        
        self:UpdateAffixDisplay()
    elseif subEvent == "UNIT_DIED" and spellID == 240446 then
        if self.affixStates[13].orbCount then
            self.affixStates[13].orbCount = math.max(0, self.affixStates[13].orbCount - 1)
            self:UpdateAffixDisplay()
        end
    end
end

function AC:GiveAffixAdvice(affixID, severity, message)
    local currentTime = GetTime()
    local lastWarningTime = self.lastWarning[affixID] or 0
    
    -- Don't spam warnings (minimum 3 seconds between same affix warnings)
    if currentTime - lastWarningTime < 3 then
        return
    end
    
    self.lastWarning[affixID] = currentTime
    
    -- Determine alert priority based on severity
    local isHighPriority = severity == "high" or severity == "critical"
    
    -- Show warning
    if TCP.CooldownTracker and TCP.CooldownTracker.TriggerAlert then
        local title = self.AFFIX_DATA[affixID].name .. " Warning"
        TCP.CooldownTracker:TriggerAlert(title, message)
    end
    
    -- Chat notification
    if TCP.debug or isHighPriority then
        print("|cFFFFD700TCP Affix:|r " .. message)
    end
    
    -- Play sound for high priority warnings
    if isHighPriority then
        PlaySound(8959) -- Warning sound
    end
end

function AC:GetAffixSuggestions()
    local suggestions = {}
    
    for _, affixID in ipairs(self.currentAffixes) do
        local affixData = self.AFFIX_DATA[affixID]
        local state = self.affixStates[affixID] or {}
        
        if affixID == 4 and state.stacks and state.stacks > 15 then -- Necrotic
            table.insert(suggestions, "Consider kiting to drop necrotic stacks")
        elseif affixID == 9 then -- Tyrannical
            table.insert(suggestions, "Save major cooldowns for boss encounters")
        elseif affixID == 10 then -- Fortified
            table.insert(suggestions, "Use cooldowns more frequently on trash")
        elseif affixID == 11 and state.stacks and state.stacks > 3 then -- Bursting
            table.insert(suggestions, "Coordinate kill timing to manage bursting")
        end
    end
    
    return suggestions
end

function AC:GetAffixStats()
    local stats = {
        activeAffixes = {},
        warnings = 0,
        affixSpecificData = {}
    }
    
    for _, affixID in ipairs(self.currentAffixes) do
        table.insert(stats.activeAffixes, self.AFFIX_DATA[affixID].name)
    end
    
    -- Count warnings given
    for affixID, _ in pairs(self.lastWarning) do
        stats.warnings = stats.warnings + 1
    end
    
    return stats
end

-- Initialize
AC:Initialize()
