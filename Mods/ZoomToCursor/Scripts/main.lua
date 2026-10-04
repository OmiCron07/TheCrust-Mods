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

-- Pinned target position for the active zoom session
local PinnedTargetX = nil
local PinnedTargetY = nil
local LastZoomInTime = 0.0

-- Interpolation target for smooth camera translation
local TargetPawnX = nil
local TargetPawnY = nil

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
        PinnedTargetX = nil
        PinnedTargetY = nil
        TargetPawnX = nil
        TargetPawnY = nil
        return
    end

    -- ZOOM IN (Axis > 0): Pin initial cursor ground location throughout gesture
    local now = os.clock()
    local isNewGesture = (not PinnedTargetX) or (not PinnedTargetY) or (now - LastZoomInTime > 0.5)

    if isNewGesture then
        local PC = GodPawn.PlayerControllerRef
        if not PC or not PC:IsValid() then
            if UEHelpers then PC = UEHelpers.GetPlayerController() end
        end

        local cursorX, cursorY, method = GetCursorGroundPosition(GodPawn, PC, PawnLoc)
        if not cursorX or not cursorY then return end

        PinnedTargetX = cursorX
        PinnedTargetY = cursorY
        TargetPawnX = PawnLoc.X
        TargetPawnY = PawnLoc.Y

        Log(string.format("New Zoom IN session pinned to: (%.1f, %.1f) via %s", PinnedTargetX, PinnedTargetY, method))
    end

    if not PinnedTargetX or not PinnedTargetY then return end

    local LongArm = GodPawn.LongArm
    local armLength = (LongArm and LongArm:IsValid() and LongArm.TargetArmLength) or 4000.0
    if armLength < 300.0 then armLength = 300.0 end

    -- Proportional zoom fraction per wheel notch
    local zoomStep = math.abs(GodPawn["Zoom Step"] or 500.0)
    if zoomStep < 100.0 then zoomStep = 500.0 end
    local fraction = (zoomStep / armLength) * math.abs(Axis) * (Config.ZoomStrengthMultiplier or 1.0)
    if fraction > 0.35 then fraction = 0.35 end
    if fraction < 0.08 then fraction = 0.08 end

    if not TargetPawnX then TargetPawnX = PawnLoc.X end
    if not TargetPawnY then TargetPawnY = PawnLoc.Y end

    -- Calculate displacement towards PINNED target (consistent straight-line trajectory)
    local shiftX = (PinnedTargetX - TargetPawnX) * fraction
    local shiftY = (PinnedTargetY - TargetPawnY) * fraction

    TargetPawnX = TargetPawnX + shiftX
    TargetPawnY = TargetPawnY + shiftY
    LastZoomInTime = now

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

    Log(string.format("Zoom IN: Target (%.1f, %.1f) shifted by (%.1f, %.1f) towards pinned (%.1f, %.1f)",
        TargetPawnX, TargetPawnY, shiftX, shiftY, PinnedTargetX, PinnedTargetY))
end

-- -----------------------------------------------------------------------------
-- ArmLenght Hook: Smoothly glide Pawn towards TargetPawn every frame
-- -----------------------------------------------------------------------------
local function OnArmLenght(self, DeltaTimeParm)
    if not TargetPawnX or not TargetPawnY then return end

    local now = os.clock()
    -- Safety timeout: if no zoom input for > 1.0 second, reset all targets
    if LastZoomInTime and (now - LastZoomInTime > 1.0) then
        TargetPawnX = nil
        TargetPawnY = nil
        PinnedTargetX = nil
        PinnedTargetY = nil
        return
    end

    local GodPawn = self:get()
    if not GodPawn or not GodPawn:IsValid() then return end

    local PawnLoc = GodPawn:K2_GetActorLocation()
    if not PawnLoc then return end

    local diffX = TargetPawnX - PawnLoc.X
    local diffY = TargetPawnY - PawnLoc.Y
    local distSq = diffX * diffX + diffY * diffY

    -- Once arrived within threshold, finish this interpolation step
    if distSq < 16.0 then
        TargetPawnX = nil
        TargetPawnY = nil
        return
    end

    local dt = 0.016
    if DeltaTimeParm then
        if type(DeltaTimeParm.get) == "function" then
            local v = DeltaTimeParm:get()
            if v and type(v) == "number" and v > 0.0001 and v < 0.2 then dt = v end
        elseif type(DeltaTimeParm) == "number" and DeltaTimeParm > 0.0001 and DeltaTimeParm < 0.2 then
            dt = DeltaTimeParm
        end
    end

    -- Match game camera interpolation speed (10.0)
    local interpSpeed = 10.0
    local alpha = 1.0 - math.exp(-interpSpeed * dt)
    if alpha > 1.0 then alpha = 1.0 end

    local newX = PawnLoc.X + diffX * alpha
    local newY = PawnLoc.Y + diffY * alpha

    GodPawn:K2_SetActorLocation({ X = newX, Y = newY, Z = PawnLoc.Z }, false, {}, false)

    pcall(function()
        GodPawn.DestinationPoint = { X = newX, Y = newY, Z = PawnLoc.Z }
        GodPawn.DoWeReachDestination = true
    end)
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
            RegisterHook(ZoomHookPath, OnZoomInput, function() end)
            ZoomHookRegistered = true
            Log("Hooked zoom input.")
        end
    end

    if not ArmHookRegistered then
        local ufuncArm = StaticFindObject(ArmHookPath)
        if ufuncArm and ufuncArm:IsValid() then
            RegisterHook(ArmHookPath, OnArmLenght, function() end)
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
