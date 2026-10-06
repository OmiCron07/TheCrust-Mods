---
type: Architecture
title: Project Topology & Directory Map
description: Navigational map of project directories, module boundaries, toolchain, and entry points.
tags: [architecture, map, layout]
status: stable
sources: []
---
## Goal
Provide navigational map of TheCrust modding directories and component boundaries.

## Verified Facts
- `Tools/`: Local standalone modding utilities.
  - `Tools/repak/`: Pak packing and unpacking CLI (`repak.exe`).
  - `Tools/UAssetGUI/`: Unreal asset viewer & JSON editor (`UAssetGUI.exe`).
  - `Tools/FModel/`: Unreal package extractor and visualizer (`FModel.exe`).
  - `Tools/UE4SS/`: Scripting system release archive and runtime assets (`dwmapi.dll`, `ue4ss/`).
- `Scripts/`: Automation scripts for packing, deploying, and installing mods.
  - `Scripts/Pack-Mod.ps1`: Builds `.pak` files using repak with UE 4.27 parameters.
  - `Scripts/Deploy-Pak-Mod.ps1`: Deploys pak files to game `~mods` directory.
  - `Scripts/Setup-UE4SS.ps1`: Installs or uninstalls UE4SS in game Win64 directory.
  - `Scripts/Deploy-Lua-Mod.ps1`: Deploys Lua scripts to UE4SS mods directory.
  - `Scripts/Extract-Game-Pak.ps1`: Unpacks game `.pak` files for inspection.
  - `Scripts/Invoke-DevBridge.ps1`: Runs Lua in the live game through the DevBridge mod.
  - `Scripts/Get-GameScreenshot.ps1`: GPU-safe game window capture into `Captures/` (gitignored).
  - `Scripts/Invoke-WinDrive.ps1`: Guarded mouse/keyboard batches to the game window (see `Playbooks/LiveVerification.md`).
- `Mods/`: Staging directory for developing custom mods (Pak mods, Lua scripts).
- `Knowledge/`: Self-improving OKF knowledge base.
- `AGENTS.md`: Root micro-router for agent orientation.

## Pitfalls & Dead Ends
- Never load the entire Knowledge/ folder into LLM context; load single cards on demand.
- Keep raw unpacked assets in `Extracted/` (gitignored) rather than committing large assets into git.
