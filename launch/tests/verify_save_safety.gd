extends SceneTree
## Crash-safe config persistence: format unchanged, .bak recovery from a corrupt/truncated main file, no partial file left behind.
##   godot --headless --path launch -s tests/verify_save_safety.gd
const SafeCfg := preload("res://scripts/safe_cfg.gd")
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	var p := "user://_savetest.cfg"
	for s in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(p + s)
	var cf := ConfigFile.new()
	cf.set_value("progress", "bank", 123)
	check(SafeCfg.save(cf, p) == OK, "first save ok")
	check(not FileAccess.file_exists(p + ".tmp"), "no .tmp left behind")
	var plain := ConfigFile.new()
	check(plain.load(p) == OK and int(plain.get_value("progress", "bank", 0)) == 123, "file is plain ConfigFile format (existing saves stay compatible)")
	cf.set_value("progress", "bank", 456)
	SafeCfg.save(cf, p)
	check(FileAccess.file_exists(p + ".bak"), "previous good copy kept as .bak")
	# simulate a crash/corruption that truncated the main file
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("[progress\nbank = ")
	f.close()
	var r := ConfigFile.new()
	check(SafeCfg.load(r, p) == OK, "corrupt main file recovers from .bak")
	check(int(r.get_value("progress", "bank", 0)) == 123, "recovered the last good value (123)")
	# legacy file (no .bak ever written) loads untouched
	DirAccess.remove_absolute(p + ".bak")
	var g := FileAccess.open(p, FileAccess.WRITE)
	g.store_string("[progress]\nbank=77\n")
	g.close()
	var l := ConfigFile.new()
	check(SafeCfg.load(l, p) == OK and int(l.get_value("progress", "bank", 0)) == 77, "legacy-format save loads unchanged")
	# missing file keeps the old 'not found' contract
	for s in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(p + s)
	check(SafeCfg.load(ConfigFile.new(), p) != OK, "missing file still reports an error (first-run contract)")
	# ---- schema version: legacy saves load unchanged, get stamped on write, originals are kept; future schemas are never down-stamped
	for sfx in ["", ".tmp", ".bak", ".v0", ".v7"]:
		DirAccess.remove_absolute(p + sfx)
	var legacy_text := "[view]\n\npull_right=true\n\n[score]\n\nbest=4200\n\n[progress]\n\nbank=980\nlaunchers={\"catapult\": 2}\n"
	var lf := FileAccess.open(p, FileAccess.WRITE)
	lf.store_string(legacy_text)
	lf.close()
	var lg := ConfigFile.new()
	check(SafeCfg.load(lg, p) == OK and SafeCfg.schema_of(lg) == 0, "legacy save (no schema key) loads as schema 0")
	check(int(lg.get_value("score", "best", 0)) == 4200 and int(lg.get_value("progress", "bank", 0)) == 980 and bool(lg.get_value("view", "pull_right", false)), "legacy progress + settings read unchanged")
	check(lg.get_value("progress", "launchers", {}) == {"catapult": 2}, "legacy dictionary values survive")
	lg.set_value("progress", "bank", 1000)
	SafeCfg.save(lg, p)
	var after := ConfigFile.new()
	after.load(p)
	check(SafeCfg.schema_of(after) == SafeCfg.SCHEMA and int(after.get_value("score", "best", 0)) == 4200 and int(after.get_value("progress", "bank", 0)) == 1000, "first write stamps the schema and keeps all progress")
	check(FileAccess.file_exists(p + ".v0") and FileAccess.get_file_as_string(p + ".v0") == legacy_text, "the untouched legacy file is kept once as .v0")
	SafeCfg.save(after, p)
	check(FileAccess.get_file_as_string(p + ".v0") == legacy_text, "the .v0 copy is never overwritten by later saves")
	var fut := FileAccess.open(p, FileAccess.WRITE)
	fut.store_string("[meta]\nschema=7\n[score]\nbest=9000\nnew_future_key=\"keep me\"\n[future_section]\nx=1\n")
	fut.close()
	var ff := ConfigFile.new()
	check(SafeCfg.load(ff, p) == OK and SafeCfg.schema_of(ff) == 7 and int(ff.get_value("score", "best", 0)) == 9000, "a newer schema is read tolerantly (known keys)")
	ff.set_value("progress", "bank", 5)
	SafeCfg.save(ff, p)
	var ff2 := ConfigFile.new()
	ff2.load(p)
	check(SafeCfg.schema_of(ff2) == 7 and str(ff2.get_value("score", "new_future_key", "")) == "keep me" and int(ff2.get_value("future_section", "x", 0)) == 1, "writing never down-stamps and keeps unknown keys / sections")
	check(FileAccess.file_exists(p + ".v7"), "the newer-format original is kept once as .v7")
	# corrupt file with a stamp: .bak recovery still works with the schema layer
	var cc := FileAccess.open(p, FileAccess.WRITE)
	cc.store_string("[meta\nschema=")
	cc.close()
	var rec := ConfigFile.new()
	check(SafeCfg.load(rec, p) == OK and SafeCfg.schema_of(rec) == 7, "interrupted write: backup fallback still works")
	for sfx in ["", ".tmp", ".bak", ".v0", ".v7"]:
		DirAccess.remove_absolute(p + sfx)
	print("---- SAVE SAFETY %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
