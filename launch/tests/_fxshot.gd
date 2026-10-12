extends SceneTree
func _init():
	_r.call_deferred()
func _r():
	var out := "/tmp/claude-0/s/shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, main.Rules.env_index("hill_steep"))
	for i in 6: await process_frame
	var cam: Camera3D = main.cam
	main.set_process(false)
	var fx = main.fx
	var T = main.town
	var base := Vector3(42, T.ground_y(42, 0), -8)
	cam.global_position = base + Vector3(-12, 5, 3)
	cam.look_at(base + Vector3(0, 1.5, 0), Vector3.UP)
	cam.far = 800
	# blood: ground splats, wall splat, spray
	for i in 7:
		fx.splat(base + Vector3(randf_range(-4, 1), 0, randf_range(-3, 3)), T.ground_normal(42, -8), randf_range(0.8, 1.6))
	fx.splat(base + Vector3(2, 2, 0), Vector3(-1, 0, 0), 1.4)
	fx.blood(base + Vector3(0, 1, 0), Vector3.UP, 1.5)
	fx.dust(base + Vector3(-3, 0, 2), 1.0)
	fx.crumble(base + Vector3(3, 0, -2), 1.5)
	fx.flame_start(base + Vector3(-2, 1, -3), 1234, 2.0)
	fx.flame_start(base + Vector3(-5, 1, 0), 1235, 1.0)
	fx.explosion(base + Vector3(6, 0, 3), 7.0)
	for i in 12: await process_frame
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/fx_a.png")
	await create_timer(0.6).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/fx_b.png")
	await create_timer(1.2).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/fx_c.png")
	quit()
