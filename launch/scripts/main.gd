extends Node3D
## RAGDOLL RALLY: LAUNCH - POC game controller.
## States: AIM (drag back) -> FLIGHT (launched, until settled) -> RESULT.

enum State { AIM, FLIGHT, RESULT }

const LAUNCH_ORIGIN := Vector3(0.0, 2.3, 0.0)
const PULL_LEN := 3.6
const MIN_SPEED := 9.0
const MAX_SPEED := 32.0
const MIN_POWER := 0.12
const TRAJ_DOTS := 26

var state: int = State.AIM
var town: Town
var ragdoll: Ragdoll
var scoring: Scoring
var sfx: Sfx
var cam: Camera3D

# aim
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_vec: Vector2 = Vector2.ZERO
var aim_dir: Vector3 = Vector3.RIGHT
var aim_power: float = 0.0
var _dots: Array[MeshInstance3D] = []

# flight bookkeeping
var t_launch: float = 0.0
var t_first_impact: float = -1.0
var settle_timer: float = 0.0
var flip_angle: float = 0.0
var _last_sound: float = -1.0
var trauma: float = 0.0
var cam_blend: float = 0.0   # 0 = tight follow, 1 = wide chaos view
var best: int = 0
var attempt: int = 0
var frame_sum: float = 0.0
var frame_n: int = 0
var frame_worst: float = 0.0
var _smash_vel_fix: Dictionary = {}

# ui
var ui: CanvasLayer
var lbl_score: Label
var lbl_hint: Label
var lbl_stats: Label
var lbl_fps: Label
var bar_bg: ColorRect
var bar_fill: ColorRect
var result_panel: PanelContainer
var lbl_result: Label
var lbl_breakdown: Label
var btn_again: Button
var btn_reset: Button
var _particles: Array[CPUParticles3D] = []
var _pi: int = 0
var _noise := FastNoiseLite.new()
var _cam_aim_xf := Transform3D.IDENTITY
var _cam_look := Vector3.ZERO

func _ready() -> void:
	randomize()
	Engine.max_fps = 60
	_load_best()
	_setup_environment()
	sfx = Sfx.new()
	add_child(sfx)
	_setup_camera()
	_setup_ui()
	_setup_particles()
	_setup_dots()
	ui.add_child(SettingsMenu.new())
	reset()
	_confirm_ota_later()

func _confirm_ota_later() -> void:
	# the OTA payload (if any) is promoted to known-good once the game has been running a few seconds
	var ota: Node = get_node_or_null("/root/Ota")
	if ota:
		await get_tree().create_timer(3.0).timeout
		ota.confirm_startup_success()

# ---------------------------------------------------------------- setup
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.55, 0.92)
	sm.sky_horizon_color = Color(0.78, 0.88, 0.97)
	sm.ground_horizon_color = Color(0.78, 0.88, 0.97)
	sm.ground_bottom_color = Color(0.45, 0.62, 0.40)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.2
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	_cam_aim_xf = Transform3D(Basis.IDENTITY, Vector3(-6.5, 4.2, 0.6)).looking_at(Vector3(10.0, 2.4, 0.0), Vector3.UP)
	cam.global_transform = _cam_aim_xf
	_noise.frequency = 2.0

func _setup_dots() -> void:
	for i in TRAJ_DOTS:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		sm.radial_segments = 8
		sm.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 1, 0.9)
		sm.material = m
		d.mesh = sm
		d.visible = false
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		_dots.append(d)

func _setup_particles() -> void:
	for i in 6:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 16
		p.lifetime = 0.8
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 8.0
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.18)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.78, 0.62)
		bm.material = m
		p.mesh = bm
		add_child(p)
		_particles.append(p)

func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	lbl_score = _label(48, HORIZONTAL_ALIGNMENT_CENTER)
	ui.add_child(lbl_score)
	lbl_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lbl_score.offset_top = 8
	lbl_score.offset_left = -300
	lbl_score.offset_right = 300
	lbl_hint = _label(34, HORIZONTAL_ALIGNMENT_CENTER)
	ui.add_child(lbl_hint)
	lbl_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_hint.offset_top = -90
	lbl_hint.offset_bottom = -20
	lbl_hint.offset_left = -400
	lbl_hint.offset_right = 400
	lbl_hint.text = "DRAG BACK, AIM, RELEASE!"
	lbl_stats = _label(22, HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_stats)
	lbl_stats.position = Vector2(16, 10)
	lbl_fps = _label(16, HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_fps)
	lbl_fps.position = Vector2(16, 690)
	lbl_fps.modulate = Color(1, 1, 1, 0.6)
	# power bar
	bar_bg = ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.45)
	bar_bg.position = Vector2(40, 640)
	bar_bg.size = Vector2(320, 26)
	bar_bg.visible = false
	ui.add_child(bar_bg)
	bar_fill = ColorRect.new()
	bar_fill.position = Vector2(3, 3)
	bar_fill.size = Vector2(0, 20)
	bar_bg.add_child(bar_fill)
	# result panel
	result_panel = PanelContainer.new()
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -300
	result_panel.offset_right = 300
	result_panel.offset_top = -180
	result_panel.offset_bottom = 190
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.82)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	result_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(vb)
	lbl_result = _label(60, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lbl_result)
	lbl_breakdown = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_breakdown.modulate = Color(0.85, 0.92, 1.0)
	vb.add_child(lbl_breakdown)
	btn_again = Button.new()
	btn_again.text = "AGAIN!"
	btn_again.custom_minimum_size = Vector2(320, 100)
	btn_again.add_theme_font_size_override("font_size", 52)
	btn_again.focus_mode = Control.FOCUS_NONE
	btn_again.pressed.connect(_on_again)
	vb.add_child(btn_again)
	result_panel.visible = false
	ui.add_child(result_panel)
	# dev reset
	btn_reset = Button.new()
	btn_reset.text = "RESET"
	btn_reset.focus_mode = Control.FOCUS_NONE
	btn_reset.add_theme_font_size_override("font_size", 26)
	btn_reset.custom_minimum_size = Vector2(130, 80)
	btn_reset.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn_reset.offset_left = -150
	btn_reset.offset_top = 12
	btn_reset.offset_right = -16
	btn_reset.offset_bottom = 92
	btn_reset.pressed.connect(_on_again)
	ui.add_child(btn_reset)

func _label(sz: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------- reset
func _on_again() -> void:
	reset()

func reset() -> void:
	if is_instance_valid(town):
		town.queue_free()
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()
	# rebuild immediately (free now so counts/tests are deterministic)
	for n in get_children():
		if n is Town or n is Ragdoll:
			remove_child(n)
			n.queue_free()
	town = Town.new()
	add_child(town)
	town.build()
	town.piece_released.connect(_on_piece_released)
	scoring = Scoring.new()
	scoring.awarded.connect(_on_awarded)
	ragdoll = Ragdoll.new()
	add_child(ragdoll)
	ragdoll.build(Ragdoll.random_letter(), Transform3D(Basis.IDENTITY, LAUNCH_ORIGIN))
	ragdoll.impact.connect(_on_impact)
	state = State.AIM
	dragging = false
	aim_power = 0.0
	drag_vec = Vector2.ZERO
	t_first_impact = -1.0
	settle_timer = 0.0
	flip_angle = 0.0
	trauma = 0.0
	cam_blend = 0.0
	frame_sum = 0.0
	frame_n = 0
	frame_worst = 0.0
	attempt += 1
	_set_aim_pose(Vector3.RIGHT, 0.0)
	result_panel.visible = false
	lbl_hint.visible = true
	lbl_hint.text = "DRAG BACK, AIM, RELEASE!" if attempt <= 1 else "AGAIN! Drag back and let go."
	for d in _dots:
		d.visible = false
	cam.global_transform = _cam_aim_xf
	_update_hud()

func _set_aim_pose(dir: Vector3, power: float) -> void:
	var b := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2.0) * Basis(Vector3.UP, PI)
	var pos: Vector3 = LAUNCH_ORIGIN - dir * PULL_LEN * power
	ragdoll.set_pose(Transform3D(b, pos))
	town.set_band(pos)

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.RESULT:
				reset()   # tap anywhere = instant retry, and the same touch starts the next aim
			if state == State.AIM:
				dragging = true
				drag_start = event.position
				drag_vec = Vector2.ZERO
				lbl_hint.visible = false
		elif dragging:
			dragging = false
			if state == State.AIM:
				if aim_power >= MIN_POWER:
					fire()
				else:
					aim_power = 0.0
					_set_aim_pose(Vector3.RIGHT, 0.0)
					for d in _dots:
						d.visible = false
					bar_bg.visible = false
	elif event is InputEventMouseMotion and dragging and state == State.AIM:
		drag_vec = event.position - drag_start
		_update_aim()

func _update_aim() -> void:
	var max_px: float = 190.0
	var p: Vector2 = drag_vec / max_px
	if p.length() > 1.0:
		p = p.normalized()
	aim_power = p.length()
	var up: float = clampf(p.y, 0.05, 1.0) * 1.6
	var side: float = -p.x * 0.7
	aim_dir = Vector3(1.0, up, side).normalized()
	_set_aim_pose(aim_dir, aim_power)
	_update_preview()
	bar_bg.visible = true
	bar_fill.size.x = 314.0 * aim_power
	bar_fill.color = Color(0.3, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.2), aim_power)

func launch_speed() -> float:
	return lerpf(MIN_SPEED, MAX_SPEED, pow(aim_power, 0.9))

func _update_preview() -> void:
	var v: Vector3 = aim_dir * launch_speed()
	var p0: Vector3 = ragdoll.centre()
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for i in _dots.size():
		var t: float = 0.1 * float(i + 1)
		var pos: Vector3 = p0 + v * t + Vector3(0, -0.5 * g * t * t, 0)
		_dots[i].global_position = pos
		_dots[i].visible = pos.y > 0.1 and aim_power >= MIN_POWER

## Fire with the current aim (also used by tests).
func fire() -> void:
	if state != State.AIM:
		return
	state = State.FLIGHT
	t_launch = Time.get_ticks_msec() / 1000.0
	for d in _dots:
		d.visible = false
	bar_bg.visible = false
	town.set_band(LAUNCH_ORIGIN)
	var spin := Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8))
	ragdoll.launch(aim_dir * launch_speed(), spin)
	sfx.play("launch", 0.0, randf_range(0.9, 1.1))
	trauma = 0.25
	lbl_hint.visible = false
	flip_angle = 0.0
	settle_timer = 0.0
	_update_hud()

# ---------------------------------------------------------------- events
func _on_impact(part: RigidBody3D, other: Node, speed: float, pos: Vector3) -> void:
	if state != State.FLIGHT:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if t_first_impact < 0.0 and speed > 2.0:
		t_first_impact = now
		var air: float = now - t_launch
		scoring.award("air", "AIRTIME %.1fs" % air, int(air * 40.0), "Airtime", pos)
	if speed > 4.0 and now - _last_sound > 0.06:
		_last_sound = now
		var heavy: bool = other.has_meta("kind") or other.has_meta("prop")
		sfx.play("crash" if (heavy and speed > 12.0) else "thud", clampf(speed * 0.4 - 12.0, -10.0, 2.0), randf_range(0.85, 1.2))
		trauma = maxf(trauma, clampf(speed / 32.0, 0.0, 0.8))
	if other.has_meta("kind") and (other as RigidBody3D).freeze:
		var piece := other as RigidBody3D
		var vel: Vector3 = ragdoll.prev_velocity(part)
		var released: Array[RigidBody3D] = town.smash(piece, pos, vel.normalized(), speed)
		if released.size() > 0:
			# bust through: the thing we hit gives way, keep most of our momentum
			part.linear_velocity = vel * 0.6
			_burst(pos)
			sfx.play("crash", 2.0, randf_range(0.8, 1.1))
			trauma = maxf(trauma, 0.7)
	elif other.has_meta("prop") and speed > 6.0:
		scoring.award("hit_%d" % other.get_instance_id(), "WHAM!", 25, "Impacts", pos)
		_burst(pos)
	elif other.has_meta("ground") == false and not other.has_meta("kind") and not other.has_meta("prop") and speed > 10.0:
		scoring.award("hit_%d" % other.get_instance_id(), "BONK!", 25, "Impacts", pos)

func _on_piece_released(p: RigidBody3D) -> void:
	if state != State.FLIGHT:
		return
	scoring.add_smash(p.get_instance_id(), 12, p.global_position)
	if p.has_meta("bonus"):
		var b: Dictionary = p.get_meta("bonus")
		scoring.award(str(b["key"]), str(b["name"]), int(b["pts"]), "Bonuses", p.global_position)

func _on_awarded(label: String, pts: int, world_pos: Vector3) -> void:
	_update_hud()
	if label == "" or state == State.RESULT:
		return
	sfx.play("pop", -4.0, randf_range(0.9, 1.3))
	var l := _label(34, HORIZONTAL_ALIGNMENT_CENTER)
	ui.add_child(l)
	l.text = "%s +%d" % [label, pts]
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	var sp: Vector2 = Vector2(640, 200)
	if cam.is_position_in_frustum(world_pos):
		sp = cam.unproject_position(world_pos)
	l.position = sp - Vector2(150, 20) + Vector2(randf_range(-40, 40), 0)
	l.size = Vector2(300, 40)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func _burst(pos: Vector3) -> void:
	var p: CPUParticles3D = _particles[_pi]
	_pi = (_pi + 1) % _particles.size()
	p.global_position = pos
	p.restart()
	p.emitting = true

func _update_hud() -> void:
	lbl_score.text = "%d" % scoring.total()
	lbl_stats.text = "Best %d   Try #%d" % [best, attempt]

# ---------------------------------------------------------------- loop
func _physics_process(dt: float) -> void:
	if state != State.FLIGHT:
		return
	var c: Vector3 = ragdoll.centre()
	scoring.set_distance(c.x)
	flip_angle += ragdoll.torso.angular_velocity.length() * dt
	var want: int = mini(int(flip_angle / TAU), 6)
	while scoring.flips < want:
		scoring.flips += 1
		scoring.award("flip_%d" % scoring.flips, "FLIP x%d" % scoring.flips, 60, "Flips", c)
	_update_hud()
	# settle / out-of-bounds detection
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - t_launch
	var slow: bool = ragdoll.max_speed() < 0.8
	settle_timer = settle_timer + dt if (slow and elapsed > 1.0) else 0.0
	if settle_timer > 1.0 or elapsed > 18.0 or c.y < -20.0 or c.x > 150.0:
		_finish()

func _finish() -> void:
	state = State.RESULT
	var c: Vector3 = ragdoll.centre()
	var d: float = Vector2(c.x - Town.TARGET_X, c.z).length()
	if d < 2.5:
		scoring.award("bullseye", "BULLSEYE!", 500, "Bonuses", c)
	elif d < 8.0:
		scoring.award("target", "LANDED ON TARGET", 150, "Bonuses", c)
	var total: int = scoring.total()
	var new_best: bool = total > best
	if new_best:
		best = total
		_save_best()
	lbl_result.text = ("NEW BEST %d" if new_best else "SCORE %d") % total
	var lines: Array[String] = scoring.summary_lines()
	var avg: float = frame_sum / maxf(frame_n, 1)
	lines.append("frames avg %.1fms worst %.1fms" % [avg * 1000.0, frame_worst * 1000.0])
	lbl_breakdown.text = "\n".join(lines)
	result_panel.visible = true
	_update_hud()
	print("[launch] result total=%d avg=%.1fms worst=%.1fms" % [total, avg * 1000.0, frame_worst * 1000.0])

func _process(dt: float) -> void:
	if state == State.FLIGHT:
		frame_sum += dt
		frame_n += 1
		frame_worst = maxf(frame_worst, dt)
	lbl_fps.text = "%d fps  phys %.1fms  bodies %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))]
	_update_camera(dt)

func _update_camera(dt: float) -> void:
	var target_xf: Transform3D = _cam_aim_xf
	if state != State.AIM and is_instance_valid(ragdoll):
		var c: Vector3 = ragdoll.centre()
		if t_first_impact >= 0.0:
			cam_blend = minf(cam_blend + dt * 0.6, 1.0)
		var off: Vector3 = Vector3(-8.5, 3.2, 4.5).lerp(Vector3(-15.0, 6.5, 8.0), cam_blend)
		var pos: Vector3 = c + off
		pos.y = maxf(pos.y, 2.0)
		var look: Vector3 = c + Vector3(3.0, 0.5, 0.0)
		_cam_look = _cam_look.lerp(look, 1.0 - exp(-6.0 * dt))
		target_xf = Transform3D(Basis.IDENTITY, pos).looking_at(_cam_look, Vector3.UP)
		cam.global_position = cam.global_position.lerp(pos, 1.0 - exp(-4.0 * dt))
		cam.look_at(_cam_look, Vector3.UP)
	else:
		_cam_look = Vector3(10, 2.4, 0)
		cam.global_transform = cam.global_transform.interpolate_with(target_xf, 1.0 - exp(-10.0 * dt))
	trauma = maxf(trauma - dt * 1.4, 0.0)
	var t: float = Time.get_ticks_msec() * 0.001
	var s: float = trauma * trauma
	cam.h_offset = _noise.get_noise_2d(t * 60.0, 0.0) * 0.8 * s
	cam.v_offset = _noise.get_noise_2d(0.0, t * 60.0) * 0.8 * s

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://launch.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best)
	cf.save("user://launch.cfg")
