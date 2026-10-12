extends SceneTree
## OTA version-floor safety. Reproduces the v14-v18 downgrade (frozen legacy client + the real poc-g2 seq 3 manifest) and proves the new
## client rejects unsafe updates, revalidates stored packs, survives interrupted / failed / repeated activations and keeps save data.
##   godot --headless --path launch -s tests/verify_ota_safety.gd
const LEGACY := "res://tests/fixtures/ota_client_legacy_v14_v18.gd"
const LIVE_MANIFEST := "res://tests/fixtures/ota_manifest_poc-g2_seq3_faeb937.json"
const COMPAT := "r2-abbbcedcb90e"            # the runtime fingerprint shared by v14..v18 and the faeb937 pack
const CH := "poc-g2"
const MURL := "https://example.invalid/manifest.json"
var fails := 0
var _n := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	await _run()
	print("---- OTA SAFETY %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _info(version_code: int, epoch: int, compat: String = COMPAT) -> Dictionary:
	var i := BuildInfo.defaults()
	i["channel"] = CH
	i["runtime_compat"] = compat
	i["ota_enabled"] = true
	i["ota_manifest_url"] = MURL
	i["version_code"] = version_code
	i["source_epoch"] = epoch
	return i

func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()

func _make_pck(path: String, marker: String, content: String) -> PackedByteArray:
	var src := "user://src_%s.txt" % marker
	var fa := FileAccess.open(src, FileAccess.WRITE)
	fa.store_string(content)
	fa.close()
	var pk := PCKPacker.new()
	pk.pck_start(path)
	pk.add_file("res://" + marker + ".txt", src)
	pk.flush()
	return FileAccess.get_file_as_bytes(path)

func _wipe(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))

## The REAL manifest currently served on poc-g2 (fixture), pointed at a local test payload.
func _live(body: PackedByteArray) -> Dictionary:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LIVE_MANIFEST))
	m["sha256"] = _sha(body)
	m["size"] = body.size()
	return m

func _new_manifest(id: String, seq: int, epoch: int, body: PackedByteArray, over: Dictionary = {}) -> Dictionary:
	var m := {"id": id, "name": "OTA %s" % id, "sequence": seq, "channel": CH, "runtime_compat": COMPAT, "url": "https://example.invalid/%s.pck" % id,
		"sha256": _sha(body), "size": body.size(), "source_sha": "dcb9c4d7faec092e18f2ca08145923ad334342d0", "source_epoch": epoch, "published_at": "2026-10-12T00:00:00Z"}
	for k in over.keys():
		m[k] = over[k]
	return m

func _json(m: Variant) -> Dictionary:
	return {"ok": true, "code": 200, "body": JSON.stringify(m).to_utf8_buffer()}

func _fetcher(routes: Dictionary) -> Callable:
	return func(url: String) -> Dictionary:
		return routes.get(url, {"ok": false, "code": 0, "body": PackedByteArray()})

func _mk(node_script: Variant, info: Dictionary, root: String, routes: Dictionary) -> Node:
	var c: Node = node_script.new()
	root_add(c)
	c.setup(info, root, _fetcher(routes))
	return c

func root_add(n: Node) -> void:
	root.add_child(n)

func _dir() -> String:
	_n += 1
	var d := "user://ota_safe%d" % _n
	_wipe(d)
	return d

func _write_state(dir: String, st: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var fa := FileAccess.open(dir.path_join("state.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(st))
	fa.close()

func _stub_pack(dir: String, name: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var fa := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	fa.store_buffer(bytes)
	fa.close()

func _meta(id: String, seq: int, epoch: int, body: PackedByteArray, over: Dictionary = {}) -> Dictionary:
	var m := {"id": id, "name": id, "sequence": seq, "sha256": _sha(body), "size": body.size(), "file": "%s.pck" % id, "source_sha": "abc1234",
		"published_at": "x", "channel": CH, "runtime_compat": COMPAT, "status": "current", "source_epoch": epoch}
	for k in over.keys():
		m[k] = over[k]
	return m

func _run() -> void:
	var body := _make_pck("user://safe1.pck", "safe_probe_a", "payload-a")
	var legacy: GDScript = load(LEGACY)
	check(legacy != null, "frozen legacy client (the exact code shipped in v14-v18) loads")
	# save-data sentinel: OTA handling must never touch the player's data
	var save_before := ""
	var had_save := FileAccess.file_exists("user://launch.cfg")
	if had_save:
		save_before = FileAccess.get_file_as_string("user://launch.cfg")
	var cf := ConfigFile.new()
	cf.set_value("progress", "bank", 12345)
	cf.save("user://launch.cfg")
	var save_text := FileAccess.get_file_as_string("user://launch.cfg")

	# ======================================================================== 1. the reported downgrade, reproduced with the legacy client
	var live := _live(body)
	check(live["source_sha"] == "faeb937439ced8fe8751deaf25c9f898b0110e6e" and int(live["sequence"]) == 3 and live["channel"] == CH and live["runtime_compat"] == COMPAT, "fixture is the live poc-g2 manifest (seq 3, source faeb937, r2-abbbcedcb90e)")
	for v in [["v14", 27], ["v15", 28], ["v16", 29], ["v17", 30], ["v18", 31]]:
		var lc: Node = _mk(legacy, _info(int(v[1]), 0), _dir(), {})
		var ev: Dictionary = lc.evaluate_manifest(live)
		check(ev["action"] == "download", "LEGACY %s client would download the seq-3 faeb937 payload (%s)" % [v[0], ev["reason"]])
	# full legacy flow on a v18-like client: stage, then the manifest is removed (404) - the staged update still activates
	var d1 := _dir()
	var routes := {MURL: _json(live), live["url"]: {"ok": true, "code": 200, "body": body}}
	var lc2: Node = _mk(legacy, _info(31, 0), d1, routes)
	var r: Dictionary = await lc2.check_for_update()
	check(r.status == "staged" and lc2.d.pending.sequence == 3, "LEGACY v18 client stages the old payload")
	var lc3: Node = _mk(legacy, _info(31, 0), d1, {MURL: {"ok": true, "code": 404, "body": PackedByteArray()}})
	check(lc3.boot_prepare() == "apply", "LEGACY: removing/retiring the channel does NOT cancel an already staged update (it activates at next launch)")
	check(lc3.apply_staged() and lc3.running.get("id", "") == "poc-g2-3-faeb937", "LEGACY: the old payload activates and runs")
	lc3.confirm_startup_success()
	var lc4: Node = _mk(legacy, _info(31, 0), d1, {MURL: {"ok": true, "code": 404, "body": PackedByteArray()}})
	check(lc4.boot_prepare() == "none" and lc4.running.get("id", "") == "poc-g2-3-faeb937", "LEGACY: once confirmed it is mounted at every launch, whatever the channel serves")
	# --- recovery for legacy clients: a NEWER sequence from baseline-equal source supersedes it (staged AND applied)
	var rec_body := _make_pck("user://safe_rec.pck", "safe_probe_rec", "baseline-equal-v18")
	var rec := _new_manifest("poc-g2-4-dcb9c4d", 4, 83, rec_body)
	var lc5: Node = _mk(legacy, _info(31, 0), d1, {MURL: _json(rec), rec["url"]: {"ok": true, "code": 200, "body": rec_body}})
	lc5.boot_prepare()
	r = await lc5.check_for_update()
	check(r.status == "staged" and lc5.d.pending.id == "poc-g2-4-dcb9c4d", "RECOVERY: a client already running seq 3 is moved to the baseline-equal seq 4")
	var d2 := _dir()
	var lc6: Node = _mk(legacy, _info(31, 0), d2, {MURL: _json(live), live["url"]: {"ok": true, "code": 200, "body": body}})
	await lc6.check_for_update()                                   # staged seq 3, not yet applied
	lc6.fetcher = _fetcher({MURL: _json(rec), rec["url"]: {"ok": true, "code": 200, "body": rec_body}})
	r = await lc6.check_for_update()
	check(r.status == "staged" and lc6.d.pending.id == "poc-g2-4-dcb9c4d", "RECOVERY: a staged-but-not-yet-applied seq 3 is replaced by seq 4")
	var lc7: Node = _mk(legacy, _info(31, 0), _dir(), {MURL: _json(rec), rec["url"]: {"ok": true, "code": 200, "body": rec_body}})
	r = await lc7.check_for_update()
	check(r.status == "staged" and lc7.d.pending.sequence == 4, "RECOVERY: a client that never saw seq 3 goes straight to seq 4 (never receives the old payload)")
	var seq0 := _new_manifest("poc-g2-0", 0, 83, rec_body)
	var lc8: Node = _mk(legacy, _info(31, 0), _dir(), {MURL: _json(seq0)})
	r = await lc8.check_for_update()
	check(r.status == "no_update", "OPTION C (sequence-0 'no update' manifest) stops new staging for clients at sequence 0 ...")
	var lc9: Node = _mk(legacy, _info(31, 0), d1, {MURL: _json(seq0)})
	lc9.boot_prepare()
	check(lc9.running.get("id", "") == "poc-g2-3-faeb937", "... but cannot remove a pack a client already confirmed (still mounted)")

	# ======================================================================== 2. the new client refuses the same updates
	var nc: Node = _mk(OtaClient, _info(40, 83), _dir(), {})
	var ev2: Dictionary = nc.evaluate_manifest(live)
	check(ev2["action"] == "reject" and "source_epoch" in ev2["reason"], "NEW: the legacy faeb937 manifest (no source provenance) is rejected (%s)" % ev2["reason"])
	var old_hi := _new_manifest("old-high-seq", 999, 63, body, {"source_sha": "faeb937439ced8fe8751deaf25c9f898b0110e6e"})
	ev2 = nc.evaluate_manifest(old_hi)
	check(ev2["action"] == "reject" and "older than this native build" in ev2["reason"], "NEW: an OLDER payload with a HIGHER sequence is rejected (%s)" % ev2["reason"])
	ev2 = nc.evaluate_manifest(_new_manifest("equal", 4, 83, body))
	check(ev2["action"] == "download", "NEW: a baseline-equal payload is accepted")
	ev2 = nc.evaluate_manifest(_new_manifest("newer", 1, 90, body))
	check(ev2["action"] == "download", "NEW: a newer payload with a lower sequence number is accepted (epoch first)")
	ev2 = nc.evaluate_manifest(_new_manifest("bad-sha", 9, 90, body, {"source_sha": "zz"}))
	check(ev2["action"] == "reject" and "revision" in ev2["reason"], "NEW: a malformed source revision is rejected")
	ev2 = nc.evaluate_manifest(_new_manifest("other-runtime", 9, 90, body, {"runtime_compat": "r3-other"}))
	check(ev2["action"] == "reject" and "native" in ev2["reason"], "NEW: a cross-runtime payload is rejected")
	ev2 = nc.evaluate_manifest(_new_manifest("capped", 9, 90, body, {"max_version_code": 30}))
	check(ev2["action"] == "reject", "NEW: max_version_code excludes newer native builds")
	# ordering by (epoch, sequence)
	var oc: Node = _mk(OtaClient, _info(40, 83), _dir(), {})
	oc.d["current"] = _meta("cur", 5, 90, body)
	check(oc.evaluate_manifest(_new_manifest("a", 4, 90, body))["action"] == "none", "ORDER: same epoch, lower sequence -> no update")
	check(oc.evaluate_manifest(_new_manifest("b", 100, 89, body))["action"] == "none", "ORDER: older epoch with a high sequence -> no update")
	check(oc.evaluate_manifest(_new_manifest("c", 1, 91, body))["action"] == "download", "ORDER: newer epoch wins")
	check(oc.evaluate_manifest(_new_manifest("d", 6, 90, body))["action"] == "download", "ORDER: same epoch, higher sequence wins")

	# ======================================================================== 3. stored packs are re-validated (previously staged / mounted obsolete updates)
	var mounts: Array = []
	var stub := func(p: String) -> bool:
		mounts.append(p)
		return true
	# 3a: obsolete update staged before a native upgrade
	var d3 := _dir()
	_stub_pack(d3, "old-staged.pck", body)
	_write_state(d3, {"current": {}, "previous": {}, "failed_ids": [], "pending": _meta("old-staged", 3, 63, body, {"status": "staged"})})
	var c3: Node = _mk(OtaClient, _info(40, 83), d3, {})
	c3.mount_func = stub
	check(c3.boot_prepare() == "none" and c3.d.pending.is_empty() and not FileAccess.file_exists(d3.path_join("old-staged.pck")) and (c3.d.failed_ids as Array).has("old-staged"), "STAGED: an obsolete staged update (older than the native build) is discarded at launch, never applied")
	_write_state(d3, {"current": {}, "previous": {}, "failed_ids": [], "pending": _meta("old-staged2", 3, 63, body, {"status": "staged"})})
	_stub_pack(d3, "old-staged2.pck", body)
	var c3b: Node = _mk(OtaClient, _info(40, 83), d3, {})
	c3b.mount_func = stub
	check(not c3b.apply_staged() and mounts.is_empty(), "STAGED: activation re-validates and refuses an obsolete pack (nothing mounted)")
	# 3b: a confirmed pack from before a native upgrade is not mounted any more
	var d4 := _dir()
	_stub_pack(d4, "poc-g2-3-faeb937.pck", body)
	_write_state(d4, {"current": _meta("poc-g2-3-faeb937", 3, 63, body), "previous": {}, "failed_ids": [], "pending": {}})
	var c4: Node = _mk(OtaClient, _info(40, 83), d4, {})
	c4.mount_func = stub
	var act: String = c4.boot_prepare()
	check(act == "none" and mounts.is_empty() and c4.running.is_empty() and c4.d.current.is_empty() and not FileAccess.file_exists(d4.path_join("poc-g2-3-faeb937.pck")), "MOUNTED: a known-good pack older than the new native build is dropped, the embedded baseline runs")
	# 3c: wrong runtime / legacy record without provenance
	var d5 := _dir()
	_stub_pack(d5, "x.pck", body)
	_write_state(d5, {"current": _meta("x", 3, 90, body, {"runtime_compat": "r2-other"}), "previous": {}, "failed_ids": [], "pending": {}})
	var c5: Node = _mk(OtaClient, _info(40, 83), d5, {})
	c5.mount_func = stub
	c5.boot_prepare()
	check(mounts.is_empty() and c5.d.current.is_empty(), "MOUNTED: a pack for a different runtime is never mounted")
	var legacy_rec := _meta("legacy-rec", 3, 0, body)
	legacy_rec.erase("source_epoch")
	var d6 := _dir()
	_stub_pack(d6, "legacy-rec.pck", body)
	_write_state(d6, {"current": legacy_rec, "previous": {}, "failed_ids": [], "pending": {}})
	var c6: Node = _mk(OtaClient, _info(40, 83), d6, {})
	c6.mount_func = stub
	c6.boot_prepare()
	check(mounts.is_empty() and c6.d.current.is_empty(), "MOUNTED: a state record from a legacy client (no provenance) is not trusted")
	# 3d: valid current still mounts; invalid current falls back to a valid previous
	var d7 := _dir()
	_stub_pack(d7, "good.pck", body)
	_stub_pack(d7, "stale.pck", body)
	_write_state(d7, {"current": _meta("stale", 3, 60, body), "previous": _meta("good", 2, 90, body), "failed_ids": [], "pending": {}})
	var c7: Node = _mk(OtaClient, _info(40, 83), d7, {})
	c7.mount_func = stub
	c7.boot_prepare()
	check(mounts.size() == 1 and c7.running.get("id", "") == "good", "FALLBACK: an invalid current falls back to a valid previous pack")
	mounts.clear()

	# ======================================================================== 4. interrupted downloads, failed activation, repeated restarts
	var d8 := _dir()
	var m_ok := _new_manifest("int-1", 7, 90, body)
	var c8: Node = _mk(OtaClient, _info(40, 83), d8, {MURL: _json(m_ok), m_ok["url"]: {"ok": true, "code": 200, "body": body.slice(0, body.size() / 2)}})
	r = await c8.check_for_update()
	check(r.status == "download_failed" and c8.d.pending.is_empty(), "INTERRUPTED: a half-downloaded payload is never staged")
	var fa := FileAccess.open(d8.path_join("download.part"), FileAccess.WRITE)
	fa.store_string("leftover")
	fa.close()
	var c8b: Node = _mk(OtaClient, _info(40, 83), d8, {})
	c8b.boot_prepare()
	check(not FileAccess.file_exists(d8.path_join("download.part")), "INTERRUPTED: leftover partial file is removed at the next launch")
	# failed activation then no retry loop
	var garbage := "this is not a pck".to_utf8_buffer()
	var d9 := _dir()
	var mg := _new_manifest("bad-1", 8, 90, garbage)
	var c9: Node = _mk(OtaClient, _info(40, 83), d9, {MURL: _json(mg), mg["url"]: {"ok": true, "code": 200, "body": garbage}})
	await c9.check_for_update()
	var c9b: Node = _mk(OtaClient, _info(40, 83), d9, {MURL: _json(mg), mg["url"]: {"ok": true, "code": 200, "body": garbage}})
	check(c9b.boot_prepare() == "apply" and not c9b.apply_staged() and (c9b.d.failed_ids as Array).has("bad-1"), "ACTIVATION: a payload that fails to mount is rolled back and blacklisted")
	r = await c9b.check_for_update()
	check(r.status == "rejected" and "failed" in r.reason, "ACTIVATION: the failed payload is not downloaded again (no restart loop)")
	# crash loop on a confirmed pack
	var d10 := _dir()
	_stub_pack(d10, "loop.pck", body)
	_write_state(d10, {"current": _meta("loop", 4, 90, body), "previous": {}, "failed_ids": [], "pending": {}})
	var boots := 0
	var dropped := false
	for i in 5:
		var cl: Node = _mk(OtaClient, _info(40, 83), d10, {})
		cl.mount_func = stub
		cl.boot_prepare()                                         # "crashes" before confirm_startup_success()
		if cl.running.is_empty():
			dropped = true
			break
		boots += 1
	check(boots == 3 and dropped, "RESTARTS: a pack that never confirms a start is dropped after 3 launches (booted %d times)" % boots)
	var d11 := _dir()
	_stub_pack(d11, "fine.pck", body)
	_write_state(d11, {"current": _meta("fine", 4, 90, body), "previous": {}, "failed_ids": [], "pending": {}})
	for i in 6:
		var cf2: Node = _mk(OtaClient, _info(40, 83), d11, {})
		cf2.mount_func = stub
		cf2.boot_prepare()
		cf2.confirm_startup_success()
	var cfin: Node = _mk(OtaClient, _info(40, 83), d11, {})
	cfin.mount_func = stub
	cfin.boot_prepare()
	check(cfin.running.get("id", "") == "fine", "RESTARTS: a healthy pack that confirms each start is kept")

	# ======================================================================== 5. deliberate rollback
	var rb_body := _make_pck("user://safe_rb.pck", "safe_probe_rb", "rollback-target")
	var rbm := _new_manifest("rb-1", 10, 70, rb_body, {"rollback": {"authorized": true, "reason": "v19 regression; return to the v17 payload", "floor_epoch": 70}})
	var rn: Node = _mk(OtaClient, _info(40, 83), _dir(), {})
	check(rn.evaluate_manifest(rbm)["action"] == "download", "ROLLBACK: an explicitly authorized older payload is accepted")
	for bad in [{"authorized": false, "reason": "x", "floor_epoch": 70}, {"authorized": true, "reason": "", "floor_epoch": 70}, {"authorized": true, "reason": "x", "floor_epoch": 80}, {"reason": "x", "floor_epoch": 70}]:
		var badm := _new_manifest("rb-bad", 10, 70, rb_body, {"rollback": bad})
		check(rn.evaluate_manifest(badm)["action"] == "reject", "ROLLBACK: incomplete authorization rejected (%s)" % JSON.stringify(bad))
	var d12 := _dir()
	var rc: Node = _mk(OtaClient, _info(40, 83), d12, {MURL: _json(rbm), rbm["url"]: {"ok": true, "code": 200, "body": rb_body}})
	r = await rc.check_for_update()
	check(r.status == "staged" and rc.d.pending.rollback_authorized == true, "ROLLBACK: staged with its authorization recorded")
	var rc2: Node = _mk(OtaClient, _info(40, 83), d12, {})
	check(rc2.boot_prepare() == "apply" and rc2.apply_staged(), "ROLLBACK: the authorized older payload activates")
	rc2.confirm_startup_success()
	var rc3: Node = _mk(OtaClient, _info(40, 83), d12, {})
	rc3.boot_prepare()
	check(rc3.running.get("id", "") == "rb-1", "ROLLBACK: and stays mounted (authorization survives revalidation)")
	check(rc3.evaluate_manifest(_new_manifest("after", 11, 83, rb_body))["action"] == "download", "ROLLBACK: a later current-epoch release moves forward again")

	# ======================================================================== 6. save data
	check(FileAccess.get_file_as_string("user://launch.cfg") == save_text, "SAVE DATA: player progress (launch.cfg) is untouched by every scenario above")
	if had_save:
		var fs := FileAccess.open("user://launch.cfg", FileAccess.WRITE)
		fs.store_string(save_before)
		fs.close()
	else:
		DirAccess.remove_absolute("user://launch.cfg")
