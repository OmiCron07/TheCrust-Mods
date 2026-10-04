---
type: Research
title: Building System, Ghost Placement & Blueprint Modding
description: How modules, conveyors and electric wires are placed (incl. planning-mode ghosts) and the UE4SS pitfalls met while building the Blueprints mod.
tags: [building, planning-mode, conveyors, electricity, ue4ss, blueprints]
status: stable
sources:
  - id: game-pak-core
    resource: pakchunk0-WindowsNoEditor.pak
    title: GodPlayer_PC, ModuleBase_BP, BP_ConveyorManager bytecode
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump (UE4SS GenerateSDK)
    title: TheCrust.hpp C++ reflection dump
stale_after: 2027-01-01
---
## Goal
Place modules, conveyor belts and electric wires programmatically as vanilla ghosts (planning mode) and capture them back from the world.

## Verified Facts
- **Grid**: 400 x 400 cells of 100 uu. `CellId = Row * 400 + Col`, Row grows with world X, Col with world Y. Underground pivot Z = 0, Crater pivot Z = 6001. `ECDirection`: 0 Up (-Row), 1 Right (+Col), 2 Down (+Row), 3 Left (-Col). Yaw +90 (vanilla `RotateModule(true)`) maps (dRow, dCol) -> (-dCol, dRow).
- **Layers**: `GodPlayer_PC.CurrentGameLayer` 0 Underground, 1 Orbital, 2 Crater. Conveyor managers: `PC.ConveyorManagerUnderground` / `PC.ConveyorManagerSurface` (`BP_ConveyorManager_C` : C++ `AConveyorManager`). `Level:GetGroundManager(TorchLocation)` takes 1 for underground, 0 for crater.
- **Modules** (`ModuleBase_BP_C` : `AModuleBase`): footprint in `CellIndexesUnderModule` (IO cells included, some listed twice), IO cells in `IOCells[i].CellId`. `BuildingStateCPP` 0 NotSettledYet ... 4 Finished, 6-8 dismantle. `"Settled Module"` is only true for modules placed this session (false after load). `IsCopyAllowed` = unlocked and built by player, or planned; electric pillars placed with the wire tool (C) never get `IsBuildedByPlayer` and are rejected by it.
- **Ghost module placement** (vanilla `PlacingModule LMB Click`): `PC:SpawnModuleOnLocation(Class, CellId)` -> optional `MirrorModule()` -> rotation -> `"Snap Module to Cursor"(Location)` -> validation -> `bPlanningModeCPP = bInPlanningMode = true` -> `SettleModule()` -> `IsBuildedByPlayer = true`. Hide the leftover validity squares with `Undercells[i]:SetVision(false)`.
- **Placement validation** (vanilla `TickFunctionForPlacingModuleMode`): when `CPPPlacementCheck` is false (`MB_ExtractorDeepOre` always returns false) vanilla only uses the module's `CheckIfCanSettleModuleAccordingToUndermoduleCells` override (extractor: at least `DT_GenerateVeinsSettings.MinimalCellCountForDeepOreExtractor` active cells on mineral fields) plus the count limit. Otherwise: `CPPPlacementCheck`, underground only `"Check Intersection Of Perimeter Cells and Soil"`, `CheckIfCanSettleModuleWithInteriorSettings`, `CheckPossibilityOfModuleSettlementAccordingToGM(GroundManager, GetAnchorCellCurrentRealID)`, `PC:CheckIfCanSettleCuzOfThisTypeModulesCount`. `CheckIfCanSettleModule` is NOT used by vanilla and wrongly rejects Big Bulk Storage.
- **Production scheme** = APS ability string: `AbilityAgencyVar."Active APS Ability"` (built) or `AbilityBeforeBuilt` when `bChangedRecipieBeforeBuilt`. Apply with `AbilityAgencyVar:ExecuteAbility(Name, nil)` (works on ghosts), as vanilla `Copy-PasteSettings` does.
- **Conveyors**: sections in `BuiltSectionStates` / `HoloSectionStates` (`FCSectionState`: `CellIds` in flow order, `LineDirections`, `CornerCellIDs`, `Type` 1 belt / 2 distributor / 3 underground belt) after `UpdateSectionStates()`; per cell via `SectionGrid` / `HoloSectionGrid :GetSectionAtCellID_Safe(Cell)`.
- `AConveyorManager:BuildHolo(Start, End, bVertical, false, -1)` creates holo (unbuilt, blue) belts: straight or L with `bVertical` choosing the first leg; it does NOT check overlaps with existing holo belts. It always creates belts, never distributors / underground belts.
- `UCSection:SetDeferred(true)` marks the planning flag (white "planning" look) but the visual only refreshes after a save reload; `bDeferModeActive`, input mode 8 and pointer actions did not make deferred holos from script.
- **Electric wires**: `Level.ElectricManager` (`AllNodesCPP`, `AllLinks` with GUID-suffixed fields `StartNode_7_...`, `EndNode_8_...`). Module node: `Module.ElectricNodeActor.Node.NodeID`. Vanilla link: `SetCurrentLinkStartNode`, `SetCurrentLinkEndNode`, `"Add Link"`, `AddLinkToItsNodes`, `"Add Neighbours By Link"`, `DrawCurrentLinkPersistent`, `ClearCurrentLinkInfo`.

- **Start construction of a ghost** (vanilla play button): `"Available For Building from PlanningMode"()` (supply + unlock) then `ChangeFromPlanningModeToDefault()`. **Build holo belts**: only `BuildAllConveyors` moves holo sections to the built grid (`BuildAllSectionsWithMoney` = pay total + `BuildAllConveyors`, skipping deferred sections). To build a subset, temporarily `SetDeferred(true)` every other holo section. `BuildSection` / `BuildSectionAtCellID` on a holo section only sets `bBuilt` and leaves it in the holo grid: a built belt and a holo drawn on top of each other (repair: `SetBuilt(false)` then `BuildAllConveyors`).

## Pitfalls & Dead Ends
- **Never call `FindFirstOf` / `FindAllOf` per frame**: they scan the whole GUObjectArray; two calls per frame halved the FPS (120 -> 45). Get the PC from the hooked `GodPawn_C.PlayerControllerRef` and cache the game instance (lives for the whole process).
- After a UE4SS auto-reload that stalled, `ExecuteInGameThread` queues stopped running and a later mod reload hung ("Stopping mod ... for uninstall" never followed by a restart): avoid `ExecuteInGameThread`/`LoopAsync` polling entirely, a game restart is required to recover.
- **GetFName on a null wrapper crashes the game** (EXCEPTION_ACCESS_VIOLATION reading 0x18 = `NamePrivate`). UE4SS returns null wrappers, not `nil`, and `pcall` cannot catch it. Always `type(o) == "userdata" and o:IsValid()` before touching an object.
- **UE4SS auto-reloads a Lua mod when its files change** (`EnableAutoReloadingLuaMods = 1`). Closures queued with `ExecuteInGameThread` (e.g. from `LoopAsync`) outlive the old Lua state and crash the game. Tick from a per-frame `RegisterHook` (e.g. `GodPawn_C:ArmLenght`) and only queue flags from `RegisterKeyBind` callbacks.
- UObject references (widgets, actors) must be dropped without being touched when the world changes (save load): key the session on `PC:GetFullName()` and idle while `CrustGameInstance_C.LoadingInProcess`.
- UE4SS out params: pass one table per out param; the first one receives all values by parameter name. A lone struct out param (e.g. `GetGridLocationByCellID`) is unpacked into the table (`X, Y, Z`). By-ref struct inputs (`"Add Link"(FLinkStruct&)`) need a Lua table copy, so write the returned `Added Link Id` back into `EM.CurrentLink` before `AddLinkToItsNodes`, or nodes get link id -1.
- `GetGridLocationByCellID` returns nothing for cells outside the level (e.g. cell 0).
- Vanilla input action mappings without modifiers also fire when Ctrl/Shift/Alt are held: `Ctrl+B` triggers belt mode. Use keys the game does not bind (K, I, O) for mod hotkeys.
- `"Debug Execute Cancel Ability"` on a module crashed the game; remove ghosts with vanilla UI tools instead.
- Engine overlay materials (`M_SimpleUnlitTranslucent`, `BasicShapeMaterial`) ignore alpha set through a MID `Color` param: draw outlines, not filled boxes.

## Direct Code / CLI Snippet
```lua
-- Ghost module at a cell (planning mode), rotated a quarter turn clockwise
local Out = {}
PC:SpawnModuleOnLocation(Class, CellId, Out, {})
local M = Out["Out Module"]
M:K2_SetActorRotation({ Pitch = 0, Yaw = 90, Roll = 0 }, false)
M:RecalculateCellIndexesUnderModule(true, {})
local Snap = M["Snap Module to Cursor"]
Snap(M, Location, {})
M.bPlanningModeCPP, M.bInPlanningMode = true, true
M:SettleModule()

-- Holo belt L-shape from Start to End, vertical leg first
PC.ConveyorManagerUnderground:BuildHolo(StartCell, EndCell, true, false, -1)
```
