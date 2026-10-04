-- World-space overlay boxes (selection rectangle, paste preview) built from a pool of
-- StaticMeshActors using the engine cube and a dynamic translucent material.

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
    Actor = GS:FinishSpawningActor(Actor, Transform)
    local Comp = Actor.StaticMeshComponent
    Comp:SetMobility(2)
    Comp:SetStaticMesh(Mesh)
    Comp:SetCollisionEnabled(0)
    Comp:SetCastShadow(false)
    local Mid = Statics("KismetMaterialLibrary"):CreateDynamicMaterialInstance(PC, Material, FName(MidName))
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

-- Destroys overlay actors left behind by a previous instance of the mod (hot reload).
function Visuals.CleanupLeftovers()
    for _, A in ipairs(FindAllOf("StaticMeshActor") or {}) do
        if Game.Valid(A) then
            local Ok, Name = pcall(function() return A.StaticMeshComponent:GetMaterial(0):GetFName():ToString() end)
            if Ok and Name and Name:find(MidName, 1, true) then A:K2_DestroyActor() end
        end
    end
end

-- Boxes: array of { R0, C0, R1, C1, Color = {R, G, B, A}, Height } in absolute cells (inclusive).
function Visuals.Show(PC, Geo, Boxes)
    if not EnsureAssets() then return false end
    for i, B in ipairs(Boxes) do
        local Box = Pool[i]
        if not (Box and Game.Valid(Box.Actor)) then
            Box = NewBox(PC)
            Pool[i] = Box
        end
        local MinR, MaxR = math.min(B[1], B[3]), math.max(B[1], B[3])
        local MinC, MaxC = math.min(B[2], B[4]), math.max(B[2], B[4])
        local X0, Y0 = Game.RowColToWorld(Geo, MinR - 0.5, MinC - 0.5)
        local X1, Y1 = Game.RowColToWorld(Geo, MaxR + 0.5, MaxC + 0.5)
        local Inset = Geo.CellSize * (B.Inset or 0.06)
        local H = B.Height or 12
        Box.Actor:K2_SetActorLocation({ X = (X0 + X1) / 2, Y = (Y0 + Y1) / 2, Z = Geo.Z + 8 + H / 2 }, false, {}, false)
        Box.Actor:SetActorScale3D({ X = (X1 - X0 - 2 * Inset) / 100, Y = (Y1 - Y0 - 2 * Inset) / 100, Z = H / 100 })
        SetColor(Box, B.Color)
        Box.Actor:SetActorHiddenInGame(false)
    end
    for i = #Boxes + 1, #Pool do
        if Game.Valid(Pool[i].Actor) then Pool[i].Actor:SetActorHiddenInGame(true) end
    end
    return true
end

function Visuals.Hide()
    for _, Box in ipairs(Pool) do
        if Game.Valid(Box.Actor) then Box.Actor:SetActorHiddenInGame(true) end
    end
end

-- Builds preview boxes of a blueprint placed on (OR, OC) rotated by Turns.
function Visuals.BlueprintBoxes(BP, OR, OC, Turns, ModuleColor, BeltColor)
    local Boxes = {}
    for _, Mod in ipairs(BP.Modules) do
        local R0, C0, R1, C1
        for _, Cell in ipairs(Mod.Cells) do
            local DR, DC = Grid.Rotate(Cell[1], Cell[2], Turns)
            local R, C = OR + DR, OC + DC
            R0, C0 = math.min(R0 or R, R), math.min(C0 or C, C)
            R1, C1 = math.max(R1 or R, R), math.max(C1 or C, C)
        end
        if R0 then Boxes[#Boxes + 1] = { R0, C0, R1, C1, Color = ModuleColor, Height = 40 } end
    end
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
                Cur = { R, C, R, C, Color = BeltColor, Height = 6, Inset = 0.25 }
                Boxes[#Boxes + 1] = Cur
            end
        end
    end
    return Boxes
end

return Visuals
