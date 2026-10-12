# Build 19 release candidate (prepared, NOT built, NOT published)

Under naming decision N1 the next release is **Ragdoll Rally Build 19** (tag `build-19`). `release/release.json` "version": 19 is the planned number only; nothing
is triggered by it. v19 / Build 19 is unpublished and the corrective OTA is unpublished.

## Content since v18 (all on the authoritative branch)
- Steam Deck / Steam Machine tuning (docs/STEAMDECK.md): controller-first prompts, Deck graphics preset, adaptive resolution, lite ink, native Linux export.
- Controller glyphs (Xbox / PlayStation / Switch / keyboard + mouse) on the Controls screen, hints, legend and toasts; manual prompt style; save schema stamp + crash-safe writes.
- Single-source-of-truth policy, provenance, coordinated build workflow (docs/ENGINEERING_POLICY.md, docs/RELEASES.md).
- OTA version floor + publisher/native gates (docs/OTA_RECOVERY.md). A native-boundary change: Build 19 has a NEW runtime fingerprint and follows channel `g3`;
  v14-v18 stay on `poc-g2`.

## Gate before building (owner decisions / evidence)
1. Corrective `poc-g2` OTA: docs/OTA_RECOVERY_AUTHORIZATION.md (published or consciously deferred).
2. No physical-device evidence exists for Android or the Deck for any build after v14; the candidate is validated headless / software / packaging only.
3. Glyph license: CC0 per the author's listing (owner screenshot); keep the itch.io URL + dated copy (launch/assets/glyphs/NOTICE.md).

## One SHA for every target (a single workflow run)
1. Freeze: `git rev-parse HEAD` on `claude/launch-gameplay-pivot`, clean tree, `tools/local_validate.sh full` and `tools/package_smoke.sh` green. Record the SHA.
2. Dispatch **Coordinated build**: platform `all`, `source_sha` = the frozen SHA, `build_number` 19, destination `local_only` first (private artifact, no number consumed),
   then `github_releases` for the same SHA once the files have been checked. The workflow validates the request, runs the full suite on the exact SHA, builds Android +
   Windows + Linux, writes `build-manifest.json` + `checksums.sha256`, and only then creates release `Ragdoll Rally Build 19` (tag `build-19`).
3. Add the Build 19 row to `docs/RELEASE_PARITY.md`; the `build-19` tag becomes a native baseline for the OTA guards automatically.
