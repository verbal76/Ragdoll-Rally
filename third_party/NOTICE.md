# Third-party assets used by Ragdoll Rally Launch

## Kenney Splat Pack 1.0 (blood / surface splats)
- Source: Kenney (www.kenney.nl), creation date 16-03-2022. License: **Creative Commons Zero (CC0 1.0)** - see `kenney_splatpack/License.txt` (copied verbatim from the supplied archive).
- Used as: `launch/assets/fx/splat_atlas.png` - the 36 supplied splat shapes (256 px originals, downsampled to 128 px cells, no other change; the artwork is white, it is tinted red at runtime).
- Credit is not required by the license; given anyway: "Splat Pack by Kenney (www.kenney.nl)".

## 3D Fire and Smoke v1.0 (stylized Godot fire and smoke)
- Supplied archive: `3dFireSmoke_v1.0.zip` (Godot 4.4, GL Compatibility project). Its only documentation is `3dFireSmoke_v1.0/README.md` ("stylized 3d fire and smoke for Godot"), preserved verbatim in `3dFireSmoke_v1.0/README.md`.
- **License status: the supplied archive contains NO license file.** The owner stated that the source page lists an MIT code license; that statement could not be verified from the archive itself. Before any public/store distribution, confirm the license on the source page and add the license text + copyright holder here. The shaders also embed Ashima Arts / Ian McEwan 3D simplex noise (`snoise`, MIT-licensed upstream, copyright Ashima Arts and Stefan Gustavson).
- Original shaders and scenes are kept untouched in `third_party/3dFireSmoke_v1.0/`.
- Adapted (not copied) for this project in `launch/assets/fx/toon_fire.gdshader`, `toon_smoke.gdshader`, `toon_smoke_outline.gdshader`: the fire keeps the original flame-shaping vertex stage and posterised noise look with one simplex octave instead of two; the smoke drops the screen-texture read, the per-vertex Voronoi displacement and the 100x64-segment spheres (the demo used 252 particles x ~12k triangles with a second outline pass) in favour of low-poly puffs with a cheap wobble, a two-band toon shade and the same outline idea.
