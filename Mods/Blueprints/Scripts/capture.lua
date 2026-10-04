-- Captures the elements inside a cell rectangle into a blueprint (plain Lua data).
--
-- Blueprint format (all offsets are in cells, relative to the origin cell = rectangle center):
--   Layer    : CurrentGameLayer the blueprint was taken on (0 underground, 2 crater)
--   Modules  : { Class, DR, DC (actor location, may be x.5), Turns (yaw / 90), Mirrored, Cells = {{dr, dc}, ...} }
--   Belts    : array of paths, each path = array of {dr, dc, dir} in flow order (dir = ECDirection)
--   Links    : { A, B } indices into Modules joined by an electric wire
--   Skipped  : count of unsupported conveyor parts (distributors, underground belts)

local Grid = require("grid")
local Game = require("game")

local Capture = {}

local BeltLine = 1

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
                Cells = Cells,
            }
            ById[M["Module ID"]] = #Modules
        end
    end
    return Modules, ById
end

local function CaptureBelts(CM, Rect, OR, OC)
    local Belts, Skipped = {}, 0
    CM:UpdateSectionStates()

    local function Visit(States)
        States:ForEach(function(_, E)
            local S = E:get()
            local Cells = ArrayToTable(S.CellIds)
            local Inside = false
            for _, Cell in ipairs(Cells) do
                if Rect.Contains(Grid.ToRowCol(Cell)) then Inside = true break end
            end
            if not Inside then return end
            if S.Type ~= BeltLine then
                Skipped = Skipped + 1
                return
            end

            local LineDirs = ArrayToTable(S.LineDirections)
            local Path = {}
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
            if #Path > 0 then Belts[#Belts + 1] = Path end
        end)
    end

    Visit(CM.BuiltSectionStates)
    Visit(CM.HoloSectionStates)
    return Belts, Skipped
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
    local Belts, Skipped = CaptureBelts(CM, Rect, OR, OC)
    local Links = CaptureLinks(PC, ById)

    return {
        Layer = Layer,
        Modules = Modules,
        Belts = Belts,
        Links = Links,
        Skipped = Skipped,
    }
end

function Capture.Summary(BP)
    local Cells = 0
    for _, P in ipairs(BP.Belts) do Cells = Cells + #P end
    local S = string.format("%d modules, %d belt cells, %d wires", #BP.Modules, Cells, #BP.Links)
    if (BP.Skipped or 0) > 0 then
        S = S .. string.format(" (%d distributor/underground parts not supported)", BP.Skipped)
    end
    return S
end

function Capture.IsEmpty(BP)
    return #BP.Modules == 0 and #BP.Belts == 0
end

return Capture
