---
type: Research
title: Belt Drag Tool & Auto Underground
description: How the vanilla belt drag tool previews and builds a path, how to redraw its preview, and how the AutoUnderground mod bridges belt crossings.
tags: [research, conveyor, belt, underground, hover, preview, autounderground]
status: draft
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/TheCrust.hpp
    title: UConveyorController, AConveyorManager, BP_ConveyorManager
  - id: live-probe
    resource: Scripts/Invoke-DevBridge.ps1
    title: Live hooks, simulated hovers / clicks and screenshots (2026-10-09)
---
## Goal
Make a belt dragged across existing belts go under them (underground pairs) instead of failing.

## Verified Facts
- **Belt tool** (`ECInputMode` 1): first `CM:MainPointerAction(Loc)` stores `Controller.FirstClickCellID`; `CM:OnHover(Loc)` computes the path from it and calls BP `ConstructHoverSectionPathVisual(CylinderPoints, FailurePointArrID, bIOCellAtStart, bIOCellAtEnd)` (`BP_ConveyorManager_C` override); the second click builds. `OnHover` and `MainPointerAction` are called from GodPlayer_PC Blueprint (imports in its uasset), so UE4SS native hooks on `/Script/TheCrust.ConveyorManager:OnHover` / `:MainPointerAction` fire on player input.
- **Hover path**: one `CylinderPoints` transform per cell in flow order (first click -> cursor), translation = cell center; `Scale3D` 0.7 every few cells (pillars), 0.35 otherwise. `FailurePointArrID` = 0-based index of the first blocked cell (red from there), -1 when the whole path is valid. Only the first failure is reported.
- Vanilla redraws the hover visual only when the cursor cell / state changes (a second `OnHover` on the same cell does not call the visual). It compares against `CM.LastHoverStartCellID` / `LastHoverEndCellID`.
- `Controller:IsVerticalPriority()` / `GetIsReversed()` only change the L leg order; points stay ordered from the first click to the cursor.
- **Blocked second click**: vanilla builds nothing and resets `FirstClickCellID` to -1. A valid second click builds the path as holo and also resets it (no chaining).
- Setting `FailurePointArrID` in the Blueprint hook (`Fail:set(-1)`) has no effect: UE4SS Blueprint hooks run after the function. Redrawing works: `CM:ClearHoverSectionPathVisual()` then `CM:ConstructHoverSectionPathVisual(LuaArrayOfFTransformTables, -1, bIOStart, bIOEnd)` draws a fully blue preview; leaving out points leaves gaps.
- **Underground max distance**: entry to exit index distance <= `CM.UndergroundBuildSectionLength` (8): 8 works, 9 fails (second click then starts a new lone end; delete it).
- Validating the rest of a path after a bridged crossing: `Controller:SetFirstClickCellID(Exit)` + `CM:OnHover(End)` gives vanilla's verdict for that sub-path (same leg order); restore `FirstClickCellID`, `LastHoverStartCellID`, `LastHoverEndCellID`, `LastSectionPathBuildCost`, `LastIsVertical` afterwards or vanilla sees a cursor change and redraws.
- Build order verified in game: underground pairs (vanilla mode 3 sequence, see [[Research/BuildingSystemAndBlueprints]]) then `BuildHolo(Start, Entry)`, `BuildHolo(Exit, NextEntry)` (2-cell exit -> adjacent entry links directly), `BuildHolo(Exit, End)`: everything links, crossed built belts untouched.

## Direct Code / CLI Snippet
```lua
-- Redraw the hover path fully valid (Points = Lua array of {Rotation, Translation, Scale3D} tables)
CM:ClearHoverSectionPathVisual()
CM:ConstructHoverSectionPathVisual(Points, -1, bIOCellAtStart, bIOCellAtEnd)
```
