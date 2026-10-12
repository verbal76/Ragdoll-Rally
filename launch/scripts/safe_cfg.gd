extends RefCounted
## Crash-safe ConfigFile persistence (same on-disk format as before, so existing saves load unchanged).
## save(): write <path>.tmp, keep the previous good file as <path>.bak, then rename the new file into place.
## load(): if the main file is missing/corrupt, fall back to <path>.bak. No class_name on purpose (OTA fingerprint).

static func save(cf: ConfigFile, path: String) -> int:
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
