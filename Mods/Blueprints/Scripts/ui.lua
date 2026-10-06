-- Blueprint manager panel built at runtime from raw UMG widgets (no cooked widget asset), styled with
-- the game's own UI assets: layered T_Panel10 panel brushes, T_Btn_Tab1 buttons, Bahnschrift font.
-- Lua cannot bind UMG delegates, so buttons are polled (pressed -> released while hovered = click).

local Game = require("game")

local UI = {}

local PanelName = "BlueprintsModPanel"
local RowsPerPage = 8

local UIPack = "/Game/Proto/SCIFIUIPACK_PROV2/Textures/"
local Assets = {
    Font = "/Game/Fonts/Bahnshrift/bahnschrift_Font.bahnschrift_Font",
    PanelFill = UIPack .. "Components_V2/Components_V2_Customizable2/T_Panel10_White1.T_Panel10_White1",
    PanelGlow = UIPack .. "Components_V2/Components_V2_Customizable2/T_Panel10_White2.T_Panel10_White2",
    PanelLine = UIPack .. "Components_V2/Components_V2_Customizable2/T_Panel10_White3.T_Panel10_White3",
    Button = UIPack .. "ExampleSceneV2/Demo_Buttons/T_Btn_Tab1_n_Saturated.T_Btn_Tab1_n_Saturated",
    ButtonHover = UIPack .. "ExampleSceneV2/Demo_Buttons/T_Btn_Tab1_s_Saturated.T_Btn_Tab1_s_Saturated",
}

-- Colors sampled from the vanilla widgets (module panel, BUILD button, tabs).
local Colors = {
    Fill = { R = 0.0, G = 0.01, B = 0.03, A = 0.88 },
    Glow = { R = 0.22, G = 0.60, B = 0.81, A = 0.30 },
    Line = { R = 0.22, G = 0.60, B = 0.81, A = 0.58 },
    Title = { R = 0.50, G = 0.84, B = 0.96, A = 1 },
    Text = { R = 0.90, G = 0.94, B = 0.97, A = 1 },
    Dim = { R = 0.56, G = 0.68, B = 0.78, A = 1 },
    Key = { R = 1.0, G = 0.78, B = 0.40, A = 1 },
    Blue = { R = 0.40, G = 0.63, B = 1.0, A = 1 },
    Green = { R = 0.12, G = 1.0, B = 0.24, A = 1 },
    Red = { R = 1.0, G = 0.30, B = 0.18, A = 1 },
}

local Root, Panel, StatusText, SelectionText, NameBox, PageText, ModeLabel
local Buttons = {}      -- { Widget, Action, Arg, WasPressed }
local Rows = {}         -- { Box, Label, DeleteLabel }
local Page = 0
local AnyPressed = false
local PendingDelete     -- library index awaiting delete confirmation
local PendingConfirm    -- Confirm button awaiting its second click
local Visible = false
local Loaded = {}

local function Load(Path)
    if Loaded[Path] ~= nil then return Loaded[Path] or nil end
    local Obj = StaticFindObject(Path)
    if not Game.Valid(Obj) then
        pcall(function() LoadAsset((Path:gsub("%.[^%.]+$", ""))) end)
        Obj = StaticFindObject(Path)
    end
    Loaded[Path] = Game.Valid(Obj) and Obj or false
    return Loaded[Path] or nil
end

local function New(ClassName, Outer, Name)
    local Cls = StaticFindObject("/Script/UMG." .. ClassName)
    return StaticConstructObject(Cls, Outer, FName(Name))
end

-- Object names must be unique per mod instance: StaticConstructObject with the name of an existing
-- object (left by a previous instance after a UE4SS auto-reload) reconstructs that object in place,
-- which leaves the new panel's buttons dead.
local Instance = string.format("%x%04x", os.time(), math.random(0, 0xFFFF))
local Counter = 0
local function Make(ClassName)
    Counter = Counter + 1
    return New(ClassName, Panel.WidgetTree, PanelName .. "_" .. Instance .. "_" .. ClassName .. Counter)
end

-- Box (9-slice) brush on a game texture; without the texture it degrades to a flat tinted box.
local function StyleBrush(Brush, TexturePath, Tint, Margin)
    local Tex = TexturePath and Load(TexturePath)
    if Tex then
        Brush.ResourceObject = Tex
        pcall(function() Brush.ImageSize = { X = Tex:Blueprint_GetSizeX(), Y = Tex:Blueprint_GetSizeY() } end)
    end
    Brush.DrawAs = 1
    Brush.Margin = { Left = Margin or 0.25, Top = Margin or 0.25, Right = Margin or 0.25, Bottom = Margin or 0.25 }
    Brush.TintColor = { SpecifiedColor = Tint, ColorUseRule = 0 }
end

local function SetFont(TextWidget, Size)
    pcall(function()
        local Font = TextWidget.Font
        local Face = Load(Assets.Font)
        if Face then
            Font.FontObject = Face
            Font.TypefaceFontName = FName("Default")
        end
        Font.Size = Size
        TextWidget:SetFont(Font)
    end)
end

local function Text(Str, Size, Color)
    local T = Make("TextBlock")
    T:SetText(FText(Str))
    SetFont(T, Size or 12)
    T:SetColorAndOpacity({ SpecifiedColor = Color or Colors.Text, ColorUseRule = 0 })
    return T
end

local function Pad(Slot, L, T, R, B)
    pcall(function() Slot:SetPadding({ Left = L, Top = T, Right = R or L, Bottom = B or T }) end)
end

-- Confirm: the first click only turns the label into "Confirm?" (any other button resets it).
local function Button(Label, Action, Arg, Tint, Confirm)
    local B = Make("Button")
    pcall(function()
        local Style = B.WidgetStyle
        StyleBrush(Style.Normal, Assets.Button, Tint or Colors.Blue)
        StyleBrush(Style.Hovered, Assets.ButtonHover, Tint or Colors.Blue)
        StyleBrush(Style.Pressed, Assets.Button, Tint or Colors.Blue)
        Style.NormalPadding = { Left = 10, Top = 3, Right = 10, Bottom = 3 }
        Style.PressedPadding = { Left = 10, Top = 4, Right = 10, Bottom = 2 }
    end)
    local T = Text(Label, 12)
    B:SetContent(T)
    Buttons[#Buttons + 1] = { Widget = B, Action = Action, Arg = Arg, Label = T, Text = Label, Confirm = Confirm }
    return B, T
end

local function HRow(Parent, Children, Top)
    local H = Make("HorizontalBox")
    for _, C in ipairs(Children) do
        Pad(H:AddChildToHorizontalBox(C), 0, 0, 6, 0)
    end
    Pad(Parent:AddChildToVerticalBox(H), 0, Top or 3, 0, 3)
    return H
end

-- Section title with a thin separator line under it, like the vanilla panels.
local function Section(Parent, Title)
    Pad(Parent:AddChildToVerticalBox(Text(Title, 13, Colors.Title)), 0, 10, 0, 2)
    local Line = Make("Image")
    StyleBrush(Line.Brush, nil, Colors.Line, 0)
    local Size = Make("SizeBox")
    Size:SetHeightOverride(1)
    Size:SetContent(Line)
    Pad(Parent:AddChildToVerticalBox(Size), 0, 0, 0, 4)
end

local function Layer(Overlay, TexturePath, Tint)
    local Img = Make("Image")
    StyleBrush(Img.Brush, TexturePath, Tint)
    local Slot = Overlay:AddChildToOverlay(Img)
    Slot:SetHorizontalAlignment(0) -- HAlign_Fill
    Slot:SetVerticalAlignment(0)   -- VAlign_Fill
end

-- Removes panels left in the viewport by a previous instance of the mod (hot reload).
function UI.CleanupLeftovers()
    for _, W in ipairs(FindAllOf("UserWidget") or {}) do
        if Game.Valid(W) and W:GetFName():ToString():find(PanelName, 1, true) then
            pcall(function() W:RemoveFromParent() end)
        end
    end
end

-- Drops every widget reference without touching them (they may belong to a destroyed world).
function UI.Forget()
    Root, Panel, StatusText, SelectionText, NameBox, PageText, ModeLabel = nil, nil, nil, nil, nil, nil, nil
    AnyPressed = false
    Buttons, Rows, Visible, PendingDelete, PendingConfirm, Loaded = {}, {}, false, nil, nil, {}
end

-- KeyHelp: array of { Keys, Description } shown in the Keybinds section.
function UI.Create(PC, Position, KeyHelp)
    UI.CleanupLeftovers()
    Buttons, Rows, Counter, PendingConfirm = {}, {}, 0, nil
    Instance = string.format("%x%04x", os.time(), math.random(0, 0xFFFF))
    Panel = New("UserWidget", PC, PanelName .. "_" .. Instance)
    Panel.WidgetTree = New("WidgetTree", Panel, PanelName .. "_" .. Instance .. "_Tree")

    local Canvas = Make("CanvasPanel")
    Panel.WidgetTree.RootWidget = Canvas
    Canvas:SetVisibility(4) -- SelfHitTestInvisible: never block clicks outside the panel.

    Root = Make("Overlay")
    local Slot = Canvas:AddChildToCanvas(Root)
    Slot:SetAutoSize(true)
    -- Anchored to the top-right corner, left of the vanilla module panel.
    Slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
    Slot:SetAlignment({ X = 1, Y = 0 })
    Slot:SetPosition({ X = -Position.X, Y = Position.Y })

    Layer(Root, Assets.PanelFill, Colors.Fill)
    Layer(Root, Assets.PanelGlow, Colors.Glow)
    Layer(Root, Assets.PanelLine, Colors.Line)

    -- Content padding through a transparent Border (overlay slot padding is not applied).
    local Content = Make("Border")
    Content:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
    Content:SetPadding({ Left = 18, Top = 14, Right = 18, Bottom = 16 })
    Root:AddChildToOverlay(Content)
    local V = Make("VerticalBox")
    Content:SetContent(V)

    Pad(V:AddChildToVerticalBox(Text("BLUEPRINTS", 20, Colors.Title)), 0, 0, 0, 2)
    StatusText = Text("Ready", 11, Colors.Dim)
    Pad(V:AddChildToVerticalBox(StatusText), 0, 2)

    Section(V, "SELECTION")
    HRow(V, {
        (Button("Select area", "SelectArea")),
        (Button("Copy", "Copy")),
        (Button("Copy + paste", "CopySelection")),
        (Button("Paste clipboard", "PasteClipboard")),
    })
    local ModeButton
    ModeButton, ModeLabel = Button("Paste as: Plan", "TogglePasteMode")
    HRow(V, {
        ModeButton,
        (Button("Build selection", "BuildSelection", nil, Colors.Green)),
        (Button("Cut", "Cut")),
        (Button("Delete", "DeleteSelection", nil, Colors.Red, true)),
    })
    SelectionText = Text("No selection", 11, Colors.Dim)
    Pad(V:AddChildToVerticalBox(SelectionText), 0, 4)

    NameBox = Make("EditableTextBox")
    pcall(function() NameBox:SetHintText(FText("Blueprint name")) end)
    local NameSize = Make("SizeBox")
    NameSize:SetWidthOverride(230)
    NameSize:SetContent(NameBox)
    HRow(V, { NameSize, (Button("Save selection", "SaveSelection", nil, Colors.Green)) })

    Section(V, "LIBRARY")
    for i = 1, RowsPerPage do
        local Place = Button("Place", "Place", i, Colors.Green)
        local Rename = Button("Rename", "Rename", i)
        local Delete, DeleteLabel = Button("Delete", "Delete", i, Colors.Red)
        local Label = Text("", 12)
        local Box = HRow(V, { Place, Rename, Delete, Label }, 2)
        Rows[i] = { Box = Box, Label = Label, DeleteLabel = DeleteLabel }
    end
    PageText = Text("", 11, Colors.Dim)
    HRow(V, { (Button("<", "PrevPage")), (Button(">", "NextPage")), PageText }, 4)

    Section(V, "KEYBINDS")
    for _, Help in ipairs(KeyHelp or {}) do
        local KeyText = Text(Help[1], 12, Colors.Key)
        local KeySize = Make("SizeBox")
        KeySize:SetWidthOverride(120)
        KeySize:SetContent(KeyText)
        HRow(V, { KeySize, Text(Help[2], 12, Colors.Text) }, 0)
    end

    Panel:SetOwningPlayer(PC)
    Panel:AddToViewport(50)
    UI.SetVisible(false)
end

function UI.IsCreated()
    return Game.Valid(Panel)
end

function UI.SetVisible(Show)
    Visible = Show
    if Game.Valid(Panel) then Panel:SetVisibility(Show and 4 or 1) end
end

function UI.IsVisible()
    return Visible and Game.Valid(Panel)
end

function UI.IsHovered()
    return UI.IsVisible() and Root:IsHovered()
end

function UI.IsTyping()
    return UI.IsVisible() and NameBox:HasKeyboardFocus()
end

function UI.SetStatus(Str)
    if Game.Valid(StatusText) then StatusText:SetText(FText(Str)) end
end

function UI.SetPasteMode(Construction)
    if Game.Valid(ModeLabel) then
        ModeLabel:SetText(FText(Construction and "Paste as: Build" or "Paste as: Plan"))
    end
end

function UI.SetSelectionInfo(Str)
    if Game.Valid(SelectionText) then SelectionText:SetText(FText(Str)) end
end

function UI.GetName()
    if not Game.Valid(NameBox) then return "" end
    return (NameBox:GetText():ToString():gsub("^%s+", ""):gsub("%s+$", ""))
end

function UI.SetName(Str)
    if Game.Valid(NameBox) then NameBox:SetText(FText(Str)) end
end

-- Library: array of blueprints (uses .Name and .Summary).
function UI.SetLibrary(Library)
    if not UI.IsCreated() then return end
    local Pages = math.max(1, math.ceil(#Library / RowsPerPage))
    Page = math.max(0, math.min(Page, Pages - 1))
    for i, Row in ipairs(Rows) do
        local Index = Page * RowsPerPage + i
        local BP = Library[Index]
        Row.Box:SetVisibility(BP and 0 or 1)
        if BP then
            Row.Label:SetText(FText(string.format("%s   %s", BP.Name, BP.Summary or "")))
            Row.DeleteLabel:SetText(FText(PendingDelete == Index and "Confirm?" or "Delete"))
        end
    end
    local Empty = #Library == 0 and "  -  save a selection to start your library" or ""
    PageText:SetText(FText(string.format("Page %d / %d  (%d blueprints)%s", Page + 1, Pages, #Library, Empty)))
end

-- Returns clicked actions as array of { Action, Index } (Index = library index for row buttons).
function UI.Poll()
    local Events = {}
    if not UI.IsVisible() then return Events end
    -- Per-frame cost: only poll the buttons while the cursor is over the panel or a press is pending.
    if not AnyPressed and not Root:IsHovered() then return Events end
    AnyPressed = false
    for _, B in ipairs(Buttons) do
        local Pressed = B.Widget:IsPressed()
        AnyPressed = AnyPressed or Pressed
        if B.WasPressed and not Pressed and B.Widget:IsHovered() then
            local Index = B.Arg and (Page * RowsPerPage + B.Arg)
            local Confirming = PendingConfirm
            if Confirming then
                PendingConfirm = nil
                Confirming.Label:SetText(FText(Confirming.Text))
            end
            if B.Confirm and Confirming ~= B then
                PendingConfirm = B
                B.Label:SetText(FText("Confirm?"))
            elseif B.Action == "PrevPage" then
                Page = Page - 1
            elseif B.Action == "NextPage" then
                Page = Page + 1
            elseif B.Action == "Delete" and PendingDelete ~= Index then
                PendingDelete = Index
                Events[#Events + 1] = { Action = "Refresh" }
            else
                if B.Action == "Delete" then PendingDelete = nil end
                Events[#Events + 1] = { Action = B.Action, Index = Index }
            end
            if B.Action == "PrevPage" or B.Action == "NextPage" then
                Events[#Events + 1] = { Action = "Refresh" }
            end
        end
        B.WasPressed = Pressed
    end
    return Events
end

return UI
