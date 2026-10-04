-- Accessors over The Crust game objects (GodPlayer_PC, conveyor managers, grid, modules).
-- UE4SS out-param convention: every out param needs a table placeholder; the first one receives
-- all out values keyed by their UFunction parameter names.

local Grid = require("grid")

local Game = {}

Game.LayerUnderground = 0
Game.LayerOrbital = 1
Game.LayerCrater = 2

-- Building states to ignore: not settled yet (cursor preview) and dismantled / being dismantled.
-- ("Settled Module" is only set on placement, it stays false for modules loaded from a save.)
local ExcludedStates = { [0] = true, [6] = true, [7] = true, [8] = true }

-- UE4SS hands out null wrappers instead of nil: always check before touching an object.
function Game.Valid(Obj)
    return type(Obj) == "userdata" and Obj:IsValid()
end

function Game.PC()
    local PC = FindFirstOf("GodPlayer_PC_C")
    if Game.Valid(PC) then return PC end
end

function Game.IsLoading()
    local GI = FindFirstOf("CrustGameInstance_C")
    return Game.Valid(GI) and GI.LoadingInProcess == true
end

-- Identifies one gameplay world: the PC is recreated on every save load / level change.
function Game.SessionKey(PC)
    return PC:GetFullName()
end

function Game.Layer(PC)
    return PC.CurrentGameLayer
end

function Game.IsBuildLayer(Layer)
    return Layer == Game.LayerUnderground or Layer == Game.LayerCrater
end

function Game.Level(PC)
    local Out = {}
    PC["GetCurrent Level"](PC, Out)
    return Out["Out CurrentLevel"]
end

-- GetGroundManager takes a TorchLocation: underground layer -> 1, crater layer -> 0
-- (same mapping as GodPlayer_PC TickFunctionForPlacingModuleMode).
function Game.GroundManager(PC, Layer)
    local Out = {}
    Game.Level(PC):GetGroundManager(Layer == Game.LayerUnderground and 1 or 0, Out)
    return Out.GroundManager
end

-- Production scheme (APS ability) of a module: active one, or the one chosen before construction.
function Game.ModuleRecipe(Module)
    local Agency = Module.AbilityAgencyVar
    local Active = Game.Valid(Agency) and Agency["Active APS Ability"]:ToString() or ""
    if Active ~= "" then return Active end
    if Module.bChangedRecipieBeforeBuilt then return Module.AbilityBeforeBuilt:ToString() end
    return ""
end

function Game.ConveyorManager(PC, Layer)
    if Layer == Game.LayerUnderground then return PC.ConveyorManagerUnderground end
    if Layer == Game.LayerCrater then return PC.ConveyorManagerSurface end
end

function Game.CursorCell(PC)
    local Out = {}
    PC:GetCellUnderCursor(11, false, Out, {}, {})
    if Out.Success and Out["Out SmallIndex"] and Out["Out SmallIndex"] >= 0 then
        return Out["Out SmallIndex"]
    end
end

function Game.IsKeyDown(PC, KeyName)
    return PC:IsInputKeyDown({ KeyName = FName(KeyName) })
end

-- World geometry of the layer grid: cell size, world position of cell (0,0) corner, ground Z.
-- Sampled near the grid center: GetGridLocationByCellID returns nothing for cells outside the level.
function Game.Geometry(CM)
    local Mid = Grid.Size // 2
    local A, B = {}, {}
    CM:GetGridLocationByCellID(A, Grid.ToCell(Mid, Mid))
    CM:GetGridLocationByCellID(B, Grid.ToCell(Mid + 1, Mid + 1))
    -- The single FVector out param is unpacked straight into the table (X, Y, Z).
    local LA, LB = A.OutLocation or A, B.OutLocation or B
    local Size = LB.X - LA.X
    return {
        CellSize = Size,
        OriginX = LA.X - (Mid + 0.5) * Size,
        OriginY = LA.Y - (Mid + 0.5) * Size,
        Z = LA.Z,
    }
end

-- Fractional (Row, Col) of a world location, cell centers being integers.
function Game.WorldToRowCol(Geo, X, Y)
    return (X - Geo.OriginX) / Geo.CellSize - 0.5, (Y - Geo.OriginY) / Geo.CellSize - 0.5
end

function Game.RowColToWorld(Geo, Row, Col)
    return Geo.OriginX + (Row + 0.5) * Geo.CellSize, Geo.OriginY + (Col + 0.5) * Geo.CellSize
end

function Game.ClassPath(Obj)
    return (Obj:GetClass():GetFullName():gsub("^%S+%s+", ""))
end

function Game.LoadClass(Path)
    local Cls = StaticFindObject(Path)
    if Game.Valid(Cls) then return Cls end
    pcall(function() LoadAsset((Path:gsub("%.[^%.]+$", ""))) end)
    Cls = StaticFindObject(Path)
    if Game.Valid(Cls) then return Cls end
end

function Game.ModuleCells(Module)
    local Cells = {}
    Module.CellIndexesUnderModule:ForEach(function(_, V) Cells[#Cells + 1] = V:get() end)
    return Cells
end

-- Settled, non-dismantled player modules of the given layer.
function Game.LayerModules(Layer)
    local Result = {}
    local OnSurface = (Layer == Game.LayerCrater)
    for _, M in ipairs(FindAllOf("ModuleBase_BP_C") or {}) do
        if Game.Valid(M) then
            local Name = M:GetFullName()
            if Name:find("PersistentLevel", 1, true) and not Name:find("Default__", 1, true)
                and M.bOnSurface == OnSurface
                and not ExcludedStates[M.BuildingStateCPP] then
                Result[#Result + 1] = M
            end
        end
    end
    return Result
end

function Game.IsCopyAllowed(Module)
    local Out = {}
    local Ok = pcall(function() Module:IsCopyAllowed(Out) end)
    return Ok and Out["Return Value"] == true
end

return Game
