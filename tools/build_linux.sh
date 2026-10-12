#!/usr/bin/env bash
# Local native Linux x86_64 build (Steam Deck / SteamOS) from the ONE authoritative codebase - no GitHub Actions minutes.
# Needs the Godot 4.7.1 Linux export templates (~/.local/share/godot/export_templates/4.7.1.stable/linux_release.x86_64).
# Usage: tools/build_linux.sh [out_dir]      GODOT=/path/to/Godot_v4.7.1 (default: godot on PATH)   ALLOW_DIRTY=1 marks an INTERNAL build
# Same rules as build_windows.sh: exact committed SHA on the authoritative branch, provenance.json packed with the game.
set -eu
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"; OUT="${1:-build/linux}"; mkdir -p "$OUT/pkg"
python3 tools/provenance.py check-tree
ARC=$(python3 tools/coordinated.py artifact-name --platform linux)   # official name only for a clean tree whose build number is not already another binary
$G --headless --path launch --import >/dev/null 2>&1 || true
$G --headless --path launch --export-release "Linux Desktop" "$(realpath "$OUT")/pkg/RagdollRallyLaunch.x86_64"
chmod +x "$OUT/pkg/RagdollRallyLaunch.x86_64"
python3 tools/provenance.py write --platform linux-x86_64 --config release --artifact "$OUT/pkg/RagdollRallyLaunch.x86_64" --out "$OUT/pkg/provenance.json"
cp docs/STEAMDECK.md "$OUT/pkg/README.txt"
printf '#!/bin/sh\ncd "$(dirname "$0")"\nexec ./RagdollRallyLaunch.x86_64 "$@"\n' > "$OUT/pkg/run.sh"; chmod +x "$OUT/pkg/run.sh"
tar -C "$OUT/pkg" -czf "$OUT/$ARC" RagdollRallyLaunch.x86_64 run.sh README.txt provenance.json
python3 tools/provenance.py write --platform linux-x86_64 --config release --artifact "$OUT/$ARC" --out "$OUT/$ARC.provenance.json" >/dev/null
sha256sum "$OUT/$ARC"
