-- Blueprint manager panel built at runtime from raw UMG widgets (no cooked widget asset).
-- Lua cannot bind UMG delegates, so buttons are polled (pressed -> released while hovered = click).

local Game = require("game")

local UI = {}

local PanelName = "BlueprintsModPanel"
local RowsPerPage = 10

local Root, Panel, StatusText, SelectionText, NameBox, PageText
local Buttons = {}      -- { Widget, Action, Arg, WasPressed }
local Rows = {}         -- { Box, Label, Place, Rename, Delete }
local Page = 0
local PendingDelete     -- library index awaiting delete confirmation
local Visible = false

local Colors = {
    Panel = { R = 0.015, G = 0.02, B = 0.03, A = 0.88 },
    Title = { R = 0.95, G = 0.75, B = 0.3, A = 1 },
    Text = { R = 0.85, G = 0.88, B = 0.92, A = 1 },
    Dim = { R = 0.55, G = 0.6, B = 0.65, A = 1 },
    Button = { R = 0.12, G = 0.16, B = 0.22, A = 1 },
    Danger = { R = 0.45, G = 0.1, B = 0.08, A = 1 },
}

local function New(ClassName, Outer, Name)
    local Cls = StaticFindObject("/Script/UMG." .. ClassName)
    return StaticConstructObject(Cls, Outer, FName(Name))
end

local Counter = 0
local function Make(ClassName)
    Counter = Counter + 1
    return New(ClassName, Panel.WidgetTree, PanelName .. "_" .. ClassName .. Counter)
end

local function SetFontSize(TextWidget, Size)
    pcall(function()
        local Font = TextWidget.Font
        Font.Size = Size
        TextWidget:SetFont(Font)
    end)
end

local function Text(Str, Size, Color)
    local T = Make("TextBlock")
    T:SetText(FText(Str))
    SetFontSize(T, Size or 12)
    T:SetColorAndOpacity({ SpecifiedColor = Color or Colors.Text, ColorUseRule = 0 })
    return T
end

local function Pad(Slot, L, T, R, B)
    pcall(function() Slot:SetPadding({ Left = L, Top = T, Right = R or L, Bottom = B or T }) end)
end

local function Button(Label, Action, Arg, Color)
    local B = Make("Button")
    B:SetBackgroundColor(Color or Colors.Button)
    local T = Text(Label, 11)
    B:SetContent(T)
    Buttons[#Buttons + 1] = { Widget = B, Action = Action, Arg = Arg, Label = T }
    return B, T
end

local function HRow(Parent, Children)
    local H = Make("HorizontalBox")
    for _, C in ipairs(Children) do
        Pad(H:AddChildToHorizontalBox(C), 0, 0, 6, 0)
    end
    Pad(Parent:AddChildToVerticalBox(H), 0, 3)
    return H
end

-- Removes panels left in the viewport by a previous instance of the mod (hot reload).
function UI.CleanupLeftovers()
    for _, W in ipairs(FindAllOf("UserWidget") or {}) do
        if Game.Valid(W) and W:GetFName():ToString():find(PanelName, 1, true) then
            pcall(function() W:RemoveFromParent() end)
        end
    end
end

function UI.Create(PC, Position)
    Buttons, Rows, Counter = {}, {}, 0
    Panel = New("UserWidget", PC, PanelName)
    Panel.WidgetTree = New("WidgetTree", Panel, PanelName .. "_Tree")

    local Canvas = Make("CanvasPanel")
    Panel.WidgetTree.RootWidget = Canvas
    Canvas:SetVisibility(4) -- SelfHitTestInvisible: never block clicks outside the panel.

    Root = Make("Border")
    Root:SetBrushColor(Colors.Panel)
    pcall(function() Root:SetPadding({ Left = 12, Top = 10, Right = 12, Bottom = 10 }) end)
    local Slot = Canvas:AddChildToCanvas(Root)
    Slot:SetAutoSize(true)
    Slot:SetPosition(Position)

    local V = Make("VerticalBox")
    Root:SetContent(V)

    Pad(V:AddChildToVerticalBox(Text("BLUEPRINTS", 16, Colors.Title)), 0, 0, 0, 4)
    StatusText = Text("", 11, Colors.Dim)
    Pad(V:AddChildToVerticalBox(StatusText), 0, 2)

    HRow(V, {
        (Button("Select area", "SelectArea")),
        (Button("Copy + paste", "CopySelection")),
        (Button("Paste clipboard", "PasteClipboard")),
    })

    SelectionText = Text("No selection", 11, Colors.Dim)
    Pad(V:AddChildToVerticalBox(SelectionText), 0, 4)

    NameBox = Make("EditableTextBox")
    pcall(function() NameBox:SetHintText(FText("Blueprint name")) end)
    local NameSize = Make("SizeBox")
    NameSize:SetWidthOverride(220)
    NameSize:SetContent(NameBox)
    HRow(V, { NameSize, (Button("Save selection", "SaveSelection")) })

    Pad(V:AddChildToVerticalBox(Text("Library", 13, Colors.Title)), 0, 8, 0, 2)
    for i = 1, RowsPerPage do
        local Place = Button("Place", "Place", i)
        local Rename = Button("Rename", "Rename", i)
        local Delete, DeleteLabel = Button("Delete", "Delete", i, Colors.Danger)
        local Label = Text("", 11)
        local Box = HRow(V, { Place, Rename, Delete, Label })
        Rows[i] = { Box = Box, Label = Label, DeleteLabel = DeleteLabel }
    end

    PageText = Text("", 11, Colors.Dim)
    HRow(V, { (Button("< Prev", "PrevPage")), (Button("Next >", "NextPage")), PageText })

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
            Row.Label:SetText(FText(string.format("%s   [%s]", BP.Name, BP.Summary or "")))
            Row.DeleteLabel:SetText(FText(PendingDelete == Index and "Confirm?" or "Delete"))
        end
    end
    PageText:SetText(FText(string.format("Page %d / %d  (%d blueprints)", Page + 1, Pages, #Library)))
end

-- Returns clicked actions as array of { Action, Index } (Index = library index for row buttons).
function UI.Poll()
    local Events = {}
    if not UI.IsVisible() then return Events end
    for _, B in ipairs(Buttons) do
        local Pressed = B.Widget:IsPressed()
        if B.WasPressed and not Pressed and B.Widget:IsHovered() then
            local Index = B.Arg and (Page * RowsPerPage + B.Arg)
            if B.Action == "PrevPage" then
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
