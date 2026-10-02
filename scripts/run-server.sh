#!/usr/bin/env bash
# Starts llama-server with defaults tuned for a single Tesla V100 32GB.
#
#   ./scripts/run-server.sh models/model.gguf [extra llama-server args...]
#
# Environment overrides: CTX (context, default 32768), KV (KV cache type,
# default q8_0), HOST (default 127.0.0.1), PORT (default 8080), UBATCH (512).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/build/bin}"
MODEL="${1:?usage: $0 <model.gguf> [extra args]}"; shift

exec "$BIN/llama-server" \
    -m "$MODEL" \
    -ngl 999 \
    -fa on \
    -c "${CTX:-32768}" \
    -ctk "${KV:-q8_0}" -ctv "${KV:-q8_0}" \
    -b 2048 -ub "${UBATCH:-512}" \
    --host "${HOST:-127.0.0.1}" --port "${PORT:-8080}" \
    "$@"
