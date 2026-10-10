# Hot Attic Games - Ragdoll Rally Launch: rules for every Claude session

## Release naming (MANDATORY, studio-wide convention)
The owner must never have to decipher branch names, SHAs, build numbers or codenames to know which file to install.

- Public product name: **Ragdoll Rally Launch**. Public version: **v<number>**, sequential (v11, v12, v13 ...).
- GitHub Release title: `Ragdoll Rally Launch v<N>`. Tag: `v<N>`. Marked **Latest** (never a pre-release).
- Playable file: `Ragdoll-Rally-Launch-v<N>.apk` (checksum: `.apk.sha256`).
- NEVER put b9 / build-17 / g2 / r5 / poc / expanded / api36 / final / codenames in a release title, tag, or filename.
- NEVER use semantic versions (0.4.0) as the public version. Android `versionName` is `v<N>`; `versionCode` stays the CI run number (internal).
- One number identifies ONE delivered binary. Never reuse a number for a different binary; never overwrite a delivered release.
- Only bump the number for a build that is actually delivered to the owner for testing/release. Failed CI runs and developer-only builds do not consume numbers.
- Technical identifiers (SHA, versionCode, OTA channel/id, native generation, API level, engine, CI run, signing, checksums) belong in the release notes' "Technical details" section and in About/diagnostics, not in titles or filenames.
- Android and any other platform artifacts of the same release share the same public version.

### How to deliver a build (the public version is supplied ONCE)
1. `release/release.json` holds the public version (`"version": N`) and `"deliver"`. Work on the next version with `deliver: false`: CI builds an *internal test build* (About says "vN (internal test build, not delivered)"), uploads it as a workflow artifact only, and publishes nothing.
2. To deliver: set `"deliver": true` (optionally fill `"notes"` with a few plain-language bullets) and push. CI builds, tests, verifies the APK, and publishes release `Ragdoll Rally Launch vN` (tag `vN`, Latest) with `Ragdoll-Rally-Launch-vN.apk`, checksum, build report and notes.
3. Afterwards, bump `"version"` to N+1 and set `"deliver": false` in the next commit. If `vN` already exists CI refuses to publish it again.
4. The same number flows into the release title, tag, filename, notes, Android versionName and the About screen.

Full history and the old-name -> v-number map: `docs/RELEASES.md`.

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
- Routine pushes cost zero minutes. `android.yml` (the APK build) triggers ONLY on a push that changes `release/release.json`, and then builds only if that file says `"deliver": true`; or by manual `workflow_dispatch` when an internal test APK is genuinely needed for physical testing. Docs/research/bookkeeping changes never run it.
- Do not rebuild the same SHA, re-run to see whether a flaky test passes, build platforms nobody asked for (no Windows EXEs unless requested), or build an APK for an OTA-only change.
- Actions ARE appropriate for: the final validation + build of a candidate that is really being delivered; OTA publication with its safety/compat/signing checks; a platform-specific check that cannot be reproduced locally.
- Release safety is never traded for minutes: signing verification, runtime/OTA compatibility, `verify_apk.py`, APK content inspection and rollback protections stay mandatory for delivery builds.
- Workflows use concurrency groups; `launch-ota.yml` is manual/request-file only; `release-retrofit.yml` is manual only.
