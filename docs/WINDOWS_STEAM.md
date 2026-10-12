Ragdoll Rally Launch v18 - Windows (x86_64)

Run Ragdoll-Rally-Launch.exe (single file). Windows 10/11, OpenGL 3.3 capable GPU.

CONTROLS (all remappable: Esc / Start -> CONTROLS, or the CONTROLS button top-left)
  Mouse: hold left button and drag back to aim, release to fire (same as touch).
  Keyboard: W/S = pull more/less, A/D = aim, Space/Enter = fire, Shift = fine aim, R = retry, Q/E = previous/next launcher,
            L = launcher shop, U = upgrades, F2 = comic-ink look, F11 = fullscreen, Esc = menu.
  In flight: A/D (or arrows) spin / flip.
  Gamepad (Xbox / PlayStation / Switch / generic, auto-detected, hot-plug): left stick or D-pad = aim, right trigger = fire (and A in the game view), A = SELECT in menus (remappable),
            left trigger = fine aim, bumpers = spin in flight and launcher switching, Y = retry, X = launcher shop,
            Back = upgrades, Start = menu.
  Every action has 2 keyboard/mouse and 2 gamepad slots. Click a slot and press the new key / mouse button / pad button /
  stick direction; right-click clears; Reset to defaults available. Sensitivity, dead zone and Invert Y are in the same screen.
  Settings are stored in %APPDATA%\Godot\app_userdata\RR Launch\controls.cfg.

STEAM (not wired yet)
  The build has no Steamworks code. For the store: add GodotSteam (GDExtension) + steam_appid.txt, Steam Input action manifest
  (the action ids in scripts/controls.gd map 1:1), achievements/cloud saves (user://), store capsule art, and sign the exe.
  The OTA updater is disabled on desktop: Steam delivers updates.
