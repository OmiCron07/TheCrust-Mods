<#
.SYNOPSIS
    Builds the release zips of the mods: one zip per mod plus one zip with all mods.
.DESCRIPTION
    Each zip mirrors the game root layout, so extracting it into "<Steam>\steamapps\common\The Crust"
    installs the mod. Two kinds of mod folders under Mods\:
    - Lua mod (Scripts\main.lua): dropped into TheCrust\Binaries\Win64\ue4ss\Mods\<Mod>, with an
      enabled.txt that makes UE4SS start the mod without editing mods.txt.
    - Game files mod (TheCrust\ subfolder): its TheCrust\ tree is shipped as is.
    Each zip also holds an INSTALL-<Mod>.txt at its root (install steps followed by the mod README).
    Markdown files of the mod folder are not shipped.
.PARAMETER Mods
    Mod folder names under Mods\ to package. Defaults to every mod folder except DevBridge
    (development tool, never shipped).
.PARAMETER OutputDir
    Folder receiving the zips (recreated on each run).
.EXAMPLE
    .\Scripts\Build-ModRelease.ps1
#>
param(
    [Parameter()]
    [string[]]$Mods = (Get-ChildItem -Directory (Join-Path (Split-Path -Parent $PSScriptRoot) "Mods") |
        Where-Object Name -ne "DevBridge" | ForEach-Object Name),

    [Parameter()]
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path -Parent $PSScriptRoot
$modsInGame = "TheCrust/Binaries/Win64/ue4ss/Mods"
$stageRoot = Join-Path $OutputDir "stage"

function Get-InstallText([string]$ModName, [bool]$IsGameFiles) {
    $readme = Get-Content -Raw (Join-Path $projectRoot "Mods/$ModName/README.md")
    if ($IsGameFiles) {
        $requirements = "None (this mod replaces game files, UE4SS is not needed)."
        $result = "The mod files overwrite the matching files in the game folder."
        $update = @"
Quit the game, then extract the new zip the same way. A game update or a Steam
"Verify integrity of game files" restores the original files: extract the zip again afterwards.
"@
        $uninstall = @"
Steam > Library > The Crust > right click > Properties > Installed Files >
Verify integrity of game files. Steam downloads the original files back.
"@
    } else {
        $requirements = @"
UE4SS v3 must be installed in the game (tested with v3.0.2, experimental build):
https://github.com/UE4SS-RE/RE-UE4SS/releases
Extract the UE4SS zip into "The Crust\TheCrust\Binaries\Win64" (dwmapi.dll next to the game exe).
"@
        $result = @"
The mod lands in "TheCrust\Binaries\Win64\ue4ss\Mods\$ModName". The enabled.txt file in the mod
   folder makes UE4SS load the mod; no need to edit mods.txt.
"@
        $update = @"
Quit the game, then extract the new zip the same way. Extracting overwrites Scripts\config.lua:
back it up first if you customized it.
"@
        $uninstall = @"
Delete the "TheCrust\Binaries\Win64\ue4ss\Mods\$ModName" folder
(or only its enabled.txt to disable it, as long as mods.txt does not list "$ModName : 1").
"@
    }
    @"
$ModName - mod for The Crust
$('=' * ($ModName.Length + 25))

Requirements
------------
$requirements

Install
-------
1. Quit the game. Open the game folder: Steam > Library > The Crust > right click > Manage >
   Browse local files. It is the folder containing "TheCrust"
   (e.g. C:\Program Files (x86)\Steam\steamapps\common\The Crust).
2. Extract this zip into that folder and accept to merge folders / overwrite files.
   $result
3. Start the game.
This INSTALL-$ModName.txt file can be deleted after extraction.

Update
------
$update

Uninstall
---------
$uninstall

Mod documentation
-----------------

$readme
"@
}

function New-ModStage([string]$ModName, [string]$StageDir) {
    $source = Join-Path $projectRoot "Mods/$ModName"
    $gameFiles = Join-Path $source "TheCrust"
    $isGameFiles = Test-Path $gameFiles
    if ($isGameFiles) {
        $destination = Join-Path $StageDir "TheCrust"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path "$gameFiles/*" -Destination $destination -Recurse -Force
    } elseif (Test-Path (Join-Path $source "Scripts/main.lua")) {
        $destination = Join-Path $StageDir "$modsInGame/$ModName"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path "$source/*" -Destination $destination -Recurse -Exclude "*.md"
        Set-Content -Path (Join-Path $destination "enabled.txt") -Value "" -NoNewline
    } else {
        throw "Mod '$ModName' has neither Scripts/main.lua nor a TheCrust folder: $source"
    }
    Set-Content -Path (Join-Path $StageDir "INSTALL-$ModName.txt") -Value (Get-InstallText $ModName $isGameFiles)
}

function New-Zip([string]$StageDir, [string]$ZipName) {
    $zipPath = Join-Path $OutputDir $ZipName
    # ZipFile writes forward-slash entry names on every platform (Compress-Archive on 5.1 does not).
    [System.IO.Compression.ZipFile]::CreateFromDirectory($StageDir, $zipPath)
    Write-Host "[OK] $zipPath" -ForegroundColor Green
}

if (Test-Path $OutputDir) { Remove-Item -Path $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

foreach ($mod in $Mods) {
    $stage = Join-Path $stageRoot $mod
    New-ModStage $mod $stage
    New-Zip $stage "TheCrust-$mod.zip"
}

$allStage = Join-Path $stageRoot "_All"
foreach ($mod in $Mods) { New-ModStage $mod $allStage }
New-Zip $allStage "TheCrust-AllMods.zip"

Remove-Item -Path $stageRoot -Recurse -Force
