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

-- Direction after mirroring rows (dRow -> -dRow): Up <-> Down, Left / Right unchanged.
function Grid.MirrorDir(Dir)
    return Dir % 2 == 0 and (Dir + 2) % 4 or Dir
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

-- Converts a contiguous belt path into chained BuildHolo calls.
-- Verified in game: separate BuildHolo calls are NOT connected, even when adjacent, unless the next
-- call starts ON the last cell of the previous one; the game then skips that shared cell and links
-- both sections (also around a turn). BuildHolo draws a straight line or an L (Vertical = first leg
-- along rows), so each piece covers two turns' worth of path: P(j) -> corner P(j+1) -> P(j+2),
-- the next piece starting on P(j+2).
-- Path entries may carry their true outgoing direction as [3] (from the source section);
-- otherwise it is derived from the next cell, the last cell reusing the previous direction.
-- Returns pieces { Start = {R, C}, End = {R, C}, Vertical = bool, Chained = bool }.
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

    -- Polyline points: path start, every turning cell, path end.
    local Points = { 1 }
    for i = 2, N do
        if Dirs[i] ~= Dirs[i - 1] then Points[#Points + 1] = i end
    end
    if Points[#Points] ~= N then Points[#Points + 1] = N end

    if #Points == 1 then
        return { { Start = Path[1], End = Path[1], Vertical = IsVertical(Dirs[1]), Chained = false } }
    end

    local Pieces, j = {}, 1
    while j < #Points do
        local Last = math.min(j + 2, #Points)
        local A = Points[j]
        Pieces[#Pieces + 1] = {
            Start = Path[A],
            End = Path[Points[Last]],
            Vertical = IsVertical(Dirs[A]),
            Chained = j > 1,
        }
        j = Last
    end
    return Pieces
end
return Grid
