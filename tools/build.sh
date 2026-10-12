#!/usr/bin/env bash
# One build interface (Hot Attic Games standard section 5): tools/build.sh --platform android|windows|linux|all [--out DIR]
# windows / linux build locally from the committed SHA (no Actions minutes). android is built only by CI (signing + SDK) and is never started from here:
# it is requested by setting release/release.json "deliver": true (CLAUDE.md) or a manual workflow_dispatch of android.yml. `all` builds the desktop
# targets from the same HEAD and prints the Android instruction; nothing is published.
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
  android) echo "Android is built by CI only (release signing + SDK). To authorize: set release/release.json deliver=true and push, or dispatch android.yml manually for an internal test APK."; exit 3;;
  all)     tools/build_windows.sh "$OUT/windows"; tools/build_linux.sh "$OUT/linux"
           echo "Desktop targets built from $(git rev-parse --short=7 HEAD). Android: authorize through release/release.json (deliver=true) so the APK comes from this same SHA.";;
  *) echo "usage: tools/build.sh --platform android|windows|linux|all [--out DIR]" >&2; exit 2;;
esac
