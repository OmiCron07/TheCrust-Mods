-- Pure grid math for The Crust cell grid (no game calls; unit-tested by selftest.lua).
-- Cell ID = Row * GridSize + Col. Row grows with world X, Col grows with world Y.
-- Conveyor directions (ECDirection): 0 = Up (-Row), 1 = Right (+Col), 2 = Down (+Row), 3 = Left (-Col).

local Grid = {}

Grid.Size = 400

local DirDelta = {
    [0] = { -1, 0 },
    [1] = { 0, 1 },
    [2] = { 1, 0 },
    [3] = { 0, -1 },
}

function Grid.ToRowCol(Cell)
    return Cell // Grid.Size, Cell % Grid.Size
end

function Grid.ToCell(Row, Col)
    return Row * Grid.Size + Col
end

function Grid.InBounds(Row, Col)
    return Row >= 0 and Col >= 0 and Row < Grid.Size and Col < Grid.Size
end

-- Rotates a (Row, Col) offset by quarter turns clockwise, matching vanilla RotateModule(true) (yaw +90).
-- Yaw +90 sends world +X to +Y, so (dRow, dCol) -> (-dCol, dRow).
function Grid.Rotate(DRow, DCol, QuarterTurns)
    for _ = 1, QuarterTurns % 4 do
        DRow, DCol = -DCol, DRow
    end
    return DRow, DCol
end

-- Direction after rotating by quarter turns clockwise (Up -> Left -> Down -> Right).
function Grid.RotateDir(Dir, QuarterTurns)
    return (Dir - QuarterTurns) % 4
end

function Grid.DirectionBetween(R1, C1, R2, C2)
    local DR, DC = R2 - R1, C2 - C1
    for Dir, D in pairs(DirDelta) do
        if D[1] == DR and D[2] == DC then return Dir end
    end
    return nil
end

local function IsVertical(Dir) return Dir == 0 or Dir == 2 end

-- Splits an ordered belt path into contiguous runs of adjacent cells.
-- Path: array of { Row, Col } in flow order. Returns array of paths.
function Grid.SplitContiguous(Path)
    local Runs, Current = {}, {}
    for i, P in ipairs(Path) do
        local Prev = Path[i - 1]
        if Prev and not Grid.DirectionBetween(Prev[1], Prev[2], P[1], P[2]) then
            Runs[#Runs + 1] = Current
            Current = {}
        end
        Current[#Current + 1] = P
    end
    if #Current > 0 then Runs[#Runs + 1] = Current end
    return Runs
end

-- Converts a contiguous belt path into BuildHolo calls.
-- Each piece is { Start = {R, C}, End = {R, C}, Vertical = bool } and covers either one straight
-- segment or two perpendicular segments (an L, whose corner BuildHolo derives from Vertical).
-- A segment is a maximal run of cells sharing the same outgoing direction; the turning cell
-- belongs to the next segment (as in vanilla FCSectionState.CornerCellIDs).
-- Path entries may carry their true outgoing direction as [3] (from the source section);
-- otherwise it is derived from the next cell, the last cell reusing the previous direction.
function Grid.BeltPieces(Path)
    local N = #Path
    if N == 0 then return {} end

    local Dirs = {}
    for i = 1, N do
        local Next = Path[i + 1]
        Dirs[i] = Path[i][3]
            or (Next and Grid.DirectionBetween(Path[i][1], Path[i][2], Next[1], Next[2]))
            or Dirs[i - 1]
            or 1
    end

    local Segs = {}
    for i = 1, N do
        local Last = Segs[#Segs]
        if Last and Last.Dir == Dirs[i] then
            Last.Last = i
        else
            Segs[#Segs + 1] = { First = i, Last = i, Dir = Dirs[i] }
        end
    end

    -- Partition segments into pieces, avoiding single-cell straight pieces (their direction is ambiguous).
    -- Best[k] = true when segments k..#Segs can be partitioned; Choice[k] = 1 (straight) or 2 (L).
    local S = #Segs
    local Best, Choice = { [S + 1] = true }, {}
    for k = S, 1, -1 do
        local Len = Segs[k].Last - Segs[k].First + 1
        if k + 1 <= S and Best[k + 2] then
            Best[k], Choice[k] = true, 2
        elseif Len >= 2 and Best[k + 1] then
            Best[k], Choice[k] = true, 1
        end
    end

    local Pieces, k = {}, 1
    while k <= S do
        local Take = Choice[k] or 1 -- Fallback: ambiguous single cell, kept as straight piece.
        local A, B = Segs[k], Segs[k + Take - 1]
        Pieces[#Pieces + 1] = {
            Start = Path[A.First],
            End = Path[B.Last],
            Vertical = IsVertical(A.Dir),
            EndDir = B.Dir,
        }
        k = k + Take
    end
    return Pieces
end

return Grid
