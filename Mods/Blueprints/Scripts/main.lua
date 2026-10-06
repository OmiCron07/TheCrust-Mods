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
Config.PanelPosition = Config.PanelPosition or { X = 480, Y = 120 }

local Grid = require("grid")
local Game = require("game")
local Capture = require("capture")
local Placer = require("placer")
local Preview = require("preview")
local Visuals = require("visuals")
local UI = require("ui")
local Storage = require("storage")

local ScriptPath = debug.getinfo(1, "S").source:gsub("^@", "")
local ModDir = ScriptPath:gsub("[\\/]Scripts[\\/]main%.lua$", "")
local LibraryFile = ModDir .. "\\library.lua"

local Colors = {
    Selection = { R = 0.15, G = 0.45, B = 1.0, A = 0.22 },
    Module = { R = 0.25, G = 0.9, B = 1.0, A = 0.35 },
    Invalid = { R = 1.0, G = 0.15, B = 0.1, A = 1 },
    VeinOn = { R = 0.2, G = 1.0, B = 0.3, A = 1 },
    VeinOff = { R = 1.0, G = 0.3, B = 0.1, A = 1 },
    Belt = { R = 1.0, G = 0.75, B = 0.15, A = 0.55 },
}

local State = {
    Mode = "idle", -- idle | selecting | selected | pasting
    Library = Storage.Load(LibraryFile),
    PasteAsConstruction = Config.PasteAsConstruction == true,
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

-- Keybind cheat sheet shown in the panel, generated from the configured keys.
local KeyDescriptions = {
    { "TogglePanel", "Open / close this panel" },
    { "SelectArea", "Select an area (drag left mouse)" },
    { "CopySelection", "Copy the selection and paste it" },
    { "PasteClipboard", "Paste the clipboard again" },
    { "BuildSelection", "Build the ghosts of the selection" },
    { "TogglePasteMode", "Paste as plan / build" },
}

local function KeyLabel(Binding)
    if not Binding then return nil end
    local Parts, Has = {}, {}
    for _, M in ipairs(Binding.Modifiers or {}) do Has[M] = true end
    for _, M in ipairs({ { "CONTROL", "Ctrl" }, { "SHIFT", "Shift" }, { "ALT", "Alt" } }) do
        if Has[M[1]] then Parts[#Parts + 1] = M[2] end
    end
    Parts[#Parts + 1] = Binding.Key
    return table.concat(Parts, "+")
end

local function KeyHelp()
    local Lines = {}
    for _, D in ipairs(KeyDescriptions) do
        local Label = KeyLabel(Config.Keys[D[1]])
        if Label then Lines[#Lines + 1] = { Label, D[2] } end
    end
    local CW, CCW = KeyLabel(Config.Keys.RotateClockwise), KeyLabel(Config.Keys.RotateCounterClockwise)
    if CW or CCW then Lines[#Lines + 1] = { table.concat({ CW, CCW }, " / "), "Rotate while pasting" } end
    local Mirror = KeyLabel(Config.Keys.Mirror)
    if Mirror then Lines[#Lines + 1] = { Mirror, "Mirror while pasting" } end
    Lines[#Lines + 1] = { "Left click", "Place ghosts / drag the selection" }
    Lines[#Lines + 1] = { "Right click", "Clear selection / stop pasting" }
    return Lines
end

local function ClearMode()
    State.Mode = "idle"
    State.Anchor, State.Corner, State.Paste = nil, nil, nil
    Visuals.Hide()
    Preview.Stop()
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
    local As = State.PasteAsConstruction and "construction" or "planning ghosts"
    Notify("Pasting " .. Label .. Note .. " as " .. As .. ": left click places, R / Shift+R rotates, T mirrors, right click stops")
end

local function SelectionBox()
    return { State.Anchor[1], State.Anchor[2], State.Corner[1], State.Corner[2], Color = Colors.Selection, Height = 10, Outline = 0.15 }
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
    elseif Action == "Copy" then
        if HasSelection() then
            State.Clipboard = State.Captured
            Notify("Selection copied to the clipboard")
        else Notify("Select an area first") end
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
    elseif Action == "TogglePasteMode" then
        State.PasteAsConstruction = not State.PasteAsConstruction
        UI.SetPasteMode(State.PasteAsConstruction)
        Notify(State.PasteAsConstruction and "Paste mode: construction" or "Paste mode: planning ghosts")
    elseif Action == "BuildSelection" then
        local S = State.Selection
        if not (S and State.Mode == "selected") then Notify("Select an area first") return end
        local Report = Placer.BuildArea(PC, State.Layer, S.R0, S.C0, S.R1, S.C1)
        for _, E in ipairs(Report.Errors) do Log(E) end
        Notify(Placer.BuildSummary(Report))
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
    if not P.PreviewStarted then
        P.PreviewStarted = true
        Preview.Start(PC, State.Layer, P.BP, OR, OC)
    end
    if Cell ~= P.Cell or P.Dirty then
        P.Cell, P.Dirty = Cell, false
        local Valid, Veins = Preview.Evaluate(State.Geo, P.BP, OR, OC, P.Turns)
        local Boxes = Visuals.BlueprintBoxes(P.BP, OR, OC, P.Turns, Colors.Module, nil, Valid, Colors.Invalid)
        for _, V in ipairs(Veins) do
            local R, C = Grid.ToRowCol(V[1])
            Boxes[#Boxes + 1] = { R, C, R, C, Color = V[2] and Colors.VeinOn or Colors.VeinOff, Height = 16, Inset = 0.3 }
        end
        Visuals.Show(PC, State.Geo, Boxes)
        local CM = Game.ConveyorManager(PC, State.Layer)
        Visuals.ShowBelts(PC, State.Geo, CM.HoloSectionVisualManager, Grid.BeltVisuals(P.BP, OR, OC, P.Turns))
    end
    if LeftPressed and not UI.IsHovered() then
        local Options = {
            PasteConveyors = Config.PasteConveyors,
            PasteElectricLinks = Config.PasteElectricLinks,
            Construction = State.PasteAsConstruction,
        }
        local Report = Placer.Paste(PC, State.Layer, P.BP, Cell, P.Turns, Options)
        for _, E in ipairs(Report.Errors) do Log(E) end
        Notify(Placer.Summary(Report))
        Preview.Refresh(PC, State.Layer)
        P.Dirty = true
    end
end

local RunPendingKeys -- Defined with the hotkey queue below.

-- Forgets all UObject references of the previous world: touching them after a save load crashes.
local function ForgetSession()
    UI.Forget()
    Visuals.Forget()
    Preview.Forget()
    State.Mode, State.Anchor, State.Corner, State.Paste, State.Captured = "idle", nil, nil, nil, nil
    State.Session = nil
end

local WarmupFrames = 60

local function Tick(Pawn)
    local PC = Game.PCFromPawn(Pawn)
    if not PC or Game.IsLoading() then
        if State.Session then ForgetSession() end
        return
    end
    local Session = Game.SessionKey(PC)
    if Session ~= State.Session then
        ForgetSession()
        State.Session, State.Warmup = Session, WarmupFrames
        return
    end
    if State.Warmup > 0 then
        State.Warmup = State.Warmup - 1
        return
    end

    RunPendingKeys(PC)
    if not UI.IsCreated() then
        Visuals.CleanupLeftovers()
        UI.Create(PC, Config.PanelPosition, KeyHelp())
        UI.SetPasteMode(State.PasteAsConstruction)
        RefreshLibrary()
    end

    -- Nothing else to do while idle with the panel closed (keeps the per-frame cost minimal).
    if State.Mode == "idle" and not UI.IsVisible() then
        State.Left, State.Right = false, false
        return
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
local function SafeTick(Pawn)
    local Ok, Err = pcall(Tick, Pawn)
    if not Ok and Err ~= LastError then
        LastError = Err
        print("[Blueprints] Tick error: " .. tostring(Err) .. "\n")
    end
end

-- Hotkeys fire on the UE4SS input thread: only queue them, the game-thread tick runs them.
-- (Queued ExecuteInGameThread closures outlive the Lua state on auto-reload and crash the game.)
local PendingKeys = {}
local function OnKey(Handler, Modifiers)
    return function() PendingKeys[#PendingKeys + 1] = { Handler = Handler, Modifiers = Modifiers } end
end

local ModifierKeyNames = {
    CONTROL = { "LeftControl", "RightControl" },
    SHIFT = { "LeftShift", "RightShift" },
    ALT = { "LeftAlt", "RightAlt" },
}

-- UE4SS may also fire a binding when extra modifiers are held: require the exact modifier set.
local function ModifiersMatch(PC, Wanted)
    for Name, Keys in pairs(ModifierKeyNames) do
        local Down = Game.IsKeyDown(PC, Keys[1]) or Game.IsKeyDown(PC, Keys[2])
        if Down ~= (Wanted[Name] == true) then return false end
    end
    return true
end

function RunPendingKeys(PC)
    local Keys = PendingKeys
    PendingKeys = {}
    if UI.IsTyping() then return end
    for _, K in ipairs(Keys) do
        if ModifiersMatch(PC, K.Modifiers) then K.Handler(PC) end
    end
end

local function Bind(Name, Handler)
    local B = Config.Keys[Name]
    if not B or not Key[B.Key] then return end
    local Mods, Wanted = {}, {}
    for _, M in ipairs(B.Modifiers or {}) do
        Mods[#Mods + 1] = ModifierKey[M]
        Wanted[M] = true
    end
    if #Mods > 0 then
        RegisterKeyBind(Key[B.Key], Mods, OnKey(Handler, Wanted))
    else
        RegisterKeyBind(Key[B.Key], OnKey(Handler, Wanted))
    end
end

local function Rotate(PC, Delta)
    if State.Mode ~= "pasting" then return end
    State.Paste.Turns = (State.Paste.Turns + Delta) % 4
    State.Paste.Dirty = true
end

-- Swaps in a mirrored copy (the clipboard / library blueprint stays as is); the preview restarts
-- because its extractor probes were spawned with the previous mirror state.
local function Mirror(PC)
    if State.Mode ~= "pasting" then return end
    local P = State.Paste
    P.BP = Capture.Mirror(P.BP)
    P.Dirty, P.PreviewStarted = true, false
end

Bind("TogglePanel", function()
    UI.SetVisible(not UI.IsVisible())
    RefreshLibrary()
end)
Bind("SelectArea", StartSelect)
Bind("CopySelection", function(PC) HandleAction(PC, "CopySelection") end)
Bind("PasteClipboard", function(PC) HandleAction(PC, "PasteClipboard") end)
Bind("BuildSelection", function(PC) HandleAction(PC, "BuildSelection") end)
Bind("TogglePasteMode", function(PC) HandleAction(PC, "TogglePasteMode") end)
Bind("RotateClockwise", function(PC) Rotate(PC, 1) end)
Bind("RotateCounterClockwise", function(PC) Rotate(PC, 3) end)
Bind("Mirror", Mirror)

-- Game-thread tick: hooked on a GodPawn function the game calls every frame (see ZoomToCursor).
local TickHookPath = "/Game/Blueprints/Core/GodPawn.GodPawn_C:ArmLenght"
local TickHooked = false

local function OnFrame(Context)
    SafeTick(Context:get())
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
