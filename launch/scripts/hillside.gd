extends RefCounted
## Procedural hillside city. Hierarchy: TERRAIN (terrain.gd) -> DISTRICTS (noise fields) -> STREETS (contour-following "traversing"
## streets + straight "climbing" streets) -> BLOCKS (the cells between them) -> LOTS (frontage rows along each street) -> BUILDINGS
## (box bodies on terraced pads, breakable) -> PROPS (street trees, hedges) -> LANDMARKS / TARGETS.
## Fully deterministic per preset seed (no randf): the same preset always loads the same city.
## Use with:  const Hillside := preload("res://scripts/hillside.gd")      (t is the Town being built)

const Rules := preload("res://scripts/rules.gd")
const Terrain := preload("res://scripts/terrain.gd")

const ROAD_W := 7.0
const WALK := 1.3
const FLOOR_H := 3.1
const LOT_MIN_X := 30.0          # nothing solid closer than this to the launcher: a fair opening corridor
const PALETTE: Array[Color] = [
	Color(0.93, 0.80, 0.45), Color(0.95, 0.72, 0.58), Color(0.62, 0.80, 0.72), Color(0.58, 0.72, 0.88), Color(0.80, 0.68, 0.86),
	Color(0.92, 0.62, 0.60), Color(0.96, 0.92, 0.80), Color(0.93, 0.66, 0.78), Color(0.86, 0.86, 0.80), Color(0.74, 0.84, 0.58),
	Color(0.88, 0.58, 0.30), Color(0.70, 0.74, 0.80)]
const ROOFS: Array[Color] = [Color(0.36, 0.33, 0.34), Color(0.52, 0.30, 0.24), Color(0.30, 0.34, 0.40), Color(0.60, 0.40, 0.28), Color(0.42, 0.42, 0.44)]

static var _win_tex: ImageTexture = null
static var seed_override: int = -1          # tests: build the preset with another seed (-1 = the preset's own)
static var dbg: Dictionary = {}
static func _d(k: String) -> void:
	dbg[k] = int(dbg.get(k, 0)) + 1
static var last_stats: Dictionary = {}      # tests / profiling: what the last build produced

class Ctx:
	var t
	var ter
	var preset: Dictionary
	var contours: Array = []          # Array of {h: float, xs: PackedFloat32Array} aligned to zs
	var zs := PackedFloat32Array()
	var climbs: Array = []            # z positions of climbing streets (base values)
	var reserved: Array = []          # Array of Rect2 (x, z extents) kept free of ordinary lots
	var mats: Dictionary = {}
	var n_lots: int = 0
	var n_trees: int = 0
	var grid: Dictionary = {}         # 16 m cell -> Array of lot indices (overlap rejection)
	var lots: Array = []              # {pos: Vector3, size: Vector3, yaw: float, kind: String, body: RigidBody3D}
	var tree_xf: Array = []
	var tree_col: Array = []

static func _hf(i: int, j: int, s: int) -> float:
	var n: int = ((i * 73856093) ^ (j * 19349663) ^ (s * 83492791)) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0

# --------------------------------------------------------------------------------------------- entry
static func build(t, id: String) -> void:
	var c := Ctx.new()
	c.t = t
	c.preset = Rules.hill_by_id(id).duplicate()
	if seed_override >= 0:
		c.preset["seed"] = seed_override
	c.ter = Terrain.new(c.preset)
	t.terrain = c.ter
	c.ter.urban = func(x: float, z: float) -> float: return _urban(c, x, z)
	_streets(c)
	t.add_child(c.ter.build_body(0.6, 0.4))
	_roads_mesh(c)
	_reserve_landmarks(c)
	_lots(c)
	_infill(c)
	_landmarks(c)
	_trees(c)
	_backdrop(c)
	last_stats = {"lots": c.lots, "contours": c.contours.size(), "climbs": c.climbs.size(), "trees": c.n_trees, "zs": c.zs, "contour_data": c.contours}

## Distant skyline: the neighbourhoods continue up the hills beyond the world edge (one MultiMesh, no collision).
static func _backdrop(c: Ctx) -> void:
	c.t.add_child(c.ter.build_backdrop())
	var seed: int = int(c.preset["seed"])
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	box.material = mat
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var x: float = Terrain.X1 + 6.0
	var ix: int = 0
	while x < 520.0:
		var z: float = -320.0
		var iz: int = 0
		while z < 320.0:
			var inside: bool = x < Terrain.X1 and absf(z) < Terrain.Z1
			var hv: float = _hf(ix, iz, seed + 71)
			var near_edge: float = float(maxi(x - Terrain.X1, maxf(absf(z) - Terrain.Z1, 0.0)))
			var dens: float = 0.78 - 0.55 * smoothstep(60.0, 330.0, near_edge)
			if not inside and hv < dens and _park_far(c, x, z) < 0.5:
				var w: float = 7.0 + 6.0 * _hf(ix + 3, iz, seed + 72)
				var d: float = 7.0 + 6.0 * _hf(ix, iz + 3, seed + 73)
				var h: float = 5.0 + 9.0 * _hf(ix + 1, iz + 1, seed + 74) + (14.0 if _hf(ix, iz, seed + 75) > 0.93 else 0.0)
				var px: float = x + 3.0 * _hf(ix, iz, seed + 76)
				var pz: float = z + 3.0 * _hf(ix, iz, seed + 77)
				var gy: float = c.ter.far_height(px, pz)
				xfs.append(Transform3D(Basis(Vector3.UP, _hf(ix, iz, seed + 78) * 0.5 - 0.25).scaled(Vector3(w, h + 2.0, d)), Vector3(px, gy + (h + 2.0) * 0.5 - 1.0, pz)))
				cols.append(PALETTE[int(_hf(ix, iz, seed + 79) * 12.0) % PALETTE.size()].lerp(Color(0.7, 0.72, 0.78), 0.35))
			iz += 1
			z += 15.0
		ix += 1
		x += 15.0
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "FarCity"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.t.add_child(mmi)

static func _park_far(c: Ctx, x: float, z: float) -> float:
	return smoothstep(0.62, 0.7, c.ter.fbm(x / 90.0, z / 90.0, 33))

## Highest point a legal launch can reach at distance x (m above the launcher plane): the governor's ballistic envelope, 90%.
static func envelope(x: float) -> float:
	var xs: Array[float] = [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0, 160.0, 180.0]
	var ys: Array[float] = [14.0, 26.6, 33.4, 36.8, 36.7, 33.1, 26.0, 15.8, 4.0]
	if x <= xs[0]:
		return ys[0] * 0.9
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1])) * 0.9
	return 0.0

# --------------------------------------------------------------------------------------------- districts
static func _urban(c: Ctx, x: float, z: float) -> float:
	if x < LOT_MIN_X - 6.0 or x > 202.0 or absf(z) > 122.0:
		return 0.0
	return 1.0 - _park(c, x, z)

static func _park(c: Ctx, x: float, z: float) -> float:
	var v: float = c.ter.fbm(x / 58.0, z / 58.0, 81)
	var thr: float = 1.0 - float(c.preset["park"]) * 1.6
	return smoothstep(thr - 0.04, thr + 0.04, v)

## 0 = low residential, 1 = downtown core. Centered on the preset's hub, modulated by noise.
static func _core(c: Ctx, x: float, z: float) -> float:
	var d: float = Vector2(x - float(c.preset["hub_x"]), (z - float(c.preset["hub_z"])) * 1.2).length()
	var near: float = 1.0 - smoothstep(18.0, 60.0 + 70.0 * float(c.preset["tall"]), d)
	return clampf(near + (c.ter.fbm(x / 40.0, z / 40.0, 5) - 0.5) * 0.4, 0.0, 1.0)

# --------------------------------------------------------------------------------------------- streets
static func _contour_x(ter, h: float, z: float) -> float:
	var xa: float = 24.0
	var prev: float = ter.height(xa, z)
	if prev >= h:
		return NAN
	var x: float = xa + 2.0
	while x <= 206.0:
		var cur: float = ter.height(x, z)
		if cur >= h:
			var lo: float = x - 2.0
			var hi: float = x
			for k in 8:
				var mid: float = (lo + hi) * 0.5
				if ter.height(mid, z) >= h:
					hi = mid
				else:
					lo = mid
			return (lo + hi) * 0.5
		x += 2.0
	return NAN

static func _streets(c: Ctx) -> void:
	var ter = c.ter
	var z: float = -124.0
	while z <= 124.0 + 0.1:
		c.zs.append(z)
		z += 4.0
	var hmax: float = 0.0
	for zq in range(-100, 101, 20):
		hmax = maxf(hmax, ter.height(185.0, float(zq)))
	var dh: float = float(c.preset["dh"])
	var h: float = dh * 0.6
	var k: int = 0
	while h < hmax * 0.97:
		var xs := PackedFloat32Array()
		var valid: int = 0
		for zz in c.zs:
			var x: float = _contour_x(ter, h, zz)
			xs.append(x)
			if not is_nan(x):
				valid += 1
		if valid > 12:
			# smooth (3-tap) so the street sweeps rather than jitters
			var sm := PackedFloat32Array()
			for i in xs.size():
				var a: float = xs[maxi(i - 1, 0)]
				var b: float = xs[i]
				var d2: float = xs[mini(i + 1, xs.size() - 1)]
				if is_nan(b):
					sm.append(NAN)
				else:
					sm.append((a if not is_nan(a) else b) * 0.25 + b * 0.5 + (d2 if not is_nan(d2) else b) * 0.25)
			c.contours.append({"h": h, "xs": sm})
		k += 1
		h += dh * (0.9 + 0.25 * _hf(k, 3, int(c.preset["seed"])))
	var zc: float = -118.0 + 6.0 * _hf(0, 1, int(c.preset["seed"]))
	var j: int = 0
	while zc < 124.0:
		c.climbs.append(zc)
		zc += 36.0 + 10.0 * _hf(j, 9, int(c.preset["seed"]))
		j += 1

static func _cx(cont: Dictionary, zs: PackedFloat32Array, z: float) -> float:
	var f: float = (z - zs[0]) / 4.0
	var i: int = clampi(int(floor(f)), 0, zs.size() - 2)
	var a: float = (cont["xs"] as PackedFloat32Array)[i]
	var b: float = (cont["xs"] as PackedFloat32Array)[i + 1]
	if is_nan(a) or is_nan(b):
		return NAN
	return lerpf(a, b, f - float(i))

static func _climb_z(c: Ctx, j: int, x: float) -> float:
	return float(c.climbs[j]) + 3.5 * sin(x / 31.0 + float(j) * 1.7)

# --------------------------------------------------------------------------------------------- roads (one mesh)
static func _strip(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, pts: Array, half: float, col: Color, lift: float, ter) -> void:
	# pts: Array of Vector2 (x, z). Builds a ribbon draped on the terrain.
	if pts.size() < 2:
		return
	var base: int = verts.size()
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var dir := q.normalized() if q.length() > 0.001 else Vector2(1, 0)
		var nrm := Vector2(-dir.y, dir.x) * half
		for sgn in [-1.0, 1.0]:
			var w: Vector2 = p + nrm * sgn
			verts.append(Vector3(w.x, ter.height(w.x, w.y) + lift, w.y))
			cols.append(col)
	for i in pts.size() - 1:
		var a: int = base + i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))

static func _roads_mesh(c: Ctx) -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var asphalt := Color(0.40, 0.40, 0.43)
	var walk := Color(0.72, 0.70, 0.64)
	# contour streets
	for cont in c.contours:
		var run: Array = []
		for i in c.zs.size():
			var x: float = (cont["xs"] as PackedFloat32Array)[i]
			if is_nan(x):
				if run.size() > 1:
					_strip(verts, cols, idx, run, ROAD_W * 0.5 + WALK, walk, 0.14, c.ter)
					_strip(verts, cols, idx, run, ROAD_W * 0.5, asphalt, 0.20, c.ter)
				run = []
			else:
				run.append(Vector2(x, c.zs[i]))
		if run.size() > 1:
			_strip(verts, cols, idx, run, ROAD_W * 0.5 + WALK, walk, 0.14, c.ter)
			_strip(verts, cols, idx, run, ROAD_W * 0.5, asphalt, 0.20, c.ter)
	# climbing streets
	for j in c.climbs.size():
		var run2: Array = []
		var x2: float = 26.0
		while x2 <= 204.0:
			run2.append(Vector2(x2, _climb_z(c, j, x2)))
			x2 += 4.0
		_strip(verts, cols, idx, run2, ROAD_W * 0.5 - 0.5 + WALK, walk, 0.15, c.ter)
		_strip(verts, cols, idx, run2, ROAD_W * 0.5 - 0.5, asphalt, 0.21, c.ter)
	if verts.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var nrms := PackedVector3Array()
	nrms.resize(verts.size())
	nrms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "Streets"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.t.add_child(mi)

# --------------------------------------------------------------------------------------------- materials / blocks
static func _wall_mat(c: Ctx, col: Color) -> StandardMaterial3D:
	var key: int = col.to_rgba32()
	if c.mats.has(key):
		return c.mats[key]
	if _win_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		for wx in [6, 20]:
			for wy in [7, 19]:
				for yy in range(wy, wy + 7):
					for xx in range(wx, wx + 6):
						img.set_pixel(xx, yy, Color(0.42, 0.50, 0.62, 1))
		_win_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = _win_tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.32, 0.32, 0.32)
	m.roughness = 0.95
	c.mats[key] = m
	return m

static func _flat_mat(c: Ctx, col: Color) -> StandardMaterial3D:
	var key: int = col.to_rgba32() ^ 0x5a5a5a
	if c.mats.has(key):
		return c.mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	c.mats[key] = m
	return m


# --------------------------------------------------------------------------------------------- Kenney modular building kit (CC0)
const KIT_DIR := "res://assets/kenney/modular-buildings/%s.glb"
const CELL_W := 4.96                  # world metres per kit cell (so one floor = 3.1 m: kit cube is 1 x 0.625 x 1)
const CELL_H := 0.625
static var _kit_meshes: Dictionary = {}
static var _unit_meshes: Dictionary = {}
static var _tex_b: Texture2D = null

static func _km(name: String) -> Mesh:
	if not _kit_meshes.has(name):
		var ps: PackedScene = load(KIT_DIR % name)
		var inst: Node = ps.instantiate()
		var m: Mesh = null
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			m = (n as MeshInstance3D).mesh
			break
		inst.free()
		_kit_meshes[name] = m
	return _kit_meshes[name]

static func _kit_mat(c: Ctx, tint: Color, variant: int) -> StandardMaterial3D:
	var key: int = tint.to_rgba32() ^ (variant * 0x3a3a3a)
	if c.mats.has(key):
		return c.mats[key]
	var base: StandardMaterial3D = _km("building-block").surface_get_material(0)
	var m: StandardMaterial3D = base.duplicate()
	m.albedo_color = tint
	if variant == 1:
		if _tex_b == null:
			_tex_b = load("res://assets/kenney/modular-buildings/Textures/variation-b.png")
		m.albedo_texture = _tex_b
	c.mats[key] = m
	return m

## Unit-space building mesh from kit cubes: nw x nd cells, `fv` floors, roof (0 gable, 1 flat, 2 none). Footprint centred on the origin,
## base at y = 0, one cell = 1 x 0.625 x 1 (the instance is scaled to the lot). Cached by shape.
static func _unit_mesh(nw: int, nd: int, fv: int, roof: int, vs: int) -> Mesh:
	var key: String = "%d_%d_%d_%d_%d" % [nw, nd, fv, roof, vs % 7]
	if _unit_meshes.has(key):
		return _unit_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var first: Mesh = _km("building-block")
	var upper: Array[String] = ["building-window", "building-windows", "building-windows-sills", "building-window", "building-windows", "building-window-balcony"]
	var ground: Array[String] = ["building-door-window", "building-door", "building-door-window", "building-window"]
	for f in fv:
		for i in nw:
			for k in nd:
				var cx: float = float(i) - float(nw - 1) * 0.5
				var cz: float = float(k) - float(nd - 1) * 0.5
				var faces: Array[float] = []
				if k == nd - 1:
					faces.append(0.0)                    # +Z (toward the street after the lot's yaw)
				if k == 0:
					faces.append(PI)
				if i == nw - 1:
					faces.append(PI * 0.5)
				if i == 0:
					faces.append(-PI * 0.5)
				var h: int = (i * 7 + k * 13 + f * 5 + vs * 3) % 9
				var rot: float = faces[0] if (f == 0 or faces.size() == 1) else faces[h % faces.size()]
				var nm: String
				if f == 0:
					nm = ground[(i + k + vs) % ground.size()] if (k == nd - 1 or faces.size() == 1) else "building-block"
				else:
					nm = upper[h % upper.size()]
					if nm == "building-window-balcony" and f < 1:
						nm = "building-window"
				st.append_from(_km(nm), 0, Transform3D(Basis(Vector3.UP, rot), Vector3(cx, float(f) * CELL_H, cz)))
	var ytop: float = float(fv) * CELL_H
	if roof == 0:
		var along_x: bool = nw >= nd
		for i in nw:
			for k in nd:
				var cx2: float = float(i) - float(nw - 1) * 0.5
				var cz2: float = float(k) - float(nd - 1) * 0.5
				st.append_from(_km("roof-gable"), 0, Transform3D(Basis(Vector3.UP, 0.0 if along_x else PI * 0.5), Vector3(cx2, ytop, cz2)))
	elif roof == 1:
		for i in nw:
			for k in nd:
				st.append_from(_km("roof-flat-top"), 0, Transform3D(Basis.IDENTITY, Vector3(float(i) - float(nw - 1) * 0.5, ytop, float(k) - float(nd - 1) * 0.5)))
	var m: ArrayMesh = st.commit()
	_unit_meshes[key] = m
	return m

## A breakable frozen block with a window-textured (or flat) look, rotated by yaw. Same bookkeeping as Town._block.
static func _hblock(c: Ctx, pos: Vector3, size: Vector3, yaw: float, col: Color, mat_name: String, group: String, mass: float, tough: float, windows: bool = true, group_all: bool = false, kit: Dictionary = {}) -> RigidBody3D:
	var t = c.t
	var b := RigidBody3D.new()
	b.name = "hb_%d" % t.pieces.size()
	b.position = pos
	b.rotation.y = yaw
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.physics_material_override = t._phys_stone
	b.can_sleep = true
	b.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * 0.98
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	if kit.is_empty():
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _wall_mat(c, col) if windows else _flat_mat(c, col)
		mi.mesh = bm
	else:
		mi.mesh = kit["mesh"]
		mi.material_override = kit["mat"]
		mi.scale = kit["scale"]
		mi.position = Vector3(0, -size.y * 0.5, 0)
	b.add_child(mi)
	b.set_meta("rest", b.position)
	b.set_meta("kind", "wall")
	b.set_meta("group", group)
	b.set_meta("tough", tough)
	b.set_meta("frozen_piece", true)
	b.set_meta("mat", mat_name)
	if group_all:
		b.set_meta("group_all", true)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	t.add_child(b)
	t.pieces.append(b)
	if not t.groups.has(group):
		t.groups[group] = []
	(t.groups[group] as Array).append(b)
	if bool(Rules.MATERIALS[mat_name]["fire"]):
		t.register_combustible(b)
	return b

static func rects_hit(ca: Vector2, ha: Vector2, ya: float, cb: Vector2, hb: Vector2, yb: float, margin: float = 0.0) -> bool:
	var xa := Vector2(cos(ya), -sin(ya))
	var za := Vector2(sin(ya), cos(ya))
	var xb := Vector2(cos(yb), -sin(yb))
	var zb := Vector2(sin(yb), cos(yb))
	var d: Vector2 = cb - ca
	for ax in [xa, za, xb, zb]:
		var ra: float = absf(ax.dot(xa)) * ha.x + absf(ax.dot(za)) * ha.y
		var rb: float = absf(ax.dot(xb)) * hb.x + absf(ax.dot(zb)) * hb.y
		if absf(ax.dot(d)) > ra + rb + margin:
			return false
	return true

static func _fits(c: Ctx, center: Vector2, w: float, d: float, yaw: float) -> bool:
	var r: float = maxf(w, d)
	for gx in range(int(floor((center.x - r) / 16.0)), int(floor((center.x + r) / 16.0)) + 1):
		for gz in range(int(floor((center.y - r) / 16.0)), int(floor((center.y + r) / 16.0)) + 1):
			for li in c.grid.get(Vector2i(gx, gz), []):
				var o: Dictionary = c.lots[li]
				if rects_hit(center, Vector2(w, d) * 0.5, yaw, Vector2(o["pos"].x, o["pos"].z), Vector2(o["size"].x, o["size"].z) * 0.5, float(o["yaw"]), 0.5):
					return false
	return true

## Pad height + fit for a footprint: returns {ok, lo, hi}. Rejects lots on unbuildable slopes.
static func _pad(c: Ctx, center: Vector2, w: float, d: float, yaw: float) -> Dictionary:
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	var lo: float = 1e9
	var hi: float = -1e9
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.0, 0.5]:
			var p: Vector2 = center + ax * (w * sx) + az * (d * sz)
			var hh: float = c.ter.height(p.x, p.y)
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
	return {"ok": hi - lo < 4.6, "lo": lo, "hi": hi}

static func _overlaps_reserved(c: Ctx, p: Vector2, r: float) -> bool:
	for rc in c.reserved:
		if (rc as Rect2).grow(r).has_point(p):
			return true
	return false

# --------------------------------------------------------------------------------------------- buildings
static func _building(c: Ctx, center: Vector2, w: float, d: float, yaw: float, floors: int, seedv: int, kind: String, tag: String = "", front_dir: Vector2 = Vector2.ZERO) -> RigidBody3D:
	var dir2: Vector2 = Vector2(sin(yaw), cos(yaw))        # (not used for placement; depth shrinks about the frontage edge below)
	var shrink: float = 1.0
	var ok_fit: bool = false
	var fd: float = d
	var fc: Vector2 = center
	for attempt in 3:
		if _fits(c, fc, w, fd, yaw):
			ok_fit = true
			break
		# retry shallower, keeping the street-side edge fixed (the centre moves toward the street)
		var nd: float = fd * 0.72
		if nd < 5.0:
			break
		fc = center + Vector2(-(front_dir.x), -(front_dir.y)) * (d - nd) * 0.5 if front_dir != Vector2.ZERO else center
		fd = nd
	if not ok_fit:
		_d("overlap")
		return null
	d = fd
	center = fc
	var pad: Dictionary = _pad(c, center, w, d, yaw)
	if not pad["ok"]:
		_d("steep")
		return null
	var lo: float = pad["lo"]
	var hi: float = pad["hi"]
	var body_h: float = float(floors) * FLOOR_H
	var col: Color = PALETTE[int(_hf(seedv, 5, 11) * float(PALETTE.size())) % PALETTE.size()]
	var timber: bool = kind == "house" or (kind == "row" and _hf(seedv, 7, 3) < 0.35)
	var mat: String = "wood" if timber else "masonry"
	var grp: String = "hb_%d" % c.n_lots
	c.n_lots += 1
	# the body reaches 0.5 m under the lowest ground of the footprint: it sits on the slope without a visible gap
	var bottom: float = lo - 0.5
	var floors_h: float = (hi + body_h) - bottom
	var nwc: int = clampi(int(round(w / CELL_W)), 1, 3)
	var ndc: int = clampi(int(round(d / CELL_W)), 1, 3)
	var fv: int = maxi(1, int(round(floors_h / FLOOR_H)))
	var sy: float = floors_h / (float(fv) * CELL_H)
	var roof_kind: int = 0 if (kind == "house" or kind == "row") else 1
	var roof_unit: float = 0.52 if roof_kind == 0 else 0.215
	var roof_h: float = roof_unit * sy
	var h_total: float = floors_h + roof_h
	var top: float = bottom + h_total
	# the street faces the model's +Z: flip the lot's yaw when its +Z points away from the frontage
	var fsgn: float = front_dir.x if front_dir != Vector2.ZERO else 1.0
	var fyaw: float = yaw + (PI if sin(yaw) * fsgn > 0.0 else 0.0)
	var vs: int = int(_hf(seedv, 3, 29) * 1000.0)
	var tint: Color = Color(minf(col.r / 0.72, 1.5), minf(col.g / 0.74, 1.5), minf(col.b / 0.92, 1.5)).lerp(Color(1, 1, 1), 0.2)   # the kit texture is blue-grey: divide it out so the lot's pastel shows
	var kmat: StandardMaterial3D = _kit_mat(c, tint, 1 if _hf(seedv, 11, 7) < 0.3 else 0)
	var segs: int = 1 if h_total <= 13.0 or fv < 4 else 2
	var first: RigidBody3D = null
	var y: float = bottom
	var f_done: int = 0
	var roof_body: RigidBody3D = null
	for sgi in segs:
		var f_seg: int = fv / segs if sgi < segs - 1 else fv - f_done
		var seg_floors_h: float = float(f_seg) * CELL_H * sy
		var is_top: bool = sgi == segs - 1
		var seg_h: float = seg_floors_h + (roof_h if is_top else 0.0)
		var um: Mesh = _unit_mesh(nwc, ndc, f_seg, roof_kind if is_top else 2, vs)
		var kit: Dictionary = {"mesh": um, "mat": kmat, "scale": Vector3(w / float(nwc), sy, d / float(ndc))}
		var pos := Vector3(center.x, y + seg_h * 0.5, center.y)
		var b: RigidBody3D = _hblock(c, pos, Vector3(w, seg_h, d), fyaw, col, mat, grp, 3.0 + seg_h * w * d * 0.012, 6.0 if mat == "masonry" else 4.2, true, false, kit)
		if first == null:
			first = b
		if is_top:
			roof_body = b
		y += seg_h
		f_done += f_seg
	var roof: RigidBody3D = roof_body
	var li: int = c.lots.size()
	c.lots.append({"pos": Vector3(center.x, top, center.y), "size": Vector3(w, h_total, d), "yaw": fyaw, "kind": kind, "body": roof, "tag": tag})
	var rr: float = maxf(w, d)
	for gx in range(int(floor((center.x - rr) / 16.0)), int(floor((center.x + rr) / 16.0)) + 1):
		for gz in range(int(floor((center.y - rr) / 16.0)), int(floor((center.y + rr) / 16.0)) + 1):
			var key := Vector2i(gx, gz)
			var arr: Array = c.grid.get(key, [])
			arr.append(li)
			c.grid[key] = arr
	return roof

static func _lots(c: Ctx) -> void:
	var seed: int = int(c.preset["seed"])
	var dens: float = float(c.preset["density"])
	var tall_share: float = float(c.preset["tall"])
	var nc: int = c.contours.size()
	for i in nc:
		var cont: Dictionary = c.contours[i]
		var nxt = c.contours[i + 1] if i + 1 < nc else null
		for j in range(c.climbs.size() - 1):
			var z_a: float = float(c.climbs[j]) + ROAD_W * 0.5 + 2.5
			var z_b: float = float(c.climbs[j + 1]) - ROAD_W * 0.5 - 2.5
			# lower frontage: buildings face the contour street and extend uphill; upper frontage faces the next street downhill
			for row in 2:
				var street: Dictionary = cont if row == 0 else (nxt if nxt != null else {})
				if street.is_empty():
					continue
				var zz: float = z_a
				var lot_i: int = 0
				while zz < z_b - 5.0:
					var hv: float = _hf(i * 131 + j * 17 + row * 7, lot_i, seed)
					var w: float = 5.5 + 3.5 * hv
					if zz + w > z_b:
						break
					var zc: float = zz + w * 0.5
					zz += w + 0.3 + 0.6 * _hf(lot_i, i, seed + 3)
					lot_i += 1
					var xc0: float = _cx(street, c.zs, zc)
					if is_nan(xc0):
						_d("nan0")
						continue
					var xc1: float = _cx(street, c.zs, zc + 3.0)
					var xc2: float = _cx(street, c.zs, zc - 3.0)
					if is_nan(xc1) or is_nan(xc2):
						_d("nan12")
						continue
					var dxdz: float = (xc1 - xc2) / 6.0
					var yaw: float = atan2(-1.0, dxdz)
					# available depth to the other street (or open slope)
					var other = (nxt if row == 0 else (c.contours[i - 1] if i > 0 else null))
					var gap: float = 40.0
					if other != null:
						var xo: float = _cx(other, c.zs, zc)
						if not is_nan(xo):
							gap = absf(xo - xc0)
					var depth_avail: float = gap - 2.0 * (ROAD_W * 0.5 + WALK + 0.9)
					if depth_avail < 5.0:
						_d("shallow")
						continue
					# the block's depth is shared by the two frontages (each gets half) so rows never run into each other
					var side_avail: float = depth_avail * (0.46 if other != null and depth_avail > 12.0 else 1.0) - 0.4
					var d: float = minf(8.0 + 4.0 * _hf(lot_i, j, seed + 9), maxf(side_avail, 5.0))
					var sgn: float = 1.0 if row == 0 else -1.0
					var xc: float = xc0 + sgn * (ROAD_W * 0.5 + WALK + 0.9 + d * 0.5)
					var ctr := Vector2(xc, zc)
					if xc < LOT_MIN_X or xc > 200.0 or absf(zc) > 120.0:
						_d("bounds")
						continue
					if _overlaps_reserved(c, ctr, w * 0.5):
						_d("reserved")
						continue
					var park: float = _park(c, xc, zc)
					if park > 0.5:
						_d("park")
						continue
					if hv > dens + 0.12:
						_d("dens")
						continue
					# district: floors / kind
					var core: float = _core(c, xc, zc)
					var kind: String = "house"
					var floors: int = 2 + int(_hf(lot_i, j + 3, seed + 5) * 2.0)
					var rr: float = _hf(i + 41, lot_i + j * 7, seed + 13)
					if core > 0.6 and rr < 0.06 + tall_share * 1.5:
						kind = "tower"
						floors = 5 + int(_hf(i, lot_i + j, seed + 21) * (4.0 + 10.0 * tall_share))
						w = maxf(w, 11.0 + 3.0 * hv)
						d = minf(maxf(d, 10.0), maxf(side_avail, 6.0))
					elif core > 0.25 and rr < 0.7:
						kind = "apt"
						floors = 3 + int(_hf(lot_i, i + j, seed + 8) * 3.0)
						w = maxf(w, 9.0 + 3.0 * hv)
					elif rr < 0.45:
						kind = "row"
						floors = 2 + int(_hf(lot_i, j, seed + 6) * 2.0)
					# keep roofs inside the reachable envelope
					var ground: float = c.ter.height(xc, zc)
					var allowed: float = envelope(Vector2(xc, zc).length()) - ground
					floors = mini(floors, maxi(2, int((allowed - 2.4) / FLOOR_H)))
					if allowed < 2.0 * FLOOR_H + 1.0:
						_d("high_ground")             # still built (reachable by skipping up the hill), just never taller than two floors
					_building(c, ctr, w, d, yaw, floors, int(hv * 997.0) + lot_i, kind, "%d_%d_%d_f" % [i, j, row], Vector2(sgn, 0.0))
					# back row: a smaller house/garage behind the front building when the block is deep enough
					var rem: float = side_avail - d - 2.5
					if rem >= 7.0 and kind != "tower" and _hf(lot_i, i + 5, seed + 61) < 0.8:
						var d2: float = minf(rem, 7.5 + 2.0 * hv)
						var ctr2 := Vector2(xc + sgn * (d * 0.5 + 2.0 + d2 * 0.5), zc)
						var w2: float = maxf(w - 1.5, 6.0)
						if not _overlaps_reserved(c, ctr2, w2 * 0.5) and _park(c, ctr2.x, ctr2.y) < 0.5:
							_building(c, ctr2, w2, d2, yaw, 2 if hv < 0.7 else 1, int(hv * 977.0) + lot_i + 500, "house", "%d_%d_%d_b" % [i, j, row], Vector2(sgn, 0.0))

## Fills the remaining free ground between the frontage rows with small houses / sheds so blocks read as built-up, not as isolated
## buildings: a fine scan, each candidate yawed along its own contour (perpendicular to the slope), rejected near roads and on overlap.
static func _infill(c: Ctx) -> void:
	var seed: int = int(c.preset["seed"])
	var dens: float = float(c.preset["density"])
	var ix: int = 0
	var x: float = LOT_MIN_X + 2.0
	while x < 198.0:
		var iz: int = 0
		var z: float = -116.0
		while z < 116.0:
			var hv: float = _hf(ix, iz, seed + 91)
			var jx: float = x + 3.0 * (_hf(ix, iz, seed + 92) - 0.5)
			var jz: float = z + 3.0 * (_hf(ix, iz, seed + 93) - 0.5)
			iz += 1
			z += 7.0
			if hv > dens * 0.9:
				continue
			if _park(c, jx, jz) > 0.5 or _near_street(c, jx, jz) or _overlaps_reserved(c, Vector2(jx, jz), 3.0):
				continue
			var gx: float = c.ter.height(jx + 1.0, jz) - c.ter.height(jx - 1.0, jz)
			var gz: float = c.ter.height(jx, jz + 1.0) - c.ter.height(jx, jz - 1.0)
			var yaw: float = 0.0
			if absf(gx) + absf(gz) > 0.05:
				var tg := Vector2(-gz, gx).normalized()
				yaw = atan2(-tg.y, tg.x)
			var w: float = 5.5 + 2.8 * _hf(ix, iz, seed + 94)
			var d: float = 5.5 + 3.0 * _hf(ix, iz, seed + 95)
			if _near_street_box(c, Vector2(jx, jz), maxf(w, d) * 0.62):
				continue
			var floors: int = 1 + int(_hf(ix, iz, seed + 96) * 2.0)
			_building(c, Vector2(jx, jz), w, d, yaw, floors, int(hv * 991.0) + ix * 7, "house", "infill")
		ix += 1
		x += 7.0

static func _near_street_box(c: Ctx, p: Vector2, r: float) -> bool:
	return _near_street(c, p.x, p.y, r)

# --------------------------------------------------------------------------------------------- landmarks + targets
static func _reserve_landmarks(c: Ctx) -> void:
	var p: Dictionary = c.preset
	c.reserved.append(Rect2(float(p["hub_x"]) - 13.0, float(p["hub_z"]) - 11.0, 26.0, 22.0))
	c.reserved.append(Rect2(float(p["tower_x"]) - 6.0, float(p["tower_z"]) - 6.0, 12.0, 12.0))
	c.reserved.append(Rect2(52.0, -9.0, 18.0, 18.0))     # first open plaza in the opening corridor: nothing else lands here
	var hilltop: Vector2 = _hilltop(c)
	c.reserved.append(Rect2(hilltop.x - 10.0, hilltop.y - 9.0, 20.0, 18.0))

static func _hilltop(c: Ctx) -> Vector2:
	var best := Vector2(110, 40)
	var bh: float = -1.0
	for xx in range(80, 124, 6):
		for zz in range(-70, 71, 8):
			if absf(float(zz) - float(c.preset["hub_z"])) < 28.0 and absf(float(xx) - float(c.preset["hub_x"])) < 28.0:
				continue
			var hh: float = c.ter.height(float(xx), float(zz)) - 0.05 * absf(float(zz))
			if c.ter.height(float(xx), float(zz)) + 13.0 > envelope(Vector2(float(xx), float(zz)).length()) / 0.9 - 2.0 or absf(float(zz)) > float(xx) * 0.7:
				continue                                     # the mansion roof must sit inside the reachable envelope
			if hh > bh:
				bh = hh
				best = Vector2(float(xx), float(zz))
	return best

static func _landmarks(c: Ctx) -> void:
	var t = c.t
	var p: Dictionary = c.preset
	var seed: int = int(p["seed"])
	# --- church with twin towers (the hub)
	var hx: float = float(p["hub_x"])
	var hz: float = float(p["hub_z"])
	var pad: Dictionary = _pad(c, Vector2(hx, hz), 22.0, 16.0, 0.0)
	var base_y: float = float(pad["lo"]) - 0.6
	var top_y: float = float(pad["hi"])
	var stone := Color(0.90, 0.84, 0.72)
	var nave_h: float = 10.0
	_hblock(c, Vector3(hx + 2.0, (base_y + top_y + nave_h) * 0.5, hz), Vector3(15.0, top_y + nave_h - base_y, 11.0), 0.0, stone, "masonry", "church", 14.0, 8.0, false)
	for tzs in [-1.0, 1.0]:
		_hblock(c, Vector3(hx - 6.0, (base_y + top_y + 13.0) * 0.5, hz + tzs * 3.4), Vector3(4.2, top_y + 13.0 - base_y, 4.2), 0.0, stone.darkened(0.04), "masonry", "church", 9.0, 7.0, false)
	var spire_a: RigidBody3D = _hblock(c, Vector3(hx - 6.0, top_y + 13.0 + 2.0, hz - 3.4), Vector3(2.4, 4.0, 2.4), 0.0, Color(0.45, 0.62, 0.55), "roof", "church", 3.0, 4.0, false)
	_hblock(c, Vector3(hx - 6.0, top_y + 13.0 + 2.0, hz + 3.4), Vector3(2.4, 4.0, 2.4), 0.0, Color(0.45, 0.62, 0.55), "roof", "church", 3.0, 4.0, false)
	t._bonus(spire_a, "hill_church", "Church Spire", 600)
	# --- radio tower on its own knoll: tapering lattice of breakable metal sections
	var tx: float = float(p["tower_x"])
	var tz: float = float(p["tower_z"])
	var tb: float = c.ter.height(tx, tz)
	var cur: float = tb - 0.4
	var sizes: Array[float] = [5.0, 3.8, 2.8, 1.8]
	var mid: RigidBody3D = null
	for k in sizes.size():
		var sh: float = 6.0
		var col: Color = Color(0.86, 0.18, 0.16) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
		var seg: RigidBody3D = _hblock(c, Vector3(tx, cur + sh * 0.5, tz), Vector3(sizes[k], sh, sizes[k]), 0.0, col, "metal", "radio", 6.0, 8.0, false, true)
		if k == 1:
			mid = seg
		cur += sh
	t._bonus(mid, "hill_radio", "Radio Tower", 900)
	# --- hilltop mansion on the best high ground
	var ht: Vector2 = _hilltop(c)
	var mp: Dictionary = _pad(c, ht, 16.0, 12.0, 0.0)
	var mb: float = float(mp["lo"]) - 0.5
	var m_top: float = float(mp["hi"]) + 6.0
	var mansion: RigidBody3D = _hblock(c, Vector3(ht.x, (mb + m_top) * 0.5, ht.y), Vector3(16.0, m_top - mb, 12.0), 0.0, Color(0.95, 0.90, 0.78), "masonry", "mansion", 10.0, 6.5)
	var mroof: RigidBody3D = _hblock(c, Vector3(ht.x, m_top + 1.0, ht.y), Vector3(17.0, 2.0, 13.0), 0.0, Color(0.70, 0.28, 0.22), "roof", "mansion", 4.0, 4.5, false)
	t._bonus(mroof, "hill_mansion", "Hilltop Mansion", 700)
	# --- corner store in the first plaza (the early target) with an awning
	var sx: float = 60.0
	var sg: float = c.ter.height(sx, 0.0)
	var store: RigidBody3D = _hblock(c, Vector3(sx, sg + 2.2, 0.0), Vector3(10.0, 5.2, 8.0), 0.0, Color(0.96, 0.78, 0.40), "wood", "store", 4.0, 4.0)
	_hblock(c, Vector3(sx - 5.7, sg + 3.2, 0.0), Vector3(2.6, 0.3, 8.0), 0.0, Color(0.85, 0.2, 0.2), "canvas", "store", 1.5, 3.0, false)
	t._bonus(store, "hill_store", "Corner Store", 150)
	# --- water tank on a rooftop (pick the tallest tower/apartment near the hub)
	var best = null
	for lt in c.lots:
		if str(lt["kind"]) in ["tower", "apt"] and Vector2(lt["pos"].x - hx, lt["pos"].z - hz).length() < 60.0:
			if float(lt["pos"].y) + 3.0 > envelope(Vector2(lt["pos"].x, lt["pos"].z).length()) / 0.9 * 0.97 or absf(lt["pos"].z) > lt["pos"].x * 0.7:
				continue
			if best == null or float(lt["pos"].y) > float(best["pos"].y):
				best = lt
	if best == null:
		best = {"pos": Vector3(hx + 2.0, top_y + nave_h, hz)}      # fallback: the church nave roof
	if best != null:
		var tp: Vector3 = best["pos"]
		var tank = t._prop_box(Vector3(tp.x, tp.y + 0.6, tp.z), Vector3(3.0, 3.4, 3.0), Color(0.55, 0.45, 0.36), "wood", 14.0)
		t._bonus(tank, "hill_tank", "Rooftop Tank", 400)
	# --- a big hospital block (wide cream slab)
	var hosp := Vector2(hx + 22.0, hz + (30.0 if hz < 0.0 else -30.0))
	var hp: Dictionary = _pad(c, hosp, 26.0, 14.0, 0.0)
	if hp["ok"] and not _overlaps_reserved(c, hosp, 12.0):
		var hb: float = float(hp["lo"]) - 0.5
		var h_top: float = float(hp["hi"]) + 14.0
		var hosp_b: RigidBody3D = _hblock(c, Vector3(hosp.x, (hb + h_top) * 0.5, hosp.y), Vector3(26.0, h_top - hb, 14.0), 0.0, Color(0.93, 0.93, 0.90), "masonry", "hospital", 16.0, 7.5)
		t._bonus(hosp_b, "hill_hospital", "Hospital", 450)

# --------------------------------------------------------------------------------------------- trees
static func _trees(c: Ctx) -> void:
	var seed: int = int(c.preset["seed"])
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.1
	cone.height = 6.0
	cone.radial_segments = 6
	cone.rings = 1
	cone.cap_bottom = false
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var trunk_n: int = 0
	var xx: float = 26.0
	var ix: int = 0
	while xx < 206.0:
		var zz: float = -126.0
		var iz: int = 0
		while zz < 126.0:
			var hv: float = _hf(ix, iz, seed + 31)
			var px: float = xx + _hf(ix, iz, seed + 41) * 5.0
			var pz: float = zz + _hf(ix, iz, seed + 43) * 5.0
			var park: float = _park(c, px, pz)
			var u: float = _urban(c, px, pz)
			var on_road: bool = _near_street(c, px, pz)
			var want: float = 0.18 if u > 0.5 else 0.55
			if park > 0.5:
				want = 0.8
			if c.ter.slope(px, pz) > 0.5:
				want = 0.7
			if hv < want and not on_road and not _overlaps_reserved(c, Vector2(px, pz), 2.0) and not _inside_lot(c, px, pz):
				var s: float = 0.8 + 0.7 * _hf(ix + 5, iz + 9, seed)
				var base: float = c.ter.height(px, pz)
				var xf := Transform3D(Basis().scaled(Vector3(s, s * (0.9 + 0.5 * hv), s)), Vector3(px, base + 3.0 * s, pz))
				xfs.append(xf)
				var g: float = _hf(ix + 3, iz + 7, seed + 55)
				cols.append(Color(0.20, 0.38, 0.22).lerp(Color(0.30, 0.46, 0.20), g))
				# collision trunks only along the central flight band, and bounded
				if trunk_n < 110 and absf(pz) < 62.0 and px < 190.0:
					var body := StaticBody3D.new()
					body.collision_layer = 1
					body.collision_mask = 0
					body.position = Vector3(px, base + 2.2 * s, pz)
					var cs := CollisionShape3D.new()
					var cyl := CylinderShape3D.new()
					cyl.radius = 0.9 * s
					cyl.height = 4.4 * s
					cs.shape = cyl
					body.add_child(cs)
					body.set_meta("mat", "wood")
					c.t.add_child(body)
					trunk_n += 1
			iz += 1
			zz += 6.5
		ix += 1
		xx += 6.5
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	cone.material = mat
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Trees"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.t.add_child(mmi)
	c.n_trees = xfs.size()

static func _near_street(c: Ctx, x: float, z: float, extra: float = 0.0) -> bool:
	for cont in c.contours:
		var xs: float = _cx(cont, c.zs, z)
		if not is_nan(xs) and absf(xs - x) < ROAD_W * 0.5 + WALK + 1.0 + extra:
			return true
	for j in c.climbs.size():
		if absf(_climb_z(c, j, x) - z) < ROAD_W * 0.5 + WALK + 0.5 + extra:
			return true
	return false

static func _inside_lot(c: Ctx, x: float, z: float) -> bool:
	for lt in c.lots:
		var sz: Vector3 = lt["size"]
		var d: Vector2 = Vector2(x - lt["pos"].x, z - lt["pos"].z)
		if absf(d.x) < sz.x * 0.5 + 2.5 and absf(d.y) < sz.z * 0.5 + 2.5:
			return true
	return false
