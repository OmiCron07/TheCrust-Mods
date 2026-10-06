-- Captures the elements inside a cell rectangle into a blueprint (plain Lua data).
--
-- Blueprint format (all offsets are in cells, relative to the origin cell = rectangle center):
--   Layer    : CurrentGameLayer the blueprint was taken on (0 underground, 2 crater)
--   Modules  : { Class, DR, DC (actor location, may be x.5), Turns (yaw / 90), Mirrored,
--                Recipe (APS ability name, "" if none), Cells = {{dr, dc}, ...} }
--   Belts    : array of paths, each path = array of {dr, dc, dir} in flow order (dir = ECDirection);
--              a path starts on the cell feeding it and ends on the distributor or underground
--              entry it feeds, if any
--   Undergrounds : { {dr, dc} entry, {dr, dc} exit, Dir } underground belt pairs (Dir = flow)
--   Links    : { A, B } indices into Modules joined by an electric wire
--   Distributors : { DR, DC, Outputs, Inputs } settings of each distributor (see settings.lua);
--              modules also carry IO = IO cell settings
--   Skipped  : count of conveyor parts not copied (underground pairs cut by the selection)

local Grid = require("grid")
local Game = require("game")
local Settings = require("settings")

local Capture = {}

local BeltLine = 1
local Distributor = 2
local Underground = 3

local function ArrayToTable(Arr)
    local T = {}
    Arr:ForEach(function(_, V) T[#T + 1] = V:get() end)
    return T
end

local function Round(X)
    return math.floor(X + 0.5)
end

local function RoundHalf(X)
    return math.floor(X * 2 + 0.5) / 2
end

local function CaptureModules(Rect, OR, OC, Geo, Layer)
    local Modules, ById = {}, {}
    for _, M in ipairs(Game.LayerModules(Layer)) do
        local Loc = M:K2_GetActorLocation()
        local Row, Col = Game.WorldToRowCol(Geo, Loc.X, Loc.Y)
        if Rect.Contains(Round(Row), Round(Col)) and Game.IsCopyAllowed(M) and not M.IsFromPackage then
            local Cells = {}
            for _, Cell in ipairs(Game.ModuleCells(M)) do
                local R, C = Grid.ToRowCol(Cell)
                Cells[#Cells + 1] = { R - OR, C - OC }
            end
            Modules[#Modules + 1] = {
                Class = Game.ClassPath(M),
                DR = RoundHalf(Row) - OR,
                DC = RoundHalf(Col) - OC,
                Turns = Round(M:K2_GetActorRotation().Yaw / 90) % 4,
                Mirrored = M.IsMirrored == true,
                Recipe = Game.ModuleRecipe(M),
                Cells = Cells,
                IO = Settings.CaptureIO(M),
            }
            ById[M["Module ID"]] = #Modules
        end
    end
    return Modules, ById
end

-- Separate BuildHolo calls only connect when one starts or ends on a cell of an existing section, and
-- distributors are created that way too (a belt starting or ending on another belt's middle cell),
-- so they are not stored: a path fed by a captured section starts on that cell, and a path feeding a
-- distributor or underground entry ends on its cell. Underground pairs are placed before the belts.
local function CaptureBelts(CM, Rect, OR, OC)
    local Belts, Skipped, Distributors, Undergrounds = {}, 0, {}, {}
    CM:UpdateSectionStates()

    local Kinds, UndergroundStates = {}, {}
    local function FindCells(States)
        States:ForEach(function(_, E)
            local S = E:get()
            if S.Type == Underground then UndergroundStates[S.CellIds[1]] = S end
            if S.Type == BeltLine or S.Type == Distributor or S.Type == Underground then
                for _, Cell in ipairs(ArrayToTable(S.CellIds)) do
                    if Rect.Contains(Grid.ToRowCol(Cell)) then
                        Kinds[Cell] = S.Type
                        if S.Type == Distributor then
                            local Section = CM.SectionGrid:GetSectionAtCellID_Safe(Cell)
                            if not Game.Valid(Section) then Section = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell) end
                            if Game.Valid(Section) then
                                local R, C = Grid.ToRowCol(Cell)
                                local D = Settings.CaptureDistributor(Section)
                                D.DR, D.DC = R - OR, C - OC
                                Distributors[#Distributors + 1] = D
                            end
                        end
                    end
                end
            end
        end)
    end
    FindCells(CM.BuiltSectionStates)
    FindCells(CM.HoloSectionStates)

    local function CellAmong(Arr, NotBelt)
        for _, Cell in ipairs(ArrayToTable(Arr)) do
            if Kinds[Cell] and not (NotBelt and Kinds[Cell] == BeltLine) then return Cell end
        end
    end

    -- Distributor / underground end feeding an adjacent distributor / underground entry: two-cell
    -- path, drawn once both exist.
    local Bridges = {}

    local function Visit(States)
        States:ForEach(function(_, E)
            local S = E:get()
            local Cells = ArrayToTable(S.CellIds)
            local Inside = false
            for _, Cell in ipairs(Cells) do
                if Rect.Contains(Grid.ToRowCol(Cell)) then Inside = true break end
            end
            if not Inside then return end
            if S.Type == Underground then
                -- Both ends of a pair look the same (each line direction points at the other end);
                -- the flow is given by the connections: the entry has inputs, the exit outputs.
                -- An unconnected pair is kept as found from its lower cell.
                local Cell, Other = Cells[1], S.ConnectedUndergroundBeltCellID
                local IsEntry = S.InputToSectionCells:GetArrayNum() > 0
                local IsExit = S.OutputFromSectionCells:GetArrayNum() > 0
                local OtherState = UndergroundStates[Other]
                local OtherEntry = OtherState and OtherState.InputToSectionCells:GetArrayNum() > 0
                local OtherExit = OtherState and OtherState.OutputFromSectionCells:GetArrayNum() > 0
                local Entry = IsEntry or OtherExit or (not (IsExit or OtherEntry) and Cell < Other)
                if Other >= 0 and Entry then
                    local R, C = Grid.ToRowCol(Cell)
                    local R2, C2 = Grid.ToRowCol(Other)
                    if Rect.Contains(R, C) and Rect.Contains(R2, C2) then
                        local Dir = (R2 == R) and (C2 > C and 1 or 3) or (R2 > R and 2 or 0)
                        Undergrounds[#Undergrounds + 1] = { { R - OR, C - OC }, { R2 - OR, C2 - OC }, Dir }
                    else
                        Skipped = Skipped + 1
                    end
                end
            end
            if S.Type == Distributor or S.Type == Underground then
                local R, C = Grid.ToRowCol(Cells[1])
                for _, To in ipairs(ArrayToTable(S.OutputFromSectionCells)) do
                    if Kinds[To] == Distributor or Kinds[To] == Underground then
                        local R2, C2 = Grid.ToRowCol(To)
                        local Dir = Grid.DirectionBetween(R, C, R2, C2)
                        Bridges[#Bridges + 1] = { { R - OR, C - OC, Dir }, { R2 - OR, C2 - OC, Dir } }
                    end
                end
                return
            end
            if S.Type ~= BeltLine then
                Skipped = Skipped + 1
                return
            end

            local LineDirs = ArrayToTable(S.LineDirections)
            local Path = {}
            local From = CellAmong(S.InputToSectionCells)
            if From and Rect.Contains(Grid.ToRowCol(Cells[1])) then
                local R, C = Grid.ToRowCol(From)
                Path[1] = { R - OR, C - OC, Grid.DirectionBetween(R, C, Grid.ToRowCol(Cells[1])) }
            end
            for i, Cell in ipairs(Cells) do
                local R, C = Grid.ToRowCol(Cell)
                local Dir
                if Cells[i + 1] then
                    Dir = Grid.DirectionBetween(R, C, Grid.ToRowCol(Cells[i + 1]))
                end
                Dir = Dir or LineDirs[#LineDirs]
                if Rect.Contains(R, C) then
                    Path[#Path + 1] = { R - OR, C - OC, Dir }
                elseif #Path > 0 then
                    Belts[#Belts + 1] = Path
                    Path = {}
                end
            end
            if #Path > 0 then
                -- Path still open: it reaches the section's last cell.
                local To = CellAmong(S.OutputFromSectionCells, true)
                if To then
                    local R, C = Grid.ToRowCol(To)
                    local Last = Path[#Path]
                    Path[#Path + 1] = { R - OR, C - OC, Grid.DirectionBetween(Last[1], Last[2], R - OR, C - OC) }
                end
                Belts[#Belts + 1] = Path
            end
        end)
    end

    Visit(CM.BuiltSectionStates)
    Visit(CM.HoloSectionStates)
    for _, Path in ipairs(Bridges) do Belts[#Belts + 1] = Path end
    return Belts, Skipped, Distributors, Undergrounds
end

local LinkStart = "StartNode_7_A30BB1064830FC46F18094A082539283"
local LinkEnd = "EndNode_8_6B7685514510C82E9E33C09259213BF9"
local LinkDead = "isDead_14_A791E9CB4F8DE716DEC7289DF0502AAE"

local function CaptureLinks(PC, ById)
    local Links = {}
    local EM = Game.Level(PC).ElectricManager
    if not Game.Valid(EM) then return Links end

    local NodeModule = {}
    EM.AllNodesCPP:ForEach(function(_, E)
        local N = E:get()
        NodeModule[N.NodeID] = N.ModuleId
    end)

    local Seen = {}
    EM.AllLinks:ForEach(function(_, E)
        local L = E:get()
        if L[LinkDead] then return end
        local A = ById[NodeModule[L[LinkStart]] or -1]
        local B = ById[NodeModule[L[LinkEnd]] or -1]
        if A and B and A ~= B then
            local Key = math.min(A, B) .. ":" .. math.max(A, B)
            if not Seen[Key] then
                Seen[Key] = true
                Links[#Links + 1] = { A, B }
            end
        end
    end)
    return Links
end

-- Rect = { R0, C0, R1, C1 } inclusive (any corner order). Returns blueprint or nil, error.
function Capture.FromRect(PC, Layer, R0, C0, R1, C1)
    local CM = Game.ConveyorManager(PC, Layer)
    if not Game.Valid(CM) then return nil, "No conveyor manager on this layer" end

    local MinR, MaxR = math.min(R0, R1), math.max(R0, R1)
    local MinC, MaxC = math.min(C0, C1), math.max(C0, C1)
    local Rect = {
        Contains = function(R, C) return R >= MinR and R <= MaxR and C >= MinC and C <= MaxC end,
    }
    local OR, OC = (MinR + MaxR) // 2, (MinC + MaxC) // 2

    local Geo = Game.Geometry(CM)
    local Modules, ById = CaptureModules(Rect, OR, OC, Geo, Layer)
    local Belts, Skipped, Distributors, Undergrounds = CaptureBelts(CM, Rect, OR, OC)
    local Links = CaptureLinks(PC, ById)

    return {
        Layer = Layer,
        Modules = Modules,
        Belts = Belts,
        Links = Links,
        Distributors = Distributors,
        Undergrounds = Undergrounds,
        Skipped = Skipped,
    }
end

function Capture.Summary(BP)
    local Cells = 0
    for _, P in ipairs(BP.Belts) do Cells = Cells + #P end
    local S = string.format("%d modules, %d belt cells, %d distributors, %d undergrounds, %d wires",
        #BP.Modules, Cells, #(BP.Distributors or {}), #(BP.Undergrounds or {}), #BP.Links)
    if (BP.Skipped or 0) > 0 then
        S = S .. string.format(" (%d underground belts cut by the selection, not copied)", BP.Skipped)
    end
    return S
end

function Capture.IsEmpty(BP)
    return #BP.Modules == 0 and #BP.Belts == 0
end

return Capture
