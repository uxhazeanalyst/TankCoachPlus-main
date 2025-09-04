--- CombatText.lua
local addonName, TCP = ...

-- Helper to show floating combat text or fallback to UIErrorsFrame
function TCP:ShowCombatText(msg, r, g, b)
  r, g, b = r or 1, g or 1, b or 0  -- default yellow if not specified

  if CombatText_AddMessage then
    -- Use WoW's built-in floating combat text system
    CombatText_AddMessage(msg, CombatText_StandardScroll, r, g, b)
  else
    -- Fallback to UIErrorsFrame if CombatText system is disabled
    UIErrorsFrame:AddMessage(msg, r, g, b)
  end
end
