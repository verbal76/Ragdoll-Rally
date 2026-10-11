#!/usr/bin/env bash
# Local Windows (x86_64) build - no GitHub Actions minutes. Needs the Godot 4.7.1 export templates installed
# (~/.local/share/godot/export_templates/4.7.1.stable/windows_release_x86_64.exe).
# Usage: tools/build_windows.sh [out_dir]      GODOT=/path/to/Godot_v4.7.1 (default: godot on PATH)
# Produces Ragdoll-Rally-Launch.exe (single file, PCK embedded) + the zip. The zip is named after release.json; the OTA updater is off on
# desktop (no build_info.json). Controls are remappable in-game (Esc / Start -> CONTROLS); config is user://controls.cfg.
set -eu
VER=$(python3 -c "import json;print(json.load(open('$(dirname "$0")/../release/release.json'))['version'])")
G="${GODOT:-godot}"; cd "$(dirname "$0")/.."; OUT="${1:-build/windows}"; mkdir -p "$OUT"
$G --headless --path launch --import >/dev/null 2>&1 || true
$G --headless --path launch --export-release "Windows Desktop" "$(realpath "$OUT")/Ragdoll-Rally-Launch.exe"
cp docs/WINDOWS_STEAM.md "$OUT/README.txt"
(cd "$OUT" && rm -f Ragdoll-Rally-Launch-v$VER-Windows.zip && python3 -c "
import zipfile
z=zipfile.ZipFile('Ragdoll-Rally-Launch-v'+'$VER'+'-Windows.zip','w',zipfile.ZIP_DEFLATED)
z.write('Ragdoll-Rally-Launch.exe'); z.write('README.txt')")
sha256sum "$OUT/Ragdoll-Rally-Launch-v$VER-Windows.zip"
