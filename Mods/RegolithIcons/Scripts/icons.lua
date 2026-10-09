-- Dominant oxide icon over regolith modules (extractors, refineries, bulk storages).
-- Each module gets its own screen-space WidgetComponent with the vanilla W_ProductionIndicator
-- (the module's ProductionOutputIndicator is driven by vanilla on hover, so it is left alone).

local Icons = {}

-- Module class -> storage agency holding the regolith composition (StorageAgency
-- CurrentResourceRegolithPercentage: oxide fractions of the regolith in that storage).
local Targets = {
    MB_ExtractorDeepOre_C = "SAO_Regolith",
    MB_EnrichmentFactory_C = "SAI_Regolith",
    MB_SingleRegolithRefinery_C = "SAI_Regolith_or_Slag",
    MB_BigBulkStorage_C = "SA_Bulk",
    MB_VeryBigBulkStorage_C = "SA_Bulk",
}

local Regolith = 1
-- EResourceType oxides; Slag (6) never names a line, so it is ignored.
local Oxides = { 2, 3, 4, 5 } -- TitanOxide, IronOxide, SiliconOxide, AluminiumOxide
-- The top oxide must be this many times the runner-up, else the regolith icon marks a blend.
-- Deposit profiles have one oxide at ~0.5-0.6 and the others at ~0.05.
local MixedRatio = 2

local WidgetClassPath = "/Game/Widgets/W_ProductionIndicator.W_ProductionIndicator_C"

local Entries = {} -- module address -> { Actor, Comp, Res }
local Pending = {} -- modules constructed since the last refresh (not initialized yet)
local Settling = {} -- modules queued one refresh ago: initialized by now

local Identity = {
    Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
    Translation = { X = 0, Y = 0, Z = 0 },
    Scale3D = { X = 1, Y = 1, Z = 1 },
}

-- UE4SS IsValid stays true for pending kill objects until the next GC.
local function Valid(Obj)
    return type(Obj) == "userdata" and Obj:IsValid()
        and not Obj:HasAnyInternalFlags(EInternalObjectFlags.PendingKill)
end

-- Oxide with the largest fraction; Regolith when no oxide stands out (blend of several deposits);
-- nil when the storage does not take regolith or never held any.
function Icons.Dominant(Storage)
    if not Valid(Storage) then return nil end
    local Capacity = 0
    Storage.MaxResourceLimit:ForEach(function(K, V)
        if K:get() == Regolith then Capacity = V:get() end
    end)
    if Capacity <= 0 then return nil end -- e.g. bulk storage switched to another resource
    local Fractions = {}
    Storage.CurrentResourceRegolithPercentage:ForEach(function(K, V) Fractions[K:get()] = V:get() end)
    return Icons.Pick(Fractions)
end

-- Fractions: EResourceType -> fraction of the regolith.
function Icons.Pick(Fractions)
    local Best, BestValue, Second = nil, 0, 0
    for _, Ox in ipairs(Oxides) do
        local V = Fractions[Ox] or 0
        if V > BestValue then
            Best, BestValue, Second = Ox, V, BestValue
        elseif V > Second then
            Second = V
        end
    end
    if Best and BestValue < MixedRatio * Second then return Regolith end
    return Best
end

local function Target(Actor)
    if not Valid(Actor) then return nil end
    local Field = Targets[Actor:GetClass():GetFName():ToString()]
    -- Skip archetypes and level sequence spawnables (MovieScene copies in the main menu).
    if Field and Actor:GetFullName():find(":PersistentLevel.", 1, true) then return Field end
end

local function Key(Actor)
    return Actor:GetAddress()
end

local function NewIcon(Actor)
    local WidgetClass = StaticFindObject(WidgetClassPath)
    if not Valid(WidgetClass) then return nil end
    local Cls = StaticFindObject("/Script/UMG.WidgetComponent")
    local Comp = Actor:AddComponentByClass(Cls, false, Identity, true)
    Comp.Space = 1 -- EWidgetSpace::Screen
    Comp.WidgetClass = WidgetClass
    Comp.DrawSize = { X = 500, Y = 500 } -- vanilla ProductionOutputIndicator values
    Comp.Pivot = { X = 0.5, Y = 0.5 }
    Actor:FinishAddComponent(Comp, false, Identity)
    local O, E = {}, {}
    Actor:GetActorBounds(true, O, E, false)
    -- Top of the bounds: higher points drift off the module under the tilted camera.
    Comp:K2_SetWorldLocation({ X = O.X, Y = O.Y, Z = O.Z + E.Z }, false, {}, false)
    return Comp
end

local function Update(Actor, Field)
    local E = Entries[Key(Actor)]
    if not (E and Valid(E.Comp)) then
        local Comp = NewIcon(Actor)
        if not Comp then return end
        E = { Actor = Actor, Comp = Comp, Res = false } -- false: visibility not set yet
        Entries[Key(Actor)] = E
    end
    -- Planning ghosts get no icon (they show one once built).
    local Res = not Actor.bPlanningModeCPP and Icons.Dominant(Actor[Field]) or nil
    if Res == E.Res then return end
    E.Res = Res
    if Res then
        local Widget = E.Comp:GetUserWidgetObject()
        if not Valid(Widget) then E.Res = nil return end
        Widget["Set Resource Icon"](Widget, Res)
    end
    E.Comp:SetVisibility(Res ~= nil, true)
end

-- NotifyOnNewObject callback: may run during loading, before the actor is initialized; only queue.
function Icons.OnNewModule(Actor)
    Pending[#Pending + 1] = Actor
end

-- Removes icon components left by a previous instance of the mod (UE4SS hot reload).
local function CleanupLeftovers(Actor)
    -- UE4SS wrappers of the same object are not equal: compare addresses.
    local WidgetClass = StaticFindObject(WidgetClassPath)
    if not Valid(WidgetClass) then return end
    local Vanilla = Actor.ProductionOutputIndicator
    local VanillaAddress = Valid(Vanilla) and Vanilla:GetAddress()
    local Cls = StaticFindObject("/Script/UMG.WidgetComponent")
    -- Returned as a Lua table of RemoteUnrealParam (unwrap with get).
    for _, Param in ipairs(Actor:K2_GetComponentsByClass(Cls) or {}) do
        local C = Param:get()
        local Widget = Valid(C) and C:GetAddress() ~= VanillaAddress and C:GetUserWidgetObject()
        if Valid(Widget) and Widget:GetClass():GetAddress() == WidgetClass:GetAddress() then
            C:K2_DestroyComponent(C)
        end
    end
end

-- Full object scan (~1 s on a large base): only when the mod starts with a world already loaded.
function Icons.ScanAll()
    for Class in pairs(Targets) do
        for _, Actor in ipairs(FindAllOf(Class) or {}) do
            if Target(Actor) then
                CleanupLeftovers(Actor)
                Pending[#Pending + 1] = Actor
            end
        end
    end
end

function Icons.Refresh()
    for _, Actor in ipairs(Settling) do
        if Target(Actor) then Entries[Key(Actor)] = Entries[Key(Actor)] or { Actor = Actor } end
    end
    Settling, Pending = Pending, {}
    for K, E in pairs(Entries) do
        local Field = Target(E.Actor)
        if Field then Update(E.Actor, Field) else Entries[K] = nil end
    end
end

return Icons
