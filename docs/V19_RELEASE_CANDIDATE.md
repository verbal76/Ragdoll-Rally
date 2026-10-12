# v19 release candidate (prepared, NOT built, NOT published)

`release/release.json` is at version 19 with `"deliver": false` (CLAUDE.md procedure step 1): pushes build nothing.

## Content since v18 (all on the authoritative branch)
- Steam Deck / Steam Machine tuning (docs/STEAMDECK.md): controller-first prompts, Deck graphics preset, adaptive resolution, lite ink, native Linux export.
- Single-source-of-truth policy, provenance and release-manifest tooling (docs/ENGINEERING_POLICY.md).
- OTA version floor + publisher/native gates (docs/OTA_RECOVERY.md). This is a native-boundary change: v19 has a NEW runtime fingerprint and follows
  channel `g3`; v14-v18 stay on `poc-g2`.

## Gate before building (owner decisions / evidence)
1. Corrective `poc-g2` OTA published (or consciously deferred): docs/OTA_RECOVERY.md "EXACT proposed publication".
2. Optional: custom controller glyph artwork (owner go-ahead pending).
3. No physical-device evidence exists for Android or the Deck for any build after v14; the candidate is validated headless/software only.

## One SHA for every target
1. Freeze: `git rev-parse HEAD` on `claude/launch-gameplay-pivot`, clean tree, `tools/local_validate.sh full` green. Record the SHA.
2. Desktop (local, exact SHA, provenance packed): `GODOT=... tools/build_windows.sh out/win` and `tools/build_linux.sh out/linux`.
3. Android: set `"deliver": true` in `release/release.json` in a commit ON that SHA's line; CI builds the APK from that exact commit (gate: policy,
   native OTA gate, tests).
   If the release commit differs from the frozen SHA, it may differ ONLY in release.json / docs (check with `git diff <frozen> <release>`), or the
   desktop builds must be redone from the release commit.
4. `python3 tools/release_manifest.py build out/manifest.json out/win/*.provenance.json out/linux/*.provenance.json` (fails unless one SHA, no dirty tree);
   attach to the release notes. Add the v19 row to `docs/RELEASE_PARITY.md`; the v19 tag becomes a native baseline automatically.
5. Tag/release `v19`; afterwards bump release.json to 20 with deliver false.
