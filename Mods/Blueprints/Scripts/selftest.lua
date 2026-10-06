-- Self-check for the pure modules (grid math, belt decomposition, serialization).
-- Runs outside the game with any Lua 5.4: package.path must include this Scripts folder.
local Grid = require("grid")
local Storage = require("storage")

-- Simulates chained BuildHolo calls as observed in game: a straight line or an L (Vertical = rows
-- first); a chained piece starts on the previous piece's last cell, which is skipped and becomes a
-- connected junction (it keeps the previous piece's direction). Returns cells and junction indices.
local function SimulateHolo(Pieces)
    local Out, Junctions = {}, {}
    local function Sign(X) return X > 0 and 1 or (X < 0 and -1 or 0) end
    for _, P in ipairs(Pieces) do
        local R, C = P.Start[1], P.Start[2]
        local Cells = { { R, C } }
        local function Step(DR, DC, Steps)
            for _ = 1, Steps do
                R, C = R + DR, C + DC
                Cells[#Cells + 1] = { R, C }
            end
        end
        local ToR, ToC = P.End[1], P.End[2]
        if P.Vertical then
            Step(Sign(ToR - R), 0, math.abs(ToR - R)); Step(0, Sign(ToC - C), math.abs(ToC - C))
        else
            Step(0, Sign(ToC - C), math.abs(ToC - C)); Step(Sign(ToR - R), 0, math.abs(ToR - R))
        end
        for i, Cell in ipairs(Cells) do
            local Next = Cells[i + 1]
            Cell[3] = Next and Grid.DirectionBetween(Cell[1], Cell[2], Next[1], Next[2]) or (Out[#Out] and Out[#Out][3])
        end
        if P.Chained then
            local Prev = Out[#Out]
            assert(Prev and Prev[1] == Cells[1][1] and Prev[2] == Cells[1][2], "chained piece must start on the previous end")
            Junctions[#Out] = true
            table.remove(Cells, 1)
        end
        for _, Cell in ipairs(Cells) do Out[#Out + 1] = Cell end
    end
    return Out, Junctions
end

local function Path(Cells)
    local P = {}
    for _, Cell in ipairs(Cells) do P[#P + 1] = { Grid.ToRowCol(Cell) } end
    return P
end

-- Asserts the simulated holo reproduces the path cells in order, each piece boundary is a chained
-- junction, and directions match everywhere except at junctions and the final cell.
local function CheckRoundTrip(Name, Cells)
    local P = Path(Cells)
    local Pieces = Grid.BeltPieces(P)
    local Got, Junctions = SimulateHolo(Pieces)
    assert(#Got == #P, Name .. ": cell count " .. #Got .. " ~= " .. #P)
    local JunctionCount = 0
    for _ in pairs(Junctions) do JunctionCount = JunctionCount + 1 end
    assert(JunctionCount == #Pieces - 1, Name .. ": every piece after the first must be chained")
    for i = 1, #P do
        assert(Got[i][1] == P[i][1] and Got[i][2] == P[i][2], Name .. ": cell " .. i .. " differs")
        if i < #P and not Junctions[i] then
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

-- Mirror: directions follow mirrored offsets; mirroring twice restores the blueprint.
for Dir = 0, 3 do
    local D = ({ [0] = { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } })[Dir]
    assert(Grid.DirectionBetween(0, 0, -D[1], D[2]) == Grid.MirrorDir(Dir), "MirrorDir " .. Dir)
end
local Capture = require("capture")
local Src = {
    Layer = 0, Links = { { 1, 1 } },
    Modules = { { Class = "X", DR = 1.5, DC = 2, Turns = 1, Mirrored = false, Cells = { { 1, 2 }, { 2, 2 } } } },
    Belts = { { { 0, 0, 2 }, { 1, 0, 1 }, { 1, 1, 1 } } },
    Undergrounds = { { { 3, 0 }, { 5, 0 }, 2 } },
    Distributors = { { DR = 2, DC = -1, Outputs = { { Dir = 0, Types = { "A" } } }, Inputs = { { Dir = 1, Level = 0 } } } },
}
local Mir = Capture.Mirror(Src)
local Mod = Mir.Modules[1]
assert(Mod.DR == -1.5 and Mod.DC == 2 and Mod.Turns == 3 and Mod.Mirrored == true and Mod.Cells[2][1] == -2)
assert(Src.Modules[1].DR == 1.5 and Src.Belts[1][1][3] == 2, "source must stay untouched")
local Path1 = Mir.Belts[1]
for i = 1, #Path1 - 1 do
    assert(Grid.DirectionBetween(Path1[i][1], Path1[i][2], Path1[i + 1][1], Path1[i + 1][2]) == Path1[i][3], "mirrored belt dir " .. i)
end
assert(Mir.Undergrounds[1][2][1] == -5 and Mir.Undergrounds[1][3] == 0)
assert(Mir.Distributors[1].DR == -2 and Mir.Distributors[1].Outputs[1].Dir == 2 and Mir.Distributors[1].Inputs[1].Dir == 1)
local Back2 = Capture.Mirror(Mir)
assert(Back2.Modules[1].DR == 1.5 and Back2.Modules[1].Turns == 1 and Back2.Modules[1].Mirrored == false)
assert(Back2.Belts[1][3][3] == 1 and Back2.Distributors[1].Outputs[1].Dir == 0 and Back2.Links == Src.Links)

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
-- Two turns, captured from a save (BeltTest): the second turn must be a chained junction.
local BeltTest = {}
for Col = 107, 98, -1 do BeltTest[#BeltTest + 1] = Grid.ToCell(104, Col) end
for Row = 103, 93, -1 do BeltTest[#BeltTest + 1] = Grid.ToCell(Row, 98) end
for Col = 97, 94, -1 do BeltTest[#BeltTest + 1] = Grid.ToCell(93, Col) end
assert(CheckRoundTrip("BeltTest", BeltTest) == 2)

-- Belt visual yaws against vanilla section visuals measured in game (key = entry > exit direction).
local Delta = { [0] = { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }
local Measured = {
    ["0>0"] = 180, ["1>1"] = 90, ["2>2"] = 0, ["3>3"] = 270,
    ["0>1"] = 180, ["0>3"] = 90, ["1>0"] = 0, ["1>2"] = 90, ["2>1"] = 270, ["2>3"] = 0, ["3>0"] = 270, ["3>2"] = 180,
}
for Key, Want in pairs(Measured) do
    local In, Out = tonumber(Key:sub(1, 1)), tonumber(Key:sub(3, 3))
    local Bp = { Belts = { { { -Delta[In][1], -Delta[In][2], In }, { 0, 0, Out }, { Delta[Out][1], Delta[Out][2], Out } } } }
    local P = Grid.BeltVisuals(Bp, 10, 10, 0)[2]
    assert(P[2] == 10 and P[3] == 10 and P[4] % 360 == Want, "belt visual " .. Key .. ": " .. P[4])
    assert(P[1] == (In == Out and Grid.VisualLine or Grid.VisualCorner), "belt visual type " .. Key)
end
local Ug = Grid.BeltVisuals({ Belts = {}, Undergrounds = { { { 0, 4 }, { 0, 0 }, 3 } } }, 0, 0, 0)
assert(Ug[1][4] % 360 == 90 and Ug[2][4] % 360 == 270, "underground yaws")
-- A quarter turn of the layout adds 90 degrees to every piece but distributors, always at yaw 0.
local Layout = { Belts = Src.Belts, Undergrounds = Src.Undergrounds, Distributors = Src.Distributors }
local A0, A1 = Grid.BeltVisuals(Layout, 50, 50, 0), Grid.BeltVisuals(Layout, 50, 50, 1)
assert(#A0 == #A1)
for i = 1, #A0 do
    local DR, DC = Grid.Rotate(A0[i][2] - 50, A0[i][3] - 50, 1)
    local Turn = A0[i][1] == Grid.VisualSplitter and 0 or 90
    assert(A1[i][2] == 50 + DR and A1[i][3] == 50 + DC and (A1[i][4] - A0[i][4] - Turn) % 360 == 0, "rotated piece " .. i)
end

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
