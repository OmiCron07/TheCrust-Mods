---
type: Research
title: Mining Zone Brush (Dig Zones Queue Ruler)
description: How the mining zone brush size cycles, which native calls build and paint brush cells, and the UE4SS hook quirks used by the BiggerMiningBrush mod.
tags: [research, mining, dig, brush, drones, ue4ss, hooks, biggerminingbrush]
status: draft
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/DigZonesQueueRuler.hpp
    title: ADigZonesQueueRuler_C, W_MiningPanel_C, ADigZoneQueueRulerBase (TheCrust.hpp)
  - id: bytecode
    resource: TheCrust/Content/Blueprints/Ground/DigZonesQueueStuff/DigZonesQueueRuler.uasset
    title: DigZonesQueueRuler and W_MiningPanel ubergraph bytecode (UAssetGUI tojson)
  - id: live-probe
    resource: Scripts/Invoke-DevBridge.ps1
    title: DevBridge probes 2026-10-08
---
## Goal
Explain the mining zone brush so its size and shape can be modded.

## Verified Facts
- Actor `DigZonesQueueRuler_C` (`/Game/Blueprints/Ground/DigZonesQueueStuff/`), parent native `ADigZoneQueueRulerBase` (`/Script/TheCrust`). Fields: `BrushSize` (int32), `BrushMode`, `UltraZoneMode`, `CurrentBrushZoneID`, `GridSize` (400), `Zones`, `ZoneIdQueue`, `SummNomberOfSelectedSellsLimit` (200000).
- Cell index = `Row * GridSize + Col`.
- `ToggleBrushSize` (BP, called by `Execute Toggle Brush Size` from the mining panel button) is a switch: 1->2, 2->3, 3->1, any other value unchanged. Then broadcasts `BrushSizeToggled(BrushSize)`.
- Panel `W_MiningPanel_C`: label widget `BrushZizeLabel` (sic), `SetBrushSizeLabelText()` writes `"x" .. PC:"Getter Dig Zone Brush Size"` (= ruler `BrushSize`). Runs from the `BrushSizeChanged` delegate handler.
- `FindAllOf("W_MiningPanel_C")` also returns the `W_MainWidget_C:WidgetTree.WGTMining` template (no `BrushZizeLabel`, not flagged `RF_ArchetypeObject`).
- Native `GetBrushCellsRaw(Center, Size)`: size 1 = 1 cell, 2 = 5 (plus), 3 = 21 (5x5 minus corners); size >= 4 returns only the center. Shape = disc radius `r = Size - 1`, `dx^2 + dy^2 <= r^2 + max(r - 1, 0)`. Used by the ubergraph for hover preview, ground selection (`ApplyGroundSelection[_withoutvisual]`), erase and `GetBrushCells`.
- Native `ApplyNewBrushPrint(Center, Size, Ultra, ZoneID)` adds the brush to zone `ZoneID`; size >= 4 paints only the center, and it does not call the hooked `GetBrushCellsRaw` UFunction. Repeated size 1 prints into the same zone are cheap (40 calls < 1 ms).
- `EraseCells(Cells)` removes cells from their zones (`GetCellZoneID` back to -1); used to undo live tests.
- `GetSquare(Center, N)` returns a (2N-1)^2 square, unused by the brush.

## UE4SS 3.0.2 Hook Quirks
- Blueprint function hook (`/Game/...`): the single callback runs AFTER the function.
- Native hook (`/Script/...`): pre and post callbacks. Post callback args are `(Context, ReturnValue, Params...)` for functions with a return value; void functions get `(Context, Params...)`.
- Returning a Lua table from a native post callback does NOT override a `TArray` return. Grow the array in place instead: `Arr = ReturnValue:get(); Arr[Arr:GetArrayNum() + 1] = v`.
- Native hooks fire for UFunction calls from Lua (verified); calls from Blueprint bytecode expected to fire too (pending in-game check of the brush preview); C++-internal calls never do.

## Pitfalls & Dead Ends
- The switch default looks like `-> 1` in a flat bytecode dump; it is a bare `pop` (no change). Verify switch defaults live.
