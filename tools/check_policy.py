#!/usr/bin/env python3
"""Static enforcement of docs/ENGINEERING_POLICY.md (no Godot needed, runs in a second).

  check_policy.py          repository checks (used by tools/local_validate.sh)
  check_policy.py --ci     the same, plus: the ref being built IS the authoritative branch (used by the release workflows)
Fails visibly; never skips.
"""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
fails = []

def need(ok, msg):
    print(("PASS  " if ok else "FAIL  ") + msg)
    if not ok:
        fails.append(msg)

def read(p):
    return open(os.path.join(ROOT, p)).read()

rel = json.load(open(os.path.join(ROOT, "release", "release.json")))
auth = rel.get("authoritative_branch", "")
need(bool(auth), "release.json names the authoritative branch (%s)" % auth)
need(isinstance(rel.get("version"), int), "release.json public version is an integer (v%s)" % rel.get("version"))

# release / OTA workflows may only start from the authoritative branch
for wf in ("android.yml", "launch-ota.yml"):
    t = read(".github/workflows/" + wf)
    m = re.search(r"push:\s*\n\s*branches:\s*\[([^\]]*)\]", t)
    names = [x.strip() for x in m.group(1).split(",")] if m else []
    need(names == [auth], "%s is triggered by pushes to the authoritative branch only (found %s)" % (wf, names))
    need("check_policy.py --ci" in t, "%s runs the policy gate (check_policy.py --ci)" % wf)
t = read(".github/workflows/release-retrofit.yml")
need("workflow_dispatch" in t and "push:" not in t, "release-retrofit.yml stays manual-only")

# one project, several export targets with the same payload
cfg = read("launch/export_presets.cfg")
presets = dict(re.findall(r'^name="([^"]+)"\nplatform="([^"]+)"', cfg, re.M))
for name in ("Android", "Windows Desktop", "Linux Desktop"):
    need(name in presets, "export preset present: %s" % name)
desk = re.findall(r'name="(Windows Desktop|Linux Desktop)".*?exclude_filter="([^"]*)"', cfg, re.S)
need(len(desk) == 2 and len({d[1] for d in desk}) == 1, "desktop presets ship the same payload (identical exclude_filter)")
need(os.path.exists(os.path.join(ROOT, "launch", "project.godot")), "one Godot project (launch/project.godot) feeds every target")
dup = [d for d in os.listdir(os.path.join(ROOT, "launch")) if d.lower() in ("android", "windows", "linux", "desktop", "ios", "web", "legacy")]
need(not dup, "no per-platform copies of the game inside launch/ (%s)" % (dup or "none"))

# OTA safety (version floor): publisher gate, native gate, tests, frozen legacy client
ota = read(".github/workflows/launch-ota.yml")
need("ota_tools.py guard" in ota and "fetch-depth: 0" in ota and "source_ref" in ota, "launch-ota.yml runs the OTA safety guard on an exact authoritative source")
need("verify_ota_safety" in ota, "launch-ota.yml runs the OTA safety tests before publishing")
need("native-gate" in read(".github/workflows/android.yml") and "--epoch" in read(".github/workflows/android.yml"), "android.yml runs the native-release OTA gate and bakes the payload epoch")
for f in ("launch/tests/verify_ota_safety.gd", "launch/tests/fixtures/ota_client_legacy_v14_v18.gd", "launch/tests/fixtures/ota_manifest_poc-g2_seq3_faeb937.json", "launch/tools/test_ota_tools.py", "release/native_baselines.json"):
    need(os.path.exists(os.path.join(ROOT, f)), "OTA safety asset present: " + f)
need("verify_ota_safety" in read("tools/local_validate.sh") and "test_ota_tools.py" in read("tools/local_validate.sh"), "local_validate runs the OTA safety tests")
need("source_epoch" in read("launch/scripts/ota_client.gd") and "source_epoch" in read("launch/scripts/build_info.gd"), "the OTA client enforces the payload version floor")

# builds must carry provenance
for sh in ("build_windows.sh", "build_linux.sh"):
    s = read("tools/" + sh)
    need("provenance.py check-tree" in s and "provenance.py write" in s, "%s refuses off-branch / dirty builds and writes provenance" % sh)
need("build_info.json" in read(".github/workflows/android.yml") and "--sha" in read(".github/workflows/android.yml"), "the Android build records its commit SHA (build_info.json)")

# durable instructions
need("SINGLE SOURCE OF TRUTH" in read("CLAUDE.md"), "CLAUDE.md carries the single-source-of-truth rule")
need(os.path.exists(os.path.join(ROOT, "docs", "ENGINEERING_POLICY.md")), "docs/ENGINEERING_POLICY.md exists")
need(os.path.exists(os.path.join(ROOT, "docs", "BRANCH_LEDGER.md")), "docs/BRANCH_LEDGER.md exists")

if "--ci" in sys.argv:
    ref = os.environ.get("GITHUB_REF_NAME", "")
    ev = os.environ.get("GITHUB_EVENT_NAME", "")
    need(ev == "workflow_dispatch" or ref == auth, "the release build runs from the authoritative branch (ref '%s', event '%s')" % (ref, ev))

print("---- POLICY %s (%d failures)" % ("OK" if not fails else "FAILED", len(fails)))
sys.exit(1 if fails else 0)
