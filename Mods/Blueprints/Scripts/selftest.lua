-- Self-check for the pure modules (grid math, belt decomposition, serialization).
-- Runs outside the game with any Lua 5.4: package.path must include this Scripts folder.
local Grid = require("grid")
local Storage = require("storage")

-- Simulates BuildHolo(start, end, vertical) on a fresh grid: returns the produced cells with directions.
local function SimulateHolo(Pieces)
    local Out = {}
    local function Walk(R, C, ToR, ToC, AlongRowFirst)
        local Cells = { { R, C } }
        local function Step(DR, DC, Steps)
            for _ = 1, Steps do
                R, C = R + DR, C + DC
                Cells[#Cells + 1] = { R, C }
            end
        end
        local function Sign(X) return X > 0 and 1 or (X < 0 and -1 or 0) end
        if AlongRowFirst then
            Step(Sign(ToR - R), 0, math.abs(ToR - R)); Step(0, Sign(ToC - C), math.abs(ToC - C))
        else
            Step(0, Sign(ToC - C), math.abs(ToC - C)); Step(Sign(ToR - R), 0, math.abs(ToR - R))
        end
        return Cells
    end
    for _, P in ipairs(Pieces) do
        local Cells = Walk(P.Start[1], P.Start[2], P.End[1], P.End[2], P.Vertical)
        for i, Cell in ipairs(Cells) do
            local Next = Cells[i + 1]
            Cell[3] = Next and Grid.DirectionBetween(Cell[1], Cell[2], Next[1], Next[2]) or P.LastDir
            Out[#Out + 1] = Cell
        end
    end
    return Out
end

local function Path(Cells)
    local P = {}
    for _, Cell in ipairs(Cells) do P[#P + 1] = { Grid.ToRowCol(Cell) } end
    return P
end

-- Asserts the simulated holo reproduces the path cells and their directions (except the final cell).
local function CheckRoundTrip(Name, Cells)
    local P = Path(Cells)
    local Pieces = Grid.BeltPieces(P)
    for _, Piece in ipairs(Pieces) do Piece.LastDir = Piece.EndDir end
    local Got = SimulateHolo(Pieces)
    assert(#Got == #P, Name .. ": cell count " .. #Got .. " ~= " .. #P)
    for i = 1, #P do
        assert(Got[i][1] == P[i][1] and Got[i][2] == P[i][2], Name .. ": cell " .. i .. " differs")
        if i < #P then
            local Want = Grid.DirectionBetween(P[i][1], P[i][2], P[i + 1][1], P[i + 1][2])
            assert(Got[i][3] == Want, Name .. ": direction at cell " .. i)
        end
    end
    return #Pieces
end

-- Cell IDs and direction convention (verified in game: 72575 -> 72578 is Right, -400 is Up).
assert(Grid.Size == 400)
assert(select(1, Grid.ToRowCol(75806)) == 189 and select(2, Grid.ToRowCol(75806)) == 206)
assert(Grid.ToCell(189, 206) == 75806)
assert(Grid.DirectionBetween(0, 0, 0, 1) == 1 and Grid.DirectionBetween(1, 0, 0, 0) == 0)

-- Rotation: four quarter turns are identity, +X goes to +Y, directions follow offsets.
assert(select(1, Grid.Rotate(1, 0, 1)) == 0 and select(2, Grid.Rotate(1, 0, 1)) == 1)
local R, C = Grid.Rotate(3, -2, 4)
assert(R == 3 and C == -2)
for Dir = 0, 3 do
    for T = 0, 3 do
        local D = ({ [0] = { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } })[Dir]
        local RR, RC = Grid.Rotate(D[1], D[2], T)
        assert(Grid.DirectionBetween(0, 0, RR, RC) == Grid.RotateDir(Dir, T), "RotateDir " .. Dir .. "/" .. T)
    end
end

-- Belt decomposition against real sections captured from a save (BuiltSectionStates).
assert(CheckRoundTrip("straight", { 83787, 83786, 83785, 83784 }) == 1)
assert(CheckRoundTrip("two cells", { 80984, 80985 }) == 1)
assert(CheckRoundTrip("L", { 81755, 81754, 81753, 81353, 80953 }) == 1)
CheckRoundTrip("S", { 88206, 88205, 88204, 88203, 88202, 88201, 88200, 88199, 88198, 88197, 87797, 87397,
    86997, 86597, 86197, 85797, 85397, 84997, 84597, 84197, 83797, 83796, 83795, 83794, 83793, 83792 })
CheckRoundTrip("5 turns", { 80578, 80178, 79778, 79777, 79776, 79376, 78976, 78975, 78974, 78973, 78972, 78971,
    78970, 78969, 78968, 78967, 78966, 78965, 78964, 78963, 78962, 78961, 78960, 78959, 79359, 79759, 80159,
    80559, 80959, 81359, 81759, 81758, 81757 })
CheckRoundTrip("staircase", { 1000, 1001, 1401, 1402, 1802, 1803 })

-- Contiguity split.
local Runs = Grid.SplitContiguous({ { 0, 0 }, { 0, 1 }, { 5, 5 }, { 5, 6 } })
assert(#Runs == 2 and #Runs[1] == 2 and #Runs[2] == 2)

-- Serialization round trip.
local BP = {
    Name = "Furnace \"line\"\n2", Layer = 0, Turns = 3,
    Modules = { { Class = "/Game/X.X_C", DR = -1.5, DC = 2, Turns = 1, Mirrored = false, Cells = { { 0, 1 }, { -1, 2 } } } },
    Belts = { { { 0, 0, 1 }, { 0, 1, 1 } } },
    Links = {},
}
local Back = Storage.Deserialize(Storage.Serialize({ Blueprints = { BP } })).Blueprints[1]
assert(Back.Name == BP.Name and Back.Modules[1].DR == -1.5 and Back.Belts[1][2][2] == 1)
assert(Back.Modules[1].Mirrored == false and #Back.Links == 0)
assert(Storage.Deserialize("os.exit()") == nil, "sandbox must reject code")

print("selftest OK")
