-- Offline smoke test for MoreRVers.
-- Stubs the UE4SS Lua globals so main.lua can be exercised without the game.
-- Run from the repo root:  lua5.4 tools/ue4ss_stub_test.lua

-- Minimal stub of the UE4SS Lua environment, to exercise main.lua off-game.
local log = {}
local realprint = print
print = function(s) log[#log+1] = s; io.write(s) end

-- fake UObject
local function mkobj(className, props, writable)
  local t = { __class = className, __props = props, __writable = writable ~= false }
  return setmetatable(t, {
    __index = function(self, k)
      if k == "IsValid" then return function() return true end end
      if k == "GetClass" then return function() return ClassOf(className) end end
      if k == "GetFullName" then return function() return className .. " /Game/Foo" end end
      if k == "IsA" then return function(_, cls) return cls and cls.__isGameSessionClass and className:find("GameSession") ~= nil end end
      return rawget(self, "__props")[k]
    end,
    __newindex = function(self, k, v)
      if rawget(self, "__writable") then rawget(self, "__props")[k] = v end
    end,
  })
end

local CDOs = {}
function ClassOf(className)
  local cls
  cls = setmetatable({ __isGameSessionClass = (className:find("GameSession") ~= nil) }, {
    __index = function(_, k)
      if k == "IsValid" then return function() return true end end
      if k == "GetFName" then return function() return { ToString = function() return className end } end end
      if k == "GetDefaultObject" then return function()
        CDOs[className] = CDOs[className] or mkobj("Default__" .. className, { MaxPlayers = 4 })
        return CDOs[className]
      end end
      return nil
    end })
  return cls
end

local sessionInst = mkobj("BP_RideGameSession_C", { MaxPlayers = 4, MaxSpectators = 2 })
local gameMode    = mkobj("BP_RideGameMode_C",    { MaxPlayerCount = 4, SomeUnrelated = 999 })
local gameState   = mkobj("BP_RideGameState_C",   { MaxNumPlayers = 4 })
local readonly    = mkobj("BP_Locked_C",          { MaxPlayers = 4 }, false)

local registry = {
  GameSession   = { sessionInst },
  GameModeBase  = { gameMode },
  GameStateBase = { gameState },
}

FindAllOf   = function(c) return registry[c] end
FindFirstOf = function(c) return registry[c] and registry[c][1] end
StaticFindObject = function(path)
  if path == "/Script/Engine.Default__GameSession" then
    CDOs.EngineGS = CDOs.EngineGS or mkobj("Default__GameSession", { MaxPlayers = 4 })
    return CDOs.EngineGS
  end
  if path == "/Script/Engine.GameSession" then return ClassOf("GameSession") end
  return nil
end
ExecuteInGameThread = function(f) f() end

local hooks, loops = {}, {}
RegisterHook = function(sig, cb)
  if not sig:find("GameModeBase") and not sig:find("GameSession") then error("no such function " .. sig) end
  hooks[sig] = cb
end
NotifyOnNewObject = function(cls, cb) hooks["notify:" .. cls] = cb end
RegisterLoadMapPostHook = function(cb) hooks["loadmap"] = cb end
RegisterBeginPlayPostHook = function(cb) hooks["beginplay"] = cb end
LoopAsync = function(ms, cb) loops[#loops+1] = { ms = ms, cb = cb } end
RegisterConsoleCommandHandler = function(name, cb) hooks["cmd:" .. name] = cb end
Key = { F10 = 121 }
RegisterKeyBind = function(k, cb) hooks["key:" .. tostring(k)] = cb end
UnrealVersion = { GetMajorVersion = function() return 5 end, GetMinorVersion = function() return 5 end }

local Mod = dofile("Mods/MoreRVers/scripts/main.lua")

realprint("\n--- assertions ---")
local function check(name, cond, extra)
  realprint((cond and "PASS  " or "FAIL  ") .. name .. (extra and ("  " .. tostring(extra)) or ""))
  if not cond then os.exit(1) end
end

check("target cap parsed from config.ini", Mod.TargetMaxPlayers == 8, Mod.TargetMaxPlayers)
check("GameSession instance bumped", sessionInst.__props.MaxPlayers == 8, sessionInst.__props.MaxPlayers)
check("GameMode MaxPlayerCount bumped", gameMode.__props.MaxPlayerCount == 8, gameMode.__props.MaxPlayerCount)
check("GameState MaxNumPlayers bumped", gameState.__props.MaxNumPlayers == 8, gameState.__props.MaxNumPlayers)
check("unrelated 999 property untouched (above sanity ceiling)", gameMode.__props.SomeUnrelated == 999)
check("MaxSpectators untouched (not a candidate)", sessionInst.__props.MaxSpectators == 2)
check("engine GameSession CDO bumped", CDOs.EngineGS.__props.MaxPlayers == 8)
check("PostLogin hook installed", hooks["/Script/Engine.GameModeBase:K2_PostLogin"] ~= nil)
check("periodic loop installed", #loops == 1 and loops[1].ms == 10000)
check("console command installed", hooks["cmd:morervers"] ~= nil)
check("F10 keybind installed", hooks["key:121"] ~= nil)

-- Game resets the cap behind our back; PostLogin must restore it.
sessionInst.__props.MaxPlayers = 4
hooks["/Script/Engine.GameModeBase:K2_PostLogin"]()
check("cap restored after game reset it", sessionInst.__props.MaxPlayers == 8, sessionInst.__props.MaxPlayers)

-- Read-only property must not crash the sweep.
registry.GameSession[#registry.GameSession+1] = readonly
local okSweep = pcall(Mod.Apply, "test readonly")
check("read-only property does not break sweep", okSweep)

-- Diagnostics must not crash.
check("diagnostics runs", pcall(Mod.Diagnostics))
realprint("\nALL PASS")
