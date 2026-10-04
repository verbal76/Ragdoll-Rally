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
const WORLD_X_MIN := -25.0
const WORLD_X_MAX := 215.0
const WORLD_Z := 130.0
const ACTIVE_CAP := 90          # max simultaneously simulated released pieces

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
var smash_push: float = 0.45            # debris launch factor (0.8 in the mayhem tuning)

func build(p_legacy: bool = false) -> void:
	legacy = p_legacy
	smash_push = 0.45 if legacy else 0.8
	_phys_stone.friction = 0.8 if legacy else 0.6
	_phys_stone.bounce = 0.12 if legacy else 0.4
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
	if not legacy:
		_fortress()
		_barn_yard()
		_watch_village()
		_harbor()
		_gate_and_keep()
		_filler()
		_deep_city()
		_dense_city()
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
	g.collision_layer = 1
	g.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9 if legacy else 0.6
	pm.bounce = 0.25 if legacy else 0.45
	g.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var gsz := Vector3(300, 2, 120) if legacy else Vector3(460, 2, 340)
	sh.size = gsz
	cs.shape = sh
	g.add_child(cs)
	g.position = Vector3(80, -1, 0) if legacy else Vector3(95, -1, 0)
	var vis := _box_mesh(gsz, Color(0.40, 0.66, 0.34))
	g.add_child(vis)
	add_child(g)
	# cobble road strip so the town reads as a place
	var road := _box_mesh(Vector3(70 if legacy else 230, 0.05, 6), Color(0.62, 0.58, 0.5))
	road.position = Vector3(36 if legacy else 90, 0.02, 0)
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
	b.set_meta("rest", b.position)
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
				_bonus(p, "window", "House Window", 150)
			_piece("wall", Vector3(11, ty, tz), "wall", "house", Vector3.ONE, 3.0, 6.5)
	for tz in [-1, 0, 1]:
		for tx in [10, 11]:
			var r := _piece("roof", Vector3(tx, 2, tz), "roof", "house", Vector3.ONE, 2.5, 5.5)
			if tx == 11 and tz == 0:
				_bonus(r, "roof", "House Roof", 100)
	# chimney on the roof
	for i in 3:
		var c := _piece("column", Vector3(11, 3.0 + i * 1.0, 1), "column", "chimney", Vector3(0.4, 1.0, 0.4), 1.0, 3.5)
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

func release(p: RigidBody3D, vel: Vector3) -> void:
	if not p.freeze:
		return
	if p.get_meta("capped", false):
		return
	p.freeze = false
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
	# stone boundary walls (collider extends high so nothing can leave the field)
	var col := Color(0.46, 0.46, 0.5)
	_static_box(Vector3(WORLD_X_MAX, 200.0, 0.0), Vector3(2.0, 400.0, WORLD_Z * 2.0 + 4.0), col, false)
	_static_box(Vector3(WORLD_X_MAX, 2.0, 0.0), Vector3(2.0, 4.0, WORLD_Z * 2.0 + 4.0), col)
	_static_box(Vector3(WORLD_X_MIN, 200.0, 0.0), Vector3(2.0, 400.0, WORLD_Z * 2.0 + 4.0), col, false)
	for sgn in [-1.0, 1.0]:
		_static_box(Vector3((WORLD_X_MAX + WORLD_X_MIN) * 0.5, 200.0, sgn * WORLD_Z), Vector3(WORLD_X_MAX - WORLD_X_MIN, 400.0, 2.0), col, false)
		_static_box(Vector3((WORLD_X_MAX + WORLD_X_MIN) * 0.5, 2.0, sgn * WORLD_Z), Vector3(WORLD_X_MAX - WORLD_X_MIN, 4.0, 2.0), col)

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
	add_child(t)

# ------------------------------------------------------ bounded active physics
func _physics_process(dt: float) -> void:
	_cap_timer += dt
	if _cap_timer >= 0.5:
		_cap_timer = 0.0
		enforce_active_cap()

func active_released() -> int:
	var n: int = 0
	for p in released_order:
		if is_instance_valid(p) and not p.freeze:
			n += 1
	return n

## Re-freeze the oldest settled released pieces so the simulation stays bounded.
func enforce_active_cap() -> void:
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
	for p in pieces:
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
	_restore_decor()

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
	var sp := _tower_stack(100, -60, 11, "spire")
	_bonus(sp, "spire", "Monastery Spire", 1500)
	_building(95, -64, 3, 3, 2, "abbey", true, false, 1)
	_building(104, -56, 2, 2, 1, "abbey2", false, true, -1)
	# --- FAR-RIGHT: harbor crane (mid-depth) and the port lighthouse (deep)
	var cr := _tower_stack(84, 38, 7, "crane")
	_bonus(cr, "crane", "Harbor Crane", 1100)
	var lh := _tower_stack(100, 56, 11, "portlight")
	_bonus(lh, "portlight", "Port Lighthouse", 1500)
	_building(94, 52, 3, 3, 2, "customs", true, false, 1)
	_building(104, 60, 2, 2, 1, "warehouse", false, true, -1)
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
	var crown := _tower_stack(126, 0, 13, "crown")
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
	add_child(b)
	decor_bodies.append(b)

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
	add_child(b)
	decor_bodies.append(b)

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
		d.collision_mask = 1 | 4
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
		for p in pieces:
			if p.get_meta("capped", false):
				continue
			var d: float = p.global_position.distance_to(c)
			if d > radius:
				continue
			var dir: Vector3 = ((p.global_position - c) + Vector3(0, 0.6 * radius * 0.2, 0)).normalized()
			var f: float = 1.0 - d / radius
			if p.freeze:
				release(p, dir * power * (0.35 + 0.65 * f) + Vector3(0, 4.0, 0))
				released.append(p)
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
	return {"released": released, "blasts": blasts}

## Barrel the ragdoll just hit: detonate it (and its chain).
func detonate(b: RigidBody3D) -> Dictionary:
	if b.get_meta("exploded", false):
		return {"released": [], "blasts": []}
	b.set_meta("exploded", true)
	b.visible = false
	b.collision_layer = 0
	b.freeze = true
	return explode(b.global_position, 9.0, 22.0)
