# "Please wait, applying update" + Settings -> About (Launch)

## Applying-update experience
- Implementation: `scripts/update_overlay.gd` (`UpdateOverlay`), driven by `scripts/boot.gd`.
- Exact message: **Please wait, applying update**.
- Trigger state: only when `Ota.boot_prepare()` returns `apply` (a verified staged payload exists) AND activation is about to run. Not shown for checking, background download, verification failure, or incompatible payloads.
- Styling: the game's own panel look (dark translucent rounded panel, white outlined text, same font/colors as the result panel); indeterminate spinner (no fake percentages).
- Blocking: full-screen input-blocking layer while shown; duplicate activation is refused by the client (`_applying` guard).
- Lifetime: bound to real activation (`applying_started` -> `applying_finished`), with 2 rendered frames before the blocking mount so it is actually visible; no fixed timer.
- Success: the overlay hides and the (updated) game scene loads. Failure: client rolls back, `applying_finished(false)` hides the overlay, the known-good/embedded game starts; the failure is recorded in About ("FAILED / ROLLED BACK" + reason).
- Tests: see `OTA_ARCHITECTURE.md` (state-machine tests; text equality; shown-exactly-during-activation; no permanent modal after failure). Physical verification of the visual: REQUIRED on device.

## Settings -> About
- Location: gear button (bottom-right, away from the drag area) -> SETTINGS -> About. Implementation: `scripts/settings_menu.gd` (OTA-safe UI).
- Fields: Application name; Device (platform, OS version/alias, model, locale, engine, renderer, captured-at); Install (package, versionName, versionCode, Godot + runtime_compat, source commit, build type/CI run/time); OTA (enabled, channel, running: embedded or OTA name/id/sequence/published/source SHA/SHA-256, update status CURRENT/CHECKING/DOWNLOADING/STAGED/APPLYING/FAILED-ROLLED BACK/DISABLED, last check, last result); Google Play/Android (target/min/compile SDK, required target API + verification date, Play API compliant YES/NO/UNVERIFIED, signing state).
- Copy Diagnostics: copies the same plain text to the clipboard (no secrets, no save data). Example (dev run):
```
HOT ATTIC GAMES — DIAGNOSTICS
APPLICATION
  Name: Ragdoll Rally Launch
DEVICE
  Platform: Linux
  ...
INSTALL
  Package: com.hotatticgames.ragdollrally.launch
  Version: dev
  Version code (native build): 0
  Native/runtime: Godot 4.4.1.stable.official ; runtime-compat dev
OTA
  Updates enabled: no
  Running: EMBEDDED NATIVE BASELINE (no OTA applied)
GOOGLE PLAY / ANDROID
  Target SDK: unknown ... Play API compliant: UNVERIFIED
```
- Values needing a native build: package, versionCode, target/min SDK, source SHA and channel come from `build_info.json` written by CI into the APK, so they are only real in CI builds (dev runs show "dev"/"unknown"). Android API level is shown through Godot's OS version alias where the engine provides it.
- Physical verification: REQUIRED on device.
