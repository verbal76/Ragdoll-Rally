extends SceneTree
## MOCKUP (xvfb): stylised comic explosion sequence - flat-colour fireball layers, charcoal smoke puffs, tumbling debris, spark streaks,
## shockwave ring, flames on the wreck - drawn over a real Lv20 punch + blast in Downtown, under the ink post-process. Not wired in.
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
var holder: Node3D

func flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

func blob(mesh: Mesh, c: Color, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = flat(c)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	return mi

func pop(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func build(c: Vector3, t: float) -> void:
	for ch in holder.get_children():
		ch.queue_free()
	var sph := SphereMesh.new()
	sph.radial_segments = 9
	sph.rings = 5
	sph.radius = 1.0
	sph.height = 2.0
	var cube := BoxMesh.new()
	cube.size = Vector3(1, 1, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# fireball: three nested lumpy layers; peaks around t=0.35 then collapses into smoke
	var grow: float = pop(t / 0.35)
	var fade: float = clampf(1.0 - (t - 0.5) / 0.5, 0.0, 1.0)
	if fade > 0.0:
		for i in 7:
			var a: float = float(i) / 7.0 * TAU
			var off := Vector3(cos(a) * 7.0, rng.randf_range(1.0, 7.0), sin(a) * 7.0) * grow
			blob(sph, Color(1.0, 0.25, 0.1), c + off, Vector3(8, 7, 8) * grow * fade)
		for i in 5:
			var a2: float = float(i) / 5.0 * TAU + 0.5
			blob(sph, Color(1.0, 0.6, 0.12), c + Vector3(cos(a2) * 4.0, 3.0 + rng.randf() * 4.0, sin(a2) * 4.0) * grow, Vector3(6, 5.5, 6) * grow * fade)
		blob(sph, Color(1.0, 0.95, 0.5), c + Vector3(0, 5.0 * grow, 0), Vector3(5, 5, 5) * grow * fade * clampf(1.2 - t * 1.6, 0.0, 1.0))
	# smoke: charcoal-blue puffs that climb and swell, outlined by the post pass
	var smoke_t: float = clampf((t - 0.15) / 1.6, 0.0, 1.0)
	if smoke_t > 0.0:
		for i in 12:
			var a3: float = float(i) / 12.0 * TAU
			var r: float = 3.0 + 5.0 * smoke_t * (0.5 + rng.randf())
			var h: float = 6.0 + 26.0 * smoke_t * (0.5 + 0.7 * rng.randf())
			blob(sph, Color(0.18, 0.2, 0.32) if i % 3 else Color(0.3, 0.33, 0.5), c + Vector3(cos(a3) * r, h, sin(a3) * r), Vector3(1, 0.85, 1) * (4.0 + 7.0 * smoke_t))
	# shockwave ring
	var tor := TorusMesh.new()
	tor.inner_radius = 0.92
	tor.outer_radius = 1.0
	tor.rings = 24
	tor.ring_segments = 4
	if t < 0.6:
		var ring := blob(tor, Color(1.0, 0.9, 0.5), c + Vector3(0, 1.0, 0), Vector3(1, 0.25, 1) * (4.0 + 34.0 * pop(t / 0.6)))
	# debris: tumbling slabs on ballistic paths
	for i in 46:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.6), rng.randf_range(-1, 1)).normalized()
		var spd: float = rng.randf_range(14.0, 34.0)
		var p: Vector3 = c + Vector3(0, 2, 0) + dir * spd * t + Vector3(0, -0.5 * 17.6 * t * t, 0)
		var sz: float = rng.randf_range(0.8, 2.6)
		var col: Color = [Color(0.85, 0.8, 0.7), Color(0.55, 0.62, 0.8), Color(0.3, 0.35, 0.55), Color(1.0, 0.5, 0.15)][i % 4]
		var d := blob(cube, col, p, Vector3(sz, sz * rng.randf_range(0.5, 1.2), sz))
		d.rotation = Vector3(t * rng.randf_range(-6, 6), t * rng.randf_range(-6, 6), t * rng.randf_range(-6, 6))
	# spark streaks: thin hot lines radiating from the core early on
	if t < 0.5:
		for i in 22:
			var dir2 := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			var l: float = 6.0 + 14.0 * pop(t / 0.5)
			var s := blob(cube, Color(1.0, 0.95, 0.4), c + Vector3(0, 3, 0) + dir2 * (8.0 + 20.0 * pop(t / 0.5)), Vector3(0.18, 0.18, l))
			s.look_at(s.global_position + dir2 if s.is_inside_tree() else dir2 + s.position, Vector3.UP)
	# flames on the wreck (appear after the blast, keep burning)
	if t > 0.4:
		var fl := CylinderMesh.new()
		fl.top_radius = 0.0
		fl.bottom_radius = 1.0
		fl.height = 2.0
		fl.radial_segments = 7
		for i in 9:
			var a4: float = float(i) / 9.0 * TAU
			var fh: float = 3.0 + 2.5 * sin(t * 9.0 + float(i) * 1.7)
			blob(fl, Color(1.0, 0.45, 0.1), c + Vector3(cos(a4) * 5.0, fh * 0.5, sin(a4) * 5.0), Vector3(1.6, fh, 1.6))
			blob(fl, Color(1.0, 0.85, 0.3), c + Vector3(cos(a4) * 5.0, fh * 0.35, sin(a4) * 5.0), Vector3(0.8, fh * 0.6, 0.8))

func _r():
	var out := "/tmp/claude-0/s/boom"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, Rules.env_index("downtown"))
	for i in 6: await process_frame
	main.set_process(false)
	main.ui.visible = false
	main.fx.visible = false          # the stylised layers below replace the stock particle puffs for this mockup
	holder = Node3D.new()
	main.add_child(holder)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tests/_toon/ink_post2.gdshader")
	qm.material = mat
	q.mesh = qm
	q.extra_cull_margin = 16384.0
	main.cam.add_child(q)
	var T = main.town
	var best = null
	var bd := 1e9
	for p in T.pieces:
		if Destruction.is_shell(p) and p.global_position.x > 60.0 and p.global_position.y > 8.0:
			var d: float = absf(p.global_position.x - 100.0) + absf(p.global_position.z)
			if d < bd:
				bd = d
				best = p
	var tgt: Vector3 = best.global_position
	var fe: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], {"power": 20, "destruction": 20, "explosive": 20, "bounce": 0, "ricochet": 0, "spin": 0, "durability": 0, "ignition": 3})
	Destruction.punch(T, best, tgt + Vector3(-6, 0, 0), Vector3(1, 0.05, 0).normalized(), 36.0 * float(fe["impact_power"]) * float(fe["destruct_mult"]), T.smash_push)
	T.explode(tgt, Rules.blast_radius(20), Rules.blast_power(20))
	var times := [0.08, 0.3, 0.75, 1.8]
	var tcur := 0.0
	var cpos: Vector3 = tgt + Vector3(-34, 62, -34)
	for k in times.size():
		var frames_needed: int = int((times[k] - tcur) * 60.0)
		for f in frames_needed:
			await physics_frame
		tcur = times[k]
		build(tgt + Vector3(0, 6, 0), tcur)
		main.cam.global_position = cpos
		main.cam.look_at(tgt + Vector3(0, 6, 0), Vector3.UP)
		main.cam.far = 900.0
		for i in 3: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/boom_%d.png" % [out, k])
		print("RENDER boom ", k, " t=", tcur)
	quit()
func _init():
	_r.call_deferred()
