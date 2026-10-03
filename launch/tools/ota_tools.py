#!/usr/bin/env python3
"""Build-identity + OTA helper for Ragdoll Rally: Launch (used by CI and tests).

  fingerprint                       -> runtime_compat string for the current source
  build-info  --out FILE ...        -> CI-generated res://build_info.json
  manifest    --out FILE ...        -> OTA manifest for a packed .pck
"""
import argparse, hashlib, json, os, re, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))   # launch/
ENGINE = "godot-4.7.1"

def boundary_files():
    out = []
    for line in open(os.path.join(ROOT, "ota", "boundary.txt")):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return sorted(out)

def class_names():
    names = set()
    for dp, _, fs in os.walk(os.path.join(ROOT, "scripts")):
        for f in fs:
            if f.endswith(".gd"):
                for m in re.finditer(r"^class_name\s+(\w+)", open(os.path.join(dp, f)).read(), re.M):
                    names.add(m.group(1))
    return sorted(names)

def fingerprint():
    h = hashlib.sha256()
    h.update(ENGINE.encode())
    for rel in boundary_files():
        h.update(b"\0F:" + rel.encode())
        h.update(open(os.path.join(ROOT, rel), "rb").read())
    h.update(b"\0C:" + ",".join(class_names()).encode())   # new class_name => native change
    return "r2-" + h.hexdigest()[:12]

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fingerprint")
    b = sub.add_parser("build-info")
    for a in ["out", "version-name", "version-code", "sha", "run", "channel", "target-sdk", "min-sdk", "compile-sdk", "generation", "manifest-url", "signing", "build-type"]:
        b.add_argument("--" + a, default="")
    m = sub.add_parser("manifest")
    for a in ["out", "pck", "id", "name", "sequence", "sha", "channel", "url", "min-version-code"]:
        m.add_argument("--" + a, default="")
    a = ap.parse_args()
    if a.cmd == "fingerprint":
        print(fingerprint())
    elif a.cmd == "build-info":
        info = {
            "app_name": "Ragdoll Rally Launch", "package_id": "com.hotatticgames.ragdollrally.launch",
            "version_name": a.version_name, "version_code": int(a.version_code or 0), "source_sha": a.sha,
            "run_number": int(a.run or 0), "build_type": a.build_type or "debug", "channel": a.channel or "poc",
            "min_sdk": a.min_sdk or "unknown", "target_sdk": a.target_sdk or "unknown",
            "compile_sdk": a.compile_sdk or "unknown", "generation": a.generation or "g1", "signing": a.signing or "debug (throwaway key; not Play-ready)",
            "runtime_compat": fingerprint(), "play_required_target_api": 36, "play_required_verified": "2026-10-03",
            "ota_enabled": bool(a.manifest_url), "ota_manifest_url": a.manifest_url,
            "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        json.dump(info, open(a.out, "w"), indent=2)
    elif a.cmd == "manifest":
        data = open(a.pck, "rb").read()
        man = {
            "id": a.id, "name": a.name, "sequence": int(a.sequence), "channel": a.channel,
            "runtime_compat": fingerprint(), "url": a.url, "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data), "source_sha": a.sha, "published_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        if a.min_version_code:
            man["min_version_code"] = int(a.min_version_code)
        json.dump(man, open(a.out, "w"), indent=2)

if __name__ == "__main__":
    main()
