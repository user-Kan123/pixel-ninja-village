class_name PixelArt
extends RefCounted
## 程序化像素忍者绘制：像素矩阵 + 两帧走路动画，无素材依赖。
## 玩家与全部人形敌人共用本绘制器，外观由 cfg 颜色表决定；数据驱动，方便后期整体替换。
##
## cfg 字段（均可省略，有兜底）：
##   hair/hair_dark 发色 · skin/skin_dark 肤色 · eye 眼睛
##   band 护额带 · plate 护额金属牌
##   outfit/outfit_dark 上衣 · trim 肩部内衬 · belt 腰带
##   pants/pants_dark 裤子 · shoes 鞋
##   pattern: "" / "cloud"（晓袍红云）/ "armor"（护甲纹）· pattern_color
##   flash_a: 0~1 受击闪白强度

## 头 + 躯干（14 列 × 15 行）
const UPPER: Array[String] = [
	"..HH..HH..HH..",
	".HHHHHHHHHHHH.",
	"HHHHHHHHHHHHHH",
	"hHHHHHHHHHHHHh",
	"bBBBBBBBBBBBBb",
	"SSSEESSSSEESSS",
	"SSSSSSSSSSSSSS",
	".sSSSSSSSSSSs.",
	"WCCCCCCCCCCCCW",
	"SCCCCCCCCCCCCS",
	"SCCCCCCCCCCCCS",
	".SCCCCCCCCCCS.",
	"..CCCCCCCCCC..",
	"..cCCCCCCCCc..",
	"..nPPPPPPPPn..",
]

## 腿部两帧（走路动画）
const LEGS_A: Array[String] = [
	"..PPP....PPP..",
	"..PPP....PPP..",
	"..PPP....PPP..",
	"..PPP....PPP..",
	"..XXX....XXX..",
]
const LEGS_B: Array[String] = [
	"..PPP....PPP..",
	"...PP....PP...",
	"...PPP..PPP...",
	"..PPP....PPP..",
	".XXX......XXX.",
]

## 木桩（10 列 × 15 行）
const DUMMY: Array[String] = [
	"..tttttt..",
	".tttttttt.",
	"tttttttttt",
	"oooooooooo",
	"rrrooooorrr",
	"oooooooooo",
	"o.oooooo.o",
	"oooooooooo",
	"rrrooooorrr",
	"oooooooooo",
	"oooooooooo",
	".oooooooo.",
	"..oooooo..",
	"...oooo...",
	"....oo....",
]


static func draw_ninja(c: CanvasItem, center: Vector2, cfg: Dictionary, frame: int, pixel: float = 3.0) -> void:
	var rows: Array = UPPER.duplicate()
	rows.append_array(LEGS_B if frame == 1 else LEGS_A)
	var w := 14
	var h := rows.size()
	var ox := center.x - float(w) * pixel / 2.0
	var oy := center.y - float(h) * pixel / 2.0
	var flash_a: float = float(cfg.get("flash_a", 0.0))
	var alpha_m: float = float(cfg.get("alpha", 1.0))
	for ry in h:
		var row: String = String(rows[ry])
		for rx in w:
			var ch := row[rx]
			if ch == ".":
				continue
			var col: Color = _color(ch, cfg)
			if flash_a > 0.0:
				col = col.lerp(Color.WHITE, flash_a)
			col.a *= alpha_m
			c.draw_rect(Rect2(ox + rx * pixel, oy + ry * pixel, pixel + 0.6, pixel + 0.6), col)
	_apply_pattern(c, cfg, ox, oy, pixel)


static func draw_dummy(c: CanvasItem, center: Vector2, flash_a: float, pixel: float = 3.0) -> void:
	var w := 10
	var h := DUMMY.size()
	var ox := center.x - float(w) * pixel / 2.0
	var oy := center.y - float(h) * pixel / 2.0
	for ry in h:
		var row: String = DUMMY[ry]
		for rx in w:
			var ch := row[rx]
			if ch == ".":
				continue
			var col: Color = _color(ch, {})
			if flash_a > 0.0:
				col = col.lerp(Color.WHITE, flash_a)
			c.draw_rect(Rect2(ox + rx * pixel, oy + ry * pixel, pixel + 0.6, pixel + 0.6), col)


# ---------------------------------------------------------------- 内部

static func _color(ch: String, cfg: Dictionary) -> Color:
	match ch:
		"H":
			return cfg.get("hair", Color("e8b83a"))
		"h":
			return cfg.get("hair_dark", Color("c89028"))
		"S":
			return cfg.get("skin", Color("f0c49c"))
		"s":
			return cfg.get("skin_dark", Color("d6a070"))
		"E":
			return cfg.get("eye", Color("2a2a33"))
		"B":
			return cfg.get("plate", Color("c9cdd6"))
		"b":
			return cfg.get("band", Color("2a3a5c"))
		"C":
			return cfg.get("outfit", Color("e8833a"))
		"c":
			return cfg.get("outfit_dark", Color("c96528"))
		"W":
			return cfg.get("trim", Color("eee8da"))
		"n":
			return cfg.get("belt", Color("3a3a44"))
		"P":
			return cfg.get("pants", Color("3a4a7a"))
		"p":
			return cfg.get("pants_dark", Color("2a3658"))
		"X":
			return cfg.get("shoes", Color("2b2b33"))
		"t":
			return Color("c89a68")
		"o":
			return Color("9a6f45")
		"r":
			return Color("5a4632")
	return Color.MAGENTA


static func _apply_pattern(c: CanvasItem, cfg: Dictionary, ox: float, oy: float, pixel: float) -> void:
	var pat: String = String(cfg.get("pattern", ""))
	match pat:
		"cloud":
			## 晓袍红云：躯干区两朵简化云
			var pc: Color = cfg.get("pattern_color", Color("c8383a"))
			for spot in [Vector2i(4, 10), Vector2i(9, 12)]:
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)]:
					c.draw_rect(Rect2(
						ox + (spot.x + d.x) * pixel, oy + (spot.y + d.y) * pixel,
						pixel + 0.5, pixel + 0.5), pc)
		"armor":
			## 横向护甲高光
			var lc: Color = cfg.get("armor_line", Color("9a8ac8"))
			for ry in [9, 11, 13]:
				c.draw_rect(Rect2(ox + 2 * pixel, oy + ry * pixel, 10 * pixel, pixel * 0.7), lc)
