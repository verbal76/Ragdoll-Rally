#!/usr/bin/env bash
# One build interface (Hot Attic Games standard section 5): tools/build.sh --platform android|windows|linux|all [--out DIR]
# windows / linux build locally from the committed SHA (no Actions minutes). android is built only by CI (signing + SDK) and is never started from here:
# it is requested by dispatching the manual "Coordinated build" workflow (.github/workflows/build.yml). `all` builds the desktop targets from the same
# HEAD and prints the Android instruction; nothing is published. BUILD_NUMBER=NN picks the number (default: release/release.json "version").
set -eu
cd "$(dirname "$0")/.."
PLAT=""; OUT="build"
while [ $# -gt 0 ]; do case "$1" in
  --platform) PLAT="${2:-}"; shift 2;;
  --out) OUT="${2:-build}"; shift 2;;
  *) echo "unknown argument: $1" >&2; exit 2;;
esac; done
case "$PLAT" in
  windows) tools/build_windows.sh "$OUT/windows";;
  linux)   tools/build_linux.sh "$OUT/linux";;
  android) echo "Android is built by CI only (SDK + signing steps). Dispatch the manual Coordinated build workflow (platform=android or all, source_sha, build_number, destination)."; exit 3;;
  all)     tools/build_windows.sh "$OUT/windows"; tools/build_linux.sh "$OUT/linux"
           echo "Desktop targets built from $(git rev-parse --short=7 HEAD). Android: dispatch the Coordinated build workflow with this SHA so the APK comes from the same commit.";;
  *) echo "usage: tools/build.sh --platform android|windows|linux|all [--out DIR]" >&2; exit 2;;
esac
