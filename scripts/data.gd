extends Node
## 全局数据加载：名词表 + 忍术表 + UI 字体。
## 这是「换皮层」：代码不出现专有名词，全部通过数据文件取用。

var strings: Dictionary = {}
var jutsu: Dictionary = {}
var ui_font: FontFile


func _ready() -> void:
	strings = _load_json("res://data/strings.json").get("zh", {})
	jutsu = _load_json("res://data/jutsu.json")
	_load_font()


func s(key: String) -> String:
	return String(strings.get(key, key))


func font() -> Font:
	if ui_font != null:
		return ui_font
	return ThemeDB.fallback_font


func _load_font() -> void:
	var candidates := [
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"C:/Windows/Fonts/simsun.ttc",
	]
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(path) == OK:
			ui_font = f
			return


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Data: 无法打开数据文件 " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("Data: JSON 解析失败 " + path)
	return {}
