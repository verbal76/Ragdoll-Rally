extends RefCounted
## Collision-safe chase camera. The camera is a small sphere: it may never end up inside terrain, a wall, a roof or a standing
## building, and it must keep a line of sight to what it is following. Moving debris and the ragdoll never block it (only standing
## geometry does), and a building that has just been punched through stops blocking the instant its pieces are released.
## Use with:  const CamSafe := preload("res://scripts/cam_safe.gd")

const MASK := 1 | 4                      # terrain / static solids (1) and frozen building pieces (4)
const RADIUS := 0.85                     # camera collision sphere
const MIN_DIST := 2.2                    # never closer to the focus than this (the ragdoll must stay in frame)
const SKIN := 0.35

static var _sphere: SphereShape3D = null

static func _blocks(c: Object) -> bool:
	if c is RigidBody3D:
		return (c as RigidBody3D).freeze            # released / flying pieces do not block the lens
	return c != null

## First blocking hit on the segment a->b for a sphere of `radius`: returns the travel fraction 0..1 (1 = clear).
static func clear_fraction(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, radius: float, exclude: Array = []) -> float:
	if _sphere == null:
		_sphere = SphereShape3D.new()
	_sphere.radius = radius
	var ex: Array[RID] = []
	for e in exclude:
		ex.append(e)
	for i in 4:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _sphere
		q.transform = Transform3D(Basis.IDENTITY, a)
		q.motion = b - a
		q.collision_mask = MASK
		q.exclude = ex
		var m: PackedFloat32Array = space.cast_motion(q)
		if m.size() < 2 or m[0] >= 1.0:
			return 1.0
		var hit_at: Vector3 = a + (b - a) * m[1]
		var rest := PhysicsShapeQueryParameters3D.new()
		rest.shape = _sphere
		rest.transform = Transform3D(Basis.IDENTITY, hit_at)
		rest.collision_mask = MASK
		rest.exclude = ex
		rest.margin = 0.05
		var cand: Array[Dictionary] = space.intersect_shape(rest, 4)
		var blocker := false
		for r in cand:
			if _blocks(r["collider"]):
				blocker = true
			else:
				ex.append(r["rid"])
		if blocker or cand.is_empty():
			return m[0]
	return 1.0

## True when `p` (camera sphere centre) overlaps standing geometry.
static func inside_solid(space: PhysicsDirectSpaceState3D, p: Vector3, radius: float = RADIUS) -> bool:
	if _sphere == null:
		_sphere = SphereShape3D.new()
	_sphere.radius = radius * 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = MASK
	for r in space.intersect_shape(q, 6):
		if _blocks(r["collider"]):
			return true
	return false

## Desired camera position -> a safe one. Pulls the camera in along the focus->desired line when something stands in the way; if
## that leaves it jammed against (or inside) a structure, tries lifted and top-down positions until one has a clear line of
## sight and is not inside anything. `exclude` = RIDs that never block (the ragdoll's own bodies).
static func resolve(space: PhysicsDirectSpaceState3D, focus: Vector3, desired: Vector3, exclude: Array = [], radius: float = RADIUS) -> Vector3:
	var cands: Array[Vector3] = [desired, desired + Vector3(0, 5.0, 0), desired + Vector3(0, 12.0, 0), focus + Vector3(0, 11.0, 0) + (desired - focus).slide(Vector3.UP).normalized() * 3.0]
	var best: Vector3 = focus + Vector3(0, 14.0, 0)
	var best_score: float = -1.0
	for c in cands:
		var dist: float = focus.distance_to(c)
		if dist < 0.01:
			continue
		var f: float = clear_fraction(space, focus, c, radius, exclude)
		var p: Vector3 = c
		if f < 1.0:
			p = focus + (c - focus) * (maxf(f * dist - SKIN, 0.0) / dist)
		var d2: float = focus.distance_to(p)
		if d2 >= MIN_DIST and not inside_solid(space, p, radius):
			return p                                    # first candidate that is both close enough and clear
		var score: float = d2 if not inside_solid(space, p, radius) else d2 * 0.1
		if score > best_score:
			best_score = score
			best = p
	return best
