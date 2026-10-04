---
type: Playbook
title: Intro and Startup Cinematics Management Playbook
description: Operational procedures to inspect, bypass, or restore intro movies and cutscenes in The Crust.
tags: [playbook, cinematics, bypass, automation]
status: stable
sources: []
---
## Goal
Provide repeatable procedures for disabling or restoring startup logos and narrative intro cinematics.

## Verified Facts
- Management script: `Scripts\Manage-IntroCinematics.ps1`.
- Target directory: `D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Movies`.
- Backups preserved in: `TheCrust\Content\Movies\_OriginalCinematicsBackup`.
- Dummy asset: `Assets\blank.mp4` (2.4 KB, 0.04s, H.264/AAC).

## Standard Procedures

### 1. Pre-Flight Check (Status)
```pwsh
powershell -File ".\Scripts\Manage-IntroCinematics.ps1" -Action Status
```

### 2. Disable All Intro Cinematics
Ensure `TheCrust` is closed before running:
```pwsh
powershell -File ".\Scripts\Manage-IntroCinematics.ps1" -Action Disable -Scope All
```

### 3. Disable Only Startup Logos
Keep story cutscenes intact while skipping boot logos:
```pwsh
powershell -File ".\Scripts\Manage-IntroCinematics.ps1" -Action Disable -Scope Startup
```

### 4. Restore Original Cinematics
Revert dummy videos back to original game videos:
```pwsh
powershell -File ".\Scripts\Manage-IntroCinematics.ps1" -Action Enable
```
