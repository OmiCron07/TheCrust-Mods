-- World-space overlay boxes (selection rectangle, paste preview) built from a pool of
-- StaticMeshActors using the engine cube and a dynamic translucent material, plus the paste
-- preview belts drawn with the game's own belt meshes as blue holograms.

local Grid = require("grid")
local Game = require("game")

local Visuals = {}

local MeshPath = "/Engine/BasicShapes/Cube.Cube"
local MaterialPaths = {
    "/Engine/EngineDebugMaterials/M_SimpleUnlitTranslucent.M_SimpleUnlitTranslucent",
    "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial",
}
local MidName = "BlueprintsModMID"
local ColorParams = { "Color", "BaseColor", "Tint" }

local Pool = {}
local Mesh, Material
local BeltHost -- overlay box whose cube is hidden, carrying one instanced mesh component per belt type

-- Per-instance custom data of the belt materials (16 floats): [9] = 1 alone draws the blue holo;
-- built belts use [8] = [9] = 1, planning ghosts [9] = [10] = 1. [3] is 1 on every vanilla belt.
local BeltCustomData = { [3] = 1, [9] = 1 }
local BeltCustomDataCount = 16

local function LoadObject(Path)
    local Obj = StaticFindObject(Path)
    if Game.Valid(Obj) then return Obj end
    pcall(function() LoadAsset((Path:gsub("%.[^%.]+$", ""))) end)
    Obj = StaticFindObject(Path)
    if Game.Valid(Obj) then return Obj end
end

local function EnsureAssets()
    if not Game.Valid(Mesh) then Mesh = LoadObject(MeshPath) end
    if not Game.Valid(Material) then
        for _, P in ipairs(MaterialPaths) do
            Material = LoadObject(P)
            if Material then break end
        end
    end
    return Mesh ~= nil and Material ~= nil
end

local function Statics(Name)
    return StaticFindObject("/Script/Engine.Default__" .. Name)
end

local function NewBox(PC)
    local Cls = StaticFindObject("/Script/Engine.StaticMeshActor")
    local GS = Statics("GameplayStatics")
    local Transform = {
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = 0, Y = 0, Z = -100000 },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
    local Actor = GS:BeginDeferredActorSpawnFromClass(PC, Cls, Transform, 1, nil)
    if not Game.Valid(Actor) then error("overlay actor spawn failed") end
    Actor = GS:FinishSpawningActor(Actor, Transform)
    local Comp = Actor.StaticMeshComponent
    Comp:SetMobility(2)
    Comp:SetStaticMesh(Mesh)
    Comp:SetCollisionEnabled(0)
    Comp:SetCastShadow(false)
    local Mid = Statics("KismetMaterialLibrary"):CreateDynamicMaterialInstance(PC, Material, FName(MidName), 0)
    Comp:SetMaterial(0, Mid)
    return { Actor = Actor, Comp = Comp, Mid = Mid }
end

local function SetColor(Box, Color)
    if Box.Color == Color then return end
    Box.Color = Color
    for _, P in ipairs(ColorParams) do
        Box.Mid:SetVectorParameterValue(FName(P), Color)
    end
end

-- Drops actor references without touching them (they may belong to a destroyed world).
function Visuals.Forget()
    Pool, BeltHost = {}, nil
end

-- Destroys overlay actors left behind by a previous instance of the mod (hot reload).
-- Every object must be IsValid-checked before GetFName: UE4SS returns null wrappers (not nil)
-- and GetFName on one reads address 0x18 and crashes the game, beyond pcall's reach.
function Visuals.CleanupLeftovers()
    for _, A in ipairs(FindAllOf("StaticMeshActor") or {}) do
        local Comp = Game.Valid(A) and A.StaticMeshComponent
        local Mat = Game.Valid(Comp) and Comp:GetMaterial(0)
        if Game.Valid(Mat) and Mat:GetFName():ToString():find(MidName, 1, true) then
            A:K2_DestroyActor()
        end
    end
end

-- Converts cell boxes to world rectangles; Outline boxes become four bars (the material is opaque,
-- so filled boxes would hide what they cover).
local function WorldRects(Geo, Boxes)
    local Rects = {}
    for _, B in ipairs(Boxes) do
        local MinR, MaxR = math.min(B[1], B[3]), math.max(B[1], B[3])
        local MinC, MaxC = math.min(B[2], B[4]), math.max(B[2], B[4])
        local X0, Y0 = Game.RowColToWorld(Geo, MinR - 0.5, MinC - 0.5)
        local X1, Y1 = Game.RowColToWorld(Geo, MaxR + 0.5, MaxC + 0.5)
        local Inset = Geo.CellSize * (B.Inset or 0)
        -- Thin boxes (belt runs) only shrink across their width, so consecutive runs meet at corners.
        local InsetX = (B.Thin and MaxR > MinR) and 0 or Inset
        local InsetY = (B.Thin and MaxC > MinC) and 0 or Inset
        X0, Y0, X1, Y1 = X0 + InsetX, Y0 + InsetY, X1 - InsetX, Y1 - InsetY
        local H = B.Height or 12
        if B.Outline then
            local T = Geo.CellSize * B.Outline
            Rects[#Rects + 1] = { X0, Y0, X0 + T, Y1, H, B.Color }
            Rects[#Rects + 1] = { X1 - T, Y0, X1, Y1, H, B.Color }
            Rects[#Rects + 1] = { X0, Y0, X1, Y0 + T, H, B.Color }
            Rects[#Rects + 1] = { X0, Y1 - T, X1, Y1, H, B.Color }
        else
            Rects[#Rects + 1] = { X0, Y0, X1, Y1, H, B.Color }
        end
    end
    return Rects
end

-- Boxes: array of { R0, C0, R1, C1, Color = {R, G, B, A}, Height, Inset, Outline } in absolute cells
-- (inclusive). Inset and Outline (bar thickness) are fractions of a cell.
function Visuals.Show(PC, Geo, Boxes)
    if not EnsureAssets() then return false end
    local Rects = WorldRects(Geo, Boxes)
    for i, R in ipairs(Rects) do
        local Box = Pool[i]
        if not (Box and Game.Valid(Box.Actor)) then
            Box = NewBox(PC)
            Pool[i] = Box
        end
        local X0, Y0, X1, Y1, H = R[1], R[2], R[3], R[4], R[5]
        Box.Actor:K2_SetActorLocation({ X = (X0 + X1) / 2, Y = (Y0 + Y1) / 2, Z = Geo.Z + 8 + H / 2 }, false, {}, false)
        Box.Actor:SetActorScale3D({ X = (X1 - X0) / 100, Y = (Y1 - Y0) / 100, Z = H / 100 })
        SetColor(Box, R[6])
        Box.Actor:SetActorHiddenInGame(false)
    end
    for i = #Rects + 1, #Pool do
        if Game.Valid(Pool[i].Actor) then Pool[i].Actor:SetActorHiddenInGame(true) end
    end
    return true
end
function Visuals.Hide()
    for _, Box in ipairs(Pool) do
        if Game.Valid(Box.Actor) then Box.Actor:SetActorHiddenInGame(true) end
    end
    if BeltHost and Game.Valid(BeltHost.Actor) then BeltHost.Actor:SetActorHiddenInGame(true) end
end

local Identity = {
    Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
    Translation = { X = 0, Y = 0, Z = 0 },
    Scale3D = { X = 1, Y = 1, Z = 1 },
}

-- Instanced copy of the game's level 0 belt mesh of that type (from VisualManager, a holo
-- UCSectionVisualManager). The custom data count must be set before the component registers.
local function NewBeltComponent(VisualManager, Type)
    local Src = VisualManager:GetHismByTypeAndLevel(Type, 0)
    if not Game.Valid(Src) then return nil end
    local Cls = StaticFindObject("/Script/Engine.InstancedStaticMeshComponent")
    local Comp = BeltHost.Actor:AddComponentByClass(Cls, false, Identity, true)
    Comp.NumCustomDataFloats = BeltCustomDataCount
    BeltHost.Actor:FinishAddComponent(Comp, false, Identity)
    Comp:SetStaticMesh(Src.StaticMesh)
    for i = 0, Src:GetNumMaterials() - 1 do Comp:SetMaterial(i, Src:GetMaterial(i)) end
    Comp:SetCollisionEnabled(0)
    Comp:SetCastShadow(false)
    return Comp
end

-- Pieces: array of { Type, Row, Col, Yaw } (Grid.BeltVisuals). Moving the same blueprint only
-- updates instance transforms; a different piece count per type rebuilds that type's instances.
function Visuals.ShowBelts(PC, Geo, VisualManager, Pieces)
    if not EnsureAssets() then return false end
    if not (BeltHost and Game.Valid(BeltHost.Actor)) then
        BeltHost = NewBox(PC)
        BeltHost.Comp:SetVisibility(false, false)
        BeltHost.Actor:K2_SetActorLocation(Identity.Translation, false, {}, false)
        BeltHost.Types = {}
    end
    local Z = Geo.Z + VisualManager.ConveyorHeight
    local ByType = {}
    for _, P in ipairs(Pieces) do
        local List = ByType[P[1]] or {}
        ByType[P[1]] = List
        local X, Y = Game.RowColToWorld(Geo, P[2], P[3])
        local Half = math.rad(P[4]) / 2
        List[#List + 1] = {
            Rotation = { X = 0, Y = 0, Z = math.sin(Half), W = math.cos(Half) },
            Translation = { X = X, Y = Y, Z = Z },
            Scale3D = { X = 1, Y = 1, Z = 1 },
        }
    end
    for Type, List in pairs(ByType) do
        local Comp = BeltHost.Types[Type]
        if not Game.Valid(Comp) then
            Comp = NewBeltComponent(VisualManager, Type)
            BeltHost.Types[Type] = Comp
        end
        if Comp and Comp:GetInstanceCount() == #List then
            Comp:BatchUpdateInstancesTransforms(0, List, true, true, true)
        elseif Comp then
            Comp:ClearInstances()
            Comp:AddInstances(List, false)
            for i = 0, #List - 1 do
                for Index, Value in pairs(BeltCustomData) do
                    Comp:SetCustomDataValue(i, Index, Value, i == #List - 1)
                end
            end
        end
    end
    for Type, Comp in pairs(BeltHost.Types) do
        if not ByType[Type] and Game.Valid(Comp) then Comp:ClearInstances() end
    end
    BeltHost.Actor:SetActorHiddenInGame(false)
    return true
end

-- Builds preview boxes of a blueprint placed on (OR, OC) rotated by Turns.
-- Valid (optional): per module index validity; false draws the module with InvalidColor.
function Visuals.BlueprintBoxes(BP, OR, OC, Turns, ModuleColor, BeltColor, Valid, InvalidColor)
    local Boxes = {}
    for i, Mod in ipairs(BP.Modules) do
        local Color = (Valid and Valid[i] == false) and InvalidColor or ModuleColor
        local R0, C0, R1, C1
        for _, Cell in ipairs(Mod.Cells) do
            local DR, DC = Grid.Rotate(Cell[1], Cell[2], Turns)
            local R, C = OR + DR, OC + DC
            R0, C0 = math.min(R0 or R, R), math.min(C0 or C, C)
            R1, C1 = math.max(R1 or R, R), math.max(C1 or C, C)
        end
        if R0 then Boxes[#Boxes + 1] = { R0, C0, R1, C1, Color = Color, Height = 30, Inset = 0.05, Outline = 0.12 } end
    end
    if not BeltColor then return Boxes end -- Belts drawn by Visuals.ShowBelts instead.
    -- Merge straight runs of belt cells into single boxes.
    for _, Path in ipairs(BP.Belts) do
        local Cur
        for _, P in ipairs(Path) do
            local DR, DC = Grid.Rotate(P[1], P[2], Turns)
            local R, C = OR + DR, OC + DC
            local Extends = Cur and ((Cur[1] == Cur[3] and R == Cur[1] and math.abs(C - Cur[4]) == 1)
                or (Cur[2] == Cur[4] and C == Cur[2] and math.abs(R - Cur[3]) == 1))
            if Extends then
                Cur[3], Cur[4] = R, C
            else
                Cur = { R, C, R, C, Color = BeltColor, Height = 6, Inset = 0.25, Thin = true }
                Boxes[#Boxes + 1] = Cur
            end
        end
    end
    for _, U in ipairs(BP.Undergrounds or {}) do
        for k = 1, 2 do
            local DR, DC = Grid.Rotate(U[k][1], U[k][2], Turns)
            local R, C = OR + DR, OC + DC
            Boxes[#Boxes + 1] = { R, C, R, C, Color = BeltColor, Height = 18, Inset = 0.15, Outline = 0.12 }
        end
    end
    return Boxes
end

return Visuals
