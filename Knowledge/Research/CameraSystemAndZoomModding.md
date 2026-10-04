---
type: Research
title: Camera System & Zoom to Cursor Modding
description: Architecture of The Crust's GodPawn camera system, zoom mechanics, and mathematical cursor-tracking implementation.
tags: [camera, zoom, godpawn, ue4ss, input]
status: stable
sources:
  - id: game-pak-core
    resource: pakchunk0-WindowsNoEditor.pak
    title: TheCrust Content Blueprints Core
stale_after: 2027-01-01
---
## Goal
Document the camera controller architecture in The Crust and the implementation of zoom-to-cursor mechanics.

## Verified Facts
- The main gameplay camera is controlled by `GodPawn_C` (`/Game/Blueprints/Core/GodPawn.uasset`), subclass of `APawn`.
- Components hierarchy: Root -> `LongArm` (`SpringArmComponent`, default length ~3000-10000) -> `StrategyCamera` (`CameraComponent`).
- Mouse wheel zoom input triggers axis event: `/Game/Blueprints/Core/GodPawn.GodPawn_C:InpAxisEvt_Zoom_K2Node_InputAxisEvent_0(AxisValue)`.
- Default zoom behaviour modifies only `Target for Target Arm Length` using `Zoom Step` (-500.0) without shifting actor location, focusing zoom strictly on screen center.
- Cursor world ground position is queryable via `APlayerController:GetHitResultUnderCursorByChannel(11, true, HitResult)` with fallback to `DeprojectMousePositionToWorld` intersected with the horizontal plane $Z = \text{PawnLoc.Z}$.
- Proportional focal shift equation to keep world point $M$ stationary under cursor during zoom:
  $\Delta P = (M - P) \times \left(1 - \frac{L_{new}}{L_{old}}\right)$ where $L_{old}$ is current target arm length and $L_{new}$ is arm length post-step.
- Map limits (`CraterCenterOffset`, `CraterRadius`) in `GodPawn_C` can bound camera displacement to prevent out-of-bounds drift.

## Pitfalls & Dead Ends
- Modifying bytecode directly in cooked `GodPawn.uasset` risks struct offset corruption and engine desync; UE4SS UFunction hooking provides safe, non-destructive execution.
- UE4SS `UE4SS-settings.ini` defaulted to `MajorVersion = 5` and `MinorVersion = 6` in some templates; must be explicitly configured to `MajorVersion = 4` and `MinorVersion = 27` for The Crust (UE 4.27.2) to avoid crash on startup.
- Unreal `InputAxis` events execute every frame with `AxisValue = 0.0` when idle; hook callbacks must immediately return when `math.abs(AxisValue) < 0.001`.

## Direct Code / CLI Snippet
```lua
-- Hook GodPawn zoom event in UE4SS
RegisterHook("/Game/Blueprints/Core/GodPawn.GodPawn_C:InpAxisEvt_Zoom_K2Node_InputAxisEvent_0", function(self, AxisValue)
    local Axis = AxisValue:get()
    if not Axis or math.abs(Axis) < 0.001 then return end
    -- Compute cursor world location and shift GodPawn actor position
end)
```
