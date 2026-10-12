extends RefCounted
## Crash-safe ConfigFile persistence (same on-disk format as before, so existing saves load unchanged).
## save(): write <path>.tmp, keep the previous good file as <path>.bak, then rename the new file into place.
## Schema: every save carries [meta] schema=N (N = SCHEMA at the time of writing). A file without it is a legacy (schema 0) save and is read exactly as
## before; the first write adds the stamp and keeps the untouched original once as <path>.v0. A file stamped NEWER than this build understands is read
## tolerantly (known keys only), never down-stamped, keeps every unknown key on write, and its original is kept once as <path>.v<N>.
## load(): if the main file is missing/corrupt, fall back to <path>.bak. No class_name on purpose (OTA fingerprint).

const SCHEMA := 1

static func schema_of(cf: ConfigFile) -> int:
	return int(cf.get_value("meta", "schema", 0))

static func save(cf: ConfigFile, path: String) -> int:
	var have := schema_of(cf)
	if FileAccess.file_exists(path):
		var orig := path + ".v%d" % have
		if (have == 0 or have > SCHEMA) and not FileAccess.file_exists(orig):
			DirAccess.copy_absolute(path, orig)          # one-time copy of the untouched legacy / newer-format file
	cf.set_value("meta", "schema", maxi(have, SCHEMA))   # never down-stamp a newer file
	var tmp := path + ".tmp"
	var err := cf.save(tmp)
	if err != OK:
		return err
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return cf.save(path)       # rename unsupported on this filesystem: plain write is still no worse than before
	return OK

static func load(cf: ConfigFile, path: String) -> int:
	var err := cf.load(path)
	if err == OK:
		return OK
	if FileAccess.file_exists(path):           # present but unreadable/corrupt: recover from the last good copy
		if cf.load(path + ".bak") == OK:
			return OK
		cf.clear()
	return err
