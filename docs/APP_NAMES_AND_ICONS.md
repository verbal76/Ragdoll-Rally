# App names and icons

Two separate apps. User-facing names are only **RR Launch** and **RR Legacy**.

| App | Name on phone | Package | Icon files | Status |
|---|---|---|---|---|
| RR Launch | RR Launch | com.hotatticgames.ragdollrally.launch | `launch/branding/RR_Launch_*` (wired into the Android export) | Builds from `launch/` |
| RR Legacy | RR Legacy | (own package, to be set when built) | `legacy/branding/RR_Legacy_*` | NOT BUILT: the original game's source is not in this repository |

Masters (full-size, from the owner): `branding/RR_Launch_Icon.png`, `branding/RR_Legacy_Icon.png`.
Per-app derived sizes: main 192x192, adaptive foreground/background 432x432, 512x512.

Releases are named `RR Launch (build N)`, tag `rr-launch-bN`, file `RR-Launch-bN-<commit>.apk`.
