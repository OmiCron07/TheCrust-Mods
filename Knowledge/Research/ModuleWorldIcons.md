---
type: Research
title: World Icons over Modules (Production Indicator Widget)
description: How to show a resource icon over a module in the world from UE4SS Lua, and the UE4SS quirks met building the RegolithIcons mod.
tags: [research, ui, widget, regolith, storage, ue4ss, regolithicons]
status: stable
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/ModuleBase_BP.hpp
    title: AModuleBase_BP_C, UW_ProductionIndicator_C, UStorageModuleAgency (TheCrust.hpp)
  - id: bytecode
    resource: TheCrust/Content/Blueprints/Modules/ModuleBase_BP.uasset
    title: ExecuteUbergraph_ModuleBase_BP (Begin/End Hover)
---
## Goal
Draw a resource icon over modules in the world (RegolithIcons: dominant oxide over regolith modules).

## Verified Facts
- Every `AModuleBase_BP_C` has `ProductionOutputIndicator`: `UWidgetComponent`, Space Screen, DrawSize 500x500, Pivot 0.5, hidden, widget `/Game/Widgets/W_ProductionIndicator.W_ProductionIndicator_C` (`"Set Resource Icon"(EResourceType)`, any type incl. Regolith = 1). Vanilla sets icon + visibility on module Begin/End Hover, so do not drive it from a mod.
- Own icon: `Actor:AddComponentByClass(/Script/UMG.WidgetComponent, false, Identity, true)`, set `Space = 1`, `WidgetClass`, `DrawSize`, `Pivot`, then `FinishAddComponent`; widget object exists right after. Verified in game 2026-10-09.
- Placement: world location = top of `GetActorBounds(true, O, E, false)` (`O.Z + E.Z`). Higher points drift off the module under the tilted camera (+150 visibly offset). Screen-space widgets do not show over full-screen menus (research tree).
- New widget components show the widget's default image (lilac box) until hidden: call `SetVisibility(false, true)` when there is nothing to show.
- Regolith storage test: `UStorageModuleAgency.MaxResourceLimit[Regolith] > 0`. BP `ResourcesAtThisStorage` is empty on bulk storages. Composition: `CurrentResourceRegolithPercentage` (keys 2 Ti, 3 Fe, 4 Si, 5 Al, 6 Slag, also 24 Water = 0).
- Storage agencies: extractor `SAO_Regolith`, Multi refinery `SAI_Regolith`, Single refinery `SAI_Regolith_or_Slag`, `MB_BigBulkStorage_C` / `MB_VeryBigBulkStorage_C` `SA_Bulk`. `MB_BulkStorage_C` has no instances (unused class).
- `FindAllOf` returns main menu level sequence copies (`/Game/Movies/LevelSequencers/...:MovieScene_0.*`, no `SA_Bulk`): keep only names containing `:PersistentLevel.`. Planning ghosts: `bPlanningModeCPP = true`.
- `FindAllOf` for 5 module classes costs ~220 ms (large base): never poll it. `NotifyOnNewObject("/Script/TheCrust.ModuleBase", cb)` catches every module (inheritance) at construction; queue there and initialize ~2 s later.
- Icon colors match the refinery panel: titanium white, iron orange-red, silicon purple, aluminium teal, slag blue.

## Pitfalls & Dead Ends
- `HasActorBegunPlay` is not reflected (TrivialObject). `WidgetComponent.WidgetClass` read from Lua is not a UObject wrapper (no `IsValid`): compare `GetUserWidgetObject():GetClass():GetAddress()`.
- `K2_GetComponentsByClass` returns a Lua table of `RemoteUnrealParam` (unwrap with `:get()`), not a TArray (`ForEach` is nil).
- `GetActorBounds` out params: each table gets its own `X/Y/Z` (not keyed by parameter name like some other functions).
- UE4SS wrappers of the same object are not `==`: compare `GetAddress()`.
