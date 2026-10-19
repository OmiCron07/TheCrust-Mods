# Plan: Flow Inspector (new mod `Mods/FlowInspector/`)

Status: not started. Research: `Knowledge/Research/ProductionStates.md`.

## Goal (v1)
A toggle key tints the footprint of every production module on the viewed layer by its live state, so stalled chains are found at a glance instead of clicking module by module.

| State | Color | Source |
|-------|-------|--------|
| Producing | green | `ProductionStateCPP == 1` |
| Starved (inputs missing) | orange | IDLE + `CheckIfCanTakeAllResourcesByRuleCPP() == false` |
| Blocked (output full) | red | IDLE + `CheckIfCanStoreAllResourcesByRuleCPP() == false` |
| No power / water / O2 | purple | `CanProduceSomethingByFlowResources() == false` |
| No colonists | blue | `ProductionStateCPP == 3` |
| Depleted extractor | grey | `bMineralFieldWasDepleted` |

## Steps
0. **DevBridge probe (read-only)** on known modules (one producing, one starved, one blocked): dump `ProductionStateCPP` and the `Check*` results. Confirm the checks are side-effect free (no notification, state unchanged after two calls). Answer the open questions in the research card, set it `stable`, commit.
1. **Scaffold** on the RegolithIcons pattern: `config.lua` (toggle key, refresh interval), tick hook, layer filter, session / loading guard, module cache via `NotifyOnNewObject("/Script/TheCrust.ModuleBase", ...)`.
2. **`status.lua`**: pure `Classify(Fields) -> Status`; `selftest.lua` with asserts covering every row of the table and priority order (no power before starved, etc.).
3. **Visual**: translucent tinted box over the module cells (`Game.ModuleCells`). Copy the minimum of `NewBox` from `Mods/Blueprints/Scripts/visuals.lua`.
4. **Refresh** about once per second, only while shown, only current layer. Skip ghosts (`bPlanningModeCPP`), modules under construction, and modules without a production agency (storages).
5. **Live verify** per `Knowledge/Playbooks/LiveVerification.md`, with screenshots. Never deploy while the game runs.
6. README, release zip (`Knowledge/Playbooks/ModReleasePlaybook.md`), commit.

## Out of v1
- Belt saturation heatmap: `UCSection.State.Resources` is unreliable (`StorageBeltIO.md`).
- "Top N bottlenecks" panel with camera focus.
- Icon of the missing input resource over starved modules.

## Risks
- `Check*` may raise notifications: step 0 decides. Fallback: `CanStartProductionCycleDueInputAndOutputResourcesCPP(false)` plus manual storage reads.
- Refinery blocked as soon as one output is full, even a 0 % oxide: show it as the game judges it (intended).
