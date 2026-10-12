# Steam Deck / Steam Machine checklist (project-specific, standard section 12)

Legend: DONE = implemented and covered by an automated test; PENDING-HW = needs a physical device; PENDING-STEAM = needs Steamworks / account;
N/A = not applicable. Nothing below is claimed as Valve-Verified; no physical Deck/Steam Machine test has been run.

| Item | Status | Where / evidence |
|---|---|---|
| 12.1 controller covers launch, menus, settings, gameplay, pause, exit | DONE (tests) / PENDING-HW | verify_controls; docs/STEAMDECK.md |
| 12.1 no mandatory mouse/keyboard | DONE (design) / PENDING-HW | |
| 12.1 Steam Input template | PENDING-STEAM | default "Gamepad" assumed; no Steamworks yet |
| 12.2 automatic on-screen keyboard | N/A | the game has no text entry |
| 12.3 mixed input (mouse + stick) | PARTIAL | touch/trackpad never flips prompts on SteamOS; simultaneous camera input untested on HW (aim is not a free-look camera) |
| 12.4 camera sensitivity calibration | N/A | no free-look 3D camera; aiming is stick/mouse-to-angle, feel preserved |
| 12.5 1280x800, 16:10, 16:9 | DONE (config) / PENDING-HW | stretch expands the wider edge |
| 12.6 Vulkan | NOT USED | GL Compatibility renderer; Vulkan not claimed or tested; switching is RED |
| 12.7 codecs | N/A | no video; audio is procedural |
| 12.8 per-device graphics, Auto/Quality/Cool | DONE | graphics.cfg is local only; DECK preset auto, user can change everything |
| 12.9 offline single-player | DONE (design) / PENDING-HW | no network needed; desktop has OTA off; first-launch-offline on a new Steam account PENDING-STEAM |
| 12.10 no external launcher | DONE | direct launch |
| 12.11 performance (FPS, frame time, CPU/GPU, memory, load, battery) | PENDING-HW | no measurements exist |
| 12.12 cold/repeat launch, suspend/resume, controller reconnect, long play, clean exit | PENDING-HW | reconnect logic exists (Controls.pad_connected); unverified on device |
| 11 Steam Cloud | PENDING-STEAM | saves are user:// ConfigFiles; graphics kept separate for non-sync |
| 13 glyphs | PARTIAL | Xbox/PS/Switch art on the Controls screen + manual prompt style; hints/toasts and keyboard/mouse art still text |
| 10 SteamPipe | PENDING-STEAM | desktop builds ship OTA-disabled; Steam delivers updates |

Owner physical checklist (Deck): launch from Game Mode with controller only -> reach every screen -> fire a full level -> Controls screen shows A/B/X/Y art ->
suspend/resume mid-flight -> unplug/replug a controller -> note FPS (Steam performance overlay) in the default DECK preset -> exit cleanly.
