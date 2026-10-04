<#
.SYNOPSIS
    Deploys a Lua mod folder into The Crust's UE4SS Mods directory.
.PARAMETER ModSourceDir
    The source mod folder (e.g. K:\GameMods\TheCrust\Mods\SampleLuaMod).
.PARAMETER TargetUe4ssModsDir
    Path to the active UE4SS Mods folder.
.EXAMPLE
    .\Deploy-Lua-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\CustomCheats"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ModSourceDir,

    [Parameter()]
    [string]$TargetUe4ssModsDir = "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64\ue4ss\Mods"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ModSourceDir)) {
    throw "Mod source folder not found at: $ModSourceDir"
}

$modName = Split-Path -Leaf $ModSourceDir
$destination = Join-Path $TargetUe4ssModsDir $modName

if (-not (Test-Path $destination)) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

Copy-Item -Path "$ModSourceDir\*" -Destination $destination -Recurse -Force
Write-Host "[OK] Lua mod '$modName' deployed to: $destination" -ForegroundColor Green

# Ensure mod is enabled in mods.txt
$modsTxtPath = Join-Path $TargetUe4ssModsDir "mods.txt"
if (Test-Path $modsTxtPath) {
    $content = Get-Content $modsTxtPath -Raw
    if ($content -notmatch "(?m)^$modName\s*:\s*1") {
        Write-Host "[+] Adding '$modName : 1' to mods.txt" -ForegroundColor Yellow
        "`n$modName : 1" | Out-File -FilePath $modsTxtPath -Append -Encoding utf8
    }
}
