-- MoreRVers - hooks/ui_helpers.lua (optional)
-- Responsibilities:
--  - Non-invasive client-side tweaks to lobby UI to display more than 4 seats
--  - Must be safe no-op when widgets not found

local M = {}

local function try_expand_lobby_list(mod)
  -- Try common patterns: converting fixed grid size to dynamic list or enabling scroll
  local ok, err = pcall(function()
    -- Attempt to locate a Lobby widget blueprint class
    local LobbyWidgetClass = UE.UClass.Load and UE.UClass.Load("/Game/**/UI/**/Lobby*_C")
    if not LobbyWidgetClass then return end
    -- Hook Construct to tweak panels
    RegisterHook(LobbyWidgetClass:GetPathName() .. ":Construct", function(self)
      mod.Log("Lobby UI Construct - attempting to enable overflow/scroll")
      -- Try common containers: ListView, ScrollBox, UniformGridPanel
      local scroll = self.ScrollBox_0 or self.ScrollBox or self:GetWidgetFromName and self:GetWidgetFromName("ScrollBox_Players")
      if scroll and scroll.SetAlwaysShowScrollbars then
        pcall(function()
          scroll:SetAlwaysShowScrollbars(true)
        end)
      end
      local list = self.ListView_0 or self.PlayerList or self:GetWidgetFromName and self:GetWidgetFromName("List_Players")
      if list and list.SetWheelScrollMultiplier then
        pcall(function()
          list:SetWheelScrollMultiplier(1.0)
        end)
      end
      -- For fixed grids, try increasing slots safely up to cap
      local grid = self.UniformGridPanel_0 or self.Grid_Players or self:GetWidgetFromName and self:GetWidgetFromName("Grid_Players")
      if grid and grid.SetMinDesiredSlotWidth then
        pcall(function()
          grid:SetMinDesiredSlotWidth(100.0)
        end)
      end
    end)
  end)
  if ok then
    mod.Log("UI helper: installed lobby Construct tweak (best-effort)")
  else
    mod.Debug("UI helper unavailable: " .. tostring(err))
  end
end

function M.install_hooks(mod)
  try_expand_lobby_list(mod)
end

return M


