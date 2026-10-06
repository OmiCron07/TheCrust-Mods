<#
.SYNOPSIS
    Captures one frame of The Crust window to PNG via ffmpeg's gfxcapture (Windows.Graphics.Capture).
.DESCRIPTION
    GDI capture returns black frames for GPU-rendered games; gfxcapture grabs the real frames of one
    window even when it is covered (not when minimized). The image is the client area in physical
    pixels, the same coordinate space as Invoke-WinDrive.ps1. With -Scale also writes <name>_small.png,
    a cheap copy for review (multiply its coordinates by 1/Scale).
    Requires ffmpeg 8+ with the gfxcapture filter. Adapted from universal-modder `um win shot` (MIT).
.PARAMETER Exe
    Executable name of the window to capture.
.PARAMETER Out
    Output PNG. Defaults to Captures\<timestamp>.png.
.PARAMETER Scale
    Optional downscale factor for the extra _small copy (e.g. 0.33).
.EXAMPLE
    .\Get-GameScreenshot.ps1 -Scale 0.33
#>
param(
    [string]$Exe = "TheCrust-Win64-Shipping.exe",
    [string]$Out,
    [double]$Scale = 0
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $Out) { $Out = Join-Path $projectRoot ("Captures\" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".png") }
New-Item -ItemType Directory -Path (Split-Path -Parent $Out) -Force | Out-Null

if (-not ((ffmpeg -hide_banner -h filter=gfxcapture 2>&1) -match "window_exe")) {
    throw "ffmpeg missing or built without gfxcapture (needs FFmpeg 8+)."
}

# Windows Auto HDR washes out SDR captures (odd AutoHDREnable = on). Per-game key wins over the global one.
$prefs = Get-ItemProperty "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -ErrorAction SilentlyContinue
if ($prefs) {
    $entry = $prefs.PSObject.Properties | Where-Object { $_.Name -like "*\$Exe" } | Select-Object -First 1
    if (-not $entry) { $entry = $prefs.PSObject.Properties["DirectXUserGlobalSettings"] }
    if ($entry -and $entry.Value -match 'AutoHDREnable=(\d+)' -and [int]$Matches[1] % 2 -eq 1) {
        Write-Warning "Auto HDR is on: capture colours will be washed out. Settings > System > Display > Graphics > (game) > Auto HDR."
    }
}

$exeRegex = "(?i)^" + [regex]::Escape($Exe) + "$"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "gfxcapture=window_exe=${exeRegex}:capture_cursor=0,hwdownload,format=bgra" -frames:v 1 $Out
if ($LASTEXITCODE -or -not (Test-Path $Out)) { throw "Capture failed: is the game window open and not minimized?" }
$Out

if ($Scale -gt 0) {
    $small = [IO.Path]::ChangeExtension($Out, $null).TrimEnd('.') + "_small.png"
    ffmpeg -hide_banner -loglevel error -y -i $Out -vf "scale=iw*${Scale}:-1:flags=lanczos" $small
    $small
}
