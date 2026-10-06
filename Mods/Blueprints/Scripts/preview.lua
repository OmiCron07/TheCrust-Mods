-- Paste preview: one unsettled (cursor-preview state) ghost module per blueprint module follows
-- the cursor, and validity says which modules can be placed there.
-- Regular modules: no overlap with existing modules / belts, and dug ground underground.
-- Special modules (CPPPlacementCheck false, e.g. deep ore extractors): the ghost runs the vanilla
-- check, like the vanilla building mode; its active cells are reported with their vein state.

local Grid = require("grid")
local Game = require("game")
local Placer = require("placer")

local Preview = {}

local Ghosts = {}       -- [module index] = unsettled module actor
local Special = {}      -- [module index] = true when the ghost runs the placement check
local GhostAddresses = {} -- [actor address] = true for the ghosts above
local SpecialByClass = {} -- class path -> true when the class uses its own placement rule
local Occupancy, GroundManager, Layer

-- Unsettled modules get IO resource icons a few frames after spawning; they stay where they were
-- created instead of following the ghost, so ours are collapsed as soon as they are bound.
local IOWidgetClass = "/Game/Widgets/ConveyorCommonWIdgets/W_IOCell_Resource.W_IOCell_Resource_C"
local IOWidgetHookPath = IOWidgetClass .. ":Set My IOCell"
local IOWidgetHooked = false

local function HookIOWidgets()
    if IOWidgetHooked or not Game.LoadClass(IOWidgetClass) then return end
    IOWidgetHooked = pcall(RegisterHook, IOWidgetHookPath, function(Context, _, MyModule)
        local M = MyModule:get()
        if Game.Valid(M) and GhostAddresses[M:GetAddress()] then
            Context:get():SetVisibility(1) -- Collapsed
        end
    end)
end

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
    Ghosts, Special, GhostAddresses, Occupancy, GroundManager, Layer = {}, {}, {}, nil, nil, nil
end

function Preview.Stop()
    for _, M in pairs(Ghosts) do
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
    HookIOWidgets()
    for i, Mod in ipairs(BP.Modules) do
        Special[i] = IsSpecial(PC, Mod, OR, OC)
        local M = Placer.SpawnModule(PC, Mod, OR, OC, 0)
        if M then
            Ghosts[i] = M
            GhostAddresses[M:GetAddress()] = true
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
        local Ghost = Ghosts[i]
        local Positioned = Game.Valid(Ghost) and pcall(function()
            Placer.PositionModule(Ghost, Geo, Mod, OR, OC, Turns)
            -- Validity squares only follow the vanilla tick on the PC's CurrentModuleToBuild.
            Ghost.Undercells:ForEach(function(_, V)
                local Cell = V:get()
                if Game.Valid(Cell) then Cell:SetVision(false) end
            end)
        end)
        if Special[i] and Game.Valid(Ghost) then
            local Ok = Positioned and pcall(function()
                pcall(function() Ghost:RecalculateExtractorActiveCells() end)
                local Result = {}
                Ghost:CheckIfCanSettleModuleAccordingToUndermoduleCells(Result)
                Valid[i] = Result.Success == true
                local Comp = Ghost.ExtractorComponent
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
