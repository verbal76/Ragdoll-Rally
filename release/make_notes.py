#!/usr/bin/env python3
"""Release notes for a coordinated build. Top: plain language for the owner/playtesters; below: engineering provenance.
Usage: make_notes.py <dir containing build-manifest.json> <out.md>"""
import json, os, sys

d, out = sys.argv[1:3]
man = json.load(open(os.path.join(d, "build-manifest.json")))
rel = json.load(open(os.path.join(os.path.dirname(__file__), "release.json")))
FILE_LABEL = {"android-arm64": "Android", "windows-x86_64": "Windows", "linux-x86_64": "Linux / Steam Deck"}
lines = [f"# {man['release_title']}", ""]
for a in man["artifacts"]:
    lines += [f"**{FILE_LABEL[a['platform']]}:** `{a['file']}`", ""]
lines += ["GitHub shows spaces in file names as dots when you download; the label on the release page keeps the standard name.", "",
          "Android installs over any earlier Ragdoll Rally build (same app and signing key; your progress is kept).", ""]
if rel.get("notes"):
    lines += ["## What's in this build", ""] + [f"- {n}" for n in rel["notes"]] + [""]
lines += ["---", "## Technical details (engineering only)", "",
          f"- Build number: {man['build_number']} (tag `{man['tag']}`)",
          f"- Source commit: `{man['source_sha']}` (the same commit for every file in this release)",
          f"- Native runtime compatibility id (Android OTA): `{man['native_runtime_compat']}`",
          "- OTA revisions are numbered separately from build numbers.",
          "- Android signing: debug key (throwaway; not Play-ready). Desktop builds have OTA disabled (Steam delivers updates).",
          "- `build-manifest.json` and `checksums.sha256` describe and verify every file."]
for a in man["artifacts"]:
    lines.append(f"- `{a['file']}`: {a['bytes']} bytes, SHA-256 `{a['sha256']}`, {a['engine']}")
open(out, "w").write("\n".join(lines) + "\n")
