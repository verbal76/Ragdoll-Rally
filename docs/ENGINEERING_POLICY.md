# Engineering policy: one source of truth

Ragdoll Rally Launch is ONE GAME that runs on Android, Windows and Linux (Steam Deck). It is not three games.
Every change belongs to one authoritative product history. Every supported platform builds from that history. Every abandoned branch
must be accounted for before valuable work is discarded. (Owner directive, 2026-10-12. Applies to every Hot Attic Games project, each in
its own repository; repositories stay independent.)

## 1. Authoritative source
- Authoritative development line: the branch named in `release/release.json` -> `"authoritative_branch"` (today `claude/launch-gameplay-pivot`).
  Every public release v11 ... v18 and every tag is reachable from it. `main` is the protected default branch and currently lags it: bringing
  `main` up to date is an owner decision (see `docs/BRANCH_LEDGER.md`).
- One Godot project (`launch/project.godot`), one set of scripts, scenes and assets. Targets differ only through export presets
  (`launch/export_presets.cfg`: Android, Windows Desktop, Linux Desktop), build scripts and the platform adapters below.
- One codebase is not one binary: the APK, EXE and Linux build come from the same SHA.

## 2. Platform parity
Shared (identical on every platform): gameplay, physics, destruction, launchers, upgrades, economy, cities, traffic and pedestrians,
scoring, saves, world persistence, comic-ink look, studio splash, OTA client.
Platform adapters (the only allowed differences, all isolated):
| Concern | Android | Desktop (Windows, Linux, Steam Deck) | Where |
|---|---|---|---|
| Input | touch (emulated mouse) | keyboard + mouse + auto-detected gamepads, remappable, controller-default on SteamOS | `scripts/controls.gd`, `controls_panel.gd`, `main.gd` (`_pad_input`, `_handle_actions`) |
| Graphics options | engine defaults | detected display/GPU, presets, Deck preset, adaptive scale | `scripts/graphics.gd`, `graphics_panel.gd` (no-ops on mobile) |
| Exit button, window modes | n/a | EXIT (double press), fullscreen/windowed | `main.gd` (guarded by `OS.has_feature("mobile")`) |
| Updates | OTA channel + native APK | none (Steam / the store delivers) | `scripts/ota_client.gd` (boundary file), `build_info.gd` |
| Packaging / signing | Gradle, throwaway debug key | export templates, archive with provenance | `tools/build_windows.sh`, `tools/build_linux.sh`, `.github/workflows/android.yml` |
A fix made for one platform is evaluated against all others before it is merged. A shared-code change never lands for one target only.

## 3. Branches are workspaces, not products
- A branch starts from the authoritative line, has a purpose, and is merged back after validation (`tools/local_validate.sh full`).
- No permanent per-platform branches. Release and OTA workflows only run for the authoritative branch (`tools/check_policy.py --ci`).
- Parallel agents/worktrees do not keep their own copy of the game; unmerged work stays discoverable in `docs/BRANCH_LEDGER.md`.
- No branch is deleted because it looks obsolete. `windows-internal-test` is an artifact-hosting orphan branch, not a development line.
- Re-generate and check the ledger: `python3 tools/branch_ledger.py --write` and `--check` (fails for a branch with work outside the
  authoritative line and no entry in `release/branch_dispositions.json`).

## 4. Builds, provenance and releases
- Every platform build records: source SHA, branch, version, platform, build config, engine, export-template version, timestamp, artifact
  SHA-256 (`tools/provenance.py`; `provenance.json` is packed with desktop builds, `build_info.json` / build report for the APK).
- Desktop builds refuse to run unless HEAD is on the authoritative branch; a dirty tree is allowed only as an INTERNAL build
  (`ALLOW_DIRTY=1`, archive named `v<N>-internal-<sha7>`), never part of a coordinated release.
- A coordinated release uses ONE SHA for every target. `python3 tools/release_manifest.py build OUT.json <provenance files>` fails when the
  SHAs or versions differ and when any build was made from a dirty tree; `verify` checks the SHA is on the authoritative branch.
  If one platform fails validation, do not substitute another revision: fix on the authoritative line and rebuild every target.
- Public naming and the delivery procedure stay as in `CLAUDE.md` (`Ragdoll Rally Launch v<N>`, `release/release.json`).
- Publishing APKs/EXEs/OTAs is an owner-authorised action; building and testing are not.

## 5. OTA and native compatibility
- An OTA pack is valid only for a native build with the same `runtime_compat` fingerprint and channel (`launch/tools/ota_tools.py fingerprint`).
- KNOWN HAZARD (found by the 2026-10-12 audit): `ota_client.gd` compares only the OTA `sequence` with the installed state. The embedded
  baseline counts as sequence 0, so a newer native APK with the SAME runtime_compat will download an OLDER OTA that has a higher sequence
  (today `poc-g2` sequence 3, source faeb937) and run the older source. Rule until the client is changed: after every native release, either
  publish a newer OTA from that release's SHA on the same channel, or confirm the channel pack is not older than the release. Changing the
  client is a boundary change (new runtime_compat) and needs owner approval.
- OTA never creates a second history: every OTA is built from a commit on the authoritative branch and records `source_sha`.

## 6. Enforcement (zero extra Actions minutes)
- `tools/check_policy.py` (also run by `tools/local_validate.sh` and by the gate step of `android.yml` and `launch-ota.yml`): authoritative
  branch named; release/OTA workflows trigger only from it; presets for all targets share one payload; no per-platform copies of the game;
  build scripts require provenance; the Android build records its SHA; this policy is present in `CLAUDE.md`; in CI the ref being built is
  the authoritative branch.
- `tools/branch_ledger.py --check` in `tools/local_validate.sh`.
- Shared tests (`tools/local_validate.sh`) run on the one codebase; a skipped required test is a failure, never a pass.

## 7. What this policy does not change
Gameplay feel, physics, scope, visual identity, workflows, save data, the Android package id and signing key, working OTA compatibility.
