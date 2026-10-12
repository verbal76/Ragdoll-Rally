extends SceneTree
## Evidence script: audits every playable board - what is breakable, what is a static building, heights, extents.
const Rules := preload("res://scripts/rules.gd")
func _init():
	_r.call_deferred()
func _r():
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	for i in 5: await process_frame
	for en in Rules.ENVIRONMENTS:
		var id: String = str(en["id"])
		main.start_game(0, Rules.env_index(id))
		for i in 4: await process_frame
		var T = main.town
		var statics := 0
		var static_big := 0          # solid statics bigger than a person-sized prop (>= 2.5 m on two axes) that are not ground/boundary
		var static_vol := 0.0
		var tall_static := 0.0
		var glass := 0
		var decor := 0
		var xmax := 0.0
		var zmax := 0.0
		var ymax := 0.0
		var by_mat := {}
		for ch in T.get_children():
			if ch is StaticBody3D:
				if ch.has_meta("boundary") or ch.has_meta("ground") or ch.name == "Terrain":
					continue
				if ch.has_meta("glass"):
					glass += 1
					continue
				if ch.has_meta("decor"):
					decor += 1
					continue
				statics += 1
				var sz := Vector3.ZERO
				for c2 in ch.get_children():
					if c2 is CollisionShape3D and c2.shape is BoxShape3D:
						sz = c2.shape.size
					elif c2 is CollisionShape3D and c2.shape is CylinderShape3D:
						sz = Vector3(c2.shape.radius * 2.0, c2.shape.height, c2.shape.radius * 2.0)
				var mn: float = minf(sz.x, sz.z)
				if sz.y >= 2.5 and mn >= 2.5:
					static_big += 1
					static_vol += sz.x * sz.y * sz.z
					tall_static = maxf(tall_static, ch.global_position.y + sz.y * 0.5)
					var m: String = str(ch.get_meta("mat", "?"))
					by_mat[m] = int(by_mat.get(m, 0)) + 1
		for p in T.pieces:
			var q: Vector3 = p.global_position
			xmax = maxf(xmax, q.x)
			zmax = maxf(zmax, absf(q.z))
			ymax = maxf(ymax, q.y)
		var tg_far := 0.0
		for tg in T.targets:
			tg_far = maxf(tg_far, tg["pos"].x)
		print("AUDIT %-13s breakable pieces %4d props %3d | decor(MultiMesh, breakable) %3d | static solids >=2.5m: %3d (vol %7.0f m3, tallest top %.0f m, mats %s) | glass %3d | pieces extent x<=%.0f |z|<=%.0f y<=%.0f | targets %d farthest x %.0f" % [id, T.pieces.size(), T.props.size(), decor, static_big, static_vol, tall_static, str(by_mat), glass, xmax, zmax, ymax, T.targets.size(), tg_far])
	quit()
