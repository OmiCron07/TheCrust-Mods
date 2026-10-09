-- =============================================================================
-- Mod: RegolithIcons
-- Description: Shows the dominant oxide icon over regolith extractors, regolith refineries and
--              bulk storages, so lines fed by different deposits are not mixed by mistake.
-- =============================================================================

local Icons = require("icons")

local RefreshSeconds = 2

-- Every module constructed (save load, building) is queued; Icons.Refresh picks the regolith ones.
NotifyOnNewObject("/Script/TheCrust.ModuleBase", Icons.OnNewModule)

local function Valid(Obj)
    return type(Obj) == "userdata" and Obj:IsValid()
end

-- The game instance lives for the whole process: look it up once.
local GameInstance
local function IsLoading()
    if not Valid(GameInstance) then GameInstance = FindFirstOf("CrustGameInstance_C") end
    return Valid(GameInstance) and GameInstance.LoadingInProcess == true
end

-- Mod (re)loaded with a world already up (UE4SS hot reload): modules were constructed before the
-- notification was registered, scan for them once.
if Valid(FindFirstOf("GodPlayer_PC_C")) then Icons.ScanAll() end

-- Game-thread tick: hooked on a GodPawn function the game calls every frame (see ZoomToCursor).
local TickHookPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:ArmLenght"
local TickHooked = false
local NextRefresh = 0

local function OnFrame()
    local Now = os.clock()
    if Now < NextRefresh then return end
    NextRefresh = Now + RefreshSeconds
    if IsLoading() then return end
    local Ok, Err = pcall(Icons.Refresh)
    if not Ok then print("[RegolithIcons] Refresh failed: " .. tostring(Err) .. "\n") end
end

local function TryHookTick()
    if TickHooked then return true end
    local Fn = StaticFindObject(TickHookPath)
    if Fn and Fn:IsValid() then
        TickHooked = pcall(RegisterHook, TickHookPath, OnFrame)
    end
    return TickHooked
end

TryHookTick()
LoopAsync(1000, TryHookTick)

print("[RegolithIcons] Loaded\n")
