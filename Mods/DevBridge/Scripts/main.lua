-- =============================================================================
-- Mod: DevBridge (development tool, do not ship)
-- Description: Polls <ModDir>/bridge/cmd.lua, executes it on the game thread
--              and writes captured output to <ModDir>/bridge/out.txt.
--              Driven by Scripts/Invoke-DevBridge.ps1.
-- =============================================================================

local ScriptPath = debug.getinfo(1, "S").source:gsub("^@", "")
local ModDir = ScriptPath:gsub("[\\/]Scripts[\\/]main%.lua$", "")
local BridgeDir = ModDir .. "\\bridge"
local CmdFile = BridgeDir .. "\\cmd.lua"
local OutFile = BridgeDir .. "\\out.txt"
local OutTmp = BridgeDir .. "\\out.tmp"

os.execute('if not exist "' .. BridgeDir .. '" mkdir "' .. BridgeDir .. '"')

-- Persistent scratch table shared between commands
DevBridgeState = DevBridgeState or {}

local function Dump(v, depth)
    depth = depth or 0
    if type(v) ~= "table" or depth > 3 then return tostring(v) end
    local parts = {}
    for k, val in pairs(v) do
        parts[#parts + 1] = tostring(k) .. "=" .. Dump(val, depth + 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function RunCommand(Source)
    local Lines = {}
    local Env = setmetatable({
        out = function(...)
            local n = select("#", ...)
            local parts = {}
            for i = 1, n do parts[i] = Dump((select(i, ...))) end
            Lines[#Lines + 1] = table.concat(parts, "\t")
        end,
        S = DevBridgeState,
    }, { __index = _G })

    local Chunk, Err = load(Source, "=cmd", "t", Env)
    if not Chunk then
        Lines[#Lines + 1] = "[compile error] " .. tostring(Err)
    else
        local Ok, RunErr = xpcall(Chunk, debug.traceback)
        if not Ok then Lines[#Lines + 1] = "[runtime error] " .. tostring(RunErr) end
    end

    local F = io.open(OutTmp, "w")
    if F then
        F:write(table.concat(Lines, "\n"))
        F:close()
        os.remove(OutFile)
        os.rename(OutTmp, OutFile)
    end
end

-- Polled from a per-frame game-thread hook (GodPawn ArmLenght): ExecuteInGameThread queues
-- stopped running after another mod's UE4SS auto-reload, leaving the bridge deaf.
local Frame = 0
local function OnFrame()
    Frame = Frame + 1
    if Frame % 15 ~= 0 then return end
    local F = io.open(CmdFile, "r")
    if not F then return end
    local Source = F:read("a")
    F:close()
    os.remove(CmdFile)
    RunCommand(Source)
end

local HookPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:ArmLenght"
local Hooked = false
local function TryHook()
    if Hooked then return true end
    local Fn = StaticFindObject(HookPath)
    if Fn and Fn:IsValid() then Hooked = pcall(RegisterHook, HookPath, OnFrame) end
    return Hooked
end
TryHook()
LoopAsync(1000, TryHook)

print("[DevBridge] Listening on " .. CmdFile .. "\n")
