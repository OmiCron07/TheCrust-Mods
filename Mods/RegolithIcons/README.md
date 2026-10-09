# RegolithIcons Mod for The Crust

## Overview
Shows the dominant oxide icon over regolith extractors, Single and Multi-Regolith Refineries and bulk
storages, so lines fed by different deposits are easy to tell apart and not mixed by mistake.

| Icon | Meaning |
|------|---------|
| Oxide icon (titanium, iron, silicon, aluminium) | That oxide is at least twice the next one in the regolith |
| Regolith icon | Blend: no oxide stands out (regolith from several deposits was mixed) |
| No icon | The module never held regolith, or the bulk storage is set to another resource |

Slag is ignored: it is in every deposit and never tells two lines apart.

## How it works
- Extractor: composition of its output storage (the deposit profile, `MineralField.ResourcePercentageForRegolithExtractor`).
- Refinery: composition of its regolith input storage.
- Bulk storage: composition of the stored regolith (the game blends what comes in, amount-weighted).

The icon is the game's own `W_ProductionIndicator` widget, shown in screen space over the top of the
module. Compositions are re-read every 2 seconds; new modules get their icon once built (planning ghosts
get none). Nothing is written to the save.

## Installation
Download `TheCrust-RegolithIcons.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, quit the game, then run:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\RegolithIcons"
```
