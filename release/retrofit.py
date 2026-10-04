#!/usr/bin/env python3
"""One-off, idempotent release retrofit (driven by release/retrofit_request.json).
 - retitles historical releases "<Product> v<N>" (titles/notes only; tags and binaries untouched)
 - re-presents the newest delivered build (the EXACT existing APK, verified by SHA-256, never rebuilt)
   as release v<N>: clean tag, clean title, clean file names, not a pre-release, marked LATEST."""
import hashlib, json, os, subprocess, sys, tempfile

req = json.load(open(os.path.join(os.path.dirname(__file__), "retrofit_request.json")))
repo, product, stem = req["repo"], req["product"], req["file_stem"]

def sh(*a, check=True, capture=True):
    r = subprocess.run(list(a), capture_output=capture, text=True)
    if check and r.returncode != 0:
        print("FAILED:", " ".join(a), "\n", r.stdout, r.stderr)
        sys.exit(1)
    return r

def view(tag):
    r = sh("gh", "release", "view", tag, "--repo", repo, "--json", "name,body,tagName,isPrerelease,assets,targetCommitish", check=False)
    return json.loads(r.stdout) if r.returncode == 0 else None

work = tempfile.mkdtemp()

# ---------------------------------------------------------------- historical titles
for h in req["history"]:
    rel = view(h["tag"])
    if not rel:
        print("skip (no release):", h["tag"])
        continue
    title = f"{product} v{h['version']}"
    note = f"**{title}** - historical build (original tag `{h['tag']}`). Newer versions exist: see the Latest release.\n\n"
    body = rel["body"] or ""
    if not body.startswith(f"**{title}**"):
        body = note + body
    f = os.path.join(work, "n.md")
    open(f, "w").write(body)
    sh("gh", "release", "edit", h["tag"], "--repo", repo, "--title", title, "--notes-file", f)
    print("retitled", h["tag"], "->", title)

# ---------------------------------------------------------------- current build
c = req["current"]
v = c["version"]
title = f"{product} v{v}"
done = view(c["new_tag"])
if done and not done["isPrerelease"]:
    print("v%d already presented; nothing to do" % v)
else:
    rel = view(c["release_tag"])
    if not rel:
        print("source release missing:", c["release_tag"])
        sys.exit(1)
    apk = os.path.join(work, "orig.apk")
    r = subprocess.run(["gh", "api", "-H", "Accept: application/octet-stream", f"repos/{repo}/releases/assets/{c['apk_asset_id']}"], capture_output=True)
    if r.returncode != 0:
        print(r.stderr.decode())
        sys.exit(1)
    open(apk, "wb").write(r.stdout)
    sha = hashlib.sha256(r.stdout).hexdigest()
    print("downloaded APK sha256", sha)
    if sha != c["apk_expected_sha256"]:
        print("SHA-256 MISMATCH - refusing to re-present a different binary")
        sys.exit(1)
    new_apk = f"{stem}-v{v}.apk"
    new_rep = f"{stem}-v{v}-build-report.json"
    sh("gh", "api", "-X", "PATCH", f"repos/{repo}/releases/assets/{c['apk_asset_id']}", "-f", f"name={new_apk}")
    sh("gh", "api", "-X", "PATCH", f"repos/{repo}/releases/assets/{c['report_asset_id']}", "-f", f"name={new_rep}")
    shaf = os.path.join(work, new_apk + ".sha256")
    open(shaf, "w").write(f"{sha}  {new_apk}\n")
    sh("gh", "release", "upload", c["release_tag"], shaf, "--repo", repo, "--clobber")
    notes = f"""# {title}

**Android:**
`{new_apk}`

Install over any earlier {product} build (same app, same signing key, your progress is kept).

## What's in this build
- App is named "RR Launch" on the phone, with the new launcher icon (transparent background).
- Hot Attic Games studio splash on startup.
- Dense, breakable city with TNT, glowing target beams, skid and bounce, and upgrades you buy with score.

---
## Technical details (engineering only)

- Public version: v{v} (this is delivered build number {v}; earlier deliveries are v1 to v{v - 1}).
- Source commit: `{c['commit']}`
- Android versionCode: {c['version_code']} (CI run {c['ci_run']}); original release tag `{c['release_tag']}`
- Engine: Godot 4.7.1; target SDK 36; arm64-v8a only; 16 KB page-size verified in CI
- Signing: debug key (throwaway; not Play-ready)
- APK SHA-256: `{sha}`
- This is the EXACT binary built and verified by CI run {c['ci_run']}; it was renamed, not rebuilt.
- Known cosmetic exception: this build predates the version convention, so its About screen shows the old
  "Version 0.4.0 / code {c['version_code']}" instead of "v{v}". Builds from v12 on show their public version in About.
"""
    nf = os.path.join(work, "notes.md")
    open(nf, "w").write(notes)
    sh("gh", "release", "edit", c["release_tag"], "--repo", repo, "--tag", c["new_tag"], "--target", c["commit"],
       "--title", title, "--notes-file", nf, "--prerelease=false", "--latest")
    print("presented", title)

# ---------------------------------------------------------------- verify
latest = sh("gh", "api", f"repos/{repo}/releases/latest").stdout
L = json.loads(latest)
print("LATEST is:", L["tag_name"], "|", L["name"], "|", [a["name"] for a in L["assets"]])
assert L["tag_name"] == c["new_tag"] and L["name"] == title and not L["prerelease"]
assert any(a["name"] == f"{stem}-v{v}.apk" for a in L["assets"])
print("OK")
