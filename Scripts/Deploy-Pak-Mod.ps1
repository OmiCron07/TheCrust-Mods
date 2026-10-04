<#
.SYNOPSIS
    Deploys a packed .pak mod file to The Crust's ~mods directory.
.PARAMETER ModPakPath
    The path to the .pak file to deploy.
.PARAMETER GamePaksDir
    The target Paks directory in the game.
.EXAMPLE
    .\Deploy-Pak-Mod.ps1 -ModPakPath "K:\GameMods\TheCrust\Mods\SampleMod_P.pak"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ModPakPath,

    [Parameter()]
    [string]$GamePaksDir = "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Paks"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ModPakPath)) {
    throw "Mod pak file not found: $ModPakPath"
}

if (-not (Test-Path $GamePaksDir)) {
    throw "Game Paks directory not found: $GamePaksDir"
}

$modsDir = Join-Path $GamePaksDir "~mods"
if (-not (Test-Path $modsDir)) {
    Write-Host "[+] Creating '~mods' directory at: $modsDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
}

$fileName = Split-Path -Leaf $ModPakPath
$destFile = Join-Path $modsDir $fileName

Copy-Item -Path $ModPakPath -Destination $destFile -Force
Write-Host "[OK] Pak mod '$fileName' successfully deployed to: $destFile" -ForegroundColor Green
