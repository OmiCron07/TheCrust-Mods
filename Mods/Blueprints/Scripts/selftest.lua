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

-- Deflate: round trips, RFC vectors produced by zlib (fixed Huffman, stored), hostile streams.
local Deflate = require("deflate")
local Seed, Noise = 12345, {}
for i = 1, 65536 do
    Seed = (Seed * 1103515245 + 12345) % 2147483648
    Noise[i] = string.char(Seed >> 16 & 255)
end
for _, S in ipairs({ "", "a", table.concat(Noise), string.rep("abc", 5000) .. "end" }) do
    assert(Deflate.Inflate(Deflate.Compress(S), 1e6) == S, "deflate round trip " .. #S)
end
local function Hex(H) return (H:gsub("%x%x", function(X) return string.char(tonumber(X, 16)) end)) end
local Vector = string.rep("TCBP fixed vector: abcabcabcabc, hello hello hello hello! 0123456789", 3)
assert(Deflate.Inflate(Hex("0b71760a5048cbac484d51284b4d2ec92fb252484c4a86231d858cd49c9c7c4c5251c1c0d0c8d8c4d4ccdcc2326490980100"), 1e6) == Vector, "zlib fixed vector")
assert(Deflate.Inflate(Hex("010700f8ff73746f72656421"), 1e6) == "stored!", "zlib stored vector")
local function Fails(F, ...) return not pcall(F, ...) end
assert(Fails(Deflate.Inflate, Deflate.Compress(string.rep("a", 5000)), 1000), "output cap")
assert(Fails(Deflate.Inflate, "\5\0\0", 1e6), "dynamic block rejected")
assert(Fails(Deflate.Inflate, Deflate.Compress("hello world"):sub(1, 4), 1e6), "truncated stream")
-- Fixed block (bits 1, 01) whose first symbol is 257 = length 3 (code 0000001, bits 3-9), distance 1.
assert(Fails(Deflate.Inflate, string.char(0x03, 0x02, 0x00), 1e6), "distance before start")

-- Share strings: lossless round trip of every field, footprint dedup, hostile strings.
local Share = require("share")
local Big = "/Game/Blueprints/Modules/Category/05_Storage/BigBulkStorage/MB_BigBulkStorage.MB_BigBulkStorage_C"
local Full = {
    Name = "Share \"test\"", Layer = 2, Summary = "x", Created = "y", Skipped = 1,
    Modules = {
        { Class = Big, DR = -1.5, DC = 2, Turns = 1, Mirrored = true, Recipe = "APS_X", Cells = { { -2, 2 }, { -1, 2 } },
            IO = { { Agency = "SAI_prodInput", Filter = { 3, 4 }, Lock = true, Overflow = false }, false } },
        { Class = Big, DR = 4.5, DC = -3, Turns = 1, Mirrored = true, Recipe = "", Cells = { { 4, -3 }, { 5, -3 } } },
        { Class = "/Game/Mods/Odd.OtherName_C", DR = 0, DC = 0, Turns = 0, Mirrored = false, Recipe = "", Cells = { { 0, 0 } } },
    },
    Belts = {
        { { 0, 0, 1 }, { 0, 1, 2 }, { 1, 1, 2 } },
        { { 5, 5, 1 }, { 6, 5, 2 } },   -- corner cell: direction differs from the move
        { { 0, 0, 1 }, { 0, 3, 1 } },   -- non-adjacent step -> flat form
        { { 2, 2 }, { 2, 3, 1 } },      -- missing direction -> flat form
    },
    Undergrounds = { { { 3, 0 }, { 5, 0 }, 2 } },
    Links = { { 1, 2 }, { 2, 3 } },
    Distributors = { { DR = 2, DC = -1, Inputs = { { Dir = 1, Level = 0 } },
        Outputs = { { Dir = 0, Level = 2, Types = { 5 }, Priority = true, Locked = false, HandTuned = true, Blocked = false } } } },
}
local function Same(A, B, Where)
    if type(A) ~= "table" or type(B) ~= "table" then
        assert(A == B, Where .. ": " .. tostring(A) .. " ~= " .. tostring(B))
        return
    end
    for K, V in pairs(A) do Same(V, B[K], Where .. "." .. tostring(K)) end
    for K in pairs(B) do assert(A[K] ~= nil, Where .. "." .. tostring(K) .. " unexpected") end
end
local function Shared(BP)
    local T = {}
    for K, V in pairs(BP) do if K ~= "Summary" and K ~= "Created" and K ~= "Skipped" then T[K] = V end end
    T.Undergrounds, T.Distributors = T.Undergrounds or {}, T.Distributors or {}
    return T
end
local Str = Share.Encode(Full)
assert(Str:match("^TCBP1:[%w%-_]+$"), "share string alphabet")
local Back, Err = Share.Decode(" \n" .. Str:sub(1, 20) .. "\n" .. Str:sub(21) .. "  ")
assert(Back, Err)
Same(Shared(Full), Back, "share")
assert(Share.ToPayload(Full)[4][2][7] == 0, "same footprint must be deduplicated")

local function Payload() return Share.ToPayload(Full) end
local function Packed(P) return Share.Pack(Storage.Serialize(P, nil, true)) end
local Hostile = {
    "hello", "TCBP2:AAAA", Share.Prefix .. "A", Share.Prefix .. "ab!d", Str:sub(1, -10),
    Share.Prefix .. string.rep("A", 300000),
    Share.Pack("{(function() end)()}"), Share.Pack("while true do end"), Share.Pack("os.exit()"),
    Share.Pack("[[x]]"), Share.Pack("{1}--x"), Share.Pack("{{{{{{{1}}}}}}}"), Share.Pack("{\"" .. string.rep("x", 300) .. "\"}"),
}
local Mutations = {
    function(P) P[3][1] = "../../Engine/X" end,
    function(P) P[3][1] = "/Game/X" end,
    function(P) P[4][1][1] = 99 end,
    function(P) P[4][1][4] = 4 end,
    function(P) P[4][1][2] = 0.25 end,
    function(P) P[4][1][7] = 0 end,          -- footprint reference before any explicit footprint
    function(P) P[5][1][3] = "aq" end,
    function(P) P[7][1] = 0 end,
    function(P) P[7] = { 1, 1 } end,
    function(P) P[2] = 1 end,
    function(P) P[8][1][3][1][1] = 7 end,
    function(P) P[6][1] = { 1, 2, 3 } end,
    function(P) P[4][1][8][1][1] = "x y" end,
}
for _, M in ipairs(Mutations) do
    local P = Payload()
    M(P)
    Hostile[#Hostile + 1] = Packed(P)
end
for i, S in ipairs(Hostile) do
    local BP, Why = Share.Decode(S)
    assert(BP == nil and type(Why) == "string", "hostile share string " .. i .. " accepted")
end

-- Optional: the real library (set BLUEPRINTS_LIBRARY to library.lua) round-trips; prints sizes.
local LibraryPath = os.getenv("BLUEPRINTS_LIBRARY")
if LibraryPath then
    for _, BP in ipairs(Storage.Load(LibraryPath)) do
        local S = Share.Encode(BP)
        Same(Shared(BP), assert(Share.Decode(S)), BP.Name)
        print(string.format("  %-30s %6d chars", BP.Name, #S))
    end
end

print("selftest OK")
