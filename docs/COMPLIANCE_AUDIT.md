# Compliance audit (provisional) - overnight run of 2026-10-12

**Reference:** the master standard (Hot Attic Games Universal Game Development, Build, Update and Distribution Standard v2.0, supplied as
`HOT_ATTIC_GAMES - steamdeck - dev mandate.doc` mid-run, after the first audit pass) was read in full and the findings below were re-checked against it.
It is not stored in the repository (binary .doc); the owner's copy is the reference. `Source.zip` was supplied and is integrated (GLY-1).

Baseline: Ragdoll Rally Launch, Godot 4.7.1 (GL Compatibility), authoritative branch `claude/launch-gameplay-pivot`, started at c094ef4.
Latest release v18 (Android APK, delivered by CI). v19 prepared, `deliver:false`. Update system: PCK-based OTA (Android only; `ota_enabled` is false in desktop builds).

## Scorecard
| # | Category | Status | Evidence / action |
|---|---|---|---|
| 1 | Source and branches | PASS | one authoritative branch, `check_policy.py` + branch ledger (8 branches, 0 unaccounted) |
| 2 | Android | PARTIAL | CI builds + verifies v18; no physical test after v14 |
| 3 | Windows | PARTIAL | local export script with provenance; v18 zip built, never run on Windows hardware |
| 4 | Linux | PARTIAL | local export (exec bit + run.sh set); internal build only; not run on a Deck |
| 5 | Build flags | PASS | one project, adapters in controls/graphics (Deck detection) |
| 6 | Build numbering | PASS | `release.json` v<N>, CI refuses to re-publish an existing tag |
| 7 | GitHub Releases | PARTIAL | Android only; desktop zips live on the orphan `windows-internal-test` branch, not in a Release (REL-1, RED) |
| 8 | Build provenance | PASS | `tools/provenance.py`, `release_manifest.py`; v14-v18 desktop provenance is reconstructed (docs/RELEASE_PARITY.md) |
| 9 | Release authorization | PASS | android.yml only on release.json + deliver; OTA only on publish_request.json; both authoritative-branch only. Fixed: gate job now read-only (SEC-1) |
| 10 | OTA architecture | PASS | version floor, revalidation, guards (docs/OTA_ARCHITECTURE.md) - new safeguards reach devices only with v19 native |
| 11 | OTA rollback | PASS | explicit authorized rollback only; tests in verify_ota_safety |
| 12 | Controller completeness | PARTIAL | all screens reachable with pad (tests); unverified on hardware |
| 13 | Steam Input | UNVERIFIED | no Steamworks / Steam Input API; default "Gamepad" template assumed |
| 14 | Mixed input | PARTIAL | trackpad/touch never switch prompts on SteamOS; hardware unverified |
| 15 | Automatic text input | NOT APPLICABLE | the game has no text fields (grep) |
| 16 | Steam display | PARTIAL | 1280x720/800 stretch config; no screenshot evidence at 1280x800 in this run |
| 17 | Steam graphics | PARTIAL | GL Compatibility (Vulkan not used; renderer change is RED) |
| 18 | Steam performance | UNVERIFIED | no measurements on Deck hardware; presets are estimates |
| 19 | Steam stability | UNVERIFIED | suspend/resume, controller reconnect not tested |
| 20 | Controller glyphs | PARTIAL | library imported + wired into Controls screen (GLY-1). Hints/toasts still text (names follow the Deck layout) |
| 21 | Offline play | PASS (static) | game needs no network; OTA check failure is non-fatal and desktop has OTA disabled; not run on a device offline |
| 22 | Save safety | PARTIAL->PASS | SAVE-1 fixed non-atomic writes; no schema version key (SAVE-2, RED: migration) |
| 23 | Steam Cloud | BLOCKED | no Steamworks |
| 24 | Graphics settings | PASS | stored in separate `graphics.cfg`, not progress |
| 25 | Branding | PASS | studio splash pinned by verify_splash |
| 26 | Automated testing | PASS | 17 Godot suites + 12 python OTA tests + policy gates, all passing locally (see /report) |
| 27 | Physical testing | FAIL | none after v14 on Android; none ever on Deck/Windows |
| 28 | CI efficiency | PASS | zero minutes on routine pushes; no PR-level lightweight check exists (owner policy prefers local validation) |
| 29 | Licensing | PARTIAL | Kenney packs verified CC0 from License.txt; glyph set and `3dFireSmoke`, `splatpack` etc. per `third_party/NOTICE.md`; glyph set = JulioCacko "Input Prompts", CC0 1.0 per owner-supplied listing screenshot (identified, not independently fetched; LIC-1) |
| 30 | Commercial readiness | FAIL | needs Steamworks, hardware tests, license evidence |

## Findings and queue
| ID | Finding | Sev | Class | Status |
|---|---|---|---|---|
| SAVE-1 | progress/controls/graphics saved with a direct `ConfigFile.save` (a crash mid-write could truncate the save) | P1 | GREEN | FIXED cfb0c2f, `verify_save_safety` |
| GLY-1 | no controller glyph art; Source.zip supplied | P2 | YELLOW | FIXED af138c2 (controls screen), `verify_glyphs`; hints/toasts remain text |
| SEC-1 | android.yml gate job had write token | P3 | GREEN | FIXED (this commit); YAML parsed locally, not exercised in CI (next release.json push) |
| CI-1 | the sparse-checkout gate fix (c094ef4) has not run in CI (android.yml triggers only on release.json) | P2 | - | simulated locally; will be exercised by the next delivery |
| LIC-1 | glyph license: CC0 1.0 identified from the author's listing screenshot; no URL / license file stored | P2 | GREEN (doc) | NOTICE.md records author + license; owner should keep the itch.io URL + dated copy |
| REL-1 | desktop builds not attached to GitHub Releases; naming differs from the directive's "Game Title Build NN" example vs CLAUDE.md `Ragdoll-Rally-Launch-v<N>` | P1 | RED | owner decision (publishing + naming) |
| SAVE-2 | no schema version in launch.cfg | P2 | RED | save-format change |
| STEAM-1 | no Steamworks/Steam Input/Cloud | P1 for Steam | RED | owner account + integration |
| HW-1 | no hardware validation (Deck, Windows, Android after v14) | P1 | RED (needs hardware) | owner |
| OTA-1 | corrective poc-g2 OTA not published | P0 for v14-v18 devices | RED | owner authorization (docs/OTA_RECOVERY.md) |
| GFX-1 | Vulkan/renderer | P3 | RED | not recommended before measurement |

## Gaps against the standard (re-check after reading it)
| ID | Standard requirement | Current state | Class |
|---|---|---|---|
| STD-1 | s.6-8: one release per build "Game Title Build NN", assets `Game Title Build NN APK.apk / EXE.zip / Linux.tar.gz`, tag build-NN or "an established compatible convention" | CLAUDE.md (owner rule, 2026-10) mandates `Ragdoll Rally Launch vN`, `Ragdoll-Rally-Launch-vN.apk`, tag vN. Tag convention is acceptable; titles/filenames differ. Not changed: two owner rules conflict | RED - owner picks one |
| STD-2 | s.9: one manual workflow with inputs platform / source_sha / build_number / destination | android.yml (release.json-gated) + local `tools/build.sh` (added); no single workflow_dispatch building all three from a SHA, desktop not built in CI | RED (Large; hosted builds) - recommended next |
| STD-3 | s.8: desktop artifacts in GitHub Releases | desktop zips are on orphan branch `windows-internal-test`; Android only in Releases | RED (publishing) |
| STD-4 | s.5 manifest per build, checksums.sha256 | `tools/release_manifest.py` + per-APK checksum exist; no single build-manifest.json/checksums.sha256 asset in releases | GREEN-later, part of STD-2 |
| STD-5 | s.19 docs | CLAUDE.md, RELEASES.md, BRANCH_LEDGER.md present; STEAM_HARDWARE_CHECKLIST.md added; UPDATES = OTA_ARCHITECTURE.md + OTA_RECOVERY.md; THIRD_PARTY = launch/ASSETS_LICENSES.md + third_party/NOTICE.md; PLATFORM_SUPPORT = STEAMDECK.md + WINDOWS_STEAM.md + RELEASE_PARITY.md (equivalents, not renamed to avoid duplicates) | done |
| STD-6 | s.13 glyphs: keyboard/mouse art, mixed-input stability, manual override | gamepad art + manual style done; keyboard/mouse art not imported (library has Keyboard_Mouse sets); hints/toasts are text | YELLOW, open |
| STD-7 | s.11 save schema version | none in launch.cfg | RED (migration) |
| STD-8 | s.12.11 measured performance | none | needs hardware |
