extends Node
## Грузит все скрипты и сцены из game/ и печатает ошибки. Godot --headless --path . res://tools/check.tscn

func _ready() -> void:
	var bad := 0
	var files := _files("res://game", ".gd") + _files("res://game", ".tscn")
	for path in files:
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			print("FAIL ", path)
			bad += 1
		elif res is GDScript and not res.can_instantiate() and not (res as GDScript).is_abstract():
			print("FAIL (не создаётся) ", path)
			bad += 1
	print("CHECK DONE, files: ", files.size(), ", failed: ", bad)
	get_tree().quit(1 if bad > 0 else 0)


func _files(dir: String, ext: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _files(dir + "/" + sub, ext)
	return out
