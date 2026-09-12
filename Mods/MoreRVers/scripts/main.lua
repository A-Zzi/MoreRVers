-- MoreRVers - main.lua
-- Host-side UE4SS Lua mod to raise the multiplayer cap beyond 4 for RV There Yet?
--
-- Design notes:
--  * A game patch can move or rename whatever set the cap last time, so the cap is
--    applied from several independent triggers instead of one, and re-applied every
--    time a player logs in.
--  * Every UE4SS global is looked up and type-checked before it is called, so a
--    UE4SS/engine change degrades to "fewer triggers" rather than "mod dead".
--  * Everything that touches engine objects goes through pcall.

local MOD_NAME    = "MoreRVers"
local MOD_VERSION = "1.1.0"

local MoreRVers = {
  Name    = MOD_NAME,
  Version = MOD_VERSION,
  State   = {
    applied      = 0,   -- number of successful property writes
    lastSweep    = nil, -- reason string of the last sweep
    triggers     = {},  -- trigger name -> true when installed
    seenProps    = {},  -- "Class.Prop" -> last value we observed
  },
}

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

-- Works with either path separator; Lua io/dofile accept "/" on Windows too.
local ScriptDir = debug.getinfo(1, "S").source:match("^@?(.*)[/\\][^/\\]*$")
if ScriptDir then ScriptDir = ScriptDir .. "/" end
local ModDir = ScriptDir and (ScriptDir .. "../") or nil

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

-- Reads "Key = Value" lines, ignoring ';' and '#' comments. Returns a table
-- keyed by lowercased key name.
local function parse_ini(filepath)
  local file = io.open(filepath, "r")
  if not file then return nil end

  local values = {}
  for line in file:lines() do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^[;#]") and not line:match("^%[") then
      local key, value = line:match("^([^=]-)%s*=%s*(.-)$")
      if key and key ~= "" then
        values[key:lower()] = value
      end
    end
  end

  file:close()
  return values
end

local ini = {}
if ModDir then
  local ok, parsed = pcall(parse_ini, ModDir .. "config.ini")
  if ok and parsed then ini = parsed end
end

local function ini_number(key, default)
  local n = tonumber(ini[key])
  if n then return n end
  return default
end

local function ini_bool(key, default)
  local v = ini[key]
  if v == nil then return default end
  v = v:lower()
  return v == "1" or v == "true" or v == "yes" or v == "on"
end

MoreRVers.Config = {
  TargetMaxPlayers = ini_number("maxplayers", 8),
  HardUpperLimit   = ini_number("hardupperlimit", 24),
  -- Upper bound on values we are willing to overwrite. Guards against clobbering
  -- an unrelated int property that happens to share a candidate name.
  SanityCeiling    = ini_number("sanityceiling", 64),
  ReapplySeconds   = ini_number("reapplyseconds", 10),
  LogLevel         = (ini["loglevel"] or "INFO"):upper(),
  TimestampFormat  = ini["timestampformat"] or "%H:%M:%S",
  WatchActorSpawns = ini_bool("watchactorspawns", true),
}

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

local LEVELS = { DEBUG = 10, INFO = 20, WARN = 30, ERROR = 40 }
local CURRENT_LEVEL = LEVELS[MoreRVers.Config.LogLevel] or LEVELS.INFO

local function ts()
  local ok, s = pcall(os.date, MoreRVers.Config.TimestampFormat)
  return (ok and s) or "--:--:--"
end

local function println(level, msg)
  print(string.format("[%s] [%s] [%s] %s\n", ts(), MOD_NAME, level, tostring(msg)))
end

function MoreRVers.Debug(msg) if LEVELS.DEBUG >= CURRENT_LEVEL then println("DEBUG", msg) end end
function MoreRVers.Log(msg)   if LEVELS.INFO  >= CURRENT_LEVEL then println("INFO",  msg) end end
function MoreRVers.Warn(msg)  if LEVELS.WARN  >= CURRENT_LEVEL then println("WARN",  msg) end end
function MoreRVers.Error(msg) if LEVELS.ERROR >= CURRENT_LEVEL then println("ERROR", msg) end end

--------------------------------------------------------------------------------
-- Target cap
--------------------------------------------------------------------------------

local function sanitize_target_cap(v)
  local num = math.floor(tonumber(v) or 8)
  local hard = math.floor(tonumber(MoreRVers.Config.HardUpperLimit) or 24)
  if num < 1 then num = 1 end
  if num > hard then num = hard end
  return num
end

MoreRVers.TargetMaxPlayers = sanitize_target_cap(MoreRVers.Config.TargetMaxPlayers)

--------------------------------------------------------------------------------
-- UE4SS API access (never assume a global exists)
--------------------------------------------------------------------------------

local function global_fn(name)
  local fn = rawget(_G, name)
  if type(fn) == "function" then return fn end
  return nil
end

local function is_valid(obj)
  if obj == nil then return false end
  local ok, valid = pcall(function() return obj:IsValid() end)
  if ok then return valid == true end
  -- No IsValid(): assume usable. Every access below is pcall'd anyway.
  return true
end

local function object_label(obj, fallback)
  local ok, name = pcall(function() return obj:GetClass():GetFName():ToString() end)
  if ok and type(name) == "string" and name ~= "" then return name end
  ok, name = pcall(function() return obj:GetFullName() end)
  if ok and type(name) == "string" and name ~= "" then return name end
  return fallback or "<object>"
end

local function find_all(className)
  local out = {}
  local FindAllOf = global_fn("FindAllOf")
  if FindAllOf then
    local ok, res = pcall(FindAllOf, className)
    if ok and type(res) == "table" then
      for _, o in ipairs(res) do
        if is_valid(o) then out[#out + 1] = o end
      end
      if #out > 0 then return out end
    end
  end
  local FindFirstOf = global_fn("FindFirstOf")
  if FindFirstOf then
    local ok, res = pcall(FindFirstOf, className)
    if ok and is_valid(res) then out[#out + 1] = res end
  end
  return out
end

--------------------------------------------------------------------------------
-- The actual patch
--------------------------------------------------------------------------------

-- Property names that have gated player count in UE games and in this one.
-- Anything here is only written when the current value looks like a real cap.
local CANDIDATE_PROPS = {
  "MaxPlayers",
  "MaxPlayerCount",
  "MaxNumPlayers",
  "MaxPublicConnections",
  "NumPublicConnections",
  "MaxPartySize",
  "MaxLobbySize",
}

-- Classes swept for those properties. Short names, so subclasses are matched too.
local SWEEP_CLASSES = {
  "GameSession",
  "GameModeBase",
  "GameStateBase",
}

-- Engine CDOs worth patching directly, so objects spawned later start correct.
local CDO_PATHS = {
  "/Script/Engine.Default__GameSession",
}

local function apply_to(obj, label, reason)
  if not is_valid(obj) then return 0 end

  local target  = MoreRVers.TargetMaxPlayers
  local ceiling = MoreRVers.Config.SanityCeiling
  local changed = 0

  for _, prop in ipairs(CANDIDATE_PROPS) do
    local ok, cur = pcall(function() return obj[prop] end)
    if ok and type(cur) == "number" then
      MoreRVers.State.seenProps[label .. "." .. prop] = cur
      -- Only touch values that look like a player cap. Skips 0/sentinel values
      -- and refuses to clobber something already far larger than any lobby.
      if cur ~= target and cur > 0 and cur <= ceiling then
        local okSet = pcall(function() obj[prop] = target end)
        if okSet then
          -- Confirm the write stuck; a replicated/const property can silently ignore it.
          local okRead, now = pcall(function() return obj[prop] end)
          if okRead and now == target then
            changed = changed + 1
            MoreRVers.State.applied = MoreRVers.State.applied + 1
            MoreRVers.Log(string.format("%s.%s: %s -> %d (%s)", label, prop, tostring(cur), target, reason))
          else
            MoreRVers.Debug(string.format("%s.%s write did not stick (still %s)", label, prop, tostring(now)))
          end
        else
          MoreRVers.Debug(string.format("%s.%s is not writable", label, prop))
        end
      end
    end
  end

  return changed
end

local function apply_to_cdo_of(obj, label, reason)
  local cdo = nil
  local ok = pcall(function() cdo = obj:GetClass():GetDefaultObject() end)
  if ok and is_valid(cdo) then
    return apply_to(cdo, label .. " [CDO]", reason)
  end
  return 0
end

-- Sweep every live session/mode/state object plus the engine CDOs.
local function sweep(reason)
  local changed = 0
  MoreRVers.State.lastSweep = reason

  local StaticFindObject = global_fn("StaticFindObject")
  if StaticFindObject then
    for _, path in ipairs(CDO_PATHS) do
      local ok, cdo = pcall(StaticFindObject, path)
      if ok and is_valid(cdo) then
        changed = changed + apply_to(cdo, path, reason)
      end
    end
  end

  for _, className in ipairs(SWEEP_CLASSES) do
    for _, obj in ipairs(find_all(className)) do
      local label = object_label(obj, className)
      changed = changed + apply_to(obj, label, reason)
      changed = changed + apply_to_cdo_of(obj, label, reason)
    end
  end

  if changed == 0 then
    MoreRVers.Debug(string.format("sweep (%s): nothing to change", reason))
  end
  return changed
end

MoreRVers.Apply = sweep

-- Dumps every cap-like property we have seen. This is what to paste into a bug
-- report when the cap stays at 4.
function MoreRVers.Diagnostics()
  MoreRVers.Log(string.format("%s v%s - target cap %d, writes applied %d, last sweep %s",
    MOD_NAME, MOD_VERSION, MoreRVers.TargetMaxPlayers, MoreRVers.State.applied,
    tostring(MoreRVers.State.lastSweep)))

  local triggers = {}
  for name, _ in pairs(MoreRVers.State.triggers) do triggers[#triggers + 1] = name end
  table.sort(triggers)
  MoreRVers.Log("Active triggers: " .. (#triggers > 0 and table.concat(triggers, ", ") or "NONE"))

  sweep("diagnostics")

  local keys = {}
  for k, _ in pairs(MoreRVers.State.seenProps) do keys[#keys + 1] = k end
  table.sort(keys)
  if #keys == 0 then
    MoreRVers.Warn("No cap-like properties found. Either no session exists yet (host a game first), "
      .. "or the game moved the cap out of GameSession/GameMode/GameState.")
  else
    for _, k in ipairs(keys) do
      MoreRVers.Log(string.format("  %s = %s", k, tostring(MoreRVers.State.seenProps[k])))
    end
  end
end

--------------------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------------------

local function mark(name)
  MoreRVers.State.triggers[name] = true
  MoreRVers.Debug("trigger installed: " .. name)
end

local function install_triggers()
  -- 1. Every new GameSession (and subclasses) as it is constructed.
  local NotifyOnNewObject = global_fn("NotifyOnNewObject")
  if NotifyOnNewObject then
    local ok = pcall(NotifyOnNewObject, "/Script/Engine.GameSession", function(obj)
      apply_to(obj, object_label(obj, "GameSession"), "new GameSession")
      apply_to_cdo_of(obj, object_label(obj, "GameSession"), "new GameSession")
    end)
    if ok then mark("NotifyOnNewObject(GameSession)") end
  end

  -- 2. After every map load, including travel into the lobby/session level.
  local RegisterLoadMapPostHook = global_fn("RegisterLoadMapPostHook")
  if RegisterLoadMapPostHook then
    local ok = pcall(RegisterLoadMapPostHook, function()
      sweep("map loaded")
    end)
    if ok then mark("RegisterLoadMapPostHook") end
  end

  -- 3. On every player login. This is the one that matters when the game resets
  --    the cap after we set it: PostLogin runs on the 5th join attempt too.
  local RegisterHook = global_fn("RegisterHook")
  if RegisterHook then
    local ufunctions = {
      "/Script/Engine.GameModeBase:K2_PostLogin",
      "/Script/Engine.GameModeBase:K2_OnLogout",
      "/Script/Engine.GameSession:ReceiveBeginPlay",
      "/Script/Engine.GameModeBase:ReceiveBeginPlay",
    }
    for _, sig in ipairs(ufunctions) do
      local ok, err = pcall(RegisterHook, sig, function()
        sweep(sig)
      end)
      if ok then
        mark(sig)
      else
        MoreRVers.Debug(string.format("hook unavailable: %s (%s)", sig, tostring(err)))
      end
    end
  end

  -- 4. BeginPlay of any actor that is a GameSession. Catches sessions created
  --    without going through the hooks above. Cheap: one IsA per actor spawn.
  local RegisterBeginPlayPostHook = global_fn("RegisterBeginPlayPostHook")
  if RegisterBeginPlayPostHook and MoreRVers.Config.WatchActorSpawns then
    local StaticFindObject = global_fn("StaticFindObject")
    local GSClass = nil
    if StaticFindObject then
      local ok, cls = pcall(StaticFindObject, "/Script/Engine.GameSession")
      if ok and is_valid(cls) then GSClass = cls end
    end
    if GSClass then
      -- Confirm IsA works before installing, so we never pay for a per-spawn error.
      local probe = pcall(function() return GSClass:GetDefaultObject():IsA(GSClass) end)
      if probe then
        local ok = pcall(RegisterBeginPlayPostHook, function(ContextParam)
          local okCtx, ctx = pcall(function() return ContextParam:get() end)
          if not okCtx or not is_valid(ctx) then return end
          local okIs, isSession = pcall(function() return ctx:IsA(GSClass) end)
          if okIs and isSession then
            local label = object_label(ctx, "GameSession")
            apply_to(ctx, label, "actor BeginPlay")
            apply_to_cdo_of(ctx, label, "actor BeginPlay")
          end
        end)
        if ok then mark("RegisterBeginPlayPostHook") end
      else
        MoreRVers.Debug("IsA() unavailable; skipping per-actor BeginPlay watch")
      end
    end
  end

  -- 5. Periodic re-apply, for the case where the game rewrites the cap on a timer
  --    or from a path none of the hooks above cover.
  local LoopAsync = global_fn("LoopAsync")
  local everyMs = math.floor((MoreRVers.Config.ReapplySeconds or 10) * 1000)
  if LoopAsync and everyMs > 0 then
    local ok = pcall(LoopAsync, everyMs, function()
      pcall(sweep, "periodic")
      return false -- keep looping
    end)
    if ok then mark(string.format("LoopAsync(%dms)", everyMs)) end
  end

  -- 6. Manual re-apply / diagnostics, for when the console is available.
  local RegisterConsoleCommandHandler = global_fn("RegisterConsoleCommandHandler")
  if RegisterConsoleCommandHandler then
    local ok = pcall(RegisterConsoleCommandHandler, "morervers", function()
      MoreRVers.Diagnostics()
      return true -- command handled
    end)
    if ok then mark("console command 'morervers'") end
  end

  -- 7. Same thing on a keybind, since the UE4SS console is off by default.
  local RegisterKeyBind = global_fn("RegisterKeyBind")
  if RegisterKeyBind and rawget(_G, "Key") and Key.F10 then
    local ok = pcall(RegisterKeyBind, Key.F10, function()
      local ExecuteInGameThread = global_fn("ExecuteInGameThread")
      if ExecuteInGameThread then
        ExecuteInGameThread(function() MoreRVers.Diagnostics() end)
      else
        MoreRVers.Diagnostics()
      end
    end)
    if ok then mark("keybind F10 (diagnostics)") end
  end
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

local function engine_info()
  local ok, s = pcall(function()
    local uv = rawget(_G, "UnrealVersion")
    if not uv then return nil end
    if uv.GetMajorVersion and uv.GetMinorVersion then
      return string.format("UE %s.%s", tostring(uv:GetMajorVersion()), tostring(uv:GetMinorVersion()))
    end
    return nil
  end)
  return (ok and s) or "unknown"
end

MoreRVers.Log(string.format("%s v%s loading. Target cap=%d (hard max %d). Engine: %s",
  MOD_NAME, MOD_VERSION, MoreRVers.TargetMaxPlayers,
  MoreRVers.Config.HardUpperLimit, engine_info()))

if not ModDir then
  MoreRVers.Warn("Could not resolve mod directory; config.ini was not read, using defaults.")
elseif next(ini) == nil then
  MoreRVers.Warn("config.ini not found or empty at " .. ModDir .. "config.ini; using defaults.")
end

install_triggers()

if next(MoreRVers.State.triggers) == nil then
  MoreRVers.Error("No triggers could be installed. This UE4SS build does not expose the "
    .. "expected Lua API - update UE4SS to the latest experimental build.")
else
  -- One sweep now, in case a session already exists (hot reload, late load).
  local ExecuteInGameThread = global_fn("ExecuteInGameThread")
  if ExecuteInGameThread then
    ExecuteInGameThread(function() pcall(sweep, "startup") end)
  else
    pcall(sweep, "startup")
  end
end

MoreRVers.Log("Press F10 in game (or run 'morervers' in the UE4SS console) for diagnostics.")

return MoreRVers
