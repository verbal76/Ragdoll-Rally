extends Node3D
## RAGDOLL RALLY: LAUNCH - POC game controller.
## States: AIM (drag back) -> FLIGHT (launched, until settled) -> RESULT.

enum State { AIM, FLIGHT, RESULT }

const LAUNCH_ORIGIN := Vector3(0.0, 2.3, 0.0)
const PULL_LEN := 3.6
const MIN_SPEED := 12.0           # v0.4 tuning (classic G1/G2: 9.0 / 32.0, kept for the regression baseline)
const MAX_SPEED := 40.0
const CLASSIC_MIN_SPEED := 9.0
const CLASSIC_MAX_SPEED := 32.0
const MIN_POWER := 0.12
const TRAJ_DOTS := 30
const AIM_MAX_PX := 240.0         # drag length (virtual px) for full power; measured along the diagonal pull
const SIDE_GAIN := 1.0            # lateral aim gain (was 0.7 in G1: far-left/right targets need up to ~45 deg)
const MAX_FLIGHT_S := 13.0
const OVERDRIVE_MAX := 1.45       # pull past the old full-power point (1.0) for extra speed
const OVERDRIVE_SPEED := 56.0     # launch speed at full overdrive (old maximum 32.0 is reached at power 1.0)
const MIN_MARGIN := Vector2(40.0, 30.0)
const SKID_ACCEL := 6.0           # m/s^2 pushed along the ground velocity so the ragdoll skids through things
const SKID_MAX_SPEED := 36.0
const MAX_UPGRADE := 5
const UPGRADE_COST := [300, 600, 1000, 1600, 2500]
const SKIP_AFTER_S := 1.5

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
var force_rebuild: bool = false     # tests: rebuild the town on every reset (instead of the fast in-place reset)
var classic: bool = false           # tests: G1/G2 speeds, materials and no skid assist (physics regression vs 4.4.1)
var up_power: int = 0
var up_speed: int = 0
var up_traj: int = 0
var bank: int = 0
var _flash_light: OmniLight3D
var upgrade_panel: Control
var _up_rows: Dictionary = {}
var btn_upgrades: Button
var legacy_world: bool = false      # tests: original small village only (physics baseline)
var view_right: bool = false        # false: pull toward lower-left, true: lower-right
var _basis_back: Vector2 = Vector2(-0.77, 0.64)    # screen direction of "pull back" (world -X)
var _basis_side: Vector2 = Vector2(0.64, 0.77)     # screen direction of world +Z
var _last_event: float = 0.0
var flight_t: float = 0.0           # physics-time clock since launch (deterministic; not wall-clock)
var _trav_dir: Vector3 = Vector3.RIGHT
var _gaps_done: Dictionary = {}
var _landed: bool = false
var margins: Vector4 = Vector4(40, 30, 40, 30)   # left, top, right, bottom (canvas px, safe-area aware)
var _bar_tick: ColorRect
var menu: SettingsMenu
var _prev_x: float = 0.0

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
	menu = SettingsMenu.new()
	menu.main_ref = self
	ui.add_child(menu)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
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
	cam.fov = 56.0
	cam.near = 0.2
	cam.far = 500.0
	add_child(cam)
	cam.current = true
	_compute_aim_camera()
	cam.global_transform = _cam_aim_xf
	_noise.frequency = 2.0

## Three-quarter opening view: camera behind the launcher, raised and rotated ~30 deg so the
## pull-back direction (world -X) points toward a LOWER screen corner and more of the field
## to the left/right is visible.
func _compute_aim_camera() -> void:
	var zs: float = -1.0 if view_right else 1.0           # camera sits on the +Z side (pull toward lower-left) or -Z side
	var fh := Vector3(cos(deg_to_rad(30.0)), 0.0, -sin(deg_to_rad(30.0)) * zs)
	var pos: Vector3 = LAUNCH_ORIGIN - fh * 26.0 + Vector3(0, 13.0, 0)
	_cam_aim_xf = Transform3D(Basis.IDENTITY, pos).looking_at(LAUNCH_ORIGIN + fh * 22.0 + Vector3(0, 0.5, 0), Vector3.UP)
	_update_aim_basis()

func _update_aim_basis() -> void:
	# screen-space directions of world -X (back) and +Z (side) at the launcher, from the aim camera
	var saved := cam.global_transform if cam else Transform3D.IDENTITY
	if cam:
		cam.global_transform = _cam_aim_xf
		var o: Vector2 = cam.unproject_position(LAUNCH_ORIGIN)
		_basis_back = (cam.unproject_position(LAUNCH_ORIGIN + Vector3(-6, 0, 0)) - o).normalized()
		_basis_side = (cam.unproject_position(LAUNCH_ORIGIN + Vector3(0, 0, 6)) - o).normalized()
		cam.global_transform = saved

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
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.6, 0.2)
	_flash_light.omni_range = 26.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)
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
	_bar_tick = ColorRect.new()          # marks the old full-power point; beyond it = overdrive
	_bar_tick.color = Color(1, 1, 1, 0.9)
	_bar_tick.size = Vector2(3, 26)
	_bar_tick.position = Vector2(3.0 + 314.0 / OVERDRIVE_MAX, 0)
	bar_bg.add_child(_bar_tick)
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
	btn_upgrades = Button.new()
	btn_upgrades.text = "UPGRADES"
	btn_upgrades.custom_minimum_size = Vector2(300, 100)
	btn_upgrades.add_theme_font_size_override("font_size", 40)
	btn_upgrades.focus_mode = Control.FOCUS_NONE
	btn_upgrades.pressed.connect(open_upgrades)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(btn_again)
	row.add_child(btn_upgrades)
	vb.add_child(row)
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
	_build_upgrade_panel()

const UP_INFO := {
	"power": ["POWER", "heavier ragdoll, harder skid, plows through more"],
	"speed": ["SPEED", "+6% launch speed per level"],
	"traj": ["TRAJECTORY", "longer aim preview, less air drag"]}

func _build_upgrade_panel() -> void:
	upgrade_panel = Control.new()
	upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	upgrade_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_panel.add_child(dim)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 0.5
	pc.anchor_bottom = 0.5
	pc.offset_left = -520
	pc.offset_right = 520
	pc.offset_top = -280
	pc.offset_bottom = 280
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var title := _label(44, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "UPGRADES"
	vb.add_child(title)
	var bl := _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	bl.name = "BankLabel"
	vb.add_child(bl)
	for key in ["power", "speed", "traj"]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		var l := _label(26, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(700, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(l)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(250, 90)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			buy(key)
			_refresh_upgrades())
		r.add_child(b)
		vb.add_child(r)
		_up_rows[key] = {"label": l, "btn": b}
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(300, 80)
	close.add_theme_font_size_override("font_size", 36)
	close.pressed.connect(func(): upgrade_panel.visible = false)
	vb.add_child(close)
	upgrade_panel.add_child(pc)
	ui.add_child(upgrade_panel)

func get_level(key: String) -> int:
	match key:
		"power": return up_power
		"speed": return up_speed
		"traj": return up_traj
	return 0

func upgrade_cost(key: String) -> int:
	var lv: int = get_level(key)
	return -1 if lv >= MAX_UPGRADE else int(UPGRADE_COST[lv])

## Spend banked points on a level. Returns true if bought.
func buy(key: String) -> bool:
	var cost: int = upgrade_cost(key)
	if cost < 0 or bank < cost:
		return false
	bank -= cost
	match key:
		"power": up_power += 1
		"speed": up_speed += 1
		"traj": up_traj += 1
	_save_progress()
	_update_hud()
	return true

func open_upgrades() -> void:
	_refresh_upgrades()
	upgrade_panel.visible = true

func _refresh_upgrades() -> void:
	(upgrade_panel.find_child("BankLabel", true, false) as Label).text = "Bank: %d points (you bank every score)" % bank
	for key in _up_rows.keys():
		var lv: int = get_level(key)
		var cost: int = upgrade_cost(key)
		(_up_rows[key]["label"] as Label).text = "%s   Lv %d/%d   %s" % [UP_INFO[key][0], lv, MAX_UPGRADE, UP_INFO[key][1]]
		var bt := _up_rows[key]["btn"] as Button
		bt.text = "MAX" if cost < 0 else "BUY  %d" % cost
		bt.disabled = cost < 0 or bank < cost

func _label(sz: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Keep every HUD element inside the visible/safe area (rounded corners, cutouts, nav bars).
func _apply_safe_area() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if win.x > 0.0 and win.y > 0.0:
		var sa: Rect2i = DisplayServer.get_display_safe_area()
		var scr: Vector2i = DisplayServer.screen_get_size()
		var spos: Vector2i = DisplayServer.screen_get_position()
		if sa.size.x > 0 and scr.x > 0:
			var k: Vector2 = Vector2(vp.x / win.x, vp.y / win.y)
			l = maxf(float(sa.position.x - spos.x), 0.0) * k.x
			t = maxf(float(sa.position.y - spos.y), 0.0) * k.y
			r = maxf(float(scr.x - (sa.position.x - spos.x) - sa.size.x), 0.0) * k.x
			b = maxf(float(scr.y - (sa.position.y - spos.y) - sa.size.y), 0.0) * k.y
	margins = Vector4(maxf(l, MIN_MARGIN.x), maxf(t, MIN_MARGIN.y), maxf(r, MIN_MARGIN.x), maxf(b, MIN_MARGIN.y))
	lbl_stats.position = Vector2(margins.x, margins.y)
	lbl_fps.position = Vector2(margins.x, vp.y - margins.w - 22.0)
	bar_bg.position = Vector2(margins.x + 10.0, vp.y - margins.w - 86.0)
	btn_reset.offset_right = -margins.z
	btn_reset.offset_left = -margins.z - 134.0
	btn_reset.offset_top = margins.y
	btn_reset.offset_bottom = margins.y + 80.0
	lbl_score.offset_top = margins.y - 6.0
	lbl_hint.offset_top = -margins.w - 76.0
	lbl_hint.offset_bottom = -margins.w
	if menu:
		menu.relayout(margins)

# ---------------------------------------------------------------- reset
func _on_again() -> void:
	reset()

func reset() -> void:
	if is_instance_valid(ragdoll):
		remove_child(ragdoll)
		ragdoll.queue_free()
	if is_instance_valid(town) and town.legacy == legacy_world and not force_rebuild:
		town.reset_in_place()          # fast path: no rebuild
	else:
		if is_instance_valid(town):
			remove_child(town)
			town.queue_free()
		town = Town.new()
		add_child(town)
		town.build(legacy_world)
		town.piece_released.connect(_on_piece_released)
	scoring = Scoring.new()
	scoring.awarded.connect(_on_awarded)
	scoring.claimed.connect(town.claim)
	ragdoll = Ragdoll.new()
	add_child(ragdoll)
	ragdoll.build(Ragdoll.random_letter(), Transform3D(Basis.IDENTITY, LAUNCH_ORIGIN), not classic, 0.0 if classic else 1.0 * up_power)
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
	_last_event = 0.0
	_gaps_done = {}
	_landed = false
	_trav_dir = Vector3.RIGHT
	_compute_aim_camera()
	_set_aim_pose(Vector3.RIGHT, 0.0)
	result_panel.visible = false
	if upgrade_panel:
		upgrade_panel.visible = false
	lbl_hint.visible = true
	lbl_hint.text = "DRAG BACK, AIM, RELEASE!" if attempt <= 1 else "AGAIN! Drag back and let go."
	for d in _dots:
		d.visible = false
	cam.global_transform = _cam_aim_xf
	_update_hud()

## Where the pouch sits for a given aim. Clamped above the ground: a steep full pull used to put the
## ragdoll BELOW the ground (G1/G2 bug: such launches went nowhere).
func pouch_pos(dir: Vector3, power: float) -> Vector3:
	var pos: Vector3 = LAUNCH_ORIGIN - dir * PULL_LEN * minf(power, 1.0) - dir * 0.8 * maxf(power - 1.0, 0.0)
	pos.y = maxf(pos.y, 1.5)
	return pos

func _set_aim_pose(dir: Vector3, power: float) -> void:
	var b := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2.0) * Basis(Vector3.UP, PI)
	var pos: Vector3 = pouch_pos(dir, power)
	ragdoll.set_pose(Transform3D(b, pos))
	town.set_band(pos)

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.FLIGHT and flight_t > SKIP_AFTER_S:
				_finish()   # tap during the chaos = skip to the result (score kept)
				return
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
	# decompose the finger drag in the camera-aligned basis: b = pull-back amount, sd = sideways amount
	var det: float = _basis_back.x * _basis_side.y - _basis_back.y * _basis_side.x
	var b: float = 0.0
	var sd: float = 0.0
	if absf(det) > 0.05:
		b = (drag_vec.x * _basis_side.y - drag_vec.y * _basis_side.x) / det
		sd = (_basis_back.x * drag_vec.y - _basis_back.y * drag_vec.x) / det
	var p := Vector2(sd, b) / AIM_MAX_PX
	if p.length() > OVERDRIVE_MAX:
		p = p.normalized() * OVERDRIVE_MAX
	aim_power = p.length()                                # 0..1 = the old power range, 1..1.45 = overdrive
	var up: float = clampf(p.y, 0.05, 1.0) * 1.6          # same elevation + power curve as G1/G2
	var side: float = -clampf(p.x, -1.0, 1.0) * SIDE_GAIN
	aim_dir = Vector3(1.0, up, side).normalized()
	_set_aim_pose(aim_dir, aim_power)
	_update_preview()
	bar_bg.visible = true
	bar_fill.size.x = 314.0 * clampf(aim_power / OVERDRIVE_MAX, 0.0, 1.0)
	if aim_power <= 1.0:
		bar_fill.color = Color(0.3, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.2), aim_power)
	else:
		bar_fill.color = Color(1.0, 0.25, 0.2).lerp(Color(0.8, 0.3, 1.0), (aim_power - 1.0) / (OVERDRIVE_MAX - 1.0))
	lbl_hint.visible = aim_power > 1.02
	lbl_hint.text = "OVERDRIVE!"
	_bar_tick.position.x = 3.0 + 314.0 / OVERDRIVE_MAX

static func speed_for_power(p: float, cls: bool = false) -> float:
	var lo: float = CLASSIC_MIN_SPEED if cls else MIN_SPEED
	var hi: float = CLASSIC_MAX_SPEED if cls else MAX_SPEED
	if p <= 1.0:
		return lerpf(lo, hi, pow(p, 0.9))
	return lerpf(hi, OVERDRIVE_SPEED if not cls else 46.0, clampf((p - 1.0) / (OVERDRIVE_MAX - 1.0), 0.0, 1.0))

## 1.0 up to the old full power; fades to 0 at full overdrive so the longest shots fly nearly ballistic.
static func air_drag_scale(p: float) -> float:
	return clampf(1.0 - (p - 1.0) / (OVERDRIVE_MAX - 1.0), 0.0, 1.0)

func launch_speed() -> float:
	return speed_for_power(aim_power, classic) * (1.0 if classic else (1.0 + 0.06 * up_speed))

func _update_preview() -> void:
	var v: Vector3 = aim_dir * launch_speed()
	var p0: Vector3 = ragdoll.centre()
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for i in _dots.size():
		var t: float = 0.16 * (1.0 if classic else 1.0 + 0.25 * up_traj) * float(i + 1)
		var pos: Vector3 = p0 + v * t + Vector3(0, -0.5 * g * t * t, 0)
		_dots[i].global_position = pos
		_dots[i].visible = pos.y > 0.1 and aim_power >= MIN_POWER

## Fire with the current aim (also used by tests).
func fire() -> void:
	if state != State.AIM:
		return
	state = State.FLIGHT
	t_launch = 0.0
	flight_t = 0.0
	for d in _dots:
		d.visible = false
	bar_bg.visible = false
	town.set_band(LAUNCH_ORIGIN)
	var spin := Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8))
	ragdoll.launch(aim_dir * launch_speed(), spin, air_drag_scale(aim_power) * (1.0 if classic else maxf(1.0 - 0.12 * up_traj, 0.0)))
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
	var now: float = flight_t
	if t_first_impact < 0.0 and speed > 2.0:
		t_first_impact = now
		var air: float = now - t_launch
		scoring.award("air", "AIRTIME %.1fs" % air, int(air * 40.0), "Airtime", pos)
	if speed > 3.0:
		_last_event = now
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
			var dmg: int = 0
			for rp in released:
				var pts: int = damage_points(rp, speed)
				if scoring.add_smash(rp.get_instance_id(), pts, rp.global_position):
					dmg += pts
			scoring.awarded.emit("SMASH x%d" % released.size(), dmg, pos)
			# bust through: the thing we hit gives way, keep most of our momentum (skid on through)
			if classic:
				part.linear_velocity = vel * 0.6
			else:
				var keep: float = 0.85 + 0.02 * up_power
				for bd in ragdoll.bodies:
					bd.linear_velocity = bd.linear_velocity.lerp(vel * keep, 0.8)
			_burst(pos)
			sfx.play("crash", 2.0, randf_range(0.8, 1.1))
			trauma = maxf(trauma, 0.7)
	elif other.has_meta("decor") and speed > 5.0:
		var dvel: Vector3 = ragdoll.prev_velocity(part)
		if town.break_decor(other as StaticBody3D, dvel.normalized(), speed):
			scoring.add_smash(other.get_instance_id(), int(8.0 * clampf(speed / 14.0, 0.6, 2.5)), pos)
			if not classic:
				var dk: float = 0.88 + 0.02 * up_power
				for bd in ragdoll.bodies:
					bd.linear_velocity = bd.linear_velocity.lerp(dvel * dk, 0.7)
			_burst(pos)
			trauma = maxf(trauma, 0.35)
			if town.decor_smashed % 10 == 0:
				scoring.award("demo_%d" % town.decor_smashed, "DEMOLITION x%d" % town.decor_smashed, town.decor_smashed * 10, "Impacts", pos)
	elif other.has_meta("ground") and not _landed and speed > 3.0:
		_landed = true
		var ra: Dictionary = town.ring_award(pos)
		if not ra.is_empty():
			scoring.award(str(ra["key"]), str(ra["name"]), int(ra["pts"]), "Targets", pos)
			if bool(ra["dead"]):
				trauma = 0.9
				sfx.play("boing", 2.0, 1.2)
	elif other.has_meta("prop") and other.has_meta("explosive") and speed > 5.0:
		_blast(other as RigidBody3D)
	elif other.has_meta("prop") and speed > 6.0:
		if other.has_meta("bonus"):
			var bb: Dictionary = other.get_meta("bonus")
			scoring.award(str(bb["key"]), str(bb["name"]), int(bb["pts"]), "Targets", pos)
		var pm: float = (other as RigidBody3D).mass if other is RigidBody3D else 1.0
		scoring.award("hit_%d" % other.get_instance_id(), "WHAM!", int((10.0 + pm * 4.0) * clampf(speed / 14.0, 0.6, 2.5)), "Impacts", pos)
		_burst(pos)
	elif other.has_meta("ground") == false and not other.has_meta("kind") and not other.has_meta("prop") and speed > 10.0:
		scoring.award("hit_%d" % other.get_instance_id(), "BONK!", 25, "Impacts", pos)

func _blast(b: RigidBody3D) -> void:
	var res: Dictionary = town.detonate(b)
	var blasts: Array = res["blasts"]
	if blasts.is_empty():
		return
	var dmg: int = 0
	for rp in (res["released"] as Array):
		if scoring.add_smash((rp as RigidBody3D).get_instance_id(), damage_points(rp as RigidBody3D, 24.0), (rp as RigidBody3D).global_position):
			dmg += damage_points(rp as RigidBody3D, 24.0)
	scoring.award("tnt_%d" % b.get_instance_id(), "BOOM x%d" % blasts.size(), 60 * blasts.size() + dmg, "Explosions", b.global_position)
	for c in blasts:
		_burst(c)
	_flash(blasts[0])
	trauma = 1.0
	sfx.play("crash", 4.0, 0.7)
	_last_event = flight_t
	for c in blasts:
		for bd in ragdoll.bodies:
			var dv: Vector3 = bd.global_position - (c as Vector3)
			var dist: float = dv.length()
			if dist < 9.0:
				bd.apply_central_impulse((dv.normalized() + Vector3(0, 0.5, 0)).normalized() * 20.0 * (1.0 - dist / 9.0) * bd.mass)

func _flash(pos: Vector3) -> void:
	_flash_light.global_position = pos + Vector3(0, 1.5, 0)
	_flash_light.light_energy = 14.0
	var tw := create_tween()
	tw.tween_property(_flash_light, "light_energy", 0.0, 0.3)

## Damage score: heavier pieces and harder hits are worth more.
func damage_points(p: RigidBody3D, impact_speed: float) -> int:
	return int(round((5.0 + 3.0 * p.mass) * clampf(impact_speed / 14.0, 0.6, 2.5)))

func _on_piece_released(p: RigidBody3D) -> void:
	if state != State.FLIGHT:
		return
	_last_event = flight_t
	if p.has_meta("bonus"):
		var b: Dictionary = p.get_meta("bonus")
		scoring.award(str(b["key"]), str(b["name"]), int(b["pts"]), "Targets", p.global_position)

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
	var hit: int = 0
	for t in town.targets:
		if scoring.keys.has(str(t["key"])):
			hit += 1
	lbl_stats.text = "Best %d   Bank %d   Try #%d   Targets %d/%d" % [best, bank, attempt, hit, town.targets.size()]

# ---------------------------------------------------------------- loop
func _physics_process(dt: float) -> void:
	if state != State.FLIGHT:
		return
	flight_t += dt
	if not classic:
		_skid(dt)
	var c: Vector3 = ragdoll.centre()
	scoring.set_distance(c.x)
	flip_angle += ragdoll.torso.angular_velocity.length() * dt
	var want: int = mini(int(flip_angle / TAU), 6)
	while scoring.flips < want:
		scoring.flips += 1
		scoring.award("flip_%d" % scoring.flips, "FLIP x%d" % scoring.flips, 60, "Flips", c)
	_update_hud()
	# thread-the-gap targets: the torso crosses a gate plane inside its opening
	for gp in town.gaps:
		var gk: String = str(gp["key"])
		if not _gaps_done.has(gk) and _prev_x < float(gp["x"]) and c.x >= float(gp["x"]) and absf(c.z) < float(gp["half"]) and c.y < float(gp["ymax"]) and c.y > 0.2:
			_gaps_done[gk] = true
			scoring.award(gk, str(gp["name"]), int(gp["pts"]), "Targets", c)
	_prev_x = c.x
	# end of flight: settled, or nothing interesting happening any more, or out of time/bounds
	var now: float = flight_t
	var elapsed: float = flight_t
	var spd: float = ragdoll.max_speed()
	settle_timer = settle_timer + dt if (spd < 1.0 and elapsed > 0.8) else 0.0
	var quiet: bool = elapsed > 2.0 and (now - maxf(_last_event, t_launch)) > 2.5 and c.y < 1.6 and spd < 4.0
	var oob: bool = c.y < -20.0 or c.x > Town.WORLD_X_MAX + 20.0 or absf(c.z) > Town.WORLD_Z + 20.0
	if settle_timer > 0.6 or quiet or elapsed > MAX_FLIGHT_S or oob:
		_finish()

## Arcade assist: keeps pushing along the ground velocity so the ragdoll skids through things instead of rolling to a stop.
func _skid(dt: float) -> void:
	var v: Vector3 = ragdoll.torso.linear_velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var sp: float = vh.length()
	if sp > 3.0 and sp < SKID_MAX_SPEED and ragdoll.torso.global_position.y < 1.7:
		var accel: float = SKID_ACCEL + 1.2 * float(up_power)
		var dirv: Vector3 = vh / sp
		for bd in ragdoll.bodies:
			bd.apply_central_impulse(dirv * accel * dt * bd.mass)

func _finish() -> void:
	if state == State.RESULT:
		return
	state = State.RESULT
	var c: Vector3 = ragdoll.centre()
	var ra: Dictionary = town.ring_award(c)
	if not ra.is_empty():
		scoring.award(str(ra["key"]), str(ra["name"]), int(ra["pts"]), "Targets", c)
	var total: int = scoring.total()
	bank += total
	_save_progress()
	var new_best: bool = total > best
	if new_best:
		best = total
		_save_best()
	lbl_result.text = ("NEW BEST %d" if new_best else "SCORE %d") % total
	var lines: Array[String] = scoring.summary_lines()
	var avg: float = frame_sum / maxf(frame_n, 1)
	var hit_names: Array[String] = []
	for t in town.targets:
		if scoring.keys.has(str(t["key"])):
			hit_names.append(str(t["name"]))
	lines.append("Targets: %d/%d  %s" % [hit_names.size(), town.targets.size(), ", ".join(hit_names)])
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
	if state != State.AIM and is_instance_valid(ragdoll):
		var c: Vector3 = ragdoll.centre()
		var v: Vector3 = ragdoll.torso.linear_velocity
		var vh := Vector3(v.x, 0.0, v.z)
		if vh.length() > 4.0:
			_trav_dir = _trav_dir.slerp(vh.normalized(), 1.0 - exp(-3.0 * dt)).normalized()
		if t_first_impact >= 0.0:
			cam_blend = minf(cam_blend + dt * 0.6, 1.0)
		var speed: float = v.length()
		var dist: float = lerpf(9.0 + clampf(speed * 0.22, 0.0, 6.0), 17.0, cam_blend)
		var height: float = lerpf(3.4, 7.5, cam_blend) + clampf(c.y * 0.25, 0.0, 6.0)
		var side := Vector3(-_trav_dir.z, 0.0, _trav_dir.x) * (4.5 if not view_right else -4.5)
		var pos: Vector3 = c - _trav_dir * dist + side + Vector3(0, height, 0)
		pos.x = clampf(pos.x, Town.WORLD_X_MIN + 2.0, Town.WORLD_X_MAX - 2.0)
		pos.z = clampf(pos.z, -Town.WORLD_Z + 2.0, Town.WORLD_Z - 2.0)
		pos.y = maxf(pos.y, 2.2)
		var look: Vector3 = c + _trav_dir * 3.0 + Vector3(0, 0.5, 0)
		_cam_look = _cam_look.lerp(look, 1.0 - exp(-7.0 * dt))
		cam.global_position = cam.global_position.lerp(pos, 1.0 - exp(-4.0 * dt))
		cam.look_at(_cam_look, Vector3.UP)
	else:
		_cam_look = LAUNCH_ORIGIN
		cam.global_transform = cam.global_transform.interpolate_with(_cam_aim_xf, 1.0 - exp(-10.0 * dt))
	trauma = maxf(trauma - dt * 1.4, 0.0)
	var t: float = Time.get_ticks_msec() * 0.001
	var sh: float = trauma * trauma
	cam.h_offset = _noise.get_noise_2d(t * 60.0, 0.0) * 0.8 * sh
	cam.v_offset = _noise.get_noise_2d(0.0, t * 60.0) * 0.8 * sh

func set_view_right(on: bool) -> void:
	view_right = on
	_compute_aim_camera()
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("view", "pull_right", on)
	cf.save("user://launch.cfg")

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://launch.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))
		view_right = bool(cf.get_value("view", "pull_right", false))
		bank = int(cf.get_value("progress", "bank", 0))
		up_power = int(cf.get_value("progress", "power", 0))
		up_speed = int(cf.get_value("progress", "speed", 0))
		up_traj = int(cf.get_value("progress", "traj", 0))

func _save_progress() -> void:
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("progress", "bank", bank)
	cf.set_value("progress", "power", up_power)
	cf.set_value("progress", "speed", up_speed)
	cf.set_value("progress", "traj", up_traj)
	cf.save("user://launch.cfg")

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("score", "best", best)
	cf.save("user://launch.cfg")
