# Hot Attic Games studio splash (Ragdoll Rally Launch)

**Standing studio requirement:** every Hot Attic Games app/game opens with the Hot Attic Games studio card BEFORE the product's own title/menu/onboarding.
Canonical artwork: **`Hot_Attic_Games_Master_Logo_ALPHA_FINAL.png`** (owner-supplied, 1536 x 1024 RGBA with real transparency, SHA-256 `e3d9bb5653eafb783eede827606e7ac73a4e45564a1c25b1ed13ad1429f48c4e`).
The old name/path `Hot_Attic_Games_Master_Logo.png` is OBSOLETE. Never redraw, recreate, crop, stretch or substitute the artwork.

## Status: DONE (no blocker)
The earlier "logo missing" blocker is resolved. The artwork lives on `main` at the repository root and, unmodified, at
`launch/branding/Hot_Attic_Games_Master_Logo_ALPHA_FINAL.png` (the copy the game ships; a test pins its SHA-256).

## Cold-launch order
native splash (dark colour only, no image) -> **studio card** -> (apply a staged OTA behind "Please wait, applying update", if any) -> the game's own opening (character / city selector) -> normal game.

## Behaviour
- Implemented in the existing `launch/scripts/boot.gd` (the project's main scene). No second splash system.
- 0.45 s fade in, 1.5 s hold, 0.45 s fade out (~2.4 s). No text, buttons or effects on top.
- "Contain" layout: the whole artwork, original 3:2 aspect, never cropped or stretched, inside the safe area with 5 % padding. Transparency is preserved over a dark warm background (`BG_COLOR`, identical to `boot_splash/bg_color`, so there is no colour flash).
- Startup work runs behind the card: the OTA known-good payload is mounted first, and the game scene is loaded on a thread while the card shows (not when an OTA is about to be applied, because the payload replaces game scripts/scenes). Discovery of updates starts only after the game scene is running.
- Cold launch only: `boot.tscn` is the main scene, so resuming from the background never re-enters it.
- Cannot strand the user: a missing/unloadable artwork skips the card and goes straight to the game; if the threaded load is unavailable or slow (6 s cap) it falls back to a direct load; if the game scene itself cannot start, a plain message is shown instead of a blank screen.

## Classification
`boot.gd`, `boot.tscn` and `project.godot` are native-boundary files and `branding/*` is excluded from OTA packs, so the splash is **NATIVE-BUILD REQUIRED and NOT OTA-capable**. It ships with the next delivered native version.

## Tests
`launch/tests/verify_splash.gd` (CI step "Verify (Hot Attic Games studio splash ...)"): canonical filename and path, obsolete path gone, SHA-256 of the shipped file, size + alpha + transparent corners, aspect/no-crop fit on 7 screen shapes, order boot -> card -> game, 2-3 s duration, fade in/full/out, the card shows the canonical texture with contain layout inside the viewport, native-splash colour match and no second image, navigation into the game, selector follows, autoloads initialised, resume/background does not replay the card, missing artwork / no threaded load / broken game scene cannot strand the user.

## Launcher icon
Unchanged: the studio logo is not the launcher icon (`launch/branding/RR_Launch_*`).
