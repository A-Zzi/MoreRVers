# MoreRVers - Multiplayer Expansion Mod for RV There Yet?

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Game](https://img.shields.io/badge/game-RV%20There%20Yet%3F-orange)
![Modloader](https://img.shields.io/badge/modloader-UE4SS-purple)

A runtime modification that increases the multiplayer player cap beyond the default 4-player limit for RV There Yet.

## Overview

This mod patches the game's multiplayer cap at runtime, allowing you to host sessions with more than the default 4 players. The modification uses UE4SS for runtime patching without requiring binary editing or permanent game file changes.

## Features

- **Simple Configuration** - Single-value INI file configuration
- **Host-Only Requirement** - Clients do not require mod installation
- **Non-Destructive** - No permanent game file modifications
- **Flexible Limits** - Configurable player count from 1-24
- **Runtime Patching** - Applied immediately upon session creation

## Installation

### Requirements
- [UE4SS 3.0.1+](https://github.com/UE4SS-RE/RE-UE4SS/releases) (experimental version recommended)
- RV There Yet? (Steam version)

### Installation Steps

1. Download the latest experimental branch of UE4SS. The zip file should be named something along the lines of `UE4SS_v3.0.1-570-g3d4fbd0.zip`


2. Install UE4SS in your game directory:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\
   ```

3. Copy the mod to the UE4SS Mods folder:
   ```
   <Steam>\steamapps\common\Ride\Ride\Binaries\Win64\ue4ss\Mods\MoreRVers\
   ```

4. Enable the mod by editing `ue4ss\Mods\mods.txt` and adding:
   ```
   MoreRVers : 1
   ```
   Note: Add this entry before the `Keybinds` line.

5. Configure the player limit by editing `config.ini`:
   ```ini
   MaxPlayers = 8
   ```

6. Launch the game and host a session.

## Configuration

Edit `UE4SS/Mods/MoreRVers/config.ini`:

```ini
MaxPlayers = 8
```

**Configuration Parameters:**
- Default: 8 (vanilla game limit is 4)
- Range: 1-24
- Recommended: 8 for optimal stability

The game must be restarted for configuration changes to take effect.

## Verification

Successful installation can be verified by checking the UE4SS console for the following messages:

```
[MoreRVers] [INFO] MoreRVers v1.0.0 loading. Target cap=8 (hard max 24)
[MoreRVers] [INFO] Applied MaxPlayers override: 4 → 8
```

## Troubleshooting

### Mod fails to load

- Check UE4SS console for error messages
- Verify UE4SS 3.0.1 or higher is installed
- Confirm file structure matches the documented structure
- Ensure mod is enabled in `mods.txt`

### Player limit remains at 4

- Check console for "Applied MaxPlayers override" confirmation message
- Test with `MaxPlayers = 1` to verify mod functionality
- Review `UE4SS-settings.ini` to ensure Lua scripting is enabled

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
