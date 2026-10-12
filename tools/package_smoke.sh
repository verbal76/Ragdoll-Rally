#!/usr/bin/env bash
# Local desktop packaging smoke test (no Actions minutes, nothing published): builds the Windows and Linux packages from the committed HEAD,
# checks names / contents / permissions / architecture / provenance / OTA-off, builds the coordinated manifest + checksums for those two
# platforms and verifies the set. Usage: GODOT=/path/to/godot tools/package_smoke.sh [build_number]   (default: release/release.json "version")
# Needs the Godot 4.7.1 Windows + Linux export templates. Requires a clean tree (official names); otherwise names are "internal" and the
# manifest step is skipped on purpose.
set -eu
cd "$(dirname "$0")/.."
N="${1:-$(python3 -c "import json;print(json.load(open('release/release.json'))['version'])")}"
export BUILD_NUMBER="$N"
OUT="$(mktemp -d)/smoke"; mkdir -p "$OUT/set"
fail=0; ok() { echo "PASS  $1"; }; bad() { echo "FAIL  $1"; fail=1; }
tools/build.sh --platform windows --out "$OUT/b" >/dev/null && tools/build.sh --platform linux --out "$OUT/b" >/dev/null || { echo "FAIL  build"; exit 1; }
WZ="$(ls "$OUT"/b/windows/*EXE.zip)"; LT="$(ls "$OUT"/b/linux/*Linux.tar.gz)"
echo "windows: $(basename "$WZ")"; echo "linux:   $(basename "$LT")"
python3 - "$WZ" <<'PY' && ok "Windows zip: PE x86-64 exe + README + provenance, no OTA build_info" || bad "Windows zip contents"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); n = z.namelist()
assert {"Ragdoll-Rally-Launch.exe", "README.txt", "provenance.json"} <= set(n), n
assert "build_info.json" not in n
exe = z.read("Ragdoll-Rally-Launch.exe")
assert exe[:2] == b"MZ"
pe = int.from_bytes(exe[0x3c:0x40], "little")
assert exe[pe:pe+4] == b"PE\0\0" and int.from_bytes(exe[pe+4:pe+6], "little") == 0x8664, "not x86-64"
PY
python3 - "$LT" <<'PY' && ok "Linux tar.gz: ELF x86-64, executable bits, run.sh, provenance" || bad "Linux tar contents"
import sys, tarfile
t = tarfile.open(sys.argv[1]); m = {i.name: i for i in t.getmembers()}
assert {"RagdollRallyLaunch.x86_64", "run.sh", "README.txt", "provenance.json"} <= set(m), list(m)
assert m["RagdollRallyLaunch.x86_64"].mode & 0o111 and m["run.sh"].mode & 0o111, "not executable"
e = t.extractfile("RagdollRallyLaunch.x86_64").read(20)
assert e[:4] == b"\x7fELF" and e[4] == 2 and int.from_bytes(e[18:20], "little") == 0x3e, "not ELF64 x86-64"
assert "build_info.json" not in m
PY
for p in "$WZ" "$LT"; do
  python3 - "$p" <<'PY' && ok "provenance matches $(basename "$p")" || bad "provenance $(basename "$p")"
import json, sys, zipfile, tarfile, os
a = sys.argv[1]
if a.endswith(".zip"): pv = json.loads(zipfile.ZipFile(a).read("provenance.json"))
else: pv = json.loads(tarfile.open(a).extractfile("provenance.json").read())
import subprocess
head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
assert pv["source_sha"] == head and not pv["working_tree_dirty"] and pv["build_number"] == int(os.environ["BUILD_NUMBER"]), pv
PY
done
if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
  cp "$WZ" "$WZ.provenance.json" "$LT" "$LT.provenance.json" "$OUT/set/"
  python3 tools/coordinated.py manifest --dir "$OUT/set" --build "$N" --sha "$(git rev-parse HEAD)" --platforms windows,linux --destination local_only && python3 tools/coordinated.py verify --dir "$OUT/set" && (cd "$OUT/set" && sha256sum -c checksums.sha256) && ok "manifest + checksums for one SHA / one build number" || bad "manifest + checksums"
else echo "SKIP  manifest (dirty tree: internal build names)"; fi
# the Linux binary must start and quit cleanly headless (smoke; not a hardware or gameplay test)
D="$(mktemp -d)"; tar -xzf "$LT" -C "$D"
timeout 60 "$D/RagdollRallyLaunch.x86_64" --headless --quit-after 30 >"$D/run.log" 2>&1 && ok "Linux binary starts and exits cleanly (headless smoke)" || { bad "Linux binary smoke"; tail -5 "$D/run.log"; }
grep -q "ota boot_prepare" "$D/run.log" && grep -qE "running=embedded" "$D/run.log" && ok "desktop runs the embedded game (OTA disabled)" || echo "NOTE  could not confirm embedded-only log line"
exit $fail
