-- =============================================================================
-- Mod: ZoomToCursor
-- Description: Centers zoom on mouse cursor instead of screen center in The Crust
-- =============================================================================

local Config = require("config")
local UEHelpers = require("UEHelpers")

local function Log(Message)
    if Config.DebugLogging then
        print(string.format("[ZoomToCursor] %s\n", tostring(Message)))
    end
end

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

-- Attempt to trace ground collision under cursor, falling back to math plane intersection
local function GetTargetGroundPosition(PC, PawnLoc)
    -- 1. Try LineTrace / Channel 11 (The Crust standard ground query channel)
    local hit = {}
    local hasHit = false
    pcall(function()
        hasHit = PC:GetHitResultUnderCursorByChannel(11, true, hit)
    end)

    if hasHit and hit.Location and hit.Location.X then
        return hit.Location.X, hit.Location.Y, hit.Location.Z or PawnLoc.Z
    end

    -- Fallback: TraceTypeQuery1 (channel 0)
    pcall(function()
        hasHit = PC:GetHitResultUnderCursorByChannel(0, true, hit)
    end)
    if hasHit and hit.Location and hit.Location.X then
        return hit.Location.X, hit.Location.Y, hit.Location.Z or PawnLoc.Z
    end

    -- 2. Fallback: Mathematical intersection of cursor ray with horizontal plane at PawnLoc.Z
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

    return nil, nil, nil
end

-- Hook GodPawn Zoom input event
RegisterHook("/Game/Blueprints/Core/GodPawn.GodPawn_C:InpAxisEvt_Zoom_K2Node_InputAxisEvent_0", function(self, AxisValue)
    local success, err = pcall(function()
        local GodPawn = self:get()
        if not GodPawn or not GodPawn:IsValid() then return end

        local Axis = AxisValue:get()
        if not Axis or math.abs(Axis) < 0.001 then return end

        -- Direction checks based on config
        if Axis > 0 and not Config.ZoomInToCursor then return end
        if Axis < 0 and not Config.ZoomOutFromCursor then return end

        -- PlayerController reference
        local PC = GodPawn.PlayerControllerRef
        if not PC or not PC:IsValid() then
            PC = UEHelpers.GetPlayerController()
        end
        if not PC or not PC:IsValid() then return end

        -- Current Pawn world location
        local PawnLoc = GodPawn:K2_GetActorLocation()
        if not PawnLoc then return end

        -- Target world point under the mouse cursor
        local TargetX, TargetY, TargetZ = GetTargetGroundPosition(PC, PawnLoc)
        if not TargetX or not TargetY then
            Log("Could not determine cursor world position.")
            return
        end

        -- Calculate arm lengths and zoom delta
        local LongArm = GodPawn.LongArm
        local currentArm = (LongArm and LongArm:IsValid() and LongArm.TargetArmLength) or 3000.0
        local targetArm = GodPawn["Target for Target Arm Length"] or currentArm
        if targetArm <= 10.0 then targetArm = 3000.0 end

        local zoomStep = GodPawn["Zoom Step"] or -500.0
        if math.abs(zoomStep) < 1.0 then zoomStep = -500.0 end

        -- Delta arm length applied by this wheel tick
        local deltaArm = Axis * zoomStep
        local newArm = targetArm + deltaArm

        -- Clamp against pawn min/max limits
        local minZoom = GodPawn.MinimalDistanceToGround or 300.0
        local maxZoom = GodPawn.MaxDistanceToGround_Underground or 25000.0
        if newArm < minZoom then newArm = minZoom end
        if newArm > maxZoom then newArm = maxZoom end

        -- Zoom ratio and shift fraction
        local ratio = newArm / targetArm
        local alpha = (1.0 - ratio) * (Config.ZoomStrengthMultiplier or 1.0)

        if math.abs(alpha) < 0.0001 then return end

        -- Calculate displacement vector towards mouse cursor
        local shiftX = (TargetX - PawnLoc.X) * alpha
        local shiftY = (TargetY - PawnLoc.Y) * alpha

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

        -- Apply new actor position
        local newLocation = {
            X = newX,
            Y = newY,
            Z = PawnLoc.Z
        }
        local sweepHit = {}
        GodPawn:K2_SetActorLocation(newLocation, false, sweepHit, false)

        -- Update DestinationPoint if tracking destination
        if GodPawn.DestinationPoint then
            GodPawn.DestinationPoint.X = newX
            GodPawn.DestinationPoint.Y = newY
        end

        Log(string.format("Zoomed %s (Axis=%.1f): Shifted (%.1f, %.1f) towards cursor",
            (Axis > 0 and "IN" or "OUT"), Axis, shiftX, shiftY))
    end)

    if not success and Config.DebugLogging then
        Log("Error during zoom hook: " .. tostring(err))
    end
end)

print("[ZoomToCursor] Mod initialized successfully. Hooked GodPawn zoom event.\n")
