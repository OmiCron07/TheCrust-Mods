---
type: Research
title: Conveyor Build & Upgrade Costs
description: Where belt, distributor, underground belt and tier upgrade prices live at runtime and how the CheaperBelts mod scales them.
tags: [research, conveyor, belt, cost, credits, cheaperbelts]
status: draft
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/TheCrust.hpp
    title: FConveyorConfigInfo, UConveyorSubsystem, FMainDifficultyGlobalDataCPP
  - id: live-probe
    resource: Scripts/Invoke-DevBridge.ps1
    title: Live reads/writes of ConveyorSubsystem.ConveyorConfig (2026-10-08)
---
## Goal
Change belt prices from a Lua mod without touching paks or saves.

## Verified Facts
- Source data: `/Game/Data/Conveyors/ConveyorConfigData/DT_ConveyorConfig` (`FConveyorConfigInfo`), copied into `UConveyorSubsystem.ConveyorConfig` (game instance subsystem, one per process: `FindFirstOf("ConveyorSubsystem")`). `CM.ConveyorSubsystem` read from `PC.ConveyorManagerUnderground` was not a usable object in one probe; `FindFirstOf` works.
- Vanilla per cell (credits): `BeltCellCost` 250, `DistributorCellCost` 1000, `UndergroundBeltCellCost` 600, `ConveyorCostRecoupPart` 0.75 (demolition refund). `ConveyorUpgradeCosts` = [500, 1000, 2000, 4000] (TArray<float>, 1-based in Lua, `GetArrayNum()`; `#` fails on it).
- `GetCellCostBySectionType(Type)` (1 belt, 2 distributor, 3 underground) and `GetTierCost(t)` (cumulative sum of `ConveyorUpgradeCosts`: 0 / 500 / 1500 / 3500 / 7500) are computed on each call from `ConveyorConfig`: writing the struct fields or array entries from Lua is reflected immediately (verified 2026-10-08).
- Each section stores its own `State.CostPerCell` (set via `UCSection:SetCostPerCell`), so the new price applies to sections created after the write.
- Difficulty also has `ConveyorPricePercentFromDefault` (`FMainDifficultyGlobalDataCPP`, saved in `UEMSInfoSaveGame`); it is NOT folded into `GetCellCostBySectionType` (still 250 in a normal save). Not used by CheaperBelts.

## Pitfalls & Dead Ends
- Scaling the live values relative to the current ones compounds on a UE4SS hot reload (the subsystem keeps the old scaled values). CheaperBelts caches vanilla values with `ModRef:SetSharedVariable` (survives hot reloads, reset on game restart) and always writes `vanilla x multiplier`.
- Not verified yet: whether holo sections planned before the change get the new price (`UpdateHoloSectionCosts`), and whether the refund uses the stored `CostPerCell` or the current config.

## Direct Code / CLI Snippet
```lua
local S = FindFirstOf("ConveyorSubsystem")
local C = S.ConveyorConfig
C.BeltCellCost = 125.0
C.ConveyorUpgradeCosts[1] = 250.0
print(S:GetCellCostBySectionType(1), S:GetTierCost(1))  -- 125.0  250.0
```
