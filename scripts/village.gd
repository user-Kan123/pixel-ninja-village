extends Node2D
## 木叶隐村 v2.0 —— 按《木叶村地图设计 v1.2》实现。
##
## 结构：圆形围墙 + 三环八放射道路 + 一条横穿南部的河 + 7 个区
##   D1 火影区(北) / D2 学校与演习场(西) / D3 商业区(东) / D4 住宅区(东南)
##   D5 河对岸·原宇智波与陵园(西南) / D6 正门区(南) / D7 中忍考试森林(东)
##
## 布局数据（区 / 建筑 / 河 / 桥 / 门 / 填充民居）全部来自 data/village_layout.json，
## 本文件只负责"把数据画出来"和交互。建筑外观是程序化绘制的像素插画（暂无外部素材，
## 以后要换成真图，只需替换 _draw_building() 这一层）。

const INTERACT_RADIUS := 96.0
const WALL_SEGMENTS := 96
## 全局建筑网格：格距固定、所有建筑都落在格子上，这是"规整"的来源
const GRID := Vector2(300.0, 268.0)
const HOUSE_SIZE := Vector2(252.0, 226.0)

var layout: Dictionary = {}
var arena_size := Vector2(4000.0, 2900.0)
var center := Vector2(2000.0, 1450.0)
var wall := Vector2(1780.0, 1280.0)
var river_w := 78.0
## 街区制：8 个扇区 × 4 个环带；rings 是环带的归一化半径边界
var sectors := 8
var rings: Array = [0.14, 0.36, 0.60, 0.84, 1.0]
var snap := 10.0
var gate_clear := 260.0

## 规范化后的建筑：[{id, name, rect, style, solid, priority}]
var buildings: Array = []
var bridges: Array = []
var gate_list: Array = []
var river_pts := PackedVector2Array()
var district_labels: Array = []
## (扇区, 环带) → 该街区铺什么（house / shop / office / none / forest）
var _block_styles: Dictionary = {}

## 交互点（_ready 里从建筑数据推导，不写死坐标）
var BOARD_POS := Vector2.ZERO
var SHOP_POS := Vector2.ZERO
var SHRINE_POS := Vector2.ZERO
var TORII_POS := Vector2.ZERO
var GATE_POS := Vector2.ZERO

var player: Player
var hud: VillageHud
var hud_layer: CanvasLayer
var board_ui: MissionBoardUi
var loadout_ui: LoadoutUi
var shop_ui: ShopUi
var fx_container: Node2D
var projectile_container: Node2D
var field_container: Node2D
var walls: Array[EarthWall] = []
var loadout_open := false

var _hs_active := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layout = Data.village_layout
	if layout.is_empty():
		push_error("village_layout.json 读取失败，村庄会是一片空地")
	_parse_layout()
	_build_decor()
	_build_wall()
	for b in buildings:
		if bool(b["solid"]):
			_add_static_rect(b["rect"] as Rect2)
	fx_container = _make_container("Fx")
	projectile_container = _make_container("Projectiles")
	field_container = _make_container("Fields")
	_spawn_player()
	_spawn_ui()


# ---------------------------------------------------------------- 布局解析

func _parse_layout() -> void:
	var c: Array = layout.get("canvas", [4000, 2900])
	arena_size = Vector2(float(c[0]), float(c[1]))
	var ctr: Array = layout.get("center", [2000, 1450])
	center = Vector2(float(ctr[0]), float(ctr[1]))
	var wr: Array = layout.get("wall_radius", [1780, 1280])
	wall = Vector2(float(wr[0]), float(wr[1]))

	sectors = int(layout.get("sectors", 8))
	rings.clear()
	for rv in layout.get("rings", [0.14, 0.36, 0.60, 0.84, 1.0]):
		rings.append(float(rv))
	snap = float(layout.get("snap", 10.0))
	gate_clear = float(layout.get("gate_clear", 260.0))

	## 河：折线 + 宽度（先算出来，后面摆建筑要避让）
	river_pts = PackedVector2Array()
	var riv: Dictionary = layout.get("river", {})
	river_w = float(riv.get("width", 78.0))
	for p in riv.get("points", []):
		river_pts.append(Vector2(float(p[0]), float(p[1])))

	buildings.clear()
	_rng.seed = 20260929
	## 1) 先放具名建筑：它们占大块，先把位置占住
	for e in layout.get("landmarks", []):
		buildings.append(_make_landmark(e))
	## 2) 街区表：只用来决定"这一格铺什么风格"，以及整块铺林子的特例
	_block_styles.clear()
	for blk in layout.get("blocks", []):
		var sec := int(blk.get("sec", 0))
		var band := int(blk.get("band", 0))
		var st := String((blk.get("fill", {}) as Dictionary).get("style", "house"))
		_block_styles[Vector2i(sec, band)] = st
		_fill_block(blk)
	## 3) 全局网格铺满剩下的空隙（规整 + 占满，遇到路 / 河 / 地标 / 门自动跳过）
	_fill_grid()
	_sort_buildings()

	bridges.clear()
	for e in layout.get("bridges", []):
		bridges.append({
			"id": String(e.get("id", "")),
			"rect": _rect_of(e),
			"angle": float(e.get("angle", 0.0)),
		})

	gate_list.clear()
	for e in layout.get("gates", []):
		gate_list.append({
			"id": String(e.get("id", "")),
			"rect": _rect_of(e),
			"direction": String(e.get("direction", "")),
		})

	district_labels.clear()
	for d in layout.get("districts", []):
		var lp: Array = d.get("label", [0, 0])
		district_labels.append({
			"name": Data.s(String(d.get("name_key", ""))),
			"pos": Vector2(float(lp[0]), float(lp[1])),
			"color": Color(String(d.get("color", "6a6a58"))),
		})

	## 交互点：由建筑推导，改布局不用改代码
	BOARD_POS = _front_of("mission_desk", 60.0)
	SHOP_POS = _front_of("tool_shop", 60.0)
	SHRINE_POS = _front_of("player_apartment", 60.0)
	TORII_POS = _front_of("training_a", 56.0)
	var mg := _building("main_gate")
	GATE_POS = (mg.get("rect", Rect2(3410, 4730, 380, 200)) as Rect2).get_center() + Vector2(0.0, -30.0)


func _rect_of(e: Dictionary) -> Rect2:
	var p: Array = e.get("pos", [0, 0])
	var w := float(e.get("w", 100))
	var h := float(e.get("h", 100))
	return Rect2(float(p[0]), float(p[1]), w, h)


# ---------------------------------------------------------------- 街区制布局

## 具名建筑：在指定街区里按"比例 + 锚点"占位，尺寸由它所在街区的大小决定
func _make_landmark(e: Dictionary) -> Dictionary:
	var sec := int(e.get("sec", 0))
	var band := int(e.get("band", 0))
	var rect := _landmark_rect(sec, band, float(e.get("ratio", 0.6)), String(e.get("anchor", "center")), String(e.get("style", "house")))
	return {
		"id": String(e.get("id", "")),
		"name": Data.s(String(e.get("name_key", ""))),
		"rect": rect,
		"style": String(e.get("style", "house")),
		"solid": bool(e.get("solid", true)),
		"priority": String(e.get("priority", "P2")),
		"variant": 0,
	}


func _sector_span(sec: int) -> Array:
	var w := 360.0 / float(sectors)
	var a0 := float(sec) * w - w * 0.5
	return [deg_to_rad(a0), deg_to_rad(a0 + w)]


## 街区（扇区 × 环带）的轴对齐包围盒：四个角 + 可能穿过的正东南西北点
func _block_bbox(sec: int, band: int) -> Rect2:
	var sp := _sector_span(sec)
	var a0 := float(sp[0])
	var a1 := float(sp[1])
	var r0 := float(rings[band])
	var r1 := float(rings[band + 1])
	var pts: Array = []
	for a in [a0, a1]:
		for rr in [r0, r1]:
			pts.append(_ellipse_point(a, rr))
	for k in 4:
		var ca := deg_to_rad(float(k) * 90.0)
		if ca >= a0 and ca <= a1:
			pts.append(_ellipse_point(ca, r0))
			pts.append(_ellipse_point(ca, r1))
	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in pts:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	return Rect2(minx, miny, maxx - minx, maxy - miny)


## 所有坐标吸附到 snap 网格，这是"规整"的关键
func _snap_rect(r: Rect2) -> Rect2:
	return Rect2(
		roundf(r.position.x / snap) * snap,
		roundf(r.position.y / snap) * snap,
		maxf(roundf(r.size.x / snap) * snap, snap),
		maxf(roundf(r.size.y / snap) * snap, snap)
	)


func _anchor_offset(anchor: String) -> Vector2:
	match anchor:
		"n":
			return Vector2(0.0, -1.0)
		"s":
			return Vector2(0.0, 1.0)
		"w":
			return Vector2(-1.0, 0.0)
		"e":
			return Vector2(1.0, 0.0)
		"nw":
			return Vector2(-1.0, -1.0)
		"ne":
			return Vector2(1.0, -1.0)
		"sw":
			return Vector2(-1.0, 1.0)
		"se":
			return Vector2(1.0, 1.0)
	return Vector2.ZERO


## 街区在"径向 / 切向"上的真实尺寸（不能用轴对齐包围盒：东西朝向的街区
## 包围盒又高又窄，会把人撑成巨型长方形）
func _block_local(sec: int, band: int) -> Dictionary:
	var sp := _sector_span(sec)
	var mid := (float(sp[0]) + float(sp[1])) * 0.5
	var r0 := float(rings[band])
	var r1 := float(rings[band + 1])
	var rm := (r0 + r1) * 0.5
	var reff := _radius_along(mid)
	return {
		"mid": mid,
		"len_r": (r1 - r0) * reff,
		"len_t": (float(sp[1]) - float(sp[0])) * rm * reff,
		"ux": sin(mid),
		"uy": -cos(mid),
		"center": _ellipse_point(mid, rm),
	}


## 椭圆在某个方位上的半径（像素）
func _radius_along(a: float) -> float:
	var sx := sin(a) / maxf(wall.x, 1.0)
	var cy := cos(a) / maxf(wall.y, 1.0)
	return 1.0 / maxf(sqrt(sx * sx + cy * cy), 0.0001)


## 各类建筑的期望长宽比（宽/高，≈贴图地基形状）。
## 斜向扇区和外圈街区的天然形状是细条，不规整会把建筑拉成筷子/薄饼
const PREFER_AR := {
	"watch": 0.75, "tower": 0.80, "vault": 1.30, "hospital": 1.60,
	"hokage": 1.50, "office": 1.40, "school": 1.05, "apartment": 1.00,
	"clan": 1.50, "shop": 1.10, "ramen": 1.10, "tools": 1.30,
	"bath": 1.10, "theater": 1.50, "house": 1.00, "residence": 1.00,
	"training": 0.85, "cemetery": 1.50, "stone": 1.50, "wharf": 2.00,
}

## 在街区里按比例取一块矩形：径向 / 切向哪个是横的就对哪一边
func _block_rect(sec: int, band: int, ratio: float, anchor: String, style := "") -> Rect2:
	var L := _block_local(sec, band)
	var len_r := float(L["len_r"])
	var len_t := float(L["len_t"])
	## 径向主要朝东西 → 宽是径向、高是切向；朝南北则相反
	var radial_horizontal := absf(float(L["ux"])) >= absf(float(L["uy"]))
	var bw := len_r if radial_horizontal else len_t
	var bh := len_t if radial_horizontal else len_r
	var w := bw * ratio
	var h := bh * ratio
	## 长宽比规整：面积不变，把细条修回该风格该有的形状（面积填充类除外）
	if style != "" and not style in ["forest", "park", "hokage_rock"]:
		var target: float = PREFER_AR.get(style, clampf(w / maxf(h, 1.0), 0.8, 1.6))
		var area := w * h
		w = clampf(sqrt(area * target), 90.0, bw * 0.92)
		h = clampf(area / maxf(w, 1.0), 90.0, bh * 0.92)
	var c: Vector2 = L["center"]
	var off := _anchor_offset(anchor)
	var cx := c.x + off.x * (bw - w) * 0.5
	var cy := c.y + off.y * (bh - h) * 0.5
	return _snap_rect(Rect2(cx - w * 0.5, cy - h * 0.5, w, h))


func _landmark_rect(sec: int, band: int, ratio: float, anchor: String, style := "") -> Rect2:
	return _block_rect(sec, band, ratio, anchor, style)


## 特殊街区：整块铺成林子（其余街区交给下面的全局网格）
func _fill_block(blk: Dictionary) -> void:
	var sec := int(blk.get("sec", 0))
	var band := int(blk.get("band", 0))
	if band < 0 or band + 1 >= rings.size():
		return
	var f: Dictionary = blk.get("fill", {})
	var style := String(f.get("style", "house"))
	if style != "forest":
		return
	buildings.append({
		"id": "forest_%d_%d" % [sec, band],
		"name": "",
		"rect": _block_rect(sec, band, 0.94, "center"),
		"style": "forest",
		"solid": false,
		"priority": "P2",
		"variant": 0,
	})


## 全局网格铺满：每格一栋楼，全部对齐在 GRID 上。
## 跳过：墙外 / 道路上 / 河上 / 地标占位 / 门口。这就是"规整且占满空隙"的做法。
func _fill_grid() -> void:
	var gx := int(ceil(arena_size.x / GRID.x))
	var gy := int(ceil(arena_size.y / GRID.y))
	var idx := 0
	var rej := {"wall": 0, "road": 0, "river": 0, "none": 0, "built": 0, "gate": 0, "total": 0}
	for j in gy:
		for i in gx:
			rej["total"] = int(rej["total"]) + 1
			var c := Vector2((float(i) + 0.5) * GRID.x, (float(j) + 0.5) * GRID.y)
			if not _inside_wall(c, 80.0):
				rej["wall"] = int(rej["wall"]) + 1
				continue
			if _on_road(c):
				rej["road"] = int(rej["road"]) + 1
				continue
			if _dist_to_river(c) < river_w * 0.5 + 76.0:
				rej["river"] = int(rej["river"]) + 1
				continue
			var blk := _block_of_point(c)
			var style := String(_block_styles.get(blk, "house"))
			if style == "none" or style == "forest":
				rej["none"] = int(rej["none"]) + 1
				continue
			## 核心规则：建筑必须临街。不在道路两侧的格子一律留空（后院 / 绿地），
			## 这样建筑自然排成"沿街两排"，不会膏状连片浮在草地上
			if not _street_front(c):
				rej["offstreet"] = int(rej.get("offstreet", 0)) + 1
				continue
			## 沿街也隔四空一，留出巷子和间隙
			if (i * 5 + j * 3) % 4 == 0:
				rej["gap"] = int(rej.get("gap", 0)) + 1
				continue
			var size := _size_for(style)
			var rect := _snap_rect(Rect2(c.x - size.x * 0.5, c.y - size.y * 0.5, size.x, size.y))
			if _rect_hits_building(rect):
				rej["built"] = int(rej["built"]) + 1
				continue
			if _rect_near_gate(rect):
				rej["gate"] = int(rej["gate"]) + 1
				continue
			buildings.append({
				"id": "grid_%d_%d" % [i, j],
				"name": "",
				"rect": rect,
				"style": style,
				"solid": true,
				"priority": "P2",
				"variant": (i * 2 + j * 3) % 4,
			})
			idx += 1


## 不同用途的建筑尺寸略有差异，避免整村一个样
func _size_for(style: String) -> Vector2:
	match style:
		"shop":
			return Vector2(244.0, 214.0)
		"office":
			return Vector2(272.0, 238.0)
		"apartment":
			return Vector2(272.0, 238.0)
	return HOUSE_SIZE


## 点是否"压在道路上"（环路、放射主路或中心广场，含建筑半个身位的安全距离）
func _on_road(p: Vector2) -> bool:
	var d := _norm_radius(p)
	## 中心广场
	if d < 0.075:
		return true
	## 环路：归一化 0.050 ≈ 路面半宽 30px + 建筑半身位 135px
	for i in range(1, rings.size() - 1):
		if absf(d - float(rings[i])) < 0.050:
			return true
	## 放射主路：到路的垂直距离 = |m| * d（弧度 × 半径），按同样的 165px 判
	var step := TAU / float(sectors)
	var m := fmod(_ang_rad(p) + step * 0.5, step) - step * 0.5
	return absf(m) * maxf(d, 0.15) < 0.055


## 点是否"临街"：贴着道路两侧约一栋楼深的范围内。
## 这是"建筑沿街排布"的核心：只有临街格子允许放建筑
func _street_front(p: Vector2) -> bool:
	var d := _norm_radius(p)
	## 广场外圈临街
	if d >= 0.075 and d < 0.15:
		return true
	## 环路两侧
	for i in range(1, rings.size() - 1):
		var dist := absf(d - float(rings[i]))
		if dist >= 0.050 and dist < 0.108:
			return true
	## 放射主路两侧
	var step := TAU / float(sectors)
	var m := fmod(_ang_rad(p) + step * 0.5, step) - step * 0.5
	var dist_r := absf(m) * maxf(d, 0.15)
	return dist_r >= 0.055 and dist_r < 0.115


## 点落在哪个街区（扇区, 环带）
func _block_of_point(p: Vector2) -> Vector2i:
	var step := TAU / float(sectors)
	var sec := int(floor((_ang_rad(p) + step * 0.5) / step))
	sec = ((sec % sectors) + sectors) % sectors
	var d := _norm_radius(p)
	var band := 0
	for i in range(1, rings.size() - 1):
		if d >= float(rings[i]):
			band = i
	return Vector2i(sec, band)


func _rect_in_block(r: Rect2, sec: int, band: int) -> bool:
	var sp := _sector_span(sec)
	var mid := (float(sp[0]) + float(sp[1])) * 0.5
	var half := deg_to_rad(360.0 / float(sectors) * 0.5) - 0.02
	var r0 := float(rings[band]) + 0.014
	var r1 := float(rings[band + 1]) - 0.014
	for p in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, r.get_center()]:
		if not _inside_wall(p, 40.0):
			return false
		var d := _norm_radius(p)
		if d < r0 or d > r1:
			return false
		if absf(_ang_diff(_ang_rad(p), mid)) > half:
			return false
	return true


func _rect_hits_building(r: Rect2) -> bool:
	for b in buildings:
		if (b["rect"] as Rect2).grow(12.0).intersects(r):
			return true
	return false


func _rect_hits_river(r: Rect2) -> bool:
	var m := river_w * 0.5 + 16.0
	for p in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, r.get_center()]:
		if _dist_to_river(p) < m:
			return true
	return false


func _rect_near_gate(r: Rect2) -> bool:
	for e in layout.get("gates", []):
		if _rect_of(e).grow(gate_clear).intersects(r):
			return true
	return false


## 归一化椭圆半径（0 = 圆心，1 = 围墙）
func _norm_radius(p: Vector2) -> float:
	var nx := (p.x - center.x) / maxf(wall.x, 1.0)
	var ny := (p.y - center.y) / maxf(wall.y, 1.0)
	return sqrt(nx * nx + ny * ny)


## 以正北为 0、顺时针的方位角（弧度）
func _ang_rad(p: Vector2) -> float:
	return atan2(p.x - center.x, -(p.y - center.y))


func _ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI


func _sort_buildings() -> void:
	## 按 y 排序，让"靠下的建筑盖住靠上的"，俯视视角才有前后关系
	buildings.sort_custom(func(a, b): return (a["rect"] as Rect2).end.y < (b["rect"] as Rect2).end.y)


func _building(id: String) -> Dictionary:
	for b in buildings:
		if String(b["id"]) == id:
			return b
	return {}


func _front_of(id: String, gap: float) -> Vector2:
	var b := _building(id)
	if b.is_empty():
		return center
	var r: Rect2 = b["rect"]
	return Vector2(r.get_center().x, r.end.y + gap)


## 在填充区里按抖动网格摆民居，避开建筑 / 道路 / 河 / 墙
func _fill_area(area: Dictionary) -> void:
	var r: Array = area.get("rect", [0, 0, 0, 0])
	var box := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var count := int(area.get("count", 4))
	var style := String(area.get("style", "house"))
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	var cols := maxi(int(box.size.x / 130.0), 1)
	var rows := maxi(int(box.size.y / 120.0), 1)
	var placed := 0
	for ry in rows:
		for rx in cols:
			if placed >= count:
				break
			var w := _rng.randf_range(78.0, 112.0)
			var h := _rng.randf_range(66.0, 96.0)
			var px := box.position.x + (float(rx) + 0.5) * box.size.x / float(cols) + _rng.randf_range(-18.0, 18.0)
			var py := box.position.y + (float(ry) + 0.5) * box.size.y / float(rows) + _rng.randf_range(-16.0, 16.0)
			var rect := Rect2(px - w * 0.5, py - h * 0.5, w, h)
			if not _spot_free(rect):
				continue
			buildings.append({
				"id": "filler_" + str(placed) + "_" + str(int(px)),
				"name": "",
				"rect": rect,
				"style": style,
				"solid": true,
				"priority": "P2",
			})
			placed += 1


func _spot_free(rect: Rect2) -> bool:
	## 必须在墙内
	var corners := [
		rect.position, Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y), rect.end,
	]
	for c in corners:
		if not _inside_wall(c, 60.0):
			return false
	## 不压已有建筑
	for b in buildings:
		if (b["rect"] as Rect2).grow(14.0).intersects(rect):
			return false
	## 不压河
	if _dist_to_river(rect.get_center()) < river_w * 0.5 + rect.size.length() * 0.5 + 26.0:
		return false
	## 不压主路
	if _near_road(rect.get_center()):
		return false
	return true


func _inside_wall(p: Vector2, margin := 0.0) -> bool:
	var rx := maxf(wall.x - margin, 1.0)
	var ry := maxf(wall.y - margin, 1.0)
	var nx := (p.x - center.x) / rx
	var ny := (p.y - center.y) / ry
	return nx * nx + ny * ny <= 1.0


## 三个环路的半径（椭圆归一化），加道路附近的判定
const RING_RADII := [0.34, 0.60, 0.85]

func _near_road(p: Vector2) -> bool:
	var nx := (p.x - center.x) / wall.x
	var ny := (p.y - center.y) / wall.y
	var d := sqrt(nx * nx + ny * ny)
	for rr in RING_RADII:
		if absf(d - float(rr)) < 0.055:
			return true
	## 八条放射主路
	var ang := rad_to_deg(atan2(p.x - center.x, -(p.y - center.y)))
	if ang < 0.0:
		ang += 360.0
	var step := fmod(ang, 45.0)
	if step < 5.0 or step > 40.0:
		return true
	return false


func _dist_to_river(p: Vector2) -> float:
	var best := 99999.0
	for i in range(river_pts.size() - 1):
		var d := _dist_to_segment(p, river_pts[i], river_pts[i + 1])
		best = minf(best, d)
	return best


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- 物理边界

func _make_container(n: String) -> Node2D:
	var c := Node2D.new()
	c.name = n
	add_child(c)
	return c


## 围墙壁：沿椭圆撒一圈薄长方体，玩家走不出去（门只是交互点，不开口）
func _build_wall() -> void:
	for i in WALL_SEGMENTS:
		var a0 := TAU * float(i) / float(WALL_SEGMENTS)
		var a1 := TAU * float(i + 1) / float(WALL_SEGMENTS)
		var p0 := center + Vector2(sin(a0) * wall.x, -cos(a0) * wall.y)
		var p1 := center + Vector2(sin(a1) * wall.x, -cos(a1) * wall.y)
		_add_static_segment(p0, p1, 26.0)
	## 画布四边兜底，防止极端情况下穿出去
	var t := 60.0
	for r in [
		Rect2(-t, -t, arena_size.x + 2.0 * t, t),
		Rect2(-t, arena_size.y, arena_size.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, arena_size.y),
		Rect2(arena_size.x, 0.0, t, arena_size.y),
	]:
		_add_static_rect(r)


func _add_static_rect(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = r.get_center()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _add_static_segment(p0: Vector2, p1: Vector2, thickness: float) -> void:
	var body := StaticBody2D.new()
	body.position = (p0 + p1) * 0.5
	body.rotation = (p1 - p0).angle()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2((p1 - p0).length() + thickness, thickness)
	col.shape = shape
	body.add_child(col)
	add_child(body)


# ---------------------------------------------------------------- 玩家 / UI

func _spawn_player() -> void:
	player = Player.new()
	player.game = self
	## 出生在公园A（村子正中），面朝火影大楼
	player.position = Vector2(center.x, center.y - 40.0)
	add_child(player)
	Flow.apply_to_player(player)


func _spawn_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	hud = VillageHud.new()
	hud.game = self
	hud.player = player
	hud_layer.add_child(hud)
	board_ui = MissionBoardUi.new()
	board_ui.game = self
	board_ui.visible = false
	board_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(board_ui)
	loadout_ui = LoadoutUi.new()
	loadout_ui.game = self
	loadout_ui.player = player
	loadout_ui.visible = false
	loadout_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(loadout_ui)
	shop_ui = ShopUi.new()
	shop_ui.game = self
	shop_ui.visible = false
	shop_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(shop_ui)


# ---------------------------------------------------------------- 任务接取

func accept_mission_from_board(id: String) -> void:
	Flow.accept_mission(id)
	close_board()
	hud.show_notice(Data.s("village.go_gate"))


# ---------------------------------------------------------------- 交互

func _nearest_interactable() -> Dictionary:
	var spots := [
		{"pos": BOARD_POS, "kind": "board", "hint": Data.s("building.mission_desk") + " · " + Data.s("village.open")},
		{"pos": TORII_POS, "kind": "torii", "hint": Data.s("building.training_a") + " · " + Data.s("village.enter")},
		{"pos": SHRINE_POS, "kind": "shrine", "hint": Data.s("building.apartment") + " · " + Data.s("village.rest")},
		{"pos": SHOP_POS, "kind": "shop", "hint": Data.s("village.shop") + " · " + Data.s("village.open_shop")},
	]
	if Flow.pending_mission != "":
		spots.append({"pos": GATE_POS, "kind": "depart", "hint": Data.s("village.depart")})
	var best := {}
	var best_d := INTERACT_RADIUS
	for s in spots:
		var d: float = player.global_position.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best


func current_interact_hint() -> String:
	if player == null:
		return ""
	return String(_nearest_interactable().get("hint", ""))


func on_interact() -> void:
	if player == null or player.dead:
		return
	var spot := _nearest_interactable()
	if spot.is_empty():
		return
	match String(spot["kind"]):
		"board":
			toggle_board()
		"torii":
			Flow.sync_from_player(player)
			Flow.start_training()
		"shrine":
			Flow.sync_from_player(player)
			Flow.save_game()
			hud.show_notice(Data.s("village.saved"))
		"shop":
			toggle_shop()
		"depart":
			Flow.sync_from_player(player)
			Flow.depart_mission()


# ---------------------------------------------------------------- 忍具店

func toggle_shop() -> void:
	if shop_ui.visible:
		close_shop()
		return
	if loadout_open:
		close_loadout()
	if board_open():
		close_board()
	shop_ui.visible = true
	shop_ui.on_opened()
	get_tree().paused = true


func close_shop() -> void:
	shop_ui.visible = false
	get_tree().paused = false


func shop_open() -> bool:
	return shop_ui != null and shop_ui.visible


func buy_item(id: String, qty := 1) -> void:
	## 先把玩家当前的装配同步给 Flow，否则买完之后会被 Flow 里的旧武器槽覆盖
	if player != null:
		Flow.sync_from_player(player)
	var res := Flow.buy_item(id, qty)
	if bool(res.get("ok", false)):
		_mirror_weapons_from_flow()
		if String(res.get("reason", "")) == "partial":
			shop_ui.show_hint(Data.s("shop.partial") % [int(res.get("bought", 0)), String(res.get("name", ""))])
		else:
			shop_ui.show_hint(Data.s("shop.bought") % [String(res.get("name", "")), int(res.get("bought", 0))])
	elif String(res.get("reason", "")) == "no_money":
		shop_ui.show_hint(Data.s("shop.no_money") % int(res.get("shortfall", 0)))
	else:
		shop_ui.show_hint(Data.s("shop.no_space") % Flow.INV_SLOTS)
	shop_ui.queue_redraw()


func _mirror_weapons_from_flow() -> void:
	if player == null:
		return
	player._ensure_weapon_slots()
	for i in range(Player.WEAPON_SLOT_COUNT):
		player.weapon_sids[i] = Flow.sid_of_slot(i)
	player.sync_active_weapon()


# ---------------------------------------------------------------- 看板 / 装配

func toggle_board() -> void:
	if board_ui.visible:
		close_board()
		return
	if loadout_open:
		close_loadout()
	if shop_open():
		close_shop()
	board_ui.visible = true
	get_tree().paused = true
	board_ui.on_opened()


func close_board() -> void:
	board_ui.visible = false
	get_tree().paused = false


func board_open() -> bool:
	return board_ui != null and board_ui.visible


func toggle_loadout() -> void:
	if player != null and player.dead:
		return
	if board_open():
		close_board()
	if shop_open():
		close_shop()
	loadout_open = not loadout_open
	loadout_ui.visible = loadout_open
	get_tree().paused = loadout_open
	if loadout_open:
		loadout_ui.on_opened()


func close_loadout() -> void:
	if not loadout_open:
		return
	loadout_open = false
	loadout_ui.visible = false
	get_tree().paused = false


# ---------------------------------------------------------------- 玩家依赖的通用接口

func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func hitstop(duration: float, time_scale := 0.05) -> void:
	if _hs_active or duration <= 0.0:
		return
	_hs_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hs_active = false


func on_player_level_up(_level: int) -> void:
	if hud != null:
		hud.show_notice(Data.s("hud.level_up") % _level)


func on_player_died() -> void:
	## 村内不应死亡；兜底：回满血送回公园A
	if player != null:
		player.dead = false
		player.hp = player.max_hp
		player.state = Player.State.MOVE
		player.global_position = Vector2(center.x, center.y - 40.0)


func on_enemy_died(_enemy: Node) -> void:
	pass


func on_intel_collected() -> void:
	pass


## 把坐标限制在围墙内（留 margin 给玩家体型）
func clamp_to_arena(pos: Vector2, margin := 24.0) -> Vector2:
	var out := Vector2(
		clampf(pos.x, margin, arena_size.x - margin),
		clampf(pos.y, margin, arena_size.y - margin)
	)
	if _inside_wall(out, margin * 0.5):
		return out
	## 超出墙就往圆心拉回来
	var dir := (out - center).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	for i in 60:
		out = out.move_toward(center, 24.0)
		if _inside_wall(out, margin * 0.5):
			break
	return out


func pos_blocked(pos: Vector2) -> bool:
	if not _inside_wall(pos, 18.0):
		return true
	for b in buildings:
		if bool(b["solid"]) and (b["rect"] as Rect2).grow(6.0).has_point(pos):
			return true
	for wr in wall_rects():
		if wr.grow(4.0).has_point(pos):
			return true
	return false


func resolve_static(pos: Vector2) -> Vector2:
	for b in buildings:
		if not bool(b["solid"]):
			continue
		var r: Rect2 = b["rect"]
		if r.grow(4.0).has_point(pos):
			pos = _push_out_of_rect(pos, r)
	return clamp_to_arena(pos, 26.0)


func resolve_point(pos: Vector2, margin: float) -> Vector2:
	return clamp_to_arena(resolve_static(pos), margin)


func _push_out_of_rect(pos: Vector2, r: Rect2) -> Vector2:
	var d := [
		absf(pos.x - r.position.x),
		absf(pos.x - r.end.x),
		absf(pos.y - r.position.y),
		absf(pos.y - r.end.y),
	]
	var m: float = d[0]
	for v in d:
		m = minf(m, v)
	if m == d[0]:
		pos.x = r.position.x - 5.0
	elif m == d[1]:
		pos.x = r.end.x + 5.0
	elif m == d[2]:
		pos.y = r.position.y - 5.0
	else:
		pos.y = r.end.y + 5.0
	return pos


func register_wall(w: EarthWall) -> void:
	if not walls.has(w):
		walls.append(w)


func unregister_wall(w: EarthWall) -> void:
	walls.erase(w)


func wall_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w in walls:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			out.append(Rect2(w.global_position + w.box.position, w.box.size))
	return out


# ---------------------------------------------------------------- 装饰预生成

var _trees: Array = []
var _grass: Array = []


## 树与草的随机分布只算一次（_draw 每帧都跑，不能每帧随机）
func _build_decor() -> void:
	_trees.clear()
	_grass.clear()
	_rng.seed = 424242
	var tries := 0
	while _grass.size() < 900 and tries < 9000:
		tries += 1
		var p := _random_in_village()
		if _decor_free(p, 14.0):
			_grass.append(p)
	tries = 0
	while _trees.size() < 520 and tries < 12000:
		tries += 1
		var p2 := _random_in_village()
		if _decor_free(p2, 52.0):
			_trees.append({"pos": p2, "size": _rng.randf_range(22.0, 36.0)})
	## 中忍考试森林：整块加密（这一块不判道路，只看建筑；自身矩形要排除）
	for b in buildings:
		if String(b["style"]) != "forest":
			continue
		var r: Rect2 = b["rect"]
		for i in 170:
			var p3 := Vector2(
				_rng.randf_range(r.position.x, r.end.x),
				_rng.randf_range(r.position.y, r.end.y)
			)
			var blocked := false
			for ob in buildings:
				if String(ob["style"]) == "forest":
					continue
				if (ob["rect"] as Rect2).grow(26.0).has_point(p3):
					blocked = true
					break
			if not blocked:
				_trees.append({"pos": p3, "size": _rng.randf_range(26.0, 44.0)})


func _random_in_village() -> Vector2:
	## 在墙内均匀撒点（用拒绝采样，简单可靠）
	for i in 24:
		var p := Vector2(
			_rng.randf_range(center.x - wall.x, center.x + wall.x),
			_rng.randf_range(center.y - wall.y, center.y + wall.y)
		)
		if _inside_wall(p, 70.0):
			return p
	return center


func _decor_free(p: Vector2, clearance: float) -> bool:
	if _dist_to_river(p) < river_w * 0.5 + 20.0:
		return false
	for b in buildings:
		if (b["rect"] as Rect2).grow(clearance).has_point(p):
			return false
	var nx := (p.x - center.x) / wall.x
	var ny := (p.y - center.y) / wall.y
	var d := sqrt(nx * nx + ny * ny)
	for i in range(1, rings.size() - 1):
		if absf(d - float(rings[i])) < 0.055:
			return false
	var ang := rad_to_deg(atan2(p.x - center.x, -(p.y - center.y)))
	if ang < 0.0:
		ang += 360.0
	var step := fmod(ang, 45.0)
	if step < 5.5 or step > 39.5:
		return false
	return true


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_ground()
	_draw_district_tints()
	_draw_roads()
	_draw_river()
	_draw_wall()
	_draw_mountain()
	for b in buildings:
		_draw_building(b)
	## 树最后画：装饰生成时已避开建筑，画在上层森林才不会被森林底色盖住
	_draw_nature()
	_draw_bridges()
	_draw_gates()
	_draw_interact_markers()


func _draw_ground() -> void:
	## 村外森林底 + 墙内草底
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color("22331f"))
	for i in 26:
		var a := TAU * float(i) / 26.0
		var p := center + Vector2(sin(a) * wall.x * 1.16, -cos(a) * wall.y * 1.16)
		draw_circle(p, 150.0, Color("2b4026"))
	_build_ellipse_fill(Color("3d5c3a"), 1.0)
	## 草点
	for p in _grass:
		draw_circle(p, 3.0, Color(0.25, 0.42, 0.23, 0.55))


func _build_ellipse_fill(col: Color, scale: float) -> void:
	var pts := PackedVector2Array()
	for i in 96:
		var a := TAU * float(i) / 96.0
		pts.append(center + Vector2(sin(a) * wall.x * scale, -cos(a) * wall.y * scale))
	draw_colored_polygon(pts, col)


func _draw_district_tints() -> void:
	for d in district_labels:
		var col: Color = d["color"]
		col.a = 0.13
		draw_circle(d["pos"], 380.0, col)
		## 分区名（半透明大字，只在拉远时看得清，不挡建筑）
		draw_string(Data.font(), Vector2(d["pos"].x - 190.0, d["pos"].y - 150.0), String(d["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, 380.0, 34, Color(1.0, 1.0, 1.0, 0.18))


func _draw_roads() -> void:
	var road := Color("8a7a5c")
	var edge := Color("6d6047")
	## 环路：58px 街道
	for idx in range(1, rings.size() - 1):
		var rr := float(rings[idx])
		var prev := _ellipse_point(0.0, rr)
		for i in range(1, 97):
			var cur := _ellipse_point(TAU * float(i) / 96.0, rr)
			draw_line(prev, cur, edge, 72.0)
			draw_line(prev, cur, road, 58.0)
			prev = cur
	## 八条放射路；南北主路（火影大道）加宽到 72px，其余 58px
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p0 := center
		var p1 := _ellipse_point(a, 1.0)
		var main := i == 0 or i == 4
		draw_line(p0, p1, edge, 88.0 if main else 72.0)
		draw_line(p0, p1, road, 72.0 if main else 58.0)
	## 中心环岛广场
	draw_circle(center, 170.0, edge)
	draw_circle(center, 158.0, Color("9a8a6a"))


func _ellipse_point(a: float, rr: float) -> Vector2:
	return center + Vector2(sin(a) * wall.x * rr, -cos(a) * wall.y * rr)


func _draw_river() -> void:
	if river_pts.size() < 2:
		return
	for i in range(river_pts.size() - 1):
		draw_line(river_pts[i], river_pts[i + 1], Color("5a6a72"), river_w + 16.0)
	for i in range(river_pts.size() - 1):
		draw_line(river_pts[i], river_pts[i + 1], Color("3f7fa8"), river_w)
	for i in range(river_pts.size() - 1):
		draw_line(river_pts[i], river_pts[i + 1], Color("6fb2d6"), river_w * 0.45)


func _draw_bridges() -> void:
	for b in bridges:
		var r: Rect2 = b["rect"]
		draw_set_transform(r.get_center(), deg_to_rad(float(b["angle"])), Vector2.ONE)
		draw_rect(Rect2(-r.size.x * 0.5, -r.size.y * 0.5, r.size.x, r.size.y), Color("6a4f30"))
		draw_rect(Rect2(-r.size.x * 0.5, -r.size.y * 0.5, r.size.x, r.size.y), Color("8a6a42"), false, 3.0)
		for i in 5:
			var x: float = -r.size.x * 0.5 + float(i) * r.size.x / 4.0
			draw_line(Vector2(x, -r.size.y * 0.5), Vector2(x, r.size.y * 0.5), Color("5a4230"), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wall() -> void:
	var prev := _ellipse_point(0.0, 1.0)
	for i in range(1, 97):
		var cur := _ellipse_point(TAU * float(i) / 96.0, 1.0)
		draw_line(prev, cur, Color("3a3229"), 24.0)
		draw_line(prev, cur, Color("6e6252"), 14.0)
		prev = cur
	## 垛口
	for i in 72:
		var a := TAU * float(i) / 72.0
		var p := _ellipse_point(a, 1.0)
		var n := (p - center).normalized()
		draw_line(p, p + n * 14.0, Color("574c3e"), 10.0)


func _draw_nature() -> void:
	for t in _trees:
		_draw_tree(t["pos"], float(t["size"]))


func _draw_tree(c: Vector2, s: float) -> void:
	draw_rect(Rect2(c + Vector2(-3.0, 0.0), Vector2(6.0, s * 0.55)), Color("5a4230"))
	draw_circle(c + Vector2(0.0, -s * 0.9), s, Color("2f5230"))
	draw_circle(c + Vector2(-s * 0.4, -s * 1.3), s * 0.6, Color("3d6638"))


## 火影岩：北面崖壁上凿出的四张脸
func _draw_mountain() -> void:
	var b := _building("hokage_rock")
	var r: Rect2 = (b.get("rect", Rect2(2520, 250, 2160, 420)) as Rect2)
	## 崖壁：几团深浅不一的岩体堆出起伏（按矩形比例摆位，地图多大都不走样）
	for fx in [0.06, 0.22, 0.42, 0.62, 0.80, 0.94]:
		for fy in [0.35, 0.75]:
			draw_circle(r.position + Vector2(r.size.x * fx, r.size.y * fy),
				r.size.y * 0.34, Color("615949"))
	for fx2 in [0.14, 0.50, 0.86]:
		draw_circle(r.position + Vector2(r.size.x * fx2, r.size.y * 0.42),
			r.size.y * 0.27, Color("7a7160"))
	## 四张脸：凿在岩壁上的浮雕
	for fx3 in [0.16, 0.38, 0.60, 0.82]:
		_draw_face(Vector2(r.position.x + r.size.x * fx3, r.position.y + r.size.y * 0.62), r.size.y)
	draw_rect(Rect2(r.position.x - 40.0, r.end.y - 30.0, r.size.x + 80.0, 30.0), Color("453f34"))


func _draw_face(c: Vector2, h: float) -> void:
	var s := h / 420.0
	draw_circle(c, 56.0 * s, Color("4a4438"))
	draw_circle(c, 49.0 * s, Color("b0a89a"))
	## 头发块
	draw_rect(Rect2(c + Vector2(-45.0 * s, -56.0 * s), Vector2(90.0 * s, 18.0 * s)), Color("6a6154"))
	## 眼、鼻、嘴
	draw_rect(Rect2(c + Vector2(-21.0 * s, -11.0 * s), Vector2(14.0 * s, 8.0 * s)), Color("3a3630"))
	draw_rect(Rect2(c + Vector2(7.0 * s, -11.0 * s), Vector2(14.0 * s, 8.0 * s)), Color("3a3630"))
	draw_rect(Rect2(c + Vector2(-3.0 * s, 3.0 * s), Vector2(6.0 * s, 14.0 * s)), Color("8a8272"))
	draw_line(c + Vector2(-15.0 * s, 25.0 * s), c + Vector2(15.0 * s, 25.0 * s), Color("3a3630"), 3.0 * s)


func _draw_gates() -> void:
	for g in gate_list:
		var r: Rect2 = g["rect"]
		_draw_torii_gate(r.get_center(), String(g["direction"]))
	## 待出发时大门发光
	if Flow.pending_mission != "":
		draw_arc(GATE_POS + Vector2(0.0, -40.0), 130.0, 0.0, TAU, 36,
			Color(1.0, 0.9, 0.5, 0.32 + 0.18 * sin(Time.get_ticks_msec() * 0.005)), 4.0)


func _draw_torii_gate(c: Vector2, direction: String) -> void:
	var horizontal := direction != "E" and direction != "W"
	## 门柱（随地图放大 1.6 倍）
	if horizontal:
		draw_rect(Rect2(c + Vector2(-84.0, -118.0), Vector2(28.0, 118.0)), Color("6a5238"))
		draw_rect(Rect2(c + Vector2(56.0, -118.0), Vector2(28.0, 118.0)), Color("6a5238"))
		draw_rect(Rect2(c + Vector2(-112.0, -154.0), Vector2(224.0, 32.0)), Color("8a6a42"))
		draw_rect(Rect2(c + Vector2(-128.0, -182.0), Vector2(256.0, 26.0)), Color("5a4230"))
		draw_rect(Rect2(c + Vector2(-42.0, -83.0), Vector2(84.0, 84.0)), Color(0.0, 0.0, 0.0, 0.25))
	else:
		draw_rect(Rect2(c + Vector2(-118.0, -84.0), Vector2(118.0, 28.0)), Color("6a5238"))
		draw_rect(Rect2(c + Vector2(-118.0, 56.0), Vector2(118.0, 28.0)), Color("6a5238"))
		draw_rect(Rect2(c + Vector2(-154.0, -112.0), Vector2(32.0, 224.0)), Color("8a6a42"))


func _draw_interact_markers() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	for p in [BOARD_POS, SHOP_POS, SHRINE_POS, TORII_POS]:
		if player != null and player.global_position.distance_to(p) < 380.0:
			draw_arc(p + Vector2(0.0, -18.0), 56.0, 0.0, TAU, 26,
				Color(1.0, 0.9, 0.5, 0.18 + 0.22 * pulse), 3.0)


## 建筑外观全部委托给 VillageArt（独立静态绘制模块）。
## 将来换成真正的插画时，只改 village_art.gd 一个文件。
func _draw_building(b: Dictionary) -> void:
	VillageArt.draw_building(self, String(b["style"]), b["rect"] as Rect2, String(b["name"]), int(b.get("variant", 0)))
