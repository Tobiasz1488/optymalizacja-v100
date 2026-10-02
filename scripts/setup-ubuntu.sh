#!/usr/bin/env bash
# Installs everything needed to build llama.cpp for Tesla V100 on Ubuntu 24.04 LTS.
#
#   ./scripts/setup-ubuntu.sh               # build tools + CUDA 12.9 toolkit
#   ./scripts/setup-ubuntu.sh --with-driver # ...and NVIDIA driver 580 (server branch)
#
# Why CUDA 12.9 and driver 580:
#   * CUDA 13.x removed support for Volta (sm_70) - nvcc 13 cannot target V100.
#   * Driver branch 580 is the last one that supports Volta. Do not install
#     the generic `cuda` / `cuda-drivers` meta packages, they pull newer versions.
set -euo pipefail

CUDA_VER="${CUDA_VER:-12-9}"
WITH_DRIVER=0
[[ "${1:-}" == "--with-driver" ]] && WITH_DRIVER=1

if [[ $EUID -ne 0 ]]; then SUDO=sudo; else SUDO=; fi

. /etc/os-release
if [[ "${VERSION_ID}" != "24.04" ]]; then
    echo "Warning: this script targets Ubuntu 24.04, detected ${PRETTY_NAME}" >&2
fi

echo "==> Build tools"
$SUDO apt-get update
$SUDO apt-get install -y build-essential cmake ninja-build git pkg-config \
    libssl-dev ccache curl ca-certificates

echo "==> NVIDIA CUDA repository"
if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/cuda-keyring.deb" \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    $SUDO dpkg -i "$tmp/cuda-keyring.deb"
    rm -rf "$tmp"
    $SUDO apt-get update
fi

echo "==> CUDA toolkit ${CUDA_VER/-/.} (last major version supporting V100 is 12.x)"
$SUDO apt-get install -y "cuda-toolkit-${CUDA_VER}"

# NCCL speeds up splitting a model across several V100s (no effect with one GPU).
# Pick the NCCL build made for CUDA 12.x - the newest packages target CUDA 13.
NCCL_VER=$(apt-cache madison libnccl-dev | awk -v c="+cuda${CUDA_VER/-/.}" 'index($3, c) {print $3; exit}')
if [[ -n "$NCCL_VER" ]]; then
    $SUDO apt-get install -y "libnccl2=$NCCL_VER" "libnccl-dev=$NCCL_VER"
    $SUDO apt-mark hold libnccl2 libnccl-dev
else
    echo "NCCL for CUDA ${CUDA_VER/-/.} not found in the repository (optional, skipping)"
fi

if [[ $WITH_DRIVER -eq 1 ]]; then
    echo "==> NVIDIA driver 580 (server branch, last branch supporting Volta)"
    $SUDO apt-get install -y nvidia-driver-580-server nvidia-utils-580-server
    echo "Reboot required after driver installation."
fi

profile=/etc/profile.d/cuda-v100.sh
echo "==> Writing ${profile}"
$SUDO tee "$profile" >/dev/null <<PROFILE
export CUDA_HOME=/usr/local/cuda-${CUDA_VER/-/.}
export PATH=\$CUDA_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$CUDA_HOME/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
PROFILE

echo
echo "Done. Open a new shell (or: source ${profile}) and run ./scripts/build-ubuntu.sh"
