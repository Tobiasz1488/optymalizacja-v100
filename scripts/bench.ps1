# V100 benchmark: prompt processing (pp) and generation (tg) at empty and long
# context, f16 vs q8_0 KV cache, all with FlashAttention.
#   .\scripts\bench.ps1 models\model.gguf
param([Parameter(Mandatory = $true)] [string] $Model, [string[]] $Extra = @())
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$b = Join-Path $Root "build\bin\llama-bench.exe"
if (-not (Test-Path $b)) { throw "$b not found - run scripts\build-windows.ps1 first." }
foreach ($kv in "f16", "q8_0") {
    & $b -m $Model -ngl 999 -fa 1 -ctk $kv -ctv $kv -p 512 -n 128 -d 0,16384 -ub 512,1024 -lm none @Extra
}
