<#
.SYNOPSIS
  Starts llama-server with defaults tuned for a single Tesla V100 32GB.
.EXAMPLE
  .\scripts\run-server.ps1 -Model models\model.gguf
.EXAMPLE
  .\scripts\run-server.ps1 -Model models\model.gguf -Ctx 65536 -Kv q4_0 -Extra "--parallel","2"
.EXAMPLE
  .\scripts\run-server.ps1 -Model models\model.gguf -Spec mtp
  Speculative decoding: "mtp" = built-in MTP heads of the model (Qwen3.5+ etc.),
  "ngram" = n-gram lookup; -DraftModel small.gguf = separate draft model.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Model,
    [int]      $Ctx    = 32768,
    [string]   $Kv     = "f16",   # q8_0/q4_0 only if out of VRAM - slower on Volta
    [int]      $Ubatch = 512,
    [string]   $HostName = "127.0.0.1",
    [int]      $Port   = 8080,
    [string]   $Spec   = "",      # "", "mtp", "ngram" or any --spec-type value
    [string]   $DraftModel = "",  # small draft model with the same tokenizer
    [string[]] $Extra  = @()
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$exe  = Join-Path $Root "build\bin\llama-server.exe"
if (-not (Test-Path $exe)) { throw "$exe not found - run scripts\build-windows.ps1 first." }

$specArgs = @()
switch ($Spec) {
    ""      { }
    "mtp"   { $specArgs += "--spec-type", "draft-mtp" }
    "ngram" { $specArgs += "--spec-type", "ngram-mod" }
    default { $specArgs += "--spec-type", $Spec }
}
if ($DraftModel) {
    $specArgs += "-md", $DraftModel, "-ngld", "999"
    if (-not $Spec) { $specArgs += "--spec-type", "draft-simple" }
}

# -lm none (no mmap): on Windows loading through mmap is slow and keeps a second copy of
# the weights in the page cache although every layer lives on the GPU.
& $exe -m $Model -ngl 999 -fa on -c $Ctx -ctk $Kv -ctv $Kv -b 2048 -ub $Ubatch -lm none `
    --host $HostName --port $Port @specArgs @Extra
