# OTA recovery: the poc-g2 downgrade (found 2026-10-12)

## What is live right now (verified against the published assets)
- Channel pointer `launch-ota-channel-poc-g2` -> `manifest.json` = OTA `poc-g2-3-faeb937`: sequence 3, runtime_compat `r2-abbbcedcb90e`, no
  min_version_code, source `faeb937` (epoch 63), published 2026-10-08. Pack sha256 `c7c3c5d9...455f` (verified: matches the manifest), 1,889,776 bytes.
- The pack carries 19 game scripts (main, town, destruction, launchers, rules, ...) plus scenes/assets. Mounted over a newer baseline it REPLACES
  those scripts, so the game runs faeb937 code (no modular towns, cars/pedestrians, movable launcher, 180-degree aim, city persistence, EXIT,
  controller SELECT, Deck tuning, ...). Scripts that only exist in v15+ stay on disk but nothing loads them.
- Download counters (not proof of installs): pack 4, manifest 6 (includes one request made by the audit itself).

## Are v14-v18 exposed? Yes (eligibility proven, installation on a device not observed)
- `launch/scripts/ota_client.gd` is byte-identical in the v14, v15, v16, v17 and v18 tags. The runtime fingerprint is `r2-abbbcedcb90e` in all five
  (and in faeb937), the channel baked into every APK is `poc-g2`, version codes are 27-31.
- Updater activation rules (read from the code, reproduced by `tests/verify_ota_safety.gd` with the frozen legacy client): manifest -> channel +
  runtime_compat + `min_version_code` + sha/size + `sequence > installed sequence` (embedded baseline counts as 0) -> download -> stage ->
  activate at next cold launch (modal) -> confirmed after the game starts -> mounted at every launch.
- Result: v14 (epoch 49) legitimately upgrades to faeb937 (epoch 63). v15-v18 (epochs 77, 78, 81, 83) are DOWNGRADED by it.
- A manifest download is not an install: staging needs the pack download + sha check, activation needs one more cold launch. The only on-device
  evidence is Settings -> About -> diagnostics ("Update status", running OTA id). If it says `poc-g2-3-faeb937` the device runs the old payload.

## Already staged / applied updates (reproduced in tests)
- A staged update is NOT cancelled by changing or deleting the manifest: `boot_prepare()` only looks at local state, `apply_staged()` only re-checks
  the stored size and sha. It activates at the next launch.
- A confirmed pack is mounted at every launch regardless of what the channel serves (`current` slot). No client code path removes it except a
  higher-sequence compatible OTA replacing it.
- After an APK upgrade `user://ota` survives, so an old confirmed pack would also keep overriding a NEWER native baseline (legacy client does not
  compare it to the new baseline). The new client (below) closes this.

## Options for the installed (legacy, r2) clients
| Option | Stops new staging | Fixes clients that staged seq 3 | Fixes clients running seq 3 | Notes |
|---|---|---|---|---|
| A. new compatible OTA from the authoritative source (sequence 4) | yes | yes (replaces pending) | yes (higher sequence) | needs a publication; supported by the legacy client exactly as seq 3 was |
| B. retire the channel (delete/404 the manifest) | yes | NO (activates anyway) | NO | proven in tests |
| C. "no update" manifest (sequence 0) | yes, only for clients at sequence 0 | NO | NO (already at/after) | `min_version_code` can only exclude OLDER natives, there is no max in legacy clients |
Recommendation: A, with a payload equal to the newest native baseline, i.e. built from the `v18` tag (`dcb9c4d`, epoch 83): zero behaviour change
for v18 users, restores v15-v17 to the v18 payload, upgrades v14 to the same payload. The worst case is exactly v18. Two launches may still show
the old payload for a client that had already staged seq 3 (it applies once, then seq 4 follows); nothing can be done remotely about that.
Why not the tip: it carries unreleased desktop/Deck work that has not been validated on Android hardware.

## Prepared (validated locally, NOT published)
- Candidate built with the same tooling the workflow uses: `launch-ota-poc-g2-4-dcb9c4d.pck`, 1,975,992 bytes, sha256 `5572d6a4...bd4a`, runtime
  `r2-abbbcedcb90e`, source `dcb9c4d7faec092e18f2ca08145923ad334342d0`, source_epoch 83, sequence 4 (the workflow uses the run number, which is
  greater than 3). Local checks: pack mounts in Godot; the real manifest is accepted by the frozen legacy client for versionCodes 27/28/31, for a fresh
  client and for one already running seq 3; `ota_tools.py guard` passes. (Rebuilt by CI at publication, so the final hash will differ.)
- The workflow now supports `source_ref`, runs the OTA safety guard and the OTA safety tests before publishing.

## EXACT proposed publication (needs owner approval; nothing has been pushed to this path)
1. Replace `launch/ota/publish_request.json` with the contents of `launch/ota/proposed/poc-g2-recovery.json`:
   `{"name": "Baseline-equal payload for v14-v18 (restores v18 gameplay, supersedes poc-g2-3-faeb937)", "channel": "poc-g2", "source_ref": "v18"}`
2. Commit and push to `claude/launch-gameplay-pivot` (that commit IS the authorization, as documented in `launch-ota.yml`).
3. The workflow: policy gate -> tests -> builds the pack from the v18 source -> manifest sequence = run number -> guard (epoch >= every native
   baseline that would accept it; sequence > live) -> creates release `launch-ota-poc-g2-<run>-dcb9c4d` and replaces the channel pointer manifest.
4. Verify: `curl -L https://github.com/verbal76/Ragdoll-Rally/releases/download/launch-ota-channel-poc-g2/manifest.json` shows source_sha
   `dcb9c4d...`, source_epoch 83 and sequence > 3; install v18 and check About after two launches.

## Permanent safeguards (implemented, validated offline; take effect for native builds from v19)
- Client (`ota_client.gd`, `build_info.gd`; boundary files => new runtime fingerprint, so legacy clients never see future r2-incompatible OTAs):
  payload version floor (`source_epoch` vs the baked native epoch), ordering by (epoch, sequence), source/compat/channel validation, re-validation of
  staged / current / previous packs at every launch and at activation, crash-loop guard (3 unconfirmed launches), leftover-download cleanup, failed-id
  blacklist, explicit rollback authorization (`rollback.authorized + reason + floor_epoch`).
- Publisher (`ota_tools.py guard`, `launch-ota.yml`): refuses a payload older than any native baseline that would accept it, a sequence not above the
  live channel, a source outside the authoritative history; `source_ref` publishes an exact earlier SHA (baseline-equal / rollback).
- Native release gate (`ota_tools.py native-gate`, `android.yml`): a delivery fails if the live channel manifest it would accept carries an older
  payload. This gate would have blocked v15 (the incident).
- v19+ uses channel `g3` (separate pointer) so the legacy poc-g2 recovery manifest keeps serving v14-v18.
