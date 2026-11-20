#!/usr/bin/env bash
# Full local gate: format, lint, type-check, unit tests, place build.
# Run from the repository root: ./scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TYPES=tools/globalTypes.d.luau
if [ ! -f "$TYPES" ]; then
	echo "== fetching Roblox type definitions"
	./scripts/setup.sh
fi

echo "== stylua"
stylua --check src tests

echo "== selene"
selene src

echo "== luau-lsp analyze (strict)"
rojo sourcemap default.project.json -o sourcemap.json >/dev/null
out=$(luau-lsp analyze --definitions="$TYPES" --sourcemap=sourcemap.json --base-luaurc=.luaurc \
	--no-strict-dm-types src 2>&1 | grep -v '^\[' || true)
if [ -n "$out" ]; then
	echo "$out" | sort -u
	exit 1
fi

echo "== lune tests"
lune run tests/logic.spec
lune run tests/terrain.spec

echo "== rojo build"
mkdir -p build
rojo build default.project.json -o build/TheStillness.rbxlx

echo "All checks passed."
