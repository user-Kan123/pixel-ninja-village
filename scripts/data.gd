extends Node
## 全局数据加载：名词表 + 忍术表 + UI 字体 + 忍术图标绘制。
## 这是「换皮层」：代码不出现专有名词，全部通过数据文件取用。

const JUTSU_DISPLAY_ORDER := [
	"blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones",
	"lightning_edge", "medical_palm", "earth_wall", "binding_seal", "fox_genjutsu",
	"rasengan", "sharingan_insight", "substitution", "chakra_flow", "monstrous_strength",
]

## 忍具店售卖顺序：由便宜到贵，与「手里剑 → 苦无 → 短刀 → 长剑」的强度梯度一致
const WEAPON_DISPLAY_ORDER := ["shuriken", "kunai", "tanto", "longsword"]
## 消耗品显示顺序（兵粮丸排在最前，因为它是唯一在店里卖的）
const ITEM_DISPLAY_ORDER := ["hyorogan", "heal_pill", "chakra_pill"]

var strings: Dictionary = {}
var jutsu: Dictionary = {}
var missions: Dictionary = {}
var weapons: Dictionary = {}
## 消耗品表（兵粮丸 / 回力药 / 查克拉药）
var items: Dictionary = {}
var jutsu_list: Array[String] = []
var weapon_list: Array[String] = []
var item_list: Array[String] = []
var ui_font: FontFile


func _ready() -> void:
	strings = _load_json("res://data/strings.json").get("zh", {})
	jutsu = _load_json("res://data/jutsu.json")
	missions = _load_json("res://data/mission.json")
	weapons = _load_json("res://data/weapon.json")
	items = _load_json("res://data/item.json")
	_build_jutsu_list()
	_build_weapon_list()
	_build_item_list()
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


func _build_weapon_list() -> void:
	weapon_list = []
	for id in WEAPON_DISPLAY_ORDER:
		if weapons.has(id):
			weapon_list.append(id)
	for id in weapons:
		if not weapon_list.has(id):
			weapon_list.append(id)


func _build_item_list() -> void:
	item_list = []
	for id in ITEM_DISPLAY_ORDER:
		if items.has(id):
			item_list.append(id)
	for id in items:
		if not item_list.has(id):
			item_list.append(id)


# ---------------------------------------------------------------- 背包物品的统一视图

## 背包里的东西分两张家：武器表（weapon.json）与消耗品表（item.json）。
## 背包、商店、HUD 都只认这个统一入口，所以以后加「起爆符」「毒苦无」只要往表里加一条。
func item_def(id: String) -> Dictionary:
	if weapons.has(id):
		return weapons[id]
	if items.has(id):
		return items[id]
	return {}


func has_item(id: String) -> bool:
	return weapons.has(id) or items.has(id)


func is_weapon(id: String) -> bool:
	return weapons.has(id)


func is_consumable(id: String) -> bool:
	return items.has(id)


func item_name(id: String) -> String:
	if id.is_empty():
		return s("loadout.empty")
	var d: Dictionary = item_def(id)
	return s(String(d.get("name_key", id)))


func item_desc(id: String) -> String:
	var d: Dictionary = item_def(id)
	return s(String(d.get("desc_key", "")))


## 一格里最多放几个（1 = 不可堆叠）
func item_stack(id: String) -> int:
	return maxi(int(item_def(id).get("stack", 1)), 1)


## 满耐久（0 = 没有耐久这个概念，比如手里剑）
func item_durability(id: String) -> float:
	return float(item_def(id).get("durability", 0.0))


func item_price(id: String) -> int:
	return int(item_def(id).get("price", 0))


## 忍具店货架：武器 + 定价大于 0 的消耗品
func shop_list() -> Array:
	var out: Array = []
	for id in weapon_list:
		out.append(id)
	for id in item_list:
		if item_price(id) > 0:
			out.append(id)
	return out


## 背包 / 商店共用的图标：武器走武器图标，消耗品画成一颗丸子
static func draw_item_icon(c: CanvasItem, id: String, center: Vector2, r: float) -> void:
	if Data.weapons.has(id):
		draw_weapon_icon(c, id, center, r)
		return
	if id == "chakra_pill":
		c.draw_circle(center, r * 0.8, Color("4a7fd4"))
		c.draw_circle(center + Vector2(-r * 0.25, -r * 0.25), r * 0.24, Color("cfe0ff"))
		c.draw_arc(center, r * 0.9, 0.0, TAU, 18, Color(0.45, 0.7, 1.0, 0.75), maxf(r * 0.12, 1.0))
	elif id == "heal_pill":
		c.draw_circle(center, r * 0.8, Color("58b866"))
		c.draw_circle(center + Vector2(-r * 0.25, -r * 0.25), r * 0.24, Color("d8f5d8"))
		c.draw_arc(center, r * 0.9, 0.0, TAU, 18, Color(0.5, 0.9, 0.6, 0.75), maxf(r * 0.12, 1.0))
	else:
		## 兵粮丸：棕色丸子 + 高光（默认分支，方便以后加同类食物）
		c.draw_circle(center, r * 0.8, Color("b07a3c"))
		c.draw_circle(center + Vector2(-r * 0.26, -r * 0.26), r * 0.26, Color("e8c89a"))
		c.draw_arc(center, r * 0.9, 0.0, TAU, 18, Color(0.85, 0.6, 0.3, 0.7), maxf(r * 0.12, 1.0))


## 忍具静态信息（缺表兜底，避免界面拿到 null）
func weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func weapon_name(id: String) -> String:
	if id.is_empty():
		return s("loadout.empty")
	var w: Dictionary = weapon(id)
	return s(String(w.get("name_key", id)))


## 忍具使用方式文案：近战 / 投掷 / 两者
func weapon_mode(id: String) -> String:
	var w: Dictionary = weapon(id)
	var melee := bool(w.get("can_melee", false))
	var ranged := bool(w.get("can_throw", false))
	if melee and ranged:
		return s("weapon.mode.both")
	if melee:
		return s("weapon.mode.melee")
	if ranged:
		return s("weapon.mode.ranged")
	return ""


## 忍具图标：程序化绘制，无素材依赖，供 HUD / 装备界面 / 商店共用。
## c 必须是正在执行 _draw 的 CanvasItem。
static func draw_weapon_icon(c: CanvasItem, id: String, center: Vector2, r: float) -> void:
	match id:
		"shuriken":
			## 四角手里剑：朝四个方向伸出的尖 + 中心圆孔
			var pts := PackedVector2Array()
			for i in 4:
				var a := TAU * float(i) / 4.0 - PI / 4.0
				var p := center + Vector2.from_angle(a) * r
				var a1 := a + 0.45
				var a2 := a - 0.45
				pts.append(p)
				pts.append(center + Vector2.from_angle(a1) * r * 0.34)
				pts.append(center + Vector2.from_angle(a2) * r * 0.34)
			c.draw_colored_polygon(pts, Color("b9bec6"))
			c.draw_circle(center, r * 0.16, Color(0.12, 0.12, 0.14))
		"kunai":
			## 短刃 + 环柄
			var d := Vector2(0.86, -0.5).normalized()
			var perp := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([
				center + d * r, center - d * r * 0.35 + perp * r * 0.3, center - d * r * 0.35 - perp * r * 0.3,
			]), Color("c8ccd4"))
			c.draw_line(center - d * r * 0.3, center - d * r * 0.95, Color("6a5a44"), maxf(r * 0.2, 2.0))
			c.draw_arc(center - d * r * 0.95, r * 0.28, 0.0, TAU, 14, Color("8a8f98"), maxf(r * 0.14, 1.5))
		"tanto":
			## 直短刀：刀刃 + 护手 + 短柄
			var d2 := Vector2(0.86, -0.5).normalized()
			var p2 := Vector2(-d2.y, d2.x)
			c.draw_colored_polygon(PackedVector2Array([
				center + d2 * r, center + d2 * r * 0.2 + p2 * r * 0.26, center + d2 * r * 0.2 - p2 * r * 0.26,
			]), Color("dfe3ea"))
			c.draw_line(center + d2 * r * 0.2 - p2 * r * 0.34, center + d2 * r * 0.2 + p2 * r * 0.34, Color("c8a24a"), maxf(r * 0.18, 2.0))
			c.draw_line(center + d2 * r * 0.2, center - d2 * r * 0.85, Color("3f3a33"), maxf(r * 0.24, 2.5))
		"longsword":
			## 长剑：更长刀刃 + 长护手 + 柄头
			var d3 := Vector2(0.86, -0.5).normalized()
			var p3 := Vector2(-d3.y, d3.x)
			c.draw_colored_polygon(PackedVector2Array([
				center + d3 * r, center + d3 * r * 0.1 + p3 * r * 0.24, center + d3 * r * 0.1 - p3 * r * 0.24,
			]), Color("e6eaf1"))
			c.draw_line(center + d3 * r * 0.1 - p3 * r * 0.5, center + d3 * r * 0.1 + p3 * r * 0.5, Color("c8a24a"), maxf(r * 0.18, 2.0))
			c.draw_line(center + d3 * r * 0.1, center - d3 * r * 0.9, Color("4a3f33"), maxf(r * 0.22, 2.5))
			c.draw_circle(center - d3 * r * 0.9, r * 0.15, Color("c8a24a"))
		_:
			c.draw_circle(center, r * 0.5, Color(0.6, 0.6, 0.63, 0.8))


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
