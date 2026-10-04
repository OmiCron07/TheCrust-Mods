# ZoomToCursor Mod for The Crust

## Overview
By default in **The Crust**, scrolling the mouse wheel zooms the camera strictly into and out of the center of the viewport (the `GodPawn` anchor location).

**ZoomToCursor** intercepts the camera zoom axis event and shifts the camera position so that zooming in or out focuses dynamically on the world location directly under your mouse cursor, similar to standard RTS and factory building games (Factorio, Beyond All Reason, Anno, etc.).

## Features
- **Accurate Geometric Projection**: Traces ray collision or mathematical ground-plane intersection to identify the exact 3D world coordinate under the cursor.
- **Proportional Focal Shift**: Calculates the exact shift factor based on spring arm length and zoom step to keep the targeted world point stationary under the mouse cursor.
- **Safe Boundary Clamping**: Prevents accidental camera drift beyond crater and surface boundaries.
- **Configurable**: Easily toggle zoom-in vs zoom-out behavior, adjust intensity multipliers, or enable debug logging in `Scripts/config.lua`.

## Configuration (`Scripts/config.lua`)
- `ZoomInToCursor` (boolean, default: `true`): Focuses zoom on cursor when scrolling up.
- `ZoomOutFromCursor` (boolean, default: `true`): Centers zoom away from cursor when scrolling down.
- `ZoomStrengthMultiplier` (float, default: `1.0`): Multiplier for the zoom displacement vector (1.0 = exact 1:1 focal match).
- `ClampToMapBounds` (boolean, default: `true`): Keeps camera within map boundaries.
- `DebugLogging` (boolean, default: `false`): Prints real-time coordinates and shifts to UE4SS console/log.

## Installation
Run the deployment script from PowerShell:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\ZoomToCursor"
```
Or manually copy the `ZoomToCursor` folder into:
`<The Crust Install>\TheCrust\Binaries\Win64\ue4ss\Mods\`
and ensure `ZoomToCursor : 1` is present in `mods.txt`.
