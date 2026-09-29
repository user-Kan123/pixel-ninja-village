class_name VillageArt
extends RefCounted
## 村庄建筑绘制：优先使用 AI 生成的星露谷风贴图（assets/buildings/*.png），
## 没有贴图的样式（公园 / 训练场 / 森林 / 墓地等）回退到程序化像素绘制。
##
## 换图规则：把新 PNG 放进 assets/buildings/ 并命名为对应 style 名即可，
## 代码不用改；删除某张 PNG 则该样式自动回退程序化绘制。


## 贴图缓存：style -> Texture2D（找不到的记 null，避免反复查盘）
static var _tex_cache: Dictionary = {}
## 当前绘制的建筑"变体号"：用来做细微色调变化，一排建筑不会一模一样
static var _variant := 0


## style -> 候选贴图名列表（按变体号轮换，一排建筑不会全是一个模子）
## 没列出的样式没有贴图，走程序化绘制
const TEXTURE_MAP := {
	"hokage": ["hokage_office"],
	"office": ["office"],
	"residence": ["house2", "house3"],
	"vault": ["vault"],
	"hospital": ["hospital"],
	"school": ["school"],
	"tower": ["tower"],
	"shop": ["shop", "shop2"],
	"ramen": ["ramen"],
	"tools": ["tools"],
	"bath": ["bath"],
	"theater": ["theater"],
	"apartment": ["apartment"],
	"clan": ["clan"],
	"house": ["house", "house2", "house3"],
	"house_block": ["house2", "house"],
	"watch": ["watch"],
}


static func _tex(style: String, variant: int) -> Texture2D:
	if not TEXTURE_MAP.has(style):
		return null
	var names: Array = TEXTURE_MAP[style]
	var tex_name := String(names[variant % names.size()])
	if not _tex_cache.has(tex_name):
		var path := "res://assets/buildings/%s.png" % tex_name
		_tex_cache[tex_name] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[tex_name]


static func draw_building(c: CanvasItem, style: String, r: Rect2, label: String, variant := 0) -> void:
	_variant = variant
	var t := _tex(style, variant)
	if t != null:
		_draw_textured(c, t, r)
	else:
		_draw_procedural(c, style, r)
	if not label.is_empty():
		draw_sign(c, r, label)


## 贴图绘制：底边对齐建筑格底边，宽度撑满格宽，等比缩放，变体微调色
static func _draw_textured(c: CanvasItem, t: Texture2D, r: Rect2) -> void:
	var w := r.size.x * 1.04
	var h := w * t.get_height() / t.get_width()
	var mod := Color(1.0, 1.0, 1.0)
	match _variant % 4:
		2:
			mod = Color(0.93, 0.93, 0.97)
		3:
			mod = Color(1.0, 0.95, 0.88)
	c.draw_texture_rect(t, Rect2(r.get_center().x - w * 0.5, r.end.y - h, w, h), false, mod)


## 程序化兜底绘制（原实现）
static func _draw_procedural(c: CanvasItem, style: String, r: Rect2) -> void:
	match style:
		"hokage": _b_hokage(c, r)
		"hokage_rock": pass
		"office": _b_office(c, r)
		"residence": _b_house(c, r, Color("b8a888"), Color("6a5a48"))
		"vault": _b_vault(c, r)
		"hospital": _b_hospital(c, r)
		"park": _b_park(c, r)
		"school": _b_school(c, r)
		"training": _b_training(c, r)
		"tower": _b_tower(c, r)
		"shop": _b_shop(c, r, Color("a88a5a"), Color("5e4630"))
		"ramen": _b_ramen(c, r)
		"tools": _b_tools(c, r)
		"bath": _b_bath(c, r)
		"theater": _b_theater(c, r)
		"apartment": _b_apartment(c, r)
		"clan": _b_clan(c, r)
		"house_block": _b_house_block(c, r)
		"cemetery": _b_cemetery(c, r)
		"stone": _b_stone(c, r)
		"watch": _b_watch(c, r)
		"forest": _b_forest(c, r)
		"wharf": _b_wharf(c, r)
		"tent": _b_tent(c, r)
		_:
			_b_house(c, r, Color("c0b0a0"), Color("6a5a52"))


## 变体配色：0 = 原色，1 = 亮一档，2 = 暗一档，3 = 偏暖
static func _tint(base: Color) -> Color:
	match _variant % 4:
		1:
			return base.lightened(0.10)
		2:
			return base.darkened(0.10)
		3:
			return base.lerp(Color(0.88, 0.84, 0.78), 0.22)
	return base


## 通用房体：屋檐投影 + 屋顶 + 墙 + 门 + 两扇窗。返回正面墙的矩形。
static func _base(c: CanvasItem, r: Rect2, wall_col: Color, roof_col: Color, trim: Color) -> Rect2:
	wall_col = _tint(wall_col)
	roof_col = _tint(roof_col)
	c.draw_rect(r.grow(6.0), roof_col.darkened(0.45))
	var roof_h := r.size.y * 0.55
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, roof_h)), roof_col)
	for i in 3:
		var yy := r.position.y + roof_h * float(i + 1) / 4.0
		c.draw_line(Vector2(r.position.x + 4.0, yy), Vector2(r.end.x - 4.0, yy), roof_col.darkened(0.22), 1.5)
	var wall_r := Rect2(Vector2(r.position.x, r.position.y + roof_h), Vector2(r.size.x, r.size.y - roof_h))
	c.draw_rect(wall_r, wall_col)
	c.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), wall_col.darkened(0.4), 3.0)
	var door := Rect2(r.get_center().x - 13.0, r.end.y - 40.0, 26.0, 40.0)
	c.draw_rect(door, Color("3a2c20"))
	c.draw_rect(door, trim, false, 1.5)
	var wy := r.position.y + roof_h + 12.0
	for sx in [r.position.x + 20.0, r.end.x - 42.0]:
		var win := Rect2(sx, wy, 22.0, 22.0)
		c.draw_rect(win, Color("7fa8c8"))
		c.draw_rect(win, trim, false, 1.5)
	return wall_r


## 建筑名招牌（画在屋顶上方）
static func draw_sign(c: CanvasItem, r: Rect2, text: String) -> void:
	var w := float(text.length()) * 22.0 + 26.0
	var box := Rect2(r.get_center().x - w * 0.5, r.position.y - 40.0, w, 32.0)
	c.draw_rect(box, Color(0.07, 0.06, 0.05, 0.8))
	c.draw_rect(box, Color(0.85, 0.78, 0.55, 0.75), false, 1.5)
	c.draw_string(Data.font(), Vector2(box.position.x + 13.0, box.position.y + 23.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f0e6c8"))


static func _b_hokage(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("c0483a"), Color("7a2e26"), Color("e8d8b8"))
	## 顶层楼阁 + 金色火字徽 + 台阶
	c.draw_rect(Rect2(r.get_center().x - 72.0, r.position.y - 34.0, 144.0, 34.0), Color("c0483a"))
	c.draw_rect(Rect2(r.get_center().x - 72.0, r.position.y - 34.0, 144.0, 34.0), Color("e8d8b8"), false, 2.0)
	c.draw_circle(Vector2(r.get_center().x, r.position.y + 20.0), 15.0, Color("e8c84a"))
	c.draw_string(Data.font(), Vector2(r.get_center().x - 7.0, r.position.y + 27.0), "火",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("7a2e26"))
	c.draw_rect(Rect2(r.get_center().x - 46.0, r.end.y, 92.0, 12.0), Color("b8b0a0"))
	c.draw_rect(Rect2(r.get_center().x - 34.0, r.end.y + 12.0, 68.0, 10.0), Color("a8a090"))


static func _b_office(c: CanvasItem, r: Rect2) -> void:
	var wall_r := _base(c, r, Color("b8b0a0"), Color("5a5a62"), Color("e0dcd0"))
	var cols := maxi(int(wall_r.size.x / 42.0), 1)
	for cx in cols:
		for ry in 2:
			var win := Rect2(
				wall_r.position.x + 14.0 + float(cx) * 42.0,
				wall_r.position.y + 10.0 + float(ry) * 26.0,
				22.0, 18.0
			)
			if win.end.x < wall_r.end.x - 8.0:
				c.draw_rect(win, Color("8fb4d0"))
				c.draw_rect(win, Color("e0dcd0"), false, 1.0)


static func _b_vault(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("5a5a60"), Color("33333a"), Color("9a9aa8"))
	## 封印符
	c.draw_rect(Rect2(r.get_center().x - 16.0, r.get_center().y - 4.0, 32.0, 44.0), Color("c8b48a"))
	c.draw_line(Vector2(r.get_center().x, r.get_center().y + 2.0),
		Vector2(r.get_center().x, r.get_center().y + 34.0), Color("8a3a3a"), 2.0)
	c.draw_circle(Vector2(r.get_center().x, r.end.y - 46.0), 7.0, Color("8a3a3a"))


static func _b_hospital(c: CanvasItem, r: Rect2) -> void:
	var wall_r := _base(c, r, Color("e4e8e4"), Color("7a8a90"), Color("f0f4f0"))
	var m := Vector2(wall_r.get_center().x, wall_r.position.y - 26.0)
	c.draw_rect(Rect2(m + Vector2(-5.0, -14.0), Vector2(10.0, 28.0)), Color("c8383a"))
	c.draw_rect(Rect2(m + Vector2(-14.0, -5.0), Vector2(28.0, 10.0)), Color("c8383a"))


static func _b_park(c: CanvasItem, r: Rect2) -> void:
	## 半径取短边，公园严格画在自己的矩形里，不会盖住上下邻居
	var rad := minf(r.size.x, r.size.y) * 0.5
	c.draw_circle(r.get_center(), rad, Color("3f6b3c"))
	c.draw_circle(r.get_center(), rad - 8.0, Color("4a7a45"))
	c.draw_circle(r.get_center() + Vector2(0.0, 26.0), minf(46.0, rad * 0.4), Color("3f7fa8"))
	c.draw_circle(r.get_center() + Vector2(0.0, 26.0), minf(34.0, rad * 0.3), Color("6fb2d6"))
	var ts := rad * 0.18
	for d in [Vector2(-0.42, -0.42), Vector2(0.42, -0.42), Vector2(-0.48, 0.36), Vector2(0.48, 0.36)]:
		_tree(c, r.get_center() + Vector2(d.x * r.size.x, d.y * r.size.y), ts)
	c.draw_rect(Rect2(r.get_center().x - 30.0, r.get_center().y - rad + 8.0, 60.0, 8.0), Color("7a5a3c"))


static func _tree(c: CanvasItem, pos: Vector2, s: float) -> void:
	c.draw_rect(Rect2(pos + Vector2(-3.0, 0.0), Vector2(6.0, s * 0.55)), Color("5a4230"))
	c.draw_circle(pos + Vector2(0.0, -s * 0.9), s, Color("2f5230"))
	c.draw_circle(pos + Vector2(-s * 0.4, -s * 1.3), s * 0.6, Color("3d6638"))


static func _b_school(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("d8c9a8"), Color("6a5a44"), Color("f0e6d0"))
	c.draw_line(Vector2(r.end.x - 34.0, r.position.y), Vector2(r.end.x - 34.0, r.position.y - 30.0), Color("e0d8c8"), 3.0)
	c.draw_rect(Rect2(r.end.x - 32.0, r.position.y - 30.0, 22.0, 14.0), Color("c8483a"))
	c.draw_circle(Vector2(r.get_center().x, r.end.y + 26.0), 34.0, Color("8a7a5c"))


static func _b_training(c: CanvasItem, r: Rect2) -> void:
	## 演习场：草地中间一块夯实的空地（不是一整块木板），四周留草，场上有木桩与靶子
	var inner := r.grow(-34.0)
	c.draw_rect(inner, _tint(Color("8a7a58")))
	c.draw_rect(inner.grow(6.0), Color("6f5f42"), false, 3.0)
	for i in 8:
		var fx := inner.position.x + float(i) * inner.size.x / 7.0
		c.draw_line(Vector2(fx, inner.position.y - 8.0), Vector2(fx, inner.position.y), Color("5a4a32"), 3.0)
		c.draw_line(Vector2(fx, inner.end.y), Vector2(fx, inner.end.y + 8.0), Color("5a4a32"), 3.0)
	for i in 3:
		var p := Vector2(inner.position.x + 46.0 + float(i) * (inner.size.x - 92.0) / 2.0, inner.get_center().y + 8.0)
		c.draw_rect(Rect2(p + Vector2(-6.0, -34.0), Vector2(12.0, 44.0)), Color("6a4f30"))
		c.draw_circle(p + Vector2(0.0, -38.0), 9.0, Color("8a6a42"))
	var t := Vector2(inner.end.x - 46.0, inner.position.y + 46.0)
	c.draw_circle(t, 18.0, Color("d8d0c0"))
	c.draw_circle(t, 9.0, Color("c8483a"))


static func _b_tower(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("9a9a90"), Color("6a6a60"), Color("d0d0c8"))
	c.draw_rect(Rect2(r.position.x + 14.0, r.position.y - 30.0, r.size.x - 28.0, 30.0), Color("8a8a80"))
	c.draw_rect(Rect2(r.position.x + 14.0, r.position.y - 30.0, r.size.x - 28.0, 30.0), Color("d0d0c8"), false, 2.0)


static func _b_shop(c: CanvasItem, r: Rect2, wall_col: Color, roof_col: Color) -> void:
	_base(c, r, wall_col, roof_col, Color("e8dcc0"))
	var n := maxi(int(r.size.x / 22.0), 2)
	for i in n:
		var cx := r.position.x + float(i) * r.size.x / float(n)
		var col := Color("c84438") if i % 2 == 0 else Color("e8dcc0")
		c.draw_rect(Rect2(cx, r.position.y + r.size.y * 0.55 - 8.0, r.size.x / float(n), 14.0), col)


static func _b_ramen(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("d8b088"), Color("8a5a38"), Color("e8dcc0"))
	for i in 5:
		var cx := r.position.x + 12.0 + float(i) * (r.size.x - 24.0) / 5.0
		c.draw_rect(Rect2(cx, r.get_center().y - 6.0, 20.0, 22.0), Color("c84438"))
	c.draw_circle(Vector2(r.end.x - 30.0, r.end.y - 20.0), 9.0, Color("e8c84a"))


static func _b_tools(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("a88a5a"), Color("5e4630"), Color("d8c8a0"))
	var p := Vector2(r.end.x - 34.0, r.position.y + 26.0)
	c.draw_colored_polygon(PackedVector2Array([
		p + Vector2(0.0, -16.0), p + Vector2(9.0, 8.0), p + Vector2(-9.0, 8.0),
	]), Color("c9ced6"))
	c.draw_line(p + Vector2(0.0, 8.0), p + Vector2(0.0, 20.0), Color("6a5a44"), 3.0)


static func _b_bath(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("b8c8d0"), Color("5a7a8c"), Color("e0e8ec"))
	c.draw_rect(Rect2(r.end.x - 40.0, r.position.y - 22.0, 16.0, 30.0), Color("e0e8ec"))
	for i in 3:
		c.draw_arc(Vector2(r.end.x - 32.0, r.position.y - 32.0 - float(i) * 12.0), 8.0 + float(i) * 3.0,
			0.0, PI, 10, Color(0.85, 0.92, 0.95, 0.5), 2.0)


static func _b_theater(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("8a6a7a"), Color("4a3a4a"), Color("d8c8d0"))
	c.draw_rect(Rect2(r.position.x + 20.0, r.get_center().y - 10.0, r.size.x - 40.0, 20.0), Color("8a2e3a"))
	for i in 5:
		var cx := r.position.x + 24.0 + float(i) * (r.size.x - 48.0) / 5.0
		c.draw_line(Vector2(cx, r.get_center().y - 10.0), Vector2(cx, r.get_center().y + 10.0), Color("c04a55"), 2.0)


static func _b_apartment(c: CanvasItem, r: Rect2) -> void:
	var wall_r := _base(c, r, Color("c0b0a0"), Color("6a5a52"), Color("e0d8cc"))
	var cols := maxi(int(wall_r.size.x / 52.0), 1)
	for cx in cols:
		for ry in 2:
			var win := Rect2(
				wall_r.position.x + 16.0 + float(cx) * 52.0,
				wall_r.position.y + 8.0 + float(ry) * 30.0,
				26.0, 22.0
			)
			if win.end.x < wall_r.end.x - 10.0:
				c.draw_rect(win, Color("7fa8c8"))
				c.draw_rect(win, Color("e0d8cc"), false, 1.5)


static func _b_clan(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r.grow(10.0), Color("7a7a70"))
	c.draw_rect(r, Color("d8d8d0"))
	c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.45), Color("5a5a62"))
	c.draw_rect(Rect2(r.get_center().x - 30.0, r.end.y - 54.0, 60.0, 54.0), Color("3a2c20"))
	c.draw_rect(Rect2(r.get_center().x - 30.0, r.end.y - 54.0, 60.0, 54.0), Color("c8c8c0"), false, 2.0)
	c.draw_circle(Vector2(r.get_center().x, r.get_center().y), 22.0, Color("e8e8e0"))
	c.draw_circle(Vector2(r.get_center().x, r.get_center().y), 12.0, Color("b8c8d8"))


static func _b_house_block(c: CanvasItem, r: Rect2) -> void:
	var w := r.size.x / 3.0 - 8.0
	for i in 3:
		var sub := Rect2(r.position.x + float(i) * (w + 12.0), r.position.y, w, r.size.y)
		_b_house(c, sub, Color("c0b0a0"), Color("6a5a52"))


static func _b_house(c: CanvasItem, r: Rect2, wall_col: Color, roof_col: Color) -> void:
	var wall_r := _base(c, r, wall_col, roof_col, Color("e8e0d0"))
	c.draw_rect(Rect2(r.get_center().x - 18.0, r.end.y, 36.0, 7.0), Color("a8a090"))
	if wall_r.size.x > 120.0:
		c.draw_rect(Rect2(wall_r.position.x + 12.0, wall_r.position.y + 12.0, 18.0, 16.0), Color("8fb4d0"))


static func _b_cemetery(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color("5f6a52"))
	c.draw_rect(r, Color("6d7a5c"), false, 3.0)
	for i in 5:
		for j in 2:
			var p := Vector2(
				r.position.x + 30.0 + float(i) * (r.size.x - 60.0) / 4.0,
				r.position.y + 46.0 + float(j) * 74.0
			)
			c.draw_rect(Rect2(p + Vector2(-9.0, -28.0), Vector2(18.0, 30.0)), Color("b8b8b0"))
			c.draw_rect(Rect2(p + Vector2(-4.0, -20.0), Vector2(8.0, 4.0)), Color("8a8a82"))


static func _b_stone(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(Rect2(r.position.x + 6.0, r.get_center().y, r.size.x - 12.0, r.size.y * 0.5), Color("9a9a92"))
	c.draw_rect(Rect2(r.get_center().x - r.size.x * 0.32, r.position.y + 6.0, r.size.x * 0.64, r.size.y * 0.7), Color("b0b0a8"))
	c.draw_rect(Rect2(r.get_center().x - r.size.x * 0.32, r.position.y + 6.0, r.size.x * 0.64, r.size.y * 0.7), Color("6a6a62"), false, 2.0)


static func _b_watch(c: CanvasItem, r: Rect2) -> void:
	_base(c, r, Color("a89a78"), Color("5a4a38"), Color("d8c8a0"))
	c.draw_line(Vector2(r.get_center().x, r.position.y - 26.0), Vector2(r.get_center().x, r.position.y - 6.0), Color("8a8a80"), 2.0)
	c.draw_rect(Rect2(r.get_center().x, r.position.y - 26.0, 20.0, 12.0), Color("c8483a"))


static func _b_forest(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color("2c4526"))
	c.draw_rect(r, Color("22331f"), false, 6.0)
	## 四角结界柱
	for d in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		c.draw_rect(Rect2(d + Vector2(-7.0, -34.0), Vector2(14.0, 34.0)), Color("8a7a5a"))
		c.draw_circle(d + Vector2(0.0, -40.0), 8.0, Color(0.65, 0.5, 0.95, 0.85))


static func _b_wharf(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r, Color("7a5a3c"))
	for i in 6:
		var x := r.position.x + float(i) * r.size.x / 5.0
		c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("5a4230"), 2.0)
	c.draw_rect(r, Color("8a6a42"), false, 3.0)


static func _b_tent(c: CanvasItem, r: Rect2) -> void:
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(r.get_center().x, r.position.y),
		Vector2(r.end.x, r.end.y),
		Vector2(r.position.x, r.end.y),
	]), Color("8a7a5a"))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(r.get_center().x, r.position.y + 14.0),
		Vector2(r.get_center().x + 16.0, r.end.y),
		Vector2(r.get_center().x - 16.0, r.end.y),
	]), Color("4a4038"))
