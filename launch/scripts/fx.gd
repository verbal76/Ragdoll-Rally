extends Node3D
## Pooled, capped visual effects: cartoon blood, per-material debris (wood splinters, glass shards,
## stone chunks, metal sparks, dust), explosions, flames, smoke, ground splats.
## Everything is a fixed pool of CPUParticles3D / quads that gets recycled - nothing grows.
## Use with:  const Fx := preload("res://scripts/fx.gd")

const FLAME_POOL := 20
const SMOKE_POOL := 10
const SPLAT_POOL := 24

var gore: bool = true
var _blood: Array[CPUParticles3D] = []
var _bi: int = 0
var _debris: Dictionary = {}          # material -> Array[CPUParticles3D]
var _di: Dictionary = {}
var _boom: Array[CPUParticles3D] = []
var _boi: int = 0
var _flames: Array[CPUParticles3D] = []
var _flame_user: Array[int] = []       # handle (instance id of requester) per flame
var _smoke: Array[CPUParticles3D] = []
var _si: int = 0
var _splats: Array[MeshInstance3D] = []
var _spi: int = 0
var live_flames: int = 0

func _ready() -> void:
	for i in 6:
		_blood.append(_emitter(_box(0.13, Color(0.78, 0.04, 0.06)), 20, 0.75, 4.0, 11.0, Vector3(0, -16, 0), 80.0, true))
	_make_debris("wood", Color(0.60, 0.38, 0.18), Vector3(0.07, 0.07, 0.45), 18, 5)
	_make_debris("glass", Color(0.65, 0.92, 1.0, 0.8), Vector3(0.22, 0.02, 0.22), 22, 5)
	_make_debris("stone", Color(0.62, 0.62, 0.66), Vector3(0.26, 0.26, 0.26), 12, 5)
	_make_debris("metal", Color(1.0, 0.85, 0.4), Vector3(0.05, 0.05, 0.05), 18, 4, true)
	_make_debris("dust", Color(0.78, 0.7, 0.58, 0.6), Vector3(0.5, 0.5, 0.5), 10, 4)
	for i in 4:
		var p := _emitter(_box(0.5, Color(1.0, 0.55, 0.1, 0.9), true), 30, 0.9, 6.0, 15.0, Vector3(0, 2.0, 0), 180.0, true)
		p.scale_amount_min = 0.8
		p.scale_amount_max = 2.2
		_boom.append(p)
	for i in FLAME_POOL:
		var f := _emitter(_quad(0.7, Color(1.0, 0.5, 0.08, 0.8)), 12, 0.7, 1.2, 3.0, Vector3(0, 3.5, 0), 25.0, false)
		f.emitting = false
		f.visible = false
		_flames.append(f)
		_flame_user.append(0)
	for i in SMOKE_POOL:
		var s := _emitter(_quad(1.4, Color(0.25, 0.25, 0.27, 0.45), false), 6, 1.8, 0.8, 1.8, Vector3(0, 2.0, 0), 20.0, false)
		s.emitting = false
		s.visible = false
		_smoke.append(s)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.6, 0.02, 0.04, 0.9)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in SPLAT_POOL:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		q.material = sm
		mi.mesh = q
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_splats.append(mi)

func _box(size: float, c: Color, additive: bool = false) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	bm.material = _mat(c, additive)
	return bm

func _quad(size: float, c: Color, additive: bool = true) -> Mesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := _mat(c, additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = m
	return qm

func _mat(c: Color, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 0.99 or additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _emitter(mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, grav: Vector3, spread: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = one_shot
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0 if one_shot else 0.0
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	p.mesh = mesh
	p.local_coords = false
	add_child(p)
	return p

func _make_debris(mat: String, c: Color, size: Vector3, amount: int, count: int, emissive: bool = false) -> void:
	var arr: Array[CPUParticles3D] = []
	for i in count:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _mat(c, emissive)
		var p := _emitter(bm, amount, 0.9 if mat != "dust" else 1.3, 3.0, 10.0, Vector3(0, -14, 0) if mat != "dust" else Vector3(0, 0.5, 0), 70.0, true)
		if mat == "dust":
			p.scale_amount_min = 1.0
			p.scale_amount_max = 3.0
		arr.append(p)
	_debris[mat] = arr
	_di[mat] = 0

func _fire(p: CPUParticles3D, pos: Vector3, dir: Vector3, vscale: float = 1.0) -> void:
	p.global_position = pos
	if dir.length() > 0.01:
		p.direction = dir.normalized()
	p.initial_velocity_min = 3.0 * vscale
	p.initial_velocity_max = 10.0 * vscale
	p.restart()
	p.emitting = true

# ----------------------------------------------------------------------- public
func blood(pos: Vector3, dir: Vector3, strength: float = 1.0) -> void:
	if not gore:
		return
	var p: CPUParticles3D = _blood[_bi]
	_bi = (_bi + 1) % _blood.size()
	p.amount = int(clampf(10.0 + 14.0 * strength, 10.0, 30.0))
	_fire(p, pos, dir, 0.6 + 0.5 * strength)

## Flat red splat on the ground / floor at pos.
func splat(pos: Vector3, size: float = 1.0) -> void:
	if not gore:
		return
	var s: MeshInstance3D = _splats[_spi]
	_spi = (_spi + 1) % _splats.size()
	s.global_position = Vector3(pos.x, 0.06, pos.z)
	var k: float = size * randf_range(0.7, 1.4)
	s.scale = Vector3(k, k, 1.0)
	s.rotation = Vector3(-PI / 2.0, randf() * TAU, 0.0)
	s.visible = true

func debris(mat: String, pos: Vector3, dir: Vector3, intensity: float = 1.0) -> void:
	var key: String = mat
	if mat == "roof":
		key = "wood"
	elif mat == "masonry":
		key = "stone"
	elif not _debris.has(mat):
		key = "dust"
	var arr: Array = _debris[key]
	var i: int = int(_di[key])
	_di[key] = (i + 1) % arr.size()
	_fire(arr[i], pos, dir, clampf(0.5 + 0.6 * intensity, 0.5, 2.0))
	if key == "stone" or key == "wood":
		dust(pos, 0.6)

func dust(pos: Vector3, strength: float = 1.0) -> void:
	var arr: Array = _debris["dust"]
	var i: int = int(_di["dust"])
	_di["dust"] = (i + 1) % arr.size()
	_fire(arr[i], pos + Vector3(0, 0.3, 0), Vector3.UP, 0.3 + 0.2 * strength)

func sparks(pos: Vector3, dir: Vector3) -> void:
	debris("metal", pos, dir, 1.0)

func explosion(pos: Vector3, radius: float = 7.0) -> void:
	var p: CPUParticles3D = _boom[_boi]
	_boi = (_boi + 1) % _boom.size()
	_fire(p, pos + Vector3(0, 0.6, 0), Vector3.UP, clampf(radius / 7.0, 0.7, 1.8))
	dust(pos, 2.0)

## Persistent flame on something burning. Returns a handle (slot) or -1 if the pool is full.
func flame_start(pos: Vector3, owner_id: int) -> int:
	for i in _flames.size():
		if _flame_user[i] == 0:
			_flame_user[i] = owner_id
			var f: CPUParticles3D = _flames[i]
			f.global_position = pos
			f.visible = true
			f.emitting = true
			live_flames += 1
			return i
	return -1

func flame_stop(handle: int) -> void:
	if handle < 0 or handle >= _flames.size() or _flame_user[handle] == 0:
		return
	_flame_user[handle] = 0
	(_flames[handle] as CPUParticles3D).emitting = false
	(_flames[handle] as CPUParticles3D).visible = false
	live_flames = maxi(live_flames - 1, 0)

func flame_move(handle: int, pos: Vector3) -> void:
	if handle >= 0 and handle < _flames.size():
		(_flames[handle] as CPUParticles3D).global_position = pos

func smoke_at(pos: Vector3) -> void:
	var s: CPUParticles3D = _smoke[_si]
	_si = (_si + 1) % _smoke.size()
	s.global_position = pos
	s.visible = true
	s.restart()
	s.emitting = true

func clear_all() -> void:
	for i in _flames.size():
		flame_stop(i)
	for s in _smoke:
		s.emitting = false
		s.visible = false
	for sp in _splats:
		sp.visible = false
	live_flames = 0
