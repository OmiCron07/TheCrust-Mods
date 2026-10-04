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

LoopAsync(250, function()
    local F = io.open(CmdFile, "r")
    if not F then return false end
    local Source = F:read("a")
    F:close()
    os.remove(CmdFile)
    ExecuteInGameThread(function() RunCommand(Source) end)
    return false
end)

print("[DevBridge] Listening on " .. CmdFile .. "\n")
