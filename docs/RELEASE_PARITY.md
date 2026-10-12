# Release parity record

Source of truth for "which artifact came from which commit" (policy: docs/ENGINEERING_POLICY.md, section 4). Audit of 2026-10-12.

| Public version | APK (CI) source | Desktop (Windows) | Notes |
|---|---|---|---|
| v14 | 6006432 | - | |
| v15 | 15c414a | Windows zip built from the working tree at 5638c8e + release metadata | desktop built locally, no provenance file |
| v16 | 7a97a8f | Windows zip, working tree at the parent of 7a97a8f + release metadata | code identical (release.json / docs only differ) |
| v17 | 2a80b90 | Windows zip, same pattern | |
| v18 | dcb9c4d | Windows zip, built at the parent of dcb9c4d + release metadata | `git diff dcb9c4d^ dcb9c4d` touches only docs/RELEASES.md, docs/WINDOWS_STEAM.md, release/release.json, so the code is identical |
| (unreleased) | - | Linux/Steam Deck + Windows internal builds at cf0353b | newer than v18 (Deck tuning); an APK from the same SHA does not exist yet. A v19 must rebuild EVERY target from one SHA. |

From now on desktop builds are produced by `tools/build_windows.sh` / `tools/build_linux.sh`, which require a committed SHA on the authoritative branch and
pack `provenance.json`; a coordinated release is joined with `tools/coordinated.py manifest` into `build-manifest.json` + `checksums.sha256` (one SHA, one build number, no dirty trees, names verified).

## OTA channel poc-g2 vs native builds
Incident, evidence, options and the exact proposed publication: `docs/OTA_RECOVERY.md`. Status: the corrective OTA (baseline-equal, from v18) is
prepared and validated locally and awaits owner authorization; the permanent client/publisher/native-release safeguards are implemented and tested
and reach devices with the v19 native build.
