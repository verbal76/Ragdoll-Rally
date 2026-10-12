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

# workflows: expensive/publishing ones are MANUAL ONLY (standard v2.0 s.9); the only automatic trigger allowed is the lightweight PR check
import yaml
WF = {}
for f in sorted(os.listdir(os.path.join(ROOT, ".github", "workflows"))):
    if f.endswith(".yml"):
        d = yaml.safe_load(read(".github/workflows/" + f))
        WF[f] = (d, read(".github/workflows/" + f))
        trig = d.get("on", d.get(True))
        keys = set(trig) if isinstance(trig, dict) else set([trig] if isinstance(trig, str) else trig)
        allowed = {"workflow_dispatch"} | ({"pull_request"} if f == "checks.yml" else set())
        need(keys <= allowed and "workflow_dispatch" in keys or keys == {"pull_request"}, "%s triggers: %s (push/tag/merge/schedule never start a workflow)" % (f, sorted(keys)))
for f in ("build.yml", "launch-ota.yml", "release-retrofit.yml", "checks.yml"):
    need(f in WF, "workflow present: " + f)
need("android.yml" not in WF, "the old push-triggered android.yml is gone (build.yml is the one build workflow)")
bd, bt = WF["build.yml"]
trig = bd.get("on", bd.get(True))
need(set(trig["workflow_dispatch"]["inputs"]) == {"platform", "source_sha", "build_number", "destination"}, "build.yml takes platform / source_sha / build_number / destination")
need(set(trig["workflow_dispatch"]["inputs"]["platform"]["options"]) == {"android", "windows", "linux", "all"}, "build.yml platform choices")
need(set(trig["workflow_dispatch"]["inputs"]["destination"]["options"]) == {"github_releases", "local_only"}, "build.yml destination choices")
need(bd["permissions"] == {"contents": "read"}, "build.yml is read-only by default")
writers = [j for j, v in bd["jobs"].items() if (v.get("permissions") or {}).get("contents") == "write"]
need(writers == ["release"], "only the release job can write (found %s)" % writers)
need("secrets." not in bt, "build.yml references no secrets (the debug keystore is a committed throwaway; desktop jobs need no signing)")
need("validate-request" in bt and "ref: ${{ inputs.source_sha }}" in bt, "build.yml validates the request and checks out the exact source SHA")
need("tools/local_validate.sh full" in bt and "native-gate" in bt and "--epoch" in bt, "build.yml runs the full validation and the native-release OTA gate, and bakes the payload epoch")
need(all("validate" in (bd["jobs"][j].get("needs") or []) for j in ("android", "desktop")), "no build starts before validation passes")
need("needs.android.result == 'success'" in bt and "needs.desktop.result == 'success'" in bt and "needs.validate.result == 'success'" in bt, "the assemble job requires every selected platform to succeed (no partial release)")
need(bd["jobs"]["release"]["needs"] == ["plan", "assemble"] and "github_releases" in str(bd["jobs"]["release"]["if"]), "release only after assemble, only for destination github_releases")
need("coordinated.py verify" in bt and "gh release create" in bt and "--target \"$SOURCE_SHA\"" in bt, "the release is created at the exact source SHA after re-verification")
need("build_info.json" in bt and "--sha" in bt, "the Android build records its commit SHA (build_info.json)")
od, ot = WF["launch-ota.yml"]
need("PUBLISH OTA" in ot and "request_sha256" in ot, "launch-ota.yml needs a confirmation phrase and the request hash")
need("ota_tools.py guard" in ot and "fetch-depth: 0" in ot and "source_ref" in ot or "REQ_REF" in ot, "launch-ota.yml runs the OTA safety guard on an exact authoritative source")
need("verify_ota_safety" in ot and "check_policy.py --ci" in ot, "launch-ota.yml runs the OTA safety tests and the policy gate before publishing")
need("${{ github.event.inputs" not in ot and "${{ steps.req" not in ot, "launch-ota.yml passes request values through the environment, not shell text")
cd_, ct = WF["checks.yml"]
need(cd_["permissions"] == {"contents": "read"} and "secrets." not in ct and "export" not in ct and "gh release" not in ct, "checks.yml is read-only, secret-free and builds nothing")
need("check_policy.py --ci" in ot and "workflow_dispatch" in str(od.get("on", od.get(True))), "OTA workflow policy gate present")

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
for f in ("launch/tests/verify_ota_safety.gd", "launch/tests/fixtures/ota_client_legacy_v14_v18.gd", "launch/tests/fixtures/ota_manifest_poc-g2_seq3_faeb937.json", "launch/tools/test_ota_tools.py", "release/native_baselines.json"):
    need(os.path.exists(os.path.join(ROOT, f)), "OTA safety asset present: " + f)
need("verify_ota_safety" in read("tools/local_validate.sh") and "test_ota_tools.py" in read("tools/local_validate.sh"), "local_validate runs the OTA safety tests")
need("source_epoch" in read("launch/scripts/ota_client.gd") and "source_epoch" in read("launch/scripts/build_info.gd"), "the OTA client enforces the payload version floor")

# builds must carry provenance
for sh in ("build_windows.sh", "build_linux.sh"):
    s = read("tools/" + sh)
    need("provenance.py check-tree" in s and "provenance.py write" in s, "%s refuses off-branch / dirty builds and writes provenance" % sh)
need(os.path.exists(os.path.join(ROOT, "tools", "coordinated.py")) and os.path.exists(os.path.join(ROOT, "tools", "build.sh")), "one build interface exists (tools/build.sh, tools/coordinated.py)")

# durable instructions
need("SINGLE SOURCE OF TRUTH" in read("CLAUDE.md"), "CLAUDE.md carries the single-source-of-truth rule")
need(os.path.exists(os.path.join(ROOT, "docs", "ENGINEERING_POLICY.md")), "docs/ENGINEERING_POLICY.md exists")
need(os.path.exists(os.path.join(ROOT, "docs", "BRANCH_LEDGER.md")), "docs/BRANCH_LEDGER.md exists")

if "--ci" in sys.argv:
    ref = os.environ.get("GITHUB_REF_NAME", "")
    ev = os.environ.get("GITHUB_EVENT_NAME", "")
    need(ev == "workflow_dispatch" and ref == auth, "the release build runs from the authoritative branch (ref '%s', event '%s')" % (ref, ev))

print("---- POLICY %s (%d failures)" % ("OK" if not fails else "FAILED", len(fails)))
sys.exit(1 if fails else 0)
