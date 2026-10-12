extends Control
## NATIVE-BOUNDARY FILE. Cold-launch sequence (Hot Attic Games studio requirement):
##   native splash (same dark colour, no image)
##   -> HOT ATTIC GAMES studio card (canonical artwork, fade in / hold / fade out, ~2.4 s)
##   -> [apply staged OTA behind "Please wait, applying update"]
##   -> the game's own opening (the character/city selector) -> background OTA discovery.
## The studio card is cold-launch only: this scene is the project's main scene, so resuming from the background
## never re-enters it. Useful startup work (OTA known-good mount, loading the game scene on a thread) happens
## BEHIND the card, so it masks work instead of adding dead time. A failure can never strand the user here.
## Never blocks on the network: discovery starts only after the game scene loads.

signal stage(name: String)

## THE canonical studio artwork. Do not point this at any other file (see CLAUDE.md).
const LOGO := "res://branding/Hot_Attic_Games_Master_Logo_ALPHA_FINAL.png"
const BG_COLOR := Color(0.043, 0.035, 0.035, 1.0)     # also project.godot boot_splash/bg_color (no colour flash)
const FADE_IN := 0.45
const HOLD := 1.5
const FADE_OUT := 0.45                                 # total ~2.4 s
const MAX_WAIT := 6.0                                  # longest we wait for the threaded load before loading directly
const PAD := 0.05                                      # breathing room around the art, fraction of the short side
const GAME_SCENE := "res://scenes/main.tscn"

var logo_path: String = LOGO                           # (tests may override)
var game_scene: String = GAME_SCENE
var hold_seconds: float = HOLD
var force_sync_load: bool = false                      # tests: do not use the threaded preload
var logo_node: TextureRect
var stages: Array[String] = []
var _bg: ColorRect

## The largest rectangle with the texture's aspect ratio that fits inside `avail` (never crops, never stretches).
static func fit_rect(avail: Vector2, tex: Vector2) -> Rect2:
	if tex.x <= 0.0 or tex.y <= 0.0 or avail.x <= 0.0 or avail.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var s: float = minf(avail.x / tex.x, avail.y / tex.y)
	var sz: Vector2 = tex * s
	return Rect2((avail - sz) * 0.5, sz)

func _mark(n: String) -> void:
	stages.append(n)
	print("[boot] stage=%s t=%dms" % [n, Time.get_ticks_msec()])
	stage.emit(n)

func _ready() -> void:
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_mark("boot_started")
	var ota: OtaClient = get_node_or_null("/root/Ota") as OtaClient
	var action := "none"
	if ota:
		action = ota.boot_prepare()          # local-only: mounts known-good payload
		print("[boot] ota boot_prepare=%s running=%s" % [action, str(ota.running.get("id", "embedded"))])
	# Load the game scene on a thread while the studio card is on screen. Not when an OTA is about to be applied:
	# the payload replaces game scripts/scenes, so the scene must be loaded AFTER that.
	var preloading := false
	if action != "apply" and not force_sync_load:
		preloading = ResourceLoader.load_threaded_request(game_scene) == OK
	var tex: Texture2D = null
	if ResourceLoader.exists(logo_path):
		tex = load(logo_path) as Texture2D
	if tex != null:
		logo_node = TextureRect.new()
		logo_node.texture = tex
		logo_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED     # contain: no crop, no distortion
		logo_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		logo_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo_node.modulate.a = 0.0
		add_child(logo_node)
		get_viewport().size_changed.connect(_layout)
		_layout()
		_mark("splash_visible")
		var tw := create_tween()
		tw.tween_property(logo_node, "modulate:a", 1.0, FADE_IN)
		tw.tween_interval(hold_seconds)
		tw.tween_property(logo_node, "modulate:a", 0.0, FADE_OUT)
		await tw.finished
		_mark("splash_done")
	else:
		push_warning("studio splash artwork could not be loaded (%s); continuing to the game" % logo_path)
		_mark("splash_skipped")
	if action == "apply" and ota:
		var overlay := UpdateOverlay.new()
		add_child(overlay)
		await get_tree().process_frame
		overlay.show_overlay()
		await get_tree().process_frame
		await get_tree().process_frame     # let the modal render before the (blocking) activation
		print("[boot] applying staged update ok=%s" % ota.apply_staged())
		overlay.hide_overlay()
	await _enter_game(preloading)
	if ota and is_inside_tree():
		ota.start_background_check.call_deferred()

## Keep the whole card inside the safe area (cutouts, rounded corners, nav bars) with some padding.
func _layout() -> void:
	if logo_node == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var m := Vector4.ZERO
	if win.x > 0.0 and win.y > 0.0:
		var sa: Rect2i = DisplayServer.get_display_safe_area()
		var scr: Vector2i = DisplayServer.screen_get_size()
		var spos: Vector2i = DisplayServer.screen_get_position()
		if sa.size.x > 0 and scr.x > 0:
			var k := Vector2(vp.x / win.x, vp.y / win.y)
			m = Vector4(maxf(float(sa.position.x - spos.x), 0.0) * k.x, maxf(float(sa.position.y - spos.y), 0.0) * k.y,
				maxf(float(scr.x - (sa.position.x - spos.x) - sa.size.x), 0.0) * k.x, maxf(float(scr.y - (sa.position.y - spos.y) - sa.size.y), 0.0) * k.y)
	var pad: float = minf(vp.x, vp.y) * PAD
	logo_node.position = Vector2(m.x + pad, m.y + pad)
	logo_node.size = Vector2(maxf(vp.x - m.x - m.z - 2.0 * pad, 1.0), maxf(vp.y - m.y - m.w - 2.0 * pad, 1.0))

func _enter_game(preloaded: bool) -> void:
	var packed: PackedScene = null
	if preloaded:
		var st: int = ResourceLoader.load_threaded_get_status(game_scene)
		var waited := 0.0
		while st == ResourceLoader.THREAD_LOAD_IN_PROGRESS and waited < MAX_WAIT:
			await get_tree().process_frame
			waited += get_process_delta_time()
			st = ResourceLoader.load_threaded_get_status(game_scene)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			packed = ResourceLoader.load_threaded_get(game_scene) as PackedScene
	_mark("game_starting")
	var err: int = OK
	if packed != null:
		err = get_tree().change_scene_to_packed(packed)
	else:
		err = get_tree().change_scene_to_file(game_scene)
	if err != OK:
		# last resort: never leave a blank screen; tell the user what happened
		_mark("game_failed")
		push_error("could not start the game scene (%s): error %d" % [game_scene, err])
		var l := Label.new()
		l.text = "Could not start the game.\nPlease close the app and open it again."
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.add_theme_font_size_override("font_size", 36)
		add_child(l)
		if logo_node:
			logo_node.modulate.a = 1.0
