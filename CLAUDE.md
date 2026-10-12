# Hot Attic Games - Ragdoll Rally Launch: rules for every Claude session

## Release naming (MANDATORY; owner decision N1, 2026-10-12, Hot Attic Games standard v2.0)
The owner must never have to decipher branch names, SHAs, build numbers or codenames to know which file to install.

- Game name stays **Ragdoll Rally Launch** in the app and About. Release naming follows the studio standard: **Ragdoll Rally Build NN**, one native build number per coordinated release.
- GitHub Release title: `Ragdoll Rally Build NN`. Tag: `build-NN`. Assets (the label on the release page keeps the spaces; GitHub downloads show dots):
  `Ragdoll Rally Build NN APK.apk`, `Ragdoll Rally Build NN EXE.zip`, `Ragdoll Rally Build NN Linux.tar.gz`, `build-manifest.json`, `checksums.sha256`.
- Numbers continue the old sequence: the next build is **Build 19** (v18 was the last `vN` release). NEVER rename, delete or move the historical `v<N>` releases and tags; they stay as they are.
- One number identifies ONE binary set built from ONE immutable source SHA. Never reuse a number; never overwrite a published release. A number is consumed only by a published release (`github_releases`); `local_only` runs and failed runs consume nothing.
- NEVER put b9 / build-17 / g2 / r5 / poc / expanded / api36 / final / codenames in a release title, tag or file name. Technical identifiers (SHA, versionCode, OTA channel/id/revision, runtime compat, API level, engine, CI run, signing, checksums) go in `build-manifest.json`, the release notes' "Technical details" and About/diagnostics. OTA revision identifiers are separate from the native build number.
- Android `versionName` is `Build NN`; `versionCode` stays the CI run number (internal).
- All platform artifacts of one release share the number and the SHA.

### How to build / deliver (one workflow, manual only)
1. Commit and validate locally (`tools/local_validate.sh full`, `tools/package_smoke.sh`). `release/release.json` "version" is only the *planned next number* used by local builds and the About text; it never triggers anything.
2. The owner (or a session the owner authorizes in the same message) dispatches **Coordinated build** (`.github/workflows/build.yml`) with `platform` (android|windows|linux|all), `source_sha` (full SHA on the authoritative branch), `build_number` and `destination` (`github_releases` | `local_only`). Nothing else ever starts a build: pushes, merges, tags and version edits cost zero minutes.
3. `local_only` keeps the verified set as the private workflow artifact `build-NN-release-set` for 14 days (Actions UI or `gh run download <run-id> -n build-NN-release-set`); no tag, no release, no number consumed. `github_releases` additionally creates the release after every selected platform passed.
4. Local desktop builds: `tools/build.sh --platform windows|linux|all` (names are "internal" unless the tree is clean and the number is unused). Android is built only by the workflow.
5. A numbered-build request authorizes that build and its stated destination only. It does not authorize an OTA, Steam, Google Play or a merge into `main`.

Full history and the old-name -> number map: `docs/RELEASES.md`.

## Studio splash (MANDATORY, studio-wide)
Every Hot Attic Games app/game must open with the **Hot Attic Games studio splash** before its own title/menu/onboarding, on cold launch only.
- The ONLY canonical artwork is **`Hot_Attic_Games_Master_Logo_ALPHA_FINAL.png`** (owner-supplied; on `main` at the repo root; shipped unmodified at `launch/branding/`). Never wait for, look for, or recreate any other logo file name. `Hot_Attic_Games_Master_Logo.png` is obsolete.
- Never redraw, recreate, crop, stretch, recolour or substitute it. Keep its transparency and aspect ratio; fit the whole artwork in the safe area. ~2.4 s with fade in/out, no extra text or effects.
- Already implemented in `launch/scripts/boot.gd` (do not build a second splash). Details, tests and behaviour: `docs/STUDIO_SPLASH.md`; guarded by `launch/tests/verify_splash.gd`, which pins the file's SHA-256.
- Order: native splash (dark, no image) -> studio card -> (staged OTA behind its modal) -> the game's own opening. Never replay on background/resume.

## Other standing rules
- Keep the Android package id and signing key unchanged (`com.hotatticgames.ragdollrally.launch`, committed throwaway debug keystore) so every build installs over the last.
- Never commit private signing material. No Play upload.
- Do not invent a separate "Legacy" game. There is one product.
- Commit and push work; open a draft PR for pushed branches.

## GitHub Actions budget policy (STANDING OWNER DIRECTIVE)
GitHub-hosted Actions minutes are shared across the owner's projects and deliberately scarce. Before starting any workflow ask: "Does this need GitHub Actions, or can I prove it locally?"
- Validate locally first: `tools/local_validate.sh [fast|full]` runs the same Godot test suites CI runs (set `GODOT=` to the 4.7.1 binary). Debug and iterate locally, never by repeated CI runs.
- Routine pushes cost zero minutes. The only builds are the manual **Coordinated build** (`build.yml`) and the manual OTA publisher; the only automatic job is the ~1-minute read-only `checks.yml` on pull requests (policy + Python tests + actionlint). Docs/research/bookkeeping changes never build anything.
- Do not rebuild the same SHA, re-run to see whether a flaky test passes, build platforms nobody asked for (no Windows EXEs unless requested), or build an APK for an OTA-only change.
- Actions ARE appropriate for: the final validation + build of a candidate that is really being delivered; OTA publication with its safety/compat/signing checks; a platform-specific check that cannot be reproduced locally.
- Release safety is never traded for minutes: signing verification, runtime/OTA compatibility, `verify_apk.py`, APK content inspection and rollback protections stay mandatory for delivery builds.
- Workflows use concurrency groups; `launch-ota.yml` is manual-only and needs the phrase `PUBLISH OTA` plus the SHA-256 of `launch/ota/publish_request.json`; `release-retrofit.yml` is manual only.

## SINGLE SOURCE OF TRUTH (MANDATORY, owner directive 2026-10-12; full text: `docs/ENGINEERING_POLICY.md`)
**Every change belongs to one authoritative product history. Every supported platform builds from that history. Every abandoned branch must be accounted for before valuable work is discarded.**
- ONE game, ONE Godot project (`launch/`), many targets (Android, Windows, Linux/Steam Deck). Never fork the game per platform; platform differences live in the documented adapters only.
- The authoritative branch is `release/release.json` -> `authoritative_branch` (`claude/launch-gameplay-pivot`). Branches are temporary workspaces: start from it, merge back after validation; never keep permanent per-platform or per-agent copies. Release/OTA workflows run only from it.
- A fix for one platform is evaluated against all platforms. A coordinated release uses ONE source SHA for every artifact (`tools/provenance.py`, `tools/coordinated.py`, `tools/release_manifest.py`); desktop builds require a committed SHA on the authoritative branch.
- Before discarding or abandoning a branch, run `python3 tools/branch_ledger.py --check` and record a disposition in `release/branch_dispositions.json`. Never delete branches or rewrite shared history without owner approval.
- Publishing APKs/EXEs/OTAs, merging into `main`, and changing OTA-boundary files need explicit owner authorisation. OTA must never serve source older than the native release on its channel (see policy section 5).
- Enforced by `python3 tools/check_policy.py` (run by `tools/local_validate.sh` and by the release workflows). Do not weaken it.
