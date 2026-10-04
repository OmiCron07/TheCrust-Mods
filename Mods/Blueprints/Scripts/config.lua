-- Configuration for the Blueprints mod.
-- Key names come from UE4SS `Key` (e.g. "K", "B", "F7") and modifiers from `ModifierKey` ("CONTROL", "SHIFT", "ALT").
-- Vanilla bindings to avoid: B/H/U/J/P/M/V/R/T/C/Z/N/Y/G/F/L/E/Q/X, Tab, Ctrl+C, Ctrl+V, Ctrl+F.
local Config = {
    Keys = {
        -- Open / close the blueprint manager panel.
        TogglePanel = { Key = "K", Modifiers = {} },
        -- Start an area selection: then drag with the left mouse button over the elements.
        SelectArea = { Key = "B", Modifiers = { "CONTROL" } },
        -- Copy the current selection to the clipboard and start pasting it.
        CopySelection = { Key = "C", Modifiers = { "CONTROL", "SHIFT" } },
        -- Paste the clipboard (last copied selection or last placed blueprint).
        PasteClipboard = { Key = "V", Modifiers = { "CONTROL", "SHIFT" } },
        -- While pasting: rotate clockwise / counter clockwise (same keys as vanilla module rotation).
        RotateClockwise = { Key = "R", Modifiers = {} },
        RotateCounterClockwise = { Key = "R", Modifiers = { "SHIFT" } },
    },

    -- While pasting: left click places the ghosts, right click cancels.
    -- While selecting: right click cancels.

    -- Paste conveyor belts as holo (unbuilt) sections. Build them with the vanilla "build" button.
    PasteConveyors = true,

    -- Recreate electric wires between pasted modules (vanilla wire cost may apply).
    PasteElectricLinks = true,

    -- Panel offset on screen (pixels from the top-right corner).
    PanelPosition = { X = 24, Y = 120 },

    -- Enable debug log output in the UE4SS console / log file.
    DebugLogging = false,
}

return Config
