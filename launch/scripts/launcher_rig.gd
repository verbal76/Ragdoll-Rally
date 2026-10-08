extends Node3D
## Visual rig for one launcher: simple, readable primitives (catapult arm, cannon barrel, artillery tube, railgun coils) that
## point where the player aims, recoil/swing when fired and glow while the railgun charges. The slingshot keeps the original
## posts and bands built by Town. The rig is cosmetic only (no collision); gameplay lives in main.gd / launchers.gd.
## Use with:  const LauncherRig := preload("res://scripts/launcher_rig.gd")

var id: String = ""
var _barrel: Node3D
var _arm: Node3D
var _coils: Array[MeshInstance3D] = []
var _recoil: float = 0.0
var _swing: float = 0.0
var _glow: float = 0.0
var _dir: Vector3 = Vector3.RIGHT

static func _mesh(sz: Vector3, c: Color, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
	bm.material = m
	mi.mesh = bm
	return mi

static func _cyl(r: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.4
	cm.material = m
	mi.mesh = cm
	return mi

func build(p_id: String) -> void:
	id = p_id
	var steel := Color(0.34, 0.36, 0.40)
	var wood := Color(0.55, 0.34, 0.18)
	match id:
		"catapult":
			var base := _mesh(Vector3(4.2, 0.6, 3.6), wood)
			base.position = Vector3(-0.4, 0.3, 0)
			add_child(base)
			for z in [-1.4, 1.4]:
				var post := _mesh(Vector3(0.5, 3.0, 0.5), wood)
				post.position = Vector3(0, 1.8, z)
				add_child(post)
			_arm = Node3D.new()
			_arm.position = Vector3(0, 3.2, 0)
			var beam := _mesh(Vector3(6.4, 0.5, 0.6), wood.darkened(0.1))
			beam.position = Vector3(-2.2, 0, 0)
			_arm.add_child(beam)
			var cup := _mesh(Vector3(1.4, 0.4, 1.8), Color(0.35, 0.22, 0.12))
			cup.position = Vector3(-5.2, 0.4, 0)
			_arm.add_child(cup)
			add_child(_arm)
			_arm.rotation.z = deg_to_rad(-62.0)
		"cannon", "artillery", "railgun":
			var base2 := _mesh(Vector3(4.2, 0.7, 3.6), steel.darkened(0.2))
			base2.position = Vector3(-0.3, 0.35, 0)
			add_child(base2)
			var mount := _mesh(Vector3(1.4, 1.4, 2.4), steel)
			mount.position = Vector3(-0.2, 1.3, 0)
			add_child(mount)
			_barrel = Node3D.new()
			_barrel.position = Vector3(0, 2.3, 0)
			add_child(_barrel)
			var len: float = 6.5 if id == "railgun" else (5.2 if id == "artillery" else 4.2)
			var rad: float = 0.55 if id == "artillery" else (0.38 if id == "railgun" else 0.5)
			var tube := _cyl(rad, len, steel if id != "railgun" else Color(0.22, 0.26, 0.34))
			tube.rotation.z = PI * 0.5                          # cylinder axis -> +X (barrel forward)
			tube.position = Vector3(len * 0.5 - 1.0, 0, 0)
			_barrel.add_child(tube)
			if id == "railgun":
				for i in 5:
					var coil := _mesh(Vector3(0.28, 1.5, 1.5), Color(0.3, 0.8, 1.0), true)
					coil.position = Vector3(float(i) * 1.15 - 0.4, 0, 0)
					_barrel.add_child(coil)
					_coils.append(coil)
			elif id == "artillery":
				var brake := _cyl(0.72, 0.5, steel.darkened(0.15))
				brake.rotation.z = PI * 0.5
				brake.position = Vector3(len - 1.0, 0, 0)
				_barrel.add_child(brake)
	set_aim(Vector3.RIGHT)

## Point the rig along the world direction `dir`.
func set_aim(dir: Vector3) -> void:
	_dir = dir.normalized()
	if _barrel != null:
		var yaw: float = atan2(-_dir.z, _dir.x)
		var pitch: float = asin(clampf(_dir.y, -1.0, 1.0))
		_barrel.rotation = Vector3(0, yaw, pitch)
		_barrel.rotation.y = yaw
		_barrel.basis = Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), pitch)

func fire_anim() -> void:
	_recoil = 1.0
	_swing = 1.0

func set_charge(k: float) -> void:
	_glow = clampf(k, 0.0, 1.0)

func _process(dt: float) -> void:
	_recoil = maxf(_recoil - dt * 2.4, 0.0)
	_swing = maxf(_swing - dt * 1.6, 0.0)
	if _barrel != null:
		var back: float = _recoil * _recoil * (1.4 if id == "artillery" else 0.9)
		_barrel.position = Vector3(0, 2.3, 0) - _dir * back * 0.6
	if _arm != null:
		_arm.rotation.z = lerpf(deg_to_rad(-62.0), deg_to_rad(40.0), 1.0 - _swing) if _swing > 0.0 else deg_to_rad(-62.0)
	for i in _coils.size():
		var c: MeshInstance3D = _coils[i]
		var wave: float = clampf(_glow * 1.4 - float(i) * 0.12, 0.0, 1.0)
		((c.mesh as BoxMesh).material as StandardMaterial3D).emission_energy_multiplier = wave * 6.0 + _recoil * 4.0
