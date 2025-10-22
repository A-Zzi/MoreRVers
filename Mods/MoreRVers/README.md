### MoreRVers - UE4SS Lua Mod for RV There Yet?

A runtime modification that increases the multiplayer player capacity by overriding `AGameSession.MaxPlayers` and bypassing 4-player join restrictions. Host-side installation only; client installation is not required.

## Functionality

**Implemented Features:**
- Configurable server capacity (default: 8, maximum: 24)
- Runtime patching of `GameSession` MaxPlayers property
- Join validation hook implementation
- Optional client UI modifications (disabled by default)

**Not Included:**
- Binary file modifications or anti-cheat bypass mechanisms
- Invasive UI modifications (fails gracefully if widgets are unavailable)

## Requirements

- UE4SS 3.0.1+ installed for RV There Yet? (Unreal Engine 5)
- Windows (Steam version)

## Installation

1. Install UE4SS according to official documentation
2. Locate game installation directory:
   ```
   <Steam>\steamapps\common\Ride\
   ```
3. Copy mod files to UE4SS Mods directory:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\ue4ss\Mods\MoreRVers\
   ```
4. Directory structure:
   ```
   MoreRVers/
     mod.json
     config.ini
     scripts/
       main.lua
       hooks/
         game_session.lua
         join_gate.lua
         ui_helpers.lua
   ```
5. Enable mod in `ue4ss\Mods\mods.txt`:
   ```
   MoreRVers : 1
   ```
   Note: Add entry before the `Keybinds` line.

6. Launch game and verify console output for `[MoreRVers]` messages.

## Configuration

Edit `UE4SS/Mods/MoreRVers/config.ini`:

```ini
MaxPlayers = 8
```

**Parameters:**
- Default: 8 (vanilla: 4)
- Range: 1-24
- Recommended: 8

Configuration changes require game restart.

## Host-Only Operation

- Mod installation required on host only
- Vanilla clients can connect without mod installation
- UI improvements visible only to clients with mod installed

## Technical Implementation

**Initialization Process:**
1. Engine information and configuration validation
2. `NotifyOnNewObject` callback registration for GameSession instantiation
3. Direct property patching of MaxPlayers on both live instance and Class Default Object (CDO)

**Hook Implementation:**
The mod attempts to hook the following functions:
- `/Script/Engine.GameSession:ReceiveBeginPlay`
- `/Script/Engine.GameSession:CanPlayerJoin`
- `/Script/Engine.GameSession:ApproveLogin`
- `/Script/Engine.GameModeBase:CanPlayerJoin`
- Blueprint-based gates: `LobbyGameMode_C:CanPlayerJoin`, `LobbyController_C:ValidateJoin`

## Verification

Expected console output on successful initialization:

```
[MoreRVers] [INFO] MoreRVers v1.0.0 loading. Target cap=8 (hard max 24)
[MoreRVers] [INFO] Applied MaxPlayers override: 4 → 8
```

**Validation Testing:**
- With `MaxPlayers=8`: 5th client should connect successfully
- With `MaxPlayers=8`: 9th client should be rejected by original validation logic

## Troubleshooting

**Mod Not Loading:**
- Verify UE4SS console for error messages
- Confirm UE4SS 3.0.1+ installation
- Validate file structure matches documentation
- Ensure mod is enabled in `mods.txt`

**Player Limit Not Applied:**
- Check console for "Applied MaxPlayers override" message
- Increase `LogLevel` to `DEBUG` for detailed output
- Verify Lua scripting is enabled in `UE4SS-settings.ini`

**Connection Failures:**
- Review console logs for hook status
- Enable `LogLevel = DEBUG` for detailed diagnostics
- Report hook signature failures if game has been updated

**UI Limitations:**
- Lobby may display only 4 slots (cosmetic limitation)
- UI improvements require mod installation on client

**Game Updates:**
- Hook signatures may become invalid after updates
- Mod fails gracefully to vanilla behavior
- Update signatures as needed based on console warnings

**Removal:**
- Close game
- Delete `UE4SS/Mods/MoreRVers/` directory
- Restart game

## Logging

- Prefix: `[MoreRVers]`
- Levels: DEBUG, INFO, WARN, ERROR
- Debug mode reports: engine classes, property values, hook registration status

## Known Limitations

- Network replication and performance scale with player count
- UI overflow may persist in certain menus
- Hook paths may require updates following game patches
- Failure modes are designed to preserve vanilla functionality

## Release Checklist

**Package Structure:**
```
MoreRVers/
  mod.json
  config.ini
  scripts/
    main.lua
    hooks/
      game_session.lua
      join_gate.lua
      ui_helpers.lua
```

**Validation:**
- Version numbers updated in `mod.json` and `main.lua`
- Changelog updated
- Host testing with `MaxPlayers=8`
- Verify 5th player connection and 9th player rejection
- Confirm hook registration in console logs

## Summary

**Hooked Functions:**
- `Engine.GameSession:ReceiveBeginPlay`
- `GameSession`/`GameModeBase` join validation functions
- Blueprint-based lobby gates (if present)

**MaxPlayers Modification:**
- Applied to live `AGameSession` instance
- Applied to `AGameSession` Class Default Object

**Configuration:**
- Edit `config.ini` and restart game to apply changes
