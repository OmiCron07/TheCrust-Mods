---
type: Architecture
title: Technology Stack & Runtime Constraints
description: Runtime environments, core frameworks, dependencies, and toolchain constraints for The Crust modding.
tags: [stack, architecture, runtime, ue4]
status: stable
sources: []
---
## Goal
Record runtime environments, core frameworks, toolchain dependencies, and engine constraints for The Crust modding.

## Verified Facts
- **Game Engine**: Unreal Engine 4.27.2 (`TheCrust-Win64-Shipping.exe`, file version `4.27.2.0`).
- **Install Path**: `D:\Games\Steam\steamapps\common\The Crust`.
- **Binaries Path**: `D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64`.
- **Paks Path**: `D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Paks`.
- **Pak Specification**:
  - Pak Version: `V11` (Fnv64BugFix).
  - Mount Point: `../../../TheCrust/Content/`.
  - Compression: `Zlib`.
  - Encryption: Disabled (`encrypted index: false`). No `.sig` or io-store (`.utoc`/`.ucas`).
- **Mod Loading Mechanisms**:
  - **Pak Mods**: `.pak` files in `TheCrust/Content/Paks/~mods/`.
  - **Scripting & Memory Hooking**: UE4SS v3.0.2 via `dwmapi.dll` proxy in `Binaries/Win64`.
- **Tooling Stack**:
  - `repak`: Rust CLI for fast unpacking & packing UE pak files.
  - `UAssetGUI`: Inspect & edit `.uasset`/`.uexp` data tables and blueprints in JSON/GUI.
  - `FModel`: Asset visualization and package extraction.
  - `UE4SS`: Lua scripting, blueprint mod loader, UObject inspector, and console enabler.

## Pitfalls & Dead Ends
- Mod pak files must use the exact mount point `../../../TheCrust/Content/` and version `V11`, otherwise UE 4.27 fails to mount internal file paths.
- Ensure mod `.pak` filenames end with `_P.pak` (e.g. `MyMod_P.pak`) to guarantee patch loading priority over base game paks.

## Direct Code / CLI Snippet
```pwsh
# Pack mod folder with repak
& "K:\GameMods\TheCrust\Tools\repak\repak.exe" pack "<ModSourceDir>" "<OutputPak>" --version V11 --compression Zlib --mount-point "../../../TheCrust/Content/"
```
