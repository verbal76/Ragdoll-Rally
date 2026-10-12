extends SceneTree
## Captures an actual throw (chase camera, real impacts/FX) as PNGs under xvfb. Not a gate.
const Rules := preload("res://scripts/rules.gd")
func _init():
	_r.call_deferred()
func _r():
	var id: String = OS.get_environment("SHOT_ID") if OS.get_environment("SHOT_ID") != "" else "hill_steep"
	var out: String = "/tmp/claude-0/s/runshots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	var lv := Rules.empty_levels()
	lv["ignition"] = 3
	lv["explosive"] = 4
	lv["destruction"] = 5
	lv["power"] = 3
	main.levels = lv
	main.start_game(6, Rules.env_index(id))
	for i in 8: await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_00_aim.png" % [out, id])
	main.drag_vec = (main._basis_back * 0.95) * main.AIM_MAX_PX
	main._update_aim()
	main.fire()
	var n := 0
	var shot := 1
	while main.state == 1 and n < 60 * 12:
		await physics_frame
		n += 1
		if n % 30 == 0 and shot < 12:
			await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%02d_run.png" % [out, id, shot])
			shot += 1
	print("RUNSHOT done frames ", n, " shots ", shot)
	quit()
