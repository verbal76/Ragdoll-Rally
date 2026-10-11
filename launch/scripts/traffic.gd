extends Node
## Street life: parked and driving cars (explosive, they blow up on impact like any barrel) and pedestrians that walk the streets,
## run from the human projectile as it flies near them, and die when it (or an explosion) reaches them.
## No class_name (keeps the OTA runtime fingerprint stable). Use with:  const Traffic := preload("res://scripts/traffic.gd")

signal ped_killed(pos: Vector3, dir: Vector3, ped: Node3D)

const CHAR_PATH := "res://assets/kenney/blocky-characters/character-%s.glb"
const LETTERS := "abcdefghijklmn"
const CAR_COLS: Array[Color] = [Color(0.8, 0.15, 0.15), Color(0.2, 0.35, 0.8), Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.17), Color(0.2, 0.6, 0.3), Color(0.9, 0.7, 0.1)]
const PED_SCALE := 0.6
const WALK_SPEED := 1.3
const RUN_SPEED := 6.5
const NOTICE_DIST := 34.0
const KILL_DIST := 1.5

var town: Node
var ragdoll_fn: Callable                      # returns the ragdoll torso (RigidBody3D) while it flies, else null
var peds: Array = []                          # {root, model, anim, home, pos, target, wait, state, body}
var cars: Array = []                          # {body, dir, speed, still_t, wrecked}
var _t := 0.0

func clear() -> void:
	for p in peds:
		if is_instance_valid(p["root"]):
			(p["root"] as Node).queue_free()
		if p["body"] != null and is_instance_valid(p["body"]):
			(p["body"] as Node).queue_free()
	peds.clear()
	cars.clear()

## Place cars and pedestrians on free ground. Call a couple of physics frames after the town was built.
func populate(t: Node, n_cars: int, n_peds: int) -> void:
	clear()
	town = t
	for i in 2:
		await get_tree().physics_frame
	if not is_instance_valid(town):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + int(n_cars) * 7
	var tries := 0
	while cars.size() < n_cars and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(14.0, 300.0), 0.0, rng.randf_range(-110.0, 110.0))
		if absf(p.z) < 22.0:
			continue                                    # the flight corridor stays clear (camera line of sight)
		if _free(p, Vector3(5.2, 2.4, 3.0), rng.randi() % 2 == 0):
			_make_car(p, rng)
	tries = 0
	while peds.size() < n_peds and tries < 900:
		tries += 1
		var p2 := Vector3(rng.randf_range(10.0, 310.0), 0.0, rng.randf_range(-115.0, 115.0))
		if _free(p2, Vector3(1.2, 2.0, 1.2), false):
			_make_ped(p2, rng)

func _ground(x: float, z: float) -> float:
	return town.ground_y(x, z)

## True when (x, z) is open ground: nothing standing on it within `size` (box test) and the ground is not covered by a roof.
func _free(p: Vector3, size: Vector3, rotated: bool) -> bool:
	var gy: float = _ground(p.x, p.z)
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, gy + 70.0, p.z), Vector3(p.x, gy - 2.0, p.z), 1 | 4)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty() or float((hit["position"] as Vector3).y) > gy + 0.4:
		return false
	var sq := PhysicsShapeQueryParameters3D.new()
	var bx := BoxShape3D.new()
	bx.size = size + Vector3(1.0, 0.0, 1.0)
	sq.shape = bx
	sq.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 if rotated else 0.0), Vector3(p.x, gy + size.y * 0.5 + 0.3, p.z))
	sq.collision_mask = 4
	return space.intersect_shape(sq, 1).is_empty()

func _make_car(p: Vector3, rng: RandomNumberGenerator) -> void:
	var gy: float = _ground(p.x, p.z)
	var col: Color = CAR_COLS[rng.randi() % CAR_COLS.size()]
	var b: RigidBody3D = town._prop_box(Vector3(p.x, gy, p.z), Vector3(4.4, 1.3, 2.0), col, "metal", 16.0, 6.5)
	var yaw: float = (PI * 0.5 if rng.randf() < 0.5 else 0.0) + (PI if rng.randf() < 0.5 else 0.0)
	b.rotation.y = yaw
	b.set_meta("rest_basis", b.basis)
	b.set_meta("car", true)
	# cabin, windows and wheels (cosmetic)
	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(2.3, 0.9, 1.8)
	cab.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = col.lerp(Color(0.7, 0.85, 1.0), 0.45)
	cab.material_override = cmat
	cab.position = Vector3(-0.3, 1.05, 0)
	b.add_child(cab)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.05, 0.05, 0.06)
	for wx in [-1.4, 1.4]:
		for wz in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.4
			cy.bottom_radius = 0.4
			cy.height = 0.35
			w.mesh = cy
			w.material_override = wmat
			w.rotation_degrees = Vector3(90, 0, 0)
			w.position = Vector3(wx, -0.45, wz)
			b.add_child(w)
	var driving: bool = rng.randf() < 0.35
	cars.append({"body": b, "dir": b.basis * Vector3.RIGHT, "speed": rng.randf_range(6.0, 10.0), "driving": driving, "still": 0.0, "wrecked": false})

func _make_ped(p: Vector3, rng: RandomNumberGenerator) -> void:
	var path: String = CHAR_PATH % LETTERS[rng.randi() % LETTERS.length()]
	if not ResourceLoader.exists(path):
		return
	var root := Node3D.new()
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * PED_SCALE
	root.add_child(model)
	town.add_child(root)
	var gy: float = _ground(p.x, p.z)
	root.position = Vector3(p.x, gy, p.z)
	var ap: AnimationPlayer = null
	var aps: Array = model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		ap = aps[0]
		for a in ["walk", "sprint", "idle"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
	peds.append({"root": root, "model": model, "anim": ap, "home": root.position, "target": root.position, "wait": rng.randf_range(0.0, 3.0), "state": "idle", "body": null, "cur": ""})

func _play(p: Dictionary, anim: String) -> void:
	var ap: AnimationPlayer = p["anim"]
	if ap != null and p["cur"] != anim and ap.has_animation(anim):
		p["cur"] = anim
		ap.play(anim, 0.15)

## Put everybody back for a new run.
func reset() -> void:
	for p in peds:
		if p["body"] != null and is_instance_valid(p["body"]):
			var body: RigidBody3D = p["body"]
			body.remove_child(p["model"])
			(p["root"] as Node3D).add_child(p["model"])
			(p["model"] as Node3D).transform = Transform3D(Basis.from_scale(Vector3.ONE * PED_SCALE), Vector3.ZERO)
			body.queue_free()
			p["body"] = null
		(p["root"] as Node3D).visible = true
		(p["root"] as Node3D).position = p["home"]
		p["state"] = "idle"
		p["wait"] = randf_range(0.0, 2.0)
		p["target"] = p["home"]
		p["cur"] = ""
		_play(p, "idle")
	for c in cars:
		c["wrecked"] = false
		c["still"] = 0.0

func blast(origin: Vector3, radius: float) -> void:
	for p in peds:
		if p["state"] == "dead":
			continue
		var d: Vector3 = (p["root"] as Node3D).global_position - origin
		if d.length() <= radius * 1.1:
			_kill(p, (d + Vector3(0, 2.0, 0)).normalized() * (8.0 + radius))

func _kill(p: Dictionary, vel: Vector3) -> void:
	p["state"] = "dead"
	var root: Node3D = p["root"]
	var pos: Vector3 = root.global_position + Vector3(0, 0.9, 0)
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | 4
	body.mass = 3.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	cs.shape = cap
	body.add_child(cs)
	town.add_child(body)
	body.global_position = pos
	var model: Node3D = p["model"]
	root.remove_child(model)
	body.add_child(model)
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * PED_SCALE), Vector3(0, -0.9, 0))
	body.linear_velocity = vel
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
	p["body"] = body
	p["die_t"] = 0.0
	if p["anim"] != null and (p["anim"] as AnimationPlayer).has_animation("die"):
		(p["anim"] as AnimationPlayer).play("die")
	ped_killed.emit(pos, vel.normalized(), root)

func _physics_process(dt: float) -> void:
	if town == null or not is_instance_valid(town):
		return
	_t += dt
	var rb: RigidBody3D = ragdoll_fn.call() if ragdoll_fn.is_valid() else null
	var rp := Vector3.ZERO
	var rv := Vector3.ZERO
	if rb != null and is_instance_valid(rb):
		rp = rb.global_position
		rv = rb.linear_velocity
	for p in peds:
		if p["state"] == "dead":
			p["die_t"] = float(p["die_t"]) + dt
			var body: RigidBody3D = p["body"]
			if body != null and is_instance_valid(body) and float(p["die_t"]) > 4.0 and not body.freeze:
				body.freeze = true
			continue
		var root: Node3D = p["root"]
		var pos: Vector3 = root.position
		var flee := false
		var away := Vector3.ZERO
		if rb != null:
			var d: Vector3 = pos - rp
			var dh := Vector3(d.x, 0.0, d.z)
			var rvh := Vector3(rv.x, 0.0, rv.z)
			if dh.length() < KILL_DIST and absf(rp.y - pos.y) < 3.2 and rv.length() > 3.0:
				_kill(p, rv * 0.5 + Vector3(0, 4.0, 0))
				continue
			if dh.length() < NOTICE_DIST and (rvh.length() > 4.0 or dh.length() < 14.0):
				flee = true
				var perp := Vector3(-rvh.z, 0.0, rvh.x).normalized()
				if perp.dot(dh) < 0.0:
					perp = -perp
				away = (perp + dh.normalized() * 0.6).normalized() if rvh.length() > 1.0 else dh.normalized()
		var dir := Vector3.ZERO
		var spd := 0.0
		if flee:
			dir = away
			spd = RUN_SPEED
			_play(p, "sprint")
			p["state"] = "flee"
		else:
			if p["state"] == "flee":
				p["state"] = "idle"
				p["wait"] = 0.5
			if p["state"] == "idle":
				p["wait"] = float(p["wait"]) - dt
				_play(p, "idle")
				if float(p["wait"]) <= 0.0:
					var ang: float = randf() * TAU
					var tgt: Vector3 = pos + Vector3(cos(ang), 0, sin(ang)) * randf_range(5.0, 14.0)
					p["target"] = tgt
					p["state"] = "walk"
			if p["state"] == "walk":
				var to: Vector3 = (p["target"] as Vector3) - pos
				to.y = 0.0
				if to.length() < 0.6:
					p["state"] = "idle"
					p["wait"] = randf_range(1.0, 4.0)
				else:
					dir = to.normalized()
					spd = WALK_SPEED
					_play(p, "walk")
		if spd > 0.0:
			var step: Vector3 = dir * spd * dt
			var np: Vector3 = pos + step
			if _blocked(pos, np):
				if flee:
					var side := Vector3(-dir.z, 0, dir.x)
					np = pos + side * spd * dt
					if _blocked(pos, np):
						np = pos
				else:
					np = pos
					p["state"] = "idle"
					p["wait"] = 0.3
			np.x = clampf(np.x, 4.0, 322.0)
			np.z = clampf(np.z, -122.0, 122.0)
			np.y = _ground(np.x, np.z)
			root.position = np
			root.rotation.y = atan2(dir.x, dir.z)
	# driving cars roll during a run (while the projectile is in flight) until something stops them
	for c in cars:
		if rb == null or not c["driving"] or c["wrecked"]:
			continue
		var b: RigidBody3D = c["body"]
		if not is_instance_valid(b) or not b.visible:
			c["wrecked"] = true
			continue
		b.sleeping = false
		var d3: Vector3 = c["dir"]
		var spd2: float = c["speed"]
		b.linear_velocity = Vector3(d3.x * spd2, b.linear_velocity.y, d3.z * spd2)
		b.angular_velocity = Vector3(0, 0, 0)
		var lp: Vector3 = b.get_meta("last_p", b.global_position)
		var real: float = (b.global_position - lp).length() / maxf(dt, 0.001)
		c["still"] = float(c["still"]) + dt if real < 0.6 else 0.0
		b.set_meta("last_p", b.global_position)
		if float(c["still"]) > 1.0:
			c["wrecked"] = true

func _blocked(a: Vector3, b: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.8, 0), b + Vector3(0, 0.8, 0) + (b - a).normalized() * 0.4, 1 | 4)
	return not space.intersect_ray(q).is_empty()
