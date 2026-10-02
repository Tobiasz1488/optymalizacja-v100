<#
.SYNOPSIS
  Starts llama-server with defaults tuned for a single Tesla V100 32GB.
.EXAMPLE
  .\scripts\run-server.ps1 -Model models\model.gguf
.EXAMPLE
  .\scripts\run-server.ps1 -Model models\model.gguf -Ctx 65536 -Kv q4_0 -Extra "--parallel","2"
#>
param(
    [Parameter(Mandatory = $true)] [string] $Model,
    [int]      $Ctx    = 32768,
    [string]   $Kv     = "q8_0",
    [int]      $Ubatch = 512,
    [string]   $HostName = "127.0.0.1",
    [int]      $Port   = 8080,
    [string[]] $Extra  = @()
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$exe  = Join-Path $Root "build\bin\llama-server.exe"

& $exe -m $Model -ngl 999 -fa on -c $Ctx -ctk $Kv -ctv $Kv -b 2048 -ub $Ubatch `
    --host $HostName --port $Port @Extra
