<#
.SYNOPSIS
    Installs or uninstalls UE4SS (Unreal Engine 4 Scripting System) into The Crust.
.PARAMETER GameBinariesDir
    The path to The Crust's Win64 binaries directory.
.PARAMETER Uninstall
    Remove UE4SS files from the game directory.
.EXAMPLE
    .\Setup-UE4SS.ps1
    .\Setup-UE4SS.ps1 -Uninstall
#>
param(
    [Parameter()]
    [string]$GameBinariesDir = "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64",

    [Parameter()]
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$ue4ssSourceDir = Join-Path $projectRoot "Tools\UE4SS"

if (-not (Test-Path $GameBinariesDir)) {
    throw "Game Win64 binaries directory not found: $GameBinariesDir"
}

$destDwmapi = Join-Path $GameBinariesDir "dwmapi.dll"
$destUe4ssDir = Join-Path $GameBinariesDir "ue4ss"

if ($Uninstall) {
    Write-Host "[+] Uninstalling UE4SS from '$GameBinariesDir'..." -ForegroundColor Yellow
    if (Test-Path $destDwmapi) {
        Remove-Item -Path $destDwmapi -Force
        Write-Host "    [OK] Removed dwmapi.dll" -ForegroundColor Green
    }
    if (Test-Path $destUe4ssDir) {
        Remove-Item -Path $destUe4ssDir -Recurse -Force
        Write-Host "    [OK] Removed ue4ss folder" -ForegroundColor Green
    }
    Write-Host "[OK] UE4SS uninstalled successfully." -ForegroundColor Green
    return
}

Write-Host "[+] Installing UE4SS into '$GameBinariesDir'..." -ForegroundColor Yellow

# Copy proxy dll
$sourceDwmapi = Join-Path $ue4ssSourceDir "dwmapi.dll"
if (Test-Path $sourceDwmapi) {
    Copy-Item -Path $sourceDwmapi -Destination $destDwmapi -Force
    Write-Host "    [OK] Deployed dwmapi.dll (proxy loader)" -ForegroundColor Green
} else {
    throw "dwmapi.dll not found in $ue4ssSourceDir"
}

# Copy ue4ss directory
$sourceUe4ss = Join-Path $ue4ssSourceDir "ue4ss"
if (Test-Path $sourceUe4ss) {
    if (-not (Test-Path $destUe4ssDir)) {
        New-Item -ItemType Directory -Path $destUe4ssDir -Force | Out-Null
    }
    Copy-Item -Path "$sourceUe4ss\*" -Destination $destUe4ssDir -Recurse -Force
    Write-Host "    [OK] Deployed ue4ss folder (runtime, mods, config)" -ForegroundColor Green
} else {
    throw "ue4ss folder not found in $ue4ssSourceDir"
}

Write-Host "[OK] UE4SS successfully installed! Launch the game to generate logs and verify." -ForegroundColor Green
