#!/usr/bin/env bash
# Local native Linux x86_64 build (Steam Deck / SteamOS) - no GitHub Actions minutes. Needs the Godot 4.7.1 Linux export templates
# (~/.local/share/godot/export_templates/4.7.1.stable/linux_release.x86_64).
# Usage: tools/build_linux.sh [out_dir] [archive_name]     GODOT=/path/to/Godot_v4.7.1 (default: godot on PATH)
set -eu
G="${GODOT:-godot}"; cd "$(dirname "$0")/.."; OUT="${1:-build/linux}"; ARC="${2:-Ragdoll-Rally-Launch-Linux.tar.gz}"; mkdir -p "$OUT/pkg"
$G --headless --path launch --import >/dev/null 2>&1 || true
$G --headless --path launch --export-release "Linux Desktop" "$(realpath "$OUT")/pkg/RagdollRallyLaunch.x86_64"
chmod +x "$OUT/pkg/RagdollRallyLaunch.x86_64"
cp docs/STEAMDECK.md "$OUT/pkg/README.txt"
printf '#!/bin/sh\ncd "$(dirname "$0")"\nexec ./RagdollRallyLaunch.x86_64 "$@"\n' > "$OUT/pkg/run.sh"; chmod +x "$OUT/pkg/run.sh"
tar -C "$OUT/pkg" -czf "$OUT/$ARC" RagdollRallyLaunch.x86_64 run.sh README.txt
sha256sum "$OUT/$ARC"
