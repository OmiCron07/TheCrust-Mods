-- Places a blueprint as ghosts: modules in vanilla planning mode, belts as holo sections,
-- electric wires between pasted modules. Mirrors the vanilla flow of
-- GodPlayer_PC "PlacingModule LMB Click" (spawn, snap, planning flags, SettleModule).

local Grid = require("grid")
local Game = require("game")

local Placer = {}

local LinkStart = "StartNode_7_A30BB1064830FC46F18094A082539283"

-- World-space target of a module, Z taken from the spawned actor (ground of the layer).
local function ModuleTarget(Mod, OR, OC, Turns)
    local DR, DC = Grid.Rotate(Mod.DR, Mod.DC, Turns)
    return OR + DR, OC + DC
end

local function PlaceModule(PC, Geo, Mod, OR, OC, Turns)
    local Cls = Game.LoadClass(Mod.Class)
    if not Cls then return nil, "class not found: " .. Mod.Class end

    local Row, Col = ModuleTarget(Mod, OR, OC, Turns)
    local SpawnRow, SpawnCol = math.floor(Row + 0.5), math.floor(Col + 0.5)
    if not Grid.InBounds(SpawnRow, SpawnCol) then return nil, "out of bounds" end

    local Out = {}
    PC:SpawnModuleOnLocation(Cls, Grid.ToCell(SpawnRow, SpawnCol), Out, {})
    local M = Out["Out Module"]
    if not Game.Valid(M) then return nil, "spawn failed" end

    local Ok, Err = pcall(function()
        if Mod.Mirrored then M:MirrorModule() end
        M:K2_SetActorRotation({ Pitch = 0, Yaw = ((Mod.Turns + Turns) % 4) * 90, Roll = 0 }, false)
        M:RecalculateCellIndexesUnderModule(true, {})
        M:RecalculatePerimeterAroundUndercells({})
        pcall(function() M:SetRotationID() end)

        local X, Y = Game.RowColToWorld(Geo, Row, Col)
        local Z = M:K2_GetActorLocation().Z
        M["Snap Module to Cursor"](M, { X = X, Y = Y, Z = Z }, {})
    end)
    if not Ok then
        M:K2_DestroyActor()
        return nil, "setup failed: " .. tostring(Err)
    end

    local Check = {}
    M:CheckIfCanSettleModule(Check, {})
    local Count = {}
    pcall(function() PC:CheckIfCanSettleCuzOfThisTypeModulesCount(M, Count) end)
    if not Check["Out No Obstacles"] or Count.Can == false then
        M:K2_DestroyActor()
        return nil, "blocked"
    end

    M.bPlanningModeCPP = true
    M.bInPlanningMode = true
    M:SettleModule()
    M.IsBuildedByPlayer = true
    return M
end

local function NodeId(Module)
    local Node = Module.ElectricNodeActor
    if Game.Valid(Node) then return Node.Node.NodeID end
end

-- Same sequence as GodPlayer_PC "LMBForElectricWires" on a successful second click.
local function PlaceLink(EM, A, B)
    local NA, NB = NodeId(A), NodeId(B)
    if not NA or not NB then return false end
    EM:SetCurrentLinkStartNode(NA)
    EM:SetCurrentLinkEndNode(NB)
    if EM.CurrentLink[LinkStart] ~= NA then
        EM:ClearCurrentLinkInfo()
        return false
    end
    EM["Add Link"](EM, EM.CurrentLink, false, {}, {})
    EM:AddLinkToItsNodes(EM.CurrentLink)
    EM["Add Neighbours By Link"](EM, EM.CurrentLink)
    EM:DrawCurrentLinkPersistent()
    EM:ClearCurrentLinkInfo()
    return true
end

-- Cells already used by modules, built belts or holo belts on the layer.
local function OccupiedCells(CM, Layer)
    local Used = {}
    for _, M in ipairs(Game.LayerModules(Layer)) do
        for _, Cell in ipairs(Game.ModuleCells(M)) do Used[Cell] = true end
    end
    local function Mark(Grid2)
        if not Game.Valid(Grid2) then return end
        Grid2.UniqueSections:ForEach(function(_, E)
            local S = E:get()
            if Game.Valid(S) then
                S.State.CellIds:ForEach(function(_, V) Used[V:get()] = true end)
            end
        end)
    end
    Mark(CM.SectionGrid)
    Mark(CM.HoloSectionGrid)
    return Used
end

local function PlaceBelts(CM, Layer, BP, OR, OC, Turns, Report)
    local Used = OccupiedCells(CM, Layer)
    for _, Path in ipairs(BP.Belts) do
        -- Transform to absolute cells; blocked cells split the path.
        local Abs = {}
        for _, P in ipairs(Path) do
            local DR, DC = Grid.Rotate(P[1], P[2], Turns)
            local R, C = OR + DR, OC + DC
            if Grid.InBounds(R, C) and not Used[Grid.ToCell(R, C)] then
                Abs[#Abs + 1] = { R, C, P[3] and Grid.RotateDir(P[3], Turns) }
            else
                Abs[#Abs + 1] = false
                Report.BeltCellsBlocked = Report.BeltCellsBlocked + 1
            end
        end

        local Run = {}
        local function Flush()
            for _, Sub in ipairs(Grid.SplitContiguous(Run)) do
                for _, Piece in ipairs(Grid.BeltPieces(Sub)) do
                    local S = Grid.ToCell(Piece.Start[1], Piece.Start[2])
                    local E = Grid.ToCell(Piece.End[1], Piece.End[2])
                    CM:BuildHolo(S, E, Piece.Vertical, false, -1)
                    Report.BeltPieces = Report.BeltPieces + 1
                end
            end
            Run = {}
        end
        for _, A in ipairs(Abs) do
            if A then Run[#Run + 1] = A else Flush() end
        end
        Flush()
    end
    CM:UpdateHoloSectionCosts()
end

-- Pastes BP with its origin on OriginCell, rotated by Turns quarter turns clockwise.
function Placer.Paste(PC, Layer, BP, OriginCell, Turns, Options)
    local Report = {
        Modules = 0, ModulesFailed = 0, Links = 0, BeltPieces = 0, BeltCellsBlocked = 0, Errors = {},
    }
    local CM = Game.ConveyorManager(PC, Layer)
    if not Game.Valid(CM) then
        Report.Errors[1] = "No conveyor manager on this layer"
        return Report
    end
    local Geo = Game.Geometry(CM)
    local OR, OC = Grid.ToRowCol(OriginCell)

    local Placed = {}
    for i, Mod in ipairs(BP.Modules) do
        local Ok, M, Err = pcall(PlaceModule, PC, Geo, Mod, OR, OC, Turns)
        if Ok and M then
            Placed[i] = M
            Report.Modules = Report.Modules + 1
        else
            Report.ModulesFailed = Report.ModulesFailed + 1
            local Name = Mod.Class:match("([^%.]+)$") or Mod.Class
            Report.Errors[#Report.Errors + 1] = Name .. ": " .. tostring(Ok and Err or M)
        end
    end

    if Options.PasteElectricLinks and #BP.Links > 0 then
        local EM = Game.Level(PC).ElectricManager
        for _, L in ipairs(BP.Links) do
            local A, B = Placed[L[1]], Placed[L[2]]
            if A and B then
                local Ok, Done = pcall(PlaceLink, EM, A, B)
                if Ok and Done then Report.Links = Report.Links + 1 end
            end
        end
    end

    if Options.PasteConveyors and #BP.Belts > 0 then
        local Ok, Err = pcall(PlaceBelts, CM, Layer, BP, OR, OC, Turns, Report)
        if not Ok then Report.Errors[#Report.Errors + 1] = "belts: " .. tostring(Err) end
    end
    return Report
end

function Placer.Summary(R)
    local S = string.format("Placed %d ghost modules, %d belt pieces, %d wires", R.Modules, R.BeltPieces, R.Links)
    if R.ModulesFailed > 0 then S = S .. string.format(" | %d modules blocked", R.ModulesFailed) end
    if R.BeltCellsBlocked > 0 then S = S .. string.format(" | %d belt cells blocked", R.BeltCellsBlocked) end
    return S
end

return Placer
