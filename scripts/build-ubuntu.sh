#!/usr/bin/env bash
# Builds the bundled llama.cpp for Tesla V100 (sm_70) on Ubuntu 24.04.
#
#   ./scripts/build-ubuntu.sh                 # Release build into ./build
#   ./scripts/build-ubuntu.sh -DGGML_NATIVE=OFF   # extra -D options are passed to cmake
#
# Binaries end up in ./build/bin (llama-server, llama-cli, llama-bench, ...).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

# Locate nvcc: $CUDA_HOME, then the newest /usr/local/cuda-12.x, then PATH.
if [[ -z "${CUDA_HOME:-}" ]]; then
    CUDA_HOME=$(ls -d /usr/local/cuda-12.* 2>/dev/null | sort -V | tail -1 || true)
fi
if [[ -n "${CUDA_HOME:-}" && -x "$CUDA_HOME/bin/nvcc" ]]; then
    NVCC="$CUDA_HOME/bin/nvcc"
else
    NVCC=$(command -v nvcc || true)
fi
if [[ -z "$NVCC" ]]; then
    echo "nvcc not found. Run ./scripts/setup-ubuntu.sh first or set CUDA_HOME." >&2
    exit 1
fi

CUDA_MAJOR=$("$NVCC" --version | sed -n 's/.*release \([0-9]*\)\..*/\1/p')
if [[ "$CUDA_MAJOR" -ge 13 ]]; then
    echo "Error: $NVCC is CUDA $CUDA_MAJOR. CUDA 13+ cannot compile for V100 (sm_70)." >&2
    echo "Install CUDA 12.x (./scripts/setup-ubuntu.sh) and set CUDA_HOME=/usr/local/cuda-12.9" >&2
    exit 1
fi
# Toolkit root of the selected nvcc. Passed to CMake explicitly, otherwise
# FindCUDAToolkit may pick /usr/local/cuda, which can point to another version.
CUDA_ROOT=$(dirname "$(dirname "$(readlink -f "$NVCC")")")
echo "Using $NVCC (CUDA $CUDA_MAJOR, toolkit $CUDA_ROOT)"

EXTRA=()
command -v ninja >/dev/null && EXTRA+=(-G Ninja)

# Without the NVIDIA driver there is no libcuda.so.1 and linking the executables
# fails (undefined reference to cuGetErrorString). The binaries still need the
# driver at runtime; this only allows building before it is installed.
if ! grep -q 'libcuda\.so\.1' <<<"$(ldconfig -p 2>/dev/null)"; then
    echo "Warning: NVIDIA driver (libcuda.so.1) not found - linking against the CUDA stub." >&2
    EXTRA+=(-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined)
fi

cmake -S "$ROOT/llama.cpp" -B "$BUILD_DIR" "${EXTRA[@]}" \
    -C "$ROOT/cmake/v100.cmake" \
    -DCMAKE_CUDA_COMPILER="$NVCC" \
    -DCUDAToolkit_ROOT="$CUDA_ROOT" \
    "$@"

cmake --build "$BUILD_DIR" --config Release -j "$(nproc)"

echo
echo "Build finished: $BUILD_DIR/bin"
ls "$BUILD_DIR/bin" | grep -E '^llama-(server|cli|bench)$' || true
