# Plan: Blueprint share strings (export / import in `Mods/Blueprints/`)

Status: planned, not started. The blueprint library is already global (`library.lua` in the mod folder, not per save); this adds sharing between players through a copy-pasteable string.

## Goal (v1)
- **Share** on a library row puts a `TCBP1:...` string on the Windows clipboard.
- Pasting that string in the name box and clicking **Import** adds the blueprint at the top of the library.
- Strings come from strangers (Discord, Reddit): decoding must never execute code, freeze, or crash the game.
- Most blueprints fit one Discord message (2000 chars).

Naming: the mod already has an internal "clipboard" (`State.Clipboard`, Paste clipboard button). UI text and notifications say "Windows clipboard" for the system one.

## Size measurements (2026-10-19, the 7 blueprints of the live `library.lua`)
| Blueprint | Modules | Belt cells | base64 of library literal | Positional payload | + fixed-Huffman deflate, base64 |
|---|---|---|---|---|---|
| Small Bulks | 4 | 12 | 2 888 | 436 | 232 |
| Large Bulks | 4 | 12 | 3 420 | 523 | 272 |
| Smelters | 7 | 54 | 6 016 | 1 206 | 604 |
| All Large Bulks | 32 | 96 | 28 652 | 4 219 | 700 |
| Fuel Factory | 8 | 137 | 8 800 | 2 059 | 996 |
| Smelters x16 | 27 | 236 | 21 848 | 3 861 | 1 264 |
| Multi-Regolith Processing | 27 | 468 | 35 864 | 8 897 | 2 388 |

Conclusions:
- base64 of the library literal (old plan) is 3-36 KB: unusable. Field names, full class paths and per-module `Cells` dominate.
- Positional payload + footprint dedup + belt letters cuts 5-7x; deflate cuts another 2-6x. 6 / 7 fit 2000 chars; the largest (2388) goes as Discord `message.txt` or Nitro.
- Dynamic Huffman (zlib -9) only gains ~15 % over fixed Huffman: not worth the extra code in v1.
- Verified on the data: module `Cells` relative to (`DR`, `DC`) are identical for every module with the same (`Class`, `Turns`, `Mirrored`) (12 keys, 0 conflicts).
- Verified: in belt paths the next cell is the step of the current cell's `dir` for 685 / 688 pairs; the 3 others are corner cells whose `dir` differs from the move. The encoding must keep both.

Measurement scripts were throwaway (Python, session scratchpad); re-measure in `selftest.lua` (step 6).

## Format `TCBP1`
`TCBP1:` + base64url (RFC 4648 `A-Z a-z 0-9 - _`, no padding) of raw DEFLATE (RFC 1951) of a minified Lua literal payload. The prefix versions the format. base64url has no `+ / =`, so the string survives URLs and file names; `_` can still trigger Discord italics, so the README tells users to paste it in a code block.

Payload (positional arrays, no field names):
```
{ Name, Layer, Classes, Modules, Belts, Undergrounds, Links, Distributors }
Classes      = { "05_Storage/BigBulkStorage/MB_BigBulkStorage", ... }
               -- path after /Game/Blueprints/Modules/Category/ without the .X_C suffix;
               -- rebuilt as "/Game/Blueprints/Modules/Category/" .. P .. "." .. Leaf .. "_C"
Module       = { ClassIndex, DR, DC, Turns, Mirrored (0/1), Recipe, Cells, IO }
               -- Cells = flat { dr, dc, dr, dc, ... }, or 0 = translate the Cells of the first
               --   earlier module with the same (Class, Turns, Mirrored) by (DR, DC) delta
               -- IO = list of { Agency, Bits (Lock | Overflow << 1), Filter } or 0 (= false entry)
Belt path    = { R, C, Letters }
               -- one letter per cell: string.char(97 + Dir * 4 + Move), "a".."p";
               -- Move = direction to the next cell (last cell: Move = Dir)
Underground  = { R1, C1, R2, C2, Dir }
Links        = flat { A, B, A, B, ... }
Distributor  = { DR, DC, Outputs, Inputs }
               -- Output = { Dir, Level, Bits (Blocked | HandTuned << 1 | Locked << 2 | Priority << 3), Types }
               -- Input  = { Dir, Level }
```
Dropped on export, rebuilt on import: `Summary` (`Capture.Summary`), `Created` (import time), `Skipped` (0). The mapping is lossless for everything `Placer` / `Preview` / `Settings` read: the round-trip test compares the decoded blueprint with the original minus those three fields.

## Code layout
- `Scripts/deflate.lua` (new, pure, ~150 lines): `Deflate.Compress(Str)` = LZ77 (hash chains, window 32 KB, lazy match optional) + fixed Huffman codes (BTYPE 01); `Deflate.Inflate(Str, MaxOut)` = stored (00) and fixed (01) blocks only, BTYPE 10 / 11 rejected. Lua 5.4 integer bit ops.
- `Scripts/share.lua` (new, pure): base64url, `Share.ToPayload(BP)` / `Share.FromPayload(T)`, safe literal reader, schema validation, `Share.Encode(BP) -> Str` and `Share.Decode(Str) -> BP | nil, Err`. No UE4SS calls: testable outside the game.
- `Scripts/storage.lua`: `Storage.Serialize(V, Indent, Compact)`: `Compact` = no newline / indent / space. Nothing else changes (the local `library.lua` stays trusted and keeps using `load`).
- `Scripts/ui.lua`: Share button per row, Import button, `UI.SelectName()` helper if the export fallback is kept.
- `Scripts/main.lua`: `Share` and `Import` actions in `HandleAction`.
- `Scripts/selftest.lua`: new checks (step 6).

## Steps
0. **DevBridge probe** (`Scripts/Invoke-DevBridge.ps1`, read-mostly, no deploy):
   - NameBox accepts Ctrl+V of a 2.5 KB and a 10 KB ASCII string; `UI.GetName()` returns it intact (no truncation, no lag spike).
   - Windows clipboard export, keep the first that works without a visible console flash:
     - A: `io.popen("clip", "w")` write + close (ASCII only, so `clip` code page is irrelevant). Check `io.popen` exists in UE4SS Lua.
     - B: a UE4 clipboard function reachable from UE4SS (`FPlatformApplicationMisc::ClipboardCopy` is not Blueprint-exposed in 4.27; search the game's reflected functions for `Clipboard`).
     - C (fallback, pure UMG): put the string in NameBox, focus, select all; the user presses Ctrl+C.
   - Record the result in `Knowledge/Research/BuildingSystemAndBlueprints.md` (or a new card), commit.
1. **`deflate.lua`**: compressor + inflater as above. Inflate hardening: `MaxOut` cap (256 KB) checked on every write, distance <= bytes written, code / length tables bounds-checked, bit reader errors on end of input, error on missing final block. Every error = `error("...")` caught by `pcall` in `Share.Decode`.
2. **`share.lua`**:
   - base64url encode / decode; decode rejects any char outside the alphabet and impossible lengths (len % 4 == 1).
   - **Safe literal reader** (recursive descent over the payload, never `load`): tables, `%q` strings, integers / decimals, `true` / `false`, implicit array entries only (payload has no keys). Caps: depth <= 6, total elements <= 50 000, string length <= 256. Anything else is an error. Removes the code-execution path by construction (the old plan's token blacklist on top of `load` was fragile: long strings, comments, escapes).
   - `ToPayload` / `FromPayload`: class table, footprint dedup, belt letters, bit fields.
   - **Schema validation** in `FromPayload` (shape before semantics, every failure = clear message):
     - `Name`: string, control chars stripped, trimmed, <= 64 chars, empty -> "Imported blueprint".
     - `Layer` in {0, 2}.
     - `Classes`: <= 64 entries, each matches `^%d%d_[%w_]+/[%w_]+/MB_[%w_]+$`.
     - Modules <= 500; `ClassIndex` in range; `DR` / `DC` numbers with `|x| <= 200` and `x * 2` integral; `Turns` 0-3; `Mirrored` 0/1; `Recipe` matches `^[%w_]*$`; `Cells` even length, <= 64 cells, ints `|x| <= 200`; a `0` Cells with no earlier same key = error.
     - Belts: <= 2000 paths, <= 10 000 cells total; letters `^[a-p]+$`; reconstructed cells within bounds.
     - Undergrounds, Links (indices <= `#Modules`, A ~= B), Distributors (dirs 0-3, levels small ints, `Types` / `Filter` lists of small non-negative ints, <= 32 each), IO `Agency` matches `^[%w_]*$`.
3. **Export**: **Share** button per library row (`Button("Share", "Share", i)`). `Share.Encode(BP)` -> Windows clipboard via the step 0 method -> `Notify("Share string copied to the Windows clipboard (N chars)")`, plus "(over 2000 chars: Discord sends it as a file)" when N > 2000.
4. **Import**: **Import** button on the name row, next to Save selection. `UI.GetName()`; no `TCBP1:` prefix -> "Paste a TCBP1: share string in the name box first"; other `TCBP<n>:` -> "Made with a newer Blueprints version". In game, after `Share.Decode`: every class must resolve with `Game.LoadClass` and be a `ModuleBase` child, else reject naming the unknown classes (other game version / modded content). Duplicate name -> suffix ` (2)`, ` (3)`... Set `Summary`, `Created`, `Skipped = 0`, `table.insert(State.Library, 1, BP)`, `UI.SetName("")`, `SaveLibrary()`, `Notify("Imported 'X': <summary>")`. Imported `Layer` differs from the current one: import anyway (placement already checks the layer).
5. **UI fit**: row = Place / Replace / Rename / Delete / Share + label; check the panel width at 1080p in a screenshot, shorten labels if it overflows. Name row = box + Save selection + Import.
6. **`selftest.lua`** (runnable with any Lua 5.4, as today):
   - Deflate: round-trip of empty, 1 byte, 64 KB random, highly repetitive text; `Inflate` of a known zlib-produced fixed-Huffman stream (hard-coded bytes) to prove RFC compliance, not just self-consistency.
   - Share: round-trip of a hand-built blueprint covering every field (half-cell `DR`, mirrored, corner belt with Dir ~= Move, underground, distributor with non-default bits, IO `false` entry); equality = deep compare minus `Summary` / `Created` / `Skipped`.
   - Optional (when `library.lua` is reachable via an env var): round-trip and print the size of every blueprint of the real library; must match the table above within a few %.
   - Malicious inputs, each must return `nil, Err` quickly: truncated string, bad base64 char, inflate bomb (> 256 KB out), back-reference before start, BTYPE 10 / 11, payload `{(function() end)()}`, long string `[[...]]`, comment `--`, nesting depth 7, class `../../Engine/X`, `ClassIndex` 99, link to module 0, Turns 4, belt letter `q`, 70 KB string.
7. **Live verify** (`Knowledge/Playbooks/LiveVerification.md`), game closed for deploy (see memory: no deploy while the game runs): Share "Smelters" -> paste in Notepad (string present) -> paste back -> Import -> Place the copy next to the original in the scratch area -> same modules, belts, distributor settings, wires. Screenshot.
8. README (Share / Import section, size note, "strings are checked, never executed"), release zip (`Knowledge/Playbooks/ModReleasePlaybook.md`), commit.

## Out of v1
- Dynamic Huffman compression (~15 % smaller): only if many real blueprints exceed 2000 chars.
- Exporting the whole library / several blueprints in one string.
- Share via file (`shared/*.txt`): only if no clipboard method from step 0 works.
- Preview of an imported string before adding it to the library.

## Risks
- `io.popen` missing or flashing a console: fallback C costs the user one Ctrl+C.
- Game updates that move or rename module classes break old strings: import rejects with the class name instead of placing garbage.
- Deflate bugs corrupt silently: the hard-coded zlib vector in step 6 catches encoder / decoder mismatches with the RFC; the round-trip test catches the rest.
