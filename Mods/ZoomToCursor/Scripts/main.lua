-- =============================================================================
-- Mod: ZoomToCursor
-- Description: Smoothly zooms towards the mouse cursor (zoom-in and/or zoom-out,
--              per config). Falls back to vanilla center zoom while WASD moves the camera.
-- =============================================================================

local Defaults = {
    ZoomInToCursor = true,
    ZoomOutFromCursor = false,
    ZoomStrengthMultiplier = 1.0,
    UndergroundMaxZoom = 10000.0,
    ClampToMapBounds = true,
    DebugLogging = false
}

local Ok, Loaded = pcall(require, "config")
if not Ok or type(Loaded) ~= "table" then
    print("[ZoomToCursor] config.lua failed to load, using defaults: " .. tostring(Loaded) .. "\n")
    Loaded = {}
end
-- Missing keys fall back to defaults (explicit false values are kept)
local Config = setmetatable(Loaded, { __index = Defaults })

local function Log(Message)
    if Config.DebugLogging then
        print(string.format("[ZoomToCursor] %s\n", tostring(Message)))
    end
end

-- Apply configurable Underground max zoom distance to GodPawn instance
local function ApplyUndergroundMaxZoom(GodPawn)
    if not Config.UndergroundMaxZoom or Config.UndergroundMaxZoom <= 0 then return end
    if GodPawn.MaxDistanceToGround_Underground ~= Config.UndergroundMaxZoom then
        GodPawn.MaxDistanceToGround_Underground = Config.UndergroundMaxZoom
        Log(string.format("Applied UndergroundMaxZoom = %.1f to GodPawn", Config.UndergroundMaxZoom))
    end
end

-- Pinned cursor ground position for the active zoom gesture
local PinnedTargetX = nil
local PinnedTargetY = nil
local PinnedDirection = 0
local LastZoomTime = 0.0

-- Camera offset still to be applied by the per-frame glide. Applied as a delta on top of
-- the current location so it composes with other camera motion instead of fighting it.
local PendingX = nil
local PendingY = nil

-- WASD movement suppresses cursor zoom (vanilla center zoom) for a short grace period,
-- covering the FloatingPawnMovement glide after the keys are released.
local MoveGraceSeconds = 0.3
local LastMoveTime = -math.huge

local function ResetZoom()
    PinnedTargetX, PinnedTargetY, PinnedDirection = nil, nil, 0
    PendingX, PendingY = nil, nil
end

local function ReadFloat(Param)
    local Value = Param and Param:get()
    return type(Value) == "number" and Value or 0.0
end

-- Retrieve accurate 3D ground location under mouse cursor
local function GetCursorGroundPosition(GodPawn, PC, PawnLoc)
    -- 1. Analytical Ray-Plane Intersection (DeprojectMousePositionToWorld)
    if PC and PC:IsValid() then
        local success, worldLoc, worldDir = nil, nil, nil
        pcall(function()
            success, worldLoc, worldDir = PC:DeprojectMousePositionToWorld()
        end)

        if not success or not worldLoc then
            pcall(function()
                local outLoc = {}
                local outDir = {}
                local s, l, d = PC:DeprojectMousePositionToWorld(outLoc, outDir)
                success = s or (outLoc.X ~= nil)
                worldLoc = l or outLoc
                worldDir = d or outDir
            end)
        end

        local locX = worldLoc and (worldLoc.X or (type(worldLoc) == "table" and worldLoc[1]))
        local locZ = worldLoc and (worldLoc.Z or (type(worldLoc) == "table" and worldLoc[3]))
        local dirX = worldDir and (worldDir.X or (type(worldDir) == "table" and worldDir[1]))
        local dirY = worldDir and (worldDir.Y or (type(worldDir) == "table" and worldDir[2]))
        local dirZ = worldDir and (worldDir.Z or (type(worldDir) == "table" and worldDir[3]))

        if locX and locZ and dirZ and math.abs(dirZ) > 0.0001 then
            local groundZ = (PawnLoc and PawnLoc.Z) or 0.0
            local t = (groundZ - locZ) / dirZ
            if t > 0 then
                local gx = locX + dirX * t
                local gy = (worldLoc.Y or (type(worldLoc) == "table" and worldLoc[2])) + dirY * t
                return gx, gy, "Deproject"
            end
        end

        -- 2. LineTrace on channel 11
        local hit = nil
        pcall(function()
            local s, h = PC:GetHitResultUnderCursorByChannel(11, true)
            hit = h or s
        end)
        if hit and hit.Location and hit.Location.X then
            return hit.Location.X, hit.Location.Y, "HitResult"
        end
    end

    -- 3. Game's UpdateCursorLight fallback
    local lightPos = nil
    pcall(function() lightPos = GodPawn:UpdateCursorLight() end)
    if lightPos and lightPos.X and math.abs(lightPos.X) > 0.01 then
        return lightPos.X, lightPos.Y, "UpdateCursorLight"
    end

    return nil, nil, "None"
end

-- -----------------------------------------------------------------------------
-- Move Input Events (WASD / arrows): cancel cursor zoom while the camera is driven
-- -----------------------------------------------------------------------------
local function OnMoveInput(self, AxisValue)
    if math.abs(ReadFloat(AxisValue)) < 0.001 then return end
    LastMoveTime = os.clock()
    if PendingX or PinnedTargetX then ResetZoom() end
end

-- -----------------------------------------------------------------------------
-- Zoom Input Event: queue a camera shift towards (zoom in) or away from (zoom out) the cursor
-- -----------------------------------------------------------------------------
local function OnZoomInput(self, AxisValue)
    local Axis = ReadFloat(AxisValue)
    -- Ignore idle frames
    if math.abs(Axis) < 0.001 then return end

    local Direction = Axis > 0 and 1 or -1
    local Enabled = (Direction > 0 and Config.ZoomInToCursor) or (Direction < 0 and Config.ZoomOutFromCursor)
    local now = os.clock()
    if not Enabled or now - LastMoveTime < MoveGraceSeconds then
        -- Vanilla zoom: centered on screen
        ResetZoom()
        return
    end

    local GodPawn = self:get()
    if not GodPawn or not GodPawn:IsValid() then return end

    local PawnLoc = GodPawn:K2_GetActorLocation()
    if not PawnLoc then return end

    -- Pin the initial cursor ground location throughout the gesture
    if not PinnedTargetX or Direction ~= PinnedDirection or now - LastZoomTime > 0.5 then
        local cursorX, cursorY, method = GetCursorGroundPosition(GodPawn, GodPawn.PlayerControllerRef, PawnLoc)
        if not cursorX or not cursorY then return end

        PinnedTargetX, PinnedTargetY, PinnedDirection = cursorX, cursorY, Direction
        Log(string.format("New zoom gesture (%d) pinned to: (%.1f, %.1f) via %s", Direction, cursorX, cursorY, method))
    end
    LastZoomTime = now

    local LongArm = GodPawn.LongArm
    local armLength = (LongArm and LongArm:IsValid() and LongArm.TargetArmLength) or 4000.0
    if armLength < 300.0 then armLength = 300.0 end

    -- Proportional zoom fraction per wheel notch; the multiplier scales the clamped value
    -- so it takes effect at every arm length
    local zoomStep = math.abs(GodPawn["Zoom Step"] or 500.0)
    if zoomStep < 100.0 then zoomStep = 500.0 end
    local fraction = (zoomStep / armLength) * math.abs(Axis)
    if fraction > 0.35 then fraction = 0.35 end
    if fraction < 0.08 then fraction = 0.08 end
    fraction = math.min(fraction * Config.ZoomStrengthMultiplier, 0.9) * Direction

    -- Displace the final camera position (current + still pending) towards / away from the pin
    local baseX = PawnLoc.X + (PendingX or 0.0)
    local baseY = PawnLoc.Y + (PendingY or 0.0)
    local targetX = baseX + (PinnedTargetX - baseX) * fraction
    local targetY = baseY + (PinnedTargetY - baseY) * fraction

    -- Map boundary clamping
    if Config.ClampToMapBounds then
        local centerOffset = GodPawn.CraterCenterOffset
        local radius = GodPawn.CraterRadius
        if centerOffset and radius and radius > 0 then
            local distSq = (targetX - centerOffset)^2 + (targetY - centerOffset)^2
            local maxDist = radius * 1.5
            if distSq > (maxDist * maxDist) then
                local scale = maxDist / math.sqrt(distSq)
                targetX = centerOffset + (targetX - centerOffset) * scale
                targetY = centerOffset + (targetY - centerOffset) * scale
            end
        end
    end

    PendingX = targetX - PawnLoc.X
    PendingY = targetY - PawnLoc.Y

    Log(string.format("Zoom (%d): target (%.1f, %.1f), pinned (%.1f, %.1f)",
        Direction, targetX, targetY, PinnedTargetX, PinnedTargetY))
end

-- -----------------------------------------------------------------------------
-- ArmLenght Hook (every frame): glide the pending offset onto the Pawn
-- -----------------------------------------------------------------------------
local function OnArmLenght(self, DeltaTimeParm)
    local GodPawn = self:get()
    if not GodPawn or not GodPawn:IsValid() then return end

    ApplyUndergroundMaxZoom(GodPawn)

    if not PendingX then return end

    local PawnLoc = GodPawn:K2_GetActorLocation()
    if not PawnLoc then return end

    local dt = ReadFloat(DeltaTimeParm)
    if dt <= 0.0001 or dt >= 0.2 then dt = 0.016 end

    -- Match game camera interpolation speed (10.0)
    local alpha = 1.0 - math.exp(-10.0 * dt)
    local stepX, stepY = PendingX * alpha, PendingY * alpha

    -- Once nearly arrived, apply the remainder and finish
    if (PendingX * PendingX + PendingY * PendingY) < 16.0 then
        stepX, stepY = PendingX, PendingY
        PendingX, PendingY = nil, nil
    else
        PendingX, PendingY = PendingX - stepX, PendingY - stepY
    end

    local NewLoc = { X = PawnLoc.X + stepX, Y = PawnLoc.Y + stepY, Z = PawnLoc.Z }
    GodPawn:K2_SetActorLocation(NewLoc, false, {}, false)

    pcall(function()
        GodPawn.DestinationPoint = NewLoc
        GodPawn.DoWeReachDestination = true
    end)
end

-- =============================================================================
-- Deferred Hook Registration
-- =============================================================================

local GodPawnPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:"
local Hooks = {
    { Name = "InpAxisEvt_Zoom_K2Node_InputAxisEvent_0", Callback = OnZoomInput },
    { Name = "InpAxisEvt_MoveForward_K2Node_InputAxisEvent_1", Callback = OnMoveInput },
    { Name = "InpAxisEvt_MoveRight_K2Node_InputAxisEvent_2", Callback = OnMoveInput },
    { Name = "ArmLenght", Callback = OnArmLenght },
}

-- The UFunction can be found before its Blueprint class finishes loading (Func = 0x0),
-- making RegisterHook throw: pcall and retry on the next poll.
local function TryRegisterHooks()
    local AllDone = true
    for _, Hook in ipairs(Hooks) do
        if not Hook.Registered then
            local Path = GodPawnPath .. Hook.Name
            local Fn = StaticFindObject(Path)
            if Fn and Fn:IsValid() then
                Hook.Registered = pcall(RegisterHook, Path, Hook.Callback)
                if Hook.Registered then Log("Hooked " .. Hook.Name) end
            end
            AllDone = AllDone and Hook.Registered == true
        end
    end
    return AllDone
end

if not TryRegisterHooks() then LoopAsync(1000, TryRegisterHooks) end

Log("Smooth ZoomToCursor mod active.")
