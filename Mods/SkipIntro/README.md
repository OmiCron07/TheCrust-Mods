# SkipIntro Mod for The Crust

## Overview
Skips the startup videos so the game reaches the main menu faster. The story cinematics of a new
campaign are kept.

The game plays loose video files from `TheCrust\Content\Movies` through custom UMG state machines, so
the `-nomovies` launch option has no effect. This mod replaces the startup videos with a valid 0.04 s
blank MP4 (deleting them or using empty files makes the media player hang).

## Replaced files (`TheCrust\Content\Movies`)
| File | Original content |
|------|------------------|
| `UE_moving_logo_v01_1080.mp4` | Unreal Engine logo |
| `LogoRevealCut.mp4` | Publisher and developer logos |
| `The_crust_short_V3.mp4` | Animated title reveal |

Not replaced: `FINALCutwithSFX.mp4` and `FallingAstronaut.mp4` (campaign intro cinematics).

## Installation
Download `TheCrust-SkipIntro.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`), overwriting the files. No UE4SS needed. A game update or a
Steam file verification restores the original videos: extract the zip again afterwards.

## Uninstall
`Steam > Library > The Crust > right click > Properties > Installed Files > Verify integrity of game files`.

## Development
`Scripts\Manage-IntroCinematics.ps1` does the same from the repo with a backup of the original videos
(`-Action Disable -Scope Startup`, `-Action Enable` to restore, `-Action Status`).
