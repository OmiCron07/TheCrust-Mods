# RegolithIcons Mod for The Crust

## Overview
Shows the dominant oxide icon over regolith extractors, Single and Multi-Regolith Refineries and bulk
storages, so lines fed by different deposits are easy to tell apart and not mixed by mistake.

| Icon | Meaning |
|------|---------|
| Oxide icon (titanium, iron, silicon, aluminium) | That oxide is at least twice the next one in the regolith |
| Regolith icon | Blend: no oxide stands out (regolith from several deposits was mixed) |
| Resource icon (bulk storage set to another resource, Single refinery on slag) | The resource the storage takes |
| No icon | The module never held regolith |

Slag is ignored: it is in every deposit and never tells two lines apart.

## How it works
- Extractor: composition of its output storage (the deposit profile, `MineralField.ResourcePercentageForRegolithExtractor`).
- Refinery: composition of its regolith input storage.
- Bulk storage: composition of the stored regolith (the game blends what comes in, amount-weighted); set to
  another resource, the icon of that resource (its "Resource type").

The icon is the game's own `W_ProductionIndicator` widget, shown in screen space over the top of the
module, only for modules on the layer being viewed (underground or surface). Compositions are re-read
every 2 seconds; new modules get their icon once built (planning ghosts get none). Nothing is written to the save.

## Configuration (`Scripts/config.lua`)
- `ToggleKey` (UE4SS key name, default: `"I"`): shows / hides all the icons. Fires only with no
  Ctrl/Shift/Alt held. The game binds every letter except I, K and O (K is used by the Blueprints mod).
- `ShowAtStart` (boolean, default: `true`): icons visible when the game starts. The toggle state is not
  saved.

Restart the game after editing the config.

## Installation
Download `TheCrust-RegolithIcons.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, quit the game, then run:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\RegolithIcons"
```
