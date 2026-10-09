-- =============================================================================
-- Mod: BiggerMiningBrush
-- Description: Raises the max size of the mining zone brush (vanilla 3). The brush size button
--              cycles 1..MaxBrushSize. Sizes above 3 are unknown to the native brush code, so the
--              mod builds the brush cells itself (same disc shape as vanilla).
-- =============================================================================

local DefaultMax = 10

local Ok, Loaded = pcall(require, "config")
if not Ok or type(Loaded) ~= "table" then
    print("[BiggerMiningBrush] config.lua failed to load, using defaults: " .. tostring(Loaded) .. "\n")
    Loaded = {}
end

local MaxSize = math.tointeger(tonumber(Loaded.MaxBrushSize))
if MaxSize == nil or MaxSize < 1 then
    print(string.format("[BiggerMiningBrush] Invalid MaxBrushSize (%s), using %d\n", tostring(Loaded.MaxBrushSize), DefaultMax))
    MaxSize = DefaultMax
end

-- Largest size the native code handles (GetBrushCellsRaw returns only the center above it)
local NativeMax = 3

local RulerClass = "/Game/Blueprints/Ground/DigZonesQueueStuff/DigZonesQueueRuler.DigZonesQueueRuler_C"
local CellsPath = "/Script/TheCrust.DigZoneQueueRulerBase:GetBrushCellsRaw"
local PrintPath = "/Script/TheCrust.DigZoneQueueRulerBase:ApplyNewBrushPrint"

-- Vanilla brush N is a disc of radius r = N - 1 with dx^2 + dy^2 <= r^2 + max(r - 1, 0)
-- (size 2 = 5 cells, size 3 = 21 cells, matching GetBrushCellsRaw)
local Offsets = {}
local function DiscOffsets(Size)
    if Offsets[Size] then return Offsets[Size] end
    local R = Size - 1
    local List = {}
    for Dy = -R, R do
        for Dx = -R, R do
            if Dx * Dx + Dy * Dy <= R * R + math.max(R - 1, 0) then List[#List + 1] = { Dy, Dx } end
        end
    end
    Offsets[Size] = List
    return List
end

-- Cells of the brush centered on Cell, clipped to the grid (no wrap to the next row)
local function BrushCells(Ruler, Cell, Size)
    local Grid = Ruler.GridSize
    local Row, Col = Cell // Grid, Cell % Grid
    local Cells = {}
    for _, Offset in ipairs(DiscOffsets(Size)) do
        local Y, X = Row + Offset[1], Col + Offset[2]
        if Y >= 0 and Y < Grid and X >= 0 and X < Grid then Cells[#Cells + 1] = Y * Grid + X end
    end
    return Cells
end

local function Valid(Object)
    return type(Object) == "userdata" and Object:IsValid()
end

-- Native post hooks get (Context, ReturnValue, Params...). The native result above size 3 is
-- just the center cell: append the rest of the disc.
RegisterHook(CellsPath, function() end, function(Context, Result, Cell, Size)
    if Size:get() <= NativeMax then return end
    local Center = Cell:get()
    local Array = Result:get()
    for _, Other in ipairs(BrushCells(Context:get(), Center, Size:get())) do
        if Other ~= Center then Array[Array:GetArrayNum() + 1] = Other end
    end
end)

-- The native paint only applies the center above size 3 (it does not go through the hooked
-- UFunction): paint every other cell as a size 1 print into the same zone.
RegisterHook(PrintPath, function() end, function(Context, Cell, Size, UltraMode, ZoneID)
    if Size:get() <= NativeMax then return end
    local Ruler = Context:get()
    local Center, Ultra, Zone = Cell:get(), UltraMode:get(), ZoneID:get()
    for _, Other in ipairs(BrushCells(Ruler, Center, Size:get())) do
        if Other ~= Center then Ruler:ApplyNewBrushPrint(Other, 1, Ultra, Zone) end
    end
end)

-- Vanilla ToggleBrushSize maps 1->2, 2->3, 3->1 and leaves larger sizes unchanged
local function OnToggle(Context)
    local Ruler = Context:get()
    local Vanilla = Ruler.BrushSize
    local Previous = Vanilla > NativeMax and Vanilla or (Vanilla == 1 and NativeMax or Vanilla - 1)
    local Size = Previous % MaxSize + 1
    if Size == Vanilla then return end

    Ruler.BrushSize = Size
    -- The panel label was already set from the vanilla size by the BrushSizeToggled broadcast.
    -- Skip the widget tree template (no label widget).
    for _, Panel in ipairs(FindAllOf("W_MiningPanel_C") or {}) do
        if Valid(Panel) and Valid(Panel.BrushZizeLabel) then Panel:SetBrushSizeLabelText() end
    end
end

local ToggleHooked = false
local function HookToggle()
    if ToggleHooked then return end
    -- RegisterHook needs the Blueprint class loaded
    if not Valid(StaticFindObject(RulerClass)) then
        pcall(LoadAsset, (RulerClass:gsub("%.[^%.]+$", "")))
    end
    -- Blueprint hooks run after the function: BrushSize already holds the vanilla result
    ToggleHooked = pcall(RegisterHook, RulerClass .. ":ToggleBrushSize", OnToggle)
end

HookToggle()
RegisterInitGameStatePostHook(HookToggle)
