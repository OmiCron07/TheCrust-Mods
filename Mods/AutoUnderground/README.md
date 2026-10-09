# AutoUnderground Mod for The Crust

## Overview
Drag a belt across existing belts or modules and it goes under them: every crossing becomes an underground
belt pair. In vanilla the path turns red past the first obstacle and the click builds nothing.

## How it works
- While you drag a belt (belt tool, second click pending), the mod reads the vanilla hover path. When it is
  blocked by belts or modules (built or planned), each blocked run becomes an underground pair: entry on the
  free cell before the run, exit on the free cell after it. Close obstacles share one pair when it still
  fits in the vanilla length (8 cells from entry to exit).
- The preview turns fully blue, with no cube over the cells the path goes under.
- On the click, the mod places the underground pairs with the vanilla underground tool, then the belts
  between them, all linked. Planning mode is respected like vanilla belts.

A crossing is only bridged when:
- the underground belt is researched;
- the blocked cells are belts or modules (unexcavated ground keeps the vanilla red path);
- the crossing is straight (no corner under the crossed belts) and spans at most 8 cells from entry to
  exit (vanilla underground limit);
- the entry and exit cells are free.

Otherwise the vanilla behavior is unchanged. Nothing is written to the save beyond the belts you place.

## Installation
Download `TheCrust-AutoUnderground.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`).

From the repo, quit the game, then run:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\AutoUnderground"
```
