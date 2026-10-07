extends RefCounted
## Reusable destruction architecture (v15 mayhem pass).
##
## Buildings are authored as ONE cheap frozen "shell" body (a visual + a box collider). A shell carries a `shell` meta: a Callable
## that returns the plan of its cells (offset, size, mesh, material, grid index). The cells are only built, as frozen rigid bodies
## in the shell's exact pose, the first time something hard enough hits (or blasts) the shell. So a whole city costs one body per
## building segment until the player actually wrecks something, and a wrecked building is a few dozen real bodies, not thousands.
##
## Impact energy decides everything (Rules.punch_*): the ragdoll walks along its path through the frozen pieces, paying each
## piece's cost out of its energy budget; broken pieces are released, the rest of the building is left standing or collapses
## where its support was removed. Pieces over the active-body budget are *dissolved* into pooled particle debris instead of
## becoming rigid bodies: the player sees a shower of fragments while the physics only simulates the focal pieces.
##
## Per-material tuning lives in PROFILES (one place, data only), so a new material or a new board needs no code.
## Use with:  const Destruction := preload("res://scripts/destruction.gd")

const Rules := preload("res://scripts/rules.gd")

const MAX_RELEASE_PER_IMPACT := 56      # rigid bodies one impact may free; the rest of the broken set dissolves into debris
const MAX_EXPANDED_SHELLS := 40         # expanded buildings per run (each keeps its cells alive until reset)
const MAX_PATH := 70.0

## strength: multiplier on a cell's toughness vs. its parent shell; cell_tough as fraction of shell tough; chunk_mass: mass
## fraction; impulse: debris launch factor; explosive: blast susceptibility (radius multiplier for being released);
## collapse: unsupported cells fall; debris_life: seconds a settled chunk stays simulated before it freezes into the aftermath.
const PROFILES := {
	"masonry": {"cell_tough": 0.62, "chunk_mass": 1.0, "impulse": 1.0, "explosive": 1.0, "collapse": true, "debris_life": 12.0, "crater_resist": 1.0},
	"wood": {"cell_tough": 0.55, "chunk_mass": 0.5, "impulse": 1.15, "explosive": 1.3, "collapse": true, "debris_life": 10.0, "crater_resist": 0.7},
	"metal": {"cell_tough": 0.7, "chunk_mass": 1.3, "impulse": 0.8, "explosive": 0.8, "collapse": false, "debris_life": 14.0, "crater_resist": 1.4},
	"roof": {"cell_tough": 0.6, "chunk_mass": 0.5, "impulse": 1.2, "explosive": 1.3, "collapse": true, "debris_life": 10.0, "crater_resist": 0.7},
	"canvas": {"cell_tough": 0.5, "chunk_mass": 0.2, "impulse": 1.4, "explosive": 1.5, "collapse": true, "debris_life": 8.0, "crater_resist": 0.4},
}

static func profile(mat: String) -> Dictionary:
	return PROFILES.get(mat, PROFILES["masonry"])

# ------------------------------------------------------------------------------------------------ authoring
## Marks a frozen block as a shell. `builder` is a Callable returning Array[Dictionary] of cells:
##   {off: Vector3 (centre, shell-local), size: Vector3, mesh: Mesh|null (null = box), moff: Vector3, mrot: float, mscale: Vector3,
##    mat: Material, idx: Vector3i (column i, floor f, column k), kind: String}
static func register_shell(body: RigidBody3D, builder: Callable, n_cells: int) -> void:
	body.set_meta("shell", builder)
	body.set_meta("shell_n", n_cells)

static func is_shell(b: Object) -> bool:
	return b != null and b.has_meta("shell") and not b.has_meta("shell_open")

## Cells of a plain box split nx x ny x nz (for blocks without kit meshes). Mesh = the parent's material, world-triplanar friendly.
static func box_cells(size: Vector3, mat: Material, n: Vector3i, kind: String = "wall") -> Array:
	var out: Array = []
	var cs := Vector3(size.x / float(n.x), size.y / float(n.y), size.z / float(n.z))
	for f in n.y:
		for i in n.x:
			for k in n.z:
				out.append({
					"off": Vector3((float(i) + 0.5) * cs.x - size.x * 0.5, (float(f) + 0.5) * cs.y - size.y * 0.5, (float(k) + 0.5) * cs.z - size.z * 0.5),
					"size": cs, "mesh": null, "moff": Vector3.ZERO, "mrot": 0.0, "mscale": Vector3.ONE, "mat": mat,
					"idx": Vector3i(i, f, k), "kind": kind})
	return out

# ------------------------------------------------------------------------------------------------ expansion
static func _cell_body(t, shell: RigidBody3D, c: Dictionary, n: int) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "%s_c%d" % [shell.name, n]
	var size: Vector3 = c["size"]
	b.mass = maxf(shell.mass * (size.x * size.y * size.z) / maxf(_shell_volume(shell), 0.01), 0.4) * float(profile(str(shell.get_meta("mat", "masonry")))["chunk_mass"])
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
	if c["mesh"] == null:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	else:
		mi.mesh = c["mesh"]
		mi.scale = c["mscale"]
		mi.rotation.y = float(c["mrot"])
		mi.position = c["moff"]
	mi.material_override = c["mat"]
	b.add_child(mi)
	b.transform = shell.transform * Transform3D(Basis.IDENTITY, c["off"])
	var mat: String = str(shell.get_meta("mat", "masonry"))
	b.set_meta("rest", b.position)
	b.set_meta("rest_basis", b.basis)
	b.set_meta("kind", c.get("kind", "wall"))
	b.set_meta("group", shell.get_meta("group", ""))
	b.set_meta("tough", float(shell.get_meta("tough", 6.0)) * float(profile(mat)["cell_tough"]))
	b.set_meta("frozen_piece", true)
	b.set_meta("mat", mat)
	b.set_meta("shell_of", shell)
	b.set_meta("cidx", c["idx"])
	b.set_meta("half", size * 0.5)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	return b

static func _shell_volume(shell: RigidBody3D) -> float:
	if shell.has_meta("shell_vol"):
		return float(shell.get_meta("shell_vol"))
	var v := 1.0
	for ch in shell.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			var sz: Vector3 = ((ch as CollisionShape3D).shape as BoxShape3D).size
			v = sz.x * sz.y * sz.z
	shell.set_meta("shell_vol", v)
	return v

## Replaces a shell by its frozen cells. Cells are cached on the shell, so a reset + second expansion costs nothing.
static func expand(t, shell: RigidBody3D) -> Array:
	if not shell.has_meta("shell") or shell.has_meta("shell_open"):
		return shell.get_meta("shell_cells", []) if shell.has_meta("shell_open") else []
	var cells: Array = []
	if shell.has_meta("shell_cells"):
		cells = shell.get_meta("shell_cells")
	else:
		var plan: Array = (shell.get_meta("shell") as Callable).call()
		var n := 0
		for c in plan:
			var cb: RigidBody3D = _cell_body(t, shell, c, n)
			n += 1
			t.add_child(cb)
			t.cell_register(cb)
			cells.append(cb)
		shell.set_meta("shell_cells", cells)
	shell.set_meta("shell_open", true)
	shell.collision_layer = 0
	shell.visible = false
	t.pieces.erase(shell)
	var g: String = str(shell.get_meta("group", ""))
	if t.groups.has(g):
		(t.groups[g] as Array).erase(shell)
	var was_burning: bool = t.fire_state_of(shell) == 1
	t.fire_retire(shell)
	t.shells_open.append(shell)
	for cb in cells:
		var c3 := cb as RigidBody3D
		c3.collision_layer = 4
		c3.visible = true
		c3.freeze = true
		c3.position = c3.get_meta("rest")
		c3.basis = c3.get_meta("rest_basis")
		t.pieces.append(c3)
		if not t.groups.has(g):
			t.groups[g] = []
		(t.groups[g] as Array).append(c3)
	if was_burning:
		for cb in cells:
			t.ignite_node(cb as Node3D)
	return cells

## Undo for a run reset: shells come back, cells go dormant (kept for reuse).
static func restore_all(t) -> void:
	for shell in t.shells_open:
		if not is_instance_valid(shell):
			continue
		var s := shell as RigidBody3D
		s.remove_meta("shell_open")
		s.collision_layer = 4
		s.visible = true
		var g: String = str(s.get_meta("group", ""))
		if not t.pieces.has(s):
			t.pieces.append(s)
		if t.groups.has(g) and not (t.groups[g] as Array).has(s):
			(t.groups[g] as Array).append(s)
		for cb in (s.get_meta("shell_cells", []) as Array):
			var c := cb as RigidBody3D
			c.freeze = true
			c.linear_velocity = Vector3.ZERO
			c.angular_velocity = Vector3.ZERO
			c.collision_layer = 0
			c.visible = false
			c.remove_meta("capped")
			c.set_meta("dissolved", false)
			t.pieces.erase(c)
			if t.groups.has(g):
				(t.groups[g] as Array).erase(c)
		t.fire_unretire(s)
	t.shells_open.clear()

# ------------------------------------------------------------------------------------------------ the punch
static func _radius(p: RigidBody3D) -> float:
	if p.has_meta("rad"):
		return float(p.get_meta("rad"))
	var r := 1.0
	for ch in p.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			r = ((ch as CollisionShape3D).shape as BoxShape3D).size.length() * 0.5
	p.set_meta("rad", r)
	return r

## The ragdoll hit `hit` at `pos` travelling along `dir`. `effk` = speed * impact_power * destruct_k. Walks the path through the
## frozen pieces and releases what the energy pays for. Returns
##   {"released": Array[RigidBody3D], "dissolved": Array, "keep": float, "blocked": bool, "n": int, "exit": Vector3, "left": float}
## `released` are the bodies that became dynamic; the caller scores them and spawns the effects.
static func punch(t, hit: RigidBody3D, pos: Vector3, dir: Vector3, effk: float, push: float) -> Dictionary:
	var res := {"released": [], "dissolved": [], "keep": 0.0, "blocked": true, "n": 0, "exit": pos, "left": 0.0}
	if hit == null:
		return res
	var start: RigidBody3D = hit
	if is_shell(hit):
		if effk < float(hit.get_meta("tough", 6.0)):
			return res
		if t.shells_open.size() < MAX_EXPANDED_SHELLS:
			expand(t, hit)
			start = _nearest_piece(t, hit, pos)
		else:
			start = hit                                 # budget: the building falls as one big chunk instead
	if start == null or not start.freeze:
		return res
	var d: Vector3 = dir.normalized()
	var reach: float = clampf(12.0 + 0.12 * effk, 12.0, MAX_PATH)
	var tube: float = clampf(1.3 + 0.012 * effk, 1.3, 4.0)
	var path: Array = []                                # [along, piece]
	for p in t.pieces:
		if not p.freeze or p.get_meta("capped", false):
			continue
		var v: Vector3 = p.global_position - pos
		var along: float = v.dot(d)
		var r: float = _radius(p)
		if along < -r * 0.6 or along > reach + r:
			continue
		var lat: float = (v - d * along).length()
		if lat <= tube + r * 0.6:
			path.append([along, p])
	if not path.any(func(e): return e[1] == start):
		path.append([0.0, start])
	path.sort_custom(func(a, b): return a[0] < b[0])
	# the contact piece is always first: whatever the ragdoll touched must give way before anything behind it
	var ordered: Array = [start]
	for e in path:
		if e[1] != start:
			ordered.append(e[1])
	var costs: Array = []
	for p in ordered:
		costs.append(Rules.piece_cost(float((p as RigidBody3D).get_meta("tough", 6.0))))
	var walk: Dictionary = Rules.punch_walk(Rules.punch_budget(effk), costs)
	var n: int = int(walk["n"])
	res["keep"] = float(walk["keep"])
	res["blocked"] = bool(walk["blocked"])
	res["left"] = float(walk["left"])
	res["n"] = n
	var rel: Array = []
	var dissolved: Array = []
	var last_pos: Vector3 = pos
	for i in n:
		var p := ordered[i] as RigidBody3D
		var mat: String = str(p.get_meta("mat", "masonry"))
		var prof: Dictionary = profile(mat)
		var v: Vector3 = d * minf(effk * push, 55.0) * float(prof["impulse"]) * (1.0 - 0.35 * float(i) / maxf(float(n), 1.0))
		v += (p.global_position - pos).slide(d).normalized() * 3.0 + Vector3(0, 2.5, 0)
		last_pos = p.global_position
		if rel.size() < MAX_RELEASE_PER_IMPACT and t.active_released() + rel.size() < t.ACTIVE_HARD:
			t.release(p, v)
			rel.append(p)
		else:
			t.dissolve(p, v)
			dissolved.append(p)
	# cavity: pieces just beside the tunnel crack loose at lower speed (the hole is wider than the ragdoll)
	var cav: float = clampf(tube * 1.5 + 0.6, 2.0, 6.5)
	for p in t.pieces:
		if not p.freeze or p.get_meta("capped", false) or n == 0:
			continue
		if rel.size() >= MAX_RELEASE_PER_IMPACT:
			break
		var dd: float = p.global_position.distance_to(pos.lerp(last_pos, 0.5))
		var span: float = pos.distance_to(last_pos) * 0.5 + cav
		if dd <= span:
			var tough: float = float(p.get_meta("tough", 6.0))
			if effk >= tough * 1.4:
				t.release(p, (p.global_position - pos).normalized() * 3.0 + d * effk * push * 0.25 + Vector3(0, 2.0, 0))
				rel.append(p)
	collapse(t, rel)
	res["released"] = rel
	res["dissolved"] = dissolved
	res["exit"] = last_pos
	return res

static func _nearest_piece(t, shell: RigidBody3D, pos: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var bd := 1e9
	for cb in (shell.get_meta("shell_cells", []) as Array):
		var c := cb as RigidBody3D
		var dd: float = c.global_position.distance_squared_to(pos)
		if dd < bd:
			bd = dd
			best = c
	return best

# ------------------------------------------------------------------------------------------------ support / collapse
## Cells whose supporting column cell was released fall too (floors above a blown-out ground storey pancake down).
static func collapse(t, released: Array) -> int:
	var cols := {}
	var n := 0
	for p in released:
		if not (p as RigidBody3D).has_meta("shell_of"):
			continue
		var sh = (p as RigidBody3D).get_meta("shell_of")
		if is_instance_valid(sh):
			cols[sh] = true
	for sh in cols.keys():
		if not bool(profile(str((sh as RigidBody3D).get_meta("mat", "masonry")))["collapse"]):
			continue
		var lowest := {}                                  # (i,k) -> lowest released floor
		var cells: Array = (sh as RigidBody3D).get_meta("shell_cells", [])
		for cb in cells:
			var c := cb as RigidBody3D
			if not c.freeze:
				var ix: Vector3i = c.get_meta("cidx")
				var key := Vector2i(ix.x, ix.z)
				lowest[key] = mini(int(lowest.get(key, 999)), ix.y)
		for cb in cells:
			var c := cb as RigidBody3D
			if c.freeze and not c.get_meta("capped", false) and t.pieces.has(c):
				var ix: Vector3i = c.get_meta("cidx")
				var key := Vector2i(ix.x, ix.z)
				if lowest.has(key) and ix.y > int(lowest[key]):
					t.release(c, Vector3(randf_range(-1.5, 1.5), -1.0, randf_range(-1.5, 1.5)))
					n += 1
	return n
