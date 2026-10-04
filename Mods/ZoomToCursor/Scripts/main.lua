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
        ZoomOutFromCursor = false, -- false = zoom out from center as requested
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

-- State variables for smooth per-frame zoom tracking
local IsZoomingIn = false
local TargetCursorX = 0.0
local TargetCursorY = 0.0
local PrevArmLength = 0.0
local IdleFrameCount = 0

-- Safely retrieve ray origin and direction from deprojected mouse cursor
local function GetRayFromDeproject(PC)
    local outLoc = {}
    local outDir = {}
    local res1, res2, res3 = PC:DeprojectMousePositionToWorld(outLoc, outDir)

    local loc = (outLoc and outLoc.X and outLoc) or (type(res2) == "table" and res2.X and res2) or (type(res1) == "table" and res1.X and res1)
    local dir = (outDir and outDir.X and outDir) or (type(res3) == "table" and res3.X and res3) or (type(res2) == "table" and res2.Z and res2)

    if loc and dir and loc.X and dir.Z and math.abs(dir.Z) > 0.0001 then
        return loc, dir
    end
    return nil, nil
end

-- Retrieve the world ground position under the cursor
local function GetTargetGroundPosition(GodPawn, PC, PawnLoc)
    -- 1. Try GodPawn:UpdateCursorLight() which is the game's built-in cursor calculation
    local cursorLightPos = nil
    pcall(function()
        cursorLightPos = GodPawn:UpdateCursorLight()
    end)
    if cursorLightPos and cursorLightPos.X and math.abs(cursorLightPos.X) > 0.01 then
        return cursorLightPos.X, cursorLightPos.Y, cursorLightPos.Z or PawnLoc.Z
    end

    -- 2. Try LineTrace on channel 11 (The Crust standard ground query channel)
    if PC and PC:IsValid() then
        local hit = {}
        local hasHit = false
        pcall(function()
            hasHit = PC:GetHitResultUnderCursorByChannel(11, true, hit)
        end)
        if hasHit and hit.Location and hit.Location.X then
            return hit.Location.X, hit.Location.Y, hit.Location.Z or PawnLoc.Z
        end

        -- Try LineTrace on channel 0 (Visibility)
        pcall(function()
            hasHit = PC:GetHitResultUnderCursorByChannel(0, true, hit)
        end)
        if hasHit and hit.Location and hit.Location.X then
            return hit.Location.X, hit.Location.Y, hit.Location.Z or PawnLoc.Z
        end

        -- 3. Fallback: Mathematical intersection of cursor ray with horizontal plane at PawnLoc.Z
        local rayLoc, rayDir = GetRayFromDeproject(PC)
        if rayLoc and rayDir then
            local groundZ = PawnLoc.Z or 0.0
            local t = (groundZ - rayLoc.Z) / rayDir.Z
            if t > 0 then
                local mx = rayLoc.X + rayDir.X * t
                local my = rayLoc.Y + rayDir.Y * t
                return mx, my, groundZ
            end
        end
    end

    return nil, nil, nil
end

-- -----------------------------------------------------------------------------
-- 1. Zoom Input Event: Capture target cursor position on Zoom IN only
-- -----------------------------------------------------------------------------
local function OnZoomInput(self, AxisValue)
    local success, err = pcall(function()
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

        -- Ignore zero input (idle frames)
        if not Axis or math.abs(Axis) < 0.001 then return end

        -- ZOOM OUT (Axis < 0): Zoom out from screen center (vanilla behavior)
        if Axis < 0 then
            IsZoomingIn = false
            -- Do not modify pawn location; let game zoom out centered
            return
        end

        -- ZOOM IN (Axis > 0): Capture cursor target for smooth tracking
        local PC = GodPawn.PlayerControllerRef
        if not PC or not PC:IsValid() then
            if UEHelpers then PC = UEHelpers.GetPlayerController() end
        end

        local PawnLoc = GodPawn:K2_GetActorLocation()
        if not PawnLoc then return end

        local curX, curY = GetTargetGroundPosition(GodPawn, PC, PawnLoc)
        if curX and curY then
            TargetCursorX = curX
            TargetCursorY = curY
            IsZoomingIn = true
            IdleFrameCount = 0

            local LongArm = GodPawn.LongArm
            if LongArm and LongArm:IsValid() then
                PrevArmLength = LongArm.TargetArmLength
            end

            Log(string.format("Zoom IN triggered: Target cursor world position (%.1f, %.1f)", TargetCursorX, TargetCursorY))
        end
    end)

    if not success then
        Log("Error in OnZoomInput: " .. tostring(err))
    end
end

-- -----------------------------------------------------------------------------
-- 2. ArmLenght Hook: Synchronously shift pawn position each frame as arm zooms
-- -----------------------------------------------------------------------------
local function OnArmLenghtPre(self)
    local GodPawn = self:get()
    if GodPawn and GodPawn:IsValid() and GodPawn.LongArm and GodPawn.LongArm:IsValid() then
        PrevArmLength = GodPawn.LongArm.TargetArmLength
    end
end

local function OnArmLenghtPost(self)
    if not IsZoomingIn then return end

    local success, err = pcall(function()
        local GodPawn = self:get()
        if not GodPawn or not GodPawn:IsValid() then return end

        local LongArm = GodPawn.LongArm
        if not LongArm or not LongArm:IsValid() then return end

        local currentArm = LongArm.TargetArmLength
        local deltaArm = PrevArmLength - currentArm

        -- If arm is not getting shorter, check if we finished zooming
        if deltaArm <= 0.05 then
            IdleFrameCount = IdleFrameCount + 1
            if IdleFrameCount > 5 then
                IsZoomingIn = false
            end
            return
        end

        IdleFrameCount = 0

        local PawnLoc = GodPawn:K2_GetActorLocation()
        if not PawnLoc then return end

        -- Proportional smooth shift fraction for this single frame
        local factor = (deltaArm / currentArm) * (Config.ZoomStrengthMultiplier or 1.0)
        -- Safety cap to prevent any possible teleportation spikes
        if factor > 0.08 then factor = 0.08 end

        local shiftX = (TargetCursorX - PawnLoc.X) * factor
        local shiftY = (TargetCursorY - PawnLoc.Y) * factor

        local newX = PawnLoc.X + shiftX
        local newY = PawnLoc.Y + shiftY

        -- Boundary clamping if enabled
        if Config.ClampToMapBounds then
            local centerOffset = GodPawn.CraterCenterOffset
            local radius = GodPawn.CraterRadius
            if centerOffset and radius and radius > 0 then
                local distSq = (newX - centerOffset)^2 + (newY - centerOffset)^2
                local maxDist = radius * 1.5
                if distSq > (maxDist * maxDist) then
                    local dist = math.sqrt(distSq)
                    local scale = maxDist / dist
                    newX = centerOffset + (newX - centerOffset) * scale
                    newY = centerOffset + (newY - centerOffset) * scale
                end
            end
        end

        -- Smoothly move pawn for this frame
        GodPawn:K2_SetActorLocation({ X = newX, Y = newY, Z = PawnLoc.Z }, false, {}, false)

        if GodPawn.DestinationPoint then
            GodPawn.DestinationPoint.X = newX
            GodPawn.DestinationPoint.Y = newY
        end
    end)

    if not success then
        Log("Error in OnArmLenghtPost: " .. tostring(err))
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
            local s, e = pcall(function()
                RegisterHook(ZoomHookPath, OnZoomInput)
            end)
            if s then
                ZoomHookRegistered = true
                Log("Successfully registered hook on GodPawn zoom input event!")
            end
        end
    end

    if not ArmHookRegistered then
        local ufuncArm = StaticFindObject(ArmHookPath)
        if ufuncArm and ufuncArm:IsValid() then
            local s, e = pcall(function()
                RegisterHook(ArmHookPath, OnArmLenghtPre, OnArmLenghtPost)
            end)
            if s then
                ArmHookRegistered = true
                Log("Successfully registered hook on GodPawn ArmLenght interpolation!")
            end
        end
    end

    return ZoomHookRegistered and ArmHookRegistered
end

-- 1. Try immediate registration
TryRegisterHooks()

-- 2. Hook player controller restart (fired when player spawns/possesses pawn)
pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(PC, NewPawn)
        TryRegisterHooks()
    end)
end)

-- 3. Notify when GodPawn object is created
pcall(function()
    NotifyOnNewObject("GodPawn_C", function(GodPawn)
        TryRegisterHooks()
    end)
end)

-- 4. Polling fallback via LoopAsync until both hooks registered
pcall(function()
    LoopAsync(1000, function()
        if TryRegisterHooks() then
            return true -- Stops loop once all hooks are active
        end
        return false -- Keeps polling
    end)
end)

Log("ZoomToCursor mod loaded. Listening for GodPawn...")
