#!/usr/bin/env python3
"""Build provenance for one platform artifact (see docs/ENGINEERING_POLICY.md).

  provenance.py write --platform windows --config release --artifact FILE --out FILE.json [--allow-dirty]
  provenance.py check-tree [--allow-dirty]       exit 1 unless the working tree is clean and on the authoritative branch

Every platform build of one release must come from the same SHA; the manifest tool (release_manifest.py) verifies that.
"""
import argparse, datetime, hashlib, json, os, platform, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def git(*a):
    return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True).stdout.strip()

def release():
    return json.load(open(os.path.join(ROOT, "release", "release.json")))

def tree_state():
    sha = git("rev-parse", "HEAD")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    dirty = bool(git("status", "--porcelain", "--untracked-files=no"))
    return sha, branch, dirty

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def tool_version(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip().splitlines()[0]
    except Exception:
        return "unknown"

def check_tree(allow_dirty):
    sha, branch, dirty = tree_state()
    auth = release().get("authoritative_branch", "")
    ok = True
    if branch != auth:
        print("provenance: HEAD is on '%s', the authoritative branch is '%s'. Platform builds must come from the authoritative line." % (branch, auth))
        ok = False
    if dirty and not allow_dirty:
        print("provenance: the working tree has uncommitted changes; a build must come from an exact, committed SHA (ALLOW_DIRTY=1 marks it internal).")
        ok = False
    return ok

def write(a):
    sha, branch, dirty = tree_state()
    rel = release()
    godot = os.environ.get("GODOT", "godot")
    info = {
        "source_sha": sha, "source_branch": branch, "working_tree_dirty": dirty,
        "version": rel["version"], "public_version": "v%s" % rel["version"], "delivered": bool(rel.get("deliver")),
        "platform": a.platform, "build_config": a.config,
        "engine": tool_version([godot, "--version"]),
        "built_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "toolchain": {"python": platform.python_version(), "host": platform.platform()},
        "artifact": os.path.basename(a.artifact), "artifact_sha256": sha256(a.artifact), "artifact_bytes": os.path.getsize(a.artifact),
    }
    tpl = os.path.expanduser("~/.local/share/godot/export_templates/4.7.1.stable/version.txt")
    if os.path.exists(tpl):
        info["toolchain"]["export_templates"] = open(tpl).read().strip()
    json.dump(info, open(a.out, "w"), indent=2)
    open(a.out, "a").write("\n")
    print("provenance: %s %s @ %s%s" % (a.platform, info["public_version"], sha[:12], " (DIRTY tree, internal)" if dirty else ""))

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("write")
    w.add_argument("--platform", required=True); w.add_argument("--config", default="release")
    w.add_argument("--artifact", required=True); w.add_argument("--out", required=True)
    c = sub.add_parser("check-tree"); c.add_argument("--allow-dirty", action="store_true")
    a = ap.parse_args()
    if a.cmd == "check-tree":
        sys.exit(0 if check_tree(a.allow_dirty or os.environ.get("ALLOW_DIRTY") == "1") else 1)
    write(a)

if __name__ == "__main__":
    main()
