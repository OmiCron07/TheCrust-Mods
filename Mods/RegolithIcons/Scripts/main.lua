-- =============================================================================
-- Mod: RegolithIcons
-- Description: Shows the dominant oxide icon over regolith extractors, regolith refineries and
--              bulk storages, so lines fed by different deposits are not mixed by mistake.
-- =============================================================================

local Icons = require("icons")

local RefreshSeconds = 2

local Ok, Config = pcall(require, "config")
if not Ok or type(Config) ~= "table" then
    print("[RegolithIcons] config.lua failed to load, using defaults: " .. tostring(Config) .. "\n")
    Config = {}
end
local ToggleKey = Config.ToggleKey or "I"
Icons.SetShown(Config.ShowAtStart ~= false)

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

-- Hotkeys fire on the UE4SS input thread: only flag them, the game-thread tick runs them.
local TogglePressed = false
if Key[ToggleKey] then
    RegisterKeyBind(Key[ToggleKey], function() TogglePressed = true end)
else
    print("[RegolithIcons] Unknown ToggleKey " .. tostring(ToggleKey) .. ", no toggle key\n")
end

local ModifierKeys = { "LeftControl", "RightControl", "LeftShift", "RightShift", "LeftAlt", "RightAlt" }

-- UE4SS also fires a binding when modifiers are held: Ctrl+I and the like must not toggle.
local function NoModifierHeld(PC)
    for _, Name in ipairs(ModifierKeys) do
        if PC:IsInputKeyDown({ KeyName = FName(Name) }) then return false end
    end
    return true
end

local function HandleToggle(Pawn)
    if not TogglePressed then return end
    TogglePressed = false
    local PC = Valid(Pawn) and Pawn:GetController()
    if Valid(PC) and NoModifierHeld(PC) then Icons.SetShown(not Icons.IsShown()) end
end

local function OnFrame(Context)
    local Ok, Err = pcall(HandleToggle, Context:get())
    if not Ok then print("[RegolithIcons] Toggle failed: " .. tostring(Err) .. "\n") end
    local Now = os.clock()
    if Now < NextRefresh then return end
    NextRefresh = Now + RefreshSeconds
    if IsLoading() then return end
    Ok, Err = pcall(Icons.Refresh)
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
