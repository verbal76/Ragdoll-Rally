extends SceneTree
## Evidence renders of the mayhem pass (needs a real renderer: xvfb-run). SHOT_ID board, SHOT_DIR output.
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
func _init():
	_r.call_deferred()
func _shoot(main, name: String, pos: Vector3, look: Vector3, out: String, id: String) -> void:
	main.cam.global_position = pos
	main.cam.look_at(look, Vector3.UP)
	main.cam.far = 900.0
	for i in 3:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [out, id, name])
	print("RENDER ", name)
func _r():
	var id: String = OS.get_environment("SHOT_ID") if OS.get_environment("SHOT_ID") != "" else "downtown"
	var out: String = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "/tmp/claude-0/s/mayhem"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, Rules.env_index(id))
	for i in 6: await process_frame
	main.set_process(false)
	await _shoot(main, "a_far_district", Vector3(150, 70, -90), Vector3(250, 15, 0), out, id)
	await _shoot(main, "b_skyline", Vector3(-10, 14, 10), Vector3(260, 25, 0), out, id)
	# a Lv20 hit on a tower in the middle distance
	var T = main.town
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
		await _shoot(main, "c_before", tgt + Vector3(-34, 6, -22), tgt, out, id)
		var fe: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], {"power": 20, "destruction": 20, "explosive": 20, "bounce": 0, "ricochet": 0, "spin": 0, "durability": 0, "ignition": 3})
		var effk: float = 36.0 * float(fe["impact_power"]) * float(fe["destruct_mult"])
		var r: Dictionary = Destruction.punch(T, best, tgt + Vector3(-6, 0, 0), Vector3(1, 0.05, 0).normalized(), effk, T.smash_push)
		print("punch released ", (r["released"] as Array).size(), " dissolved ", (r["dissolved"] as Array).size(), " keep ", r["keep"], " collapsed ", r["collapsed"])
		var res: Dictionary = T.explode(tgt, Rules.blast_radius(20), Rules.blast_power(20))
		main.fx.explosion(tgt, Rules.blast_radius(20))
		main.fx.crater(Vector3(tgt.x, 0, tgt.z), Vector3.UP, Rules.blast_radius(20), 4)
		for k in 12:
			await physics_frame
		await _shoot(main, "d_blast_early", tgt + Vector3(-34, 8, -22), tgt, out, id)
		for k in 40:
			await physics_frame
		await _shoot(main, "e_blast_mid", tgt + Vector3(-40, 12, -26), tgt, out, id)
		for k in 150:
			await physics_frame
		await _shoot(main, "f_aftermath", tgt + Vector3(-40, 14, -26), tgt, out, id)
		# blood on a wall: use the first intact shell near the camera
		await _shoot(main, "g_overview", tgt + Vector3(-80, 55, -70), tgt, out, id)
	quit()
