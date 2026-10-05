-- Configuration for ZoomToCursor mod
local Config = {
    -- Enable zooming towards mouse cursor for zoom in (scroll up)
    ZoomInToCursor = true,

    -- Enable zooming away from mouse cursor for zoom out (scroll down)
    -- Set to false so that zooming out always stays centered on screen center (vanilla)
    ZoomOutFromCursor = false,

    -- Multiplier for zoom shift intensity (1.0 = default; per-notch shift is capped at 90% of the cursor distance)
    ZoomStrengthMultiplier = 1.0,

    -- Maximum zoom-out camera distance for Underground layer
    -- Vanilla default: 4200.0 (Surface is 25000.0)
    -- Increase to 10000.0 or more to allow zooming out significantly farther underground
    UndergroundMaxZoom = 10000.0,

    -- Whether to prevent camera from drifting outside crater boundaries
    ClampToMapBounds = true,

    -- Enable debug log output in UE4SS console / log file
    DebugLogging = false
}

return Config
