-- Configuration for ZoomToCursor mod
local Config = {
    -- Enable zooming towards mouse cursor for zoom in (scroll up)
    ZoomInToCursor = true,

    -- Enable zooming away from mouse cursor for zoom out (scroll down)
    -- Set to false so that zooming out always stays centered on screen center (vanilla)
    ZoomOutFromCursor = false,

    -- Multiplier for zoom shift intensity (1.0 = exact 1:1 focal match)
    ZoomStrengthMultiplier = 1.0,

    -- Whether to prevent camera from drifting outside crater boundaries
    ClampToMapBounds = true,

    -- Enable debug log output in UE4SS console / log file
    DebugLogging = true
}

return Config
