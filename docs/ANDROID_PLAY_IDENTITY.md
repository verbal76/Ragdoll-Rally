# Android / Google Play identity and readiness (Ragdoll Rally)

Scope: **Launch** (Godot, `launch/`) is the only app that exists in this repository today. **Original** (Matter.js/Capacitor) has not been built; everything below marked "Original" is N/A until it exists.
Status labels: CONFIRMED (read from repo or the built APK) / OWNER (owner confirmation or Play Console action required).

## Identity (Launch) — CONFIRMED
| Item | Value | Source |
|---|---|---|
| App name | Ragdoll Rally Launch | export preset / APK label |
| Package ID | `com.hotatticgames.ragdollrally.launch` (preserved; a POC test identity, not a decided Play identity) | APK |
| versionName | b2: `0.1.0-poc`; infra build: `0.1.1-poc-infra` | APK / CI |
| versionCode | b2: 2; later builds = GitHub run number (monotonic per workflow) | APK / CI |
| minSdk | 21 | b2 APK badging |
| targetSdk | **34** (baked into the Godot 4.4.1 prebuilt export template) | b2 APK badging |
| compileSdk | n/a (prebuilt template; no Gradle build) | export preset |
| ABIs | arm64-v8a only | preset |
| Permissions | b2: none. Infra build adds `INTERNET` (OTA client) | APK / preset |
| Signing | DEBUG, committed throwaway keystore `launch/debug.keystore` (cert SHA-256 32:A3:98:8D:...:C1:5B). Not an upload key, not Play-ready | APK |
| Build route | GitHub Actions, Godot 4.4.1 headless, prebuilt template, APK only | `.github/workflows/android.yml` |
| AAB | **Not possible with the current route** (Godot AAB needs the Gradle build template). Not built | — |

## Google Play target-API requirement — VERIFIED 2026-10-03
developer.android.com/google/play/requirements/target-sdk (page "last updated 2026-10-01"): from **31 Aug 2026** new apps and updates must target **Android 16 / API 36** (extension request to 1 Nov 2026 available in Play Console). Existing apps stay available to new users only if they target >= API 35.

**PLAY API COMPLIANT: NO** (targetSdk 34 < 36).

## STOP GATE — Class B decision report (no migration was performed)
- Current stack: Godot 4.4.1, prebuilt Android export template, non-Gradle export. Current API 34. Required API 36.
- Exact reason it cannot comply: the prebuilt template's manifest fixes targetSdk at 34. API 36 needs an engine/export-template that supports it. A web search (Godot docs host was blocked from this environment, so this is **not verified against primary Godot docs**) indicates API 36 support arrives with Godot 4.5+ and is the default in 4.7. AAB output additionally requires switching to Godot's Gradle build route (build template, AGP/Gradle/JDK, SDK/NDK setup).
- Classification: **CLASS B**. It means an engine-version upgrade (4.4.1 to 4.5+/4.7) plus a build-route change. The engine upgrade can change Jolt/ragdoll behavior, rendering and Android lifecycle behavior; physics feel is the very thing these POCs are testing, and the owner has already physically played b2.
- Minimum migration: upgrade Godot (export templates, CI download URLs), re-import assets, regression-test physics/ragdoll against b2 numbers, then set target 36 and move to the Gradle build route for AAB. Likely files: `project.godot`, `export_presets.cfg`, both workflows, `launch/tools/ota_tools.py` (`ENGINE`), possibly `ragdoll.gd`/`town.gd` joint and collision tuning.
- OTA consequences: a new engine version is a new native runtime, so a new `runtime_compat`; old installs will correctly refuse OTAs built for it.
- Save/data consequences: only the local best score (`user://launch.cfg`); low risk.
- Risks: ragdoll joint/solver behavior drift; Android 15/16 edge-to-edge/back-gesture behavior; first Gradle-route build failures (no log access to CI beyond the API).
- Recommendation: do NOT migrate during the head-to-head playtest. If Launch wins, upgrade Godot in a dedicated branch before any Play work; if Original (Capacitor) wins, re-audit its own Capacitor/AGP target.
- OWNER DECISION REQUIRED before any of the above.

## Play Console inventory (Launch) — nothing is fabricated
| Item | Status |
|---|---|
| Category | OWNER (game/arcade, not decided) |
| Ads / IAP / accounts / login | CONFIRMED none |
| Internet required | CONFIRMED no for gameplay; infra build declares INTERNET for the OTA check only |
| User data collected / shared | CONFIRMED none collected or transmitted by the app; the OTA check requests a public GitHub release URL (the host sees the device IP/User-Agent as for any download) |
| Analytics / crash reporting / third-party SDKs | CONFIRMED none |
| Camera / mic / location / storage / notifications | CONFIRMED not used |
| Local data | CONFIRMED best score (`user://launch.cfg`) and OTA state (`user://ota/`) |
| AI/ML | CONFIRMED none |
| Privacy policy | NONE exists (OWNER: needed for Play; the OTA/INTERNET declaration should be described) |
| Data Safety form | OWNER: can be answered "no data collected" per the above, owner must confirm |
| Content rating | OWNER: cartoon slapstick ragdoll physics, no blood/gore by design |
| Store assets (icon, feature graphic, screenshots) | OWNER: default Godot icon only |
| Third-party licenses | Kenney Blocky Characters 2.0 and Retro Fantasy Kit 2.0, CC0 (see `launch/ASSETS_LICENSES.md`) |
| Upload key / Play App Signing | OWNER: none exists |
| Internal testing readiness | **NOT READY**: needs API 36 (Class B), AAB route, upload key, privacy policy, store assets |

## Original
N/A: not built. When it is, its package ID will be `com.hotatticgames.ragdollrally.original` and it needs its own audit (Capacitor/AGP/Gradle/JDK vs API 36).
