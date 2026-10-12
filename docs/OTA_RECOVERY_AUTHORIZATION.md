# OTA recovery authorization package (corrective poc-g2 OTA) - NOT PUBLISHED

Status: prepared and validated locally. Nothing has been published, nothing has been dispatched. Decision N2: not yet authorized.
Background and incident analysis: `docs/OTA_RECOVERY.md`.

| # | Question | Answer (evidence) |
|---|---|---|
| 1 | Exact proposed OTA source | tag `v18` = `dcb9c4d7faec092e18f2ca08145923ad334342d0` (payload epoch 83), on the authoritative line. Request file: `launch/ota/proposed/poc-g2-recovery.json` (`source_ref: v18`). |
| 2 | Native runtime identifiers | `runtime_compat r2-abbbcedcb90e` (computed from the v18 tree, identical to the shipped v14-v18 APKs), channel `poc-g2`. Build 19 / the current tip (`r2-f683798da27a`, channel `g3`) is a different runtime and is untouched. |
| 3 | Supported installed APKs | v14, v15, v16, v17, v18 (versionCodes 27, 28, 29, 30, 31). Any other runtime ignores the manifest (`NEW`/`LEGACY` tests: cross-runtime payload rejected). |
| 4 | What changes | Payload content = the exact v18 game scripts/scenes/assets (baseline-equal). v18 devices: no change at all. v15-v17 devices: move to v18 content. v14 devices: move to v18 content (the same upgrade the old seq-3 gave them). Devices that applied seq 3 (faeb937, older than v15): restored to v18 content. Recovery behaviour / update infrastructure on devices: NOT changed (legacy clients cannot be changed remotely). No native code, signing or package identity change. |
| 5 | Signing and integrity | HTTPS-only manifest and payload URLs; manifest carries SHA-256 + size, checked after download (before staging) and again at activation. Authenticity rests on GitHub repository/release permissions: there is NO detached signature and legacy clients cannot verify one (stated limitation). APK signing is unaffected. Publisher gate `ota_tools.py guard` refuses an older payload, a non-increasing sequence, or a source outside the authoritative history. |
| 6 | Atomic staging | `download.part` is renamed to the staged file only after the hash matches; state is written via `state.json.tmp` + rename; activation only at the next cold launch behind the "applying update" modal (legacy client behaviour, tests `INTERRUPTED`, `ACTIVATION`). |
| 7 | Rollback / known-good | The embedded baseline always exists; a pack that fails to mount is rolled back and blacklisted; the previous pack is kept as fallback. To roll the channel forward-safely: publish a NEW higher sequence (legacy clients only move to a higher sequence; re-uploading an old manifest does nothing for devices already past it). A deliberate older payload needs `rollback_reason` + `rollback_floor_epoch` in the request (guard refuses otherwise). |
| 8 | Could the workflow publish unintentionally? | It could before this pass: committing `launch/ota/publish_request.json` to the branch started `launch-ota.yml`. FIXED: `launch-ota.yml` is now `workflow_dispatch` only and also needs the exact phrase `PUBLISH OTA` and the SHA-256 of the committed request file (`check_policy.py` and `test_coordinated.py` enforce no push/merge/tag trigger; actionlint clean). The old request file currently in the repo (mayhem pass) is inert. |
| 9 | Validation without exposing players | Done locally: (a) frozen copy of the shipped v14-v18 client + the real live manifest reproduce the downgrade, then accept the seq-4 baseline-equal manifest for versionCodes 27/28/31, fresh clients, clients already running seq 3 and clients with seq 3 staged (`verify_ota_safety`, 49 checks); (b) candidate pack built with the workflow's own commands mounts in Godot: `launch-ota-poc-g2-4-dcb9c4d.pck`, 1,975,992 bytes, sha256 `5572d6a4...bd4a` (CI rebuild will differ in hash, not content); (c) `ota_tools.py guard` passes: "epoch 83 >= baseline 83 (v18), sequence 4"; (d) save data sentinel untouched. NOT possible: a device canary - installed APKs follow only `poc-g2`. NOT done: byte comparison with the shipped v18 APK (the release asset is not downloadable from this environment). Residual risk: first exposure is real players on `poc-g2`; mitigated because the payload equals the v18 APK content. The owner's own v18 device should be the first to launch after publication. |
| 10 | Exact publication / rollback procedure | below |

## Exact publication procedure (only after the owner says "publish the poc-g2 recovery")
1. On `claude/launch-gameplay-pivot`: `cp launch/ota/proposed/poc-g2-recovery.json launch/ota/publish_request.json`; commit; push. (This alone starts nothing.)
2. `sha256sum launch/ota/publish_request.json` -> hash H.
3. Dispatch workflow **Launch OTA publish** from `claude/launch-gameplay-pivot` with `confirm = PUBLISH OTA` and `request_sha256 = H`.
4. The job: policy gate -> suites + OTA safety tests -> builds the pack from `v18` -> manifest (sequence = run number > 3) -> guard against the live channel -> immutable release `launch-ota-poc-g2-<run>-dcb9c4d` -> replaces the channel pointer manifest.
5. Verify: `curl -L https://github.com/verbal76/Ragdoll-Rally/releases/download/launch-ota-channel-poc-g2/manifest.json` shows `source_sha` dcb9c4d..., `source_epoch` 83, sequence > 3, runtime `r2-abbbcedcb90e`. On a v18 device: Settings -> About -> diagnostics, running OTA id after two launches.
## Rollback
- Bad payload: publish the next sequence from a known-good source with the same procedure (for an older-than-v18 payload add `rollback_reason` and `rollback_floor_epoch` to the request). Pointer-only revert is not a rollback for devices already past that sequence.
- Devices that cannot mount the pack fall back automatically (rollback + blacklist) to the previous pack or the embedded v18 baseline.

## Approval needed from the owner
Authorize steps 1-3 (publication to the live `poc-g2` channel). Accept the stated limits: no detached signature; no device canary; a client that already staged seq 3 applies it once before seq 4.
