# MoreRVers - Multiplayer Expansion Mod for RV There Yet?

![Version](https://img.shields.io/badge/version-1.0.1-blue)
![Game](https://img.shields.io/badge/game-RV%20There%20Yet%3F-orange)
![Modloader](https://img.shields.io/badge/modloader-UE4SS-purple)

A runtime mod that increases the multiplayer player cap beyond the default 4-player limit for RV There Yet.

**Only the host needs to install the mod.**

## Overview

This mod patches the game's multiplayer cap at runtime, allowing you to host sessions with more than the default 4 players. The modification uses UE4SS for runtime patching without requiring binary editing or permanent game file changes.

## Features

- **Simple Configuration** - Single-value INI file configuration
- **Host-Only Requirement** - Clients do not require mod installation
- **Non-Destructive** - No permanent game file modifications
- **Flexible Limits** - Configurable player count from 1-24
- **Runtime Patching** - Applied after game initialization, map loading, and accepted-player Blueprint login events

## Installation

Two installation packages are available with each release. **The With-UE4SS package is recommended for most users.**

### Option 1: With-UE4SS (Recommended - Easy Install)

**File:** `MoreRVers-vX.Y.Z-WithUE4SS.zip`

This package includes UE4SS experimental and MoreRVers pre-configured. Just extract and play!

1. Download `MoreRVers-vX.Y.Z-WithUE4SS.zip` from the latest release
2. Navigate to your game directory:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\
   ```
3. Extract **all files** from the zip directly into the `Win64` folder
4. (Optional) Configure player limit by editing `ue4ss\Mods\MoreRVers\config.ini`:
   ```ini
   MaxPlayers = 8
   ```
5. Launch the game and host a session

**That's it!** The mod is pre-enabled!

### Option 2: Mod-Only (Advanced Users)

**File:** `MoreRVers-vX.Y.Z-ModOnly.zip`

Use this if you already have UE4SS experimental installed and configured.

**Requirements:**
- [UE4SS experimental branch](https://github.com/UE4SS-RE/RE-UE4SS/releases) (3.0.1+)
- RV There Yet? (Steam version)

**Installation:**

1. Download `MoreRVers-vX.Y.Z-ModOnly.zip` from the latest release
2. Extract the `MoreRVers` folder to:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\ue4ss\Mods\
   ```
3. Enable the mod by editing `ue4ss\Mods\mods.txt`:
   ```
   MoreRVers : 1
   ```
   Note: Add this line before `Keybinds : 1`
4. Configure the player limit in `ue4ss\Mods\MoreRVers\config.ini`:
   ```ini
   MaxPlayers = 8
   ```
5. Launch the game and host a session

## File Tree
When properly installed, your game directory should look similar to this:
```
{Steam}\steamapps\common\Ride\
├── Ride\
│   └── Binaries\
│       └── Win64\
│           ├── Ride-Win64-Shipping.exe         
│           ├── dwmapi.dll                       
│           │
│           └── ue4ss\                          
│               ├── UE4SS.dll                  
│               ├── UE4SS-settings.ini         
│               │
│               └── Mods\
│                   ├── mods.txt                 
│                   │
│                   └── MoreRVers\               
│                       ├── mod.json             
│                       ├── config.ini           
│                       │
│                       └── scripts\
```

## Configuration

Edit `UE4SS/Mods/MoreRVers/config.ini`:

```ini
MaxPlayers = 8
```

**Configuration Parameters:**
- Default: 8 (vanilla game limit is 4)
- Range: whole numbers from 1-24
- Recommended: 8 for optimal stability

The game must be restarted for configuration changes to take effect. A missing or invalid `MaxPlayers` value now stops the mod with an error in `UE4SS.log`; it does not silently substitute a different limit.

## Verification

When hosting, `ue4ss/UE4SS.log` should contain a startup message and a line such as:

```text
[MoreRVers] live MaxPlayers=8 [game initialized] GameSession ...
```

The startup message confirms only that the script loaded. `live MaxPlayers` is the value read from the actual session. Neither proves that a fifth player successfully connected through Steam; test that separately in a new lobby.

Press **F10** in game to log current live and class-default limits. Diagnostics run on the game thread and do not change the values they report.

The fix targets `GameSession.MaxPlayers` and its class default using `GetCDO()`. It reapplies after game initialization and map loading. `RegisterCustomEvent("K2_PostLogin", ...)` also handles Blueprint overrides on different game modes. Rejected players do not reach PostLogin; the callback prevents earlier accepted-player events from leaving the next join with a reset limit.

### Local checks

Run from the repository root with Lua 5.4:

```sh
luac5.4 -p Mods/MoreRVers/scripts/main.lua
lua5.4 tools/session_test.lua
```

The tests simulate UE4SS lifecycle callbacks, cap resets, travel to a session subclass, Windows config paths, read-only diagnostics, and failed property writes. They also assert game-thread object access. They do not run Unreal Engine, UE4SS's native hooks, or Steam networking. The host has also tested the patched mod in-game and confirmed that it works. The exact installed game build was not recorded.

## Troubleshooting

### Mod fails to load

- Check UE4SS console for error messages
- Verify UE4SS 3.0.1 or higher is installed
- Confirm file structure matches the documented structure
- Ensure mod is enabled in `mods.txt`

### Player limit remains at 4

- Host a fresh lobby and check for `live MaxPlayers` messages or `[MoreRVers] ERROR` in `ue4ss/UE4SS.log`.
- If a fifth player is disconnected, press F10 immediately afterwards and include the full `UE4SS.log` plus the game log from that join attempt in your report.
- If `live MaxPlayers` matches your configuration but joining still fails, the cause needs investigation in the game's admission or online session handling.
- `WidgetComponent ... NOT Supported` warnings alone do not establish a capacity failure. This mod does not change widgets or suppress networking warnings.

### Game crashes or instability

- Reduce the configured player count
- Verify UE4SS version compatibility
- Report issues with complete console logs

## Contributing

Bug reports and feature suggestions can be submitted via GitHub Issues. Pull requests are welcome.

## License

MIT License. See LICENSE file for details.

## Credits

- **UE4SS Team** - Unreal Engine modding framework
- **RV There Yet? Community** - Testing and feedback
