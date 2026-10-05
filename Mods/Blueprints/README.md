# Blueprints Mod for The Crust

Select an area of your base, copy/paste it or save it as a reusable blueprint. Pasting places
**vanilla ghosts**: modules in planning mode (with their rotation, mirroring and production scheme),
holo conveyor belts and the electric wires between pasted modules. Build them afterwards with the
normal game buttons, or all at once from the panel.

![Blueprints panel, annotated](https://github.com/OmiCron07/TheCrust-Mods/raw/main/Docs/Images/blueprints-panel.png)

Press `K` in game to open the panel. Every button also has a hotkey, so the panel can stay closed.

## Quick start
Blueprints work on the **Underground** and **Crater** layers (not on the orbital view). Selections and
pastes are cancelled when you switch layer.

### Copy and paste an area
1. Click **Select area** ② (or press `Ctrl+K`), then press and drag the left mouse button over the
   modules and belts to copy. A highlight shows the captured elements and **Selection info** ⑦ counts
   them.
2. Click **Copy + paste** ③ (`Ctrl+Shift+K`). A preview follows the cursor (see
   [Paste preview](#paste-preview)).
3. Rotate with `R` / `Shift+R`, then left click to place the ghosts. You stay in paste mode: keep
   clicking to place more copies.
4. Right click to stop pasting. **Paste clipboard** ④ (`Alt+K`) pastes the same thing again later.

### Save and reuse a blueprint
1. Select an area as above.
2. Type a name in the name box ⑧ and click **Save selection** (an empty name gives `Blueprint N`).
   The blueprint appears at the top of the **Library**.
3. Later, click **Place** ⑨ next to it to paste it, exactly like a copy.
4. To rename: type the new name in the name box, then click **Rename** ⑩. To delete: click
   **Delete** ⑪, then **Confirm?** on the same button.

### Build the ghosts
- One by one: the vanilla play button of each planned module.
- All at once: select the area of the ghosts, then click **Build selection** ⑥ (`Shift+K`). This
  starts construction of the planned modules and holo belts inside the selection.
- Or paste directly as construction: switch **Paste as** ⑤ to **Build** (`Ctrl+Alt+K`), see
  [Paste modes](#paste-modes).

## The panel
| # | Element | Hotkey | What it does |
|---|---------|--------|--------------|
| 1 | Status line | | Result of the last action and what to do next (e.g. "Drag with the left mouse button over the area"). |
| 2 | Select area | `Ctrl+K` | Starts an area selection: press and drag the left mouse button. Right click cancels or clears the selection. |
| 3 | Copy + paste | `Ctrl+Shift+K` | Copies the selection to the clipboard and starts pasting it. |
| 4 | Paste clipboard | `Alt+K` | Pastes the clipboard again: the last copied selection or the last placed blueprint. |
| 5 | Paste as: Plan / Build | `Ctrl+Alt+K` | Switches the paste mode between planning ghosts and direct construction. |
| 6 | Build selection | `Shift+K` | Starts construction of the planned modules and holo belts inside the selection. |
| 7 | Selection info | | Modules, belt cells and wires captured by the current selection. |
| 8 | Name box + Save selection | | Saves the selection to the library under that name. The name box is also used by **Rename**. |
| 9 | Place | | Starts pasting that blueprint; it also becomes the clipboard. |
| 10 | Rename | | Renames that blueprint with the text of the name box. |
| 11 | Delete | | Deletes that blueprint; the first click turns the button into **Confirm?**. |
| 12 | Pages | | 8 blueprints per page, newest first. |
| 13 | Keybinds | | Reminder of the hotkeys, as configured in `Scripts/config.lua`. |

## Controls
| Key | Action |
|-----|--------|
| `K` | Open / close the blueprint manager panel |
| `Ctrl+K` | Select an area, then drag with the left mouse button |
| `Ctrl+Shift+K` | Copy the selection and start pasting it |
| `Alt+K` | Paste the clipboard again |
| `Shift+K` | Start construction of the planned modules and holo belts in the selection |
| `Ctrl+Alt+K` | Switch pasting between planning ghosts and direct construction |
| `R` / `Shift+R` | While pasting: rotate clockwise / counter clockwise |
| Left click | While selecting: drag the area. While pasting: place the ghosts (stay in paste mode) |
| Right click | Cancel / clear the selection, stop pasting |

### Paste preview
- Cyan outline: the module can be placed there; red outline: it cannot (overlap, undug ground,
  or the module's own rule).
- Extractors: their active cells are shown as small squares, green on an ore vein, red elsewhere;
  the outline turns cyan once enough cells cover a vein (vanilla rule).
- Orange strips: conveyor belts (cells already used are skipped when pasting).
- A blueprint made on the other layer can still be pasted; the status line mentions it.

### Paste modes
- **Plan** (default, `PasteAsConstruction = false`): vanilla planning ghosts, built later with the
  play button of each module, or all at once with **Build selection** / `Shift+K`.
- **Build**: construction starts right away. Modules over the supply limit stay planned; belt
  sections are paid in credits like the vanilla build and stay holo when credits are missing.

## What is copied
- Modules with rotation, mirroring and production scheme.
- Module IO cell settings: IO swaps, output filters, output lock, overflow.
- Conveyor belts (straight lines and turns), on built or holo sections.
- Distributors (splitters / mergers), recreated from the belts joining them, with all their
  settings: allowed resources, priority, hand-tuned, blocked and locked flags and priority level of
  each output, priority level of each input. Settings follow the rotation of the paste.
- Electric wires whose two ends are both copied modules.

The paste status reports settings that could not be applied (`N settings not applied`).

Not supported yet: underground belts, storage limits. Blueprints saved before distributor and
settings support must be captured again to include them.

## Configuration (`Scripts/config.lua`)
- `Keys`: hotkeys (avoid letters the game binds: B/C/E/F/G/H/J/L/M/N/P/Q/R/T/U/V/X/Y/Z).
- `PasteConveyors` / `PasteElectricLinks`: toggle belt and wire pasting.
- `PanelPosition`: panel offset from the top-right corner.
- `DebugLogging`: log per-module paste errors to the UE4SS log.

The library is stored in `library.lua` next to the `Scripts` folder. Back it up to keep or share
your blueprints.

## Installation
Download `TheCrust-Blueprints.zip` from the latest GitHub release and extract it into the game root
folder (the one containing `TheCrust`). Updating keeps the library (`library.lua` is not in the zip)
but overwrites `Scripts/config.lua`.

## Development
- Deploy from the repo: `.\Scripts\Deploy-Lua-Mod.ps1 -ModSourceDir "<repo>\Mods\Blueprints"`.
- `Scripts/selftest.lua`: pure checks (grid math, belt decomposition, serialization), runnable with any Lua 5.4.
- Research notes: `Knowledge/Research/BuildingSystemAndBlueprints.md`.
