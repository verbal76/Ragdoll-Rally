class_name BuildInfo
extends RefCounted
## NATIVE-BOUNDARY FILE (see ota/boundary.txt). Reads the CI-generated
## res://build_info.json baked into the APK. Local/dev runs fall back to "dev".

const PATH := "res://build_info.json"

static func defaults() -> Dictionary:
	return {
		"app_name": "RR Launch",
		"package_id": "com.hotatticgames.ragdollrally.launch",
		"version_name": "dev",
		"version_code": 0,
		"source_sha": "dev",
		"run_number": 0,
		"build_type": "dev",
		"channel": "dev",
		"min_sdk": "unknown",
		"target_sdk": "unknown",
		"compile_sdk": "unknown",
		"generation": "dev",
		"signing": "none (dev run)",
		"runtime_compat": "dev",
		"play_required_target_api": 36,
		"play_required_verified": "2026-10-03",
		"ota_enabled": false,
		"ota_manifest_url": "",
		"built_at": "",
	}

static func load_info() -> Dictionary:
	var out: Dictionary = defaults()
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			for k in (parsed as Dictionary).keys():
				out[k] = parsed[k]
	return out

## "YES" / "NO" / "UNVERIFIED"
static func play_compliance(info: Dictionary) -> String:
	var t: String = str(info.get("target_sdk", "unknown"))
	if not t.is_valid_int():
		return "UNVERIFIED"
	return "YES" if int(t) >= int(info.get("play_required_target_api", 36)) else "NO"

static func device_lines() -> Array[String]:
	var out: Array[String] = []
	out.append("Platform: %s" % OS.get_name())
	var ver: String = OS.get_version()
	if OS.has_method("get_version_alias"):
		ver = "%s / %s" % [OS.call("get_version_alias"), OS.get_version()]
	out.append("OS version: %s" % ver)
	out.append("Model: %s" % OS.get_model_name())
	out.append("Locale: %s" % OS.get_locale())
	out.append("Engine: Godot %s" % Engine.get_version_info().get("string", "?"))
	out.append("Renderer: %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")))
	return out
