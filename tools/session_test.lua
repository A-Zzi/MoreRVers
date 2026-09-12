local patched = "Mods/MoreRVers/scripts/main.lua"
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

-- Model the UE4SS boundary, not the mod's implementation. Property access must
-- run on the game thread; callback context is wrapped, whereas searches return
-- UObjects. Only documented class methods are exposed.
local function fixture(config)
    local f = {thread = false, logs = {}, queue = {}, sessions = {}, hooks = {}}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.UE = nil
    env.print = function(message) f.logs[#f.logs + 1] = message end
    local function game_thread() assert(f.thread, "UObject access outside game thread") end
    function f.session(name, initial, cdo)
        local values = {MaxPlayers = initial, MaxPartySize = 4, MaxSpectators = 2}
        local object = {}
        local methods = {
            IsValid = function() game_thread(); return true end,
            GetFullName = function() game_thread(); return name end,
            GetClass = function() game_thread(); return {GetCDO = function() return cdo or object end} end,
        }
        setmetatable(object, {
            __index = function(_, key)
                if methods[key] then return methods[key] end
                game_thread()
                if values[key] == nil then error("unknown UObject member: " .. key) end
                return values[key]
            end,
            __newindex = function(_, key, value)
                game_thread()
                if f.reject_write and object == f.reject_write then error("reflected property is read only") end
                if f.ignore_write ~= object then values[key] = value end
            end,
        })
        return object
    end
    function f.call(callback, ...)
        f.thread = true
        local result = table.pack(callback(...))
        f.thread = false
        return table.unpack(result, 1, result.n)
    end
    function f.flush()
        local queued = f.queue
        f.queue = {}
        for _, callback in ipairs(queued) do f.call(callback) end
    end
    function f.mode(session, class)
        return {get = function()
            game_thread()
            return {
                GameSession = session,
                IsValid = function() return true end,
                IsA = function(_, requested) return requested == (class or "/Script/Engine.GameModeBase") end,
            }
        end}
    end
    f.cdo = f.session("GameSession /Script/Engine.Default__GameSession", 4)
    env.StaticFindObject = function(path)
        game_thread()
        assert(path == "/Script/Engine.Default__GameSession", "unexpected object search")
        return f.cdo
    end
    env.FindAllOf = function(class)
        game_thread(); assert(class == "GameSession", "unexpected class search")
        return #f.sessions > 0 and f.sessions or nil
    end
    env.ExecuteInGameThread = function(callback) f.queue[#f.queue + 1] = callback end
    env.RegisterInitGameStatePostHook = function(cb) f.hooks.init = cb end
    env.RegisterLoadMapPostHook = function(cb) f.hooks.map = cb end
    env.RegisterCustomEvent = function(name, cb) assert(name == "K2_PostLogin"); f.hooks.login = cb end
    env.RegisterKeyBind = function(key, cb) assert(key == 121); f.hooks.key = cb end
    env.Key = {F10 = 121}
    if config then
        env.io = {open = function(path)
            assert(path == "C:/Games/RV There Yet/ue4ss/Mods/MoreRVers/scripts/../config.ini")
            return {lines = function() return config:gmatch("[^\r\n]+") end, close = function() end}
        end}
    end
    function f.load(path)
        if config then
            local input = assert(io.open(path)); local code = input:read("*a"); input:close()
            return assert(load(code, "@C:\\Games\\RV There Yet\\ue4ss\\Mods\\MoreRVers\\scripts\\main.lua", "t", env))()
        end
        return assert(loadfile(path, "t", env))()
    end
    return f, env
end

local f = fixture()
f.load(patched)
check(#f.queue == 1, "startup should queue game-thread work")
f.flush()
f.call(function() check(f.cdo.MaxPlayers == 8, "startup must patch default even in main menu") end)
local session = f.session("GameSession /Game/Ride/Maps/JungleLevel", 4, f.cdo)
f.sessions = {session}
f.call(f.hooks.init, f.mode(session))
f.call(function() check(session.MaxPlayers == 8, "restore after InitOptions reset") end)
f.call(function() session.MaxPlayers = 4 end)
check(f.call(f.hooks.map) == nil, "map hook must preserve LoadMap return value")
f.call(function() check(session.MaxPlayers == 8, "restore after map BeginPlay reset") end)
f.call(function() session.MaxPlayers = 4 end)
f.call(f.hooks.login, f.mode(session))
f.call(function()
    check(session.MaxPlayers == 8, "restore after accepted Blueprint login")
    check(4 < session.MaxPlayers, "engine capacity comparison should allow fifth player")
    check(not (8 < session.MaxPlayers), "configured capacity must still reject ninth player")
    check(session.MaxPartySize == 4 and session.MaxSpectators == 2, "do not modify other limits")
end)

-- Travel creates a new instance and may use a subclass with its own default.
local subclass_cdo = f.session("CustomGameSession default", 4)
local next_session = f.session("CustomGameSession /Game/Ride/Maps/OtherMap", 4, subclass_cdo)
f.sessions = {next_session}
f.call(f.hooks.init, f.mode(next_session))
f.call(function()
    check(next_session.MaxPlayers == 8 and subclass_cdo.MaxPlayers == 8,
        "seamless travel must patch new instance and exact subclass default")
    next_session.MaxPlayers = 4
end)
f.call(f.hooks.login, f.mode(next_session, "/Script/UMG.UserWidget"))
f.call(function() check(next_session.MaxPlayers == 4, "same-name non-game-mode event must be ignored") end)

-- Diagnostics must queue, then read the reset value without concealing it.
f.hooks.key()
check(#f.queue == 1, "F10 must queue on game thread")
f.flush()
f.call(function() check(next_session.MaxPlayers == 4, "diagnostics must not repair observed state") end)
check(table.concat(f.logs):find("live MaxPlayers=4", 1, true), "diagnostics must expose effective cap")
f.reject_write = next_session
f.call(f.hooks.init, f.mode(next_session))
check(table.concat(f.logs):find("reflected property is read only", 1, true), "write error cause must be visible")
f.reject_write, f.ignore_write = nil, next_session
f.call(f.hooks.init, f.mode(next_session))
check(table.concat(f.logs):find("write failed: expected 8, read 4", 1, true), "silent write failure must be detected")

local windows = fixture("\239\187\191MaxPlayers = 12 ; friends\r\n")
windows.load(patched); windows.flush()
windows.call(function() check(windows.cdo.MaxPlayers == 12, "Windows path, BOM and configured cap") end)
local bad = fixture("MaxPlayers = 8.5\n")
local ok, err = pcall(bad.load, patched)
check(not ok and tostring(err):find("whole number", 1, true), "invalid config must fail clearly")
local missing, missing_env = fixture()
missing_env.RegisterInitGameStatePostHook = false
ok, err = pcall(missing.load, patched)
check(not ok and tostring(err):find("Required UE4SS API is missing", 1, true), "missing API must not silently degrade")
print("PASS: " .. checks .. " assertions; session lifecycle verified in UE4SS stubs")
