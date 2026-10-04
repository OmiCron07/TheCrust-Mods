---
type: Playbook
title: UE4SS Setup and Script Modding Playbook
description: Guide for deploying UE4SS, enabling developer console, and writing Lua script mods for The Crust.
tags: [playbook, ue4ss, lua, scripting]
status: stable
sources: []
---
## Goal
Setup UE4SS runtime, activate runtime object inspection, and develop Lua script mods.

## Verified Facts
- UE4SS proxy `dwmapi.dll` loads `ue4ss\UE4SS.dll` in `TheCrust\Binaries\Win64`.
- Mods are loaded from `TheCrust\Binaries\Win64\ue4ss\Mods` based on `mods.txt`.

## Standard Procedures

### 1. Install UE4SS
```pwsh
.\Scripts\Setup-UE4SS.ps1
```

### 2. Verify Installation
- Launch The Crust from Steam.
- Press `F10` or `~` to verify developer console or UE4SS GUI (if enabled).
- Check `D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64\ue4ss\UE4SS.log` for successful hook initialization.

### 3. Deploy Lua Mod
- Create mod folder in `Mods\<ModName>\Scripts\main.lua`.
- Deploy to game:
```pwsh
.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\<ModName>"
```

### 4. Uninstall UE4SS
```pwsh
.\Scripts\Setup-UE4SS.ps1 -Uninstall
```
