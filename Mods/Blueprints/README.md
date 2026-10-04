# Blueprints Mod for The Crust

## Overview
Select an area, copy/paste it or save it as a reusable blueprint. Pasting places **vanilla ghosts**:
modules in planning mode (with their production scheme), holo conveyor belts and the electric wires
between pasted modules. Build them afterwards with the normal game buttons.

## Controls
| Key | Action |
|-----|--------|
| `K` | Open / close the blueprint manager panel |
| `Ctrl+K` | Select an area, then drag with the left mouse button |
| `Ctrl+Shift+K` | Copy the selection and start pasting it |
| `Alt+K` | Paste the clipboard again |
| `Shift+K` | Start construction of the planned modules and holo belts in the selection |
| `Ctrl+Alt+K` | Switch pasting between planning ghosts and direct construction |
| `R` / `Shift+R` | While pasting: rotate clockwise / counter clockwise |
| Left click | While pasting: place the ghosts (stay in paste mode) |
| Right click | Cancel the selection / stop pasting |

### Paste preview
- Cyan outline: the module can be placed there; red outline: it cannot (overlap, undug ground,
  or the module's own rule).
- Extractors: their active cells are shown as small squares, green on an ore vein, red elsewhere;
  the outline turns cyan once enough cells cover a vein (vanilla rule).
- Orange strips: conveyor belts (cells already used are skipped when pasting).

The panel offers the same actions plus the library: name a selection and click **Save selection**,
then **Place**, **Rename** (uses the name box) or **Delete** (click twice) a saved blueprint.

### Paste modes
- **Plan** (default, `PasteAsConstruction = false`): vanilla planning ghosts, built later with the
  play button of each module, or all at once with **Build selection** / `Shift+K`.
- **Build**: construction starts right away. Modules over the supply limit stay planned; belt
  sections are paid in credits like the vanilla build and stay holo when credits are missing.

## What is copied
- Modules with rotation, mirroring and production scheme.
- Conveyor belts (straight lines and turns), on built or holo sections.
- Electric wires whose two ends are both copied modules.

Not supported yet: distributors and underground belts (the game only creates them from real mouse
input), storage/logistics settings other than the production scheme.

## Configuration (`Scripts/config.lua`)
- `Keys`: hotkeys (avoid letters the game binds: B/C/E/F/G/H/J/L/M/N/P/Q/R/T/U/V/X/Y/Z).
- `PasteConveyors` / `PasteElectricLinks`: toggle belt and wire pasting.
- `PanelPosition`: panel offset from the top-right corner.
- `DebugLogging`: log per-module paste errors to the UE4SS log.

The library is stored in `library.lua` next to the `Scripts` folder.

## Installation
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\Blueprints"
```

## Development
- `Scripts/selftest.lua`: pure checks (grid math, belt decomposition, serialization), runnable with any Lua 5.4.
- Research notes: `Knowledge/Research/BuildingSystemAndBlueprints.md`.
