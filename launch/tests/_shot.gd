extends SceneTree
## Renders a city from several camera positions to PNGs (needs a real renderer: run under xvfb-run).
func _init():
	_r.call_deferred()
func _r():
	var id: String = OS.get_environment("SHOT_ID") if OS.get_environment("SHOT_ID") != "" else "hill_steep"
	var out: String = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "/tmp/claude-0/s/shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, main.Rules.env_index(id))
	for i in 6: await process_frame
	var cam: Camera3D = main.cam
	var bd = main.town.get_node("Backdrop")
	print("BACKDROP vis ", bd.is_visible_in_tree(), " layers ", bd.layers, " cam cull ", cam.cull_mask, " far ", cam.far, " mesh ", bd.mesh.get_aabb())
	var views := {
		"launch": [Vector3(-14, 6, 0), Vector3(60, 8, 0)],
		"mid": [Vector3(30, 28, -70), Vector3(100, 10, 10)],
		"high": [Vector3(-10, 90, -10), Vector3(100, 5, 0)],
		"side": [Vector3(110, 60, -150), Vector3(110, 10, 0)],
		"skim": [Vector3(60, 14, 5), Vector3(130, 14, 5)],
		"far": [Vector3(150, 120, -20), Vector3(400, 40, 0)],
	}
	main.set_process(false)
	if OS.get_environment("HIDE_FAR") == "1":
		main.town.get_node("FarCity").visible = false
	for k in views:
		var v: Array = views[k]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		cam.far = 900.0
		for i in 3: await process_frame
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out, id, k])
	quit()
