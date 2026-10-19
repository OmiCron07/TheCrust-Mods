---
type: Research
title: Module Production States (Producing / Starved / Blocked)
description: Where a production module's live state lives and which native checks tell starved from blocked; header-derived, not yet verified live.
tags: [research, production, module, state, flowInspector]
status: draft
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/TheCrust.hpp
    title: UProductionAgencyCPP, AModuleBase (ProductionAgencyCPPref)
  - id: cxx-header-enums
    resource: Extracted/CXXHeaderDump/TheCrust_enums.hpp
    title: EProductionState
stale_after: 2027-04-19
---
## Goal
Read why a production module is or is not producing, from UE4SS Lua (Flow Inspector mod).

## Verified Facts (header dump only)
- `AModuleBase.ProductionAgencyCPPref` -> `UProductionAgencyCPP` (storages have no production agency; `HasProductionCPP()` on the module).
- `UProductionAgencyCPP.ProductionStateCPP` : `EProductionState` = 0 NoProductionState, 1 ProducingSomething, 2 IDLE, 3 ProductionStoppedDueLackOfColonists.
- IDLE carries no reason. Candidate reason checks (all `bool`, no params):
  - `CheckIfCanTakeAllResourcesByRuleCPP()` false -> starved (inputs missing).
  - `CheckIfCanStoreAllResourcesByRuleCPP()` false -> blocked (output full).
  - `CanProduceSomethingByFlowResources()` false -> no power / water / oxygen.
  - `CanStartCycleDueMineralFieldConditionCPP()` / field `bMineralFieldWasDepleted` -> extractor depleted.
- Other fields: `CurrentProductionCycleProgressCPP` (float), `LastAveragePerformanceCPP` (float), `bOverdriveMode_CPP`, `bIsExtractor`, `ResourceTypeToInputStorageRef` / `ResourceTypeToOutputStorageRef` (`TMap<EResourceType, UStorageModuleAgency*>`).
- Vanilla already separates the two cases: `UpdateNotificationHasNoResourcesForProductionBlueprint()` and `UpdateNotificationForFullOutputStorageForBlueprint()`.
- `CanStartProductionCycleDueInputAndOutputResourcesCPP(bool WithNotifications)`: pass `false` to avoid notifications.
- Refinery gotcha (see `RegolithComposition.md`): one full output storage, even a 0 % oxide, blocks the whole cycle.

## Open Questions (verify with DevBridge before relying on them)
- Are the `Check*` functions side-effect free (no notification, `ProductionStateCPP` unchanged after repeated calls)?
- Does `ProductionStateCPP` stay `ProducingSomething` during a cycle that later stalls, or flip to IDLE between cycles only?
- Do planned / under-construction modules have a valid `ProductionAgencyCPPref`?

## Pitfalls & Dead Ends
- Belt item counts via `UCSection.State.Resources` are unreliable (`StorageBeltIO.md`): do not build belt saturation on them.
