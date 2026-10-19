---
type: Research
title: Windows Clipboard Access from UE4SS Lua
description: The game's UUIFunctionLib exposes CopyToClipboard / PasteFromClipboard, callable from Lua through the class default object; no io.popen needed.
tags: [research, ue4ss, lua, clipboard, ui]
status: draft
sources: []
---
## Goal
Read / write the Windows clipboard from a Lua mod without spawning a process.

## Verified Facts
- Header dump `Extracted/CXXHeaderDump/TheCrust.hpp`: `class UUIFunctionLib : public UBlueprintFunctionLibrary` has `void CopyToClipboard(FString Text)` and `FString PasteFromClipboard()` (game C++ module `/Script/TheCrust`).
- Static Blueprint library functions are called on the class default object: `StaticFindObject("/Script/TheCrust.Default__UIFunctionLib")`.
- Not yet verified in game: exact return type marshalling of `PasteFromClipboard` (FString userdata needing `:ToString()` or plain Lua string) and large text (> 10 KB).

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
