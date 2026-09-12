# MoreRVers - Multiplayer Expansion Mod for RV There Yet?

![Version](https://img.shields.io/badge/version-1.1.0-blue)
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
- **Runtime Patching** - Applied immediately upon session creation

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
3. The mod ships with an `enabled.txt` marker file, so UE4SS picks it up with no
   further setup. If your UE4SS build ignores that, enable it explicitly by
   editing `ue4ss\Mods\mods.txt`:
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
│                       ├── enabled.txt
│                       ├── config.ini           
│                       │
│                       └── scripts\
```

## Configuration

Edit `ue4ss\Mods\MoreRVers\config.ini`:

```ini
MaxPlayers = 8
```

**Configuration Parameters:**
- Default: 8 (vanilla game limit is 4)
- Range: 1-24
- Recommended: 8 for optimal stability

The game must be restarted for configuration changes to take effect.

### Advanced options

These are only worth touching while troubleshooting:

| Key | Default | Purpose |
| --- | --- | --- |
| `LogLevel` | `INFO` | `DEBUG` makes the mod log every object and property it inspects. Set this before reporting a bug. |
| `ReapplySeconds` | `10` | How often the cap is re-applied. The game can overwrite the cap after the mod sets it; set to `0` to disable. |
| `HardUpperLimit` | `24` | `MaxPlayers` is clamped to this. |
| `SanityCeiling` | `64` | The mod only overwrites cap-like values at or below this, so it can never clobber an unrelated number. |
| `WatchActorSpawns` | `1` | Checks each spawned actor for being a `GameSession`. Set to `0` if you suspect a performance cost. |

## Verification

**In game, press `F10`.** The mod prints a diagnostics report: its version, the
target cap, which hooks it managed to install, and every player-cap property it
can currently see, with its live value. If the UE4SS console is enabled you can
also type `morervers` there for the same report.

The report goes to the UE4SS console and to `UE4SS.log`, which sits next to
`UE4SS.dll` in the `ue4ss` folder. That file is what to attach to a bug report.

On a working install the log contains lines like:

```
[21:04:11] [MoreRVers] [INFO] MoreRVers v1.1.0 loading. Target cap=8 (hard max 24). Engine: UE 5.5
[21:04:11] [MoreRVers] [INFO] BP_RideGameSession_C.MaxPlayers: 4 -> 8 (new GameSession)
```

## Troubleshooting

### After a game update, start here

A game patch can change the engine build, which stops **UE4SS itself** from
loading. When that happens no mod runs and `UE4SS.log` will not contain any
`[MoreRVers]` lines at all.

1. Check whether `UE4SS.log` exists and has recent entries. If it does not,
   UE4SS never attached: update to the latest
   [UE4SS experimental build](https://github.com/UE4SS-RE/RE-UE4SS/releases)
   and re-install.
2. If the log contains `Failed to find EngineVersion`, set the engine version
   manually in `UE4SS-settings.ini`:
   ```ini
   [EngineVersionOverride]
   MajorVersion = 5
   MinorVersion = 5
   ```
   Use the version the game's launcher or `Ride-Win64-Shipping.exe` reports.
3. If the log *does* contain `[MoreRVers]` lines, the mod is loading and the
   problem is the cap itself. Press `F10` while hosting and read the report.

### Mod fails to load

- Check `UE4SS.log` for error messages
- Verify UE4SS 3.0.1 or higher is installed
- Confirm the file structure matches the documented structure
- Confirm `ue4ss\Mods\MoreRVers\enabled.txt` exists, or that the mod is listed
  in `mods.txt` / `mods.json`

### Player limit remains at 4

Press `F10` and read the diagnostics report.

- **"Active triggers: NONE"** - UE4SS loaded but does not expose the Lua API the
  mod expects. Update UE4SS.
- **"No cap-like properties found"** - either no session exists yet (host a game
  first, then press `F10`), or the game moved the cap somewhere the mod does not
  look. Set `LogLevel = DEBUG`, reproduce, and open an issue with the log.
- **The report lists a property still sitting at `4`** - the write is being
  rejected or the game is overwriting it. Attach the report to an issue.
- Sanity-check the mod is doing anything at all by setting `MaxPlayers = 1`. If
  you can no longer host anyone, the override works and the remaining limit is
  elsewhere.

### Game crashes or instability

- Reduce the configured player count
- Verify UE4SS version compatibility
- Report issues with the complete `UE4SS.log`

## Development

`tools/ue4ss_stub_test.lua` stubs the UE4SS Lua globals so `main.lua` can be
exercised without launching the game. Run it from the repo root:

```bash
lua5.4 tools/ue4ss_stub_test.lua
```

It is also run by the release workflow before packaging.

## Contributing

Bug reports and feature suggestions can be submitted via GitHub Issues. Pull requests are welcome.

## License

MIT License. See LICENSE file for details.

## Credits

- **UE4SS Team** - Unreal Engine modding framework
- **RV There Yet? Community** - Testing and feedback
