# Blueprints Mod for The Crust

Select an area of your base, copy, move (cut) or delete it, or save it as a reusable blueprint.
Pasting places **vanilla ghosts**: modules in planning mode (with their rotation, mirroring and
production scheme), holo conveyor belts, distributors, underground belts and the electric wires
between pasted modules. Build them afterwards with the normal game buttons, or all at once from the
panel.

![Blueprints panel, annotated](https://github.com/OmiCron07/TheCrust-Mods/raw/main/Docs/Images/blueprints-panel.png)

Press `K` in game to open the panel. The main actions also have hotkeys (see [Controls](#controls)),
so the panel can stay closed.

## Quick start
Blueprints work on the **Underground** and **Crater** layers (not on the orbital view). Selections and
pastes are cancelled when you switch layer.

### Copy and paste an area
1. Click **Select area** ② (or press `Ctrl+K`), then press and drag the left mouse button over the
   modules and belts to copy. A highlight shows the captured elements and **Selection info** ⑦ counts
   them.
2. Click **Copy + paste** ③ (`Ctrl+Shift+K`). A preview follows the cursor (see
   [Paste preview](#paste-preview)).
3. Rotate with `R` / `Shift+R`, mirror with `T`, then left click to place the ghosts. You stay in
   paste mode: keep clicking to place more copies.
4. Right click to stop pasting. **Paste clipboard** ④ (`Alt+K`) pastes the same thing again later.
   **Copy** (`Ctrl+Insert`) only puts the selection in the clipboard, without starting a paste.

### Move or delete an area
1. Select an area as above.
2. **Cut** (`Shift+Delete`, right of **Build selection**) deletes the selection and starts pasting
   it: place it elsewhere, then right click to stop. The cut elements stay in the clipboard (`Alt+K`).
3. **Delete** (`Delete`, right of **Cut**) deletes the selection. The button asks for a second click
   (**Confirm?**); the `Delete` key deletes right away.

Both use the vanilla demolition tool: planned ghosts and holo belts vanish, built belts are removed
and refunded like with the vanilla tool, built modules get the vanilla dismantle order (robots take
them down, so their cells stay taken until then). Nothing outside the selection is removed: built
belts are cut exactly at the selection edge, but holo belts only go away by vanilla chunks of 4-5
cells, so a holo chunk (or an underground pair) crossing the edge is kept. The status line counts the
kept cells.

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
| | Copy | `Ctrl+Insert` | Copies the selection to the clipboard without pasting (button left of **Copy + paste**). |
| 3 | Copy + paste | `Ctrl+Shift+K` | Copies the selection to the clipboard and starts pasting it. |
| 4 | Paste clipboard | `Alt+K` | Pastes the clipboard again: the last copied or cut selection, or the last placed blueprint. |
| 5 | Paste as: Plan / Build | `Ctrl+Alt+K` | Switches the paste mode between planning ghosts and direct construction. |
| 6 | Build selection | `Shift+K` | Starts construction of the planned modules and holo belts inside the selection. |
| | Cut | `Shift+Delete` | Deletes the selection and starts pasting it; it also becomes the clipboard (button right of **Build selection**). |
| | Delete | `Delete` | Deletes the selection (planned ghosts, belts, dismantle order on built modules); the first click turns the button into **Confirm?** (the key deletes right away). |
| 7 | Selection info | | Modules, belt cells, distributors, underground belts and wires captured by the current selection. |
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
| `Ctrl+Insert` | Copy the selection to the clipboard |
| `Ctrl+Shift+K` | Copy the selection and start pasting it |
| `Shift+Delete` | Cut: delete the selection and start pasting it |
| `Delete` | Delete the selection (vanilla demolition, no confirmation) |
| `Alt+K` | Paste the clipboard again |
| `Shift+K` | Start construction of the planned modules and holo belts in the selection |
| `Ctrl+Alt+K` | Switch pasting between planning ghosts and direct construction |
| `R` / `Shift+R` | While pasting: rotate clockwise / counter clockwise |
| `T` | While pasting: mirror the blueprint (like vanilla module mirroring; combine with `R` for any orientation) |
| Left click | While selecting: drag the area. While pasting: place the ghosts (stay in paste mode) |
| Right click | Cancel / clear the selection, stop pasting |

### Paste preview
- Every module and belt is shown as its vanilla blue hologram, like in the building mode.
- Cyan outline: the module can be placed there; red outline: it cannot (overlap, undug ground,
  or the module's own rule).
- Extractors: their active cells are shown as small squares, green on an ore vein, red elsewhere;
  the outline turns cyan once enough cells cover a vein (vanilla rule).
- Belt cells already used are skipped when pasting.
- A blueprint made on the other layer can still be pasted; the status line mentions it.

### Paste modes
- **Plan** (default, `PasteAsConstruction = false`): vanilla planning ghosts, built later with the
  play button of each module, or all at once with **Build selection** / `Shift+K`.
- **Build**: construction starts right away. Modules over the supply limit stay planned; belt
  sections are paid in credits like the vanilla build and stay holo when credits are missing.

## What is copied
- Modules with rotation, mirroring and production scheme.
- Module IO cell settings: IO swaps, output filters, output lock, overflow.
- Conveyor belts (straight lines and turns), on built or holo sections, pasted as planning ghosts
  (vanilla belt plan mode) whatever the current belt mode.
- Underground belts, with their connections to belts, distributors and other underground belts.
  A pair cut by the selection is not copied.
- Distributors (splitters / mergers), recreated from the belts joining them, with all their
  settings: allowed resources, priority, hand-tuned, blocked and locked flags and priority level of
  each output, priority level of each input. Settings follow the rotation and mirroring of the paste.
- Electric wires whose two ends are both copied modules.

The paste status reports settings that could not be applied (`N settings not applied`).

Mirroring flips the whole blueprint like vanilla `T` flips a module: each module is mirrored too.
Modules the game never mirrors (storages) keep their shape; their IO settings follow the mirrored
belts.

## Limitations
- Not copied: storage limits, belt tiers (belts are pasted at the base tier), gas pipes, roads,
  wires to modules outside the selection, and modules the vanilla copy rule refuses (not built by
  the player, or still locked).
- Underground belt pairs cut by the selection are not copied (the selection info counts them).
- Blueprints saved before distributor, IO settings or underground belt support do not contain them:
  capture the area again to include them.
- After a **Cut** of built modules, their cells stay taken until the robots finish dismantling
  them: a paste over the old place shows red outlines until then.

## Configuration (`Scripts/config.lua`)
- `Keys`: hotkeys (avoid keys the game binds, e.g. A/B/C/D/E/F/G/H/J/L/M/N/P/Q/R/S/T/U/V/W/X/Y/Z;
  `Insert` and `Delete` are free and named `INS` / `DEL`).
- `PasteConveyors` / `PasteElectricLinks`: toggle belt and wire pasting.
- `PasteAsConstruction`: default paste mode (`false` = Plan, `true` = Build).
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
