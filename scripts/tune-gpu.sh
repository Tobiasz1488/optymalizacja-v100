#!/usr/bin/env bash
# Sets every Tesla V100 in the system to its fastest stable state (needs root):
#   * persistence mode  - driver stays loaded, no ~1-2 s init on every start
#   * application clocks - highest supported memory/graphics clocks, so the GPU
#                          does not start from the lower default clocks
#   * power limit        - maximum allowed by the board (250 W PCIe / 300 W SXM2)
# Settings reset on reboot; run it from a systemd unit or cron @reboot if wanted.
#   sudo ./scripts/tune-gpu.sh          # apply
#   sudo ./scripts/tune-gpu.sh --reset  # back to defaults
set -euo pipefail

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

[[ "${1:-}" == "--reset" ]] || nvidia-smi -pm 1 >/dev/null

for i in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
    name=$(nvidia-smi -i "$i" --query-gpu=name --format=csv,noheader)
    [[ "$name" == *V100* ]] || { echo "GPU $i: $name - skipped"; continue; }

    if [[ "${1:-}" == "--reset" ]]; then
        nvidia-smi -i "$i" -rac >/dev/null
        nvidia-smi -i "$i" -pl "$(nvidia-smi -i "$i" --query-gpu=power.default_limit --format=csv,noheader,nounits)" >/dev/null
        echo "GPU $i: $name - defaults restored"
        continue
    fi

    clocks=$(nvidia-smi -i "$i" --query-supported-clocks=mem,gr --format=csv,noheader,nounits)
    mem=$(awk -F', ' '{print $1}' <<<"$clocks" | sort -n | tail -1)
    gr=$(awk -F', ' -v m="$mem" '$1 == m {print $2}' <<<"$clocks" | sort -n | tail -1)
    if nvidia-smi -i "$i" -ac "$mem,$gr" >/dev/null; then
        echo "GPU $i: $name - application clocks ${mem}/${gr} MHz"
    else
        echo "GPU $i: setting application clocks failed" >&2
    fi

    pl=$(nvidia-smi -i "$i" --query-gpu=power.max_limit --format=csv,noheader,nounits)
    if nvidia-smi -i "$i" -pl "$pl" >/dev/null; then
        echo "GPU $i: $name - power limit ${pl} W"
    else
        echo "GPU $i: setting power limit failed" >&2
    fi
done
