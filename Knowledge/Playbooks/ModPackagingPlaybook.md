---
type: Playbook
title: Mod Packaging and Deployment Playbook
description: Step-by-step procedures to extract, modify, pack, and deploy .pak mods for The Crust.
tags: [playbook, pak, repak, workflow]
status: stable
sources: []
---
## Goal
Standardized procedure for creating and deploying asset replacement or addition mods via `.pak` packages.

## Verified Facts
- UE 4.27 scans `Content\Paks\~mods` alphabetically. Naming the mod `[ModName]_P.pak` ensures patch precedence over base assets.
- Mod folder staging must mimic the internal path: e.g. `<ModDir>\TheCrust\Content\...` or `<ModDir>\Content\...` depending on repak mount point.

## Standard Workflow

### 1. Extract Asset for Editing
```pwsh
.\Scripts\Extract-Game-Pak.ps1 -PakPath "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Paks\pakchunk1-WindowsNoEditor.pak" -OutputDir "K:\GameMods\TheCrust\Extracted\pakchunk1"
```

### 2. Inspect and Modify Assets
- Open `.uasset` / `.uexp` files with `Tools\UAssetGUI\UAssetGUI.exe` or `Tools\FModel\FModel.exe`.
- Export/modify JSON or texture/audio data.
- Save modified `.uasset` files into `Mods\<ModName>\Content\...`.

### 3. Pack Mod
```pwsh
.\Scripts\Pack-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\<ModName>" -OutputPakPath "K:\GameMods\TheCrust\Mods\<ModName>_P.pak"
```

### 4. Deploy Mod to Game
```pwsh
.\Scripts\Deploy-Pak-Mod.ps1 -ModPakPath "K:\GameMods\TheCrust\Mods\<ModName>_P.pak"
```
