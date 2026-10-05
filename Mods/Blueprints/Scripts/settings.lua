-- Logistics settings exposed by the vanilla UI, captured and re-applied with the same calls:
--   distributors (W_ConveyorDistributorRenewed / W_ConveyorDistributor_Input): per output the
--     allowed resources, priority / hand-tuned / blocked / locked flags and priority level, per
--     input the priority level;
--   module IO cells (W_ConveyorOutputSetting): storage agency binding (IO swap), output
--     filtration list, output lock, overflow.
-- Distributor outputs and inputs are stored by direction: their array indices follow the order
-- belts got connected, which differs between the source and the paste.

local Grid = require("grid")
local Game = require("game")

local Settings = {}

local LocksOutputTag = "ObjectType.IOCELL.Bool.LocksOutput"

local function ToList(Arr)
    local T = {}
    Arr:ForEach(function(_, V) T[#T + 1] = V:get() end)
    return T
end

local function SameList(A, B)
    if #A ~= #B then return false end
    for i = 1, #A do
        if A[i] ~= B[i] then return false end
    end
    return true
end

local function ByDir(List, Dir)
    for _, E in ipairs(List) do
        if E.Dir == Dir then return E end
    end
end

-- Distributor section (UCSection, Type 2) -> { Outputs = {...}, Inputs = {...} }.
function Settings.CaptureDistributor(S)
    local St = S.State
    local Outputs, Inputs = {}, {}
    local Allowed = St.OutputAllowedResources
    for i, Dir in ipairs(ToList(St.OutputDirections)) do
        local O = { Dir = Dir, Types = {}, Priority = false, Locked = false, HandTuned = false, Blocked = false }
        if i <= Allowed:GetArrayNum() then
            local A = Allowed[i]
            O.Types = ToList(A.ResourceTypesAllowed)
            O.Priority = A.bPriorityOutput
            O.Locked = A.bLockedOutput
            O.HandTuned = A.bHandTunedOutput
            O.Blocked = A.bUserBlockedOutput
        end
        O.Level = S:GetOutputPriority(i - 1)
        Outputs[#Outputs + 1] = O
    end
    for i, Dir in ipairs(ToList(St.InputDirections)) do
        Inputs[#Inputs + 1] = { Dir = Dir, Level = S:GetInputPriority(i - 1) }
    end
    return { Outputs = Outputs, Inputs = Inputs }
end

-- Applies captured settings D (directions as captured) to distributor S rotated by Turns.
-- SetIsPriorityOutput also changes the priority level, so the level is set after it.
-- Returns the number of settings that do not read back as captured.
function Settings.ApplyDistributor(CM, S, D, Turns)
    local St = S.State
    for i, NewDir in ipairs(ToList(St.OutputDirections)) do
        local O = ByDir(D.Outputs, Grid.RotateDir(NewDir, -Turns))
        if O then
            local Id = i - 1
            for _, Type in ipairs(O.Types) do CM:AddResourceTypeAtOutput(Id, S, Type) end
            S:SetIsHandTunedOutput(Id, O.HandTuned)
            S:SetIsPriorityOutput(Id, O.Priority)
            S:SetUserBlockedOutput(Id, O.Blocked)
            S:SetOutputLocked(Id, O.Locked)
            S:SetOutputPriority(Id, O.Level)
        end
    end
    for i, NewDir in ipairs(ToList(St.InputDirections)) do
        local In = ByDir(D.Inputs, Grid.RotateDir(NewDir, -Turns))
        if In then S:SetInputPriority(i - 1, In.Level) end
    end

    local Got, Mismatches = Settings.CaptureDistributor(S), 0
    local function Check(Want, Have, Fields)
        if not Have then
            Mismatches = Mismatches + 1
            return
        end
        for _, F in ipairs(Fields) do
            local Same = F == "Types" and SameList(Want.Types, Have.Types) or Want[F] == Have[F]
            if not Same then Mismatches = Mismatches + 1 end
        end
    end
    for _, O in ipairs(D.Outputs) do
        Check(O, ByDir(Got.Outputs, Grid.RotateDir(O.Dir, Turns)), { "Types", "Priority", "Locked", "HandTuned", "Blocked", "Level" })
    end
    for _, In in ipairs(D.Inputs) do
        Check(In, ByDir(Got.Inputs, Grid.RotateDir(In.Dir, Turns)), { "Level" })
    end
    return Mismatches
end

local function IOCells(M)
    local Cells = {}
    M.IOCells:ForEach(function(_, V) Cells[#Cells + 1] = V:get() end)
    return Cells
end

local function AgencyName(IO)
    local A = IO.StorageModuleAgency
    return Game.Valid(A) and A:GetFName():ToString() or ""
end

-- Module -> list of IO cell settings in IOCells order (same order for every module of a class).
function Settings.CaptureIO(M)
    local List = {}
    for _, IO in ipairs(IOCells(M)) do
        if Game.Valid(IO) then
            List[#List + 1] = {
                Agency = AgencyName(IO),
                Filter = ToList(IO.ResourceOutputFiltrationArray),
                Lock = IO.bLocksOutput == true,
                Overflow = IO:Get_bOverflow() == true,
            }
        else
            List[#List + 1] = false
        end
    end
    return List
end

-- Applies captured IO settings to a freshly placed module of the same class.
-- Returns the number of IO cells whose settings do not read back as captured.
function Settings.ApplyIO(M, List)
    local Cells = IOCells(M)
    -- Swaps first (they rebind storage agencies), then the per-cell settings.
    for i, Want in ipairs(List) do
        local IO = Cells[i]
        if Want and Game.Valid(IO) and Want.Agency ~= "" and AgencyName(IO) ~= Want.Agency then
            for j = i + 1, #Cells do
                if Game.Valid(Cells[j]) and AgencyName(Cells[j]) == Want.Agency then
                    M:Execute_SwapIOCells(IO, Cells[j], {})
                    break
                end
            end
        end
    end

    local Mismatches = 0
    for i, Want in ipairs(List) do
        local IO = Cells[i]
        if Want and Game.Valid(IO) then
            if not SameList(ToList(IO.ResourceOutputFiltrationArray), Want.Filter) then
                IO["Execute Clear Resource Output Filtration Array"](IO)
                for _, Type in ipairs(Want.Filter) do
                    IO["Add In Resource Output Filtration Array"](IO, Type)
                end
            end
            if (IO.bLocksOutput == true) ~= Want.Lock then
                IO["Setter Bool by Tag"](IO, { TagName = FName(LocksOutputTag) }, Want.Lock)
            end
            if (IO:Get_bOverflow() == true) ~= Want.Overflow then
                IO["Flip OverflowState"](IO, {})
            end

            if AgencyName(IO) ~= Want.Agency
                or not SameList(ToList(IO.ResourceOutputFiltrationArray), Want.Filter)
                or (IO.bLocksOutput == true) ~= Want.Lock
                or (IO:Get_bOverflow() == true) ~= Want.Overflow then
                Mismatches = Mismatches + 1
            end
        elseif Want then
            Mismatches = Mismatches + 1
        end
    end
    return Mismatches
end

return Settings
