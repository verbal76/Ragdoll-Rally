extends Node3D
## Pooled, capped visual effects. Everything is a fixed pool that gets recycled - nothing grows.
##   BLOOD   Kenney splat atlas (CC0) tinted red -> persistent surface marks (bounded ring buffer, fade out) + a small droplet spray.
##   FIRE    toon flame meshes (adapted from the supplied 3dFireSmoke pack) + dark toon smoke puffs while something burns.
##   SMOKE   opaque low-poly toon puffs (dust / debris cloud / explosion smoke), not the demo's 12k-triangle spheres.
##   DEBRIS  per-material chips (wood, glass, stone, metal) as before.
## Use with:  const Fx := preload("res://scripts/fx.gd")

const FLAME_POOL := 20
const FLAME_SMOKE_POOL := 8          # smoke columns on the first N flames only
const SMOKE_POOL := 8                # one-shot smoke from objects that burn out
const SPLAT_POOL := 40               # persistent blood marks (hard cap)
const SPLAT_LIFE := 30.0             # seconds before a mark is recycled (it shrinks away over the last 3 s)
const ATLAS_PATH := "res://assets/fx/splat_atlas.png"
const ATLAS_COLS := 6
const ATLAS_N := 36
const BLOOD_REDS: Array[Color] = [Color(0.66, 0.02, 0.04), Color(0.74, 0.03, 0.05), Color(0.58, 0.02, 0.05), Color(0.80, 0.05, 0.06), Color(0.50, 0.01, 0.03)]

var gore: bool = true
var live_flames: int = 0
var _blood: Array[CPUParticles3D] = []
var _bi: int = 0
var _debris: Dictionary = {}          # material -> Array[CPUParticles3D]
var _di: Dictionary = {}
var _dust: Array[CPUParticles3D] = []
var _dusti: int = 0
var _crumble: Array[CPUParticles3D] = []
var _ci: int = 0
var _boom: Array[CPUParticles3D] = []
var _boom_smoke: Array[CPUParticles3D] = []
var _boi: int = 0
var _flash: Array[MeshInstance3D] = []
var _flash_t: Array[float] = []
var _flames: Array[MeshInstance3D] = []
var _flame_smoke: Array[CPUParticles3D] = []
var _flame_user: Array[int] = []
var _smoke: Array[CPUParticles3D] = []
var _si: int = 0
var _splats: Array[MeshInstance3D] = []
var _splat_age: Array[float] = []
var _splat_base: Array[float] = []
var _spi: int = 0
var _splat_mats: Array[StandardMaterial3D] = []
var _scale_curve: Curve
var _fire_shader: Shader
var _smoke_shader: Shader
var _outline_shader: Shader

func _ready() -> void:
	_fire_shader = load("res://assets/fx/toon_fire.gdshader")
	_smoke_shader = load("res://assets/fx/toon_smoke.gdshader")
	_outline_shader = load("res://assets/fx/toon_smoke_outline.gdshader")
	_scale_curve = Curve.new()
	_scale_curve.add_point(Vector2(0.0, 0.25))
	_scale_curve.add_point(Vector2(0.28, 1.0), 0.0, 0.0)
	_scale_curve.add_point(Vector2(1.0, 0.0))
	_build_splats()
	for i in 6:
		_blood.append(_emitter(_drop_mesh(), 16, 0.75, 4.0, 11.0, Vector3(0, -16, 0), 80.0, true))
	_make_debris("wood", Color(0.60, 0.38, 0.18), Vector3(0.07, 0.07, 0.45), 14, 5)
	_make_debris("glass", Color(0.65, 0.92, 1.0, 0.8), Vector3(0.22, 0.02, 0.22), 18, 5)
	_make_debris("stone", Color(0.62, 0.62, 0.66), Vector3(0.26, 0.26, 0.26), 10, 5)
	_make_debris("metal", Color(1.0, 0.85, 0.4), Vector3(0.05, 0.05, 0.05), 14, 4, true)
	# --- toon puffs: dust (tan), crumble clouds (grey-tan), explosion fire, explosion smoke (charcoal), burn-out smoke
	var dust_mesh: Mesh = _puff_mesh(0.34, Color(0.78, 0.70, 0.58), 0.0)
	for i in 6:
		_dust.append(_puff_emitter(dust_mesh, 6, 0.9, 1.0, 3.0, Vector3(0, 0.6, 0), 60.0, true, 0.9, 1.5))
	var crumble_mesh: Mesh = _puff_mesh(0.5, Color(0.74, 0.70, 0.64), 0.0)
	for i in 3:
		_crumble.append(_puff_emitter(crumble_mesh, 12, 1.7, 2.0, 7.0, Vector3(0, 1.0, 0), 75.0, true, 1.2, 2.4))
	var fire_mesh: Mesh = _puff_mesh(0.5, Color(1.0, 0.58, 0.12), 1.0)
	var smoke_mesh: Mesh = _puff_mesh(0.55, Color(0.55, 0.55, 0.58), 0.0)
	for i in 4:
		_boom.append(_puff_emitter(fire_mesh, 14, 0.7, 5.0, 13.0, Vector3(0, 1.5, 0), 180.0, true, 0.9, 2.0))
		_boom_smoke.append(_puff_emitter(smoke_mesh, 14, 2.3, 2.0, 8.0, Vector3(0, 2.2, 0), 180.0, true, 1.2, 2.6))
		var fl := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
		qm.material = fm
		fl.mesh = qm
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_flash.append(fl)
		_flash_t.append(0.0)
	for i in FLAME_POOL:
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 10
		cm.rings = 14
		cm.cap_top = false
		cm.cap_bottom = false
		var sm := ShaderMaterial.new()
		sm.shader = _fire_shader
		sm.set_shader_parameter("top_radius", 0.05)
		sm.set_shader_parameter("bottom_radius", 0.07)
		sm.set_shader_parameter("center_radius", 0.75)
		sm.set_shader_parameter("center_position", 0.3)
		sm.set_shader_parameter("cylinder_height", 3.5)
		sm.set_shader_parameter("bottom_curve", 0.4)
		sm.set_shader_parameter("_vibrate_amplitude", 0.0)
		sm.set_shader_parameter("_vibrate_frequency", 150.0)
		sm.set_shader_parameter("_speed", 2.0)
		sm.set_shader_parameter("_scale", 2.0)
		sm.set_shader_parameter("seed", float(i) * 3.7)
		cm.material = sm
		f.mesh = cm
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_flames.append(f)
		_flame_user.append(0)
	var fsmoke_mesh: Mesh = _puff_mesh(0.36, Color(0.50, 0.50, 0.54), 0.0)
	for i in FLAME_SMOKE_POOL:
		var s := _puff_emitter(fsmoke_mesh, 5, 2.4, 1.0, 2.2, Vector3(0, 1.8, 0), 18.0, false, 0.8, 1.9)
		s.emitting = false
		s.visible = false
		_flame_smoke.append(s)
	var burn_mesh: Mesh = _puff_mesh(0.5, Color(0.66, 0.66, 0.68), 0.0)
	for i in SMOKE_POOL:
		var s2 := _puff_emitter(burn_mesh, 8, 2.6, 1.0, 3.0, Vector3(0, 1.6, 0), 28.0, true, 1.0, 2.2)
		_smoke.append(s2)

# ----------------------------------------------------------------------------------------------- builders
func _build_splats() -> void:
	var tex: Texture2D = load(ATLAS_PATH)
	var cell: float = 1.0 / float(ATLAS_COLS)
	for k in ATLAS_N:
		var u0: float = float(k % ATLAS_COLS) * cell
		var v0: float = float(k / ATLAS_COLS) * cell
		# QuadMesh has no UV control: build the quad by hand with this cell's UV rect
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)])
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u0, v0 + cell), Vector2(u0 + cell, v0 + cell), Vector2(u0 + cell, v0), Vector2(u0, v0)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_splat_atlas_meshes.append(am)
	for c in BLOOD_REDS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.albedo_color = c                         # the supplied artwork is white: this IS the blood colour
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_splat_mats.append(m)
	for i in SPLAT_POOL:
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_splats.append(mi)
		_splat_age.append(-1.0)
		_splat_base.append(1.0)

var _splat_atlas_meshes: Array[ArrayMesh] = []

func _drop_mesh() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.72, 0.03, 0.05)
	sm.material = m
	return sm

## Opaque low-poly toon puff (the supplied pack's smoke look, adapted for mobile): sphere + shader + outline pass.
func _puff_mesh(radius: float, col: Color, emissive: float) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 7
	var m := ShaderMaterial.new()
	m.shader = _smoke_shader
	m.set_shader_parameter("smoke_color", col)
	m.set_shader_parameter("emissive", emissive)
	if emissive < 0.5:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("outline_width", 0.7)
		o.set_shader_parameter("outline_color", Color(0.10, 0.10, 0.12))
		m.next_pass = o
	sm.material = m
	return sm

func _puff_emitter(mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, grav: Vector3, spread: float, one_shot: bool, smin: float, smax: float) -> CPUParticles3D:
	var p := _emitter(mesh, amount, life, vmin, vmax, grav, spread, one_shot)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.scale_amount_curve = _scale_curve
	p.angle_max = 180.0
	return p

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

func _mat(c: Color, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 0.99 or additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _make_debris(mat: String, c: Color, size: Vector3, amount: int, count: int, emissive: bool = false) -> void:
	var arr: Array[CPUParticles3D] = []
	for i in count:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _mat(c, emissive)
		var p := _emitter(bm, amount, 0.9, 3.0, 10.0, Vector3(0, -14, 0), 70.0, true)
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

func _burst(p: CPUParticles3D, pos: Vector3, vmin: float, vmax: float, dir: Vector3 = Vector3.UP) -> void:
	p.global_position = pos
	p.direction = dir if dir.length() > 0.01 else Vector3.UP
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.restart()
	p.emitting = true

func _process(dt: float) -> void:
	for i in _splats.size():
		var a: float = _splat_age[i]
		if a < 0.0:
			continue
		a += dt
		_splat_age[i] = a
		if a >= SPLAT_LIFE:
			_splats[i].visible = false
			_splat_age[i] = -1.0
		elif a > SPLAT_LIFE - 3.0:
			var k: float = (SPLAT_LIFE - a) / 3.0
			var s: float = _splat_base[i] * k
			(_splats[i] as MeshInstance3D).scale = Vector3(s, s, s)
	for i in _flash.size():
		if _flash_t[i] > 0.0:
			_flash_t[i] -= dt
			var f: MeshInstance3D = _flash[i]
			if _flash_t[i] <= 0.0:
				f.visible = false
			else:
				var k2: float = _flash_t[i] / 0.22
				f.scale = Vector3.ONE * lerpf(9.0, 3.0, k2)
				((f.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = k2

# ----------------------------------------------------------------------------------------------- blood
## Droplet spray for hard impacts / limb loss (small, bounded).
func blood(pos: Vector3, dir: Vector3, strength: float = 1.0) -> void:
	if not gore:
		return
	var p: CPUParticles3D = _blood[_bi]
	_bi = (_bi + 1) % _blood.size()
	p.amount = int(clampf(8.0 + 8.0 * strength, 8.0, 22.0))
	_fire(p, pos, dir, 0.6 + 0.5 * strength)

## Persistent blood mark on a surface: oriented to `normal` (ground, slope or wall), red-tinted Kenney splat shape,
## random rotation / size / red value. Ring buffer of SPLAT_POOL marks; the oldest is recycled, all fade after SPLAT_LIFE s.
func splat(pos: Vector3, normal: Vector3 = Vector3.UP, size: float = 1.0) -> void:
	if not gore:
		return
	var i: int = _spi
	_spi = (_spi + 1) % _splats.size()
	var mi: MeshInstance3D = _splats[i]
	mi.mesh = _splat_atlas_meshes[randi() % _splat_atlas_meshes.size()]
	mi.material_override = _splat_mats[randi() % _splat_mats.size()]
	var n: Vector3 = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var bx: Vector3 = Vector3.UP.cross(n)
	if bx.length() < 0.2:
		bx = Vector3.RIGHT.cross(n)
	bx = bx.normalized()
	var by: Vector3 = n.cross(bx)
	var basis := Basis(bx, by, n).rotated(n, randf() * TAU)
	var k: float = size * randf_range(1.0, 2.0)
	mi.global_transform = Transform3D(basis.scaled(Vector3(k, k, k)), pos + n * 0.07)
	mi.visible = true
	_splat_age[i] = 0.0
	_splat_base[i] = k

# ----------------------------------------------------------------------------------------------- impacts / destruction
func debris(mat: String, pos: Vector3, dir: Vector3, intensity: float = 1.0) -> void:
	var key: String = mat
	if mat == "roof":
		key = "wood"
	elif mat == "masonry":
		key = "stone"
	elif not _debris.has(mat):
		key = "wood"
	var arr: Array = _debris[key]
	var i: int = int(_di[key])
	_di[key] = (i + 1) % arr.size()
	_fire(arr[i], pos, dir, clampf(0.5 + 0.6 * intensity, 0.5, 2.0))
	if key == "stone" or key == "wood":
		dust(pos, 0.6)

## Ordinary impact: a small dust puff.
func dust(pos: Vector3, strength: float = 1.0) -> void:
	var p: CPUParticles3D = _dust[_dusti]
	_dusti = (_dusti + 1) % _dust.size()
	p.amount = int(clampf(4.0 + 4.0 * strength, 4.0, 10.0))
	p.scale_amount_max = 1.2 + 0.4 * strength
	_burst(p, pos + Vector3(0, 0.3, 0), 0.8, 1.2 + 1.4 * strength)

## A building / big structure giving way: an expanding dust-and-debris cloud that dissipates.
func crumble(pos: Vector3, size: float = 1.0) -> void:
	var p: CPUParticles3D = _crumble[_ci]
	_ci = (_ci + 1) % _crumble.size()
	p.amount = int(clampf(8.0 + 6.0 * size, 8.0, 18.0))
	p.scale_amount_max = 1.8 + 0.8 * size
	_burst(p, pos + Vector3(0, 0.6, 0), 1.5, 3.5 + 3.0 * size)
	if size > 1.0:
		debris("stone", pos, Vector3.UP, 1.0)

func sparks(pos: Vector3, dir: Vector3) -> void:
	debris("metal", pos, dir, 1.0)

## Explosion: bright flash -> orange fireball puffs -> expanding charcoal smoke (+ a dust ring).
func explosion(pos: Vector3, radius: float = 7.0) -> void:
	var i: int = _boi
	_boi = (_boi + 1) % _boom.size()
	var s: float = clampf(radius / 7.0, 0.7, 1.8)
	_burst(_boom[i], pos + Vector3(0, 0.6, 0), 4.0 * s, 11.0 * s)
	_burst(_boom_smoke[i], pos + Vector3(0, 1.2, 0), 2.0 * s, 7.0 * s)
	var f: MeshInstance3D = _flash[i]
	f.global_position = pos + Vector3(0, 1.0, 0)
	f.visible = true
	_flash_t[i] = 0.22
	dust(pos, 2.0)

# ----------------------------------------------------------------------------------------------- fire
## Persistent flame on something burning. `scale` ~ the burning object's size (a crate ~1, a house wall ~2.5).
## Returns a handle (slot) or -1 if the pool is full.
func flame_start(pos: Vector3, owner_id: int, scale: float = 1.0) -> int:
	for i in _flames.size():
		if _flame_user[i] == 0:
			_flame_user[i] = owner_id
			var f: MeshInstance3D = _flames[i]
			var k: float = clampf(scale, 0.6, 3.2)
			f.scale = Vector3(k, k, k) * 0.5
			f.global_position = pos
			f.rotation = Vector3(0, randf() * TAU, 0)
			f.visible = true
			if i < _flame_smoke.size():
				var sp: CPUParticles3D = _flame_smoke[i]
				sp.global_position = pos + Vector3(0, 1.4 * k, 0)
				sp.scale_amount_min = 0.7 * k
				sp.scale_amount_max = 1.6 * k
				sp.visible = true
				sp.emitting = true
			live_flames += 1
			return i
	return -1

func flame_stop(handle: int) -> void:
	if handle < 0 or handle >= _flames.size() or _flame_user[handle] == 0:
		return
	_flame_user[handle] = 0
	(_flames[handle] as MeshInstance3D).visible = false
	if handle < _flame_smoke.size():
		(_flame_smoke[handle] as CPUParticles3D).emitting = false
	live_flames = maxi(live_flames - 1, 0)

func flame_move(handle: int, pos: Vector3) -> void:
	if handle >= 0 and handle < _flames.size():
		var k: float = (_flames[handle] as MeshInstance3D).scale.x * 2.0
		(_flames[handle] as MeshInstance3D).global_position = pos
		if handle < _flame_smoke.size():
			(_flame_smoke[handle] as CPUParticles3D).global_position = pos + Vector3(0, 1.4 * k, 0)

## One-shot smoke when something burns out.
func smoke_at(pos: Vector3) -> void:
	var s: CPUParticles3D = _smoke[_si]
	_si = (_si + 1) % _smoke.size()
	_burst(s, pos, 1.0, 3.0)

func clear_all() -> void:
	for i in _flames.size():
		flame_stop(i)
	for arr in [_dust, _crumble, _boom, _boom_smoke, _smoke, _flame_smoke, _blood]:
		for p in arr:
			(p as CPUParticles3D).emitting = false
	for k in _debris.keys():
		for p in (_debris[k] as Array):
			(p as CPUParticles3D).emitting = false
	for i in _flash.size():
		_flash[i].visible = false
		_flash_t[i] = 0.0
	for i in _splats.size():
		_splats[i].visible = false
		_splat_age[i] = -1.0
	live_flames = 0
