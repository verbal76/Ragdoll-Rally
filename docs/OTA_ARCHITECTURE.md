# Launch OTA architecture

Stack: Godot 4.4.1 (GDScript). Previous OTA: **none** (b1/b2 had no updater, no INTERNET permission). Final: custom, architecture-natural **PCK resource-pack OTA**. Original: N/A.

## Boundary
- **OTA-SAFE payload** (shipped as a PCK): `scripts/*.gd` except the boundary files, `scenes/main.tscn`, all `assets/**` (GLB/textures, imported resources).
- **NATIVE-BUILD-REQUIRED**: everything in `launch/ota/boundary.txt` (`project.godot`, `scenes/boot.tscn`, `scripts/boot.gd`, `ota_client.gd`, `build_info.gd`, `update_overlay.gd`, `icon.svg`), the Godot version, export preset (permissions, package, version), export templates, any new `class_name` (global class cache is baked in), GDExtensions.
- **runtime_compat** = `r1-` + SHA-256 prefix over (engine id + boundary file contents + sorted `class_name` list), computed by `launch/tools/ota_tools.py fingerprint`. It is written into the APK (`build_info.json`) and into each OTA manifest. The client refuses an OTA whose `runtime_compat` differs, so a native-required change cannot be delivered as an OTA by accident. Native build identity (`version_code`, source SHA) and OTA identity (id, sequence, source SHA, hash) are kept separate.

## Publication (GitHub Actions: `.github/workflows/launch-ota.yml`, MANUAL `workflow_dispatch` only)
tests (`verify.gd`, `verify_ota.gd`) -> `godot --export-pack "Launch OTA Pack"` (excludes the boundary files) -> `manifest.json` (id, name, sequence = run number, channel, runtime_compat, url, sha256, size, source_sha, published_at) -> immutable release `launch-ota-<channel>-<run>-<sha7>` (pck + manifest) -> mutable channel pointer release `launch-ota-channel-<channel>` whose `manifest.json` asset is replaced. The pack is built with a Linux pack preset: no export templates or Android SDK needed, and the exported resources are byte-identical in name/size to the ones inside the Android APK (checked against b2).
Channels: installed APKs follow **`poc`**. Use `test` for pipeline checks (no installed app follows it). Never auto-triggered.

## Client (`scripts/ota_client.gd`, autoload `Ota`)
- **Discovery**: automatically in the background after the game scene has loaded (never blocks startup, 12 s timeouts), plus on application resume if the last check is older than 30 min. "Check for update" in About is for diagnostics only.
- **Validation**: manifest has all fields, channel matches, runtime_compat matches, sequence strictly newer than running/known-good, not previously failed, not already staged, https only, size cap 64 MB, SHA-256 well-formed.
- **Download/stage**: payload into `user://ota/download.part`, size and SHA-256 verified, then renamed to `<id>.pck`; a partial/corrupt/interrupted download never becomes a pending update.
- **Activation point**: the next cold launch, in `boot.gd`, before any game script is loaded. (Mid-session reload is deliberately not done: already-loaded scripts would stay stale.) The state `activating` is persisted BEFORE mounting.
- **Applying-update UI**: shown only while a verified staged OTA is being activated (see `APPLYING_UPDATE_AND_ABOUT.md`).
- **Known-good / rollback**: the game calls `confirm_startup_success()` after running 3 s on the new payload; only then it is promoted to `current` (old `current` kept as `previous`). A payload that fails to mount, fails verification, or whose activation is never confirmed (crash/kill) is rolled back at the next launch, deleted and blacklisted by id. At boot the client mounts `current` (fallback `previous`); if both are unusable the embedded baseline runs.
- **Offline**: no network is needed to start. Disabled (dev) builds never touch the network.
- **Running OTA identity**: Settings -> About -> OTA section / Copy Diagnostics.

## Verification evidence
- `launch/tests/verify_ota.gd` (deterministic, no network): offline; 503; 404; malformed manifest; staged update; duplicate; wrong channel; native-required (runtime_compat mismatch); min-version; non-https; corrupt payload (hash mismatch); interrupted download; partial payload; failed activation (garbage pack with valid hash) -> rollback; unconfirmed activation -> rollback at next launch; old/equal OTA ignored; successful activation + promotion; repeat startup; modal state transitions; disabled build.
- Local end-to-end over real HTTP (headless, local server): launch 1 discovered and staged a payload; launch 2 applied it ("[boot] applying staged update ok=true", the changed game script ran), promoted it after confirmation; launch 3 mounted the known-good. Runtime pack mounting does not alter project settings.
- Not verified on a device: HTTPS to GitHub from Android, the visual modal, app-kill rollback on a phone.
