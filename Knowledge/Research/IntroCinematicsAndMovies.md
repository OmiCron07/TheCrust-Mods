---
type: Research
title: Intro Cinematics and Movie Playback Architecture
description: Reverse engineering of startup logos, narrative cutscenes, and WmfMedia playback mechanisms in The Crust.
tags: [research, movies, cinematics, media-framework, ue4]
status: stable
sources: []
---
## Goal
Document movie playback systems, file targets, and bypass mechanisms for intro cinematics in The Crust.

## Verified Facts
- **Media Delivery Architecture**: The Crust uses loose video files located in `TheCrust\Content\Movies` rather than packing MP4s inside `.pak` archives.
- **Media Asset References**: Pak files contain `UFileMediaSource` assets (`TheCrust/Content/Movies/MediaSources/...`) referencing disk paths using relative notation `./Movies/<FileName>.mp4`.
- **Startup Movie Pipeline**:
  - `UE_moving_logo_v01_1080.mp4` (2.09 MB): Engine splash.
  - `LogoRevealCut.mp4` (81.43 MB): Publisher & developer logos (Crytivo & Veom Studios), played by `QSM_StartVideo` in `MainMenuLevel`.
  - `The_crust_short_V3.mp4` (41.88 MB): Animated logo / title reveal, played by `QSM_StartVideoExplosion`.
- **Narrative Story Cutscenes**:
  - `FINALCutwithSFX.mp4` (370.55 MB, 1m56s): Campaign intro radio narrative, referenced by `The_Crust_v3_radiotalking3_2k.uasset`.
  - `FallingAstronaut.mp4` (204.63 MB, 30s): Cosmonaut intro cutscene, referenced by `FallingCosmonaut.uasset`.
- **Engine Skip Limitations**: Unreal Engine `-nomovies` parameter fails because playback is handled by custom UMG state machines (`QSM_StartVideo`, `S_StartBakedCinematic`) via `UMediaPlayer`, not UE4's native `MoviePlayer`.
- **Safe Bypass Mechanism**: Replacing files with a 1-frame (0.04s) valid H.264/AAC MP4 container bypasses playback delays without triggering `OnMediaOpenFailed` or crashing Slate/WmfMedia.

## Pitfalls & Dead Ends
- Deleting files or using 0-byte files causes `WmfMedia` open failures which may hang state machines waiting for `OnEndReached`.
- Replacing files while the game process (`TheCrust-Win64-Shipping.exe`) is running causes `IOException: Sharing violation` because the media player locks active playback handles.

## Direct Code / CLI Snippet
```pwsh
# Check cinematics status
powershell -File "K:\GameMods\TheCrust\Scripts\Manage-IntroCinematics.ps1" -Action Status

# Replace intros with 0.04s dummy
powershell -File "K:\GameMods\TheCrust\Scripts\Manage-IntroCinematics.ps1" -Action Disable -Scope All
```
