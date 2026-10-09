# CheaperBelts Mod for The Crust

## Overview
Lowers the credit cost of conveyor belts: building belts, distributors and underground belts, and
upgrading belt tiers. Half price by default, configurable.

## How it works
The game copies `DT_ConveyorConfig` into `ConveyorSubsystem.ConveyorConfig` once per game launch and
reads every belt price from there. The mod writes `vanilla x multiplier` into that copy at startup and on
every map load. The belt panel labels read the DataTable directly (once, when the panel is created), so
the mod also rewrites them with the scaled prices. Nothing is written to the save: removing the mod restores vanilla prices on the next
launch.

| Cost (credits per cell) | Vanilla | Default (x0.5) |
|-------------------------|---------|----------------|
| Belt                    | 250     | 125            |
| Distributor             | 1000    | 500            |
| Underground belt        | 600     | 300            |
| Upgrade to tier 2 / 3 / 4 / 5 | 500 / 1000 / 2000 / 4000 | 250 / 500 / 1000 / 2000 |

Demolition still refunds 75% of the belt cost (`ConveyorCostRecoupPart`, not scaled).

## Configuration (`Scripts/config.lua`)
- `BuildCostMultiplier` (float, default: `0.5`): multiplier on the build cost of belts, distributors and
  underground belts (1.0 = vanilla, 0.0 = free).
- `UpgradeCostMultiplier` (float, default: `0.5`): multiplier on the belt tier upgrade cost.

Restart the game after editing the config.

## Installation
Download `TheCrust-CheaperBelts.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, quit the game, then run:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\CheaperBelts"
```
