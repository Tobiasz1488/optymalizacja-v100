#!/usr/bin/env bash
# Replaces the bundled llama.cpp copy with another upstream release tag.
#   ./scripts/update-llama.sh b11400
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: $0 <llama.cpp tag, e.g. b11400>}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$tmp/llama.cpp"
COMMIT=$(git -C "$tmp/llama.cpp" rev-parse HEAD)
rm -rf "$tmp/llama.cpp/.git"
rm -rf "$ROOT/llama.cpp"
mv "$tmp/llama.cpp" "$ROOT/llama.cpp"

cat > "$ROOT/LLAMA_CPP_VERSION" <<VER
tag=$TAG
commit=$COMMIT
source=https://github.com/ggml-org/llama.cpp
VER
echo "llama.cpp updated to $TAG ($COMMIT). Rebuild and commit the changes."
