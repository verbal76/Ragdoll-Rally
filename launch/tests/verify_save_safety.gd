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
	print("---- SAVE SAFETY %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
