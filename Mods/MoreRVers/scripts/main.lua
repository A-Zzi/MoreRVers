-- MoreRVers: host-side session capacity fix.
-- Uses the UE4SS Lua API; no map-specific Blueprint paths are required.
local VERSION = "1.0.1-fix1"
local SESSION_CDO = "/Script/Engine.Default__GameSession"

local function log(message)
    print("[MoreRVers] " .. message .. "\n")
end

-- Windows accepts forward slashes too. Keep loading independent of package.path.
local source = debug.getinfo(1, "S").source:gsub("\\", "/")
local script_dir = assert(source:match("^@(.*/)"), "[MoreRVers] Cannot locate main.lua")
local config_path = script_dir .. "../config.ini"
local file, open_error = io.open(config_path, "r")
assert(file, "[MoreRVers] Cannot open " .. config_path .. ": " .. tostring(open_error))
local cap
for raw_line in file:lines() do
    local line = raw_line:gsub("^\239\187\191", ""):gsub("[;#].*$", "")
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and key:lower() == "maxplayers" then
        cap = tonumber(value)
        break
    end
end
file:close()
assert(cap and cap >= 1 and cap <= 24 and cap % 1 == 0,
    "[MoreRVers] config.ini: MaxPlayers must be a whole number from 1 to 24")

-- These APIs are present in the supplied UE4SS build. A missing API is an error,
-- not a reason to report success with part of the mod disabled.
for _, name in ipairs({
    "StaticFindObject", "FindAllOf", "ExecuteInGameThread",
    "RegisterInitGameStatePostHook", "RegisterLoadMapPostHook",
    "RegisterCustomEvent", "RegisterKeyBind",
}) do
    assert(type(_G[name]) == "function",
        "[MoreRVers] Required UE4SS API is missing: " .. name .. ". Check UE4SS.log")
end
assert(Key and Key.F10, "[MoreRVers] UE4SS key definitions are missing")

local function valid(object)
    return object ~= nil and object:IsValid()
end

-- Catch Lua/reflection errors at the engine callback boundary, with their cause.
local function run(reason, action)
    local ok, err = pcall(action)
    if not ok then
        log("ERROR [" .. reason .. "] " .. tostring(err))
    end
end

local function set_cap(session, reason)
    local before = session.MaxPlayers
    assert(type(before) == "number", "GameSession.MaxPlayers is not a numeric property")
    if before ~= cap then
        session.MaxPlayers = cap
    end
    local after = session.MaxPlayers
    assert(after == cap, "GameSession.MaxPlayers write failed: expected " .. cap
        .. ", read " .. tostring(after) .. " on " .. session:GetFullName())
    if before ~= after then
        log("MaxPlayers " .. tostring(before) .. " -> " .. after
            .. " [" .. reason .. "] " .. session:GetFullName())
    end
end

local function apply_session(session, reason)
    if not valid(session) then return end
    set_cap(session, reason)
    -- GetCDO is the UE4SS method; GetDefaultObject is not a Lua API method.
    local cdo = session:GetClass():GetCDO()
    assert(valid(cdo), "GameSession class default object is unavailable")
    set_cap(cdo, reason .. "/default")
    log("live MaxPlayers=" .. session.MaxPlayers
        .. " [" .. reason .. "] " .. session:GetFullName())
end

local function apply_all(reason)
    local cdo = StaticFindObject(SESSION_CDO)
    assert(valid(cdo), "Cannot find " .. SESSION_CDO)
    set_cap(cdo, reason .. "/default")
    -- FindAllOf also includes subclasses and excludes class default objects.
    for _, session in ipairs(FindAllOf("GameSession") or {}) do
        run(reason, function() apply_session(session, reason) end)
    end
end

local function apply_game_mode(context, reason)
    -- The native InitGameState callback supplies AGameModeBase, wrapped as a
    -- RemoteUnrealParam. Unwrap it inside the callback, never in a deferred task.
    local game_mode = context:get()
    if valid(game_mode) then
        apply_session(game_mode.GameSession, reason)
    end
end

-- Construction is too early: InitOptions can replace MaxPlayers afterwards.
-- InitGameState covers new game modes, including seamless level travel.
RegisterInitGameStatePostHook(function(context)
    run("game initialized", function() apply_game_mode(context, "game initialized") end)
end)

-- Re-check after the map's initialization/BeginPlay has finished.
RegisterLoadMapPostHook(function()
    run("map loaded", function() apply_all("map loaded") end)
    -- Do not return anything: the engine's LoadMap result must be preserved.
end)

-- Match the Blueprint event by name, including overrides on map game modes.
-- Earlier (1st-4th) logins must not leave the next join with a reset cap.
-- Rejected players do not reach PostLogin; this is not an admission override.
RegisterCustomEvent("K2_PostLogin", function(context)
    run("after player login", function()
        local game_mode = context:get()
        if valid(game_mode) and game_mode:IsA("/Script/Engine.GameModeBase") then
            apply_session(game_mode.GameSession, "after player login")
        end
    end)
end)

local function diagnostics()
    log("v" .. VERSION .. "; target=" .. cap .. "; diagnostics (read only)")
    local count = 0
    for _, session in ipairs(FindAllOf("GameSession") or {}) do
        if valid(session) then
            count = count + 1
            log("live MaxPlayers=" .. tostring(session.MaxPlayers) .. "; " .. session:GetFullName())
            local cdo = session:GetClass():GetCDO()
            if valid(cdo) then log("default MaxPlayers=" .. tostring(cdo.MaxPlayers)) end
        end
    end
    if count == 0 then
        log("No live GameSession. Host a lobby before collecting diagnostics.")
    end
end

-- Key callbacks are outside the game thread; only queue work from here.
RegisterKeyBind(Key.F10, function()
    ExecuteInGameThread(function() run("diagnostics", diagnostics) end)
end)

-- Cover an already running session and prepare the engine default for hosting.
ExecuteInGameThread(function() run("startup", function() apply_all("startup") end) end)
log("v" .. VERSION .. " loaded; target MaxPlayers=" .. cap
    .. ". Lifecycle hooks registered. F10: session diagnostics.")
