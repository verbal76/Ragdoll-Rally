extends SceneTree
func _init():
	_r.call_deferred()
func _r():
	var root3 := Node3D.new()
	root.add_child(root3)
	var names := ["building-block","building-window","building-windows","building-door","building-door-window","building-corner","building-window-balcony","building-window-awnings","roof-gable","roof-gable-end","roof-gable-corner","roof-slanted","roof-flat-top","roof-flat-border-center","building-sample-house-a","building-sample-house-b","building-sample-house-c","building-sample-tower-a","building-sample-tower-b","building-sample-tower-c","building-sample-tower-d","building-windows-sills"]
	var i := 0
	for n in names:
		var inst: Node3D = (load("res://assets/kenney/modular-buildings/%s.glb" % n) as PackedScene).instantiate()
		inst.position = Vector3(float(i % 6) * 3.2, 0, float(i / 6) * 4.5)
		root3.add_child(inst)
		var l := Label3D.new()
		l.text = n.replace("building-", "b-")
		l.position = inst.position + Vector3(0, 0.1, 1.6)
		l.rotation_degrees = Vector3(-60, 0, 0)
		l.pixel_size = 0.004
		l.font_size = 40
		root3.add_child(l)
		i += 1
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.position = Vector3(8, 9, 20)
	cam.look_at(Vector3(8, 0.5, 6), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	root3.add_child(env)
	for k in 4: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/s/shots/models.png")
	quit()
