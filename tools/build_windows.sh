#!/usr/bin/env bash
# Local Windows (x86_64) build from the ONE authoritative codebase - no GitHub Actions minutes (see docs/ENGINEERING_POLICY.md).
# Needs the Godot 4.7.1 export templates (~/.local/share/godot/export_templates/4.7.1.stable/windows_release_x86_64.exe).
# Usage: tools/build_windows.sh [out_dir]      GODOT=/path/to/Godot_v4.7.1 (default: godot on PATH)   ALLOW_DIRTY=1 marks an INTERNAL build
# The build must come from an exact committed SHA on the authoritative branch (provenance.py check-tree). The archive contains the exe,
# README and provenance.json (SHA, branch, version, platform, engine, timestamp). The OTA updater is off on desktop (no build_info.json).
set -eu
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"; OUT="${1:-build/windows}"; mkdir -p "$OUT"
python3 tools/provenance.py check-tree
ARC=$(python3 tools/coordinated.py artifact-name --platform windows)   # official name only for a clean tree whose build number is not already another binary
$G --headless --path launch --import >/dev/null 2>&1 || true
$G --headless --path launch --export-release "Windows Desktop" "$(realpath "$OUT")/Ragdoll-Rally-Launch.exe"
python3 tools/provenance.py write --platform windows-x86_64 --config release --artifact "$OUT/Ragdoll-Rally-Launch.exe" --out "$OUT/provenance.json"
cp docs/WINDOWS_STEAM.md "$OUT/README.txt"
(cd "$OUT" && rm -f "$ARC" && python3 -c "
import zipfile
z=zipfile.ZipFile('$ARC','w',zipfile.ZIP_DEFLATED)
for f in ('Ragdoll-Rally-Launch.exe','README.txt','provenance.json'): z.write(f)")
python3 tools/provenance.py write --platform windows-x86_64 --config release --artifact "$OUT/$ARC" --out "$OUT/$ARC.provenance.json" >/dev/null
sha256sum "$OUT/$ARC"
