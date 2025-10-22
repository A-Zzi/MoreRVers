-- MoreRVers - hooks/game_session.lua
-- Responsibilities:
--  - Locate AGameSession instances and CDO
--  - Set MaxPlayers on both live instance and CDO as early as possible
--  - Provide helper to obtain current player count

local M = {}

-- Utility: safe property set with pcall and logging
local function safe_set(mod, target, prop, value, label)
  local ok, err = pcall(function()
    target[prop] = value
  end)
  if ok then
    mod.Log(string.format("%s %s.%s := %s", label or "Set", target and target:GetName() or "<obj>", prop, tostring(value)))
  else
    mod.Warn(string.format("Failed to set %s on %s: %s", prop, label or "<obj>", tostring(err)))
  end
  return ok
end

-- Helper: attempt to get current players from GameSession or GameState
local function try_get_current_players()
  -- Multiple strategies; all guarded by pcall
  -- 1) Use UWorld: GetGameState()->PlayerArray length
  local ok, count = pcall(function()
    local world = nil
    if UE.UWorld.GetAllWorlds then
      world = UE.UWorld.GetAllWorlds()[1]
    end
    if not world then return nil end
    local gs = world:GetGameState()
    if gs and gs.PlayerArray then
      return #gs.PlayerArray
    end
    return nil
  end)
  if ok and type(count) == "number" then return count end

  -- 2) Fallback: count PlayerController in world
  ok, count = pcall(function()
    local world = nil
    if UE.UWorld.GetAllWorlds then
      world = UE.UWorld.GetAllWorlds()[1]
    end
    if not world then return nil end
    local num = 0
    local controllers = nil
    if world.GetPlayerControllerIterator then
      controllers = world:GetPlayerControllerIterator()
    end
    if controllers then
      for _, _pc in ipairs(controllers) do
        num = num + 1
      end
      return num
    end
    return nil
  end)
  if ok and type(count) == "number" then return count end

  return nil
end

-- Print all GameSession properties (troubleshooting aid)
local function print_gamesession_props(mod, gs)
  if not gs then return end
  local ok, props = pcall(function()
    if gs.GetProperties then return gs:GetProperties() end
    return nil
  end)
  if ok and props then
    mod.Debug("AGameSession properties dump start")
    for k, v in pairs(props) do
      mod.Debug(string.format("  %s = %s", tostring(k), tostring(v)))
    end
    mod.Debug("AGameSession properties dump end")
  else
    mod.Debug("AGameSession GetProperties() unavailable; skipping dump")
  end
end

-- Install hooks: set MaxPlayers on BeginPlay and also attempt immediate CDO change
function M.install_hooks(mod)
  -- Check if UE API is available
  if not UE then
    mod.Warn("UE API not available yet - hooks will be registered on first use")
    return false
  end

  -- Early: find the CDO of AGameSession and set MaxPlayers
  local GSClass = nil
  local okFind, errFind = pcall(function()
    if UE.FindFirstOf then
      GSClass = UE.FindFirstOf("GameSession")
    elseif StaticFindObject then
      GSClass = StaticFindObject("/Script/Engine.GameSession")
    end
  end)
  if not okFind then
    mod.Debug("Could not resolve AGameSession class: " .. tostring(errFind))
  end

  if GSClass then
    local okCDO, cdo = pcall(function() return GSClass:GetDefaultObject() end)
    if okCDO and cdo then
      safe_set(mod, cdo, "MaxPlayers", mod.TargetMaxPlayers, "CDO")
    else
      mod.Debug("Failed to get AGameSession CDO")
    end
  end

  -- Try multiple hook signatures that might exist
  local signatures = {
    "/Script/Engine.GameSession:ReceiveBeginPlay",
    "Function /Script/Engine.GameSession:K2_PostBeginPlay",
  }
  
  local hooked = false
  for _, sig in ipairs(signatures) do
    local okHook, errHook = pcall(function()
      RegisterHook(sig, function(self)
      -- self is AGameSession instance
      mod.Log("AGameSession:ReceiveBeginPlay - applying MaxPlayers override")

      -- Snapshot original value for logging
      local original = nil
      pcall(function() original = self.MaxPlayers end)

      local okSetLive = safe_set(mod, self, "MaxPlayers", mod.TargetMaxPlayers, "Live")
      local okSetCDO = false
      local cdo = nil
      local okGetCDO, errGetCDO = pcall(function()
        cdo = self:GetClass():GetDefaultObject()
      end)
      if okGetCDO and cdo then
        okSetCDO = safe_set(mod, cdo, "MaxPlayers", mod.TargetMaxPlayers, "CDO")
      else
        mod.Warn("Could not fetch GameSession CDO in BeginPlay: " .. tostring(errGetCDO))
      end

      mod.Log(string.format("AGameSession MaxPlayers original=%s liveSet=%s cdoSet=%s → %d",
        tostring(original), tostring(okSetLive), tostring(okSetCDO), mod.TargetMaxPlayers))

        -- Optional: dump properties once on first run to aid troubleshooting
        print_gamesession_props(mod, self)
      end)
    end)

    if okHook then
      mod.Log("Hooked: " .. sig)
      hooked = true
      break
    else
      mod.Debug("Failed to hook " .. sig .. ": " .. tostring(errHook))
    end
  end
  
  if not hooked then
    mod.Warn("Could not hook any GameSession BeginPlay functions - will try runtime patching")
  end
  
  return hooked
end

-- Expose helper
function M.get_current_player_count()
  return try_get_current_players()
end

return M


