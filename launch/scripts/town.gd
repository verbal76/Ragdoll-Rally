class_name Town
extends Node3D
## The single playground: launcher + a few structures made of Kenney Retro
## Fantasy Kit pieces. Pieces start frozen (static) and switch to physics when
## struck hard enough (cheap "destruction"). Props are ordinary rigid bodies.

const Rules := preload("res://scripts/rules.gd")
const Cities := preload("res://scripts/cities.gd")
const Hillside := preload("res://scripts/hillside.gd")
const Destruction := preload("res://scripts/destruction.gd")
const Outskirts := preload("res://scripts/outskirts.gd")

signal piece_released(piece: RigidBody3D)
signal ignited(node: Node3D, pos: Vector3)
signal burned(node: Node3D, pos: Vector3)

const KIT := "res://assets/kenney/retro-fantasy-kit/%s.glb"
const S := 1.5          # kit unit -> metres
const PROP_S := 2.5     # detail props are tiny in the kit
const POLE_TOP := Vector3(0.0, 3.4, 0.0)
const POLE_Z := 1.7
const WORLD_X_MIN := -25.0
const WORLD_X_MAX := 330.0     # 215 in v14; deep districts and Lv20 flights reach out to here
const WORLD_Z := 130.0
const ACTIVE_CAP := 100         # settled released pieces beyond this are re-frozen (aftermath stays visible)
const ACTIVE_HARD := 125        # never more than this many simulated pieces: extra broken pieces dissolve into particle debris
var _hctx = null                             # Hillside.Ctx shared by shell_box (materials cache)
var shells_open: Array[RigidBody3D] = []   # expanded shells (Destruction.expand), restored on reset

var pieces: Array[RigidBody3D] = []
var props: Array[RigidBody3D] = []
var groups: Dictionary = {}
var used_assets: Array[String] = []
var _phys_stone := PhysicsMaterial.new()
var band_l: MeshInstance3D
var band_r: MeshInstance3D
var targets: Array[Dictionary] = []     # {key, name, pts, pos, region}
var released_order: Array[RigidBody3D] = []
var legacy: bool = false                # tests: original small village only (also the classic G1/G2 materials)
var _beams: Dictionary = {}             # target key -> [beam, label]
var tnt: Array[RigidBody3D] = []
var rings: Array[Dictionary] = []       # landing rings {key, name, center: Vector2, r, base}
var gaps: Array[Dictionary] = []        # thread-the-gap targets {key, name, pts, x, half, ymax}
var _reserved: Array[Rect2] = []        # keep-out zones for the decorative city
var _decor_walls: Array[Transform3D] = []
var _decor_roofs: Array[Transform3D] = []
var _decor_trees: Array[Transform3D] = []
var _occupied: Array[Vector2] = []
var static_pos: Array[Vector3] = []     # immovable kit pieces (castle walls, gates...), for density checks
var _cap_timer: float = 0.0
# --- fire (combustible registry; the spread maths lives in Rules.fire_step)
var fx: Node = null                       # effects pool (set by main)
var fire_nodes: Array[Node3D] = []
var fire_pos: Array = []
var fire_state := PackedInt32Array()
var fire_timer := PackedFloat32Array()
var fire_handle: Array[int] = []
var _fire_grid: Dictionary = {}
var _fire_idx: Dictionary = {}
var fire_spread_mult: float = 1.0
var _fire_acc: float = 0.0
var burning_count: int = 0
var _burnt_static: Array[Node3D] = []
# --- breakable glass + yard bits
var glass: Array[StaticBody3D] = []
var _broken_glass: Array[StaticBody3D] = []
var env_id: String = "city"
var terrain = null                      # terrain.gd instance on the hillside cities (null = flat world at y = 0)
var ground_color: Color = Color(0.40, 0.66, 0.34)
var road_color: Color = Color(0.62, 0.58, 0.5)
var _mat_cache: Dictionary = {}
var _glass_xfs: Array[Transform3D] = []
var _glass_mm: MultiMeshInstance3D
var boundary_bodies: Array[StaticBody3D] = []
var smash_push: float = 0.45            # debris launch factor (0.8 in the mayhem tuning)

func build(p_legacy: bool = false, p_env: String = "city") -> void:
	legacy = p_legacy
	env_id = p_env
	smash_push = 0.45 if legacy else 0.8
	_phys_stone.friction = 0.8 if legacy else 0.6
	_phys_stone.bounce = 0.12 if legacy else 0.4
	if not legacy:
		var th: Dictionary = Rules.env_by_id(env_id)["theme"]
		ground_color = th["ground"]
		road_color = th.get("road", road_color)
	if not (not legacy and Rules.is_hill(env_id)):
		_ground()
	_launcher()
	if not legacy and Rules.is_hill(env_id):
		smash_push = 0.9
		Hillside.build(self, env_id)
		Outskirts.build(self, env_id)
		_perimeter()
		return
	if env_id == "yard" and not legacy:
		build_yard()
		Outskirts.build(self, env_id)
		_perimeter()
		return
	if not legacy and Cities.IDS.has(env_id):
		smash_push = 0.9
		Cities.build(self, env_id)
		Outskirts.build(self, env_id)
		_finish_glass()
		_perimeter()
		return
	_house()
	_tower()
	_small_house()
	_barrier_wall()
	_crates()
	_castle()
	_scenery()
	_bullseye()
	if not legacy:
		_fortress()
		_barn_yard()
		_watch_village()
		_harbor()
		_gate_and_keep()
		_filler()
		_deep_city()
		_dense_city()
		Outskirts.build(self, env_id)
		_perimeter()
		_decor_city()

# ------------------------------------------------------------------ helpers
func _kit(model: String) -> Node3D:
	var path: String = KIT % model
	if not used_assets.has(path):
		used_assets.append(path)
	return (load(path) as PackedScene).instantiate() as Node3D

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box_mesh(size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(c)
	mi.mesh = bm
	return mi

func _ground() -> void:
	var g := StaticBody3D.new()
	g.name = "Ground"
	g.set_meta("ground", true)
	g.set_meta("mat", "ground")
	g.collision_layer = 1
	g.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9 if legacy else 0.6
	pm.bounce = 0.25 if legacy else 0.45
	g.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var gsz := Vector3(300, 2, 120) if legacy else Vector3(560, 2, 340)
	sh.size = gsz
	cs.shape = sh
	g.add_child(cs)
	g.position = Vector3(80, -1, 0) if legacy else Vector3(130, -1, 0)
	var vis := _box_mesh(gsz, ground_color)
	g.add_child(vis)
	add_child(g)
	# cobble road strip so the town reads as a place
	var road := _box_mesh(Vector3(70 if legacy else 230, 0.05, 6), road_color)
	road.position = Vector3(36 if legacy else 90, 0.02, 0)
	add_child(road)

## Ground height under (x, z): 0 on the flat cities, the terrain height on the hillside cities.
func ground_y(x: float, z: float) -> float:
	return terrain.height(x, z) if terrain != null else 0.0

func ground_normal(x: float, z: float) -> Vector3:
	return terrain.normal(x, z) if terrain != null else Vector3.UP

var launcher_nodes: Array[Node3D] = []      # the slingshot's posts / bands (hidden when another launcher is selected)

func _launcher() -> void:
	var wood := Color(0.55, 0.34, 0.18)
	var base := _box_mesh(Vector3(3.0, 0.5, 4.4), wood)
	base.position = Vector3(-0.2, 0.25, 0)
	add_child(base)
	launcher_nodes.append(base)
	for z in [-POLE_Z, POLE_Z]:
		var pole := _box_mesh(Vector3(0.4, POLE_TOP.y, 0.4), wood)
		pole.position = Vector3(0, POLE_TOP.y * 0.5, z)
		add_child(pole)
		launcher_nodes.append(pole)
		var knob := _box_mesh(Vector3(0.6, 0.3, 0.6), Color(0.8, 0.2, 0.2))
		knob.position = Vector3(0, POLE_TOP.y + 0.1, z)
		add_child(knob)
		launcher_nodes.append(knob)
	band_l = _box_mesh(Vector3(0.1, 0.1, 1.0), Color(0.9, 0.15, 0.2))
	band_r = _box_mesh(Vector3(0.1, 0.1, 1.0), Color(0.9, 0.15, 0.2))
	add_child(band_l)
	add_child(band_r)
	launcher_nodes.append(band_l)
	launcher_nodes.append(band_r)

## Stretch both bands from the pole tops to `pull` (world position of the pouch).
func set_band(pull: Vector3) -> void:
	_stretch(band_l, Vector3(POLE_TOP.x, POLE_TOP.y, -POLE_Z), pull)
	_stretch(band_r, Vector3(POLE_TOP.x, POLE_TOP.y, POLE_Z), pull)

func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var len: float = maxf(a.distance_to(b), 0.05)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(b - a, up).scaled(Vector3(1, 1, len)), (a + b) * 0.5)

## A frozen kit piece. `tile` = grid cell (x,y,z) with y in tile levels; the
## kit pivot is bottom-centre. `size` is the collision/visual extent in tiles.
func _piece(model: String, tile: Vector3, kind: String, group: String, size: Vector3 = Vector3.ONE, mass: float = 3.0, tough: float = 6.0) -> RigidBody3D:
	var h: float = size.y * S
	var b := RigidBody3D.new()
	b.name = "%s_%d" % [kind, pieces.size()]
	b.position = Vector3(tile.x * S, tile.y * S + h * 0.5, tile.z * S)
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.physics_material_override = _phys_stone
	b.can_sleep = true
	b.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * S * 0.98
	cs.shape = sh
	b.add_child(cs)
	var m := _kit(model)
	m.scale = Vector3.ONE * S
	m.position = Vector3(0, -h * 0.5, 0)
	b.add_child(m)
	b.set_meta("rest", b.position)
	b.set_meta("kind", kind)
	b.set_meta("group", group)
	b.set_meta("tough", tough)
	b.set_meta("frozen_piece", true)
	var mat_name: String = Rules.material_of_model(model)
	b.set_meta("mat", mat_name)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	add_child(b)
	pieces.append(b)
	if bool(Rules.MATERIALS[mat_name]["fire"]):
		register_combustible(b)
	if not groups.has(group):
		groups[group] = []
	(groups[group] as Array).append(b)
	return b

func _static_kit(model: String, tile: Vector3, size: Vector3 = Vector3.ONE) -> Node3D:
	if not legacy:
		# the fortress is destructible like everything else - it is just very tough masonry (Destruction levels chew through it)
		var wood: bool = model.begins_with("wood")
		var pc := _piece(model, tile, "wall", "fort_%d" % int(tile.x), size, 3.0 if wood else 9.0, 4.5 if wood else 11.0)
		static_pos.append(pc.position)
		return pc
	var h: float = size.y * S
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.physics_material_override = _phys_stone
	b.position = Vector3(tile.x * S, tile.y * S + h * 0.5, tile.z * S)
	static_pos.append(b.position)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * S
	cs.shape = sh
	b.add_child(cs)
	var m := _kit(model)
	m.scale = Vector3.ONE * S
	m.position = Vector3(0, -h * 0.5, 0)
	b.add_child(m)
	b.set_meta("mat", Rules.material_of_model(model))
	add_child(b)
	return b

func _prop(model: String, pos: Vector3, real_size: Vector3, mass: float, scale_mul: float = PROP_S) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.position = pos + Vector3(0, real_size.y * 0.5, 0)
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7 if legacy else 0.6
	pm.bounce = 0.3 if legacy else 0.5
	b.physics_material_override = pm
	b.can_sleep = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = real_size * 0.96
	cs.shape = sh
	b.add_child(cs)
	var m := _kit(model)
	m.scale = Vector3.ONE * scale_mul
	m.position = Vector3(0, -real_size.y * 0.5, 0)
	b.add_child(m)
	b.set_meta("prop", true)
	b.set_meta("rest", b.position)
	var pmat: String = Rules.material_of_model(model)
	b.set_meta("mat", pmat)
	add_child(b)
	b.sleeping = true
	props.append(b)
	if bool(Rules.MATERIALS[pmat]["fire"]):
		register_combustible(b)
	return b

# --------------------------------------------------------------- structures
func _house() -> void:
	# v13: the full-size city keeps a 16 m+ clear launch corridor (hx = 12 instead of 10); the legacy village (tests) is unchanged.
	var hx: int = 10 if legacy else 12
	# 2 deep x 3 wide x 2 storeys + roof, front face towards the launcher.
	for ty in 2:
		for tz in [-1, 0, 1]:
			var fm := "wall"
			var tough := 6.5
			if ty == 0 and tz == 0:
				fm = "wall-door"
			if ty == 1 and tz == 0:
				fm = "wall-window"
				tough = 3.0
			var p := _piece(fm, Vector3(hx, ty, tz), "wall", "house", Vector3.ONE, 3.0, tough)
			if fm == "wall-window":
				_bonus(p, "window", "House Window", 150)
			_piece("wall", Vector3(hx + 1, ty, tz), "wall", "house", Vector3.ONE, 3.0, 6.5)
	for tz in [-1, 0, 1]:
		for tx in [hx, hx + 1]:
			var r := _piece("roof", Vector3(tx, 2, tz), "roof", "house", Vector3.ONE, 2.5, 5.5)
			if tx == hx + 1 and tz == 0:
				_bonus(r, "roof", "House Roof", 100)
	# chimney on the roof
	for i in 3:
		var c := _piece("column", Vector3(hx + 1, 3.0 + i * 1.0, 1), "column", "chimney", Vector3(0.4, 1.0, 0.4), 1.0, 3.5)
		c.set_meta("group_all", true)
		if i == 2:
			_bonus(c, "chimney", "Chimney", 250)

func _tower() -> void:
	var tz: float = -4.0
	var tx: float = 17.0
	var names := ["tower-base", "tower", "tower", "tower", "tower-top"]
	for i in names.size():
		var sz := Vector3(1.0, 1.0, 1.0)
		var p := _piece(names[i], Vector3(tx, i, tz), "tower", "tower", sz, 4.0, 4.0)
		p.set_meta("group_all", true)
		if i == names.size() - 1:
			_bonus(p, "tower", "Old Tower", 300)

func _small_house() -> void:
	for ty in 1:
		for tx in [20, 21]:
			for tz in [3, 4]:
				_piece("wall-window" if (tx == 20 and tz == 3) else "wall", Vector3(tx, ty, tz), "wall", "house2", Vector3.ONE, 3.0, 3.5 if (tx == 20 and tz == 3) else 6.0)
	for tx in [20, 21]:
		for tz in [3, 4]:
			_piece("roof", Vector3(tx, 1, tz), "roof", "house2", Vector3.ONE, 2.5, 5.0)
	_piece("overhang", Vector3(19, 0.5, 3.5), "awning", "house2", Vector3(1.0, 0.3, 1.0), 1.0, 2.5)

func _barrier_wall() -> void:
	for tz in range(-3, 4):
		for ty in 2:
			if tz == 0 and ty == 0:
				continue
			_piece("wall-low" if ty == 1 else "wall", Vector3(24, ty if ty == 0 else 1, tz), "wall", "barrier", Vector3(1, 0.5 if ty == 1 else 1.0, 1), 3.0, 6.0)

func _crates() -> void:
	var cs: float = 0.75
	var x0: float = 12.0
	var z0: float = 7.0
	for row in 3:
		var n: int = 3 - row
		for i in n:
			var off: float = (i - (n - 1) * 0.5) * (cs + 0.02)
			_prop("detail-crate", Vector3(x0, row * cs + 0.001, z0 + off), Vector3(cs, cs, cs), 1.6)
	_prop("barrels", Vector3(15.0, 0.0, -9.0), Vector3(1.5, 1.23, 0.75), 14.0, PROP_S * 2.5 / 2.5 * 1.0)
	for i in 3:
		_prop("detail-barrel", Vector3(14.0 + i * 0.9, 0.0, 9.5), Vector3(0.62, 0.75, 0.62), 2.0)
	for i in 4:
		_prop("detail-crate-small", Vector3(27.0 + i * 0.6, 0.0, -7.5), Vector3(0.5, 0.5, 0.5), 0.9)

func _castle() -> void:
	# immovable stone wall far downrange: the "you hit the big thing" backstop
	for tz in range(-4, 5):
		for ty in 2:
			_static_kit("wall-fortified", Vector3(36, ty, tz))
	_static_kit("tower-base", Vector3(36, 0, -5), Vector3(1.1, 1.0, 1.1))
	_static_kit("tower-base", Vector3(36, 0, 5), Vector3(1.1, 1.0, 1.1))

func _scenery() -> void:
	var spots := [Vector3(6, 0, -9), Vector3(8, 0, 11), Vector3(30, 0, 9), Vector3(30, 0, -11),
		Vector3(44, 0, -6), Vector3(46, 0, 8), Vector3(52, 0, -12), Vector3(64, 0, 10), Vector3(66, 0, -9)]
	for s in spots:
		var t := StaticBody3D.new()
		t.collision_layer = 1
		t.collision_mask = 0
		t.position = s
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.4
		sh.height = 2.4
		cs.shape = sh
		cs.position = Vector3(0, 1.2, 0)
		t.add_child(cs)
		var cs2 := CollisionShape3D.new()
		var sh2 := SphereShape3D.new()
		sh2.radius = 1.3
		cs2.shape = sh2
		cs2.position = Vector3(0, 3.4, 0)
		t.add_child(cs2)
		var m := _kit("tree-large")
		m.scale = Vector3.ONE * 2.2
		t.add_child(m)
		add_child(t)

func _bullseye() -> void:
	if legacy:
		_ring("bullseye", "Bullseye", Vector2(58.0, 0.0), 8.0, 500)
	else:
		_ring("bullseye", "Bullseye", Vector2(68.0, 14.0), 7.5, 500)

## A landing target: concentric rings; the closer to the centre the ground contact, the more it pays
## (dead centre x2, inner x1, middle x0.5, outer x0.3 of `base`).
func _ring(key: String, nm: String, center: Vector2, r: float, base: int) -> void:
	rings.append({"key": key, "name": nm, "center": center, "r": r, "base": base})
	var cols := [Color(0.9, 0.15, 0.15), Color(0.97, 0.97, 0.97), Color(0.9, 0.15, 0.15), Color(0.97, 0.97, 0.97), Color(1.0, 0.85, 0.1)]
	var fr := [1.0, 0.7, 0.4, 0.17, 0.08]
	for i in 5:
		var d := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var rr: float = r * float(fr[i])
		cm.top_radius = rr
		cm.bottom_radius = rr
		cm.height = 0.04
		cm.material = _mat(cols[i])
		d.mesh = cm
		d.position = Vector3(center.x, 0.03 + i * 0.01, center.y)
		add_child(d)
	_target(key, nm, base, Vector3(center.x, 0.5, center.y))

## Points for a ground contact at `pos` (0 = outside every ring) and the ring record.
func ring_award(pos: Vector3) -> Dictionary:
	for rg in rings:
		var d: float = Vector2(pos.x - (rg["center"] as Vector2).x, pos.z - (rg["center"] as Vector2).y).length()
		var f: float = d / float(rg["r"])
		if f <= 1.0:
			var mult: float = 2.0 if f <= 0.17 else (1.0 if f <= 0.4 else (0.5 if f <= 0.7 else 0.3))
			var nm: String = "DEAD CENTRE " + str(rg["name"]) if f <= 0.17 else str(rg["name"])
			return {"key": rg["key"], "name": nm, "pts": int(float(rg["base"]) * mult), "dead": f <= 0.17}
	return {}

# --------------------------------------------------------------- destruction
func frozen_count() -> int:
	var n: int = 0
	for p in pieces:
		if p.freeze:
			n += 1
	return n


# ------------------------------------------------------------- destruction support (see destruction.gd)
func cell_register(cb: RigidBody3D) -> void:
	if bool(Rules.MATERIALS[str(cb.get_meta("mat", "masonry"))]["fire"]):
		register_combustible(cb)

func fire_state_of(n: Node) -> int:
	var id: int = n.get_instance_id()
	return fire_state[int(_fire_idx[id])] if _fire_idx.has(id) else 0

## A shell that has been replaced by cells stops being fuel itself.
func fire_retire(n: Node) -> void:
	var id: int = n.get_instance_id()
	if not _fire_idx.has(id):
		return
	var i: int = int(_fire_idx[id])
	if fire_state[i] == 1:
		if fx and fire_handle[i] >= 0:
			fx.flame_stop(fire_handle[i])
			fire_handle[i] = -1
		burning_count = maxi(burning_count - 1, 0)
	fire_state[i] = 2

func fire_unretire(n: Node) -> void:
	var id: int = n.get_instance_id()
	if _fire_idx.has(id):
		fire_state[int(_fire_idx[id])] = 0

## Over-budget broken pieces never become rigid bodies: they vanish in a burst of pooled debris (fake the impossible).
func dissolve(p: RigidBody3D, vel: Vector3) -> void:
	if p.get_meta("dissolved", false):
		return
	p.set_meta("dissolved", true)
	p.set_meta("capped", true)
	p.collision_layer = 0
	p.visible = false
	_spawn_debris(p.global_position, vel * 0.6, 4)
	var id: int = p.get_instance_id()
	if _fire_idx.has(id):
		fire_retire(p)
	piece_released.emit(p)

## Facade windows are world-triplanar so a standing building reads as one wall; once a chunk moves the texture would slide over it,
## so a released chunk gets its own object-space copy, aligned to where it stood (the pattern leaves the building intact).
func _own_texture(p: RigidBody3D) -> void:
	if p.has_meta("own_tex"):
		return
	p.set_meta("own_tex", true)
	for ch in p.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			var m = mi.material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).uv1_world_triplanar:
				var own: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				own.uv1_world_triplanar = false
				own.uv1_offset = (p.get_meta("rest") as Vector3) * own.uv1_scale
				mi.material_override = own

func release(p: RigidBody3D, vel: Vector3) -> void:
	if not p.freeze:
		return
	if p.get_meta("capped", false):
		return
	if _live_cnt >= ACTIVE_HARD:                 # the simulation budget is spent: this piece becomes a puff of debris instead
		_live_check()
		if _live_cnt >= ACTIVE_HARD:
			dissolve(p, vel)
			return
	if p.has_meta("shell_of"):
		_own_texture(p)
	p.freeze = false
	p.set_meta("t_rel", Time.get_ticks_msec())
	_live_cnt += 1
	released_order.append(p)
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	piece_released.emit(p)

## Called when the ragdoll hits `hit` at `speed` along `dir`. Returns released pieces.
func smash(hit: RigidBody3D, hit_pos: Vector3, dir: Vector3, speed: float) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if not hit.freeze or speed < float(hit.get_meta("tough", 6.0)):
		return out
	var radius: float = minf(1.7 + 0.1 * speed, 4.2)
	var group: String = hit.get_meta("group", "")
	var all_group: bool = hit.get_meta("group_all", false)
	for p in pieces:
		if not p.freeze or p.get_meta("capped", false):
			continue
		var d: float = p.global_position.distance_to(hit_pos)
		var same: bool = all_group and p.get_meta("group", "") == group
		if same or d <= radius:
			var fall: float = 1.0 - clampf(d / maxf(radius, 0.01), 0.0, 1.0) * 0.6
			var v: Vector3 = dir * speed * smash_push * fall + (p.global_position - hit_pos).normalized() * 2.0 + Vector3(0, 2.0, 0)
			release(p, v)
			out.append(p)
	return out

# ------------------------------------------------------------- targets / markers
static func region_of(pos: Vector3) -> String:
	var a: float = rad_to_deg(atan2(pos.z, maxf(pos.x, 1.0)))
	if a <= -35.0: return "far_left"
	if a <= -12.0: return "left_center"
	if a < 12.0: return "center"
	if a < 35.0: return "right_center"
	return "far_right"

## Registers a slingshot target (+ floating value marker). Returns the bonus record.
func _target(key: String, nm: String, pts: int, pos: Vector3) -> Dictionary:
	var t := {"key": key, "name": nm, "pts": pts, "pos": pos, "region": Town.region_of(pos)}
	targets.append(t)
	if not legacy:
		var l := Label3D.new()
		l.text = "%d" % pts
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0010
		l.font_size = 40
		l.outline_size = 12
		l.no_depth_test = true
		l.modulate = Color(0.95, 0.62, 0.3) if pts < 200 else (Color(0.85, 0.92, 1.0) if pts < 500 else (Color(1.0, 0.86, 0.2) if pts < 1000 else Color(1.0, 0.45, 0.95)))
		l.position = pos + Vector3(0, 3.2, 0)
		add_child(l)
		# glowing light beam so the target can be spotted from anywhere in the city
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.7
		cm.height = 90.0
		cm.radial_segments = 8
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tc: Color = l.modulate
		bm.albedo_color = Color(tc.r, tc.g, tc.b, 0.32)
		cm.material = bm
		beam.mesh = cm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(pos.x, 45.0, pos.z)
		add_child(beam)
		_beams[key] = [beam, l]
	return t

func _bonus(body: Node, key: String, nm: String, pts: int) -> void:
	var pos: Vector3 = (body as Node3D).position
	var t := _target(key, nm, pts, pos)
	body.set_meta("bonus", {"name": nm, "pts": pts, "key": key})

# ------------------------------------------------------- expanded playground
func _building(ox: int, oz: int, w: int, d: int, floors: int, group: String, fort: bool, roof: bool, window_floor: int) -> RigidBody3D:
	var win: RigidBody3D = null
	for f in floors:
		for i in w:
			for j in d:
				var is_win: bool = (i == 0 and f == window_floor and j == d / 2)
				var model: String = ("wall-fortified-window" if fort else "wall-window") if is_win else ("wall-fortified" if fort else "wall")
				var p := _piece(model, Vector3(ox + i, f, oz + j), "wall", group, Vector3.ONE, 3.0, 3.0 if is_win else 6.5)
				if is_win:
					win = p
	if roof:
		for i in w:
			for j in d:
				_piece("roof", Vector3(ox + i, floors, oz + j), "roof", group, Vector3.ONE, 2.5, 5.5)
	return win

func _tower_stack(tx: int, tz: int, n: int, group: String) -> RigidBody3D:
	var top: RigidBody3D = null
	for i in n:
		var nm: String = "tower-base" if i == 0 else ("tower-top" if i == n - 1 else "tower")
		var p := _piece(nm, Vector3(tx, i, tz), "tower", group, Vector3.ONE, 4.0, 4.0)
		p.set_meta("group_all", true)
		top = p
	return top

func _chimney_stack(tx: float, ty: float, tz: float, n: int, group: String) -> RigidBody3D:
	var top: RigidBody3D = null
	for i in n:
		var c := _piece("column", Vector3(tx, ty + i * 1.0, tz), "column", group, Vector3(0.4, 1.0, 0.4), 1.0, 3.5)
		c.set_meta("group_all", true)
		top = c
	return top

## A building-sized box as a stack of destruction shells (<= 18 m each) with a window-textured facade, linked so the upper
## storeys fall when the ones under them are destroyed. Replaces the old immovable static towers. Returns the top shell.
func shell_box(pos: Vector3, size: Vector3, color: Color, mat_name: String, group: String, tough: float = 7.0, windows: bool = true) -> RigidBody3D:
	if _hctx == null:
		_hctx = Hillside.Ctx.new()
		_hctx.t = self
	var segs: int = maxi(1, int(ceil(size.y / 18.0)))
	var seg_h: float = size.y / float(segs)
	var prev: RigidBody3D = null
	var top: RigidBody3D = null
	var mat: Material = Hillside._wall_mat(_hctx, color) if windows else _cmat(color)
	for i in segs:
		var cy: float = pos.y - size.y * 0.5 + (float(i) + 0.5) * seg_h
		var b: RigidBody3D = _block(Vector3(pos.x, cy, pos.z), Vector3(size.x, seg_h, size.z), color, mat_name, 3.0 + size.x * seg_h * size.z * 0.012, tough, group)
		for ch in b.get_children():
			if ch is MeshInstance3D:
				(ch as MeshInstance3D).material_override = mat
		var n := Vector3i(clampi(int(round(size.x / 4.5)), 1, 4), clampi(int(round(seg_h / 3.6)), 1, 6), clampi(int(round(size.z / 4.5)), 1, 4))
		Destruction.register_shell(b, Destruction.box_cells.bind(Vector3(size.x, seg_h, size.z), mat, n), n.x * n.y * n.z)
		if prev != null:
			Destruction.link_stack(prev, b)
		prev = b
		top = b
	return top

func _static_box(pos: Vector3, size: Vector3, color: Color, visual: bool = true) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.physics_material_override = _phys_stone
	b.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	if visual:
		b.add_child(_box_mesh(size, color))
	add_child(b)
	return b

func _crate_pyramid(x: float, z: float, rows: int) -> void:
	var cs: float = 0.75
	for row in rows:
		var n: int = rows - row
		for i in n:
			var off: float = (i - (n - 1) * 0.5) * (cs + 0.02)
			_prop("detail-crate", Vector3(x, row * cs + 0.001, z + off), Vector3(cs, cs, cs), 1.6)

func _fortress() -> void:
	# LEFT-CENTER: stone block with a window, and a bell tower on its corner
	var win := _building(30, -19, 3, 4, 2, "fortress", true, false, 1)
	_bonus(win, "fort_window", "Fortress Window", 400)
	var top := _tower_stack(33, -20, 5, "bell")
	_bonus(top, "bell", "Bell Tower", 550)
	_crate_pyramid(40.0, -20.0, 3)

func _barn_yard() -> void:
	# RIGHT-CENTER: barn, very tall chimney, crate pyramid and a heavy barrel pile
	_building(28, 15, 3, 2, 1, "barn", false, true, -1)
	var top := _chimney_stack(29.0, 2.0, 15.0, 6, "tallchimney")
	_bonus(top, "tall_chimney", "Tall Chimney", 450)
	_crate_pyramid(40.0, 27.0, 4)
	var heavy := _prop("barrels", Vector3(37.0, 0.0, 21.0), Vector3(1.5, 1.23, 0.75), 14.0, PROP_S)
	_bonus(heavy, "barrels", "Barrel Yard", 300)
	for i in 3:
		_prop("detail-barrel", Vector3(34.0 + i * 0.9, 0.0, 30.0), Vector3(0.62, 0.75, 0.62), 2.0)

func _watch_village() -> void:
	# FAR-LEFT: a tall watchtower and a couple of cottages
	var top := _tower_stack(48, -38, 8, "watch")
	_bonus(top, "watchtower", "Watchtower", 900)
	_building(45, -33, 2, 2, 1, "cottageL", false, true, -1)
	_building(51, -41, 2, 2, 1, "cottageL2", false, true, -1)

func _harbor() -> void:
	# FAR-RIGHT: lighthouse, shed, docks over water
	var top := _tower_stack(46, 36, 9, "lighthouse")
	_bonus(top, "lighthouse", "Lighthouse", 900)
	_building(43, 31, 2, 2, 1, "shed", false, true, -1)
	var water := _box_mesh(Vector3(26.0, 0.05, 16.0), Color(0.2, 0.45, 0.8))
	water.position = Vector3(76.0, 0.04, 66.0)
	add_child(water)
	for i in 8:
		_static_kit("wood-floor", Vector3(44 + i, 0.0, 41), Vector3(1.0, 0.125, 1.0))
	_crate_pyramid(63.0, 49.0, 3)

func _gate(key: String, nm: String, pts: int, tx: int, reach: int) -> void:
	for f in 3:
		for z in range(2, reach):
			_static_kit("wall-fortified", Vector3(tx, f, z))
			_static_kit("wall-fortified", Vector3(tx, f, -z))
	var gx: float = float(tx) * S
	gaps.append({"key": key, "name": nm, "pts": pts, "x": gx, "half": 2.2, "ymax": 6.5})
	_target(key, nm, pts, Vector3(gx, 2.5, 0.0))

func _gate_and_keep() -> void:
	# CENTER-FAR: a narrow gate you can thread ("Needle Gap") and the distant keep wall
	_gate("needle", "Needle Gap", 800, 50, 8)
	var win := _building(57, -4, 1, 9, 2, "keep", true, false, 1)
	_bonus(win, "keep_window", "Keep Window", 1200)

func _perimeter() -> void:
	# The world edge. These colliders are NOT destructive surfaces: touching one ends the throw cleanly
	# (meta "boundary"; see main.gd _hit_boundary). v12 treated them as masonry and fast throws "exploded" against nothing.
	var col := Color(0.46, 0.46, 0.5)
	var walls: Array[StaticBody3D] = []
	walls.append(_static_box(Vector3(WORLD_X_MAX, 200.0, 0.0), Vector3(2.0, 400.0, WORLD_Z * 2.0 + 4.0), col, false))
	walls.append(_static_box(Vector3(WORLD_X_MAX, 2.0, 0.0), Vector3(2.0, 4.0, WORLD_Z * 2.0 + 4.0), col))
	walls.append(_static_box(Vector3(WORLD_X_MIN, 200.0, 0.0), Vector3(2.0, 400.0, WORLD_Z * 2.0 + 4.0), col, false))
	for sgn in [-1.0, 1.0]:
		walls.append(_static_box(Vector3((WORLD_X_MAX + WORLD_X_MIN) * 0.5, 200.0, sgn * WORLD_Z), Vector3(WORLD_X_MAX - WORLD_X_MIN, 400.0, 2.0), col, false))
		walls.append(_static_box(Vector3((WORLD_X_MAX + WORLD_X_MIN) * 0.5, 2.0, sgn * WORLD_Z), Vector3(WORLD_X_MAX - WORLD_X_MIN, 4.0, 2.0), col))
	for w in walls:
		w.set_meta("boundary", true)
		w.set_meta("mat", "ground")
		boundary_bodies.append(w)

func _tree(s: Vector3) -> void:
	var t := StaticBody3D.new()
	t.collision_layer = 1
	t.collision_mask = 0
	t.position = s
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.4
	sh.height = 2.4
	cs.shape = sh
	cs.position = Vector3(0, 1.2, 0)
	t.add_child(cs)
	var m := _kit("tree-large")
	m.scale = Vector3.ONE * 2.2
	t.add_child(m)
	t.set_meta("mat", "wood")
	add_child(t)
	register_combustible(t)

# ------------------------------------------------------ bounded active physics
func _physics_process(dt: float) -> void:
	_fire_acc += dt
	if _fire_acc >= 0.25:
		if burning_count > 0:
			_fire_tick(_fire_acc)
		_fire_acc = 0.0
	_cap_timer += dt
	if _cap_timer >= 0.5:
		_cap_timer = 0.0
		enforce_active_cap()

var _live_cnt: int = 0                           # released, still-simulated pieces (recounted when the budget is reached)

func _live_check() -> void:
	_live_cnt = active_released()

func active_released() -> int:
	var n: int = 0
	for p in released_order:
		if is_instance_valid(p) and not p.freeze:
			n += 1
	return n

## Re-freeze the oldest settled released pieces so the simulation stays bounded.
func enforce_active_cap() -> void:
	# settled chunks stop being simulated after a while and stay where they fell (the aftermath persists, the physics cost does not)
	var now_ms: int = Time.get_ticks_msec()
	for p in released_order:
		if is_instance_valid(p) and not p.freeze and now_ms - int(p.get_meta("t_rel", now_ms)) > 7000 and p.linear_velocity.length() < 0.5:
			p.set_meta("capped", true)
			p.freeze = true
	if active_released() <= ACTIVE_CAP:
		return
	for p in released_order:
		if active_released() <= ACTIVE_CAP:
			break
		if is_instance_valid(p) and not p.freeze and p.linear_velocity.length() < 1.0:
			p.set_meta("capped", true)
			p.freeze = true

## Mid-field cottages, low walls and crate piles so the lateral zones are not empty grass.
func _filler() -> void:
	var cottages := [Vector2i(12, -8), Vector2i(20, -12), Vector2i(36, -14), Vector2i(42, -8), Vector2i(58, -20), Vector2i(62, -30),
		Vector2i(20, -30), Vector2i(8, -18), Vector2i(12, 8), Vector2i(18, 16), Vector2i(34, 10), Vector2i(42, 8), Vector2i(54, 18),
		Vector2i(60, 26), Vector2i(20, 28), Vector2i(10, 20), Vector2i(50, -30), Vector2i(52, 30)]
	var n := 0
	for c in cottages:
		_building(c.x, c.y, 2, 1, 1, "cot%d" % n, n % 3 == 0, true, -1)
		n += 1
	var walls := [Vector3i(26, -6, 5), Vector3i(26, 3, 4), Vector3i(48, -24, 4), Vector3i(48, 18, 5), Vector3i(64, 12, 4), Vector3i(64, -14, 4)]
	for w in walls:
		_building(w.x, w.y, 1, w.z, 1, "wallrun%d" % n, true, false, -1)
		n += 1
	for sp in [Vector2(30.0, -34.0), Vector2(56.0, -44.0), Vector2(30.0, 38.0), Vector2(58.0, 44.0), Vector2(90.0, -20.0), Vector2(92.0, 22.0)]:
		_crate_pyramid(sp.x, sp.y, 2)

## Fast reset: put every piece/prop back where it was instead of rebuilding ~400 nodes.
func reset_in_place() -> void:
	Destruction.restore_all(self)
	for p in pieces:
		if p.get_meta("dissolved", false):
			p.set_meta("dissolved", false)
			p.visible = true
			p.collision_layer = 4
		p.collision_layer = 4
		p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		p.freeze = true
		p.remove_meta("capped")
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.global_transform = Transform3D(Basis.IDENTITY, p.get_meta("rest"))
	unclaim_all()
	for b in props:
		b.set_meta("exploded", false)
		b.visible = true
		b.collision_layer = 4
		b.freeze = false
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.global_transform = Transform3D(Basis.IDENTITY, b.get_meta("rest"))
	for b in props:                     # second pass: moving neighbours would wake sleepers
		b.sleeping = true
	released_order.clear()
	_live_cnt = 0
	_restore_decor()
	_restore_glass()
	fire_reset()

# ------------------------------------------------------------ the deep city (60-200 m)
func _reserve(x0: float, z0: float, x1: float, z1: float) -> void:
	_reserved.append(Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2(absf(x1 - x0), absf(z1 - z0))))

func _is_reserved(x: float, z: float, pad: float) -> bool:
	for r in _reserved:
		if (r as Rect2).grow(pad).has_point(Vector2(x, z)):
			return true
	return false

func _deep_city() -> void:
	# keep-out zones (meters) for everything hand-placed, so the decorative city never overlaps it
	for r in [[8, -16, 62, 16], [38, -36, 56, -16], [34, 14, 52, 36], [60, -68, 84, -36], [56, 26, 92, 74], [64, -14, 96, 14],
			[110, -76, 160, -34], [110, 34, 160, 80], [150, -26, 200, 26], [128, -50, 146, -28], [128, 26, 146, 48], [138, -110, 166, -76], [138, 76, 166, 112]]:
		_reserve(r[0], r[1], r[2], r[3])
	# --- LEFT-CENTER, far: old mill tower
	var mill := _tower_stack(87, -23, 7, "mill")
	_bonus(mill, "mill", "Old Mill", 1000)
	_building(84, -20, 2, 2, 1, "millhouse", false, true, -1)
	# --- RIGHT-CENTER, far: grain silo
	var silo := _tower_stack(90, 26, 7, "silo")
	_bonus(silo, "silo", "Grain Silo", 1000)
	_building(86, 23, 2, 2, 1, "siloshed", true, true, -1)
	# --- FAR-LEFT: cliff watch (mid-depth) and the monastery spire (deep)
	var cw := _tower_stack(80, -40, 8, "cliff")
	_bonus(cw, "cliff_watch", "Cliff Watch", 1100)
	_building(76, -36, 3, 2, 2, "cliffhall", true, false, 1)
	var sp := _tower_stack(84, -56, 11, "spire")
	_bonus(sp, "spire", "Monastery Spire", 1500)
	_building(79, -60, 3, 3, 2, "abbey", true, false, 1)
	_building(90, -52, 2, 2, 1, "abbey2", false, true, -1)
	# --- FAR-RIGHT: harbor crane (mid-depth) and the port lighthouse (deep)
	var cr := _tower_stack(84, 38, 7, "crane")
	_bonus(cr, "crane", "Harbor Crane", 1100)
	var lh := _tower_stack(84, 54, 11, "portlight")
	_bonus(lh, "portlight", "Port Lighthouse", 1500)
	_building(78, 48, 3, 3, 2, "customs", true, false, 1)
	_building(90, 60, 2, 2, 1, "warehouse", false, true, -1)
	var water := _box_mesh(Vector3(52.0, 0.05, 36.0), Color(0.2, 0.45, 0.8))
	water.position = Vector3(150.0, 0.04, 98.0)
	add_child(water)
	for i in 12:
		_static_kit("wood-floor", Vector3(100 + i, 0.0, 66), Vector3(1.0, 0.125, 1.0))
	_crate_pyramid(138.0, 70.0, 4)
	_crate_pyramid(144.0, -72.0, 4)
	# --- FAR-CENTER: the grand castle
	_gate("grand_gate", "Grand Gate", 1600, 110, 10)
	for i in 4:
		_crate_pyramid(168.0, -10.0 + i * 7.0, 3)
	var wall_win := _building(118, -8, 1, 17, 3, "castle", true, false, 2)
	_bonus(wall_win, "castle_window", "Castle Window", 1800)
	var crown := _tower_stack(100, 0, 13, "crown")   # v14: tile 100 (150 m); v13 had it at 116 (174 m) - still outside the governor's ballistic reach
	_bonus(crown, "crown", "Castle Crown", 2500)
	_tower_stack(118, -10, 6, "ctowerL")
	_tower_stack(118, 10, 6, "ctowerR")
	_ring("far_ring", "Far Bullseye", Vector2(130.0, -14.0), 9.0, 1000)
	# --- extra mid-depth cover: wall runs and crate piles
	for w in [Vector3i(70, -14, 5), Vector3i(70, 12, 5), Vector3i(96, -6, 6), Vector3i(96, 2, 5)]:
		_building(w.x, w.y, 1, w.z, 2, "deepwall%d_%d" % [w.x, w.y], true, false, -1)

# The dense city: thousands of cottages/trees drawn with MultiMesh, each with its own static
# collider. They look immovable but SMASH when the ragdoll hits them fast: the instance is hidden and
# a puff of pooled debris flies (cheap destruction for the whole city).
var _mm_walls: MultiMesh
var _mm_roofs: MultiMesh
var _mm_trees: MultiMesh
var decor_bodies: Array[StaticBody3D] = []
var _broken: Array[StaticBody3D] = []
var debris: Array[RigidBody3D] = []
var _debris_i: int = 0
var decor_smashed: int = 0

func _decor_cottage(x: float, z: float, yaw: float) -> void:
	var bas := Basis(Vector3.UP, yaw)
	var sc := Basis.from_scale(Vector3.ONE * S)
	var w0: int = _decor_walls.size()
	for i in 2:
		var pos: Vector3 = Vector3(x, 0.0, z) + bas * Vector3((float(i) - 0.5) * S, 0.0, 0.0)
		_decor_walls.append(Transform3D(bas * sc, pos))
		_decor_roofs.append(Transform3D(bas * sc, pos + Vector3(0, S, 0)))
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.physics_material_override = _phys_stone
	b.transform = Transform3D(bas, Vector3(x, S, z))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.0 * S, 2.0 * S, S)
	cs.shape = sh
	b.add_child(cs)
	b.set_meta("decor", decor_bodies.size())
	b.set_meta("w0", w0)
	b.set_meta("mat", "wood")
	add_child(b)
	decor_bodies.append(b)
	register_combustible(b)

func _decor_tree(x: float, z: float) -> void:
	_decor_trees.append(Transform3D(Basis.from_scale(Vector3.ONE * 2.2), Vector3(x, 0, z)))
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = Vector3(x, 1.3, z)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.5
	sh.height = 2.6
	cs.shape = sh
	b.add_child(cs)
	b.set_meta("decor", decor_bodies.size())
	b.set_meta("tree", _decor_trees.size() - 1)
	b.set_meta("mat", "wood")
	add_child(b)
	decor_bodies.append(b)
	register_combustible(b)

func _mesh_of(model: String) -> Mesh:
	var inst := _kit(model)
	var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh: Mesh = mi.mesh
	inst.free()
	return mesh

func _multimesh(mesh: Mesh, xfs: Array[Transform3D]) -> MultiMesh:
	if xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm

func _decor_city() -> void:
	# city blocks: 3x3 terraced cottages per block, alleys between blocks, a clear main street along z=0
	var n := 0
	var bx := 0
	for x0 in range(8, 214, 17):
		var bz := 0
		for z0 in range(-128, 128, 17):
			for i in 3:
				for j in 3:
					var x: float = float(x0) + float(i) * 4.7
					var z: float = float(z0) + float(j) * 4.5
					var h: int = (bx * 7 + bz * 13 + i * 5 + j * 11 + bx * bz) % 11
					if absf(z) < 4.6 or _is_reserved(x, z, 2.2) or not _free(x, z, 2.4):
						continue
					if h <= 7:
						_decor_cottage(x, z, 0.0)
						n += 1
					elif h == 8:
						_decor_tree(x, z)
			bz += 1
		bx += 1
	_mm_walls = _multimesh(_mesh_of("wall"), _decor_walls)
	_mm_roofs = _multimesh(_mesh_of("roof"), _decor_roofs)
	_mm_trees = _multimesh(_mesh_of("tree-large"), _decor_trees)
	_make_debris_pool()

func _make_debris_pool() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.45, 0.5)
	bm.material = _mat(Color(0.58, 0.55, 0.5))
	for i in 140:
		var d := RigidBody3D.new()
		d.collision_layer = 0
		d.collision_mask = 1                 # debris only touches the ground: it is a visual shower, not simulation load
		d.mass = 0.8
		d.freeze = true
		d.visible = false
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bm.size
		cs.shape = sh
		d.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.add_child(mi)
		d.position = Vector3(0, -50, 0)
		add_child(d)
		debris.append(d)

func _spawn_debris(pos: Vector3, vel: Vector3, n: int) -> void:
	if debris.is_empty():
		_make_debris_pool()
	for i in n:
		var d: RigidBody3D = debris[_debris_i]
		_debris_i = (_debris_i + 1) % debris.size()
		d.freeze = false
		d.visible = true
		d.collision_layer = 8
		d.global_transform = Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)), pos + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 2.2), randf_range(-1.2, 1.2)))
		d.linear_velocity = vel * randf_range(0.35, 0.9) + Vector3(randf_range(-5, 5), randf_range(2, 9), randf_range(-5, 5))
		d.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))

func _hide_instance(mm: MultiMesh, idx: int) -> void:
	if mm:
		mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -200, 0)))

## The ragdoll hit a decorative building/tree hard: it bursts into debris. Returns true if it broke.
func break_decor(b: StaticBody3D, dir: Vector3, speed: float) -> bool:
	if b.collision_layer == 0:
		return false
	b.collision_layer = 0
	_broken.append(b)
	var at: Vector3 = b.global_position
	if b.has_meta("tree"):
		_hide_instance(_mm_trees, int(b.get_meta("tree")))
		_spawn_debris(at, dir * speed * 0.5, 3)
	else:
		var w0: int = int(b.get_meta("w0"))
		_hide_instance(_mm_walls, w0)
		_hide_instance(_mm_walls, w0 + 1)
		_hide_instance(_mm_roofs, w0)
		_hide_instance(_mm_roofs, w0 + 1)
		_spawn_debris(at, dir * speed * 0.6, 8)
	decor_smashed += 1
	return true

func _restore_decor() -> void:
	for b in _broken:
		b.collision_layer = 1
		if b.has_meta("tree"):
			var ti: int = int(b.get_meta("tree"))
			_mm_trees.set_instance_transform(ti, _decor_trees[ti])
		else:
			var w0: int = int(b.get_meta("w0"))
			for k in 2:
				_mm_walls.set_instance_transform(w0 + k, _decor_walls[w0 + k])
				_mm_roofs.set_instance_transform(w0 + k, _decor_roofs[w0 + k])
	_broken.clear()
	decor_smashed = 0
	for d in debris:
		d.freeze = true
		d.visible = false
		d.collision_layer = 0
		d.position = Vector3(0, -50, 0)

func _free(x: float, z: float, r: float) -> bool:
	for o in _occupied:
		if (o as Vector2).distance_squared_to(Vector2(x, z)) < r * r:
			return false
	return true

## Thick city: small breakable sheds and crate/barrel/TNT clutter everywhere the ragdoll is likely to land.
func _dense_city() -> void:
	var n := 0
	var ix := 0
	for xi in range(14, 170, 9):
		var iz := 0
		for zi in range(-84, 85, 9):
			var h: int = (ix * 17 + iz * 31 + ix * iz) % 10
			iz += 1
			var x: float = float(xi) + float((ix * 5 + iz * 3) % 4) - 1.5
			var z: float = float(zi) + float((ix * 3 + iz * 7) % 4) - 1.5
			if _is_reserved(x, z, 2.5) or (absf(z) < 4.0):
				continue
			if h < 5:
				var tx: int = int(round(x / S))
				var tz: int = int(round(z / S))
				_building(tx, tz, 1, 1, 1, "shed%d" % n, h == 0, true, -1)
				_occupied.append(Vector2(x, z))
				n += 1
		ix += 1
	# clutter (crates, barrels, red TNT barrels)
	ix = 0
	var tnt_n := 0
	for xi in range(12, 190, 6):
		var iz := 0
		for zi in range(-90, 91, 6):
			var h: int = (ix * 13 + iz * 7 + ix * iz * 3) % 10
			iz += 1
			var x: float = float(xi) + float((ix * 7 + iz) % 3) - 1.0
			var z: float = float(zi) + float((ix + iz * 5) % 3) - 1.0
			if _is_reserved(x, z, 1.5) or not _free(x, z, 2.2):
				continue
			if h <= 2:
				_prop("detail-crate", Vector3(x, 0.001, z), Vector3(0.75, 0.75, 0.75), 1.6)
				_prop("detail-crate", Vector3(x, 0.76, z), Vector3(0.75, 0.75, 0.75), 1.6)
				_occupied.append(Vector2(x, z))
			elif h <= 5:
				_prop("detail-barrel", Vector3(x, 0.0, z), Vector3(0.62, 0.75, 0.62), 2.0)
				_occupied.append(Vector2(x, z))
			elif (h == 6 or h == 7) and tnt_n < 44:
				_tnt_barrel(x, z)
				tnt_n += 1
				_occupied.append(Vector2(x, z))
		ix += 1

## Target claimed this attempt: dim its beam and label.
func claim(key: String) -> void:
	if _beams.has(key):
		var bl: Array = _beams[key]
		(bl[0] as MeshInstance3D).visible = false
		(bl[1] as Label3D).modulate.a = 0.3

func unclaim_all() -> void:
	for k in _beams.keys():
		var bl: Array = _beams[k]
		(bl[0] as MeshInstance3D).visible = true
		(bl[1] as Label3D).modulate.a = 1.0

# ------------------------------------------------------------------- mayhem
func _tnt_barrel(x: float, z: float) -> void:
	var b := _prop("detail-barrel", Vector3(x, 0.0, z), Vector3(0.62, 0.75, 0.62), 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.08, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.05)
	mat.emission_energy_multiplier = 0.6
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	b.set_meta("explosive", true)
	tnt.append(b)

## Boom: shoves released pieces/props, releases frozen pieces in range, chains into other TNT.
## Returns {released: Array[RigidBody3D], blasts: Array[Vector3]} (all blast centres incl. chains).
func explode(center: Vector3, radius: float, power: float) -> Dictionary:
	var released: Array[RigidBody3D] = []
	var blasts: Array[Vector3] = []
	var queue: Array[Vector3] = [center]
	var guard := 0
	while not queue.is_empty() and guard < 24:
		guard += 1
		var c: Vector3 = queue.pop_front()
		blasts.append(c)
		var opened := 0
		for sh in pieces.duplicate():                       # buildings in the blast come apart into cells first
			if opened >= Destruction.MAX_EXPAND_PER_BLAST or shells_open.size() >= Destruction.MAX_EXPANDED_SHELLS:
				break
			if Destruction.is_shell(sh) and sh.global_position.distance_to(c) <= radius * 0.9 + 4.0:
				Destruction.expand(self, sh)
				opened += 1
		var rel_n := 0
		for p in pieces.duplicate():
			if p.get_meta("capped", false):
				continue
			if Destruction.is_shell(p):
				continue                                        # a building we did not open this blast stays standing (never a flying whole-building slab)
			var d: float = p.global_position.distance_to(c)
			if d > radius:
				continue
			var dir: Vector3 = ((p.global_position - c) + Vector3(0, 0.6 * radius * 0.2, 0)).normalized()
			var f: float = 1.0 - d / radius
			if p.freeze:
				var bv: Vector3 = dir * power * (0.35 + 0.65 * f) * float(Destruction.profile(str(p.get_meta("mat", "masonry")))["impulse"]) + Vector3(0, 4.0, 0)
				if rel_n < Destruction.MAX_RELEASE_PER_IMPACT * 2 and active_released() + rel_n < ACTIVE_HARD:
					release(p, bv)
					released.append(p)
					rel_n += 1
				else:
					dissolve(p, bv)
			else:
				p.apply_central_impulse(dir * power * 0.4 * f * p.mass)
		for b in props:
			if not is_instance_valid(b) or not b.visible:
				continue
			var d2: float = b.global_position.distance_to(c)
			if d2 > radius or d2 < 0.01:
				continue
			var dir2: Vector3 = ((b.global_position - c) + Vector3(0, 1.0, 0)).normalized()
			b.sleeping = false
			b.apply_central_impulse(dir2 * power * 0.5 * (1.0 - d2 / radius) * b.mass)
			if b.get_meta("explosive", false) and not b.get_meta("exploded", false):
				b.set_meta("exploded", true)
				b.visible = false
				b.collision_layer = 0
				b.freeze = true
				queue.append(b.global_position)
	released.append_array(Destruction.collapse(self, released))
	for c in blasts:
		ignite_near(c, radius * 0.9, 0.75)
	return {"released": released, "blasts": blasts, "power": power, "radius": radius}

## Barrel the ragdoll just hit: detonate it (and its chain).
func detonate(b: RigidBody3D) -> Dictionary:
	if b.get_meta("exploded", false):
		return {"released": [], "blasts": []}
	b.set_meta("exploded", true)
	b.visible = false
	b.collision_layer = 0
	b.freeze = true
	var br: float = float(b.get_meta("blast_r", 9.0))
	return explode(b.global_position, br, 22.0 * br / 9.0)


# ================================================================== fire engine
## Everything that can burn registers here. The spread maths is Rules.fire_step (capped + bounded).
func register_combustible(n: Node3D) -> void:
	_fire_idx[n.get_instance_id()] = fire_nodes.size()
	fire_nodes.append(n)
	fire_pos.append(n.position)
	fire_state.append(0)
	fire_timer.append(0.0)
	fire_handle.append(-1)
	var key := Vector2i(int(floor(n.position.x / 4.0)), int(floor(n.position.z / 4.0)))
	var arr: PackedInt32Array = _fire_grid.get(key, PackedInt32Array())
	arr.append(fire_nodes.size() - 1)
	_fire_grid[key] = arr

func is_combustible(n: Node) -> bool:
	return _fire_idx.has(n.get_instance_id())

func ignite_node(n: Node3D) -> bool:
	var id: int = n.get_instance_id()
	if not _fire_idx.has(id):
		return false
	return _ignite_idx(int(_fire_idx[id]))

## Flame size from the burning object's collision box (a crate ~1, a house wall / building ~2-3).
func _fire_scale(n: Node3D) -> float:
	for ch in n.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			var sz: Vector3 = ((ch as CollisionShape3D).shape as BoxShape3D).size
			return clampf(pow(maxf(sz.x * sz.y * sz.z, 0.01), 1.0 / 3.0) * 0.55, 0.7, 3.0)
	return 1.0

func _ignite_idx(i: int) -> bool:
	if fire_state[i] != 0 or burning_count >= Rules.FIRE_CAP:
		return false
	fire_state[i] = 1
	fire_timer[i] = 0.0
	burning_count += 1
	var n: Node3D = fire_nodes[i]
	var pos: Vector3 = n.global_position + Vector3(0, 1.0, 0)
	if fx:
		fire_handle[i] = fx.flame_start(pos, n.get_instance_id(), _fire_scale(n))
	ignited.emit(n, pos)
	return true

## Light every fuel object within r of pos (probability p each). Returns how many caught.
func ignite_near(pos: Vector3, r: float, p: float = 1.0) -> int:
	var cnt: int = 0
	var c0 := Vector2i(int(floor((pos.x - r) / 4.0)), int(floor((pos.z - r) / 4.0)))
	var c1 := Vector2i(int(floor((pos.x + r) / 4.0)), int(floor((pos.z + r) / 4.0)))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var arr = _fire_grid.get(Vector2i(cx, cz))
			if arr == null:
				continue
			for i in arr:
				if fire_state[i] == 0 and (fire_nodes[i] as Node3D).global_position.distance_to(pos) <= r and (p >= 1.0 or randf() < p):
					if _ignite_idx(i):
						cnt += 1
	return cnt

func _fire_tick(dt: float) -> void:
	var res: Dictionary = Rules.fire_step(fire_pos, fire_state, fire_timer, dt, fire_spread_mult, [], _fire_grid, 4.0)
	for i in (res["ignite"] as Array):
		var n: Node3D = fire_nodes[i]
		var pos: Vector3 = n.global_position + Vector3(0, 1.0, 0)
		if fx:
			fire_handle[i] = fx.flame_start(pos, n.get_instance_id(), _fire_scale(n))
		ignited.emit(n, pos)
	for i in (res["burnt"] as Array):
		_burn_out(int(i))
	burning_count = 0
	for i in fire_state.size():
		if fire_state[i] == 1:
			burning_count += 1
			if fx and fire_handle[i] >= 0:
				fx.flame_move(fire_handle[i], (fire_nodes[i] as Node3D).global_position + Vector3(0, 1.0, 0))

func _burn_out(i: int) -> void:
	var n: Node3D = fire_nodes[i]
	if fx and fire_handle[i] >= 0:
		fx.flame_stop(fire_handle[i])
		fire_handle[i] = -1
	if not is_instance_valid(n):
		return
	var pos: Vector3 = n.global_position + Vector3(0, 1.0, 0)
	if fx:
		fx.smoke_at(pos)
	if n.has_meta("kind"):                      # a burnt timber piece gives way and collapses
		var p := n as RigidBody3D
		if p.freeze:
			release(p, Vector3(0, 1.0, 0))
	elif n.has_meta("decor"):
		break_decor(n as StaticBody3D, Vector3.UP, 6.0)
	elif n.has_meta("prop"):
		if not n.has_meta("explosive"):         # TNT is handled by main (it explodes when burnt)
			(n as RigidBody3D).visible = false
			(n as RigidBody3D).collision_layer = 0
			(n as RigidBody3D).freeze = true
	else:
		n.visible = false
		if n is StaticBody3D:
			(n as StaticBody3D).collision_layer = 0
		_burnt_static.append(n)
	burned.emit(n, pos)

func fire_reset() -> void:
	for i in fire_state.size():
		fire_state[i] = 0
		fire_timer[i] = 0.0
		fire_handle[i] = -1
	burning_count = 0
	for n in _burnt_static:
		if is_instance_valid(n):
			n.visible = true
			if n is StaticBody3D:
				(n as StaticBody3D).collision_layer = 1
	_burnt_static.clear()
	if fx:
		fx.clear_all()

# ================================================================== glass
func _glass_pane(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := _box_mesh(size, Color(0.6, 0.9, 1.0, 0.35))
	((mi.mesh as BoxMesh).material as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.add_child(mi)
	b.set_meta("mat", "glass")
	b.set_meta("glass", true)
	b.set_meta("half", size * 0.5)
	add_child(b)
	glass.append(b)
	return b

## A light static fixture (awning, sign, pole) is knocked out of the world; it comes back on reset like burnt statics.
func smash_static(b: StaticBody3D, dir: Vector3, speed: float) -> bool:
	if b.collision_layer == 0:
		return false
	b.collision_layer = 0
	b.visible = false
	_burnt_static.append(b)
	_spawn_debris(b.global_position, dir * speed * 0.3, 3)
	return true

func break_glass(b: StaticBody3D) -> bool:
	if b.collision_layer == 0:
		return false
	b.collision_layer = 0
	if b.has_meta("gi") and _glass_mm != null:
		var gi: int = int(b.get_meta("gi"))
		_glass_mm.multimesh.set_instance_transform(gi, Transform3D(Basis.from_scale(Vector3.ZERO), (_glass_xfs[gi] as Transform3D).origin))
	else:
		b.visible = false
	_broken_glass.append(b)
	return true

func _restore_glass() -> void:
	for b in _broken_glass:
		b.collision_layer = 1
		if b.has_meta("gi") and _glass_mm != null:
			var gi: int = int(b.get_meta("gi"))
			_glass_mm.multimesh.set_instance_transform(gi, _glass_xfs[gi])
		else:
			b.visible = true
	_broken_glass.clear()

# ================================================================== RAGDOLL TEST YARD
## Compact chaos lab, ~110 m long: every system gets something to hit.
func _yard_box(pos: Vector3, size: Vector3, color: Color, mat: String, basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var b := _static_box(pos, size, color)
	b.transform = Transform3D(basis, pos)
	b.set_meta("mat", mat)
	b.set_meta("half", size * 0.5)
	if basis != Basis.IDENTITY and mat == "metal":
		b.set_meta("pad", true)                 # tilted signage: a designed ricochet surface, an exemption in the destructibility audit
	return b

func _wood_house(tx: int, tz: int, w: int, d: int, floors: int, group: String) -> void:
	for f in floors:
		for i in w:
			for j in d:
				var model: String = "wall-pane-wood"
				if f == 0 and i == 0 and j == d / 2:
					model = "wall-pane-wood-door"
				elif f == 0 and i == 0:
					model = "wall-pane-wood-window"
				_piece(model, Vector3(tx + i, f, tz + j), "wall", group, Vector3.ONE, 2.2, 3.5)
	for i in w:
		for j in d:
			_piece("roof", Vector3(tx + i, floors, tz + j), "roof", group, Vector3.ONE, 2.0, 4.0)

func _dist_marker(x: float) -> void:
	var l := Label3D.new()
	l.text = "%d m" % int(x)
	l.font_size = 64
	l.pixel_size = 0.012
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(x, 0.08, -4.5)
	add_child(l)
	var line := _box_mesh(Vector3(0.3, 0.04, 9.0), Color(1, 1, 1))
	line.position = Vector3(x, 0.04, 0)
	add_child(line)

func build_yard() -> void:
	smash_push = 0.9
	for x in [20, 40, 60, 80, 100]:
		_dist_marker(float(x))
	# 1) shop front: a wall of glass panes in a timber frame (glass is cheap to break, satisfying to burst through)
	for k in 5:
		var z: float = -9.0 + 4.5 * k
		var gp := _glass_pane(Vector3(30.0, 1.9, z), Vector3(0.25, 3.4, 4.0))
		if k == 2:
			_bonus(gp, "shop", "Shop Window", 150)
	for k in 6:
		_yard_box(Vector3(30.0, 2.0, -11.25 + 4.5 * k), Vector3(0.5, 4.0, 0.5), Color(0.5, 0.32, 0.16), "wood")
	_yard_box(Vector3(30.0, 4.15, 0.0), Vector3(0.6, 0.5, 24.0), Color(0.5, 0.32, 0.16), "wood")
	# 2) trampolines (springy surfaces)
	var tp := _yard_box(Vector3(22.0, 0.3, 15.0), Vector3(7.0, 0.6, 7.0), Color(0.9, 0.2, 0.55), "trampoline")
	_bonus(tp, "tramp", "Trampoline", 100)
	_yard_box(Vector3(52.0, 0.3, -19.0), Vector3(7.0, 0.6, 7.0), Color(0.2, 0.7, 0.95), "trampoline")
	# 3) tilted metal billboard on poles: hard ricochet + sparks
	for z in [-3.0, 3.0]:
		_yard_box(Vector3(44.0, 2.4, z), Vector3(0.5, 4.8, 0.5), Color(0.35, 0.35, 0.4), "metal")
	var sign_b := _yard_box(Vector3(43.4, 6.0, 0.0), Vector3(0.4, 5.0, 8.5), Color(0.78, 0.8, 0.86), "metal", Basis(Vector3.BACK, deg_to_rad(-32.0)))
	_bonus(sign_b, "sign", "Billboard", 200)
	# 4) timber district: wood houses close together + stalls + trees (fire spreads here)
	_wood_house(32, -9, 3, 2, 1, "timber_a")
	_wood_house(36, -9, 2, 2, 2, "timber_b")
	_wood_house(36, -5, 2, 2, 1, "timber_c")
	var tb: RigidBody3D = _pieces_in("timber_b")[0]
	_bonus(tb, "timber", "Timber Hall", 250)
	for i in 4:
		_prop("detail-crate", Vector3(51.0 + i * 1.1, 0.0, -9.0), Vector3(0.75, 0.75, 0.75), 1.6)
		_prop("fence-wood", Vector3(51.0 + i * 1.6, 0.0, -11.0), Vector3(1.5, 0.9, 0.2), 1.2)
	for p in [Vector3(48, 0, -14), Vector3(56, 0, -13), Vector3(60, 0, -9), Vector3(47, 0, -2)]:
		_tree(p)
	# 5) masonry house with a pitched roof: ricochet off the roof, crack through the walls
	var stone := _building(42, 3, 3, 2, 2, "stonehouse", false, true, 1)
	if stone:
		_bonus(stone, "stonewin", "Stone Window", 150)
	# 6) TNT shack: barrels beside a wooden shack. Boom -> fire
	for k in 4:
		_tnt_barrel(70.0 + (k % 2) * 1.2, 16.0 + (k / 2) * 1.2)
	_wood_house(43, 13, 2, 2, 1, "tntshack")
	_prop("detail-crate", Vector3(68.5, 0.0, 17.0), Vector3(0.75, 0.75, 0.75), 1.6)
	# 7) elevated target: a keep tower
	var keep := _tower_stack(58, 0, 7, "keep")
	_bonus(keep, "keep", "Elevated Keep", 600)
	# 8) backstop wall (static, high-resistance masonry)
	for tz in range(-5, 6):
		for ty in 3:
			_static_kit("wall-fortified", Vector3(70, ty, tz))
	# 9) a second masonry building for secondary ricochets
	_building(50, -5, 2, 3, 2, "annex", true, true, -1)
	_scatter_scenery_yard()

func _scatter_scenery_yard() -> void:
	for p in [Vector3(8, 0, -10), Vector3(9, 0, 12), Vector3(18, 0, -14), Vector3(60, 0, 22), Vector3(78, 0, -12), Vector3(80, 0, 14)]:
		_tree(p)

func _pieces_in(group: String) -> Array:
	return groups.get(group, [])


# ================================================================== CITY KIT (used by cities.gd)
## Deterministic hash for layout variation (no randomness: a city always loads identically).
static func hsh(i: int, j: int) -> int:
	return int(((i * 73856093) ^ (j * 19349663) ^ 83492791) & 0x7fffffff) % 1000

func _cmat(c: Color) -> StandardMaterial3D:
	var key: int = c.to_rgba32()
	if not _mat_cache.has(key):
		_mat_cache[key] = _mat(c)
	return _mat_cache[key]

func _box_mesh_shared(size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _cmat(c)
	mi.mesh = bm
	return mi

## A breakable frozen block (container, panel, scaffold plank...). Behaves like the kit pieces: released by hard hits.
func _block(pos: Vector3, size: Vector3, color: Color, mat_name: String, mass: float = 3.0, tough: float = 8.0, group: String = "blocks", group_all: bool = false) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "block_%d" % pieces.size()
	b.position = pos
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.physics_material_override = _phys_stone
	b.can_sleep = true
	b.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * 0.98
	cs.shape = sh
	b.add_child(cs)
	b.add_child(_box_mesh_shared(size, color))
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
	add_child(b)
	pieces.append(b)
	if not groups.has(group):
		groups[group] = []
	(groups[group] as Array).append(b)
	if bool(Rules.MATERIALS[mat_name]["fire"]):
		register_combustible(b)
	return b

## A free rigid box prop (car, dumpster, tank, lounger...). `blast_r` > 0 makes it explosive with that radius.
func _prop_box(pos: Vector3, size: Vector3, color: Color, mat_name: String, mass: float = 4.0, blast_r: float = 0.0) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.position = pos + Vector3(0, size.y * 0.5, 0)
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.4
	b.physics_material_override = pm
	b.can_sleep = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * 0.98
	cs.shape = sh
	b.add_child(cs)
	b.add_child(_box_mesh_shared(size, color))
	b.set_meta("prop", true)
	b.set_meta("rest", b.position)
	b.set_meta("mat", mat_name)
	if blast_r > 0.0:
		b.set_meta("explosive", true)
		b.set_meta("blast_r", blast_r)
		tnt.append(b)
	add_child(b)
	b.sleeping = true
	props.append(b)
	if bool(Rules.MATERIALS[mat_name]["fire"]) or blast_r > 0.0:
		register_combustible(b)
	return b

## A wall of glass panes (cheap): one static collider per pane, ONE MultiMesh for every pane's visual.
## `along` = unit horizontal direction the wall runs, `normal` = unit horizontal direction it faces,
## `origin` = bottom centre of the wall. Panes shatter individually (break_glass).
func _glass_wall(origin: Vector3, along: Vector3, normal: Vector3, width: float, height: float, pane_w: float, pane_h: float) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	var cols: int = maxi(int(width / pane_w), 1)
	var rows: int = maxi(int(height / pane_h), 1)
	var basis := Basis(along.normalized(), Vector3.UP, normal.normalized())
	for r in rows:
		for c in cols:
			var pos: Vector3 = origin + along.normalized() * ((float(c) + 0.5 - float(cols) * 0.5) * pane_w) + Vector3.UP * ((float(r) + 0.5) * pane_h)
			var b := StaticBody3D.new()
			b.collision_layer = 1
			b.collision_mask = 0
			b.transform = Transform3D(basis, pos)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(pane_w * 0.96, pane_h * 0.96, 0.3)
			cs.shape = sh
			b.add_child(cs)
			b.set_meta("mat", "glass")
			b.set_meta("glass", true)
			b.set_meta("half", sh.size * 0.5)
			b.set_meta("gi", _glass_xfs.size())
			_glass_xfs.append(Transform3D(basis.scaled(Vector3(pane_w * 0.96, pane_h * 0.96, 0.14)), pos))
			add_child(b)
			glass.append(b)
			out.append(b)
	return out

func _finish_glass() -> void:
	if _glass_xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic = 0.4
	bm.material = m
	mm.mesh = bm
	mm.instance_count = _glass_xfs.size()
	for i in _glass_xfs.size():
		mm.set_instance_transform(i, _glass_xfs[i])
	_glass_mm = MultiMeshInstance3D.new()
	_glass_mm.multimesh = mm
	_glass_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass_mm)

## Standing palm (static, burns).
func _palm(pos: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos + Vector3(0, 3.0, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.7, 6.0, 0.7)
	cs.shape = sh
	b.add_child(cs)
	b.add_child(_box_mesh_shared(Vector3(0.6, 6.0, 0.6), Color(0.45, 0.32, 0.2)))
	var crown := _box_mesh_shared(Vector3(3.6, 0.5, 3.6), Color(0.2, 0.62, 0.28))
	crown.position = Vector3(0, 3.2, 0)
	b.add_child(crown)
	var crown2 := _box_mesh_shared(Vector3(0.5, 0.5, 5.2), Color(0.18, 0.55, 0.25))
	crown2.position = Vector3(0, 3.5, 0)
	b.add_child(crown2)
	b.set_meta("mat", "wood")
	b.set_meta("half", sh.size * 0.5)
	add_child(b)
	register_combustible(b)

## Cylinder tank (static, metal). Radial normals come from the cylinder fallback in main._surface_normal.
func _tank(pos: Vector3, r: float, h: float, color: Color) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos + Vector3(0, h * 0.5, 0)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.material = _cmat(color)
	mi.mesh = cm
	b.add_child(mi)
	b.set_meta("mat", "metal")
	add_child(b)
	return b

## Sign text that faces the launcher (-X).
func _sign_label(text: String, pos: Vector3, color: Color = Color(1, 1, 1), px: float = 0.05, facing: float = -90.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 10
	l.rotation_degrees = Vector3(0, facing, 0)
	l.position = pos
	add_child(l)
