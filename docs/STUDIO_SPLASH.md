# Hot Attic Games studio splash (Launch)

- Canonical asset: `branding/Hot_Attic_Games_Master_Logo.png` — **NOT PRESENT in this repository** (searched `*/branding`, `*hot*attic*`). It was not recreated or substituted. **CANONICAL HOT ATTIC GAMES ASSET MISSING.**
- Implementation (PREPARED, not visible yet): `scripts/boot.gd` is the main scene. Sequence: native boot (black background, Godot logo disabled via `boot_splash`) -> black screen + logo centered, aspect preserved (`STRETCH_KEEP_ASPECT_CENTERED`, no crop/distortion), 1.5 s, silent -> optional update-activation modal -> existing game. If the asset is missing the splash is skipped with a warning (no crash, no fake logo). Shown once per cold start (not on resume).
- To enable: add the canonical PNG at `launch/branding/Hot_Attic_Games_Master_Logo.png`. The Godot importer will import it; the code path is already in place.
- Classification: splash code and the asset are **NATIVE-BUILD REQUIRED** (`boot.gd`/`boot.tscn`/`project.godot` are boundary files; `branding/*` is excluded from OTA packs).
- Launcher icon: unchanged (the studio logo is not the launcher icon).
- OTA discovery starts after the game scene loads, so it never delays or depends on the splash.
- Verification: asset presence NO; cold-launch, offline, orientation and screen-size checks: physical-device test REQUIRED after the asset is added.
