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
pack `provenance.json`; a coordinated release is joined with `tools/release_manifest.py` (one SHA, no dirty trees).

## OTA channel poc-g2 vs native builds (open finding)
All APKs v14-v18 embed channel `poc-g2` and runtime_compat `r2-abbbcedcb90e` (unchanged because no boundary file changed). The channel manifest
(`launch-ota-channel-poc-g2`, downloaded 6 times so far) points at OTA `poc-g2-3-faeb937`: sequence 3, source faeb937, which is 20 commits OLDER than v18.
`ota_client.gd` only compares sequences (embedded baseline = 0), so a v15-v18 install that reaches the manifest will download and run the older
faeb937 source after the next cold launch. Resolution needs the owner (publishing an OTA is not an authorised action for the development agent):
publish a newer OTA from the authoritative tip to `poc-g2` (sequence 4), or retire the channel, and make the next native build refuse OTAs older than
its own source (boundary change).
