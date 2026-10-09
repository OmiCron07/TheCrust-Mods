-- =============================================================================
-- Mod: CheaperBelts
-- Description: Scales the build and upgrade costs of conveyor belts. Costs come from
--              DT_ConveyorConfig, copied into ConveyorSubsystem.ConveyorConfig (lives for the
--              whole process); the game reads them from there for every new belt and upgrade.
-- =============================================================================

local Defaults = {
    BuildCostMultiplier = 0.5,
    UpgradeCostMultiplier = 0.5
}

local Ok, Loaded = pcall(require, "config")
if not Ok or type(Loaded) ~= "table" then
    print("[CheaperBelts] config.lua failed to load, using defaults: " .. tostring(Loaded) .. "\n")
    Loaded = {}
end

local function Multiplier(Key)
    local Value = tonumber(Loaded[Key])
    if Value == nil or Value < 0 then
        print(string.format("[CheaperBelts] Invalid %s (%s), using %.2f\n", Key, tostring(Loaded[Key]), Defaults[Key]))
        return Defaults[Key]
    end
    return Value
end

local BuildMultiplier = Multiplier("BuildCostMultiplier")
local UpgradeMultiplier = Multiplier("UpgradeCostMultiplier")

local CellCostFields = { "BeltCellCost", "DistributorCellCost", "UndergroundBeltCellCost" }

local PanelClass = "/Game/Widgets/WidgetPanelTools/PipeLineWidgets/W_ConveyorsPanel.W_ConveyorsPanel_C"
-- Belt price labels of the panel, tier 1 to 5 (each shows belt cell cost + cumulative tier cost)
local TierLabels = { "convLvl0Cost", "ConvLvl1Cost", "convLvl2Cost", "convLvl3Cost", "convLvl3Cost_1" }

local function Valid(Object)
    return type(Object) == "userdata" and Object:IsValid()
end

-- Vanilla values are kept in shared variables: they survive UE4SS hot reloads, after which the
-- subsystem still holds the values scaled by the previous instance of the mod.
local function Vanilla(Key, Current)
    local Name = "CheaperBelts.Vanilla." .. Key
    local Value = ModRef:GetSharedVariable(Name)
    if type(Value) ~= "number" then
        Value = Current
        ModRef:SetSharedVariable(Name, Value)
    end
    return Value
end

local function Apply()
    local Subsystem = FindFirstOf("ConveyorSubsystem")
    if not Valid(Subsystem) then return end

    local Conveyor = Subsystem.ConveyorConfig
    for _, Field in ipairs(CellCostFields) do
        Conveyor[Field] = Vanilla(Field, Conveyor[Field]) * BuildMultiplier
    end
    local Upgrades = Conveyor.ConveyorUpgradeCosts
    for i = 1, Upgrades:GetArrayNum() do
        Upgrades[i] = Vanilla("Upgrade" .. i, Upgrades[i]) * UpgradeMultiplier
    end

    print(string.format("[CheaperBelts] Belt cell cost %.0f, upgrade costs x%.2f\n",
        Conveyor.BeltCellCost, UpgradeMultiplier))
    return Subsystem
end

-- The belt panel fills its price labels once, in OnInitialized, straight from DT_ConveyorConfig
-- (not from the subsystem): overwrite them with the scaled costs.
local function RefreshPanel(Panel, Subsystem)
    local Belt = Subsystem:GetCellCostBySectionType(1)
    for i, Label in ipairs(TierLabels) do
        Panel[Label]:SetCurrentValue(Belt + Subsystem:GetTierCost(i - 1))
    end
    Panel.DistributorCost:SetCurrentValue(Subsystem:GetCellCostBySectionType(2))
    Panel.convUndergroundCost:SetCurrentValue(Subsystem:GetCellCostBySectionType(3))
end

local PanelHooked = false
local function HookPanel()
    if PanelHooked then return end
    -- RegisterHook needs the Blueprint class loaded; load it so the first panel is not missed
    if not Valid(StaticFindObject(PanelClass)) then
        pcall(LoadAsset, (PanelClass:gsub("%.[^%.]+$", "")))
    end
    PanelHooked = pcall(RegisterHook, PanelClass .. ":OnInitialized", function(Context)
        local Subsystem = Apply()
        if Subsystem then RefreshPanel(Context:get(), Subsystem) end
    end)
end

-- The subsystem and panel already exist on a hot reload; on a cold start they appear later.
-- Writes are absolute (vanilla x multiplier), so applying again on every map load is harmless.
local Subsystem = Apply()
local Panel = FindFirstOf("W_ConveyorsPanel_C")
if Subsystem and Valid(Panel) then RefreshPanel(Panel, Subsystem) end

RegisterInitGameStatePostHook(function()
    Apply()
    HookPanel()
end)
