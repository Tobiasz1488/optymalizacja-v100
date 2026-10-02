# Quick V100 benchmark: prompt processing and generation, FlashAttention off/on.
#   .\scripts\bench.ps1 models\model.gguf
param([Parameter(Mandatory = $true)] [string] $Model)
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $Root "build\bin\llama-bench.exe") -m $Model -ngl 999 -fa 0,1 -p 512,4096 -n 128 -ub 512
