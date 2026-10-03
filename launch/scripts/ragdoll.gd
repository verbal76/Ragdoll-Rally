class_name Ragdoll
extends Node3D
## Custom rigid-body ragdoll built from the six mesh parts of a Kenney blocky
## character (torso, head, 2 arms, 2 legs) joined with cone-twist joints.
## The node itself stays at the origin; bodies carry world transforms.

signal impact(part: RigidBody3D, other: Node, speed: float, point: Vector3)

const CHAR_SCALE := 0.6
const AIR_DRAG := 0.15        # project default linear damp (0.1) + body damp (0.05) = what G1/G2 flew with
const LETTERS := "abcdefghijklmnopqr"
const PARTS := ["torso", "head", "arm-left", "arm-right", "leg-left", "leg-right"]
const MASS := {"torso": 6.0, "head": 2.6, "arm-left": 1.1, "arm-right": 1.1, "leg-left": 1.8, "leg-right": 1.8}

var bodies: Array[RigidBody3D] = []
var rest: Array[Transform3D] = []   # per body, relative to rig origin (= torso centre)
var torso: RigidBody3D
var joint_count: int = 0
var launched: bool = false
var _air_free: bool = false      # reduced-drag flight (overdrive shots) until the first impact
var _prev_vel: Dictionary = {}

static func scene_path(letter: String) -> String:
	return "res://assets/kenney/blocky-characters/character-%s.glb" % letter

static func random_letter() -> String:
	return LETTERS[randi() % LETTERS.length()]

static func _rel_xf(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## Build all bodies and joints; the rig origin is placed at `pose`.
func build(letter: String, pose: Transform3D) -> void:
	var inst: Node3D = (load(scene_path(letter)) as PackedScene).instantiate()
	var scale_xf := Transform3D(Basis.from_scale(Vector3.ONE * CHAR_SCALE), Vector3.ZERO)
	var xf: Dictionary = {}
	var box: Dictionary = {}
	var nodes: Dictionary = {}
	for pn in PARTS:
		var m := inst.find_child(pn, true, false) as MeshInstance3D
		nodes[pn] = m
		xf[pn] = scale_xf * _rel_xf(m, inst)
		box[pn] = (xf[pn] as Transform3D) * m.mesh.get_aabb()
	for pn in PARTS:
		var m: MeshInstance3D = nodes[pn]
		m.get_parent().remove_child(m)
		m.owner = null
	var origin: Vector3 = (box["torso"] as AABB).get_center()
	var phys := PhysicsMaterial.new()
	phys.friction = 0.7
	phys.bounce = 0.25
	for pn in PARTS:
		var b: AABB = box[pn]
		var body := RigidBody3D.new()
		body.name = pn
		body.mass = MASS[pn]
		body.collision_layer = 2
		body.collision_mask = 1 | 4
		body.physics_material_override = phys
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 4
		body.linear_damp = 0.05
		body.angular_damp = 0.4 if pn == "torso" else 0.9
		body.can_sleep = true
		var r := Transform3D(Basis.IDENTITY, b.get_center() - origin)
		rest.append(r)
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		body.transform = pose * r
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b.size * 0.9
		cs.shape = sh
		body.add_child(cs)
		var mesh_xf: Transform3D = xf[pn]
		var m2: MeshInstance3D = nodes[pn]
		body.add_child(m2)
		m2.transform = Transform3D(mesh_xf.basis, mesh_xf.origin - b.get_center())
		body.body_entered.connect(_on_body_entered.bind(body))
		add_child(body)
		bodies.append(body)
		if pn == "torso":
			torso = body
	inst.free()
	# joints: anchors are node origins (shoulders/hips) and the torso top (neck)
	var torso_box: AABB = box["torso"]
	var down := Basis(Vector3.BACK, -PI / 2.0)
	var up := Basis(Vector3.BACK, PI / 2.0)
	var neck: Vector3 = Vector3(origin.x, torso_box.end.y, origin.z)
	_joint("head", neck, up, 1.0, 0.7, pose, origin)
	for pn in ["arm-left", "arm-right", "leg-left", "leg-right"]:
		var anchor: Vector3 = (xf[pn] as Transform3D).origin
		var swing: float = 1.5 if pn.begins_with("arm") else 1.15
		_joint(pn, anchor, down, swing, 0.6, pose, origin)

func _joint(part: String, anchor: Vector3, basis_local: Basis, swing: float, twist: float, pose: Transform3D, origin: Vector3) -> void:
	var j := ConeTwistJoint3D.new()
	j.name = "J_" + part
	j.transform = Transform3D(pose.basis * basis_local, pose * (anchor - origin))
	add_child(j)
	j.node_a = j.get_path_to(torso)
	j.node_b = j.get_path_to(_body(part))
	j.set("swing_span", swing)
	j.set("twist_span", twist)
	joint_count += 1

func _body(part: String) -> RigidBody3D:
	for b in bodies:
		if b.name == part:
			return b
	return null

func _physics_process(_dt: float) -> void:
	for b in bodies:
		_prev_vel[b] = b.linear_velocity

func _restore_drag() -> void:
	if _air_free:
		_air_free = false
		for b in bodies:
			b.linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
			b.linear_damp = 0.05

func _on_body_entered(other: Node, body: RigidBody3D) -> void:
	_restore_drag()
	var pv: Vector3 = _prev_vel.get(body, body.linear_velocity)
	impact.emit(body, other, pv.length(), body.global_position)

func prev_velocity(body: RigidBody3D) -> Vector3:
	return _prev_vel.get(body, body.linear_velocity)

## While aiming: teleport the whole (frozen) rig to a pose.
func set_pose(pose: Transform3D) -> void:
	for i in bodies.size():
		bodies[i].global_transform = pose * rest[i]

## `drag_scale` 1.0 = the original air drag (G1/G2 behaviour, used up to full power); below 1.0 the
## ragdoll flies with proportionally less linear drag until its first impact (overdrive shots).
func launch(velocity: Vector3, spin: Vector3, drag_scale: float = 1.0) -> void:
	launched = true
	if drag_scale < 0.999:
		_air_free = true
		for b in bodies:
			b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
			b.linear_damp = AIR_DRAG * drag_scale
	for b in bodies:
		b.freeze = false
		b.linear_velocity = velocity
		b.angular_velocity = Vector3.ZERO
	torso.angular_velocity = spin
	for b in bodies:
		if b != torso:
			b.angular_velocity = spin * 0.4

func centre() -> Vector3:
	return torso.global_position

func max_speed() -> float:
	var m: float = 0.0
	for b in bodies:
		m = maxf(m, b.linear_velocity.length())
	return m

func is_finite_and_sane() -> bool:
	for b in bodies:
		var p: Vector3 = b.global_position
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or p.length() > 2000.0:
			return false
		if b.linear_velocity.length() > 120.0:
			return false
		if p.distance_to(torso.global_position) > 6.0:
			return false
	return true
