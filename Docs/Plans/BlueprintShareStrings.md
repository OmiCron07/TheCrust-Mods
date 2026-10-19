# Plan: Blueprint share strings (export / import in `Mods/Blueprints/`)

Status: not started. The blueprint library is already global (`library.lua` in the mod folder, not per save); this adds sharing between players.

## Format
`TCBP1:` + base64 of the compact Lua literal of one blueprint (`Name` kept, `Summary` recomputed on import). The prefix versions the format and identifies valid strings.

## Steps
0. **DevBridge probe**: does the panel `EditableTextBox` (NameBox) accept a Ctrl+V of ~10 KB? Clipboard export options:
   - A: put the string in NameBox, focus, select all, user presses Ctrl+C (pure UMG, no process).
   - B: `io.popen("clip", "w")` (one click, may flash a console). Keep A if B flashes.
1. **`storage.lua`**: compact mode for `Storage.Serialize` (no newlines / indent), plus `Encode(BP)` / `Decode(Str)` with a pure Lua base64 (~25 lines).
2. **Safe decode (trust boundary: strings come from strangers)**:
   - Current `Storage.Deserialize` uses an empty env (no globals) but `(function() while true do end end)()` would still freeze the game.
   - Before `load`: size cap, then a tokenizer that rejects, outside string literals, `(`, `:`, `..` and the keywords `function while repeat for goto local`.
   - Schema validation after load: `Class` matches `^/Game/[%w_/]+%.[%w_]+_C$` and the loaded class is a `ModuleBase` child; bounds on `DR` / `DC`; `Turns` and directions in 0-3; `Links` indices <= `#Modules`; array shapes; string length caps.
3. **Export**: a **Share** button per library row.
4. **Import**: user pastes the string in NameBox, clicks **Import**: decode, validate, insert at the top of the library, `SaveLibrary()`, `Notify` with the summary. Duplicate name -> suffix ` (2)`.
5. **Measure** encoded size of the blueprints in the current `library.lua` (Discord limit 2000 chars). If too big, a `TCBP2` format could encode belt paths as start cell + direction letters (~1 char per cell). Not in v1 unless the measure requires it.
6. **`selftest.lua`**: round-trip every library blueprint; reject malicious inputs (infinite loop, `Class` outside `/Game/`, truncated base64).
7. Check row width (5th button next to Place / Replace / Rename / Delete), README, release, commit.
