<#
.SYNOPSIS
    Manages intro and startup cinematics for The Crust by disabling, restoring, or inspecting them.

.DESCRIPTION
    Replaces long startup logos and narrative intro cinematics with an ultra-short (0.04s) blank video,
    bypassing the mandatory unskippable/5-second hold delays without crashing the Unreal Engine media player.
    Original movie files are safely preserved in a backup directory on the same drive.

.PARAMETER Action
    Disable : Backs up original videos and installs 1-frame dummy files.
    Enable  : Restores original videos from the backup folder.
    Status  : Reports the current state of each cinematic file.

.PARAMETER Scope
    All     : Manages both startup logos and story intro cinematics.
    Startup : Manages only startup logos (UE logo, Veom/Crytivo logos, title animation).
    Story   : Manages only campaign story intro cutscenes (radio talk intro, falling cosmonaut).

.PARAMETER GameDir
    Path to The Crust game installation root directory.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Disable", "Enable", "Status")]
    [string]$Action = "Disable",

    [Parameter()]
    [ValidateSet("All", "Startup", "Story")]
    [string]$Scope = "All",

    [Parameter()]
    [string]$GameDir = "D:\Games\Steam\steamapps\common\The Crust"
)

$ErrorActionPreference = "Stop"

$moviesDir = Join-Path $GameDir "TheCrust\Content\Movies"
$backupDir = Join-Path $moviesDir "_OriginalCinematicsBackup"
$blankVideoSource = Join-Path $PSScriptRoot "..\Assets\blank.mp4"

if (-not (Test-Path $moviesDir)) {
    throw "Movies directory not found at '$moviesDir'. Please check -GameDir parameter."
}

if (-not (Test-Path $blankVideoSource)) {
    throw "Blank video asset not found at '$blankVideoSource'."
}

if ($Action -in @("Disable", "Enable")) {
    $gameProc = Get-Process | Where-Object { $_.ProcessName -match "^TheCrust" }
    if ($gameProc) {
        Write-Warning "The Crust is currently running ($($gameProc.ProcessName -join ', ')). Files in Content\Movies may be locked."
        Write-Warning "Please close the game before modifying or restoring video files."
    }
}

$startupFiles = @(
    "UE_moving_logo_v01_1080.mp4",
    "LogoRevealCut.mp4",
    "The_crust_short_V3.mp4"
)

$storyFiles = @(
    "FINALCutwithSFX.mp4",
    "FallingAstronaut.mp4"
)

$targetFiles = switch ($Scope) {
    "Startup" { $startupFiles }
    "Story"   { $storyFiles }
    "All"     { $startupFiles + $storyFiles }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " The Crust - Intro Cinematics Manager    " -ForegroundColor Cyan
Write-Host " Action: $Action | Scope: $Scope         " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Movies Directory : $moviesDir"
Write-Host "Backup Directory : $backupDir`n"

switch ($Action) {
    "Status" {
        $results = foreach ($file in $targetFiles) {
            $filePath = Join-Path $moviesDir $file
            $backupPath = Join-Path $backupDir $file

            $currentState = "Missing"
            $sizeStr = "N/A"
            $hasBackup = Test-Path $backupPath

            if (Test-Path $filePath) {
                $item = Get-Item $filePath
                $sizeBytes = $item.Length
                if ($sizeBytes -lt 10000) {
                    $currentState = "Disabled (Blank Dummy)"
                } else {
                    $currentState = "Active (Original)"
                }
                $sizeStr = [string]::Format("{0:N2} MB", ($sizeBytes / 1MB))
            }

            [PSCustomObject]@{
                File      = $file
                Status    = $currentState
                Size      = $sizeStr
                BackedUp  = $hasBackup
            }
        }
        $results | Format-Table -AutoSize
    }

    "Disable" {
        if (-not (Test-Path $backupDir)) {
            Write-Host "Creating backup directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        foreach ($file in $targetFiles) {
            $filePath = Join-Path $moviesDir $file
            $backupPath = Join-Path $backupDir $file

            if (-not (Test-Path $filePath)) {
                Write-Host "[-] Skipping $($file): Not found in Movies directory." -ForegroundColor DarkGray
                continue
            }

            $currentFile = Get-Item $filePath
            if ($currentFile.Length -lt 10000) {
                Write-Host "[*] $($file) is already disabled (dummy file present)." -ForegroundColor DarkYellow
                continue
            }

            if (-not (Test-Path $backupPath)) {
                Write-Host "[+] Backing up original $($file) ($([math]::Round($currentFile.Length / 1MB, 2)) MB)..." -ForegroundColor Green
                Move-Item -Path $filePath -Destination $backupPath -Force
            } else {
                Write-Host "[!] Backup already exists for $($file). Removing original in Movies dir..." -ForegroundColor Yellow
                Remove-Item -Path $filePath -Force
            }

            Write-Host "[+] Installing 0.04s blank dummy for $($file)..." -ForegroundColor Cyan
            Copy-Item -Path $blankVideoSource -Destination $filePath -Force
        }

        Write-Host "`nAll selected cinematics have been successfully disabled!" -ForegroundColor Green
        Write-Host "The game will now start or skip scenes without video delay." -ForegroundColor Green
    }

    "Enable" {
        if (-not (Test-Path $backupDir)) {
            Write-Host "No backup directory found at '$backupDir'. Nothing to restore." -ForegroundColor Yellow
            return
        }

        foreach ($file in $targetFiles) {
            $filePath = Join-Path $moviesDir $file
            $backupPath = Join-Path $backupDir $file

            if (Test-Path $backupPath) {
                Write-Host "[+] Restoring $file from backup..." -ForegroundColor Green
                Move-Item -Path $backupPath -Destination $filePath -Force
            } else {
                Write-Host "[-] No backup found for $file, keeping current file." -ForegroundColor DarkGray
            }
        }

        $remainingBackups = Get-ChildItem -Path $backupDir -File
        if ($remainingBackups.Count -eq 0) {
            Remove-Item -Path $backupDir -Force -Recurse
            Write-Host "Cleaned up empty backup directory." -ForegroundColor DarkGray
        }

        Write-Host "`nRestoration complete. Original cinematics are restored." -ForegroundColor Green
    }
}
