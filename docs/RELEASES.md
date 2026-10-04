# Releases and versions

**Ragdoll Rally Launch v12 is the current public version (gameplay pivot + studio splash). The next delivered build is v13.**

The newest playable file is always the GitHub **Latest** release, titled `Ragdoll Rally Launch v<N>`, containing `Ragdoll-Rally-Launch-v<N>.apk`.
The rules and the delivery procedure are in the repository root `CLAUDE.md` (they are mandatory for every session).

## How the numbering was established (2026-10-04)
Public versions count the playable builds that were actually *delivered* as installable APK releases, in order.
Failed or never-delivered CI runs did not consume a number (CI runs 3, 10, 13, 14 never produced a release).
The OTA pipeline-check releases (`launch-ota-*`) are infrastructure, not playable builds, and are not versions.
The old `bN` numbers were CI run numbers (they double as Android versionCode), so they have gaps; the public sequence does not.

| Public version | Original tag (historical, kept) | What it was |
|---|---|---|
| v1 | `launch-poc-b1` | first 3D slingshot proof of concept |
| v2 | `launch-poc-b2` | physics reference build |
| v3 | `launch-poc-b4` | About screen + OTA client |
| v4 | `launch-poc-b5` | same, CI iteration |
| v5 | `launch-poc-b6` | same, CI iteration |
| v6 | `launch-g2-b7` | Godot 4.7.1 / Android API 36 / 16 KB pages |
| v7 | `launch-g2x-b8` | expanded city |
| v8 | `launch-g2x-b9` | expanded city + HUD safe margins (the "b9" checkpoint) |
| v9 | `launch-g2m-b11` | dense breakable city, TNT, beams, upgrades |
| v10 | `launch-g2m-b12` | + Hot Attic Games studio splash |
| v11 | `rr-launch-b15` (re-tagged `v11`) | + "RR Launch" name, new icon, transparent icon background |
| **v12** | `v12` | gameplay pivot (18 ragdolls, skipping/ricochet physics, limbs, fire, upgrades, Test Yard) + Hot Attic Games studio splash |

Why v11 and not v15 or v13: v15 would be the CI run number / versionCode (an internal counter with gaps), and the old tags
were never a clean sequence. Eleven installable builds were delivered, so the current version is v11.

## v11 is the original binary
v11 is the exact APK CI built and verified for run 15 (SHA-256 recorded in the release notes). It was renamed and re-presented, not rebuilt,
so there is no binary drift. Consequence: its About screen predates the convention and shows "Version 0.4.0 / code 15". The release notes say so.
From v12 on, About shows `Version: v<N>` at the top, with the commit, versionCode, engine, SDK and OTA data below it.

## Historical releases
Titles were changed to `Ragdoll Rally Launch v<N>` with the original tag named in the notes. Tags, binaries and asset names were left untouched.
They remain pre-releases, so only the newest delivery is ever "Latest".

## Internal (engineering) identifiers still exist
Git SHA, Android versionCode (CI run number), package id, OTA channel/id/runtime-compat, native generation, API level, engine version,
CI run, signing identity, checksums. They appear in the release notes' Technical details and in About. They are not the public version.

## Multiple platforms
If a Windows (or other) build is ever added it shares the Android build's public version for the same release
(`Ragdoll-Rally-Launch-v<N>-Windows.zip`). Platform build counters stay internal.
