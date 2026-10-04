-- Configuration for ZoomToCursor mod
local Config = {
    -- Enable zooming towards mouse cursor for zoom in (scroll up)
    ZoomInToCursor = true,

    -- Enable zooming away from mouse cursor for zoom out (scroll down)
    -- If false, zooming out will center on current camera position
    ZoomOutFromCursor = true,

    -- Multiplier for zoom shift intensity (1.0 = exact 1:1 geometric match)
    ZoomStrengthMultiplier = 1.0,

    -- Whether to prevent camera from drifting outside crater boundaries
    ClampToMapBounds = true,

    -- Enable debug log output in UE4SS console / log file
    DebugLogging = false
}

return Config
