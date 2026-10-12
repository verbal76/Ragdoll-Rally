Ragdoll Rally Launch - Steam Deck / Steam Machine

BUILDS
  Native Linux x86_64 (preferred on Deck): tools/build_linux.sh -> Ragdoll-Rally-Launch-Linux.tar.gz (one executable, PCK embedded).
  Windows x86_64 (runs through Proton): tools/build_windows.sh.
  Neither build contains Steamworks code yet (no steam_api, no Steam Input API calls); see "Not done" below.

HOW THE REQUIREMENTS ARE MET
  Controller support
    - Every action has gamepad bindings (aim, fire, spin, retry, launcher shop, upgrades, menu, select) and every screen (character / city
      select, HUD, results, launcher shop, upgrades, controls, graphics, quit) is reachable with D-pad + A. No in-game setting is needed:
      a connected controller is detected automatically and is the default input on SteamOS.
    - Default Steam Input template ("Gamepad") works as is: left stick aims, right trigger or A fires, right stick = elevation / move launcher,
      bumpers = spin and launcher switch, Y retry, X launcher shop, Back upgrades, Start menu, A selects in menus (remappable in CONTROLS).
  Glyphs
    - On SteamOS (SteamDeck / SteamOS environment or the Jupiter / Galileo board) the controller prompts are the default, and the trackpads /
      touch screen (which Steam Input turns into mouse clicks) never switch prompts to keyboard or mouse. Only a real key press does.
    - With a controller in use no hint, toast or controls-screen column shows mouse or keyboard wording; keyboard bindings are hidden behind a
      "Show keyboard bindings" button. Buttons are named A / B / X / Y / LB / RB / LT / RT / Start / Back (the Deck layout).
  Text input: the game has none.
  Performance (30 fps at 800p)
    - On SteamOS the first start picks the DECK preset: native 1280x800 fullscreen, 80% render scale, no MSAA, shadows off, "lite" comic ink
      (half the edge samples), 60 fps cap (V-Sync). If a flight runs under ~29 fps for 2 s the render scale steps down by 10% (floor 55%).
    - The player can change all of it in GRAPHICS (preset, render resolution, ink quality, MSAA, shadows, V-Sync, 30/40/45/60/90 fps caps).
  No compatibility warnings: the game never shows a hardware / distribution warning. No launcher.
  Resolution: 1280x800 and 1280x720 (16:9 and 16:10 both fit; the canvas stretches with the wider edge expanding).
  Text: the smallest UI text is 18 px at 1280x720 base (>= 12 px recommended, 9 px minimum).

STEAM INPUT
  Use the default "Gamepad" template for the Deck. Do not ship a keyboard-and-mouse default for the Deck.
  Optional: "Gamepad with Mouse Trackpad" is fine (trackpad = mouse, glyphs stay controller).

NOT DONE / NEEDS HARDWARE
  - Nothing here has been run on a real Steam Deck or Steam Machine: frame rate (30 fps at 800p) and the glyph behavior must be confirmed on
    hardware. The Deck APU numbers are estimates from presets, not measurements.
  - No Steamworks: add GodotSteam + steam_appid.txt to use the SteamInput API (it then supplies exact glyphs for Deck / Steam Controller / Xbox /
    PlayStation) and achievements / cloud saves. The text button names used now follow the Xbox layout the Deck presents.
