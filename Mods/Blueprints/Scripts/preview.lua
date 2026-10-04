-- Paste preview validity: which blueprint modules can be placed at the cursor.
-- Regular modules: no overlap with existing modules / belts, and dug ground underground.
-- Special modules (CPPPlacementCheck false, e.g. deep ore extractors): an invisible unsettled
-- "probe" module follows the cursor and runs the vanilla check, like the vanilla building mode;
-- its active cells are reported with their vein state.

local Grid = require("grid")
local Game = require("game")
local Placer = require("placer")

local Preview = {}

local Probes = {}       -- [module index] = unsettled module actor
local SpecialByClass = {} -- class path -> true when the class uses its own placement rule
local Occupancy, GroundManager, Layer

local function IsSpecial(PC, Mod, OR, OC)
    if SpecialByClass[Mod.Class] ~= nil then return SpecialByClass[Mod.Class] end
    local M = Placer.SpawnModule(PC, Mod, OR, OC, 0)
    if not M then return false end
    local Cpp = {}
    M:CPPPlacementCheck(Cpp)
    M:K2_DestroyActor()
    SpecialByClass[Mod.Class] = not Cpp.Yes
    return SpecialByClass[Mod.Class]
end

-- Drops actor references without touching them (they may belong to a destroyed world).
function Preview.Forget()
    Probes, Occupancy, GroundManager, Layer = {}, nil, nil, nil
end

function Preview.Stop()
    for _, M in pairs(Probes) do
        if Game.Valid(M) then M:K2_DestroyActor() end
    end
    Preview.Forget()
end

-- Re-reads the occupied cells (after a paste placed new ghosts).
function Preview.Refresh(PC, InLayer)
    Layer = InLayer
    Occupancy = Placer.Occupancy(Game.ConveyorManager(PC, Layer), Layer)
    GroundManager = Game.GroundManager(PC, Layer)
end

function Preview.Start(PC, InLayer, BP, OR, OC)
    Preview.Stop()
    Preview.Refresh(PC, InLayer)
    for i, Mod in ipairs(BP.Modules) do
        if IsSpecial(PC, Mod, OR, OC) then
            local M = Placer.SpawnModule(PC, Mod, OR, OC, 0)
            if M then
                M:SetActorHiddenInGame(true)
                Probes[i] = M
            end
        end
    end
end

local function RegularValid(Mod, OR, OC, Turns)
    for _, Cell in ipairs(Mod.Cells) do
        local DR, DC = Grid.Rotate(Cell[1], Cell[2], Turns)
        local R, C = OR + DR, OC + DC
        if not Grid.InBounds(R, C) then return false end
        local Id = Grid.ToCell(R, C)
        if Occupancy.Modules[Id] then return false end
        if Layer == Game.LayerUnderground and GroundManager:GetSoilCellState(Id) == 0 then return false end
    end
    return true
end

-- Returns Valid[i] per module and VeinCells = array of { Cell, OnVein } for special modules.
function Preview.Evaluate(Geo, BP, OR, OC, Turns)
    local Valid, VeinCells = {}, {}
    if not Occupancy then return Valid, VeinCells end
    for i, Mod in ipairs(BP.Modules) do
        local Probe = Probes[i]
        if Game.Valid(Probe) then
            local Ok = pcall(function()
                Placer.PositionModule(Probe, Geo, Mod, OR, OC, Turns)
                pcall(function() Probe:RecalculateExtractorActiveCells() end)
                local Special = {}
                Probe:CheckIfCanSettleModuleAccordingToUndermoduleCells(Special)
                Valid[i] = Special.Success == true
                local Comp = Probe.ExtractorComponent
                if Game.Valid(Comp) then
                    Comp.ExtractorActiveCells:ForEach(function(_, V)
                        local Cell = V:get()
                        VeinCells[#VeinCells + 1] = { Cell, #GroundManager:GetMineralFieldIDsInThisCell(Cell).IntArr > 0 }
                    end)
                end
            end)
            if not Ok then Valid[i] = false end
        else
            Valid[i] = RegularValid(Mod, OR, OC, Turns)
        end
    end
    return Valid, VeinCells
end

return Preview
