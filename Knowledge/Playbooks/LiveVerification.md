---
type: Playbook
title: Live In-Game Verification (DevBridge, Screenshots, Input)
description: How an agent verifies changes in the running game - DevBridge Lua probes first, gfxcapture screenshots, guarded mouse/keyboard input last.
tags: [playbook, testing, verification, devbridge, capture, automation]
status: stable
sources:
  - id: universal-modder
    resource: https://github.com/rehan-remade/universal-modder
    title: universal-modder game-automation skill, um win shot and WinDrive.ps1 (MIT)
---
## Goal
Verify mod behavior in the running game with the cheapest reliable channel, without touching the user's builds or input.

## Verified Facts
- **Channel order**: 1) `Scripts/Invoke-DevBridge.ps1` (Lua on the game thread: state as text, direct actions) -> 2) `Scripts/Get-GameScreenshot.ps1` (visual check of UI/HUD/ghosts) -> 3) `Scripts/Invoke-WinDrive.ps1` (real clicks/keys, only for flows DevBridge cannot trigger, e.g. UI widgets, hotkeys, drag-select).
- **Screenshot**: ffmpeg 8 `gfxcapture` (Windows.Graphics.Capture) on `TheCrust-Win64-Shipping.exe`; output = client area in physical pixels into `Captures/` (gitignored). `-Scale 0.33` adds a `_small.png` for cheap review; multiply its coords by 3.
- **Coordinates**: WinDrive runs per-monitor DPI aware, so `click x y` uses the same pixel space as the full-size screenshot (client area, origin top-left).
- **WinDrive batch**: one call = one batch, one `<cmd> -> <reply>` line each, stops at the first `fail`/`error` (exit 1). Example: `.\Scripts\Invoke-WinDrive.ps1 "focus" "click 1280 720" "wait 300" "key 0x1B"`.
- **WinDrive guards** (audit of upstream `WinDrive.ps1` 2026-10-06; no network, file or process-memory access, pure user32 calls):
  - refuses input commands when the user touched mouse/keyboard < `-MinIdleSeconds` (default 5) ago;
  - aborts the batch when real user input appears between our injected events (GetLastInputInfo newer than our last injection + 250 ms);
  - sends input and moves the cursor only while the game is foreground (or nothing is and the cursor is over the game);
  - `focus` clicks the title bar, never the game client area; borderless window -> `fail` (ask the user to click the game).
- Upstream behaviors removed: unconditional Alt tap into the current foreground app, topmost + click at client top-center (could hit HUD), unguarded cursor moves, long-running stdin mode.
- Read-only commands (`rect`, `fg`, `idle`, `wait`, `size`) skip the idle gate.

## Pitfalls & Dead Ends
- gfxcapture cannot capture a minimized window; a covered window is fine.
- Windows Auto HDR washes out captures (script warns): `Settings > System > Display > Graphics > The Crust > Auto HDR`.
- `GetLastInputInfo` counts every input on the machine: if the user is at the PC the idle gate blocks; ask them to step away rather than lowering `-MinIdleSeconds`.
- Live tests run in the user's real save: map the area and fence a scratch rectangle before destructive actions (a scratch `clear()` once wiped user pastes).
- Never deploy the Blueprints Lua mod while the game runs: UE4SS hot reload usually crashes it. Read-only DevBridge probes are fine.

## Direct Code / CLI Snippet
```pwsh
.\Scripts\Invoke-DevBridge.ps1 -Code 'out(FindFirstOf("GodPawn_C"):GetFullName())'
.\Scripts\Get-GameScreenshot.ps1 -Scale 0.33
.\Scripts\Invoke-WinDrive.ps1 "rect" "idle"
.\Scripts\Invoke-WinDrive.ps1 "focus" "click 1280 720" "wait 300" "key 0x1B"
```
