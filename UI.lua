-- UI.lua
local addonName, TCP = ...

-- Create the main history window frame
local hist = CreateFrame("Frame", "TCPHistoryFrame", UIParent, "BasicFrameTemplate")
hist:SetSize(480, 400)
hist:SetPoint("CENTER")
hist:SetMovable(true)
hist:EnableMouse(true)
hist:RegisterForDrag("LeftButton")
hist:SetScript("OnDragStart", hist.StartMoving)
hist:SetScript("OnDragStop", hist.StopMovingOrSizing)
hist:Hide()

-- Set the title
hist.title = hist:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
hist.title:SetPoint("TOP", hist, "TOP", 0, -8)
hist.title:SetText("TankCoachPlus History")

-- Create content frame (scrollable area)
local content = CreateFrame("ScrollFrame", nil, hist, "UIPanelScrollFrameTemplate")
content:SetPoint("TOPLEFT", hist, "TOPLEFT", 10, -30)
content:SetPoint("BOTTOMRIGHT", hist, "BOTTOMRIGHT", -30, 10)

-- Create the actual content container
local contentChild = CreateFrame("Frame", nil, content)
contentChild:SetSize(430, 1) -- Height will be set dynamically
content:SetScrollChild(contentChild)

-- Create the text widget
contentChild.text = contentChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
contentChild.text:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 10, -10)
contentChild.text:SetJustifyH("LEFT")
contentChild.text:SetWidth(430)

-- Store reference for easy access
TCP.HistoryUI = hist
local content = contentChild -- Use contentChild as our content reference

-- Mini-sparklines for HPS/mana usage and cooldown timeline placeholders
content.sparklines = {}
function TCP:AddSparkline(pullIndex, data, type)
    local spark = CreateFrame("StatusBar", nil, content)
    spark:SetSize(400, 16)
    spark:SetPoint("TOPLEFT", 10, -((pullIndex-1)*30 + 200))
    spark:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    spark.bg = spark:CreateTexture(nil, "BACKGROUND")
    spark.bg:SetAllPoints(true)
    spark.bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    content.sparklines[pullIndex] = spark
    -- placeholder: set sparkline values based on 'data'
end

function TCP:RefreshSummaryUI()
    local lines = {}
    table.insert(lines, "───────────── TankCoachPlus Report ─────────────")
    table.insert(lines, string.format("Pulls Analyzed: %d", #TCP.history))

    -- Aggregate stats
    local statTotals = {Haste=0, Mastery=0, Versatility=0, Avoidance=0}
    local pullCount = #TCP.history
    
    if pullCount > 0 then
        for _, pull in ipairs(TCP.history) do
            if TCP.RecommendStats then
                local rec = TCP:RecommendStats()
                for stat, val in pairs(rec) do 
                    statTotals[stat] = statTotals[stat] + val 
                end
            end
        end

        table.insert(lines, "Overall Stat Trend:")
        for stat, total in pairs(statTotals) do
            table.insert(lines, string.format(" %s = %.2f", stat, total/pullCount))
        end

        -- Scorecard
        local function grade(value)
            if value >= 0.3 then return "A" 
            elseif value >= 0.25 then return "B" 
            elseif value >= 0.2 then return "C" 
            else return "D" 
            end
        end
        
        table.insert(lines, "\nScorecard:")
        table.insert(lines, string.format(" Cooldowns: %s", grade(statTotals.Versatility/pullCount)))
        table.insert(lines, string.format(" Damage Mitigation: %s", grade(statTotals.Haste/pullCount)))
        table.insert(lines, string.format(" Stat Focus: %s", grade(statTotals.Mastery/pullCount)))

        -- Pull-wise verdicts and clickable cooldown markers
        table.insert(lines, "\nVerdicts by Pull:")
        for i, pull in ipairs(TCP.history) do
            table.insert(lines, string.format(" Pull %d: %d events", i, #pull))
            -- Add sparkline and cooldown timeline
            TCP:AddSparkline(i, pull, "hps") -- example placeholder
            -- clickable marker logic placeholder
        end
    else
        table.insert(lines, "No pull data available yet.")
        table.insert(lines, "Complete some dungeon pulls to see analysis!")
    end

    table.insert(lines, "───────────── End of Report ─────────────")
    content.text:SetText(table.concat(lines, "\n"))
    
    -- Update the content height based on text
    local textHeight = content.text:GetStringHeight()
    contentChild:SetHeight(math.max(textHeight + 50, content:GetHeight()))
end

hist:SetScript("OnShow", function() 
    TCP:RefreshSummaryUI() 
end)
