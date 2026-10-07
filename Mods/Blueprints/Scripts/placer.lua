-- Places a blueprint as ghosts: modules in vanilla planning mode, belts as holo sections,
-- electric wires between pasted modules. Mirrors the vanilla flow of
-- GodPlayer_PC "PlacingModule LMB Click" (spawn, snap, planning flags, SettleModule).

local Grid = require("grid")
local Game = require("game")
local Settings = require("settings")

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
        -- Extractors only know their active cells once recalculated (vanilla does it every tick
        -- while the module follows the cursor); without it they count 0 cells on a vein.
        pcall(function() M:RecalculateExtractorActiveCells() end)
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

-- Spawns an unsettled (cursor-preview state) module for Mod near (OR, OC); mirrored like the source.
function Placer.SpawnModule(PC, Mod, OR, OC, Turns)
    local Cls = Game.LoadClass(Mod.Class)
    if not Cls then return nil, "class not found: " .. Mod.Class end
    local Row, Col = ModuleTarget(Mod, OR, OC, Turns)
    local SpawnRow, SpawnCol = math.floor(Row + 0.5), math.floor(Col + 0.5)
    if not Grid.InBounds(SpawnRow, SpawnCol) then return nil, "out of bounds" end
    local Out = {}
    PC:SpawnModuleOnLocation(Cls, Grid.ToCell(SpawnRow, SpawnCol), Out, {})
    local M = Out["Out Module"]
    if not Game.Valid(M) then return nil, "spawn failed" end
    if Mod.Mirrored then M:MirrorModule() end
    return M
end

-- Rotates and snaps an unsettled module onto its blueprint position.
function Placer.PositionModule(M, Geo, Mod, OR, OC, Turns)
    local Row, Col = ModuleTarget(Mod, OR, OC, Turns)
    M:K2_SetActorRotation({ Pitch = 0, Yaw = ((Mod.Turns + Turns) % 4) * 90, Roll = 0 }, false)
    M:RecalculateCellIndexesUnderModule(true, {})
    M:RecalculatePerimeterAroundUndercells({})
    pcall(function() M:SetRotationID() end)
    local X, Y = Game.RowColToWorld(Geo, Row, Col)
    local Z = M:K2_GetActorLocation().Z
    M["Snap Module to Cursor"](M, { X = X, Y = Y, Z = Z }, {})
end

local function PlaceModule(PC, Layer, Geo, Mod, OR, OC, Turns)
    local M, SpawnErr = Placer.SpawnModule(PC, Mod, OR, OC, Turns)
    if not M then return nil, SpawnErr end

    local Ok, Err = pcall(Placer.PositionModule, M, Geo, Mod, OR, OC, Turns)
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

-- Cell occupancy of the layer. Belts: cells a pasted belt cannot use (module cells except their IO
-- cells, where belts connect, and existing belts). Modules: cells a pasted module cannot cover
-- (all module cells and existing belts).
function Placer.Occupancy(CM, Layer)
    local Used, Modules = {}, {}
    for _, M in ipairs(Game.LayerModules(Layer)) do
        for _, Cell in ipairs(Game.ModuleCells(M)) do
            Used[Cell] = true
            Modules[Cell] = true
        end
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
                S.State.CellIds:ForEach(function(_, V)
                    local Cell = V:get()
                    Used[Cell] = true
                    Modules[Cell] = true
                end)
            end
        end)
    end
    Mark(CM.SectionGrid)
    Mark(CM.HoloSectionGrid)
    return { Belts = Used, Modules = Modules }
end

-- Underground belt pair through the vanilla tool (ECInputMode 3): set the direction, click the entry,
-- click the exit. BuildHolo never creates underground belts. Restores the tool state afterwards.
local function PlaceUnderground(CM, Geo, Entry, Exit, Dir)
    local Ctl = CM.Controller
    local PrevMode, PrevDir = CM:GetConveyorMode(), Ctl:GetUndergroundBeltDirection()
    local function Click(Cell)
        local X, Y = Game.RowColToWorld(Geo, Grid.ToRowCol(Cell))
        CM:MainPointerAction({ X = X, Y = Y, Z = Geo.Z })
    end
    local function Rotate(To)
        for _ = 1, 4 do
            if Ctl:GetUndergroundBeltDirection() == To then return end
            CM:RotateUndergroundBelt(false)
        end
    end
    CM:SetConveyorMode(3)
    Ctl:ResetClickCellIDs()
    Rotate(Dir)
    local Ok, Err = pcall(function()
        Click(Entry)
        Click(Exit)
    end)
    Ctl:ResetClickCellIDs()
    Rotate(PrevDir)
    CM:SetConveyorMode(PrevMode)
    if not Ok then error(Err) end
    local S = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Entry)
    return Game.Valid(S) and S:GetSectionType() == 3 and S.State.ConnectedUndergroundBeltCellID == Exit
end

local function PlaceBelts(CM, Layer, BP, OR, OC, Turns, Report)
    local Used = Placer.Occupancy(CM, Layer).Belts

    -- Underground pairs first: the belts feeding / leaving them start or end on their cells.
    local Geo = Game.Geometry(CM)
    for _, U in ipairs(BP.Undergrounds or {}) do
        local Ends = {}
        for k = 1, 2 do
            local DR, DC = Grid.Rotate(U[k][1], U[k][2], Turns)
            local R, C = OR + DR, OC + DC
            Ends[k] = Grid.InBounds(R, C) and not Used[Grid.ToCell(R, C)] and Grid.ToCell(R, C)
        end
        local Ok, Done = false, false
        if Ends[1] and Ends[2] then
            Ok, Done = pcall(PlaceUnderground, CM, Geo, Ends[1], Ends[2], Grid.RotateDir(U[3], Turns))
        end
        if Ok and Done then
            Report.Undergrounds = Report.Undergrounds + 1
            Report.BeltCells[#Report.BeltCells + 1] = Ends[1]
            Report.BeltCells[#Report.BeltCells + 1] = Ends[2]
        else
            Report.UndergroundsFailed = Report.UndergroundsFailed + 1
            if not Ok and Done then Report.Errors[#Report.Errors + 1] = "underground: " .. tostring(Done) end
        end
    end
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
                for _, P in ipairs(Sub) do
                    Report.BeltCells[#Report.BeltCells + 1] = Grid.ToCell(P[1], P[2])
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

-- Applies the captured distributor settings to the distributors the pasted belts created.
local function ApplyDistributors(CM, BP, OR, OC, Turns, Report)
    for _, D in ipairs(BP.Distributors or {}) do
        local DR, DC = Grid.Rotate(D.DR, D.DC, Turns)
        local Cell = Grid.ToCell(OR + DR, OC + DC)
        local S = CM.SectionGrid:GetSectionAtCellID_Safe(Cell)
        if not Game.Valid(S) then S = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell) end
        if Game.Valid(S) and S:GetSectionType() == 2 then
            local Ok, Mismatches = pcall(Settings.ApplyDistributor, CM, S, D, Turns)
            if Ok then
                Report.Distributors = Report.Distributors + 1
                Report.SettingsMismatches = Report.SettingsMismatches + Mismatches
            else
                Report.Errors[#Report.Errors + 1] = "distributor settings: " .. tostring(Mismatches)
            end
        else
            Report.DistributorsMissing = Report.DistributorsMissing + 1
        end
    end
end

-- Vanilla "play" button of a planned module: supply / unlock check, then start construction.
-- Returns true when the module is (now) under construction.
function Placer.BuildPlanned(M)
    if not M.bPlanningModeCPP then return true end
    if not M["Available For Building from PlanningMode"](M) then return false end
    M:ChangeFromPlanningModeToDefault()
    return true
end

-- Builds the holo belt sections covering Cells with the vanilla build button logic
-- (BP_ConveyorManager BuildAllSectionsWithMoney: pays the total cost, then BuildAllConveyors moves
-- the holo sections to the built grid). Every other holo section is deferred meanwhile so only ours
-- are built. BuildSection alone only flags the holo section as built without moving it, which draws
-- a built belt and a holo belt on top of each other.
function Placer.BuildBelts(CM, Cells, Report)
    local Targets, Count = {}, 0
    for _, Cell in ipairs(Cells) do
        local S = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell)
        if Game.Valid(S) and not Targets[S:GetAddress()] then
            Targets[S:GetAddress()] = S
            Count = Count + 1
        end
    end
    if Count == 0 then return end

    local Deferred, Undeferred = {}, {}
    CM.HoloSectionGrid.UniqueSections:ForEach(function(_, E)
        local S = E:get()
        if Game.Valid(S) and not Targets[S:GetAddress()] and not S:IsDeferred() then
            S:SetDeferred(true)
            Deferred[#Deferred + 1] = S
        end
    end)
    for _, S in pairs(Targets) do
        if S:IsDeferred() then
            S:SetDeferred(false)
            Undeferred[#Undeferred + 1] = S
        end
    end

    CM:UpdateHoloSectionCosts()
    local Out = {}
    local Ok, Err = pcall(function() CM:BuildAllSectionsWithMoney(Out) end)
    local Built = Ok and Out.IsSuccess == true

    for _, S in ipairs(Deferred) do
        if Game.Valid(S) then S:SetDeferred(false) end
    end
    if not Built then
        for _, S in ipairs(Undeferred) do
            if Game.Valid(S) then S:SetDeferred(true) end
        end
    end
    CM:UpdateHoloSectionCosts()

    if Built then
        Report.SectionsBuilt = Report.SectionsBuilt + Count
    else
        Report.SectionsNoFunds = Report.SectionsNoFunds + Count
        if not Ok then Report.Errors[#Report.Errors + 1] = "build belts: " .. tostring(Err) end
    end
end
local function NewReport()
    return {
        Modules = 0, ModulesFailed = 0, Links = 0, BeltPieces = 0, BeltCellsBlocked = 0, Errors = {},
        BeltCells = {}, Built = 0, NotBuilt = 0, SectionsBuilt = 0, SectionsNoFunds = 0,
        Distributors = 0, DistributorsMissing = 0, SettingsMismatches = 0,
        Undergrounds = 0, UndergroundsFailed = 0,
    }
end

-- Starts construction of the planned modules and holo belts inside a cell rectangle (inclusive).
function Placer.BuildArea(PC, Layer, R0, C0, R1, C1)
    local Report = NewReport()
    local CM = Game.ConveyorManager(PC, Layer)
    local Geo = Game.Geometry(CM)
    for _, M in ipairs(Game.LayerModules(Layer)) do
        if M.bPlanningModeCPP then
            local Loc = M:K2_GetActorLocation()
            local Row, Col = Game.WorldToRowCol(Geo, Loc.X, Loc.Y)
            Row, Col = math.floor(Row + 0.5), math.floor(Col + 0.5)
            if Row >= R0 and Row <= R1 and Col >= C0 and Col <= C1 then
                local Ok, Done = pcall(Placer.BuildPlanned, M)
                if Ok and Done then Report.Built = Report.Built + 1 else Report.NotBuilt = Report.NotBuilt + 1 end
            end
        end
    end
    local Cells = {}
    for R = R0, R1 do
        for C = C0, C1 do Cells[#Cells + 1] = Grid.ToCell(R, C) end
    end
    local Ok, Err = pcall(Placer.BuildBelts, CM, Cells, Report)
    if not Ok then Report.Errors[#Report.Errors + 1] = "belts: " .. tostring(Err) end
    return Report
end

-- Removes the modules and belts of a cell rectangle (inclusive) through the vanilla demolition tool
-- paths (GodPlayer_PC "LMB for Demolition"): ToggleModuleDismantle on modules (planned ghosts vanish,
-- built modules get the dismantle order), DeleteWindowedCells + BP_RecoupCollected on built belts
-- (refunded), HoverOnDestruction + DeleteHoloSectionAtCellID on holo belts. Only the modules a capture
-- of the rectangle copies are touched, and nothing outside the rectangle is removed.
function Placer.DeleteArea(PC, Layer, R0, C0, R1, C1)
    local Report = { Modules = 0, ModulesKept = 0, BeltCells = 0, BeltCellsKept = 0, Errors = {} }
    local CM = Game.ConveyorManager(PC, Layer)
    local Geo = Game.Geometry(CM)
    local function Inside(Cell)
        if not Cell or Cell < 0 then return false end
        local R, C = Grid.ToRowCol(Cell)
        return R >= R0 and R <= R1 and C >= C0 and C <= C1
    end

    local function Cells(Arr)
        local T = {}
        Arr:ForEach(function(_, V) T[#T + 1] = V:get() end)
        return T
    end
    local function AllInside(List)
        for _, Cell in ipairs(List) do
            if not Inside(Cell) then return false end
        end
        return true
    end
    -- Both ends of an underground pair go together (a capture skips pairs cut by the selection).
    -- Deleting one end unlinks the other (ConnectedUndergroundBeltCellID -1): a lone end goes too.
    local function PairInside(S)
        if S:GetSectionType() ~= 3 then return true end
        local Other = S.State.ConnectedUndergroundBeltCellID
        return Other < 0 or Inside(Other)
    end

    local PrevMode = CM:GetConveyorMode()
    CM:SetConveyorMode(2) -- Vanilla demolition mode (GodPlayer_PC StartDeconstruct).
    local Ok, Err = pcall(function()
        -- Built belts: DeleteWindowedCells removes exactly the cells of LastDestructionWindowCellIDs
        -- (the vanilla hover fills it with a contiguous 4-5 cell chunk of one section). Every deletion
        -- changes the sections around it, so each one re-reads the section owning the cell and only
        -- passes the contiguous run of its cells inside the rectangle (stale cells crashed the game).
        local Pending = {}
        for R = R0, R1 do
            for C = C0, C1 do
                local Cell = Grid.ToCell(R, C)
                if Game.Valid(CM.SectionGrid:GetSectionAtCellID_Safe(Cell)) then Pending[#Pending + 1] = Cell end
            end
        end
        for _, Cell in ipairs(Pending) do
            local Built = CM.SectionGrid:GetSectionAtCellID_Safe(Cell)
            if Game.Valid(Built) then
                local List = Cells(Built.State.CellIds)
                local At
                for i, Id in ipairs(List) do
                    if Id == Cell then
                        At = i
                        break
                    end
                end
                if At and PairInside(Built) then
                    local First, Last = At, At
                    while First > 1 and Inside(List[First - 1]) do First = First - 1 end
                    while Last < #List and Inside(List[Last + 1]) do Last = Last + 1 end
                    local Window = CM.LastDestructionWindowCellIDs
                    Window:Empty()
                    for i = First, Last do Window[i - First + 1] = List[i] end
                    CM:DeleteWindowedCells(Cell)
                    Report.BeltCells = Report.BeltCells + Last - First + 1
                else
                    Report.BeltCellsKept = Report.BeltCellsKept + 1
                end
            end
        end
        -- Holo belts: DeleteHoloSectionAtCellID always removes the vanilla chunk (custom windows are
        -- ignored), so a chunk crossing the rectangle edge is kept.
        for R = R0, R1 do
            for C = C0, C1 do
                local Cell = Grid.ToCell(R, C)
                local Holo = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell)
                if Game.Valid(Holo) then
                    CM:HoverOnDestruction(Cell)
                    local Chunk = Cells(CM.LastDestructionWindowCellIDs)
                    if #Chunk > 0 and AllInside(Chunk) and PairInside(Holo) then
                        CM:DeleteHoloSectionAtCellID(Cell)
                        Report.BeltCells = Report.BeltCells + #Chunk
                    else
                        Report.BeltCellsKept = Report.BeltCellsKept + 1
                    end
                end
            end
        end
    end)
    pcall(function() CM:ClearDestructionHoverSelection() end)
    pcall(function() CM:BP_RecoupCollected() end)
    CM:SetConveyorMode(PrevMode)
    CM:UpdateHoloSectionCosts()
    if not Ok then Report.Errors[#Report.Errors + 1] = "belts: " .. tostring(Err) end

    -- Modules after the belts: a built module's dismantle order also changes the sections on its IO cells.
    for _, M in ipairs(Game.LayerModules(Layer)) do
        local Loc = M:K2_GetActorLocation()
        local Row, Col = Game.WorldToRowCol(Geo, Loc.X, Loc.Y)
        Row, Col = math.floor(Row + 0.5), math.floor(Col + 0.5)
        local Agency = M.BuildingAgency
        if Row >= R0 and Row <= R1 and Col >= C0 and Col <= C1 and Game.IsCopyAllowed(M) and not M.IsFromPackage
            and not (Game.Valid(Agency) and Agency.MarkedOnDismantle) then
            -- The result shows up later in the frame (planned and under construction modules are
            -- destroyed after the call returns), so orders are counted, not results.
            local Ok, Locked = pcall(function()
                if M:ActorHasTag(FName("LockedDemolition")) then return true end
                PC:ToggleModuleDismantle(M)
                return false
            end)
            if not Ok then
                Report.Errors[#Report.Errors + 1] = "dismantle: " .. tostring(Locked)
            elseif Locked then
                Report.ModulesKept = Report.ModulesKept + 1
            else
                Report.Modules = Report.Modules + 1
            end
        end
    end
    return Report
end

function Placer.DeleteSummary(R)
    local S = string.format("Deleted %d modules (built ones are dismantled by robots), %d belt cells", R.Modules, R.BeltCells)
    if R.ModulesKept > 0 then S = S .. string.format(" | %d modules kept (locked)", R.ModulesKept) end
    if R.BeltCellsKept > 0 then S = S .. string.format(" | %d belt cells kept (holo or underground belt crossing the selection edge)", R.BeltCellsKept) end
    if #R.Errors > 0 then S = S .. " | " .. R.Errors[1] end
    return S
end

function Placer.BuildSummary(R)
    local S = string.format("Construction started: %d modules, %d belt sections", R.Built, R.SectionsBuilt)
    if R.NotBuilt > 0 then S = S .. string.format(" | %d modules kept planned (supply limit or locked)", R.NotBuilt) end
    if R.SectionsNoFunds > 0 then S = S .. string.format(" | %d belt sections not built (not enough credits)", R.SectionsNoFunds) end
    return S
end

-- Pastes BP with its origin on OriginCell, rotated by Turns quarter turns clockwise.
-- Options.Construction starts construction right away (otherwise ghosts stay planned).
function Placer.Paste(PC, Layer, BP, OriginCell, Turns, Options)
    local Report = NewReport()
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

    if Options.PasteConveyors and (#BP.Belts > 0 or #(BP.Undergrounds or {}) > 0) then
        -- New holo sections are deferred (vanilla planning ghosts) only while the PC planning mode
        -- is on (BP_ConveyorManager GetDeferModeActive); construction undefers ours later.
        local PrevPlanning = PC.bIsPlanningModeActive
        PC.bIsPlanningModeActive = true
        local Ok, Err = pcall(PlaceBelts, CM, Layer, BP, OR, OC, Turns, Report)
        PC.bIsPlanningModeActive = PrevPlanning
        if not Ok then Report.Errors[#Report.Errors + 1] = "belts: " .. tostring(Err) end
    end

    if Options.Construction then
        for _, M in pairs(Placed) do
            local Ok, Done = pcall(Placer.BuildPlanned, M)
            if Ok and Done then Report.Built = Report.Built + 1 else Report.NotBuilt = Report.NotBuilt + 1 end
        end
        local Ok, Err = pcall(Placer.BuildBelts, CM, Report.BeltCells, Report)
        if not Ok then Report.Errors[#Report.Errors + 1] = "build belts: " .. tostring(Err) end
    end
    -- Settings last: belt connections and construction (holo sections moved to the built grid)
    -- happen before.
    for i, M in pairs(Placed) do
        local Mod = BP.Modules[i]
        if Mod.IO and Game.Valid(M) then
            local Ok, Mismatches = pcall(function()
                local IO = Mod.IO
                if Mod.Mirrored and not M.IsMirrored then IO = Settings.MirrorIO(M, IO, Geo) end
                return Settings.ApplyIO(M, IO)
            end)
            if Ok then
                Report.SettingsMismatches = Report.SettingsMismatches + Mismatches
            else
                Report.Errors[#Report.Errors + 1] = "IO settings: " .. tostring(Mismatches)
            end
        end
    end
    if Options.PasteConveyors then ApplyDistributors(CM, BP, OR, OC, Turns, Report) end
    return Report
end

function Placer.Summary(R)
    local S = string.format("Placed %d ghost modules, %d belt pieces, %d distributors, %d undergrounds, %d wires",
        R.Modules, R.BeltPieces, R.Distributors, R.Undergrounds, R.Links)
    if R.Built > 0 or R.SectionsBuilt > 0 then
        S = S .. string.format(" | construction: %d modules, %d belt sections", R.Built, R.SectionsBuilt)
    end
    if R.NotBuilt > 0 then S = S .. string.format(" | %d kept planned (supply/locked)", R.NotBuilt) end
    if R.SectionsNoFunds > 0 then S = S .. string.format(" | %d belt sections not built (not enough credits)", R.SectionsNoFunds) end
    if R.ModulesFailed > 0 then S = S .. string.format(" | %d modules blocked (%s)", R.ModulesFailed, R.Errors[1] or "?") end
    if R.BeltCellsBlocked > 0 then S = S .. string.format(" | %d belt cells blocked", R.BeltCellsBlocked) end
    if R.UndergroundsFailed > 0 then S = S .. string.format(" | %d undergrounds blocked", R.UndergroundsFailed) end
    if R.DistributorsMissing > 0 then S = S .. string.format(" | %d distributors not recreated", R.DistributorsMissing) end
    if R.SettingsMismatches > 0 then S = S .. string.format(" | %d settings not applied", R.SettingsMismatches) end
    return S
end

return Placer
