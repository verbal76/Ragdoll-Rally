extends RefCounted
## Procedural rising hillside terrain: an analytic height field (deterministic per preset seed), its colored mesh and its collision.
## The launcher stands on a flat pad at the origin; the land rises away from it (a loose amphitheater: a ramp along +X, a bowl toward
## the lateral edges, an optional central valley, and noise ridges/terraces). height()/normal() are the single source of truth: the
## mesh, the collision, the street layout and the building pads all sample them.
## Use with:  const Terrain := preload("res://scripts/terrain.gd")

const X0 := -25.0
const X1 := 215.0
const Z0 := -130.0
const Z1 := 130.0
const CELL := 2.5
const PAD_X := 16.0            # flat launch pad / approach runs to here, then the land starts to climb
const RAMP_X0 := 22.0

var p: Dictionary
var seed: int = 1
var nx: int
var nz: int
var urban: Callable             # optional (x, z) -> 0..1 urbanisation, set by the city generator (colors the ground)

func _init(preset: Dictionary) -> void:
	p = preset
	seed = int(preset["seed"])
	nx = int(round((X1 - X0) / CELL)) + 1
	nz = int(round((Z1 - Z0) / CELL)) + 1

# --------------------------------------------------------------------- noise
func _h(ix: int, iz: int, s: int) -> float:
	var n: int = (ix * 374761393 + iz * 668265263 + (seed + s) * 1442695041) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0

func vnoise(x: float, z: float, s: int = 0) -> float:
	var ix: int = int(floor(x))
	var iz: int = int(floor(z))
	var fx: float = x - float(ix)
	var fz: float = z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a: float = lerpf(_h(ix, iz, s), _h(ix + 1, iz, s), fx)
	var b: float = lerpf(_h(ix, iz + 1, s), _h(ix + 1, iz + 1, s), fx)
	return lerpf(a, b, fz)

func fbm(x: float, z: float, s: int = 0) -> float:
	return vnoise(x, z, s) * 0.62 + vnoise(x * 2.1, z * 2.1, s + 11) * 0.28 + vnoise(x * 4.3, z * 4.3, s + 23) * 0.10

# --------------------------------------------------------------------- height field
func height(x: float, z: float) -> float:
	var u: float = clampf((x - RAMP_X0) / (X1 - 40.0 - RAMP_X0), 0.0, 1.0)
	var ramp: float = float(p["rise"]) * pow(u, 1.2)
	var bowl: float = float(p["side"]) * pow(absf(z) / Z1, 2.0) * smoothstep(0.0, 0.5, u)
	var vw: float = float(p["valley_w"])
	var valley: float = -float(p["valley"]) * exp(-pow(z / vw, 2.0)) * smoothstep(0.0, 0.5, u)
	var relief: float = (fbm(x / 46.0, z / 46.0, 3) - 0.5) * 2.0 * float(p["ridge"]) * smoothstep(8.0, 70.0, x)
	var h: float = ramp + bowl + valley + relief
	h = maxf(h, 0.0)
	return h * smoothstep(PAD_X, PAD_X + 14.0, x) if x > PAD_X else 0.0

func normal(x: float, z: float) -> Vector3:
	var e: float = 1.0
	var dx: float = height(x + e, z) - height(x - e, z)
	var dz: float = height(x, z + e) - height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()

## Rise over run (0 = flat, 1 = 45 degrees).
func slope(x: float, z: float) -> float:
	var n: Vector3 = normal(x, z)
	return sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(n.y, 0.001)

# --------------------------------------------------------------------- mesh + collision
func ground_color(x: float, z: float, sl: float) -> Color:
	var n: float = fbm(x / 9.0, z / 9.0, 41)
	var grass := Color(0.48, 0.47, 0.26).lerp(Color(0.60, 0.55, 0.30), n)          # dry golden-green hillside
	var scrub := Color(0.30, 0.38, 0.20).lerp(Color(0.25, 0.33, 0.18), n)            # darker vegetation
	var dirt := Color(0.55, 0.46, 0.33)
	var c: Color = grass.lerp(scrub, smoothstep(0.35, 0.8, vnoise(x / 31.0, z / 31.0, 57)))
	c = c.lerp(dirt, smoothstep(0.32, 0.6, sl))
	var u: float = 0.0
	if urban.is_valid():
		u = float(urban.call(x, z))
	c = c.lerp(Color(0.55, 0.52, 0.40).lerp(Color(0.44, 0.46, 0.30), n), u * 0.55)   # yards / lots: muted, not a bright board
	return c

func build_mesh() -> ArrayMesh:
	var hg := PackedFloat32Array()
	hg.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			hg[iz * nx + ix] = height(X0 + float(ix) * CELL, Z0 + float(iz) * CELL)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x: float = X0 + float(ix) * CELL
			var z: float = Z0 + float(iz) * CELL
			var i: int = iz * nx + ix
			var hl: float = hg[iz * nx + maxi(ix - 1, 0)]
			var hr: float = hg[iz * nx + mini(ix + 1, nx - 1)]
			var hd: float = hg[maxi(iz - 1, 0) * nx + ix]
			var hu: float = hg[mini(iz + 1, nz - 1) * nx + ix]
			var nn := Vector3(-(hr - hl), 2.0 * CELL, -(hu - hd)).normalized()
			verts[i] = Vector3(x, hg[i], z)
			norms[i] = nn
			cols[i] = ground_color(x, z, sqrt(maxf(1.0 - nn.y * nn.y, 0.0)) / maxf(nn.y, 0.001))
	for iz in nz - 1:
		for ix in nx - 1:
			var a: int = iz * nx + ix
			idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	m.surface_set_material(0, mat)
	return m

## Static terrain body: visual mesh + trimesh collision (carries the meta main.gd expects of ground).
func build_body(ground_friction: float = 0.6, ground_bounce: float = 0.4) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.set_meta("ground", true)
	body.set_meta("terrain", true)
	body.set_meta("mat", "ground")
	body.collision_layer = 1
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = ground_friction
	pm.bounce = ground_bounce
	body.physics_material_override = pm
	var mesh: ArrayMesh = build_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	sh.backface_collision = true
	cs.shape = sh
	body.add_child(cs)
	return body

# --------------------------------------------------------------------- distant backdrop (visual only, no collision)
## Height continuing the playable terrain outward: the hills keep rising past the world edge so the city climbs into the sky.
func far_height(x: float, z: float) -> float:
	var ex: float = minf(x, X1 - 5.0)
	var ez: float = clampf(z, Z0, Z1)
	var base: float = height(ex, ez)
	var dx: float = maxf(x - (X1 - 5.0), 0.0)
	var dz: float = maxf(absf(z) - Z1, 0.0)
	var far: float = dx * 0.17 + dx * dx * 0.00035 + dz * 0.22 + dz * dz * 0.0004
	return base + far + (fbm(x / 80.0, z / 80.0, 9) - 0.5) * 16.0 * smoothstep(0.0, 70.0, dx + dz)

func build_backdrop() -> MeshInstance3D:
	var bx0: float = -140.0
	var bx1: float = 560.0
	var bz: float = 340.0
	var cs: float = 10.0
	var cx: int = int((bx1 - bx0) / cs) + 1
	var cz: int = int((bz * 2.0) / cs) + 1
	var hg := PackedFloat32Array()
	hg.resize(cx * cz)
	for iz in cz:
		for ix in cx:
			var x: float = bx0 + float(ix) * cs
			var z: float = -bz + float(iz) * cs
			hg[iz * cx + ix] = (far_height(x, z) if x > X0 else 0.0) - 0.7
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(cx * cz)
	norms.resize(cx * cz)
	cols.resize(cx * cz)
	for iz in cz:
		for ix in cx:
			var x: float = bx0 + float(ix) * cs
			var z: float = -bz + float(iz) * cs
			var i: int = iz * cx + ix
			var dxh: float = hg[iz * cx + mini(ix + 1, cx - 1)] - hg[iz * cx + maxi(ix - 1, 0)]
			var dzh: float = hg[mini(iz + 1, cz - 1) * cx + ix] - hg[maxi(iz - 1, 0) * cx + ix]
			verts[i] = Vector3(x, hg[i], z)
			norms[i] = Vector3(-dxh, 2.0 * cs, -dzh).normalized()
			var n: float = fbm(x / 40.0, z / 40.0, 13)
			cols[i] = Color(0.40, 0.42, 0.26).lerp(Color(0.52, 0.48, 0.30), n).lerp(Color(0.62, 0.62, 0.62), smoothstep(0.7, 1.0, fbm(x / 90.0, z / 90.0, 29)) * 0.5)
	for iz in cz - 1:
		for ix in cx - 1:
			var a: int = iz * cx + ix
			idx.append_array(PackedInt32Array([a, a + 1, a + cx, a + 1, a + cx + 1, a + cx]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "Backdrop"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
