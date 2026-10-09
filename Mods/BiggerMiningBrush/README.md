# BiggerMiningBrush Mod for The Crust

## Overview
Raises the max size of the brush used to paint mining zones for the drones from x3 to x10. The brush size
button of the mining panel keeps its vanilla behavior: each click adds 1 (x1, x2, ..., x10, then back to x1).

## How it works
The vanilla `DigZonesQueueRuler.ToggleBrushSize` cycles 1, 2, 3 and the native brush code
(`GetBrushCellsRaw`, `ApplyNewBrushPrint`) only knows sizes 1 to 3. The mod:
- steps the size after each click up to `MaxBrushSize` and refreshes the `xN` label;
- appends the missing cells to the brush returned by `GetBrushCellsRaw` (hover preview, ground selection,
  erase), using the vanilla disc shape: size N = disc of radius N - 1 (size 10 = 285 cells);
- paints the missing cells of a print as single-cell prints into the same zone.

Sizes 1 to 3 stay fully vanilla. Nothing is written to the save beyond the mining zones you paint.

## Configuration (`Scripts/config.lua`)
- `MaxBrushSize` (integer, default: `10`): largest brush size (vanilla: 3).

Restart the game after editing the config.

## Installation
Download `TheCrust-BiggerMiningBrush.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, quit the game, then run:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\BiggerMiningBrush"
```
