extends SceneTree
## PROTOTYPE evidence render (xvfb): comic-ink post pass on a board. Not wired into the game.
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
func _shoot(main, name: String, pos: Vector3, look: Vector3, out: String) -> void:
	main.cam.global_position = pos
	main.cam.look_at(look, Vector3.UP)
	main.cam.far = 900.0
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("RENDER ", name)
func _r():
	var id: String = OS.get_environment("SHOT_ID") if OS.get_environment("SHOT_ID") != "" else "downtown"
	var out: String = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "/tmp/claude-0/s/toon"
	var theme: String = OS.get_environment("TOON") if OS.get_environment("TOON") != "" else "blue"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, Rules.env_index(id))
	for i in 6: await process_frame
	main.set_process(false)
	main.ui.visible = false
	var pal := {"blue": [Color(0.03, 0.05, 0.28), Color(0.10, 0.28, 0.85), Color(0.62, 0.84, 1.0)],
		"orange": [Color(0.35, 0.12, 0.05), Color(0.95, 0.55, 0.25), Color(1.0, 0.9, 0.6)],
		"green": [Color(0.04, 0.2, 0.08), Color(0.35, 0.75, 0.2), Color(0.85, 1.0, 0.45)]}
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tests/_toon/" + (OS.get_environment("SHADER") if OS.get_environment("SHADER") != "" else "ink_post") + ".gdshader")
	var pc: Array = pal[theme]
	mat.set_shader_parameter("c_dark", pc[0])
	mat.set_shader_parameter("c_mid", pc[1])
	mat.set_shader_parameter("c_light", pc[2])
	qm.material = mat
	q.mesh = qm
	q.extra_cull_margin = 16384.0
	main.cam.add_child(q)
	q.position = Vector3(0, 0, -1)
	var T = main.town
	await _shoot(main, "%s_%s_street" % [id, theme], Vector3(-6, 5, 0), Vector3(90, 12, 0), out)
	await _shoot(main, "%s_%s_high" % [id, theme], Vector3(20, 60, -70), Vector3(110, 10, 0), out)
	var best = null
	var bd := 1e9
	for p in T.pieces:
		if Destruction.is_shell(p) and p.global_position.x > 60.0 and p.global_position.y > 8.0:
			var d: float = absf(p.global_position.x - 100.0) + absf(p.global_position.z)
			if d < bd:
				bd = d
				best = p
	if best != null:
		var tgt: Vector3 = best.global_position
		var fe: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], {"power": 20, "destruction": 20, "explosive": 20, "bounce": 0, "ricochet": 0, "spin": 0, "durability": 0, "ignition": 3})
		Destruction.punch(T, best, tgt + Vector3(-6, 0, 0), Vector3(1, 0.05, 0).normalized(), 36.0 * float(fe["impact_power"]) * float(fe["destruct_mult"]), T.smash_push)
		T.explode(tgt, Rules.blast_radius(20), Rules.blast_power(20))
		main.fx.explosion(tgt, Rules.blast_radius(20))
		for k in 25:
			await physics_frame
		await _shoot(main, "%s_%s_blast" % [id, theme], tgt + Vector3(-45, 12, -30), tgt, out)
	quit()
func _init():
	_r.call_deferred()
