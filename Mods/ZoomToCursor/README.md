# ZoomToCursor Mod for The Crust

## Overview
By default in **The Crust**, scrolling the mouse wheel zooms the camera strictly into and out of the center of the viewport (the `GodPawn` anchor location).

**ZoomToCursor** intercepts the camera zoom axis event and shifts the camera position so that zooming in or out focuses dynamically on the world location directly under your mouse cursor, similar to standard RTS and factory building games (Factorio, Beyond All Reason, Anno, etc.).

## Features
- **Accurate Geometric Projection**: Traces ray collision or mathematical ground-plane intersection to identify the exact 3D world coordinate under the cursor.
- **Proportional Focal Shift**: Calculates the exact shift factor based on spring arm length and zoom step to keep the targeted world point stationary under the mouse cursor.
- **Underground Extended Zoom-Out**: Expands maximum underground camera distance (vanilla 4200.0) up to 10000.0+ while preserving the native surface / crater zoom limit (25000.0).
- **Safe Boundary Clamping**: Prevents accidental camera drift beyond crater and surface boundaries.
- **WASD Friendly**: While the camera is moved with WASD / arrows (plus a 0.3 s grace period), zoom stays vanilla (screen center) and any pending cursor shift is cancelled. The cursor shift is applied as a delta on top of the current position, so it never pulls the camera back.
- **Configurable**: Easily toggle zoom-in vs zoom-out behavior, adjust intensity multipliers, set underground zoom distance, or enable debug logging in `Scripts/config.lua`.

## Configuration (`Scripts/config.lua`)
- `ZoomInToCursor` (boolean, default: `true`): Focuses zoom on cursor when scrolling up.
- `ZoomOutFromCursor` (boolean, default: `false`): Zooms out away from the cursor when scrolling down (false = screen center vanilla).
- `ZoomStrengthMultiplier` (float, default: `1.0`): Multiplier for the per-notch shift towards the cursor (capped at 90% of the cursor distance).
- `UndergroundMaxZoom` (float, default: `10000.0`): Maximum spring arm camera distance underground (vanilla: 4200.0).
- `ClampToMapBounds` (boolean, default: `true`): Keeps camera within map boundaries.
- `DebugLogging` (boolean, default: `false`): Prints real-time coordinates and shifts to UE4SS console/log.

## Installation
Download `TheCrust-ZoomToCursor.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, run the deployment script from PowerShell:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\ZoomToCursor"
```

Both overwrite `config.lua`; to keep a customized config, copy only `Scripts/main.lua`. Quit the game before installing or deploying: the UE4SS auto-reload of a mod hooking `GodPawn_C:ArmLenght` usually crashes the game.
