class_name Town
extends Node3D
## The single playground: launcher + a few structures made of Kenney Retro
## Fantasy Kit pieces. Pieces start frozen (static) and switch to physics when
## struck hard enough (cheap "destruction"). Props are ordinary rigid bodies.

signal piece_released(piece: RigidBody3D)

const KIT := "res://assets/kenney/retro-fantasy-kit/%s.glb"
const S := 1.5          # kit unit -> metres
const PROP_S := 2.5     # detail props are tiny in the kit
const POLE_TOP := Vector3(0.0, 3.4, 0.0)
const POLE_Z := 1.7
const TARGET_X := 58.0  # bullseye centre

var pieces: Array[RigidBody3D] = []
var props: Array[RigidBody3D] = []
var groups: Dictionary = {}
var used_assets: Array[String] = []
var _phys_stone := PhysicsMaterial.new()
var band_l: MeshInstance3D
var band_r: MeshInstance3D

func build() -> void:
	_phys_stone.friction = 0.8
	_phys_stone.bounce = 0.12
	_ground()
	_launcher()
	_house()
	_tower()
	_small_house()
	_barrier_wall()
	_crates()
	_castle()
	_scenery()
	_bullseye()

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
	g.collision_layer = 1
	g.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.25
	g.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(300, 2, 120)
	cs.shape = sh
	g.add_child(cs)
	g.position = Vector3(80, -1, 0)
	var vis := _box_mesh(Vector3(300, 2, 120), Color(0.40, 0.66, 0.34))
	g.add_child(vis)
	add_child(g)
	# cobble road strip so the town reads as a place
	var road := _box_mesh(Vector3(70, 0.05, 6), Color(0.62, 0.58, 0.5))
	road.position = Vector3(36, 0.02, 0)
	add_child(road)

func _launcher() -> void:
	var wood := Color(0.55, 0.34, 0.18)
	var base := _box_mesh(Vector3(3.0, 0.5, 4.4), wood)
	base.position = Vector3(-0.2, 0.25, 0)
	add_child(base)
	for z in [-POLE_Z, POLE_Z]:
		var pole := _box_mesh(Vector3(0.4, POLE_TOP.y, 0.4), wood)
		pole.position = Vector3(0, POLE_TOP.y * 0.5, z)
		add_child(pole)
		var knob := _box_mesh(Vector3(0.6, 0.3, 0.6), Color(0.8, 0.2, 0.2))
		knob.position = Vector3(0, POLE_TOP.y + 0.1, z)
		add_child(knob)
	band_l = _box_mesh(Vector3(0.1, 0.1, 1.0), Color(0.9, 0.15, 0.2))
	band_r = _box_mesh(Vector3(0.1, 0.1, 1.0), Color(0.9, 0.15, 0.2))
	add_child(band_l)
	add_child(band_r)

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
	b.set_meta("kind", kind)
	b.set_meta("group", group)
	b.set_meta("tough", tough)
	b.set_meta("frozen_piece", true)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	add_child(b)
	pieces.append(b)
	if not groups.has(group):
		groups[group] = []
	(groups[group] as Array).append(b)
	return b

func _static_kit(model: String, tile: Vector3, size: Vector3 = Vector3.ONE) -> StaticBody3D:
	var h: float = size.y * S
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.physics_material_override = _phys_stone
	b.position = Vector3(tile.x * S, tile.y * S + h * 0.5, tile.z * S)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size * S
	cs.shape = sh
	b.add_child(cs)
	var m := _kit(model)
	m.scale = Vector3.ONE * S
	m.position = Vector3(0, -h * 0.5, 0)
	b.add_child(m)
	add_child(b)
	return b

func _prop(model: String, pos: Vector3, real_size: Vector3, mass: float, scale_mul: float = PROP_S) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.position = pos + Vector3(0, real_size.y * 0.5, 0)
	b.mass = mass
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.3
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
	add_child(b)
	b.sleeping = true
	props.append(b)
	return b

# --------------------------------------------------------------- structures
func _house() -> void:
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
			var p := _piece(fm, Vector3(10, ty, tz), "wall", "house", Vector3.ONE, 3.0, tough)
			if fm == "wall-window":
				p.set_meta("bonus", {"name": "WINDOW!", "pts": 300, "key": "window"})
			_piece("wall", Vector3(11, ty, tz), "wall", "house", Vector3.ONE, 3.0, 6.5)
	for tz in [-1, 0, 1]:
		for tx in [10, 11]:
			var r := _piece("roof", Vector3(tx, 2, tz), "roof", "house", Vector3.ONE, 2.5, 5.5)
			if tx == 11 and tz == 0:
				r.set_meta("bonus", {"name": "ROOF!", "pts": 100, "key": "roof"})
	# chimney on the roof
	for i in 3:
		var c := _piece("column", Vector3(11, 3.0 + i * 1.0, 1), "column", "chimney", Vector3(0.4, 1.0, 0.4), 1.0, 3.5)
		c.set_meta("group_all", true)
		if i == 2:
			c.set_meta("bonus", {"name": "CHIMNEY!", "pts": 250, "key": "chimney"})

func _tower() -> void:
	var tz: float = -4.0
	var tx: float = 17.0
	var names := ["tower-base", "tower", "tower", "tower", "tower-top"]
	for i in names.size():
		var sz := Vector3(1.0, 1.0, 1.0)
		var p := _piece(names[i], Vector3(tx, i, tz), "tower", "tower", sz, 4.0, 4.0)
		p.set_meta("group_all", true)
		if i == names.size() - 1:
			p.set_meta("bonus", {"name": "TOWER TOPPLED!", "pts": 300, "key": "tower"})

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
	var cols := [Color(0.9, 0.15, 0.15), Color(0.97, 0.97, 0.97), Color(0.9, 0.15, 0.15), Color(0.97, 0.97, 0.97)]
	for i in 4:
		var d := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r: float = 8.0 - i * 2.0
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.04
		cm.material = _mat(cols[i])
		d.mesh = cm
		d.position = Vector3(TARGET_X, 0.03 + i * 0.01, 0)
		add_child(d)

# --------------------------------------------------------------- destruction
func frozen_count() -> int:
	var n: int = 0
	for p in pieces:
		if p.freeze:
			n += 1
	return n

func release(p: RigidBody3D, vel: Vector3) -> void:
	if not p.freeze:
		return
	p.freeze = false
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
		if not p.freeze:
			continue
		var d: float = p.global_position.distance_to(hit_pos)
		var same: bool = all_group and p.get_meta("group", "") == group
		if same or d <= radius:
			var fall: float = 1.0 - clampf(d / maxf(radius, 0.01), 0.0, 1.0) * 0.6
			var v: Vector3 = dir * speed * 0.45 * fall + (p.global_position - hit_pos).normalized() * 2.0 + Vector3(0, 2.0, 0)
			release(p, v)
			out.append(p)
	return out
