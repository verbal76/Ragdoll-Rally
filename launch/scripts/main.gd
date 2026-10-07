extends Node3D
## RAGDOLL RALLY: LAUNCH - POC game controller.
## States: AIM (drag back) -> FLIGHT (launched, until settled) -> RESULT.

const Rules := preload("res://scripts/rules.gd")
const Fx := preload("res://scripts/fx.gd")
const SelectUI := preload("res://scripts/select_ui.gd")

enum State { AIM, FLIGHT, RESULT, SELECT }

const LAUNCH_ORIGIN := Vector3(0.0, 2.3, 0.0)
const PULL_LEN := 3.6
const MIN_SPEED := 20.0           # pivot tuning: PULL -> RELEASE -> WHAM (classic G1/G2: 9.0 / 32.0, kept for the regression baseline)
const MAX_SPEED := 50.0
const CLASSIC_MIN_SPEED := 9.0
const CLASSIC_MAX_SPEED := 32.0
const MIN_POWER := 0.12
const TRAJ_DOTS := 30
const AIM_MAX_PX := 240.0         # drag length (virtual px) for full power; measured along the diagonal pull
const SIDE_GAIN := 1.0            # lateral aim gain (was 0.7 in G1: far-left/right targets need up to ~45 deg)
const MAX_FLIGHT_S := 11.0
const OVERDRIVE_MAX := 1.45       # pull past the old full-power point (1.0) for extra speed
const OVERDRIVE_SPEED := 68.0     # launch speed at full overdrive (old maximum 32.0 is reached at power 1.0)
const MIN_MARGIN := Vector2(40.0, 30.0)
const SKID_ACCEL := 6.0           # m/s^2 pushed along the ground velocity so the ragdoll skids through things
const SKID_MAX_SPEED := 22.0       # assist tapers to nothing at this ground speed (no runaway)
var _skid_dir := Vector3.RIGHT      # horizontal launch heading; the assist only ever pushes forward along it
const SKIP_AFTER_S := 2.0
const COMBO_WINDOW := 1.6

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
var levels: Dictionary = {}            # upgrade key -> level (see Rules.UPGRADES)
var bank: int = 0
var char_idx: int = 0
var env_idx: int = 0
var fxp: Dictionary = {}               # Rules.effective() for the current character + upgrades (empty in classic)
var fx: Node                           # pooled effects (blood/debris/fire)
var energy: float = 1.0                # arcade energy left in this throw (decays per impact)
var skips: int = 0
var ricochets: int = 0
var limbs_lost: int = 0
var fires_started: int = 0
var gore: bool = true
var skip_select: bool = false          # tests: go straight to AIM
var air_input: float = 0.0             # -1..1 left/right swipe while airborne = extra rotation
var _air_start: Vector2 = Vector2.ZERO
var _air_drag: bool = false
var _imp_t: Dictionary = {}
var _tramp_uses: int = 0
var _hit_any: bool = false
var calm_t: float = 0.0
var _trails: Array = []                # [limb body, seconds left] blood trails (capped)
var _trail_acc: float = 0.0
var _burn_acc: float = 0.0
var _popups: int = 0
var _sky_mat: ProceduralSkyMaterial
var dev_tools: bool = false          # developer-only economy tools (never on in a normal build; see _ready)
var last_credit: int = 0
var _oob_at: float = -1.0
var _last_skip_t: float = -9.0
var _air_since_skip: bool = true
var economy_reset_note: bool = false
const ECONOMY_SCHEMA := 3          # 3 = 20-level mayhem upgrades (levels re-spent on the new curve, surplus refunded)
var migration_refund := 0
var _pop_slot: int = 0
var _wound_down: bool = false
var cam_event: float = 0.0             # briefly widens the camera after big events
var _last_boom: float = -9.0
var _fire_next: int = 4
var select_ui: Control
var btn_skip: Button
var btn_change: Button
var lbl_combo: Label
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
	# developer tools exist only when explicitly requested on the command line / environment; players never see them
	dev_tools = OS.get_cmdline_user_args().has("--dev-economy") or OS.get_environment("RR_DEV_ECONOMY") == "1"
	levels = Rules.empty_levels()
	_load_best()
	_setup_environment()
	sfx = Sfx.new()
	add_child(sfx)
	fx = Fx.new()
	add_child(fx)
	fx.gore = gore
	_setup_camera()
	_setup_ui()
	_setup_particles()
	_setup_dots()
	menu = SettingsMenu.new()
	menu.main_ref = self
	ui.add_child(menu)
	select_ui = SelectUI.new()
	select_ui.char_idx = clampi(char_idx, 0, Rules.CHARACTERS.size() - 1)
	select_ui.env_idx = clampi(env_idx, 0, Rules.ENVIRONMENTS.size() - 1)
	select_ui.chosen.connect(start_game)
	ui.add_child(select_ui)
	ui.move_child(menu, ui.get_child_count() - 1)     # the settings gear stays reachable on the selector
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	if skip_select:
		select_ui.visible = false
		reset()
	else:
		state = State.SELECT
	_confirm_ota_later()

## Called by the selector (and tests): pick a ragdoll + city and start throwing.
func start_game(ci: int, ei: int) -> void:
	char_idx = clampi(ci, 0, Rules.CHARACTERS.size() - 1)
	env_idx = clampi(ei, 0, Rules.ENVIRONMENTS.size() - 1)
	_save_choice()
	select_ui.visible = false
	reset()

func open_select() -> void:
	state = State.SELECT
	result_panel.visible = false
	upgrade_panel.visible = false
	select_ui.char_idx = char_idx
	select_ui.env_idx = env_idx
	select_ui.visible = true
	select_ui._show_page(0)
	select_ui._refresh()
	for d in _dots:
		d.visible = false
	bar_bg.visible = false

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
	_sky_mat = sm
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
	result_panel.offset_left = -420
	result_panel.offset_right = 420
	result_panel.offset_top = -290
	result_panel.offset_bottom = 290
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.82)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	result_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(vb)
	lbl_result = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lbl_result)
	lbl_breakdown = _label(21, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_breakdown.modulate = Color(0.85, 0.92, 1.0)
	vb.add_child(lbl_breakdown)
	btn_again = Button.new()
	btn_again.text = "AGAIN!"
	btn_again.custom_minimum_size = Vector2(300, 84)
	btn_again.add_theme_font_size_override("font_size", 52)
	btn_again.focus_mode = Control.FOCUS_NONE
	btn_again.pressed.connect(_on_again)
	btn_upgrades = Button.new()
	btn_upgrades.text = "UPGRADES"
	btn_upgrades.custom_minimum_size = Vector2(300, 84)
	btn_upgrades.add_theme_font_size_override("font_size", 40)
	btn_upgrades.focus_mode = Control.FOCUS_NONE
	btn_upgrades.pressed.connect(open_upgrades)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_change = Button.new()
	btn_change.text = "CHANGE"
	btn_change.custom_minimum_size = Vector2(240, 84)
	btn_change.add_theme_font_size_override("font_size", 34)
	btn_change.focus_mode = Control.FOCUS_NONE
	btn_change.pressed.connect(open_select)
	row.add_child(btn_again)
	row.add_child(btn_upgrades)
	row.add_child(btn_change)
	vb.add_child(row)
	result_panel.visible = false
	ui.add_child(result_panel)
	btn_skip = Button.new()
	btn_skip.text = "SKIP >>"
	btn_skip.focus_mode = Control.FOCUS_NONE
	btn_skip.add_theme_font_size_override("font_size", 26)
	btn_skip.custom_minimum_size = Vector2(170, 64)
	btn_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	btn_skip.offset_left = -85
	btn_skip.offset_right = 85
	btn_skip.offset_top = 80
	btn_skip.offset_bottom = 144
	btn_skip.visible = false
	btn_skip.pressed.connect(_finish)
	ui.add_child(btn_skip)
	lbl_combo = _label(34, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_combo.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	lbl_combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lbl_combo.offset_left = -300
	lbl_combo.offset_right = 300
	lbl_combo.offset_top = 66
	lbl_combo.offset_bottom = 110
	lbl_combo.visible = false
	ui.add_child(lbl_combo)
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

func _build_upgrade_panel() -> void:
	upgrade_panel = Control.new()
	upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	upgrade_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_panel.add_child(dim)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 0.5
	pc.anchor_bottom = 0.5
	pc.offset_left = -600
	pc.offset_right = 600
	pc.offset_top = -330
	pc.offset_bottom = 330
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.96)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(16)
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var title := _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "UPGRADES  (they stack!)"
	vb.add_child(title)
	var bl := _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	bl.name = "BankLabel"
	vb.add_child(bl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for key in Rules.UPGRADE_ORDER:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var l := _label(20, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(380, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(l)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 74)
		b.add_theme_font_size_override("font_size", 26)
		var k: String = key
		b.pressed.connect(func():
			buy(k)
			_refresh_upgrades())
		cell.add_child(b)
		grid.add_child(cell)
		_up_rows[key] = {"label": l, "btn": b}
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	if dev_tools:                                  # developer-only (cmdline --dev-economy / RR_DEV_ECONOMY=1)
		var dev := Button.new()
		dev.text = "DEV +10,000"
		dev.focus_mode = Control.FOCUS_NONE
		dev.custom_minimum_size = Vector2(300, 70)
		dev.add_theme_font_size_override("font_size", 28)
		dev.pressed.connect(dev_grant)
		row.add_child(dev)
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(300, 70)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(func(): upgrade_panel.visible = false)
	row.add_child(close)
	vb.add_child(row)
	upgrade_panel.add_child(pc)
	ui.add_child(upgrade_panel)

## Developer-only credit grant. Does nothing in a normal build.
func dev_grant(amount: int = 10000) -> void:
	if not dev_tools:
		return
	bank += amount
	_save_progress()
	_update_hud()
	_refresh_upgrades()

func get_level(key: String) -> int:
	return int(levels.get(key, 0))

func upgrade_cost(key: String) -> int:
	return Rules.upgrade_cost(key, get_level(key))

## Spend banked points on a level. Returns true if bought. Takes effect on the next throw.
func buy(key: String) -> bool:
	if not Rules.UPGRADES.has(key):
		return false
	var cost: int = upgrade_cost(key)
	if cost < 0 or bank < cost:
		return false
	bank -= cost
	levels[key] = get_level(key) + 1
	_save_progress()
	_update_hud()
	return true

func open_upgrades() -> void:
	_refresh_upgrades()
	upgrade_panel.visible = true

func _refresh_upgrades() -> void:
	(upgrade_panel.find_child("BankLabel", true, false) as Label).text = "Credits: %d  (earned from your throws, separate from score)" % bank
	for key in _up_rows.keys():
		var lv: int = get_level(key)
		var cost: int = upgrade_cost(key)
		var u: Dictionary = Rules.UPGRADES[key]
		(_up_rows[key]["label"] as Label).text = "%s  Lv %d/%d
%s" % [str(u["name"]), lv, int(u["max"]), str(u["desc"])]
		var bt := _up_rows[key]["btn"] as Button
		bt.text = "MAX" if cost < 0 else "BUY %d" % cost
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
	if btn_skip:
		btn_skip.offset_top = margins.y + 70.0
		btn_skip.offset_bottom = margins.y + 134.0
		lbl_combo.offset_top = margins.y + 58.0
		lbl_combo.offset_bottom = margins.y + 102.0
	if select_ui:
		select_ui.relayout(margins)
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
	var env_id: String = "city" if legacy_world else str(Rules.ENVIRONMENTS[env_idx]["id"])
	if not bool(Rules.ENVIRONMENTS[env_idx]["playable"]) and not legacy_world:
		env_id = "yard"
	if is_instance_valid(town) and town.legacy == legacy_world and town.env_id == env_id and not force_rebuild:
		town.reset_in_place()          # fast path: no rebuild
	else:
		if is_instance_valid(town):
			remove_child(town)
			town.queue_free()
		town = Town.new()
		town.fx = fx
		add_child(town)
		town.build(legacy_world, env_id)
		town.piece_released.connect(_on_piece_released)
		town.ignited.connect(_on_ignited)
		town.burned.connect(_on_burned)
	town.fx = fx
	fx.gore = gore
	fx.clear_all()
	_apply_theme(env_id)
	scoring = Scoring.new()
	scoring.combo_enabled = not classic
	scoring.awarded.connect(_on_awarded)
	scoring.claimed.connect(town.claim)
	var ch: Dictionary = Rules.CHARACTERS[char_idx]
	fxp = {} if classic else Rules.effective(ch["stats"] as Dictionary, levels)
	ragdoll = Ragdoll.new()
	add_child(ragdoll)
	ragdoll.build(Ragdoll.random_letter() if classic else str(ch["letter"]), Transform3D(Basis.IDENTITY, LAUNCH_ORIGIN), not classic, 0.0)
	if not classic:
		ragdoll.apply_fx(fxp)
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
	energy = 1.0
	skips = 0
	ricochets = 0
	limbs_lost = 0
	fires_started = 0
	_fire_next = 4
	_tramp_uses = 0
	_hit_any = false
	calm_t = 0.0
	_trails.clear()
	_oob_at = -1.0
	_last_skip_t = -9.0
	_air_since_skip = true
	_popups = 0
	_wound_down = false
	_imp_t.clear()
	air_input = 0.0
	_air_drag = false
	cam_event = 0.0
	_last_boom = -9.0
	_compute_aim_camera()
	_set_aim_pose(Vector3.RIGHT, 0.0)
	result_panel.visible = false
	if upgrade_panel:
		upgrade_panel.visible = false
	if select_ui:
		select_ui.visible = false
	btn_skip.visible = false
	lbl_combo.visible = false
	lbl_hint.visible = true
	lbl_hint.text = "DRAG BACK, AIM, RELEASE!" if attempt <= 1 else "AGAIN! Drag back and let go."
	for d in _dots:
		d.visible = false
	cam.global_transform = _cam_aim_xf
	cam.fov = 56.0
	_update_hud()

## Every city gets its own sky tint (and its ground colour, set by Town) so it reads as its own place.
func _apply_theme(env_id: String) -> void:
	if _sky_mat == null:
		return
	var th: Dictionary = Rules.env_by_id(env_id)["theme"]
	_sky_mat.sky_top_color = th["sky_top"]
	_sky_mat.sky_horizon_color = th["sky_hz"]
	_sky_mat.ground_horizon_color = th["sky_hz"]

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
	if state == State.SELECT:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.FLIGHT:
				_air_drag = true               # drag left/right while airborne = extra flip / spin
				_air_start = event.position
				return
			if state == State.RESULT:
				reset()   # tap anywhere = instant retry, and the same touch starts the next aim
			if state == State.AIM:
				dragging = true
				drag_start = event.position
				drag_vec = Vector2.ZERO
				lbl_hint.visible = false
		else:
			if _air_drag:
				_air_drag = false
				air_input = 0.0
			if dragging:
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
	elif event is InputEventMouseMotion:
		if dragging and state == State.AIM:
			drag_vec = event.position - drag_start
			_update_aim()
		elif _air_drag and state == State.FLIGHT:
			air_input = clampf((event.position.x - _air_start.x) / 160.0, -1.0, 1.0)

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
	var up: float = clampf(p.y, 0.05, 1.0) * (1.6 if classic else Rules.AIM_ELEV_GAIN)   # classic = G1/G2 elevation; pivot launches flatter and faster
	var side: float = -clampf(p.x, -1.0, 1.0) * SIDE_GAIN
	if classic:
		aim_dir = Vector3(1.0, up, side).normalized()
	else:
		# v13: the upward angle is soft-limited (Rules.soft_pitch_deg) so no gesture can fire a near-vertical rocket
		aim_dir = Rules.launch_dir(Vector3(1.0, 0.0, side), up / sqrt(1.0 + side * side))
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

## Height above the terrain (the world is flat, y = 0, in the older cities).
func _agl(p: Vector3) -> float:
	return p.y - (town.ground_y(p.x, p.z) if is_instance_valid(town) else 0.0)

func launch_speed() -> float:
	var v: float = speed_for_power(aim_power, classic) * (1.0 if classic else float(fxp.get("launch_mult", 1.0)))
	if classic:
		return v
	# v13: range/apex governor - no throw can fly over the whole playfield or reach the world wall
	return Rules.governed_speed(v, asin(clampf(aim_dir.y, -1.0, 1.0)), fxp)

func _update_preview() -> void:
	var v: Vector3 = aim_dir * launch_speed()
	var p0: Vector3 = ragdoll.centre()
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for i in _dots.size():
		var t: float = 0.13 * float(i + 1)
		var pos: Vector3 = p0 + v * t + Vector3(0, -0.5 * g * (1.0 if classic else 1.8) * t * t, 0)
		_dots[i].global_position = pos
		_dots[i].visible = _agl(pos) > 0.1 and aim_power >= MIN_POWER

## Fire with the current aim (also used by tests).
func fire() -> void:
	if state != State.AIM:
		return
	state = State.FLIGHT
	_skid_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	t_launch = 0.0
	flight_t = 0.0
	for d in _dots:
		d.visible = false
	bar_bg.visible = false
	town.set_band(LAUNCH_ORIGIN)
	var spin := Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8))
	if not classic:
		# the pouch orientation sets the tumble: pulled-back angle -> forward/back flip, plus a corkscrew
		spin = Vector3(randf_range(-4, 4), randf_range(-5, 5), -aim_dir.y * 9.0 + randf_range(-3, 3))
	ragdoll.launch(aim_dir * launch_speed(), spin, air_drag_scale(aim_power))
	sfx.play("launch", 0.0, randf_range(0.9, 1.1))
	trauma = 0.5 if not classic else 0.25
	cam_event = 0.4
	lbl_hint.visible = false
	flip_angle = 0.0
	settle_timer = 0.0
	_update_hud()

# ---------------------------------------------------------------- events
func _on_impact(part: RigidBody3D, other: Node, speed: float, pos: Vector3) -> void:
	if state != State.FLIGHT:
		return
	if classic:
		_on_impact_classic(part, other, speed, pos)
	else:
		_on_impact_pivot(part, other, speed, pos)

## Surface normal at the contact (pointing out of the surface, against the incoming velocity).
## Everything in the playgrounds is a box, so the normal comes from the box faces.
func _surface_normal(other: Node, pos: Vector3, vin: Vector3) -> Vector3:
	if other.has_meta("ground"):
		return town.ground_normal(pos.x, pos.z) if is_instance_valid(town) else Vector3.UP
	var n: Vector3 = Vector3.ZERO
	var half: Vector3 = Vector3.ZERO
	var xf: Transform3D = Transform3D.IDENTITY
	if other.has_meta("half") and other is Node3D:
		half = other.get_meta("half")
		xf = (other as Node3D).global_transform
	else:
		for ch in other.get_children():
			if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
				half = ((ch as CollisionShape3D).shape as BoxShape3D).size * 0.5
				xf = (ch as CollisionShape3D).global_transform
				break
	if half != Vector3.ZERO:
		n = Rules.box_normal(xf.affine_inverse() * pos, half, xf.basis)
	elif other is Node3D:
		n = pos - (other as Node3D).global_position
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else -vin.normalized()
	else:
		n = -vin.normalized()
	if n.dot(vin) > 0.0:
		n = -n
	return n

func _on_impact_pivot(part: RigidBody3D, other: Node, speed: float, pos: Vector3) -> void:
	var now: float = flight_t
	if speed < 2.0:
		return
	var okey: int = part.get_instance_id() * 7919 + other.get_instance_id()
	if now - float(_imp_t.get(okey, -9.0)) < 0.12:
		return                                  # contact chatter on the same pair
	_imp_t[okey] = now
	if t_first_impact < 0.0:
		t_first_impact = now
		var air: float = now - t_launch
		scoring.award("air", "AIRTIME %.1fs" % air, int(air * 50.0), "Airtime", pos)
	if other.has_meta("boundary"):
		_hit_boundary()
		return
	_hit_any = true
	if speed > 3.0:
		_last_event = now
	var limb: bool = ragdoll.is_detached(part)
	var pname: String = String(part.name)
	var vin: Vector3 = ragdoll.prev_velocity(part)
	var n: Vector3 = _surface_normal(other, pos, vin)
	var mat: String = "ground" if other.has_meta("ground") else str(other.get_meta("mat", "masonry"))
	if mat == "trampoline":
		_tramp_uses += 1
		if _tramp_uses > 3:
			mat = "ground"                      # springs wear out: no infinite bouncing
	var sev: float = Rules.severity(speed)
	var eff: float = speed * float(fxp["impact_power"]) * (0.55 if limb else 1.0)
	var pass_through: bool = false
	var keep: float = 0.85
	var vdir: Vector3 = vin.normalized() if vin.length() > 0.1 else Vector3.RIGHT
	# ---------------- things that give way
	if other.has_meta("glass"):
		if speed > 5.0 and town.break_glass(other as StaticBody3D):
			fx.debris("glass", pos, vdir, 1.0 + sev)
			scoring.award("glass_%d" % other.get_instance_id(), "GLASS!", int(30.0 * (1.0 + float(levels.get("destruction", 0)) * 0.2)), "Glass", pos)
			pass_through = true
			keep = 0.95
			mat = "glass"
	elif other.has_meta("kind") and other is RigidBody3D and (other as RigidBody3D).freeze:
		var piece := other as RigidBody3D
		var released: Array[RigidBody3D] = town.smash(piece, pos, vdir, eff * float(fxp["destruct_mult"]))
		if released.size() > 0:
			var dmg: int = 0
			for rp in released:
				var pts: int = int(damage_points(rp, eff) * float(fxp["destruct_mult"]))
				if scoring.add_smash(rp.get_instance_id(), pts, rp.global_position):
					dmg += pts
			scoring.awarded.emit("SMASH x%d" % released.size(), dmg, pos)
			var m0: String = str(piece.get_meta("mat", "masonry"))
			fx.debris(m0, pos, vdir, 0.8 + sev + 0.3 * float(levels.get("destruction", 0)))
			if released.size() >= 3:
				fx.crumble(pos, clampf(float(released.size()) / 6.0, 0.6, 2.0))
			if released.size() > 4:
				fx.debris(m0, (released[released.size() - 1] as Node3D).global_position, vdir, 1.0)
			sfx.play(str((Rules.MATERIALS.get(m0, Rules.MATERIALS["masonry"]) as Dictionary)["sound"]), 0.0, randf_range(0.8, 1.1))
			pass_through = true
			keep = 0.82 + 0.02 * float(levels.get("power", 0))
			mat = m0
	elif other.has_meta("decor"):
		if speed > 5.0 and town.break_decor(other as StaticBody3D, vdir, speed):
			scoring.add_smash(other.get_instance_id(), int(10.0 * clampf(eff / 14.0, 0.6, 2.5)), pos)
			fx.debris("wood", pos, vdir, 0.8 + sev)
			sfx.play("wood", -2.0, randf_range(0.9, 1.2))
			pass_through = true
			keep = 0.9
			mat = "wood"
			if town.decor_smashed % 10 == 0:
				scoring.award("demo_%d" % town.decor_smashed, "DEMOLITION x%d" % town.decor_smashed, town.decor_smashed * 10, "Impacts", pos)
	elif other.has_meta("prop"):
		if other.has_meta("explosive") and speed > 5.0:
			_blast(other as RigidBody3D)
		elif speed > 6.0:
			var pm: float = (other as RigidBody3D).mass if other is RigidBody3D else 1.0
			scoring.award("hit_%d" % other.get_instance_id(), "WHAM!", int((10.0 + pm * 4.0) * clampf(eff / 14.0, 0.6, 2.5)), "Impacts", pos)
	if other.has_meta("bonus") and not other.has_meta("kind") and speed > 6.0:
		var bb: Dictionary = other.get_meta("bonus")
		scoring.award(str(bb["key"]), str(bb["name"]), int(bb["pts"]), "Targets", pos)
	if other.has_meta("ground") and not _landed and speed > 3.0:
		_landed = true
		var ra: Dictionary = town.ring_award(pos)
		if not ra.is_empty():
			scoring.award(str(ra["key"]), str(ra["name"]), int(ra["pts"]), "Targets", pos)
	# ---------------- pass through (momentum mostly kept) or SKIP / RICOCHET (pebble model)
	if pass_through:
		for bd in ragdoll.bodies:
			if limb and bd != part:
				continue
			if not limb and ragdoll.is_detached(bd):
				continue
			bd.linear_velocity = bd.linear_velocity.lerp(vin * keep, 0.8)
	else:
		var face: String = ragdoll.torso_face(n) if part == ragdoll.torso else ""
		var mods: Dictionary = Rules.part_modifiers(pname, face)
		var resp: Dictionary = Rules.impact_response(vin, n, fxp, mat, mods, energy, randf_range(-1.0, 1.0))
		if bool(resp["bounced"]) and speed > 4.0:
			var v2: Vector3 = resp["v"]
			if v2.length() > 48.0:
				v2 = v2.normalized() * 48.0
			part.linear_velocity = v2
			part.angular_velocity += resp["omega"] as Vector3
			ragdoll.clamp_omega(part)
			if not limb:
				for bd in ragdoll.bodies:
					if bd != part and not ragdoll.is_detached(bd):
						bd.linear_velocity = bd.linear_velocity.lerp(v2, 0.55)
				if part != ragdoll.torso:
					ragdoll.torso.angular_velocity += (resp["omega"] as Vector3) * 0.5
					ragdoll.clamp_omega(ragdoll.torso)
			energy = Rules.energy_after(energy, fxp, speed)
			var graze: float = float(resp["graze"])
			if (mat == "ground" or mat == "trampoline" or mat == "water") and graze > 0.5 and speed > 8.0 \
					and now - _last_skip_t > 0.35 and _air_since_skip:
				# one physical bounce = one skip (v12 counted every body part touching the ground and paid 40*n)
				skips += 1
				_last_skip_t = now
				_air_since_skip = false
				scoring.award("skip_%d" % skips, "SKIP x%d" % skips, Rules.skip_points(skips), "Skips", pos)
				sfx.play("boing", -6.0, 1.0 + 0.05 * float(skips))
			elif mat != "ground" and absf(float(resp["ricochet_deg"])) > 8.0 and speed > 9.0:
				ricochets += 1
				scoring.award("rico_%d_%d" % [other.get_instance_id(), ricochets], "RICOCHET!", 80, "Ricochets", pos)
			var lab: String = str(mods["label"])
			if lab != "" and speed > 9.0:
				scoring.award("style_%s_%d" % [lab, int(now)], lab + "!", 25, "Style", pos)
			if mat == "metal" and speed > 8.0:
				fx.sparks(pos, n)
	# ---------------- body damage: limbs fly off, hard hits explode, fire spreads
	if not limb:
		var pr: float = Rules.dismember_chance(speed, pname, fxp)
		if pr > 0.0 and randf() < pr:
			_lose_limb(part, n, speed, pos)
		elif part == ragdoll.torso and speed > 20.0:
			var attached: Array[RigidBody3D] = []
			for bd in ragdoll.bodies:
				if bd != ragdoll.torso and not ragdoll.is_detached(bd) and bd.name != "head":
					attached.append(bd)
			if not attached.is_empty():
				var cand: RigidBody3D = attached[randi() % attached.size()]
				if randf() < Rules.dismember_chance(speed * 0.85, String(cand.name), fxp) * 0.6:
					_lose_limb(cand, n, speed, cand.global_position)
	if Rules.explosive_impact(speed, fxp, randf()) and now - _last_boom > 0.6:
		_last_boom = now
		var res: Dictionary = town.explode(pos, 7.0, 20.0)
		_apply_blast_result(res, "boomimpact_%d" % int(now * 10.0), pos)
	var ign: int = int(fxp.get("ignition", 0))
	if ign > 0 and speed >= float(fxp["ignite_speed"]) and not ragdoll.is_burning("torso"):
		ragdoll.ignite_all(7.0 + 3.0 * float(ign))
		scoring.award("ignite", "IGNITED!", 60, "Fire", pos)
		sfx.play("fire", -2.0, 1.0)
	if ragdoll.is_burning(pname) and other is Node3D:
		if town.is_combustible(other):
			town.ignite_node(other as Node3D)
		town.ignite_near(pos, 1.8, 0.7)
	# ---------------- feedback scaled by severity
	var tier: String = Rules.impact_tier(speed)
	var snd: String = str((Rules.MATERIALS.get(mat, Rules.MATERIALS["ground"]) as Dictionary)["sound"])
	if now - _last_sound > 0.05:
		_last_sound = now
		match tier:
			"light":
				sfx.play(snd, clampf(speed * 0.5 - 14.0, -12.0, -4.0), randf_range(0.9, 1.3))
			"medium":
				sfx.play(snd, -4.0, randf_range(0.85, 1.2))
			_:
				sfx.play("crash", 0.0 if tier == "major" else 3.0, randf_range(0.75, 1.0))
	match tier:
		"light":
			trauma = maxf(trauma, 0.1)
		"medium":
			trauma = maxf(trauma, 0.3)
			fx.dust(pos, 0.7)
			if randf() < 0.35:
				fx.blood(pos, n, 0.4)
		"major":
			trauma = maxf(trauma, 0.6)
			cam_event = maxf(cam_event, 0.5)
			fx.debris(mat, pos, n, 1.0)
			fx.dust(pos, 1.3)
			fx.blood(pos, n, 1.0)
			if n.y > 0.7:
				fx.splat(pos, n, 0.8)
			_burst(pos)
		"extreme":
			trauma = maxf(trauma, 0.95)
			cam_event = maxf(cam_event, 1.0)
			fx.debris(mat, pos, n, 1.6)
			fx.blood(pos, n, 1.8)
			fx.splat(pos, n, 1.2)
			_burst(pos)

## The world edge is NOT a destructive surface. Touching it ends the throw cleanly: no blood, limbs, explosions or score
## (v12: the invisible wall was treated as masonry, so a fast throw "exploded" in mid-air against nothing).
func _hit_boundary() -> void:
	if _oob_at >= 0.0:
		return
	_oob_at = flight_t + 0.45
	lbl_hint.visible = true
	lbl_hint.text = "OUT OF BOUNDS"
	for bd in ragdoll.bodies:
		bd.linear_velocity = bd.linear_velocity * 0.15
		bd.angular_velocity = bd.angular_velocity * 0.3
	ragdoll.burning.clear()

## Tear a limb off: stylised, bounded, never trivial.
func _lose_limb(part: RigidBody3D, n: Vector3, speed: float, pos: Vector3) -> void:
	var b: RigidBody3D = ragdoll.detach(String(part.name), n * speed * 0.25 + Vector3(0, speed * 0.18, 0))
	if b == null:
		return
	limbs_lost += 1
	fx.blood(pos, n, 1.4)
	if _agl(pos) < 1.6:
		fx.splat(Vector3(pos.x, town.ground_y(pos.x, pos.z), pos.z), town.ground_normal(pos.x, pos.z), 0.9)
	scoring.award("limb_%d" % b.get_instance_id(), "LIMB LOST!", 150, "Carnage", pos)
	sfx.play("limb", 0.0, randf_range(0.9, 1.2))
	trauma = maxf(trauma, 0.7)
	cam_event = maxf(cam_event, 0.8)
	_last_event = flight_t
	if _trails.size() < 4:
		_trails.append([b, 1.6])

func _on_ignited(node: Node3D, pos: Vector3) -> void:
	if state != State.FLIGHT:
		return
	fires_started += 1
	_last_event = flight_t
	scoring.award("fire_%d" % node.get_instance_id(), "", 12, "Fire", pos)
	if fires_started >= _fire_next:
		_fire_next += 4
		scoring.award("firespread_%d" % fires_started, "FIRE SPREADING x%d" % fires_started, 40 * (fires_started / 4), "Fire", pos)
		sfx.play("fire", -4.0, 0.9)

func _on_burned(node: Node3D, pos: Vector3) -> void:
	if state == State.FLIGHT:
		_last_event = flight_t
		scoring.award("burnt_%d" % node.get_instance_id(), "BURNED DOWN", 35, "Fire", pos)
	if node.has_meta("explosive") and node is RigidBody3D:
		_blast(node as RigidBody3D)

func _blast(b: RigidBody3D) -> void:
	var res: Dictionary = town.detonate(b)
	_apply_blast_result(res, "tnt_%d" % b.get_instance_id(), b.global_position)

func _apply_blast_result(res: Dictionary, key: String, origin: Vector3) -> void:
	var blasts: Array = res["blasts"]
	if blasts.is_empty():
		return
	var dmg: int = 0
	for rp in (res["released"] as Array):
		if scoring.add_smash((rp as RigidBody3D).get_instance_id(), damage_points(rp as RigidBody3D, 24.0), (rp as RigidBody3D).global_position):
			dmg += damage_points(rp as RigidBody3D, 24.0)
	scoring.award(key, "BOOM x%d" % blasts.size(), 60 * blasts.size() + dmg, "Explosions", origin)
	for c in blasts:
		_burst(c)
		fx.explosion(c, 7.0)
	_flash(blasts[0])
	trauma = 1.0
	cam_event = 1.0
	sfx.play("boom", 2.0, randf_range(0.85, 1.05))
	_last_event = flight_t
	if not classic:
		for c in blasts:
			for bd in ragdoll.bodies:
				var dv: Vector3 = bd.global_position - (c as Vector3)
				var dist: float = dv.length()
				if dist < 9.0:
					bd.apply_central_impulse((dv.normalized() + Vector3(0, 0.5, 0)).normalized() * 22.0 * (1.0 - dist / 9.0) * bd.mass)
	else:
		for c in blasts:
			for bd in ragdoll.bodies:
				var dv2: Vector3 = bd.global_position - (c as Vector3)
				var dist2: float = dv2.length()
				if dist2 < 9.0:
					bd.apply_central_impulse((dv2.normalized() + Vector3(0, 0.5, 0)).normalized() * 20.0 * (1.0 - dist2 / 9.0) * bd.mass)

func _on_impact_classic(part: RigidBody3D, other: Node, speed: float, pos: Vector3) -> void:
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
				var keep: float = 0.85 + 0.02 * 0
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
				var dk: float = 0.88 + 0.02 * 0
				for bd in ragdoll.bodies:
					bd.linear_velocity = bd.linear_velocity.lerp(dvel * dk, 0.7)
			_burst(pos)
			trauma = maxf(trauma, 0.35)
			if town.decor_smashed % 10 == 0:
				scoring.award("demo_%d" % town.decor_smashed, "DEMOLITION x%d" % town.decor_smashed, town.decor_smashed * 10, "Impacts", pos)
	elif other.has_meta("ground") and not _landed and speed > 3.0:
		_landed = true
		if not classic:
			# arcade: the first touchdown keeps most of the forward speed so it skids on instead of dead-stopping
			var pv: Vector3 = ragdoll.prev_velocity(part)
			var hv := Vector3(pv.x, 0.0, pv.z) * (0.62 + 0.02 * 0)
			for bd in ragdoll.bodies:
				var cv: Vector3 = bd.linear_velocity
				var tv := Vector3(hv.x, cv.y, hv.z)
				if Vector2(cv.x, cv.z).length() < hv.length():
					bd.linear_velocity = cv.lerp(tv, 0.8)
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
	if _popups >= 7:
		return                                  # keep the screen readable: drop extras (points still count)
	_popups += 1
	_pop_slot = (_pop_slot + 1) % 6
	var l := _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	ui.add_child(l)
	l.text = "%s +%d" % [label, pts]
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	var sp: Vector2 = Vector2(640, 260)
	if cam.is_position_in_frustum(world_pos):
		sp = cam.unproject_position(world_pos)
	sp.y = clampf(sp.y, 160.0, 560.0)
	l.position = sp - Vector2(150, 20) + Vector2(0, float(_pop_slot - 3) * 34.0)
	l.size = Vector2(300, 40)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.chain().tween_callback(func():
		_popups = maxi(_popups - 1, 0)
		l.queue_free())

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
	lbl_stats.text = "Best %d   Credits %d   Try #%d   Targets %d/%d" % [best, bank, attempt, hit, town.targets.size()]

# ---------------------------------------------------------------- loop
func _physics_process(dt: float) -> void:
	if state != State.FLIGHT:
		return
	flight_t += dt
	scoring.clock = flight_t
	if not classic:
		_skid(dt)
		_pivot_tick(dt)
	var c: Vector3 = ragdoll.centre()
	scoring.set_distance(c.x)
	flip_angle += ragdoll.torso.angular_velocity.length() * dt
	var want: int = mini(int(flip_angle / TAU), 8)
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
	var now: float = flight_t
	var spd: float = ragdoll.max_speed() if classic else ragdoll.motion_speed()
	if not classic and _agl(ragdoll.torso.global_position) > 0.9:
		_air_since_skip = true
	var oob: bool = c.y < -20.0 or c.x > Town.WORLD_X_MAX + 20.0 or absf(c.z) > Town.WORLD_Z + 20.0
	if classic:
		# end of flight: settled, or nothing interesting happening any more, or out of time/bounds
		settle_timer = settle_timer + dt if (spd < 1.0 and now > 0.8) else 0.0
		var quiet: bool = now > 2.0 and (now - maxf(_last_event, t_launch)) > 2.5 and _agl(c) < 1.6 and spd < 4.0
		if settle_timer > 0.6 or quiet or now > 13.0 or oob:
			_finish()
		return
	# pivot: the throw ends the moment the chaos is over (no 10 s of dead rolling)
	calm_t = calm_t + dt if Rules.is_calm(spd, energy) else 0.0
	btn_skip.visible = now > SKIP_AFTER_S
	var over: bool = Rules.run_finished({"elapsed": now, "landed": _hit_any, "max_speed": spd, "calm_t": calm_t,
		"event_age": now - maxf(_last_event, t_launch), "energy": energy, "max_t": MAX_FLIGHT_S})
	if over or oob or (_oob_at >= 0.0 and flight_t >= _oob_at):
		_finish()

## Per-frame pivot systems: airborne spin control, burning spread, blood trails, combo display.
func _pivot_tick(dt: float) -> void:
	var ai: float = air_input
	var k: float = Input.get_axis("ui_left", "ui_right")
	if k != 0.0:
		ai = k
	if absf(ai) > 0.05 and _agl(ragdoll.torso.global_position) > 1.3:
		var axis: Vector3 = Vector3.UP.cross(_trav_dir).normalized()
		ragdoll.torso.angular_velocity += axis * ai * 14.0 * float(fxp.get("spin_mult", 1.0)) * dt
		ragdoll.clamp_omega(ragdoll.torso)
	if energy < 0.2 and not _wound_down:
		_wound_down = true                      # energy spent: bleed speed fast so the throw ends promptly
		for bd in ragdoll.bodies:
			bd.linear_damp = 1.4
			bd.angular_damp = 1.0
	_burn_acc += dt
	if _burn_acc >= 0.2:
		_burn_acc = 0.0
		for b in ragdoll.burning_bodies():
			town.ignite_near(b.global_position, 1.8, 0.5)
	_trail_acc += dt
	if _trail_acc >= 0.1:
		_trail_acc = 0.0
		for tr in _trails:
			tr[1] = float(tr[1]) - 0.1
			if is_instance_valid(tr[0]) and float(tr[1]) > 0.0:
				fx.blood((tr[0] as Node3D).global_position, Vector3.UP, 0.25)
		for ti in range(_trails.size() - 1, -1, -1):
			if float(_trails[ti][1]) <= 0.0:
				_trails.remove_at(ti)
	var cm: float = Rules.combo_mult(scoring.combo) if (scoring.clock - scoring.combo_t) < COMBO_WINDOW else 1.0
	if scoring.combo >= 3 and cm > 1.0:
		lbl_combo.visible = true
		lbl_combo.text = "COMBO x%d   (x%.1f points)" % [scoring.combo, cm]
	else:
		lbl_combo.visible = false

## Arcade assist: keeps pushing along the ground velocity so the ragdoll skids through things instead of rolling to a stop.
func _skid(dt: float) -> void:
	if _agl(ragdoll.torso.global_position) >= 2.8:
		return
	var v: Vector3 = ragdoll.torso.linear_velocity
	var fwd: float = v.x * _skid_dir.x + v.z * _skid_dir.z
	# only while still travelling forward; taper out so it can never run away or push backwards
	if fwd < 1.5 or fwd >= SKID_MAX_SPEED:
		return
	var accel: float = (SKID_ACCEL + 1.2 * float(levels.get("bounce", 0))) * (1.0 - fwd / SKID_MAX_SPEED) * 0.5 * clampf(energy * 1.5 - 0.1, 0.0, 1.0)
	for bd in ragdoll.bodies:
		if not ragdoll.is_detached(bd):
			bd.apply_central_impulse(_skid_dir * accel * dt * bd.mass)

func _finish() -> void:
	if state == State.RESULT:
		return
	state = State.RESULT
	var c: Vector3 = ragdoll.centre()
	var ra: Dictionary = town.ring_award(c)
	if not ra.is_empty():
		scoring.award(str(ra["key"]), str(ra["name"]), int(ra["pts"]), "Targets", c)
	var total: int = scoring.total()
	last_credit = Rules.bank_credit(scoring.lines) if not classic else total
	bank += last_credit
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
	if not classic:
		lines.append("+%d CREDITS banked for upgrades (score and credits are separate)" % last_credit)
		lines.append("Skips %d   Ricochets %d   Limbs lost %d   Fires %d   Best combo x%d" % [skips, ricochets, limbs_lost, fires_started, scoring.best_combo])
	lbl_breakdown.text = "\n".join(lines)
	btn_skip.visible = false
	lbl_combo.visible = false
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
		cam_event = maxf(cam_event - dt * 0.7, 0.0)
		var dist: float = lerpf(9.0 + clampf(speed * 0.22, 0.0, 6.0), 17.0, cam_blend) + cam_event * 6.0
		var height: float = lerpf(3.4, 7.5, cam_blend) + clampf(c.y * 0.25, 0.0, 6.0) + cam_event * 2.5
		cam.fov = lerpf(cam.fov, 56.0 + clampf(speed - 14.0, 0.0, 40.0) * 0.3 + cam_event * 7.0, 1.0 - exp(-4.0 * dt))
		var side := Vector3(-_trav_dir.z, 0.0, _trav_dir.x) * (4.5 if not view_right else -4.5)
		var pos: Vector3 = c - _trav_dir * dist + side + Vector3(0, height, 0)
		pos.x = clampf(pos.x, Town.WORLD_X_MIN + 2.0, Town.WORLD_X_MAX - 2.0)
		pos.z = clampf(pos.z, -Town.WORLD_Z + 2.0, Town.WORLD_Z - 2.0)
		pos.y = maxf(pos.y, (town.ground_y(pos.x, pos.z) if is_instance_valid(town) else 0.0) + 2.2)
		var look: Vector3 = c + _trav_dir * 3.0 + Vector3(0, 0.5, 0)
		_cam_look = _cam_look.lerp(look, 1.0 - exp(-7.0 * dt))
		cam.global_position = cam.global_position.lerp(pos, 1.0 - exp(-(4.0 if classic else 6.0) * dt))
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
	if skip_select:
		return                      # tests: hermetic (no saved choices/upgrades)
	var cf := ConfigFile.new()
	if cf.load("user://launch.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))
		view_right = bool(cf.get_value("view", "pull_right", false))
		bank = int(cf.get_value("progress", "bank", 0))
		for key in Rules.UPGRADE_ORDER:
			levels[key] = clampi(int(cf.get_value("progress", "up_" + key, 0)), 0, int((Rules.UPGRADES[key] as Dictionary)["max"]))
		var saved_schema: int = int(cf.get_value("progress", "schema", 0))
		if saved_schema == 2:
			var mig: Dictionary = Rules.migrate_levels(levels)
			levels = mig["levels"]
			migration_refund = int(mig["refund"])
			bank += migration_refund
			_save_progress()
		elif saved_schema < 2:
			# v12 and earlier banked score 1:1 and had a +10,000 test button: that progress is not real progression.
			bank = 0
			levels = Rules.empty_levels()
			economy_reset_note = true
			_save_progress()
		char_idx = int(cf.get_value("choice", "char", 0))
		env_idx = Rules.env_index(str(cf.get_value("choice", "env_id", "hill_steep")))
		gore = bool(cf.get_value("settings", "gore", true))

func _save_progress() -> void:
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("progress", "bank", bank)
	cf.set_value("progress", "schema", ECONOMY_SCHEMA)
	for key in Rules.UPGRADE_ORDER:
		cf.set_value("progress", "up_" + key, get_level(key))
	cf.save("user://launch.cfg")

func _save_choice() -> void:
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("choice", "char", char_idx)
	cf.set_value("choice", "env_id", str(Rules.ENVIRONMENTS[env_idx]["id"]))
	cf.save("user://launch.cfg")

func set_gore(on: bool) -> void:
	gore = on
	if fx:
		fx.gore = on
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("settings", "gore", on)
	cf.save("user://launch.cfg")

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.load("user://launch.cfg")
	cf.set_value("score", "best", best)
	cf.save("user://launch.cfg")
