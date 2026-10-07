# v14 candidate evidence (local renders under xvfb/software GL, headless physics profile)

| file | what it shows |
|---|---|
| `hill_*_launch.jpg` | from the launcher: the rising hillside city ahead (4 presets: steep, valley, rolling, skyline) |
| `hill_*_mid.jpg` | low-altitude traversal view: contour streets, blocks, landmarks (church, radio tower, mansion, store) |
| `hill_*_high.jpg` | high view: neighbourhood organisation, parks, street network |
| `run_hill_steep_00_aim.jpg` | the game's own aim camera at the launcher (hillside rising ahead) |
| `run_hill_steep_03/06/10_run.jpg` | a real throw: flight into the city, wall blood splats, fire, combo scoring, target hit |
| `fx_blood_fire_smoke.jpg` | red Kenney splats on the ground and a wall, toon flames, toon smoke puffs |
| `trajectory_profile.png` | old (dashed) vs new (solid) launch arcs over each preset's terrain profile along the launch lane |

Profile (tests/profile_v14.gd, headless desktop; 2 destructive throws per map with max ignition/explosive/destruction, Big Red):
physics step avg / p95 ms: Grand Fortress (old flat city) 3.74 / 6.15, hill_steep 2.13 / 4.16, hill_valley 1.81 / 3.92, hill_rolling 2.35 / 4.37, hill_skyline 2.96 / 4.55.
Map load (generate + build): Grand Fortress 417 ms, hills 600-790 ms. One-off first-step broadphase stall: Grand Fortress 434 ms, hills 645-735 ms.
Render (software GL, view dependent, not frame times): hill_steep launch view 226 draw calls / 101k primitives / 366 objects; valley 218 / 98k / 358; rolling 162 / 82k / 302; skyline 225 / 101k / 365.
