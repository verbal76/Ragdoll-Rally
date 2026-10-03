extends Control
## NATIVE-BOUNDARY FILE. Startup sequence:
##   black -> Hot Attic Games studio splash (~1.5 s, skipped if the canonical
##   asset is absent) -> [apply staged OTA behind "Please wait, applying update"]
##   -> existing game (res://scenes/main.tscn) -> background OTA discovery.
## Never blocks on the network: discovery starts only after the game scene loads.

const LOGO := "res://branding/Hot_Attic_Games_Master_Logo.png"
const SPLASH_SECONDS := 1.5
const GAME_SCENE := "res://scenes/main.tscn"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var ota: OtaClient = get_node_or_null("/root/Ota") as OtaClient
	var action := "none"
	if ota:
		action = ota.boot_prepare()          # local-only: mounts known-good payload
		print("[boot] ota boot_prepare=%s running=%s" % [action, str(ota.running.get("id", "embedded"))])
	if ResourceLoader.exists(LOGO):
		var tex := load(LOGO) as Texture2D
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # contain: no crop, no distortion
		add_child(tr)
		await get_tree().create_timer(SPLASH_SECONDS).timeout
	else:
		push_warning("CANONICAL HOT ATTIC GAMES ASSET MISSING: %s (studio splash skipped)" % LOGO)
	if action == "apply" and ota:
		var overlay := UpdateOverlay.new()
		add_child(overlay)
		await get_tree().process_frame
		overlay.show_overlay()
		await get_tree().process_frame
		await get_tree().process_frame     # let the modal render before the (blocking) activation
		print("[boot] applying staged update ok=%s" % ota.apply_staged())
		overlay.hide_overlay()
	get_tree().change_scene_to_file(GAME_SCENE)
	if ota:
		ota.start_background_check.call_deferred()
