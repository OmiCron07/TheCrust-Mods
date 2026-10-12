---
type: Research
title: UE4SS Lua Out Parameter Tables Across Builds
description: Non-struct out params of a UFunction called from Lua land in different tables depending on the UE4SS build; pass the same table for every out param.
tags: [research, ue4ss, lua, out-params, compatibility, blueprints]
status: draft
sources:
  - id: issue-1
    resource: https://github.com/OmiCron07/TheCrust-Mods/issues/1
    title: "Blueprint: nothing happens when left mouse dragging after Select Area (user UE4SS.log)"
  - id: ue4ss-fix
    resource: https://github.com/UE4SS-RE/RE-UE4SS/commit/3a4b6422
    title: "fix(Lua): Non-struct/array out params corrupt following params (#1454)"
---
## Symptom
Blueprints mod on a user's UE4SS build `v3.0.1 Beta #0 - Git SHA #5e627997` (experimental, 2026-10-09): panel works, `Select area` and right click cancel work, left drag selects nothing, no error logged.

## Verified Facts
- Dev install runs `v3.0.1 Beta #0 - Git SHA #c2ac2464` (2026-07-04); the user's build is 155 commits ahead. Both print "v3.0.1 Beta" in `UE4SS.log`: compare the Git SHA, not the version string.
- Old builds (before `3a4b6422`): for a non-struct/array out param, the Lua table was left on the stack, so all following out params were written into the FIRST out table passed. Code like `PC:GetCellUnderCursor(11, false, Out, {}, {})` then reading `Out.Success` only worked thanks to this bug.
- From `3a4b6422` on: each out param is written into its own table (keyed by param name). `Success` lands in the third table, `Out.Success` is nil, `Game.CursorCell` returns nil, the drag anchor is never set.
- Struct out params (FVector, FHitResult, e.g. `GetActorBounds`, `GetGridLocationByCellID`) are not affected.

## Rule
Pass the same table for every out param of a call (`PC:GetCellUnderCursor(11, false, Out, Out, Out)`, `EM["Add Link"](EM, Link, false, Out, Out)`): works with both behaviors.
