#!/usr/bin/env python3
"""Coordinated build helpers (Hot Attic Games standard v2.0, sections 5-9): ONE native build number, ONE source SHA, ONE release.

  coordinated.py validate-request --platform P --source-sha SHA --build-number N --destination D [--auth-ref origin/BRANCH]
        rejects (exit 1) a malformed/unknown SHA, a SHA outside the authoritative lineage, a reused or non-monotonic build number
  coordinated.py names --build N            JSON: release title, tag and the five asset names
  coordinated.py artifact-name --platform android|windows|linux [--build N]
        the player-facing file name for the CURRENT tree: official only for a clean, authoritative, unreleased-number tree, else an "internal SHA7" name
  coordinated.py manifest --dir DIR --build N --sha SHA --platforms android,windows,linux --destination D
        writes DIR/build-manifest.json + DIR/checksums.sha256 after verifying every artifact against its provenance file
  coordinated.py verify --dir DIR           re-checks manifest, checksums, names, one SHA, one build number (used before any release is created)
"""
import argparse, hashlib, json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PLATFORMS = ("android", "windows", "linux", "all")
DESTINATIONS = ("github_releases", "local_only")
GAME = "Ragdoll Rally"
SUFFIX = {"android": "APK.apk", "windows": "EXE.zip", "linux": "Linux.tar.gz"}

def git(*a, cwd=None):
    r = subprocess.run(["git", "-C", cwd or ROOT, *a], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

def release_json():
    return json.load(open(os.path.join(ROOT, "release", "release.json")))

def expand(platform):
    return ["android", "windows", "linux"] if platform == "all" else [platform]

def names(build, internal_sha=None):
    mid = "Build %d" % build + (" internal %s" % internal_sha if internal_sha else "")
    d = {"release_title": "%s Build %d" % (GAME, build), "tag": "build-%d" % build,
         "manifest": "build-manifest.json", "checksums": "checksums.sha256"}
    for p, s in SUFFIX.items():
        d[p] = "%s %s %s" % (GAME, mid, s)
    return d

def published_numbers(cwd=None):
    """Build numbers already identifying a binary: historical v<N> tags and coordinated build-<N> tags."""
    _, out = git("tag", cwd=cwd)
    nums = set()
    for t in out.splitlines():
        m = re.fullmatch(r"(?:v|build-)(\d+)", t.strip())
        if m:
            nums.add(int(m.group(1)))
    return nums

def validate_request(platform, sha, build, destination, auth_ref, cwd=None):
    errs = []
    if platform not in PLATFORMS:
        errs.append("platform must be one of %s (got %r)" % (", ".join(PLATFORMS), platform))
    if destination not in DESTINATIONS:
        errs.append("destination must be one of %s (got %r)" % (", ".join(DESTINATIONS), destination))
    if not re.fullmatch(r"[0-9a-f]{40}", sha or ""):
        errs.append("source_sha must be a full 40-character lowercase commit SHA (branch names, tags and short SHAs are refused)")
    else:
        rc, _ = git("cat-file", "-e", sha + "^{commit}", cwd=cwd)
        if rc != 0:
            errs.append("source_sha %s is not a commit in this repository" % sha[:12])
        else:
            rc, _ = git("merge-base", "--is-ancestor", sha, auth_ref, cwd=cwd)
            if rc != 0:
                errs.append("source_sha %s is not part of the authoritative line (%s)" % (sha[:12], auth_ref))
    if not re.fullmatch(r"[1-9][0-9]{0,3}", str(build)):
        errs.append("build_number must be a positive integer without leading zeros (got %r)" % (build,))
    else:
        n = int(build)
        used = published_numbers(cwd)
        if n in used:
            errs.append("build number %d is already used by an existing tag (v%d or build-%d): one number identifies ONE binary" % (n, n, n))
        elif destination == "github_releases" and used and n <= max(used):
            errs.append("build number %d is not above the highest published number %d (numbers only increase)" % (n, max(used)))
    return errs

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def runtime_compat():
    r = subprocess.run([sys.executable, os.path.join(ROOT, "launch", "tools", "ota_tools.py"), "fingerprint"], capture_output=True, text=True)
    return r.stdout.strip().splitlines()[-1] if r.returncode == 0 and r.stdout.strip() else "unknown"

PROV_NAME = {"android": "android-arm64", "windows": "windows-x86_64", "linux": "linux-x86_64"}

def make_manifest(d, build, sha, platforms, destination):
    nm = names(build)
    arts, errs = [], []
    for p in platforms:
        art = os.path.join(d, nm[p])
        prov = os.path.join(d, nm[p] + ".provenance.json")
        if not os.path.exists(art) or not os.path.exists(prov):
            errs.append("missing artifact or provenance for %s (%s)" % (p, nm[p]))
            continue
        pv = json.load(open(prov))
        if pv.get("source_sha") != sha:
            errs.append("%s was built from %s, not the requested %s" % (p, str(pv.get("source_sha"))[:12], sha[:12]))
        if int(pv.get("build_number", -1)) != build:
            errs.append("%s carries build number %s, not %d" % (p, pv.get("build_number"), build))
        if pv.get("working_tree_dirty"):
            errs.append("%s was built from a dirty tree" % p)
        if pv.get("platform") != PROV_NAME[p]:
            errs.append("%s provenance names platform %s" % (p, pv.get("platform")))
        digest = sha256_file(art)
        if pv.get("artifact_sha256") != digest or int(pv.get("artifact_bytes", -1)) != os.path.getsize(art):
            errs.append("%s does not match its provenance (hash/size)" % p)
        arts.append({"platform": PROV_NAME[p], "file": nm[p], "sha256": digest, "bytes": os.path.getsize(art),
                     "engine": pv.get("engine"), "build_config": pv.get("build_config"), "built_at_utc": pv.get("built_at_utc"),
                     "update_delivery": "Android OTA (PCK, channel g3; native runtime compat below)" if p == "android" else "SteamPipe (OTA disabled in this build)"})
    if errs:
        return None, errs
    man = {"game": GAME, "build_number": build, "release_title": nm["release_title"], "tag": nm["tag"], "source_sha": sha,
           "destination": destination, "platforms": [PROV_NAME[p] for p in platforms],
           "native_runtime_compat": runtime_compat(), "ota_revisions": "independent of the build number (see the OTA channel manifests)",
           "artifacts": arts}
    return man, []

def write_manifest(d, build, sha, platforms, destination):
    man, errs = make_manifest(d, build, sha, platforms, destination)
    if errs:
        return errs
    json.dump(man, open(os.path.join(d, "build-manifest.json"), "w"), indent=2)
    open(os.path.join(d, "build-manifest.json"), "a").write("\n")
    with open(os.path.join(d, "checksums.sha256"), "w") as f:
        for a in man["artifacts"]:
            f.write("%s  %s\n" % (a["sha256"], a["file"]))
    return []

def verify_dir(d):
    errs = []
    try:
        man = json.load(open(os.path.join(d, "build-manifest.json")))
    except Exception as e:
        return ["build-manifest.json unreadable: %s" % e]
    build, sha = int(man["build_number"]), man["source_sha"]
    nm = names(build)
    if man.get("release_title") != nm["release_title"] or man.get("tag") != nm["tag"]:
        errs.append("release title / tag do not match the build number")
    sums = {}
    for line in open(os.path.join(d, "checksums.sha256")).read().splitlines():
        h, _, f = line.partition("  ")
        sums[f] = h
    if not man["artifacts"]:
        errs.append("manifest lists no artifacts")
    for a in man["artifacts"]:
        p = [k for k, v in PROV_NAME.items() if v == a["platform"]]
        if not p or a["file"] != nm[p[0]]:
            errs.append("artifact %s has a non-standard name" % a["file"])
        path = os.path.join(d, a["file"])
        if not os.path.exists(path) or sha256_file(path) != a["sha256"]:
            errs.append("artifact %s is missing or does not match the manifest" % a["file"])
        if sums.get(a["file"]) != a["sha256"]:
            errs.append("checksums.sha256 disagrees for %s" % a["file"])
        pv = path + ".provenance.json"
        if os.path.exists(pv) and json.load(open(pv)).get("source_sha") != sha:
            errs.append("artifact %s comes from a different source SHA" % a["file"])
    return errs

def artifact_name(platform, build=None):
    rel = release_json()
    b = build if build is not None else int(os.environ.get("BUILD_NUMBER") or rel["version"])
    sha = git("rev-parse", "HEAD")[1]
    dirty = bool(git("status", "--porcelain", "--untracked-files=no")[1])
    internal = dirty
    for tag in ("build-%d" % b, "v%d" % b):
        rc, t = git("rev-parse", "-q", "--verify", "refs/tags/%s^{commit}" % tag)
        if rc == 0 and t != sha:
            internal = True                 # the number already identifies a different binary
    return names(b, sha[:7] if internal else None)[platform]

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate-request")
    v.add_argument("--platform", required=True); v.add_argument("--source-sha", required=True)
    v.add_argument("--build-number", required=True); v.add_argument("--destination", required=True)
    v.add_argument("--auth-ref", default=None)
    n = sub.add_parser("names"); n.add_argument("--build", type=int, required=True)
    an = sub.add_parser("artifact-name"); an.add_argument("--platform", required=True, choices=list(SUFFIX)); an.add_argument("--build", type=int)
    m = sub.add_parser("manifest")
    m.add_argument("--dir", required=True); m.add_argument("--build", type=int, required=True); m.add_argument("--sha", required=True)
    m.add_argument("--platforms", required=True); m.add_argument("--destination", default="local_only")
    vd = sub.add_parser("verify"); vd.add_argument("--dir", required=True)
    a = ap.parse_args()
    if a.cmd == "validate-request":
        auth = a.auth_ref or "origin/" + release_json()["authoritative_branch"]
        errs = validate_request(a.platform, a.source_sha, a.build_number, a.destination, auth)
        for e in errs:
            print("REJECTED: " + e)
        if not errs:
            print("request ok: %s build %s from %s -> %s" % (a.platform, a.build_number, a.source_sha[:12], a.destination))
        sys.exit(1 if errs else 0)
    if a.cmd == "names":
        print(json.dumps(names(a.build), indent=2))
    elif a.cmd == "artifact-name":
        print(artifact_name(a.platform, a.build))
    elif a.cmd == "manifest":
        errs = write_manifest(a.dir, a.build, a.sha, a.platforms.split(","), a.destination)
        for e in errs:
            print("MANIFEST ERROR: " + e)
        sys.exit(1 if errs else 0)
    elif a.cmd == "verify":
        errs = verify_dir(a.dir)
        for e in errs:
            print("VERIFY ERROR: " + e)
        print("verify ok" if not errs else "verify FAILED")
        sys.exit(1 if errs else 0)

if __name__ == "__main__":
    main()
