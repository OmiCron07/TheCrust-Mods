<#
.SYNOPSIS
    Executes a Lua snippet inside the running game through the DevBridge UE4SS mod.
.DESCRIPTION
    Writes the snippet to the DevBridge command file, waits for the mod to execute it on the
    game thread, and prints the captured output. Use `out(...)` inside the snippet to emit
    values and the global table `S` to keep state between calls.
.PARAMETER Code
    Lua source to execute. Mutually exclusive with -File.
.PARAMETER File
    Path to a Lua file to execute.
.EXAMPLE
    .\Invoke-DevBridge.ps1 -Code 'out(FindFirstOf("GodPawn_C"):GetFullName())'
#>
param(
    [string]$Code,
    [string]$File,
    [int]$TimeoutSeconds = 15,
    [string]$BridgeDir = "D:\Games\Steam\steamapps\common\The Crust\TheCrust\Binaries\Win64\ue4ss\Mods\DevBridge\bridge"
)

$ErrorActionPreference = "Stop"
if ($File) { $Code = Get-Content -Raw $File }
if (-not $Code) { throw "Provide -Code or -File." }

$cmd = Join-Path $BridgeDir "cmd.lua"
$tmp = Join-Path $BridgeDir "cmd.tmp"
$out = Join-Path $BridgeDir "out.txt"

if (Test-Path $out) { Remove-Item $out -Force }
[System.IO.File]::WriteAllText($tmp, $Code)
Move-Item $tmp $cmd -Force

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not (Test-Path $out)) {
    if ((Get-Date) -gt $deadline) {
        if (Test-Path $cmd) { Remove-Item $cmd -Force }
        throw "DevBridge timeout: is the game running with the DevBridge mod loaded?"
    }
    Start-Sleep -Milliseconds 100
}
Get-Content -Raw $out
Remove-Item $out -Force
