<#
.SYNOPSIS
  Builds the bundled llama.cpp for Tesla V100 (sm_70) on Windows 11.

.DESCRIPTION
  Requirements (see README.md):
    * Visual Studio 2022 or Build Tools 2022 with "Desktop development with C++"
      (includes CMake and Ninja)
    * CUDA Toolkit 12.x (12.9 recommended). CUDA 13+ does NOT support V100.
    * NVIDIA driver from the 580 branch or older (last branch supporting Volta)

  Binaries end up in .\build\bin (llama-server.exe, llama-cli.exe, llama-bench.exe, ...).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
.EXAMPLE
  .\scripts\build-windows.ps1 -NoHttps -CMakeArgs "-DGGML_NATIVE=OFF"
#>
param(
    [string]   $BuildDir  = "",
    [string]   $CudaPath  = "",
    [switch]   $NoHttps,              # skip bundled BoringSSL (no -hf model downloads)
    [string[]] $CMakeArgs = @()
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $BuildDir) { $BuildDir = Join-Path $Root "build" }

# --- Visual Studio developer environment -----------------------------------
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found - install Visual Studio 2022 / Build Tools 2022." }

# Prefer VS 2022 (officially supported by CUDA 12.x), fall back to the newest one.
$vsPath = & $vswhere -products * -version "[17.0,18.0)" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$unsupportedHost = $false
if (-not $vsPath) {
    $vsPath = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $unsupportedHost = $true
}
if (-not $vsPath) { throw "No Visual Studio with the C++ toolset found." }
Write-Host "Visual Studio: $vsPath"

Import-Module (Join-Path $vsPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null

# --- CUDA 12.x ---------------------------------------------------------------
if (-not $CudaPath) {
    $cudaVars = Get-ChildItem env: | Where-Object { $_.Name -match '^CUDA_PATH_V12_(\d+)$' } |
        Sort-Object { [int]($_.Name -replace '^CUDA_PATH_V12_', '') } -Descending
    if ($cudaVars) { $CudaPath = $cudaVars[0].Value } elseif ($env:CUDA_PATH) { $CudaPath = $env:CUDA_PATH }
}
$nvcc = Join-Path $CudaPath "bin\nvcc.exe"
if (-not $CudaPath -or -not (Test-Path $nvcc)) { throw "CUDA Toolkit 12.x not found. Install CUDA 12.9 or pass -CudaPath." }

$nvccVersion = (& $nvcc --version) -join "`n"
if ($nvccVersion -match 'release (\d+)\.(\d+)') {
    if ([int]$Matches[1] -ge 13) {
        throw "nvcc at $nvcc is CUDA $($Matches[1]).$($Matches[2]). CUDA 13+ cannot compile for V100 (sm_70). Install CUDA 12.9 and pass -CudaPath."
    }
    Write-Host "CUDA: $CudaPath ($($Matches[1]).$($Matches[2]))"
}
$env:CUDA_PATH = $CudaPath
$env:PATH = "$CudaPath\bin;$env:PATH"

# --- Configure & build -------------------------------------------------------
$args_ = @(
    "-S", (Join-Path $Root "llama.cpp"),
    "-B", $BuildDir,
    "-G", "Ninja",
    "-C", (Join-Path $Root "cmake\v100.cmake"),
    "-DCMAKE_C_COMPILER=cl",
    "-DCMAKE_CXX_COMPILER=cl",
    "-DCMAKE_CUDA_COMPILER=$($nvcc -replace '\\','/')"
)
if (-not $NoHttps)       { $args_ += "-DLLAMA_BUILD_BORINGSSL=ON" }
if ($unsupportedHost)    {
    Write-Warning "Visual Studio 2022 not found, using a newer MSVC with -allow-unsupported-compiler."
    $args_ += "-DCMAKE_CUDA_FLAGS=-Wno-deprecated-gpu-targets -allow-unsupported-compiler"
}
$args_ += $CMakeArgs

& cmake @args_
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed." }

& cmake --build $BuildDir --config Release -j $env:NUMBER_OF_PROCESSORS
if ($LASTEXITCODE -ne 0) { throw "Build failed." }

# Copy the CUDA runtime DLLs next to the binaries so they run without CUDA in PATH.
$bin = Join-Path $BuildDir "bin"
Get-ChildItem (Join-Path $CudaPath "bin") -Filter "*.dll" |
    Where-Object { $_.Name -match '^(cudart64|cublas64|cublasLt64)_' } |
    Copy-Item -Destination $bin -Force

Write-Host ""
Write-Host "Build finished: $bin"
