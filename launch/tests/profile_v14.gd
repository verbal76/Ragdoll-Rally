extends SceneTree
## Evidence script (not a pass/fail gate): per-city load time, body counts and physics step time during real destructive throws.
##   godot --headless --path launch -s tests/profile_v14.gd        (physics + counts)
##   xvfb-run godot --path launch --rendering-driver opengl3 -s tests/profile_v14.gd -- --render   (draw calls / primitives; frame times are software-GL, not meaningful)
const Rules := preload("res://scripts/rules.gd")
var main: Node

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _aim(b: float, s: float) -> void:
	main.drag_vec = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
	main._update_aim()

func _init() -> void:
	Engine.max_fps = 0
	_run.call_deferred()

func _run() -> void:
	var render: bool = OS.get_cmdline_user_args().has("--render")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	await frames(5)
	var ids: Array = ["city", "hill_steep", "hill_valley", "hill_rolling", "hill_skyline"]
	for id in ids:
		var t0: int = Time.get_ticks_msec()
		main.start_game(6, Rules.env_index(id))
		await frames(4)
		var load_ms: int = Time.get_ticks_msec() - t0
		var T = main.town
		var n_pieces: int = T.pieces.size()
		var n_props: int = T.props.size()
		var n_burn: int = T.fire_nodes.size()
		var samples: Array = []
		var spikes := 0
		var phys_sum := 0.0
		var phys_max := 0.0
		var steps := 0
		var peak_bodies := 0
		var peak_particles := 0
		var draw_peak := 0
		var prim_peak := 0.0
		for vec in [[0.9, 0.0], [1.0, 0.3]]:
			main.start_game(6, Rules.env_index(id))
			await frames(3)
			_aim(vec[0], vec[1])
			main.fire()
			var n := 0
			while main.state == 1 and n < 60 * 14:
				await physics_frame
				n += 1
				var pt: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				if n <= 3 or pt > 100.0:
					spikes += 1                      # first-contact / broadphase build stalls are reported separately, not averaged
				else:
					phys_sum += pt
					samples.append(pt)
				phys_max = maxf(phys_max, pt)
				steps += 1
				peak_bodies = maxi(peak_bodies, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
				if render and n % 10 == 0:
					draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
					prim_peak = maxf(prim_peak, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				if n % 15 == 0:
					var pc := 0
					for ch in main.fx.get_children():
						if ch is CPUParticles3D and (ch as CPUParticles3D).emitting:
							pc += (ch as CPUParticles3D).amount
					peak_particles = maxi(peak_particles, pc)
		print("PROFILE %-12s load %4d ms | pieces %4d props %3d burnables %4d | active bodies peak %3d | physics avg %.2f ms p95 %.2f ms (%d stalls, worst %.0f ms) | particles peak %3d | draw calls %d prims %d | splats <= %d" % [id, load_ms, n_pieces, n_props, n_burn, peak_bodies, phys_sum / maxf(samples.size(), 1), _p95(samples), spikes, phys_max, peak_particles, draw_peak, int(prim_peak), main.fx.SPLAT_POOL])
	quit()

func _p95(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[int(float(b.size() - 1) * 0.95)])
