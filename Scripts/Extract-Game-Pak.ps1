<#
.SYNOPSIS
    Extracts an Unreal Engine .pak file from The Crust using repak.
.PARAMETER PakPath
    Path to the .pak file to extract.
.PARAMETER OutputDir
    Destination directory where assets will be unpacked.
.EXAMPLE
    .\Extract-Game-Pak.ps1 -PakPath "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Content\Paks\pakchunk1-WindowsNoEditor.pak" -OutputDir "K:\GameMods\TheCrust\Extracted\pakchunk1"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PakPath,

    [Parameter()]
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$repakExe = Join-Path $projectRoot "Tools\repak\repak.exe"

if (-not (Test-Path $repakExe)) {
    throw "repak executable not found at: $repakExe"
}

if (-not (Test-Path $PakPath)) {
    throw "Pak file not found: $PakPath"
}

if (-not $OutputDir) {
    $pakName = [System.IO.Path]::GetFileNameWithoutExtension($PakPath)
    $OutputDir = Join-Path $projectRoot "Extracted\$pakName"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "[+] Extracting '$PakPath' -> '$OutputDir'..." -ForegroundColor Yellow
& $repakExe unpack "$PakPath" "$OutputDir"

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Successfully unpacked into: $OutputDir" -ForegroundColor Green
} else {
    throw "repak failed with exit code $LASTEXITCODE"
}
