---
type: Research
title: Windows Clipboard Access from UE4SS Lua
description: The game's UUIFunctionLib exposes CopyToClipboard / PasteFromClipboard, callable from Lua through the class default object; no io.popen needed.
tags: [research, ue4ss, lua, clipboard, ui]
status: stable
sources: []
---
## Goal
Read / write the Windows clipboard from a Lua mod without spawning a process.

## Verified Facts
- Header dump `Extracted/CXXHeaderDump/TheCrust.hpp`: `class UUIFunctionLib : public UBlueprintFunctionLibrary` has `void CopyToClipboard(FString Text)` and `FString PasteFromClipboard()` (game C++ module `/Script/TheCrust`).
- Static Blueprint library functions are called on the class default object: `StaticFindObject("/Script/TheCrust.Default__UIFunctionLib")`.
- Verified in game 2026-10-20 (UE4SS v3.0.1 Beta c2ac2464): Default object valid; `PasteFromClipboard()` returns an FString userdata -> `:ToString()`; `CopyToClipboard` + `PasteFromClipboard` round-trips 10 006 ASCII chars exactly; no console flash, no lag.
- Used by Blueprints Share / Import (`Game.CopyToClipboard`, `Game.PasteFromClipboard` in `Mods/Blueprints/Scripts/game.lua`).

## Pitfalls & Dead Ends
- `io.popen("clip", "w")` from a GUI process spawns `cmd.exe` and may flash a console window: avoid.
- UE4 `FPlatformApplicationMisc::ClipboardCopy` is not Blueprint-exposed in 4.27; only the game's own wrapper is reachable.

## Direct Code / CLI Snippet
```lua
local Lib = StaticFindObject("/Script/TheCrust.Default__UIFunctionLib")
Lib:CopyToClipboard("TCBP1:...")
local Text = Lib:PasteFromClipboard()
Text = type(Text) == "string" and Text or Text:ToString()
```
