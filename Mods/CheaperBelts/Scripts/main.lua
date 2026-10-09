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
    if not (type(Subsystem) == "userdata" and Subsystem:IsValid()) then return end

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
end

-- The subsystem already exists on a hot reload; on a cold start it appears before the first map.
-- Writes are absolute (vanilla x multiplier), so applying again on every map load is harmless.
Apply()
RegisterInitGameStatePostHook(Apply)
