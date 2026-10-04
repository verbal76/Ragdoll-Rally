#!/usr/bin/env python3
"""Writes the GitHub release notes for a delivered build. The top is for the human installing the game;
engineering provenance follows. Usage: make_notes.py <apk> <out.md> <commit> <versionCode> <run> <engine> <target_sdk>"""
import hashlib, json, os, sys

apk, out, commit, vcode, run, engine, target = sys.argv[1:8]
rel = json.load(open(os.path.join(os.path.dirname(__file__), "release.json")))
v, product = rel["version"], rel["product"]
name = os.path.basename(apk)
sha = hashlib.sha256(open(apk, "rb").read()).hexdigest()
lines = [
    f"# {product} v{v}", "",
    "**Android:**", f"`{name}`", "",
    f"Install over any earlier {product} build (same app, same signing key, your progress is kept).", "",
]
if rel.get("notes"):
    lines += ["## What's in this build", ""] + [f"- {n}" for n in rel["notes"]] + [""]
lines += [
    "---", "## Technical details (engineering only)", "",
    f"- Public version: v{v}",
    f"- Source commit: `{commit}`",
    f"- Android versionCode: {vcode} (CI run {run})",
    f"- Engine: {engine}; target SDK {target}; arm64-v8a only",
    "- Signing: debug key (throwaway; not Play-ready)",
    f"- APK SHA-256: `{sha}`",
    "- The About screen shows the same public version, the commit and the versionCode.",
]
open(out, "w").write("\n".join(lines) + "\n")
