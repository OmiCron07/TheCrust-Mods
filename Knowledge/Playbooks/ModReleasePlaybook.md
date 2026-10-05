---
type: Playbook
title: Lua Mod Release Pipeline
description: How release zips are built and published (enabled.txt, game-root layout, GitHub Actions trigger rules).
tags: [playbook, release, ci, ue4ss, github]
status: stable
sources: []
---
## Goal
Ship Lua mods as zips that players extract into the game root folder, no manual mods.txt edit.

## Verified Facts
- Public repo: `https://github.com/OmiCron07/TheCrust-Mods`, default branch `main`.
- UE4SS v3 `start_mods()` part 2 (`UE4SS/src/UE4SSProgram.cpp`, tag v3.0.1) starts every mod folder containing `enabled.txt`, even when the mod is absent from mods.txt or listed with `: 0`. To disable such a mod, delete `enabled.txt`.
- Zip layout (root = game folder containing `TheCrust`): `INSTALL-<Mod>.txt` + Lua mod (`Scripts/main.lua`) at `TheCrust/Binaries/Win64/ue4ss/Mods/<Mod>/{enabled.txt,Scripts/*.lua}`, or game files mod (has a `TheCrust/` subfolder, e.g. `Mods/SkipIntro`) shipped as is. Mod `*.md` files are not shipped; INSTALL text = install steps + mod README.
- `Scripts/Build-ModRelease.ps1` auto-discovers every `Mods/*` folder except `DevBridge`; outputs `dist/TheCrust-<Mod>.zip` + `dist/TheCrust-AllMods.zip`. Uses `ZipFile.CreateFromDirectory` (forward-slash entries).
- `.github/workflows/release-mods.yml`: push to `main` with path filter `Mods/**` minus `Mods/**/*.md` and `Mods/DevBridge/**`, plus `workflow_dispatch`. Creates release `v<yyyy.MM.dd>-<run>` marked latest; README links use `releases/latest/download/<zip>`.

## Pitfalls & Dead Ends
- Changes to only the build script, workflow or docs do not trigger a release: run the workflow manually (`gh workflow run release-mods.yml`).
- SkipIntro overwrites only the 3 startup videos (story cinematics kept on purpose); no backup in zip form, Steam "Verify integrity of game files" restores them and also undoes the mod after game updates.
- Extracting an update overwrites `Scripts/config.lua`; Blueprints `library.lua` lives outside the zip and survives.

## Direct Code / CLI Snippet
```pwsh
.\Scripts\Build-ModRelease.ps1          # local build into dist/
gh workflow run release-mods.yml        # manual release
```
