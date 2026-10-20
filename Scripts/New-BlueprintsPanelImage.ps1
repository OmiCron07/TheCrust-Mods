<#
.SYNOPSIS
    Renders the annotated Blueprints panel image used by the READMEs.
.DESCRIPTION
    Draws numbered boxes over a raw in-game capture of the Blueprints panel and a legend on the right
    (System.Drawing, no extra dependency). Numbers follow the panel order and must match the
    "The panel" table of Mods/Blueprints/README.md.
.PARAMETER Screenshot
    Raw panel capture (default Docs/Images/blueprints-panel-raw.png, 977 x 797).
.PARAMETER Out
    Output PNG (default Docs/Images/blueprints-panel.png).
.EXAMPLE
    .\Scripts\New-BlueprintsPanelImage.ps1
#>
param(
    [string]$Screenshot = (Join-Path $PSScriptRoot "..\Docs\Images\blueprints-panel-raw.png"),
    [string]$Out = (Join-Path $PSScriptRoot "..\Docs\Images\blueprints-panel.png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# ponytail: box coordinates are pixels of the 977 x 797 raw capture; re-measure them when the panel
# layout or the capture changes (no element detection).
# Number, x0, y0, x1, y1, marker position ('corner' = top-right corner, 'right' = right of the box).
$Boxes = @(
    @(1, 4, 38, 452, 57, 'right'),
    @(2, 4, 92, 99, 118, 'corner'),
    @(3, 104, 92, 157, 118, 'corner'),
    @(4, 161, 92, 265, 118, 'corner'),
    @(5, 268, 92, 390, 118, 'corner'),
    @(6, 4, 121, 116, 148, 'corner'),
    @(7, 120, 121, 238, 148, 'corner'),
    @(8, 241, 121, 353, 148, 'corner'),
    @(9, 356, 121, 401, 148, 'corner'),
    @(10, 404, 121, 467, 148, 'corner'),
    @(11, 4, 152, 80, 169, 'right'),
    @(12, 4, 172, 335, 200, 'corner'),
    @(13, 338, 172, 404, 200, 'corner'),
    @(14, 4, 233, 63, 261, 'corner'),
    @(15, 66, 233, 139, 261, 'corner'),
    @(16, 141, 233, 216, 261, 'corner'),
    @(17, 219, 233, 280, 261, 'corner'),
    @(18, 282, 233, 345, 261, 'corner'),
    @(19, 4, 463, 206, 491, 'right'),
    @(20, 4, 499, 972, 790, 'corner')
)

$Legend = @(
    @('Status line', 'Result of the last action and what to do next.'),
    @('Select area  -  Ctrl+K', 'Press and drag over the area. Right click cancels.'),
    @('Copy  -  Ctrl+Insert', 'Copies the selection without pasting.'),
    @('Copy + paste  -  Ctrl+Shift+K', 'Copies the selection and starts pasting it.'),
    @('Paste clipboard  -  Alt+K', 'Pastes the last copied, cut or placed blueprint again.'),
    @('Paste as: Plan / Build  -  Ctrl+Alt+K', 'Plan: ghosts built later. Build: construction starts now.'),
    @('Build selection  -  Shift+K', 'Starts construction of the ghosts in the selection.'),
    @('Upgrade belts', 'Raises the belts of the selection by one tier.'),
    @('Cut  -  Shift+Delete', 'Deletes the selection and starts pasting it.'),
    @('Delete  -  Delete', 'Deletes the selection (click twice: "Confirm?").'),
    @('Selection info', 'What the selection captured: modules, belts, wires...'),
    @('Name + Save selection', 'Saves the selection to the library (empty: "Blueprint N").'),
    @('Import', 'Adds a TCBP1 share string (name box or Windows clipboard).'),
    @('Place', 'Starts pasting that blueprint.'),
    @('Replace', 'Overwrites that blueprint with the selection (click twice).'),
    @('Rename', 'Type the new name in the name box first.'),
    @('Share', 'Copies its share string to the Windows clipboard.'),
    @('Delete', 'Deletes that blueprint (click twice: "Confirm?").'),
    @('Pages', '8 blueprints per page, newest first.'),
    @('Keybinds', 'Hotkey reminder (keys are set in Scripts/config.lua).')
)

$Shot = [System.Drawing.Image]::FromFile((Resolve-Path $Screenshot))
$W, $H = 1820, 1520
$Bmp = New-Object System.Drawing.Bitmap $W, $H
$G = [System.Drawing.Graphics]::FromImage($Bmp)
$G.SmoothingMode = 'AntiAlias'
$G.TextRenderingHint = 'AntiAliasGridFit'
$G.Clear([System.Drawing.Color]::FromArgb(255, 16, 26, 36))

$Px, $Py = 40, [int](($H - $Shot.Height) / 2)
$G.DrawImage($Shot, $Px, $Py, $Shot.Width, $Shot.Height)

$Orange = [System.Drawing.Color]::FromArgb(255, 244, 181, 63)
$Pen = New-Object System.Drawing.Pen $Orange, 2.5
$Fill = New-Object System.Drawing.SolidBrush $Orange
$Dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 20, 20))
$TitleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 240, 245))
$DescBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 170, 182, 194))
$Px_ = [System.Drawing.GraphicsUnit]::Pixel
$FontMark = New-Object System.Drawing.Font 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold), $Px_
$FontBig = New-Object System.Drawing.Font 'Segoe UI', 16, ([System.Drawing.FontStyle]::Bold), $Px_
$FontTitle = New-Object System.Drawing.Font 'Segoe UI', 25, ([System.Drawing.FontStyle]::Regular), $Px_
$FontDesc = New-Object System.Drawing.Font 'Segoe UI', 20, ([System.Drawing.FontStyle]::Regular), $Px_
$Center = New-Object System.Drawing.StringFormat
$Center.Alignment = 'Center'
$Center.LineAlignment = 'Center'

function Draw-Marker($Cx, $Cy, $R, $N, $Font) {
    $G.FillEllipse($Fill, $Cx - $R, $Cy - $R, 2 * $R, 2 * $R)
    $Rect = New-Object System.Drawing.RectangleF ($Cx - $R), ($Cy - $R + 1), (2 * $R), (2 * $R)
    $G.DrawString("$N", $Font, $Dark, $Rect, $Center)
}

# Boxes first, markers on top so a marker is never hidden by a neighbour's box.
foreach ($B in $Boxes) {
    $G.DrawRectangle($Pen, $Px + $B[1], $Py + $B[2], $B[3] - $B[1], $B[4] - $B[2])
}
foreach ($B in $Boxes) {
    if ($B[5] -eq 'right') { Draw-Marker ($Px + $B[3] + 16) ($Py + ($B[2] + $B[4]) / 2) 12 $B[0] $FontMark }
    else { Draw-Marker ($Px + $B[3]) ($Py + $B[2]) 12 $B[0] $FontMark }
}

$Lx, $Ly, $Step = 1110, 34, 73
for ($i = 0; $i -lt $Legend.Count; $i++) {
    Draw-Marker ($Lx - 50) ($Ly + 18) 18 ($i + 1) $FontBig
    $G.DrawString($Legend[$i][0], $FontTitle, $TitleBrush, $Lx, $Ly)
    $G.DrawString($Legend[$i][1], $FontDesc, $DescBrush, $Lx, ($Ly + 33))
    $Ly += $Step
}

$Bmp.Save((Join-Path (Resolve-Path (Split-Path $Out)) (Split-Path $Out -Leaf)), [System.Drawing.Imaging.ImageFormat]::Png)
$G.Dispose(); $Bmp.Dispose(); $Shot.Dispose()
Write-Host "[OK] $Out" -ForegroundColor Green
