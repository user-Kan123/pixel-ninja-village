extends Node
## 全局数据加载：名词表 + 忍术表 + UI 字体 + 忍术图标绘制。
## 这是「换皮层」：代码不出现专有名词，全部通过数据文件取用。

const JUTSU_DISPLAY_ORDER := [
	"blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones",
	"lightning_edge", "medical_palm", "earth_wall", "binding_seal", "fox_genjutsu",
	"rasengan", "sharingan_insight", "substitution", "chakra_flow", "monstrous_strength",
]

var strings: Dictionary = {}
var jutsu: Dictionary = {}
var missions: Dictionary = {}
var jutsu_list: Array[String] = []
var ui_font: FontFile


func _ready() -> void:
	strings = _load_json("res://data/strings.json").get("zh", {})
	jutsu = _load_json("res://data/jutsu.json")
	missions = _load_json("res://data/mission.json")
	_build_jutsu_list()
	_load_font()


func s(key: String) -> String:
	return String(strings.get(key, key))


func font() -> Font:
	if ui_font != null:
		return ui_font
	return ThemeDB.fallback_font


func _build_jutsu_list() -> void:
	jutsu_list = []
	for id in JUTSU_DISPLAY_ORDER:
		if jutsu.has(id):
			jutsu_list.append(id)
	for id in jutsu:
		if not jutsu_list.has(id):
			jutsu_list.append(id)


## 忍术图标：程序化绘制，无素材依赖，供 HUD 与装配界面共用。
## c 必须是正在执行 _draw 的 CanvasItem（调用时传 self）。
static func draw_jutsu_icon(c: CanvasItem, id: String, center: Vector2, r: float) -> void:
	match id:
		"blink":
			c.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r * 0.85, r * 0.6), center + Vector2(-r * 0.85, r * 0.6),
			]), Color(0.6, 0.88, 1.0))
		"fireball":
			c.draw_circle(center, r * 0.85, Color(1.0, 0.55, 0.2))
			c.draw_circle(center, r * 0.4, Color(1.0, 0.92, 0.65))
		"great_fireball":
			c.draw_circle(center, r, Color(1.0, 0.42, 0.15))
			c.draw_circle(center, r * 0.62, Color(1.0, 0.7, 0.25))
			c.draw_circle(center, r * 0.28, Color(1.0, 0.96, 0.8))
		"thunder_dash":
			c.draw_colored_polygon(PackedVector2Array([
				center + Vector2(r * 0.3, -r), center + Vector2(-r * 0.15, 0.0),
				center + Vector2(r * 0.2, 0.0), center + Vector2(-r * 0.35, r),
				center + Vector2(r * 0.05, r * 0.15), center + Vector2(-r * 0.4, r * 0.15),
			]), Color(0.55, 0.9, 1.0))
		"shadow_clones":
			c.draw_rect(Rect2(center + Vector2(-r * 0.85, -r * 0.5), Vector2(r * 0.8, r * 1.2)), Color(0.42, 0.68, 1.0, 0.75))
			c.draw_rect(Rect2(center + Vector2(-r * 0.05, -r * 0.85), Vector2(r * 0.9, r * 1.3)), Color(0.6, 0.85, 1.0, 0.95))
		"lightning_edge":
			var d := Vector2(0.85, -0.55).normalized()
			var p := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([
				center + d * r, center - d * r * 0.9 + p * r * 0.22, center - d * r * 0.9 - p * r * 0.22,
			]), Color(0.6, 0.95, 1.0))
			c.draw_line(center - d * r, center + d * r, Color(0.9, 1.0, 1.0, 0.9), 1.5)
		"medical_palm":
			c.draw_rect(Rect2(center + Vector2(-r * 0.22, -r * 0.85), Vector2(r * 0.44, r * 1.7)), Color(0.45, 0.95, 0.6))
			c.draw_rect(Rect2(center + Vector2(-r * 0.85, -r * 0.22), Vector2(r * 1.7, r * 0.44)), Color(0.45, 0.95, 0.6))
		"earth_wall":
			for i in 3:
				var y := center.y - r * 0.8 + float(i) * r * 0.62
				c.draw_rect(Rect2(center.x - r * 0.85, y, r * 1.7, r * 0.5), Color(0.55, 0.44, 0.28) if i % 2 == 0 else Color(0.45, 0.36, 0.24))
		"binding_seal":
			c.draw_arc(center, r * 0.85, 0.0, TAU, 20, Color(0.75, 0.55, 1.0), 2.0)
			c.draw_arc(center, r * 0.45, 0.0, TAU, 14, Color(0.85, 0.7, 1.0), 1.5)
			c.draw_line(center + Vector2(0, -r * 0.85), center + Vector2(0, r * 0.85), Color(0.8, 0.6, 1.0, 0.7), 1.0)
		"fox_genjutsu":
			c.draw_arc(center, r * 0.9, 0.0, TAU * 0.7, 16, Color(0.72, 0.45, 1.0), 2.0)
			c.draw_arc(center, r * 0.55, PI, PI + TAU * 0.7, 14, Color(0.85, 0.6, 1.0), 2.0)
			c.draw_circle(center, r * 0.18, Color(0.9, 0.75, 1.0))
		"rasengan":
			c.draw_circle(center, r * 0.8, Color(0.55, 0.75, 1.0, 0.9))
			c.draw_arc(center, r * 0.55, 0.0, TAU * 0.75, 14, Color(0.85, 0.95, 1.0), 2.0)
			c.draw_arc(center, r * 0.3, PI, PI + TAU * 0.7, 10, Color(0.4, 0.65, 1.0), 2.0)
		"sharingan_insight":
			c.draw_arc(center, r * 0.85, 0.0, TAU, 20, Color(0.9, 0.25, 0.3), 2.0)
			c.draw_circle(center, r * 0.32, Color(0.85, 0.2, 0.25))
			for i in 3:
				var ang := TAU * float(i) / 3.0 + 0.5
				c.draw_circle(center + Vector2.from_angle(ang) * r * 0.6, r * 0.14, Color(0.95, 0.5, 0.55))
		"substitution":
			c.draw_rect(Rect2(center.x - r * 0.25, center.y - r * 0.8, r * 0.5, r * 1.6), Color(0.65, 0.45, 0.25))
			c.draw_arc(center + Vector2(r * 0.4, 0), r * 0.45, -PI / 2.0, PI / 2.0, 10, Color(0.9, 0.85, 0.7), 1.5)
		"chakra_flow":
			c.draw_arc(center, r * 0.75, 0.0, TAU, 18, Color(0.4, 0.7, 1.0), 2.0)
			for i in 3:
				var ang2 := TAU * float(i) / 3.0 - PI / 2.0
				var p2 := center + Vector2.from_angle(ang2) * r * 0.75
				c.draw_colored_polygon(PackedVector2Array([
					p2 + Vector2.from_angle(ang2) * r * 0.35,
					p2 + Vector2.from_angle(ang2 + 2.3) * r * 0.18,
					p2 + Vector2.from_angle(ang2 - 2.3) * r * 0.18,
				]), Color(0.6, 0.85, 1.0))
		"monstrous_strength":
			c.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-r * 0.7, r * 0.7), center + Vector2(-r * 0.7, -r * 0.3),
				center + Vector2(-r * 0.1, -r * 0.8), center + Vector2(r * 0.5, -r * 0.5),
				center + Vector2(r * 0.7, r * 0.1), center + Vector2(r * 0.3, r * 0.7),
			]), Color(0.95, 0.5, 0.35))
		_:
			c.draw_rect(Rect2(center - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), Color(0.75, 0.75, 0.78))


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
