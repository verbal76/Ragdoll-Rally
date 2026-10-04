extends SceneTree
## Deterministic OTA + About + applying-update state-machine tests (no network).
##   godot --headless --path launch -s tests/verify_ota.gd
var fails: int = 0
var _n: int = 0
const CH := "poc"
const COMPAT := "r1-testcompat"

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	await _run()
	print("---- OTA %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _info() -> Dictionary:
	var i := BuildInfo.defaults()
	i["channel"] = CH
	i["runtime_compat"] = COMPAT
	i["ota_enabled"] = true
	i["ota_manifest_url"] = "https://example.invalid/manifest.json"
	i["version_code"] = 5
	i["target_sdk"] = "34"
	return i

func _wipe(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))

func _make_pck(path: String, marker_name: String, content: String) -> PackedByteArray:
	var src := "user://src_%s.txt" % marker_name
	var fa := FileAccess.open(src, FileAccess.WRITE)
	fa.store_string(content)
	fa.close()
	var pk := PCKPacker.new()
	pk.pck_start(path)
	pk.add_file("res://" + marker_name + ".txt", src)
	pk.flush()
	return FileAccess.get_file_as_bytes(path)

func _manifest(id: String, seq: int, body: PackedByteArray, over: Dictionary = {}) -> Dictionary:
	var m := {"id": id, "name": "Test OTA %d" % seq, "sequence": seq, "channel": CH, "runtime_compat": COMPAT,
		"url": "https://example.invalid/%s.pck" % id, "sha256": _sha(body), "size": body.size(),
		"source_sha": "abc1234", "published_at": "2026-10-03T00:00:00Z"}
	for k in over.keys():
		m[k] = over[k]
	return m

func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()

## fixture server: map url -> {ok, code, body}; missing url => offline failure
func _client(routes: Dictionary) -> OtaClient:
	_n += 1
	var root := "user://ota_t%d" % _n
	_wipe(root)
	_wipe(root.path_join("x"))
	var c := OtaClient.new()
	var fetch := func(url: String) -> Dictionary:
		if routes.has(url):
			return routes[url]
		return {"ok": false, "code": 0, "body": PackedByteArray()}
	root_add(c)
	c.setup(_info(), root, fetch)
	return c

func root_add(n: Node) -> void:
	root.add_child(n)

func _json(m: Variant) -> Dictionary:
	return {"ok": true, "code": 200, "body": JSON.stringify(m).to_utf8_buffer()}

func _run() -> void:
	var MURL := "https://example.invalid/manifest.json"
	var body := _make_pck("user://p1.pck", "probe_a", "hello-a")
	# --- offline / server / manifest availability
	var c := _client({})
	var r: Dictionary = await c.check_for_update()
	check(r.status == "offline" and c.d.pending.is_empty(), "offline: app unaffected, nothing staged")
	c = _client({MURL: {"ok": true, "code": 503, "body": PackedByteArray()}})
	r = await c.check_for_update()
	check(r.status == "server_error", "server unavailable (503)")
	c = _client({MURL: {"ok": true, "code": 404, "body": PackedByteArray()}})
	r = await c.check_for_update()
	check(r.status == "manifest_unavailable", "manifest unavailable (404)")
	c = _client({MURL: {"ok": true, "code": 200, "body": "{not json".to_utf8_buffer()}})
	r = await c.check_for_update()
	check(r.status == "rejected", "malformed manifest rejected")
	# --- no update / duplicate / old
	var m1 := _manifest("poc-1", 1, body)
	c = _client({MURL: _json(m1), m1.url: {"ok": true, "code": 200, "body": body}})
	r = await c.check_for_update()
	check(r.status == "staged" and c.d.pending.status == "staged", "compatible update downloaded, verified and staged")
	check(c.state != "applying", "checking/downloading never enters the applying state")
	r = await c.check_for_update()
	check(r.status == "no_update", "duplicate OTA ignored while already staged")
	# --- incompatible / wrong channel / native-required
	var mbad := _manifest("poc-9", 9, body, {"runtime_compat": "r1-other"})
	c = _client({MURL: _json(mbad)})
	r = await c.check_for_update()
	check(r.status == "rejected" and "native" in r.reason, "native-required change presented as OTA is rejected")
	c = _client({MURL: _json(_manifest("poc-9", 9, body, {"channel": "stable"}))})
	r = await c.check_for_update()
	check(r.status == "rejected" and r.reason == "wrong channel", "wrong channel rejected")
	c = _client({MURL: _json(_manifest("poc-9", 9, body, {"min_version_code": 99}))})
	r = await c.check_for_update()
	check(r.status == "rejected", "requires newer native build rejected")
	c = _client({MURL: _json(_manifest("poc-9", 9, body, {"url": "http://evil.invalid/x.pck"}))})
	r = await c.check_for_update()
	check(r.status == "rejected", "non-https payload url rejected")
	# --- corrupt / hash / interrupted / partial
	var m2 := _manifest("poc-2", 2, body)
	var bad := body.duplicate()
	bad[bad.size() - 1] = (bad[bad.size() - 1] + 1) % 256
	c = _client({MURL: _json(m2), m2.url: {"ok": true, "code": 200, "body": bad}})
	r = await c.check_for_update()
	check(r.status == "download_failed" and "sha256" in r.reason and c.d.pending.is_empty() and not FileAccess.file_exists(c._path("download.part")), "corrupt download: hash mismatch, nothing staged, no leftover")
	c = _client({MURL: _json(m2)})
	r = await c.check_for_update()
	check(r.status == "download_failed" and c.d.pending.is_empty(), "interrupted download leaves no staged update")
	c = _client({MURL: _json(m2), m2.url: {"ok": true, "code": 200, "body": body.slice(0, body.size() / 2)}})
	r = await c.check_for_update()
	check(r.status == "download_failed" and c.d.pending.is_empty(), "partial payload never becomes a valid update")
	# --- applying-update modal state machine + successful activation
	var routes := {MURL: _json(m1), m1.url: {"ok": true, "code": 200, "body": body}}
	c = _client(routes)
	await c.check_for_update()
	var ov := UpdateOverlay.new()
	root.add_child(ov)
	await process_frame
	var vis_log: Array = []
	c.applying_started.connect(func(): ov.show_overlay(); vis_log.append(ov.visible))
	c.applying_finished.connect(func(ok: bool): ov.hide_overlay(); vis_log.append(ov.visible))
	check(ov.message() == "Please wait, applying update" and ov._label.text == "Please wait, applying update", "modal text is exactly 'Please wait, applying update'")
	check(not ov.visible, "modal hidden during check/stage")
	# new process: reload state from disk, as at next cold launch
	var c2 := OtaClient.new()
	root.add_child(c2)
	var fetch2 := func(_u): return {"ok": false, "code": 0, "body": PackedByteArray()}
	c2.setup(_info(), c._path("").trim_suffix("/"), fetch2)
	c2.applying_started.connect(func(): ov.show_overlay(); vis_log.append(ov.visible))
	c2.applying_finished.connect(func(ok: bool): ov.hide_overlay(); vis_log.append(ov.visible))
	check(c2.boot_prepare() == "apply", "boot sees verified staged update -> apply")
	check(ov.visible == false, "modal not shown before activation begins")
	var ok: bool = c2.apply_staged()
	check(ok and vis_log == [true, false], "modal shown exactly during activation, gone after")
	check(FileAccess.file_exists("res://probe_a.txt") and FileAccess.get_file_as_string("res://probe_a.txt") == "hello-a", "activated payload is live (resource overridden)")
	check(c2.apply_staged() == false, "duplicate activation cannot occur")
	check(c2.d.pending.status == "activating" and c2.running.id == "poc-1", "running OTA identity exposed (unconfirmed)")
	var txt := SettingsMenu.diagnostics_text(c2)
	check("OTA 'Test OTA 1'" in txt and "poc-1" in txt and "abc1234" in txt and COMPAT in txt, "About/diagnostics reflect the running OTA")
	c2.confirm_startup_success()
	check(c2.d.current.id == "poc-1" and c2.d.pending.is_empty() and c2.update_status() == "CURRENT", "confirmed -> promoted to known-good")
	# repeat startup: known-good mounted, nothing to apply
	var c3 := OtaClient.new()
	root.add_child(c3)
	c3.setup(_info(), c2.root_dir, fetch2)
	check(c3.boot_prepare() == "none" and c3.running.id == "poc-1", "repeat startup mounts known-good, no re-apply")
	# old OTA cannot replace a newer one
	var routes_old := {MURL: _json(_manifest("poc-0", 0, body))}
	c3.fetcher = func(u): return routes_old.get(u, {"ok": false, "code": 0, "body": PackedByteArray()})
	r = await c3.check_for_update()
	check(r.status == "no_update", "older/equal OTA does not replace newer")
	# --- failed activation (garbage pack with valid hash) -> rollback, modal gone
	var garbage := "this is not a pck".to_utf8_buffer()
	var mg := _manifest("poc-3", 3, garbage)
	c = _client({MURL: _json(mg), mg.url: {"ok": true, "code": 200, "body": garbage}})
	await c.check_for_update()
	var c4 := OtaClient.new()
	root.add_child(c4)
	c4.setup(_info(), c.root_dir, fetch2)
	var log4: Array = []
	c4.applying_started.connect(func(): log4.append("start"))
	c4.applying_finished.connect(func(k: bool): log4.append("end:%s" % k))
	check(c4.boot_prepare() == "apply", "garbage staged (hash valid) reaches activation")
	ok = c4.apply_staged()
	check(not ok and log4 == ["start", "end:false"] and c4.state == "rolled_back", "failed activation: finishes (no permanent modal) and rolls back")
	check(c4.d.pending.is_empty() and (c4.d.failed_ids as Array).has("poc-3") and c4.update_status() == "FAILED / ROLLED BACK", "rollback recorded, failed OTA blacklisted")
	# --- crash after activation (never confirmed) -> next boot rolls back to known-good
	var body2 := _make_pck("user://p2.pck", "probe_b", "hello-b")
	var m5 := _manifest("poc-5", 5, body2)
	c = _client({MURL: _json(m5), m5.url: {"ok": true, "code": 200, "body": body2}})
	await c.check_for_update()
	var c5 := OtaClient.new()
	root.add_child(c5)
	c5.setup(_info(), c.root_dir, fetch2)
	c5.boot_prepare()
	c5.apply_staged()          # ...then the app "crashes" before confirm_startup_success()
	var c6 := OtaClient.new()
	root.add_child(c6)
	c6.setup(_info(), c.root_dir, fetch2)
	check(c6.boot_prepare() == "none" and c6.state == "current" and c6.d.pending.is_empty() and (c6.d.failed_ids as Array).has("poc-5"), "unconfirmed activation is rolled back at next launch")
	# --- disabled / dev builds never touch the network
	var di := _info()
	di["ota_enabled"] = false
	var c7 := OtaClient.new()
	root.add_child(c7)
	c7.setup(di, "user://ota_t_disabled", fetch2)
	r = await c7.check_for_update()
	check(r.status == "disabled" and c7.update_status() == "DISABLED", "OTA disabled build performs no check")
	# --- About content
	var t2 := SettingsMenu.diagnostics_text(c7)
	for needle in ["APPLICATION", "DEVICE", "INSTALL", "Package: com.hotatticgames.ragdollrally.launch", "Version code (native build)", "OTA", "Channel", "GOOGLE PLAY / ANDROID", "Play API compliant: NO", "Captured:",
			"Product: Ragdoll Rally Launch", "  Version: ", "Android versionName:", "Source commit:"]:
		check(needle in t2, "diagnostics contains '%s'" % needle)
	# the public version is shown on its own line in APPLICATION (before the technical INSTALL block)
	check(t2.find("  Version: ") > t2.find("APPLICATION") and t2.find("  Version: ") < t2.find("INSTALL"), "public product version is shown at the top, ahead of technical metadata")
	check(not ("password" in t2.to_lower() or "token" in t2.to_lower() or "keystore" in t2.to_lower()), "diagnostics contain no secrets")
	check(BuildInfo.play_compliance({"target_sdk": "36", "play_required_target_api": 36}) == "YES" and BuildInfo.play_compliance({"target_sdk": "?", "play_required_target_api": 36}) == "UNVERIFIED", "play compliance logic")
