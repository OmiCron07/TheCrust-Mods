-- =============================================================================
-- Mod: Blueprints
-- Description: Area selection, copy/paste and a saved blueprint library for The Crust.
--              Pasting places vanilla ghosts: planning-mode modules, holo conveyor belts
--              and electric wires between pasted modules.
-- =============================================================================

local Config = nil
pcall(function() Config = require("config") end)
Config = Config or {}
Config.Keys = Config.Keys or {}
if Config.PasteConveyors == nil then Config.PasteConveyors = true end
if Config.PasteElectricLinks == nil then Config.PasteElectricLinks = true end
Config.PanelPosition = Config.PanelPosition or { X = 24, Y = 140 }

local Grid = require("grid")
local Game = require("game")
local Capture = require("capture")
local Placer = require("placer")
local Visuals = require("visuals")
local UI = require("ui")
local Storage = require("storage")

local ScriptPath = debug.getinfo(1, "S").source:gsub("^@", "")
local ModDir = ScriptPath:gsub("[\\/]Scripts[\\/]main%.lua$", "")
local LibraryFile = ModDir .. "\\library.lua"

local Colors = {
    Selection = { R = 0.15, G = 0.45, B = 1.0, A = 0.22 },
    Module = { R = 0.25, G = 0.9, B = 1.0, A = 0.35 },
    Belt = { R = 1.0, G = 0.75, B = 0.15, A = 0.55 },
}

local State = {
    Mode = "idle", -- idle | selecting | selected | pasting
    Library = Storage.Load(LibraryFile),
}

local function Log(Message)
    if Config.DebugLogging then print("[Blueprints] " .. tostring(Message) .. "\n") end
end

local function Notify(Message)
    print("[Blueprints] " .. Message .. "\n")
    UI.SetStatus(Message)
end

local function RefreshLibrary()
    UI.SetLibrary(State.Library)
end

local function SaveLibrary()
    local Ok, Err = pcall(Storage.Save, LibraryFile, State.Library)
    if not Ok then Notify("Saving library failed: " .. tostring(Err)) end
    RefreshLibrary()
end

local LayerNames = { [0] = "Underground", [1] = "Orbital", [2] = "Crater" }

local function ClearMode()
    State.Mode = "idle"
    State.Anchor, State.Corner, State.Paste = nil, nil, nil
    Visuals.Hide()
end

-- Prepares per-mode layer data; fails on the orbital layer.
local function EnterLayer(PC)
    local Layer = Game.Layer(PC)
    if not Game.IsBuildLayer(Layer) then
        Notify("Switch to the Underground or Crater layer first")
        return false
    end
    local CM = Game.ConveyorManager(PC, Layer)
    Grid.Size = CM.GridSize
    State.Layer, State.Geo = Layer, Game.Geometry(CM)
    return true
end

local function StartSelect(PC)
    if not EnterLayer(PC) then return end
    ClearMode()
    State.Mode = "selecting"
    State.Captured = nil
    UI.SetSelectionInfo("No selection")
    Notify("Drag with the left mouse button over the area (right click cancels)")
end

local function StartPaste(PC, BP, Label)
    if not EnterLayer(PC) then return end
    ClearMode()
    State.Mode = "pasting"
    State.Paste = { BP = BP, Turns = 0, Dirty = true }
    State.Clipboard = BP
    local Note = ""
    if BP.Layer ~= State.Layer then Note = " (made on " .. (LayerNames[BP.Layer] or "?") .. ")" end
    Notify("Pasting " .. Label .. Note .. ": left click places, R / Shift+R rotates, right click stops")
end

local function SelectionBox()
    return { State.Anchor[1], State.Anchor[2], State.Corner[1], State.Corner[2], Color = Colors.Selection, Height = 4, Inset = 0 }
end

local function DrawSelected(PC)
    local Boxes = { SelectionBox() }
    if State.Captured then
        local S = State.Selection
        local OR, OC = (S.R0 + S.R1) // 2, (S.C0 + S.C1) // 2
        for _, B in ipairs(Visuals.BlueprintBoxes(State.Captured, OR, OC, 0, Colors.Module, Colors.Belt)) do
            Boxes[#Boxes + 1] = B
        end
    end
    Visuals.Show(PC, State.Geo, Boxes)
end

local function FinishSelection(PC)
    local A, C = State.Anchor, State.Corner
    State.Selection = {
        R0 = math.min(A[1], C[1]), C0 = math.min(A[2], C[2]),
        R1 = math.max(A[1], C[1]), C1 = math.max(A[2], C[2]),
    }
    local S = State.Selection
    local BP, Err = Capture.FromRect(PC, State.Layer, S.R0, S.C0, S.R1, S.C1)
    if not BP then
        Notify("Capture failed: " .. tostring(Err))
        ClearMode()
        return
    end
    State.Captured = BP
    State.Mode = "selected"
    local Info = "Selection: " .. Capture.Summary(BP)
    UI.SetSelectionInfo(Info)
    Notify(Capture.IsEmpty(BP) and "Nothing to copy in this area" or (Info .. " (right click clears)"))
    DrawSelected(PC)
end

local function HasSelection()
    return State.Captured ~= nil and not Capture.IsEmpty(State.Captured)
end

local function HandleAction(PC, Action, Index)
    Log("Action " .. Action .. " " .. tostring(Index))
    if Action == "SelectArea" then
        StartSelect(PC)
    elseif Action == "CopySelection" then
        if HasSelection() then StartPaste(PC, State.Captured, "selection")
        else Notify("Select an area first") end
    elseif Action == "PasteClipboard" then
        if State.Clipboard then StartPaste(PC, State.Clipboard, "clipboard")
        else Notify("Clipboard is empty") end
    elseif Action == "SaveSelection" then
        if not HasSelection() then Notify("Select an area first") return end
        local Name = UI.GetName()
        if Name == "" then Name = "Blueprint " .. (#State.Library + 1) end
        local BP = State.Captured
        BP.Name, BP.Created, BP.Summary = Name, os.date("%Y-%m-%d %H:%M"), Capture.Summary(BP)
        table.insert(State.Library, 1, BP)
        State.Captured = nil
        UI.SetName("")
        SaveLibrary()
        Notify("Saved blueprint '" .. Name .. "'")
    elseif Action == "Place" then
        local BP = State.Library[Index]
        if BP then StartPaste(PC, BP, "'" .. BP.Name .. "'") end
    elseif Action == "Rename" then
        local BP, Name = State.Library[Index], UI.GetName()
        if BP and Name ~= "" then
            BP.Name = Name
            UI.SetName("")
            SaveLibrary()
            Notify("Renamed to '" .. Name .. "'")
        else
            Notify("Type the new name in the name box, then click Rename")
        end
    elseif Action == "Delete" then
        local BP = table.remove(State.Library, Index)
        if BP then
            SaveLibrary()
            Notify("Deleted '" .. BP.Name .. "'")
        end
    elseif Action == "Refresh" then
        RefreshLibrary()
    end
end

local function TickPasting(PC, LeftPressed, RightPressed)
    local P = State.Paste
    if RightPressed then
        ClearMode()
        Notify("Paste stopped")
        return
    end
    local Cell = Game.CursorCell(PC)
    if not Cell then return end
    local OR, OC = Grid.ToRowCol(Cell)
    if Cell ~= P.Cell or P.Dirty then
        P.Cell, P.Dirty = Cell, false
        Visuals.Show(PC, State.Geo, Visuals.BlueprintBoxes(P.BP, OR, OC, P.Turns, Colors.Module, Colors.Belt))
    end
    if LeftPressed and not UI.IsHovered() then
        local Report = Placer.Paste(PC, State.Layer, P.BP, Cell, P.Turns, Config)
        for _, E in ipairs(Report.Errors) do Log(E) end
        Notify(Placer.Summary(Report))
    end
end

local RunPendingKeys -- Defined with the hotkey queue below.

local function Tick()
    local PC = Game.PC()
    if not PC then return end
    RunPendingKeys(PC)
    if not UI.IsCreated() then
        UI.Create(PC, Config.PanelPosition)
        RefreshLibrary()
    end

    for _, E in ipairs(UI.Poll()) do HandleAction(PC, E.Action, E.Index) end

    local Left = Game.IsKeyDown(PC, "LeftMouseButton")
    local Right = Game.IsKeyDown(PC, "RightMouseButton")
    local LeftPressed, LeftReleased = Left and not State.Left, State.Left and not Left
    local RightPressed = Right and not State.Right
    State.Left, State.Right = Left, Right

    if State.Mode == "idle" then return end
    if Game.Layer(PC) ~= State.Layer then
        ClearMode()
        Notify("Layer changed, cancelled")
        return
    end

    if State.Mode == "selecting" then
        if RightPressed then
            ClearMode()
            Notify("Selection cancelled")
            return
        end
        local Cell = Game.CursorCell(PC)
        if Cell and LeftPressed and not UI.IsHovered() then State.Anchor = { Grid.ToRowCol(Cell) } end
        if State.Anchor and Cell then
            local Corner = { Grid.ToRowCol(Cell) }
            if not State.Corner or Corner[1] ~= State.Corner[1] or Corner[2] ~= State.Corner[2] then
                State.Corner = Corner
                Visuals.Show(PC, State.Geo, { SelectionBox() })
            end
        end
        if State.Anchor and State.Corner and LeftReleased then FinishSelection(PC) end
    elseif State.Mode == "selected" then
        if RightPressed then
            ClearMode()
            State.Captured = nil
            UI.SetSelectionInfo("No selection")
            Notify("Selection cleared")
        end
    elseif State.Mode == "pasting" then
        TickPasting(PC, LeftPressed, RightPressed)
    end
end

local LastError
local function SafeTick()
    local Ok, Err = pcall(Tick)
    if not Ok and Err ~= LastError then
        LastError = Err
        print("[Blueprints] Tick error: " .. tostring(Err) .. "\n")
    end
end

-- Hotkeys fire on the UE4SS input thread: only queue them, the game-thread tick runs them.
-- (Queued ExecuteInGameThread closures outlive the Lua state on auto-reload and crash the game.)
local PendingKeys = {}
local function OnKey(Handler)
    return function() PendingKeys[#PendingKeys + 1] = Handler end
end

function RunPendingKeys(PC)
    local Keys = PendingKeys
    PendingKeys = {}
    if UI.IsTyping() then return end
    for _, Handler in ipairs(Keys) do Handler(PC) end
end

local function Bind(Name, Handler)
    local B = Config.Keys[Name]
    if not B or not Key[B.Key] then return end
    local Mods = {}
    for _, M in ipairs(B.Modifiers or {}) do Mods[#Mods + 1] = ModifierKey[M] end
    if #Mods > 0 then
        RegisterKeyBind(Key[B.Key], Mods, OnKey(Handler))
    else
        RegisterKeyBind(Key[B.Key], OnKey(Handler))
    end
end

local function Rotate(PC, Delta)
    if State.Mode ~= "pasting" then return end
    State.Paste.Turns = (State.Paste.Turns + Delta) % 4
    State.Paste.Dirty = true
end

Bind("TogglePanel", function()
    UI.SetVisible(not UI.IsVisible())
    RefreshLibrary()
end)
Bind("SelectArea", StartSelect)
Bind("CopySelection", function(PC) HandleAction(PC, "CopySelection") end)
Bind("PasteClipboard", function(PC) HandleAction(PC, "PasteClipboard") end)
Bind("RotateClockwise", function(PC)
    if Game.IsKeyDown(PC, "LeftShift") or Game.IsKeyDown(PC, "RightShift") then return end
    Rotate(PC, 1)
end)
Bind("RotateCounterClockwise", function(PC) Rotate(PC, 3) end)

-- Game-thread tick: hooked on a GodPawn function the game calls every frame (see ZoomToCursor).
local TickHookPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:ArmLenght"
local TickHooked = false
local CleanedUp = false

local function OnFrame()
    if not CleanedUp then
        CleanedUp = true
        pcall(UI.CleanupLeftovers)
        pcall(Visuals.CleanupLeftovers)
    end
    SafeTick()
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

print(string.format("[Blueprints] Loaded, %d blueprints in library.\n", #State.Library))
