-- =============================================================================
-- Mod: AutoUnderground
-- Description: A belt dragged across existing belts goes under them: each crossing becomes an
--              underground belt pair instead of the vanilla red "blocked" path that builds nothing.
-- =============================================================================

local ManagerClass = "/Game/Blueprints/Conveyors/BP_ConveyorManager.BP_ConveyorManager_C"
local VisualPath = ManagerClass .. ":ConstructHoverSectionPathVisual"
local HoverPath = "/Script/TheCrust.ConveyorManager:OnHover"
local ClickPath = "/Script/TheCrust.ConveyorManager:MainPointerAction"

local GridSize = 400
local ModeBelt, ModeUnderground = 1, 3
-- ECDirection: 0 Up (-Row), 1 Right (+Col), 2 Down (+Row), 3 Left (-Col)
local DirDelta = { [0] = { -1, 0 }, [1] = { 0, 1 }, [2] = { 1, 0 }, [3] = { 0, -1 } }

local Busy = false   -- our own conveyor calls re-enter the hooks
local Visual = nil   -- arguments of the last hover path visual drawn by vanilla
local Current = nil  -- plan of the path currently hovered
local Pending = nil  -- plan to build after the vanilla click

local function Valid(Object)
    return type(Object) == "userdata" and Object:IsValid()
end

local function ToRowCol(Cell) return Cell // GridSize, Cell % GridSize end

-- World geometry of the layer grid (cell centers are integers in Row / Col space).
local function Geometry(CM)
    local Mid = GridSize // 2
    local A, B = {}, {}
    CM:GetGridLocationByCellID(A, Mid * GridSize + Mid)
    CM:GetGridLocationByCellID(B, (Mid + 1) * GridSize + Mid + 1)
    local LA, LB = A.OutLocation or A, B.OutLocation or B
    local Size = LB.X - LA.X
    return { Size = Size, X = LA.X - (Mid + 0.5) * Size, Y = LA.Y - (Mid + 0.5) * Size, Z = LA.Z }
end

local function CellAt(Geo, X, Y)
    return math.floor((X - Geo.X) / Geo.Size) * GridSize + math.floor((Y - Geo.Y) / Geo.Size)
end

local function Location(Geo, Cell)
    local Row, Col = ToRowCol(Cell)
    return { X = Geo.X + (Row + 0.5) * Geo.Size, Y = Geo.Y + (Col + 0.5) * Geo.Size, Z = Geo.Z }
end

local function Direction(From, To)
    local R1, C1 = ToRowCol(From)
    local R2, C2 = ToRowCol(To)
    for Dir, D in pairs(DirDelta) do
        if R2 - R1 == D[1] and C2 - C1 == D[2] then return Dir end
    end
end

local function HasBelt(CM, Cell)
    return Valid(CM.SectionGrid:GetSectionAtCellID_Safe(Cell))
        or Valid(CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell))
end

local function HoloAt(CM, Cell)
    local S = CM.HoloSectionGrid:GetSectionAtCellID_Safe(Cell)
    if Valid(S) then return S end
end

-- Copies the visual arguments: the TArray only lives during the call. Blueprint hooks run after
-- the function.
local function OnVisual(Context, Points, Fail, IOAtStart, IOAtEnd)
    local Copy = {}
    Points:get():ForEach(function(_, V)
        local T = V:get()
        local L, R, S = T.Translation, T.Rotation, T.Scale3D
        Copy[#Copy + 1] = {
            Rotation = { X = R.X, Y = R.Y, Z = R.Z, W = R.W },
            Translation = { X = L.X, Y = L.Y, Z = L.Z },
            Scale3D = { X = S.X, Y = S.Y, Z = S.Z },
        }
    end)
    Visual = { Points = Copy, Fail = Fail:get(), IOAtStart = IOAtStart:get(), IOAtEnd = IOAtEnd:get() }
end

-- Vanilla only reports the first blocked cell of a path. Validates the rest from Start (1-based index
-- into Cells) with a vanilla hover of that sub-path, then restores the hover state so vanilla does
-- not see a cursor change and redraw every frame. Returns the first blocked index, nil if none,
-- false if the sub-path differs from the original one.
local function SubPathFailure(CM, Geo, Cells, Start)
    local C = CM.Controller
    local Saved = {
        First = C:GetFirstClickCellID(),
        HoverStart = CM.LastHoverStartCellID,
        HoverEnd = CM.LastHoverEndCellID,
        Cost = CM.LastSectionPathBuildCost,
        Vertical = CM.LastIsVertical,
    }
    Visual = nil
    C:SetFirstClickCellID(Cells[Start])
    CM:OnHover(Location(Geo, Cells[#Cells]))
    C:SetFirstClickCellID(Saved.First)
    CM.LastHoverStartCellID, CM.LastHoverEndCellID = Saved.HoverStart, Saved.HoverEnd
    CM.LastSectionPathBuildCost, CM.LastIsVertical = Saved.Cost, Saved.Vertical

    local V = Visual
    Visual = nil
    if not V or #V.Points ~= #Cells - Start + 1 then return false end
    for i, P in ipairs(V.Points) do
        if CellAt(Geo, P.Translation.X, P.Translation.Y) ~= Cells[Start + i - 1] then return false end
    end
    if V.Fail < 0 then return nil end
    return Start + V.Fail
end

-- Turns a blocked path into underground crossings. Each blocked run must be belts only, straight,
-- with free entry / exit cells at most UndergroundBuildSectionLength apart. Returns nil when the
-- path cannot be bridged (vanilla stays in charge).
local function MakePlan(CM, Geo, V)
    if V.Fail < 1 or not CM.bUndergroundBeltUnlocked then return nil end
    local Cells = {}
    for i, P in ipairs(V.Points) do Cells[i] = CellAt(Geo, P.Translation.X, P.Translation.Y) end
    local N, MaxLength = #Cells, CM.UndergroundBuildSectionLength

    local Crossings, Tunneled = {}, {}
    local Start, Blocked = 1, V.Fail + 1
    while Blocked do
        if not HasBelt(CM, Cells[Blocked]) then return nil end
        local Last = Blocked
        while Last < N and HasBelt(CM, Cells[Last + 1]) do Last = Last + 1 end
        local Entry, Exit = Blocked - 1, Last + 1
        -- The start cell is the previous exit, or the path start (may itself be a belt to continue)
        if Exit > N or Entry < Start or (Entry == Start and (Start > 1 or HasBelt(CM, Cells[1]))) then
            return nil
        end
        local Dir = Direction(Cells[Entry], Cells[Entry + 1])
        for i = Entry + 1, Exit do
            if Direction(Cells[i - 1], Cells[i]) ~= Dir then return nil end
        end
        if Exit - Entry > MaxLength then return nil end
        Crossings[#Crossings + 1] = { Entry = Entry, Exit = Exit, Dir = Dir }
        for i = Blocked, Last do Tunneled[i] = true end

        Start = Exit
        if Start == N then break end
        Blocked = SubPathFailure(CM, Geo, Cells, Start)
        if Blocked == false then return nil end
    end
    return { CM = CM, Geo = Geo, Cells = Cells, Crossings = Crossings, Tunneled = Tunneled, Visual = V }
end

-- Vanilla preview without the red failure part and without cubes over the tunneled cells.
local function DrawPlan(Plan)
    local Points = {}
    for i, P in ipairs(Plan.Visual.Points) do
        if not Plan.Tunneled[i] then Points[#Points + 1] = P end
    end
    Plan.CM:ClearHoverSectionPathVisual()
    Plan.CM:ConstructHoverSectionPathVisual(Points, -1, Plan.Visual.IOAtStart, Plan.Visual.IOAtEnd)
end

-- Underground pair through the vanilla tool (same sequence as the Blueprints mod): direction,
-- click the entry, click the exit, restore the tool state.
local function PlaceUnderground(CM, Geo, Entry, Exit, Dir)
    local C = CM.Controller
    local PrevMode, PrevDir = CM:GetConveyorMode(), C:GetUndergroundBeltDirection()
    local function Rotate(To)
        for _ = 1, 4 do
            if C:GetUndergroundBeltDirection() == To then return end
            CM:RotateUndergroundBelt(false)
        end
    end
    CM:SetConveyorMode(ModeUnderground)
    C:ResetClickCellIDs()
    Rotate(Dir)
    local Ok, Err = pcall(function()
        CM:MainPointerAction(Location(Geo, Entry))
        CM:MainPointerAction(Location(Geo, Exit))
    end)
    C:ResetClickCellIDs()
    Rotate(PrevDir)
    CM:SetConveyorMode(PrevMode)
    if not Ok then error(Err) end
    local S = HoloAt(CM, Entry)
    return S ~= nil and S:GetSectionType() == 3 and S.State.ConnectedUndergroundBeltCellID == Exit
end

local function IsVertical(Dir) return Dir == 0 or Dir == 2 end

-- Underground pairs first, then the belts between them: a belt ending on an entry or starting on an
-- exit links to it. BuildHolo draws a straight line or an L (Vertical = first leg along rows), which
-- covers any part of a vanilla path.
local function BuildPlan(Plan)
    local CM, Geo, Cells = Plan.CM, Plan.Geo, Plan.Cells
    for _, X in ipairs(Plan.Crossings) do
        if HasBelt(CM, Cells[X.Entry]) or HasBelt(CM, Cells[X.Exit]) then return end
    end
    local Empty = {}
    for i, Cell in ipairs(Cells) do
        if not Plan.Tunneled[i] and not HasBelt(CM, Cell) then Empty[#Empty + 1] = Cell end
    end

    local Ok = true
    for _, X in ipairs(Plan.Crossings) do
        Ok = PlaceUnderground(CM, Geo, Cells[X.Entry], Cells[X.Exit], X.Dir)
        if not Ok then break end
    end
    if Ok then
        local From = 1
        local function Segment(To)
            if To > From then
                local Dir = Direction(Cells[From], Cells[From + 1])
                CM:BuildHolo(Cells[From], Cells[To], IsVertical(Dir), false, -1)
            end
        end
        for _, X in ipairs(Plan.Crossings) do
            Segment(X.Entry)
            From = X.Exit
        end
        Segment(#Cells)
        for _, Cell in ipairs(Empty) do
            if not HoloAt(CM, Cell) then Ok = false end
        end
    end

    if not Ok then
        -- Remove what this click created (modules or unexcavated ground on the path)
        for _, Cell in ipairs(Empty) do
            if HoloAt(CM, Cell) then CM:DeleteHoloSectionAtCellID(Cell) end
        end
        print("[AutoUnderground] Path could not be built, nothing placed\n")
    end
    CM:UpdateHoloSectionCosts()
end

local function Guarded(Fn, ...)
    if Busy then return end
    Busy = true
    local Ok, Err = pcall(Fn, ...)
    Busy = false
    if not Ok then
        Current, Pending = nil, nil
        print("[AutoUnderground] " .. tostring(Err) .. "\n")
    end
end

-- Vanilla only redraws the hover path when the cursor cell changes: plan on each new visual.
RegisterHook(HoverPath, function() end, function(Context)
    Guarded(function()
        local V = Visual
        Visual = nil
        if not V then return end
        local CM = Context:get()
        Current = nil
        if CM:GetConveyorMode() ~= ModeBelt then return end
        Current = MakePlan(CM, Geometry(CM), V)
        if Current then
            DrawPlan(Current)
            Visual = nil -- our own redraw, not a new vanilla path
        end
    end)
end)

-- A blocked second click builds nothing in vanilla (and resets the first click): build the plan
-- afterwards if the click is on the planned end cell.
RegisterHook(ClickPath, function(Context, Loc)
    Guarded(function()
        Pending = nil
        local CM = Context:get()
        local Plan = Current
        if not Plan or CM:GetConveyorMode() ~= ModeBelt then return end
        if Plan.CM:GetAddress() ~= CM:GetAddress() then return end
        local L = Loc:get()
        if CM.Controller:GetFirstClickCellID() == Plan.Cells[1]
            and CellAt(Plan.Geo, L.X, L.Y) == Plan.Cells[#Plan.Cells] then
            Pending = Plan
        end
    end)
end, function()
    Guarded(function()
        local Plan = Pending
        Pending, Current = nil, nil
        if Plan then BuildPlan(Plan) end
    end)
end)

local VisualHooked = false
local function HookVisual()
    if VisualHooked then return end
    -- RegisterHook needs the Blueprint class loaded
    if not Valid(StaticFindObject(ManagerClass)) then
        pcall(LoadAsset, (ManagerClass:gsub("%.[^%.]+$", "")))
    end
    VisualHooked = pcall(RegisterHook, VisualPath, OnVisual)
end

HookVisual()
RegisterInitGameStatePostHook(HookVisual)
print("[AutoUnderground] Loaded\n")
