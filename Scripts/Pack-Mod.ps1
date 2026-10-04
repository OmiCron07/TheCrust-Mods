<#
.SYNOPSIS
    Packs a mod folder into an Unreal Engine 4.27 .pak file for The Crust using repak.
.PARAMETER ModSourceDir
    The root folder of the mod files to pack (should contain Content/...).
.PARAMETER OutputPakPath
    The destination path for the generated .pak file.
.PARAMETER PakVersion
    Unreal pak version (default: V11 for UE 4.27).
.PARAMETER Compression
    Compression algorithm: Zlib, None, Oodle, or Zstd (default: Zlib).
.PARAMETER MountPoint
    Custom mount point for the pak file (default: ../../../TheCrust/Content/).
.EXAMPLE
    .\Pack-Mod.ps1 -ModSourceDir "K:\GameMods\TheCrust\Mods\SampleMod" -OutputPakPath "K:\GameMods\TheCrust\Mods\SampleMod_P.pak"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ModSourceDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputPakPath,

    [Parameter()]
    [string]$PakVersion = "V11",

    [Parameter()]
    [string]$Compression = "Zlib",

    [Parameter()]
    [string]$MountPoint = "../../../TheCrust/Content/"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$repakExe = Join-Path $projectRoot "Tools\repak\repak.exe"

if (-not (Test-Path $repakExe)) {
    throw "repak executable not found at: $repakExe"
}

if (-not (Test-Path $ModSourceDir)) {
    throw "Mod source directory not found: $ModSourceDir"
}

$outputDir = Split-Path -Parent $OutputPakPath
if ($outputDir -and (-not (Test-Path $outputDir))) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Host "[+] Packing '$ModSourceDir' -> '$OutputPakPath'..." -ForegroundColor Yellow
Write-Host "    Version: $PakVersion | Compression: $Compression | Mount Point: $MountPoint" -ForegroundColor DarkGray

& $repakExe pack "$ModSourceDir" "$OutputPakPath" --version "$PakVersion" --compression "$Compression" --mount-point "$MountPoint"

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Successfully packed mod: $OutputPakPath" -ForegroundColor Green
} else {
    throw "repak failed with exit code $LASTEXITCODE"
}
