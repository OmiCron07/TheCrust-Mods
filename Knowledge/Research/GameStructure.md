---
type: Research
title: Game Structure & Pak Packages Analysis
description: Reverse-engineering analysis of The Crust binary layout, pak packages, and mount structures.
tags: [research, reverse-engineering, paks, ue4]
status: stable
sources: []
---
## Goal
Document the internal filesystem, binary targets, and package distribution of The Crust (Steam edition).

## Verified Facts
- **Binary Target**: `D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64\TheCrust-Win64-Shipping.exe`.
- **Target Engine**: Unreal Engine 4.27.2 (64-bit Windows).
- **Pak Files Breakdown** (`Content\Paks`):
  - `pakchunk0-WindowsNoEditor.pak` (~5.76 GB): Main game content (meshes, textures, blueprints, UI, animations).
  - `pakchunk0optional-WindowsNoEditor.pak` (~30 MB): Optional or localized game assets.
  - `pakchunk1-WindowsNoEditor.pak` (~19.5 MB): Audio assets (ambient, cinematics, sound effects, music).
- **Encryption**: No AES key required. Headers and index are unencrypted (`encrypted index: false`).
- **Pak File Format**:
  - Format Version: `V11` (Fnv64BugFix).
  - Mount Point: `../../../TheCrust/Content/`.
  - Compression: `Zlib`.
  - Path Hash Seed: `0x8402222B`.
- **Mod Directory**:
  - Unreal Engine automatically scans for `.pak` files inside `TheCrust\Content\Paks\~mods\`.
  - Files prefixed or suffixed with `_P` have higher load priority.

## Pitfalls & Dead Ends
- Attempting to load pak files without the `../../../TheCrust/Content/` mount point will cause asset resolution to fail silently in-game.

## Direct Code / CLI Snippet
```pwsh
# List assets from game pak chunk
& "K:\GameMods\TheCrust\Tools\repak\repak.exe" list "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Paks\pakchunk1-WindowsNoEditor.pak" | Select-Object -First 10
```
