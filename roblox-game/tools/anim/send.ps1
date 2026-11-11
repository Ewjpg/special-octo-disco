# Runs a script inside the open Blender window (see blender_bridge.py) and prints its output.
#   powershell -File tools/anim/send.ps1 path\to\script.py [timeoutSeconds]
param([string]$Script, [int]$Timeout = 120)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$name = [IO.Path]::GetFileNameWithoutExtension($Script) + "_" + (Get-Date -Format "HHmmssfff")
$inbox = Join-Path $root "bridge\in"
$out = Join-Path $root "bridge\out\$name.txt"
New-Item -ItemType Directory -Force $inbox | Out-Null
# write under a temporary name, then rename, so Blender never reads half a file
Copy-Item $Script (Join-Path $inbox "$name.tmp")
Rename-Item (Join-Path $inbox "$name.tmp") "$name.py"
$deadline = (Get-Date).AddSeconds($Timeout)
while (-not (Test-Path $out)) {
    if ((Get-Date) -gt $deadline) { Write-Output "TIMEOUT: Blender did not answer (is the window open with the bridge?)"; exit 1 }
    Start-Sleep -Milliseconds 200
}
Start-Sleep -Milliseconds 100
Get-Content $out -Encoding UTF8
