# Launch native generation G2: Godot 4.4.1 -> 4.7.1, API 36

Branch `claude/launch-api36-modernization` (from `e2c16e4`). Rollback/reference points kept untouched: tags `launch-poc-b2` (physics reference), `launch-poc-b6` (infra reference), branch `ccr-7c0d7291-e3d5o1`, and their release assets.

## Engine choice (from Godot engine source at each release tag, `platform/android/java/app/config.gradle`)
| Godot | compileSdk | targetSdk (default) | minSdk | AGP | build-tools | NDK | Kotlin |
|---|---|---|---|---|---|---|---|
| 4.4.1 (G1) | 34 | 34 | 21 | 8.2.0 | 34.0.0 | 23.2 | 1.9.20 |
| 4.5.2 | 35 | 35 | 24 | 8.6.1 | 35.0.1 | 28.1 | 2.1.20 |
| 4.6.2 | 35 | 35 | 24 | 8.6.1 | 35.0.1 | 28.1 | 2.1.20 |
| **4.7.1 (chosen)** | **36** | **36** | 24 | 8.6.1 | 36.1.0 | **29.0** | 2.1.21 |
Only 4.7.x targets API 36 by default. 4.7.1 is the newest stable at execution time (4.8 does not exist; Godot 4.5/4.6 stop at API 35). JDK 17, Gradle 8.11.1 (wrapper in the template). NDK r28+ builds are 16 KB-aligned. Not evaluated: Godot support-window policy (the docs host was unreachable); 4.7.1 is simply the latest stable.
Consequences: minSdk rises 21 -> 24 (engine floor), APK grows 28 MB -> 81 MB because native libs are stored uncompressed (`compress_native_libraries=false`) so they can be 16 KB-aligned/mmapped.

## Migration changes
- GDScript source: **no code changes required** (both test suites pass unmodified on 4.7.1). `project.godot` features 4.4 -> 4.7.
- Android route: prebuilt template -> **Gradle build** (`gradle_build/use_gradle_build=true`, template installed in CI from `android_source.zip`, APK export; AAB is now possible by setting `export_format=1` but was not built). `screen/edge_to_edge=true` (API 36 enforces edge-to-edge anyway).
- Runtime compat: `ota_tools.py` ENGINE `godot-4.7.1`, prefix `r2-`: fingerprint of the shipped build `r2-e691ce8f7ee3`. A G1 PCK (`r1-...`) is refused by G2 and vice versa. G2 follows its own OTA channel **`poc-g2`** (manifest `launch-ota-channel-poc-g2`); nothing was published to any channel, and no installed G1 device can receive anything from this round.
- Identity: same package `com.hotatticgames.ragdollrally.launch`, same debug keystore (cert SHA-256 `32a3988d...3dc15b`, verified), versionCode 7 (> b6's 6) => installs over b2/b6 as an update.
- About now also shows "native generation".

## Physics preservation (record, then compare)
Reference: `docs/physics/baseline_godot_4.4.1.json` (deterministic on 4.4.1: two runs identical). New: `docs/physics/migrated_godot_4.7.1_local.json`. `launch/tools/physics_compare.py` runs in CI.
- All 67 registered `physics/*` project settings are identical except two engine-side items: `physics/3d/physics_interpolation/scene_traversal` (new in 4.7, DEFAULT) and `physics/jolt_physics_3d/simulation/areas_detect_static_bodies` (removed from 4.7; the project has no Area3D). Nothing in `project.godot` needed pinning. Gravity 9.8, Jolt, 60 Hz unchanged; launch constants (MIN 9.0, MAX 32.0) identical.
- Six seeded shots: launch speeds identical to 0.01 (25.67, 23.53, 32.04, 27.73, 27.89, 20.49 m/s); destruction identical (19/8/0/0/0/13 pieces); joint stretch 0.60-0.71 m vs 0.60-0.70 m (stable, no explosions); all settle (211-425 frames vs 211-391). End positions drift by up to ~4 m laterally (chaotic outcomes differ because Jolt changed between versions), e.g. shot 0: (31.6, 2.9) -> (31.1, -0.9); shot 4: z 24.4 -> 20.2. Scores differ by < 7%.
- **Verdict: invariants preserved; exact trajectories are NOT identical.** The "feel" can only be judged by the owner against b2/b6. No retuning was done.

## Artifact verification (APK `ragdoll-rally-launch-g2-api36-5f6a122-b7.apk`)
Package `com.hotatticgames.ragdollrally.launch`, versionName `0.2.0-poc-api36`, versionCode 7, minSdk 24, targetSdk 36, compileSdk 36 (from build_info in the APK), ABI arm64-v8a only, permissions: INTERNET only. Native libs (2): `libgodot_android.so` (76,177,376 B) and `libc++_shared.so` (1,374,336 B), all PT_LOAD p_align = 16384, stored uncompressed, zip data offsets 16 KB-aligned, `zipalign -c -P 16` OK, APK signature verifies, certificate matches the b2 lineage. Size 81,296,983 B, SHA-256 `3e6d17fb71819c750ea24d5d73cdbc0fb1ec77b13d182feb345d0e268809361d`. The same check on b2 (Godot 4.4.1) shows 4096 alignment and misaligned/compressed libs: b2/b6 are NOT 16 KB compatible.
