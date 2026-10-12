#!/usr/bin/env bash
# Local validation = what CI would run, without spending GitHub Actions minutes (see CLAUDE.md, "GitHub Actions budget policy").
# Usage: tools/local_validate.sh [fast|full]      GODOT=/path/to/Godot_v4.7.1 (default: godot on PATH)
# fast: rules/economy/trajectory + splash + OTA (about a minute). full: adds the game, pivot, expanded, city gate (several minutes).
set -u
G="${GODOT:-godot}"; MODE="${1:-full}"; cd "$(dirname "$0")/.."
$G --headless --path launch --import >/dev/null 2>&1 || true
TESTS="verify_v13 verify_mayhem verify_launchers verify_controls verify_traffic verify_persist verify_envelope verify_hills verify_splash verify_ota verify_ota_safety verify_save_safety verify_glyphs"
[ "$MODE" = "full" ] && TESTS="$TESTS verify verify_pivot verify_expanded verify_cities verify_stress"
rc=0
for t in $TESTS; do
  out=$(timeout 1200 $G --headless --path launch -s tests/$t.gd 2>&1); code=$?
  if [ $code -ne 0 ] || echo "$out" | grep -qE "^FAIL|SCRIPT ERROR"; then echo "FAIL  $t"; echo "$out" | grep -E "^FAIL|SCRIPT ERROR" | head; rc=1; else echo "PASS  $t"; fi
done
python3 -c "import json;json.load(open('release/release.json'))" && echo "PASS  release.json parses"
python3 -W ignore launch/tools/test_ota_tools.py >/tmp/ota_py.out 2>&1 && echo "PASS  OTA publisher/native gates (python)" || { echo "FAIL  OTA publisher/native gates"; tail -5 /tmp/ota_py.out; rc=1; }
python3 tools/check_policy.py | grep -E "^FAIL|^----" ; [ "${PIPESTATUS[0]}" = "0" ] && echo "PASS  engineering policy (single source of truth)" || { echo "FAIL  engineering policy"; rc=1; }
python3 tools/branch_ledger.py --check || rc=1
exit $rc
