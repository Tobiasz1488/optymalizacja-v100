#!/usr/bin/env bash
# V100 benchmark: prompt processing (pp) and generation (tg) at empty and long
# context, f16 vs q8_0 KV cache, all with FlashAttention.
#   ./scripts/bench.sh models/model.gguf [extra llama-bench args]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${1:?usage: $0 <model.gguf>}"; shift
B="$ROOT/build/bin/llama-bench"
[[ -x "$B" ]] || { echo "$B not found - run ./scripts/build-ubuntu.sh first" >&2; exit 1; }
for kv in f16 q8_0; do
    "$B" -m "$MODEL" -ngl 999 -fa 1 -ctk "$kv" -ctv "$kv" -p 512 -n 128 -d 0,16384 -ub 512,1024 "$@"
done
