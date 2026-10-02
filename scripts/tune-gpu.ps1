<#
.SYNOPSIS
  Sets every Tesla V100 to its highest application clocks and maximum power limit.
  Run from an elevated (Administrator) PowerShell. Settings reset on reboot.
.EXAMPLE
  .\scripts\tune-gpu.ps1
.EXAMPLE
  .\scripts\tune-gpu.ps1 -Reset
#>
param([switch] $Reset)
$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Run this script as Administrator." }

foreach ($i in (& nvidia-smi --query-gpu=index --format=csv,noheader)) {
    $i = $i.Trim()
    $name = (& nvidia-smi -i $i --query-gpu=name --format=csv,noheader).Trim()
    if ($name -notmatch "V100") { Write-Host "GPU ${i}: $name - skipped"; continue }

    if ($Reset) {
        & nvidia-smi -i $i -rac | Out-Null
        $def = (& nvidia-smi -i $i --query-gpu=power.default_limit --format=csv,noheader,nounits).Trim()
        & nvidia-smi -i $i -pl $def | Out-Null
        Write-Host "GPU ${i}: $name - defaults restored"
        continue
    }

    $clocks = & nvidia-smi -i $i --query-supported-clocks=mem,gr --format=csv,noheader,nounits |
        ForEach-Object { $p = $_ -split ',\s*'; [pscustomobject]@{ Mem = [int]$p[0]; Gr = [int]$p[1] } }
    $mem = ($clocks | Measure-Object Mem -Maximum).Maximum
    $gr  = ($clocks | Where-Object Mem -eq $mem | Measure-Object Gr -Maximum).Maximum
    & nvidia-smi -i $i -ac "$mem,$gr" | Out-Null

    $pl = (& nvidia-smi -i $i --query-gpu=power.max_limit --format=csv,noheader,nounits).Trim()
    & nvidia-smi -i $i -pl $pl | Out-Null

    Write-Host "GPU ${i}: $name - application clocks $mem/$gr MHz, power limit $pl W"
}
