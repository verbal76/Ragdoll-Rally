#!/usr/bin/env python3
"""Build-identity + OTA helper for Ragdoll Rally: Launch (used by CI and tests).

  fingerprint                       -> runtime_compat string for the current source
  build-info  --out FILE ...        -> CI-generated res://build_info.json
  manifest    --out FILE ...        -> OTA manifest for a packed .pck
  epoch       [--rev REV]           -> payload epoch (commit count of REV on the authoritative line)
  baselines   [--write]             -> native baselines (release/native_baselines.json) recomputed from the release tags
  guard       --manifest F --live F -> publisher gate: an OTA must never be older than a native baseline or the live channel
  native-gate --live F --epoch N    -> native-release gate: the live channel manifest must not downgrade the new native build

Safety model (docs/ENGINEERING_POLICY.md section 5): an OTA carries source_epoch (monotonic commit count of its source). Clients refuse
payloads older than their own native baseline and order updates by (source_epoch, sequence), never by sequence alone.
"""
import argparse, hashlib, json, os, re, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))   # launch/
REPO = os.path.abspath(os.path.join(ROOT, ".."))
ENGINE = "godot-4.7.1"
import subprocess

def git(*a, repo=None):
    r = subprocess.run(["git", "-C", repo or REPO, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def epoch_of(rev="HEAD", repo=None):
    """Monotonic payload epoch: number of commits in the history of REV (linear authoritative line)."""
    n = git("rev-list", "--count", rev, repo=repo)
    return int(n) if n.isdigit() else 0

def boundary_files(root=None, rev=None):
    if rev:
        txt = git("show", "%s:launch/ota/boundary.txt" % rev)
    else:
        txt = open(os.path.join(root or ROOT, "ota", "boundary.txt")).read()
    out = []
    for line in txt.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return sorted(out)

def _read(root, rel, rev):
    if rev:
        r = subprocess.run(["git", "-C", REPO, "show", "%s:launch/%s" % (rev, rel)], capture_output=True)
        return r.stdout
    return open(os.path.join(root or ROOT, rel), "rb").read()

def class_names(root=None, rev=None):
    names = set()
    if rev:
        files = [f[len("launch/"):] for f in git("ls-tree", "-r", "--name-only", rev, "launch/scripts").splitlines() if f.endswith(".gd")]
        texts = [_read(None, f, rev).decode("utf-8", "replace") for f in files]
    else:
        texts = []
        for dp, _, fs in os.walk(os.path.join(root or ROOT, "scripts")):
            for f in fs:
                if f.endswith(".gd"):
                    texts.append(open(os.path.join(dp, f)).read())
    for t in texts:
        for m in re.finditer(r"^class_name\s+(\w+)", t, re.M):
            names.add(m.group(1))
    return sorted(names)

def fingerprint(root=None, rev=None):
    h = hashlib.sha256()
    h.update(ENGINE.encode())
    for rel in boundary_files(root, rev):
        h.update(b"\0F:" + rel.encode())
        h.update(_read(root, rel, rev))
    h.update(b"\0C:" + ",".join(class_names(root, rev)).encode())   # new class_name => native change
    return "r2-" + h.hexdigest()[:12]

BASELINES = os.path.join(REPO, "release", "native_baselines.json")

def channel_for(version):
    """OTA channel a native release follows: v14-v18 shipped on poc-g2 (runtime r2); later generations use g3."""
    return "poc-g2" if version <= 18 else "g3"

def computed_baselines():
    """Native releases (tags v<N>, N >= 14) with their payload epoch, runtime fingerprint and channel, straight from Git history."""
    out = []
    for t in git("tag", "-l", "v[0-9]*").split():
        if not t[1:].isdigit() or int(t[1:]) < 14:
            continue
        sha = git("rev-parse", t + "^{commit}")
        out.append({"version": int(t[1:]), "tag": t, "source_sha": sha, "source_epoch": epoch_of(sha), "runtime_compat": fingerprint(rev=sha), "channel": channel_for(int(t[1:]))})
    return sorted(out, key=lambda b: b["version"])

def load_baselines():
    comp = computed_baselines()
    if comp:
        return comp
    return json.load(open(BASELINES))["baselines"] if os.path.exists(BASELINES) else []

def _fail(msg):
    print("OTA SAFETY: " + msg)
    sys.exit(1)

def guard(a):
    """Publisher gate. Fails unless the new manifest is safe for every native baseline that would accept it and newer than the live channel."""
    man = json.load(open(a.manifest))
    live = json.load(open(a.live)) if a.live and os.path.exists(a.live) else None
    for k in ("sequence", "source_epoch", "source_sha", "runtime_compat", "channel"):
        if k not in man:
            _fail("manifest lacks '%s'" % k)
    rb = man.get("rollback")
    rb_ok = isinstance(rb, dict) and bool(rb.get("authorized")) and str(rb.get("reason", "")).strip() != ""
    if live is not None and live.get("channel") == man["channel"] and int(man["sequence"]) <= int(live.get("sequence", 0)):
        _fail("sequence %s is not greater than the live channel's %s" % (man["sequence"], live.get("sequence")))
    floor = 0
    who = ""
    for b in load_baselines():
        if b["runtime_compat"] == man["runtime_compat"] and b["channel"] == man["channel"] and int(b["source_epoch"]) > floor:
            floor, who = int(b["source_epoch"]), b["tag"]
    if int(man["source_epoch"]) < floor and not rb_ok:
        _fail("payload epoch %s is OLDER than native baseline %s (epoch %s) that would accept it; a downgrade needs an explicit rollback authorization (--rollback-reason)" % (man["source_epoch"], who, floor))
    if rb_ok and int(man["source_epoch"]) >= floor:
        _fail("rollback authorization given but the payload is not older than the baseline; remove it")
    if git("merge-base", "--is-ancestor", man["source_sha"], a.auth_ref or "HEAD") == "" and subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", man["source_sha"], a.auth_ref or "HEAD"]).returncode != 0:
        _fail("source %s is not part of the authoritative history" % man["source_sha"][:12])
    print("OTA safety ok: epoch %s >= baseline %s (%s), sequence %s" % (man["source_epoch"], floor, who or "none", man["sequence"]))

def native_gate(a):
    """Native-release gate: a live channel manifest that this build would accept must not carry an OLDER payload than the build itself."""
    if not a.live or not os.path.exists(a.live):
        print("native gate ok: no live manifest for this channel"); return
    live = json.load(open(a.live))
    if live.get("runtime_compat") != a.compat:
        print("native gate ok: live manifest is for another runtime (%s), this build ignores it" % live.get("runtime_compat")); return
    ep = int(live.get("source_epoch") or epoch_of(live["source_sha"]))
    if ep < int(a.epoch):
        _fail("the live '%s' manifest (%s, source %s, epoch %s) would be accepted by this native build (epoch %s) and DOWNGRADE it. Publish a baseline-equal OTA first or retire the channel." % (live.get("channel"), live.get("id"), str(live.get("source_sha"))[:7], ep, a.epoch))
    print("native gate ok: live payload epoch %s >= native epoch %s" % (ep, a.epoch))

def write_baselines():
    out = []
    for tag, vc in (("v14", 27), ("v15", 28), ("v16", 29), ("v17", 30), ("v18", 31)):
        sha = git("rev-parse", tag + "^{commit}")
        out.append({"version": int(tag[1:]), "tag": tag, "source_sha": sha, "source_epoch": epoch_of(sha), "version_code": vc,
                    "runtime_compat": fingerprint(rev=sha), "channel": "poc-g2"})
    json.dump({"_comment": "Native (APK) releases and the OTA channel/runtime they follow. Append a row for every native release. tools/ota_tools.py guard uses it.", "baselines": out}, open(BASELINES, "w"), indent=2)
    open(BASELINES, "a").write("\n")

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fingerprint")
    b = sub.add_parser("build-info")
    for a in ["out", "version-name", "version-code", "sha", "run", "channel", "target-sdk", "min-sdk", "compile-sdk", "generation", "manifest-url", "signing", "build-type", "product-name", "public-version", "build-kind", "epoch"]:
        b.add_argument("--" + a, default="")
    m = sub.add_parser("manifest")
    for a in ["out", "pck", "id", "name", "sequence", "sha", "channel", "url", "min-version-code", "max-version-code", "epoch", "root", "rollback-reason", "rollback-floor"]:
        m.add_argument("--" + a, default="")
    ep = sub.add_parser("epoch"); ep.add_argument("--rev", default="HEAD")
    bl = sub.add_parser("baselines"); bl.add_argument("--write", action="store_true")
    g = sub.add_parser("guard")
    for a in ["manifest", "live", "auth-ref"]:
        g.add_argument("--" + a, default="")
    ng = sub.add_parser("native-gate")
    for a in ["live", "epoch", "compat"]:
        ng.add_argument("--" + a, default="")
    a = ap.parse_args()
    if a.cmd == "fingerprint":
        print(fingerprint())
    elif a.cmd == "epoch":
        print(epoch_of(a.rev))
    elif a.cmd == "baselines":
        write_baselines() if a.write else print(json.dumps(load_baselines(), indent=2))
    elif a.cmd == "guard":
        guard(a)
    elif a.cmd == "native-gate":
        native_gate(a)
    elif a.cmd == "build-info":
        info = {
            "app_name": "RR Launch", "product_name": a.product_name or "Ragdoll Rally Launch", "public_version": a.public_version or a.version_name,
            "build_kind": a.build_kind or "internal", "package_id": "com.hotatticgames.ragdollrally.launch",
            "version_name": a.version_name, "version_code": int(a.version_code or 0), "source_sha": a.sha,
            "run_number": int(a.run or 0), "build_type": a.build_type or "debug", "channel": a.channel or "poc",
            "min_sdk": a.min_sdk or "unknown", "target_sdk": a.target_sdk or "unknown",
            "compile_sdk": a.compile_sdk or "unknown", "generation": a.generation or "g1", "signing": a.signing or "debug (throwaway key; not Play-ready)",
            "runtime_compat": fingerprint(), "source_epoch": int(a.epoch or 0), "play_required_target_api": 36, "play_required_verified": "2026-10-03",
            "ota_enabled": bool(a.manifest_url), "ota_manifest_url": a.manifest_url,
            "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        json.dump(info, open(a.out, "w"), indent=2)
    elif a.cmd == "manifest":
        data = open(a.pck, "rb").read()
        man = {
            "id": a.id, "name": a.name, "sequence": int(a.sequence), "channel": a.channel,
            "runtime_compat": fingerprint(root=a.root or None), "source_epoch": int(a.epoch or epoch_of(a.sha)), "url": a.url, "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data), "source_sha": a.sha, "published_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        if a.min_version_code:
            man["min_version_code"] = int(a.min_version_code)
        if a.max_version_code:
            man["max_version_code"] = int(a.max_version_code)
        if a.rollback_reason:
            man["rollback"] = {"authorized": True, "reason": a.rollback_reason, "floor_epoch": int(a.rollback_floor or man["source_epoch"])}
        json.dump(man, open(a.out, "w"), indent=2)

if __name__ == "__main__":
    main()
