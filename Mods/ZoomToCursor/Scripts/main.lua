-- =============================================================================
-- Mod: ZoomToCursor
-- Description: Smoothly zooms towards mouse cursor for zoom-in,
--              and zooms out from screen center (vanilla) for zoom-out.
-- =============================================================================

local Config = nil
pcall(function()
    Config = require("config")
end)
if not Config then
    Config = {
        ZoomInToCursor = true,
        ZoomOutFromCursor = false,
        ZoomStrengthMultiplier = 1.0,
        ClampToMapBounds = true,
        DebugLogging = true
    }
end

local UEHelpers = nil
pcall(function()
    UEHelpers = require("UEHelpers")
end)

local function Log(Message)
    if Config.DebugLogging then
        print(string.format("[ZoomToCursor] %s\n", tostring(Message)))
    end
end

-- Interpolation target for smooth camera translation
local TargetPawnX = nil
local TargetPawnY = nil

-- Retrieve accurate 3D ground location under mouse cursor
local function GetCursorGroundPosition(GodPawn, PC, PawnLoc)
    -- 1. Analytical Ray-Plane Intersection (accurate at any altitude)
    if PC and PC:IsValid() then
        local outLoc = {}
        local outDir = {}
        local res1, res2, res3 = PC:DeprojectMousePositionToWorld(outLoc, outDir)

        local loc = (outLoc and outLoc.X and outLoc) or (type(res2) == "table" and res2.X and res2) or (type(res1) == "table" and res1.X and res1)
        local dir = (outDir and outDir.X and outDir) or (type(res3) == "table" and res3.X and res3) or (type(res2) == "table" and res2.Z and res2)

        if loc and dir and loc.X and dir.Z and math.abs(dir.Z) > 0.0001 then
            local groundZ = PawnLoc.Z or 0.0
            local t = (groundZ - loc.Z) / dir.Z
            if t > 0 then
                return loc.X + dir.X * t, loc.Y + dir.Y * t
            end
        end

        -- 2. LineTrace on channel 11
        local hit = {}
        local hasHit = false
        pcall(function() hasHit = PC:GetHitResultUnderCursorByChannel(11, true, hit) end)
        if hasHit and hit.Location and hit.Location.X then
            return hit.Location.X, hit.Location.Y
        end
    end

    -- 3. Game's UpdateCursorLight fallback
    local lightPos = nil
    pcall(function() lightPos = GodPawn:UpdateCursorLight() end)
    if lightPos and lightPos.X and math.abs(lightPos.X) > 0.01 then
        return lightPos.X, lightPos.Y
    end

    return nil, nil
end

-- -----------------------------------------------------------------------------
-- Zoom Input Event: Calculate target position on Zoom IN
-- -----------------------------------------------------------------------------
local function OnZoomInput(self, AxisValue)
    local GodPawn = self:get()
    if not GodPawn or not GodPawn:IsValid() then return end

    local Axis = 0.0
    if AxisValue then
        if type(AxisValue.get) == "function" then
            Axis = AxisValue:get()
        elseif type(AxisValue) == "number" then
            Axis = AxisValue
        end
    end

    -- Ignore idle frames
    if not Axis or math.abs(Axis) < 0.001 then return end

    local PawnLoc = GodPawn:K2_GetActorLocation()
    if not PawnLoc then return end

    -- ZOOM OUT (Axis < 0): Keep zoom centered on screen (vanilla behavior)
    if Axis < 0 then
        TargetPawnX = PawnLoc.X
        TargetPawnY = PawnLoc.Y
        return
    end

    -- ZOOM IN (Axis > 0): Shift TargetPawn towards cursor
    local PC = GodPawn.PlayerControllerRef
    if not PC or not PC:IsValid() then
        if UEHelpers then PC = UEHelpers.GetPlayerController() end
    end

    local cursorX, cursorY = GetCursorGroundPosition(GodPawn, PC, PawnLoc)
    if not cursorX or not cursorY then return end

    local LongArm = GodPawn.LongArm
    local armLength = (LongArm and LongArm:IsValid() and LongArm.TargetArmLength) or 4000.0
    if armLength < 300.0 then armLength = 300.0 end

    -- Proportional zoom fraction per wheel notch
    local zoomStep = math.abs(GodPawn["Zoom Step"] or 500.0)
    if zoomStep < 100.0 then zoomStep = 500.0 end
    local fraction = (zoomStep / armLength) * (Config.ZoomStrengthMultiplier or 1.0)
    if fraction > 0.20 then fraction = 0.20 end
    if fraction < 0.04 then fraction = 0.04 end

    -- Base target position from current Pawn position if not yet set
    if not TargetPawnX then TargetPawnX = PawnLoc.X end
    if not TargetPawnY then TargetPawnY = PawnLoc.Y end

    -- Calculate displacement towards cursor
    local shiftX = (cursorX - TargetPawnX) * fraction
    local shiftY = (cursorY - TargetPawnY) * fraction

    TargetPawnX = TargetPawnX + shiftX
    TargetPawnY = TargetPawnY + shiftY

    -- Map boundary clamping
    if Config.ClampToMapBounds then
        local centerOffset = GodPawn.CraterCenterOffset
        local radius = GodPawn.CraterRadius
        if centerOffset and radius and radius > 0 then
            local distSq = (TargetPawnX - centerOffset)^2 + (TargetPawnY - centerOffset)^2
            local maxDist = radius * 1.5
            if distSq > (maxDist * maxDist) then
                local dist = math.sqrt(distSq)
                local scale = maxDist / dist
                TargetPawnX = centerOffset + (TargetPawnX - centerOffset) * scale
                TargetPawnY = centerOffset + (TargetPawnY - centerOffset) * scale
            end
        end
    end

    Log(string.format("Zoom IN: Target shifted by (%.1f, %.1f) towards cursor (%.1f, %.1f)", shiftX, shiftY, cursorX, cursorY))
end

-- -----------------------------------------------------------------------------
-- ArmLenght Post Hook: Smoothly glide Pawn towards TargetPawn every frame
-- -----------------------------------------------------------------------------
local function OnArmLenghtPost(self, DeltaTimeParm)
    if not TargetPawnX or not TargetPawnY then return end

    local GodPawn = self:get()
    if not GodPawn or not GodPawn:IsValid() then return end

    local PawnLoc = GodPawn:K2_GetActorLocation()
    if not PawnLoc then return end

    local diffX = TargetPawnX - PawnLoc.X
    local diffY = TargetPawnY - PawnLoc.Y
    local distSq = diffX * diffX + diffY * diffY

    -- Once arrived within threshold, finish interpolation
    if distSq < 4.0 then
        return
    end

    local dt = 0.016
    if DeltaTimeParm then
        if type(DeltaTimeParm.get) == "function" then
            local v = DeltaTimeParm:get()
            if v and v > 0.0001 and v < 0.2 then dt = v end
        elseif type(DeltaTimeParm) == "number" and DeltaTimeParm > 0.0001 and DeltaTimeParm < 0.2 then
            dt = DeltaTimeParm
        end
    end

    -- Smooth exponential ease-out matching game camera interpolation (speed 12)
    local interpSpeed = 12.0
    local alpha = 1.0 - math.exp(-interpSpeed * dt)
    if alpha > 1.0 then alpha = 1.0 end

    local newX = PawnLoc.X + diffX * alpha
    local newY = PawnLoc.Y + diffY * alpha

    GodPawn:K2_SetActorLocation({ X = newX, Y = newY, Z = PawnLoc.Z }, false, {}, false)

    if GodPawn.DestinationPoint then
        GodPawn.DestinationPoint.X = newX
        GodPawn.DestinationPoint.Y = newY
    end
end

-- =============================================================================
-- Deferred Hook Registration
-- =============================================================================

local ZoomHookRegistered = false
local ArmHookRegistered = false

local ZoomHookPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:InpAxisEvt_Zoom_K2Node_InputAxisEvent_0"
local ArmHookPath  = "/Game/Blueprints/Core/GodPawn.GodPawn_C:ArmLenght"

local function TryRegisterHooks()
    if not ZoomHookRegistered then
        local ufuncZoom = StaticFindObject(ZoomHookPath)
        if ufuncZoom and ufuncZoom:IsValid() then
            RegisterHook(ZoomHookPath, OnZoomInput)
            ZoomHookRegistered = true
            Log("Hooked zoom input.")
        end
    end

    if not ArmHookRegistered then
        local ufuncArm = StaticFindObject(ArmHookPath)
        if ufuncArm and ufuncArm:IsValid() then
            RegisterHook(ArmHookPath, function() end, OnArmLenghtPost)
            ArmHookRegistered = true
            Log("Hooked ArmLenght.")
        end
    end

    return ZoomHookRegistered and ArmHookRegistered
end

TryRegisterHooks()
pcall(function() RegisterHook("/Script/Engine.PlayerController:ClientRestart", function() TryRegisterHooks() end) end)
pcall(function() NotifyOnNewObject("GodPawn_C", function() TryRegisterHooks() end) end)
pcall(function() LoopAsync(1000, function() return TryRegisterHooks() end) end)

Log("Smooth ZoomToCursor mod active.")
