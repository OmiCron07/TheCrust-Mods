-- Places a blueprint as ghosts: modules in vanilla planning mode, belts as holo sections,
-- electric wires between pasted modules. Mirrors the vanilla flow of
-- GodPlayer_PC "PlacingModule LMB Click" (spawn, snap, planning flags, SettleModule).

local Grid = require("grid")
local Game = require("game")

local Placer = {}

local LinkFields = {
    Id = "LinkId_4_AC9D2B5A48151C50D5206D88EBAAA72F",
    Start = "StartNode_7_A30BB1064830FC46F18094A082539283",
    End = "EndNode_8_6B7685514510C82E9E33C09259213BF9",
    Invalid = "Invalid_12_FE3B70EF4125246496B0A3A16B309E96",
    Dead = "isDead_14_A791E9CB4F8DE716DEC7289DF0502AAE",
    Hidden = "VisualHidden_16_CF1EC7AB41A504B6E2F828821165E5F0",
}

-- World-space target of a module, Z taken from the spawned actor (ground of the layer).
local function ModuleTarget(Mod, OR, OC, Turns)
    local DR, DC = Grid.Rotate(Mod.DR, Mod.DC, Turns)
    return OR + DR, OC + DC
end

-- Same validation as GodPlayer_PC TickFunctionForPlacingModuleMode ("Can Settle").
-- CheckIfCanSettleModule is not used by vanilla placement and wrongly rejects e.g. Big Bulk Storage.
local function CanSettle(PC, Layer, M)
    M:RecalculatePerimeterAroundUndercells({})
    local Cpp = {}
    M:CPPPlacementCheck(Cpp)
    if not Cpp.Yes then
        -- Modules with special placement rules (e.g. deep ore extractors always return false) are
        -- validated by their CheckIfCanSettleModuleAccordingToUndermoduleCells override instead
        -- (extractors: enough cells on a mineral vein), then only the module count limit applies.
        local Special = {}
        M:CheckIfCanSettleModuleAccordingToUndermoduleCells(Special)
        if not Special.Success then return false, "special placement rule (e.g. extractor needs an ore vein)" end
        local Count = {}
        PC:CheckIfCanSettleCuzOfThisTypeModulesCount(M, Count)
        if Count.Can == false then return false, "module count limit" end
        return true
    end
    if Layer == Game.LayerUnderground then
        local Soil = {}
        M["Check Intersection Of Perimeter Cells and Soil"](M, Soil)
        if Soil["Intersection detected"] then return false, "touches undug soil" end
    end
    local Interior = {}
    M:CheckIfCanSettleModuleWithInteriorSettings(Interior)
    if not Interior.Success then return false, "interior/exterior rule" end
    local Anchor = {}
    M:GetAnchorCellCurrentRealID(Anchor)
    if not M:CheckPossibilityOfModuleSettlementAccordingToGM(Game.GroundManager(PC, Layer), Anchor["Out SmallIndex"]) then
        return false, "blocked"
    end
    local Count = {}
    PC:CheckIfCanSettleCuzOfThisTypeModulesCount(M, Count)
    if Count.Can == false then return false, "module count limit" end
    return true
end

local function PlaceModule(PC, Layer, Geo, Mod, OR, OC, Turns)
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

    local CheckOk, Can, Reason = pcall(CanSettle, PC, Layer, M)
    if not (CheckOk and Can) then
        M:K2_DestroyActor()
        return nil, CheckOk and Reason or ("check failed: " .. tostring(Can))
    end

    M.bPlanningModeCPP = true
    M.bInPlanningMode = true
    M:SettleModule()
    M.IsBuildedByPlayer = true
    -- Placement validity squares stay visible on modules that never were the PC's CurrentModuleToBuild.
    M.Undercells:ForEach(function(_, V)
        local Cell = V:get()
        if Game.Valid(Cell) then Cell:SetVision(false) end
    end)
    -- Production scheme: same call as the vanilla paste-settings (GodPlayer_PC "Copy-PasteSettings").
    if Mod.Recipe and Mod.Recipe ~= "" and Game.Valid(M.AbilityAgencyVar) then
        pcall(function() M.AbilityAgencyVar:ExecuteAbility(Mod.Recipe, nil) end)
    end
    return M
end

local function NodeId(Module)
    local Node = Module.ElectricNodeActor
    if Game.Valid(Node) then return Node.Node.NodeID end
end

-- Same sequence as GodPlayer_PC "LMBForElectricWires" on a successful second click.
-- "Add Link" takes the link by reference: UE4SS needs a Lua table there, so the new link ID
-- is written back into CurrentLink by hand before registering it on both nodes.
local function PlaceLink(EM, A, B)
    local NA, NB = NodeId(A), NodeId(B)
    if not NA or not NB then return false end
    EM:SetCurrentLinkStartNode(NA)
    EM:SetCurrentLinkEndNode(NB)
    local Current = EM.CurrentLink
    if Current[LinkFields.Start] ~= NA or Current[LinkFields.End] ~= NB then
        EM:ClearCurrentLinkInfo()
        return false
    end
    local Link = {}
    for _, Field in pairs(LinkFields) do Link[Field] = Current[Field] end
    local Out = {}
    EM["Add Link"](EM, Link, false, Out, {})
    local Id = Out["Added Link Id"]
    if not Id or Id < 0 then
        EM:ClearCurrentLinkInfo()
        return false
    end
    Current[LinkFields.Id] = Id
    EM:AddLinkToItsNodes(EM.CurrentLink)
    EM["Add Neighbours By Link"](EM, EM.CurrentLink)
    EM:DrawCurrentLinkPersistent()
    EM:ClearCurrentLinkInfo()
    return true
end

-- Cells already used by modules (except their IO cells, where belts connect), built belts or holo belts.
local function OccupiedCells(CM, Layer)
    local Used = {}
    for _, M in ipairs(Game.LayerModules(Layer)) do
        for _, Cell in ipairs(Game.ModuleCells(M)) do Used[Cell] = true end
        M.IOCells:ForEach(function(_, V)
            local IO = V:get()
            if Game.Valid(IO) then Used[IO.CellId] = nil end
        end)
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
        local Ok, M, Err = pcall(PlaceModule, PC, Layer, Geo, Mod, OR, OC, Turns)
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
    if R.ModulesFailed > 0 then S = S .. string.format(" | %d modules blocked (%s)", R.ModulesFailed, R.Errors[1] or "?") end
    if R.BeltCellsBlocked > 0 then S = S .. string.format(" | %d belt cells blocked", R.BeltCellsBlocked) end
    return S
end

return Placer
