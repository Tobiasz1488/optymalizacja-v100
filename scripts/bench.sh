#!/usr/bin/env bash
# Quick V100 benchmark: prompt processing and generation, FlashAttention off/on.
#   ./scripts/bench.sh models/model.gguf
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${1:?usage: $0 <model.gguf>}"; shift
exec "$ROOT/build/bin/llama-bench" -m "$MODEL" -ngl 999 -fa 0,1 -p 512,4096 -n 128 -ub 512 "$@"
