extends Node
const SafeCfg := preload("res://scripts/safe_cfg.gd")
## Desktop graphics: detects the display and the GPU class (integrated / APU vs discrete), picks a preset for it the first time,
## and applies / saves the player's choices. Desktop only: phones keep the engine defaults.
## Use with:  const Graphics := preload("res://scripts/graphics.gd")

signal changed

const CFG_PATH := "user://graphics.cfg"
const PRESETS := {
	"low": {"scale": 0.67, "msaa": 0, "shadows": false, "vsync": true},
	"medium": {"scale": 0.85, "msaa": 0, "shadows": true, "vsync": true},
	"high": {"scale": 1.0, "msaa": 2, "shadows": true, "vsync": true},
	"ultra": {"scale": 1.0, "msaa": 4, "shadows": true, "vsync": true},
	# Steam Deck (RDNA2 APU, 1280x800): the playable default is 30+ fps at 800p; lighter ink pass, no MSAA, frame-rate adapts further if needed
	"deck": {"scale": 0.8, "msaa": 0, "shadows": false, "vsync": true, "ink": "lite", "fps": 60},
}
const FPS_CAPS := [0, 30, 40, 45, 60, 90, 120, 144]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MODES := ["fullscreen", "exclusive", "windowed"]

var s := {"preset": "auto", "mode": "fullscreen", "res": Vector2i(0, 0), "scale": 1.0, "msaa": 0, "shadows": true, "vsync": true, "fps": 60, "ink": "full"}
var first_run := false
var info := {}
var host: Node

func setup(h: Node) -> void:
	host = h
	info = detect()
	first_run = not FileAccess.file_exists(CFG_PATH)
	if first_run:
		s["preset"] = "auto"
		_take(recommend())
		if not bool(info.get("deck", false)):
			s["fps"] = _fps_for(int(info["hz"]))
		save()
	else:
		load_cfg()
	apply()

## Display + adapter facts. adapter: "integrated" (APU / iGPU), "discrete", "virtual", "cpu" or "unknown".
func detect() -> Dictionary:
	var kinds := ["unknown", "integrated", "discrete", "virtual", "cpu"]
	var t: int = RenderingServer.get_video_adapter_type()
	var scr: Vector2i = DisplayServer.screen_get_size()
	var hz: float = DisplayServer.screen_get_refresh_rate()
	return {"gpu": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter": kinds[clampi(t, 0, kinds.size() - 1)], "screen": scr, "hz": int(hz) if hz > 0.0 else 60, "deck": host != null and host.get("controls") != null and bool(host.controls.deck)}

## The preset that suits this machine. Integrated graphics get a lower render scale; a big screen on any GPU does too.
func recommend() -> String:
	if bool(info.get("deck", false)):
		return "deck"
	var px: int = (info["screen"] as Vector2i).x * (info["screen"] as Vector2i).y
	match str(info["adapter"]):
		"integrated", "cpu", "virtual":
			return "low" if px > 2300000 else "medium"
		"discrete":
			return "high" if px <= 8300000 else "medium"
	return "medium"

func _fps_for(hz: int) -> int:
	var best := 60
	for c in FPS_CAPS:
		if c != 0 and c <= hz:
			best = c
	return best

func _take(preset: String) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["medium"])
	for k in p.keys():
		s[k] = p[k]

func choose_preset(name: String) -> void:
	s["preset"] = name
	if name == "auto":
		_take(recommend())
	elif PRESETS.has(name):
		_take(name)
	apply()
	save()

func set_opt(key: String, value: Variant) -> void:
	s[key] = value
	s["preset"] = "custom"
	apply()
	save()

func resolution_options() -> Array:
	var out: Array = [Vector2i(0, 0)]                      # (0,0) = native / window as is
	var scr: Vector2i = info["screen"]
	if bool(info.get("deck", false)):
		return out                                              # the Deck always runs at its own screen size
	for r in RESOLUTIONS:
		if r.x <= scr.x and r.y <= scr.y:
			out.append(r)
	return out

func apply() -> void:
	if OS.has_feature("mobile") or host == null or not host.is_inside_tree():
		return
	var win: Window = host.get_window()
	match str(s["mode"]):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var r: Vector2i = s["res"]
			if r.x > 0:
				win.size = r
				win.position = DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - r) / 2
	var vp: Viewport = host.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(s["scale"]), 0.5, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(s["msaa"]) / 2, 0, 2)]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(s["vsync"]) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(s["fps"])
	if host.has_method("set_ink_quality"):
		host.set_ink_quality(str(s.get("ink", "full")))
	for l in host.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = bool(s["shadows"])
	changed.emit()

func save() -> void:
	var cf := ConfigFile.new()
	for k in s.keys():
		var v = s[k]
		cf.set_value("graphics", k, [v.x, v.y] if v is Vector2i else v)
	SafeCfg.save(cf, CFG_PATH)

func load_cfg() -> void:
	var cf := ConfigFile.new()
	if SafeCfg.load(cf, CFG_PATH) != OK:
		return
	for k in s.keys():
		if cf.has_section_key("graphics", k):
			var v = cf.get_value("graphics", k)
			s[k] = Vector2i(int(v[0]), int(v[1])) if (k == "res" and v is Array) else v

func describe() -> String:
	var scr: Vector2i = info["screen"]
	if bool(info.get("deck", false)):
		return "Steam Deck   screen %dx%d @ %d Hz   preset: DECK" % [scr.x, scr.y, int(info["hz"])]
	return "%s  (%s graphics)   screen %dx%d @ %d Hz   recommended: %s" % [str(info["gpu"]), str(info["adapter"]), scr.x, scr.y, int(info["hz"]), recommend().to_upper()]
