# Initial CMake cache for llama.cpp tuned for NVIDIA Tesla V100 32GB (Volta, sm_70).
# Used by scripts/build-ubuntu.sh and scripts/build-windows.ps1 via `cmake -C`.
# Every value can still be overridden with -D on the command line.

set(CMAKE_BUILD_TYPE Release CACHE STRING "")

# --- CUDA backend -----------------------------------------------------------
set(GGML_CUDA ON CACHE BOOL "")

# Compile ONLY real sm_70 code: no PTX JIT on first start, smaller binary,
# much shorter build, and ggml picks its Volta-specific code paths
# (MMQ, MMVQ, FlashAttention WMMA) based on the highest compiled arch.
set(CMAKE_CUDA_ARCHITECTURES "70-real" CACHE STRING "")

# CUDA 12.x warns that sm_70 is deprecated; it is still fully supported in 12.x.
set(CMAKE_CUDA_FLAGS "-Wno-deprecated-gpu-targets" CACHE STRING "")

# FlashAttention kernels (-fa on). V100 has no BF16, so instead of the
# upstream default (which includes bf16-bf16) compile the KV-cache types
# that make sense on Volta. f16-f16 is always included.
set(GGML_CUDA_FA ON CACHE BOOL "")
set(GGML_CUDA_FA_QUANTS "q8_0-q8_0,q4_0-q4_0,q8_0-q4_0,q5_0-q5_0,q8_0-f16" CACHE STRING "")

# CUDA graphs cut kernel-launch overhead during token generation.
set(GGML_CUDA_GRAPHS ON CACHE BOOL "")

# Keep the fatbin uncompressed: slightly faster start, size does not matter
# with a single architecture.
set(GGML_CUDA_COMPRESSION_MODE "none" CACHE STRING "")

# --- CPU side (host of the V100) --------------------------------------------
# Optimize the CPU code for the machine you build on (offloaded layers,
# sampling, tokenization). Set -DGGML_NATIVE=OFF to build portable binaries.
set(GGML_NATIVE ON CACHE BOOL "")

# --- What to build ----------------------------------------------------------
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "")
set(LLAMA_BUILD_TOOLS    ON  CACHE BOOL "")
set(LLAMA_BUILD_SERVER   ON  CACHE BOOL "")
