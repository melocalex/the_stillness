#!/usr/bin/env bash
# Builds a place file of any commit with the screenshot rig added, so two
# commits can be shot from identical cameras at the same time of day.
#   tools/studio/shot-rig/build.sh <commit> <out.rbxlx>
# Example (before and after the valley rebuild):
#   tools/studio/shot-rig/build.sh ba2d2a0 /tmp/terrain-before.rbxlx
#   tools/studio/shot-rig/build.sh HEAD /tmp/terrain-after.rbxlx
# Open the place in Studio, press Play, click Play in the menu. The cameras
# cycle every 14 s; the output prints "[Shot] <camera>" for each.
set -euo pipefail
rig="$(cd "$(dirname "$0")" && pwd)"
repo="$(git -C "$rig" rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$repo" archive "$1" | tar -x -C "$work"
mkdir -p "$work/tools/studio/shot-rig"
cp "$rig"/ShotClient.client.luau "$rig"/ShotServer.server.luau "$rig"/shot.project.json "$work/tools/studio/shot-rig/"
rojo build "$work/tools/studio/shot-rig/shot.project.json" -o "$2"
