#!/usr/bin/env bash
# Starts llama-server with defaults tuned for a single Tesla V100 32GB.
#
#   ./scripts/run-server.sh models/model.gguf [extra llama-server args...]
#
# Environment overrides: CTX (context, default 32768), KV (KV cache type,
# default f16), HOST (default 127.0.0.1), PORT (default 8080), UBATCH (512).
#
# KV cache: on Volta the FlashAttention kernels used for token generation with
# GQA models work on f16 data, so a quantized KV cache (q8_0/q4_0) is converted
# to f16 for every generated token. f16 is therefore the fastest choice;
# use KV=q8_0 (or q4_0) only when the model + context does not fit in 32 GB.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/build/bin}"
MODEL="${1:?usage: $0 <model.gguf> [extra args]}"; shift
[[ -x "$BIN/llama-server" ]] || { echo "$BIN/llama-server not found - run ./scripts/build-ubuntu.sh first" >&2; exit 1; }

exec "$BIN/llama-server" \
    -m "$MODEL" \
    -ngl 999 \
    -fa on \
    -c "${CTX:-32768}" \
    -ctk "${KV:-f16}" -ctv "${KV:-f16}" \
    -b 2048 -ub "${UBATCH:-512}" \
    --host "${HOST:-127.0.0.1}" --port "${PORT:-8080}" \
    "$@"
