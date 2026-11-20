#!/usr/bin/env bash
# Fetches the Roblox API type definitions used by luau-lsp, pinned to the
# luau-lsp release in rokit.toml. Data file only; nothing is executed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tools
curl -fsSL -o tools/globalTypes.d.luau \
	https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.None.d.luau
selene generate-roblox-std >/dev/null
echo "Type definitions ready in tools/globalTypes.d.luau"
