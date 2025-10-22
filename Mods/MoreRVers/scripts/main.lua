-- MoreRVers - main.lua
-- Host-side UE4SS Lua mod to raise multiplayer cap beyond 4 for RV There Yet?

-- Set up package path for this mod's directory structure
local ModPath = debug.getinfo(1, "S").source:match("@?(.*/)")
if not ModPath then
  -- Try Windows path separator
  ModPath = debug.getinfo(1, "S").source:match("@?(.*)[\\/]")
  if ModPath then ModPath = ModPath .. "\\" end
end

local MoreRVers = {
  Name = "MoreRVers",
  Version = "1.0.0",
  Metrics = {
    forcedAllows = 0,
  }
}

-- ModPath detection (silent unless there's an issue)
if not ModPath then
  print("[MoreRVers] WARNING: ModPath not detected - hooks may fail to load!")
end

-- Simple INI file parser (reads MaxPlayers value)
local function parse_ini(filepath)
  local file = io.open(filepath, "r")
  if not file then return nil end
  
  local maxPlayers = nil
  for line in file:lines() do
    -- Skip comments and empty lines
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^;") then
      -- Parse MaxPlayers = value
      local key, value = line:match("^([^=]+)%s*=%s*(.+)$")
      if key and value then
        key = key:match("^%s*(.-)%s*$")
        value = value:match("^%s*(.-)%s*$")
        
        if key == "MaxPlayers" and tonumber(value) then
          maxPlayers = tonumber(value)
          break
        end
      end
    end
  end
  
  file:close()
  return maxPlayers
end

-- Load config from INI file
local configLoaded = nil
if ModPath then
  local iniPath = ModPath .. "../config.ini"
  local ok, maxPlayers = pcall(function() return parse_ini(iniPath) end)
  if ok and maxPlayers then
    configLoaded = {
      TargetMaxPlayers = maxPlayers,
      HardUpperLimit = 24,
      EnableClientUiTweaks = false,
      LogLevel = "INFO",
      TimestampFormat = "%H:%M:%S"
    }
  end
end

MoreRVers.Config = configLoaded or {
  TargetMaxPlayers = 8,
  HardUpperLimit = 24,
  EnableClientUiTweaks = false,
  LogLevel = "INFO",
  TimestampFormat = "%H:%M:%S"
}

-- Logging utilities with levels and timestamps
local LEVELS = { DEBUG = 10, INFO = 20, WARN = 30, ERROR = 40 }
local CURRENT_LEVEL = LEVELS[MoreRVers.Config.LogLevel or "INFO"] or LEVELS.INFO

local function ts()
  local fmt = MoreRVers.Config.TimestampFormat or "%H:%M:%S"
  local ok, s = pcall(function() return os.date(fmt) end)
  return ok and s or "--:--:--"
end

local function println(level, msg)
  local lvl = level or "INFO"
  print(string.format("[%s] [%s] [%s] %s", ts(), MoreRVers.Name, lvl, tostring(msg)))
end

function MoreRVers.Debug(msg)
  if LEVELS.DEBUG >= CURRENT_LEVEL then println("DEBUG", msg) end
end

function MoreRVers.Log(msg)
  if LEVELS.INFO >= CURRENT_LEVEL then println("INFO", msg) end
end

function MoreRVers.Warn(msg)
  if LEVELS.WARN >= CURRENT_LEVEL then println("WARN", msg) end
end

function MoreRVers.Error(msg)
  if LEVELS.ERROR >= CURRENT_LEVEL then println("ERROR", msg) end
end

-- Clamp and sanitize target cap
local function sanitize_target_cap(v)
  local num = tonumber(v) or 8
  if num < 1 then num = 1 end  -- Allow as low as 1 for testing
  local hard = tonumber(MoreRVers.Config.HardUpperLimit or 24) or 24
  if num > hard then num = hard end
  return num
end

MoreRVers.TargetMaxPlayers = sanitize_target_cap(MoreRVers.Config.TargetMaxPlayers)

-- Engine/game info (best-effort)
local function get_engine_info()
  local info = "UE5 (detected)"
  local ok, ver = pcall(function()
    if UE ~= nil and UE.UObject and UE.UObject.GetEngineVersion then
      return UE.UObject.GetEngineVersion()
    end
    return nil
  end)
  if ok and ver then
    info = tostring(ver)
  end
  return info
end

-- Require hook modules with fallbacks that work across common UE4SS layouts
local function require_hook(name)
  -- Try loading relative to current script location using dofile
  if ModPath then
    local hookPath = ModPath .. "hooks\\" .. name .. ".lua"
    local ok, result = pcall(function() return dofile(hookPath) end)
    if ok and result then
      return result
    end
  end
  
  -- Fallback to require with various paths
  return try_require({
    "hooks." .. name,
    "scripts.hooks." .. name,
    "Mods.MoreRVers.scripts.hooks." .. name,
  })
end

-- Initialization log header
MoreRVers.Log(("MoreRVers v%s loading. Target cap=%d (hard max %d)")
  :format(MoreRVers.Version, MoreRVers.TargetMaxPlayers, MoreRVers.Config.HardUpperLimit))
MoreRVers.Log("Engine: " .. get_engine_info())

-- Load hooks
local game_session = require_hook("game_session")
local join_gate = require_hook("join_gate")
local ui_helpers = nil
if MoreRVers.Config.EnableClientUiTweaks then
  ui_helpers = require_hook("ui_helpers")
end

-- Defensive guards
if not game_session then
  MoreRVers.Warn("game_session hook module not found; MaxPlayers may remain vanilla.")
else
  -- Defer hook installation until UE API is ready
  if UE then
    -- Apply MaxPlayers bump as early as possible
    local ok, err = pcall(function()
      game_session.install_hooks(MoreRVers)
      if game_session.get_current_player_count then
        MoreRVers.get_current_player_count = game_session.get_current_player_count
      end
    end)
    if not ok then
      MoreRVers.Error("Failed to install game_session hooks: " .. tostring(err))
    end
  else
    -- UE API not ready - patch GameSession directly when created
    NotifyOnNewObject("/Script/Engine.GameSession", function(obj)
      -- Read original value
      local original = nil
      pcall(function() original = obj.MaxPlayers end)
      
      -- Set new value directly
      local okSet = pcall(function() 
        obj.MaxPlayers = MoreRVers.TargetMaxPlayers 
      end)
      
      if okSet then
        MoreRVers.Log(string.format("Applied MaxPlayers override: %s → %d", 
          tostring(original or "?"), MoreRVers.TargetMaxPlayers))
        
        -- Try to set on CDO too
        pcall(function()
          local cdo = obj:GetClass():GetDefaultObject()
          if cdo then
            cdo.MaxPlayers = MoreRVers.TargetMaxPlayers
          end
        end)
      else
        MoreRVers.Warn("Failed to set MaxPlayers on GameSession")
      end
    end)
  end
end

if join_gate then
  local ok, err = pcall(function()
    join_gate.install_hooks(MoreRVers)
  end)
  if not ok then
    MoreRVers.Error("Failed to install join_gate hooks: " .. tostring(err))
  end
end

if ui_helpers then
  local ok, err = pcall(function()
    ui_helpers.install_hooks(MoreRVers)
  end)
  if not ok then
    MoreRVers.Warn("UI helpers failed to load (non-fatal): " .. tostring(err))
  end
else
  if MoreRVers.Config.EnableClientUiTweaks then
    MoreRVers.Warn("UI helpers module not found; continuing without client tweaks.")
  end
end

-- Export for other scripts
return MoreRVers


