-- MoreRVers - hooks/join_gate.lua
-- Responsibilities:
--  - Discover and hook common join validation paths
--  - Allow joins when current players < TargetMaxPlayers
--  - Track metrics for allowed joins beyond 4

local M = {}

-- Return true to allow join, false to deny (or nil to defer)
local function should_allow(mod, currentPlayers)
  local cap = tonumber(mod.TargetMaxPlayers) or 8
  if not currentPlayers then return nil end
  if currentPlayers < cap then
    return true
  end
  return false
end

-- Wrapper that attempts to force-allow below cap while preserving original logic otherwise
local function make_gate_wrapper(mod, fnName)
  return function(self, ...)
    local cur = nil
    local okCount, errCount = pcall(function()
      if mod.get_current_player_count then
        return mod.get_current_player_count()
      end
      if mod and mod.Metrics then return nil end
    end)
    if okCount then cur = errCount else mod.Debug("join_gate count error: " .. tostring(errCount)) end

    local allow = should_allow(mod, cur)
    if allow == true then
      -- Metrics: only count when beyond 4
      if cur and cur >= 4 and mod.Metrics then
        mod.Metrics.forcedAllows = (mod.Metrics.forcedAllows or 0) + 1
      end
      mod.Log(string.format("Join allowed by MoreRVers (%s). current=%s cap=%d forcedBeyond4=%d",
        fnName, tostring(cur), mod.TargetMaxPlayers, mod.Metrics.forcedAllows or 0))
      -- Return value conventions vary; in many games CanPlayerJoin returns bool
      return true
    end

    -- Fall back to original function
    return nil -- nil tells UE4SS to continue the original function normally
  end
end

function M.install_hooks(mod)
  -- The actual function names differ per game; we attempt several known patterns.
  local candidates = {
    "/Script/Engine.GameSession:CanPlayerJoin",
    "/Script/Engine.GameModeBase:CanPlayerJoin",
    "/Script/Engine.GameModeBase:ReadyToStartMatch", -- sometimes gates late joins
    "/Script/Engine.GameSession:ApproveLogin",      -- common in UE for session approval
  }

  local anyHooked = false
  for _, sig in ipairs(candidates) do
    local ok, err = pcall(function()
      RegisterHook(sig, make_gate_wrapper(mod, sig))
    end)
    if ok then
      anyHooked = true
      mod.Log("Hooked: " .. sig)
    else
      mod.Debug("Join hook unavailable: " .. sig .. " (" .. tostring(err) .. ")")
    end
  end

  -- Some games implement gates in Blueprints (LobbyController, LobbyGameMode)
  local bpCandidates = {
    "/Game/**/LobbyGameMode_C:CanPlayerJoin",
    "/Game/**/LobbyController_C:ValidateJoin",
  }
  for _, sig in ipairs(bpCandidates) do
    local ok, err = pcall(function()
      RegisterHook(sig, make_gate_wrapper(mod, sig))
    end)
    if ok then
      anyHooked = true
      mod.Log("Hooked (BP): " .. sig)
    else
      mod.Debug("BP join hook unavailable: " .. sig .. " (" .. tostring(err) .. ")")
    end
  end

  if not anyHooked then
    mod.Debug("No additional join gate hooks needed - using MaxPlayers override")
  end
end

return M


