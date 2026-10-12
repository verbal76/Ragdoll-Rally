#!/usr/bin/env python3
"""Release manifest: one source SHA, every platform artifact (see docs/ENGINEERING_POLICY.md).

  release_manifest.py build OUT.json PROVENANCE.json [PROVENANCE.json ...]   merge provenance files; fails unless all share one SHA + version
  release_manifest.py verify MANIFEST.json                                   re-checks parity and that the SHA is on the authoritative branch
"""
import json, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def build(out, files):
    items = [json.load(open(f)) for f in files]
    shas = {i["source_sha"] for i in items}
    vers = {i["version"] for i in items}
    if len(shas) != 1 or len(vers) != 1:
        print("release manifest: platform artifacts come from different sources: shas=%s versions=%s" % (sorted(shas), sorted(vers)))
        sys.exit(1)
    dirty = [i["platform"] for i in items if i.get("working_tree_dirty")]
    if dirty:
        print("release manifest: dirty-tree builds cannot be part of a coordinated release: %s" % dirty)
        sys.exit(1)
    m = {"version": items[0]["version"], "public_version": items[0]["public_version"], "source_sha": shas.pop(),
         "artifacts": [{k: i[k] for k in ("platform", "build_config", "artifact", "artifact_sha256", "artifact_bytes", "engine", "built_at_utc")} for i in items]}
    json.dump(m, open(out, "w"), indent=2); open(out, "a").write("\n")
    print("release manifest: %s, %d artifacts, one source %s" % (m["public_version"], len(items), m["source_sha"][:12]))

def verify(path):
    m = json.load(open(path))
    rel = json.load(open(os.path.join(ROOT, "release", "release.json")))
    auth = "origin/" + rel["authoritative_branch"]
    r = subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", m["source_sha"], auth], capture_output=True)
    if r.returncode != 0:
        print("release manifest: source %s is not part of %s" % (m["source_sha"][:12], auth))
        sys.exit(1)
    print("release manifest ok: %s on %s" % (m["public_version"], auth))

if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "build":
        build(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 3 and sys.argv[1] == "verify":
        verify(sys.argv[2])
    else:
        print(__doc__); sys.exit(2)
