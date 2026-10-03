class_name OtaClient
extends Node
## NATIVE-BOUNDARY FILE (see ota/boundary.txt). Self-discovering OTA client for
## Godot resource packs (PCK). Flow:
##   boot_prepare() -> [apply_staged()] -> game runs -> confirm_startup_success()
##   check_for_update() (background): manifest -> compat/channel/sequence checks
##   -> download -> size + SHA-256 verify -> stage (activates at next cold launch).
## A pack is promoted to "known good" only after the game starts successfully;
## an unconfirmed activation is rolled back at the next launch.

signal state_changed(new_state: String)
signal applying_started
signal applying_finished(ok: bool)

const MAX_PACK_BYTES := 64 * 1024 * 1024
const RESUME_COOLDOWN_S := 1800
const HTTP_TIMEOUT_S := 12.0

var root_dir: String = "user://ota"
var info: Dictionary = {}
var fetcher: Callable = Callable()          # (url) -> {ok, code, body}; awaitable
var mount_func: Callable = Callable()       # (path) -> bool; overridable for tests
var allow_insecure_localhost: bool = false  # tests only
var state: String = "idle"
var last_status: String = "never checked"
var last_check_unix: int = 0
var running: Dictionary = {}                # active OTA meta; empty = embedded baseline
var d: Dictionary = {}                      # persisted state
var _applying: bool = false
var _checking: bool = false

func _ready() -> void:
	if info.is_empty():
		setup(BuildInfo.load_info(), "user://ota")
		allow_insecure_localhost = str(info.get("build_type", "")) == "dev-e2e"   # local end-to-end tests only

func setup(p_info: Dictionary, p_root: String, p_fetcher: Callable = Callable()) -> void:
	info = p_info
	root_dir = p_root
	fetcher = p_fetcher if p_fetcher.is_valid() else Callable(self, "_http_fetch")
	DirAccess.make_dir_recursive_absolute(root_dir)
	_load_state()

# ------------------------------------------------------------------ state file
func _default_state() -> Dictionary:
	return {"current": {}, "previous": {}, "pending": {}, "failed_ids": [], "last_error": "", "last_check": 0, "last_status": "never checked"}

func _path(n: String) -> String:
	return root_dir.path_join(n)

func _load_state() -> void:
	d = _default_state()
	var f := _path("state.json")
	if FileAccess.file_exists(f):
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if p is Dictionary:
			for k in (p as Dictionary).keys():
				d[k] = p[k]
	last_check_unix = int(d.get("last_check", 0))
	last_status = str(d.get("last_status", "never checked"))

func _save_state() -> void:
	d["last_check"] = last_check_unix
	d["last_status"] = last_status
	var tmp := _path("state.json.tmp")
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return
	fa.store_string(JSON.stringify(d))
	fa.close()
	DirAccess.open(root_dir).rename("state.json.tmp", "state.json")

func _set_state(s: String) -> void:
	state = s
	state_changed.emit(s)

func _size(path: String) -> int:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return -1
	var n: int = fa.get_length()
	fa.close()
	return n

func _mount(path: String) -> bool:
	if mount_func.is_valid():
		return bool(mount_func.call(path))
	return ProjectSettings.load_resource_pack(path, true)

func _remove_file(name: String) -> void:
	if name != "" and FileAccess.file_exists(_path(name)):
		DirAccess.remove_absolute(_path(name))

# ------------------------------------------------------------------ boot phase
## Returns "apply" when a verified staged update is waiting for activation.
func boot_prepare() -> String:
	var pending_ready := false
	var p: Dictionary = d.get("pending", {})
	if not p.is_empty():
		if str(p.get("status", "")) == "activating":
			_rollback_pending("previous activation was never confirmed (crash/kill); rolled back")
		elif FileAccess.file_exists(_path(str(p.get("file", "")))):
			pending_ready = true
		else:
			d["pending"] = {}
	# mount known-good (current, then previous as fallback)
	for slot in ["current", "previous"]:
		var c: Dictionary = d.get(slot, {})
		if c.is_empty():
			continue
		var f := _path(str(c.get("file", "")))
		if FileAccess.file_exists(f) and _size(f) == int(c.get("size", -2)) and _mount(f):
			running = c.duplicate()
			break
		d["last_error"] = "known-good pack '%s' unusable; falling back" % slot
		d[slot] = {}
	_save_state()
	if pending_ready:
		_set_state("staged")
		return "apply"
	_set_state("current")
	return "none"

## Called by the boot scene AFTER it is showing the applying-update UI.
func apply_staged() -> bool:
	if _applying:
		return false
	var p: Dictionary = d.get("pending", {})
	if p.is_empty() or str(p.get("status", "")) != "staged":
		return false
	_applying = true
	_set_state("applying")
	applying_started.emit()
	var f := _path(str(p.get("file", "")))
	var ok: bool = FileAccess.file_exists(f) and _size(f) == int(p.get("size", -2)) and FileAccess.get_sha256(f) == str(p.get("sha256", ""))
	if not ok:
		_rollback_pending("staged pack failed verification at activation")
	else:
		p["status"] = "activating"
		d["pending"] = p
		_save_state()          # persisted BEFORE mounting: a crash now triggers rollback next launch
		if _mount(f):
			running = p.duplicate()
			last_status = "applied OTA '%s'; awaiting startup confirmation" % str(p.get("name", ""))
			_save_state()
		else:
			ok = false
			_rollback_pending("pack failed to mount")
	_applying = false
	applying_finished.emit(ok)
	return ok

## Called by the game once it has started successfully on the running payload.
func confirm_startup_success() -> void:
	var p: Dictionary = d.get("pending", {})
	if p.is_empty() or str(p.get("status", "")) != "activating" or str(running.get("id", "")) != str(p.get("id", "-")):
		return
	var old_prev: Dictionary = d.get("previous", {})
	if not old_prev.is_empty():
		_remove_file(str(old_prev.get("file", "")))
	d["previous"] = d.get("current", {})
	p["status"] = "current"
	d["current"] = p
	d["pending"] = {}
	last_status = "OTA '%s' confirmed" % str(p.get("name", ""))
	_save_state()
	_set_state("current")

func _rollback_pending(reason: String) -> void:
	var p: Dictionary = d.get("pending", {})
	if not p.is_empty():
		_remove_file(str(p.get("file", "")))
		var failed: Array = d.get("failed_ids", [])
		if not failed.has(p.get("id", "")):
			failed.append(p.get("id", ""))
		d["failed_ids"] = failed
	d["pending"] = {}
	d["last_error"] = reason
	last_status = "ROLLED BACK: " + reason
	_save_state()
	_set_state("rolled_back")

# ------------------------------------------------------------------ discovery
func start_background_check() -> void:
	if bool(info.get("ota_enabled", false)) and not _checking and not _applying:
		check_for_update()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and Time.get_unix_time_from_system() - last_check_unix > RESUME_COOLDOWN_S:
		start_background_check()

func _url_ok(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	return allow_insecure_localhost and (url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost"))

## Pure decision function. Returns {action: "none"|"download"|"reject", reason}.
func evaluate_manifest(m: Variant) -> Dictionary:
	if not (m is Dictionary):
		return {"action": "reject", "reason": "malformed manifest"}
	var mm: Dictionary = m
	for k in ["id", "name", "sequence", "channel", "runtime_compat", "url", "sha256", "size", "source_sha", "published_at"]:
		if not mm.has(k):
			return {"action": "reject", "reason": "manifest missing '%s'" % k}
	if not (mm["sequence"] is float or mm["sequence"] is int) or not (mm["size"] is float or mm["size"] is int):
		return {"action": "reject", "reason": "malformed manifest types"}
	if str(mm["channel"]) != str(info.get("channel", "")):
		return {"action": "reject", "reason": "wrong channel"}
	if str(mm["runtime_compat"]) != str(info.get("runtime_compat", "")):
		return {"action": "reject", "reason": "incompatible runtime (native build required)"}
	if mm.has("min_version_code") and int(mm["min_version_code"]) > int(info.get("version_code", 0)):
		return {"action": "reject", "reason": "requires newer native build"}
	if str(mm["sha256"]).length() != 64 or not str(mm["sha256"]).is_valid_hex_number(false):
		return {"action": "reject", "reason": "bad sha256"}
	var size: int = int(mm["size"])
	if size <= 0 or size > MAX_PACK_BYTES:
		return {"action": "reject", "reason": "bad size"}
	if not _url_ok(str(mm["url"])):
		return {"action": "reject", "reason": "payload url must be https"}
	var seq: int = int(mm["sequence"])
	if (d.get("failed_ids", []) as Array).has(mm["id"]):
		return {"action": "reject", "reason": "previously failed OTA"}
	var cur: Dictionary = d.get("current", {})
	var cur_seq: int = int(cur.get("sequence", 0))
	if not running.is_empty():
		cur_seq = maxi(cur_seq, int(running.get("sequence", 0)))
	if seq <= cur_seq:
		return {"action": "none", "reason": "already at or beyond this OTA"}
	var pend: Dictionary = d.get("pending", {})
	if not pend.is_empty() and int(pend.get("sequence", 0)) >= seq:
		return {"action": "none", "reason": "already staged"}
	return {"action": "download", "reason": "newer compatible OTA"}

func check_for_update() -> Dictionary:
	if _checking or _applying:
		return {"status": "busy"}
	_checking = true
	_set_state("checking")
	var res: Dictionary = await _check_impl()
	_checking = false
	last_check_unix = int(Time.get_unix_time_from_system())
	last_status = "%s%s" % [res.get("status", "?"), (": " + str(res["reason"])) if res.has("reason") else ""]
	_save_state()
	if str(res.get("status", "")) == "staged":
		_set_state("staged")
	else:
		_set_state("current" if running.is_empty() or d.get("pending", {}).is_empty() else state)
	return res

func _check_impl() -> Dictionary:
	var url: String = str(info.get("ota_manifest_url", ""))
	if not bool(info.get("ota_enabled", false)) or url == "":
		return {"status": "disabled"}
	if not _url_ok(url):
		return {"status": "rejected", "reason": "manifest url must be https"}
	var r: Dictionary = await fetcher.call(url)
	if not bool(r.get("ok", false)):
		return {"status": "offline", "reason": "network unavailable"}
	var code: int = int(r.get("code", 0))
	if code >= 500:
		return {"status": "server_error", "reason": "HTTP %d" % code}
	if code != 200:
		return {"status": "manifest_unavailable", "reason": "HTTP %d" % code}
	var m: Variant = JSON.parse_string((r["body"] as PackedByteArray).get_string_from_utf8())
	var ev: Dictionary = evaluate_manifest(m)
	if ev["action"] == "none":
		return {"status": "no_update", "reason": ev["reason"]}
	if ev["action"] == "reject":
		return {"status": "rejected", "reason": ev["reason"]}
	var mm: Dictionary = m
	_set_state("downloading")
	var r2: Dictionary = await fetcher.call(str(mm["url"]))
	if not bool(r2.get("ok", false)) or int(r2.get("code", 0)) != 200:
		return {"status": "download_failed", "reason": "interrupted or HTTP %d" % int(r2.get("code", 0))}
	var body: PackedByteArray = r2["body"]
	if body.size() != int(mm["size"]):
		return {"status": "download_failed", "reason": "partial or wrong-size payload"}
	var part := _path("download.part")
	var fa := FileAccess.open(part, FileAccess.WRITE)
	if fa == null:
		return {"status": "download_failed", "reason": "cannot write staging file"}
	fa.store_buffer(body)
	fa.close()
	if FileAccess.get_sha256(part) != str(mm["sha256"]).to_lower():
		DirAccess.remove_absolute(part)
		return {"status": "download_failed", "reason": "sha256 mismatch"}
	var final_name := "%s.pck" % str(mm["id"]).validate_filename()
	DirAccess.open(root_dir).rename("download.part", final_name)
	var old_pending: Dictionary = d.get("pending", {})
	if not old_pending.is_empty() and str(old_pending.get("file", "")) != final_name:
		_remove_file(str(old_pending.get("file", "")))
	d["pending"] = {"id": mm["id"], "name": mm["name"], "sequence": int(mm["sequence"]), "sha256": str(mm["sha256"]).to_lower(),
		"size": int(mm["size"]), "file": final_name, "source_sha": mm["source_sha"], "published_at": mm["published_at"],
		"channel": mm["channel"], "runtime_compat": mm["runtime_compat"], "status": "staged"}
	return {"status": "staged", "reason": "OTA '%s' staged; applies at next launch" % str(mm["name"])}

func _http_fetch(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = HTTP_TIMEOUT_S
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray()}
	var res: Array = await req.request_completed
	req.queue_free()
	var ok: bool = int(res[0]) == HTTPRequest.RESULT_SUCCESS
	return {"ok": ok, "code": int(res[1]) if ok else 0, "body": res[3]}

## CURRENT / CHECKING / DOWNLOADING / STAGED (applies next launch) / APPLYING / FAILED-ROLLED BACK / DISABLED
func update_status() -> String:
	if not bool(info.get("ota_enabled", false)):
		return "DISABLED"
	match state:
		"checking": return "CHECKING"
		"downloading": return "DOWNLOADING"
		"applying": return "APPLYING"
		"staged": return "STAGED (applies at next launch)"
		"rolled_back": return "FAILED / ROLLED BACK"
	if not (d.get("pending", {}) as Dictionary).is_empty():
		return "STAGED (applies at next launch)"
	return "CURRENT"
