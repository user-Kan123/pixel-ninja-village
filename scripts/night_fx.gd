class_name NightFx
extends RefCounted
## 夜幕：按当前时刻算压暗强度，并在屏幕上铺一层"玩家周围看得见"的黑暗。
##
## 为什么用一圈圈粗圆弧：Godot 的普通绘制只能"加深"不能"减淡"，
## 所以不铺整屏再挖洞，而是从玩家身边向外画同心圆环，越往外越黑，直到超出屏幕对角线。
## 好处是不依赖 shader，也不受纹理导入设置（repeat / filter）影响。

const NIGHT_DARK_MAX := 0.55      ## 最大压暗不透明度（规格写 0.35，实测看不出夜色，见 ledger 裁决）
const DUSK_FADE_HOURS := 0.5      ## 黄昏 / 黎明的渐变时长（游戏小时）
const VISIBLE_RADIUS := 180.0     ## 玩家周围完全可见的半径（像素）
const FADE_RADIUS := 640.0        ## 到这里的压暗达到最大
## 环越细分层越不明显（每帧 draw_arc 次数 = 屏幕对角线 / 环距，约 70 次）
const RING_WIDTH := 20.0
const DARK_COLOR := Color(0.05, 0.07, 0.16)


## 当前时刻的压暗强度：18:00 起半小时内升到最大，06:00 前半小时降回 0。
static func dark_alpha(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h >= 18.0 and h < 18.0 + DUSK_FADE_HOURS:
		return NIGHT_DARK_MAX * ((h - 18.0) / DUSK_FADE_HOURS)
	if h >= 6.0 - DUSK_FADE_HOURS and h < 6.0:
		return NIGHT_DARK_MAX * ((6.0 - h) / DUSK_FADE_HOURS)
	if h >= 18.0 + DUSK_FADE_HOURS or h < 6.0 - DUSK_FADE_HOURS:
		return NIGHT_DARK_MAX
	return 0.0


## 在 HUD 上铺夜幕；center 是玩家在屏幕上的坐标
static func draw_overlay(c: CanvasItem, center: Vector2, view_size: Vector2) -> void:
	var a := dark_alpha(Flow.hour)
	if a <= 0.002:
		return
	var fade := maxf(FADE_RADIUS - VISIBLE_RADIUS, 1.0)
	var far := view_size.length() + RING_WIDTH * 2.0
	var r := VISIBLE_RADIUS
	while r < far:
		var t: float = clampf((r - VISIBLE_RADIUS) / fade, 0.0, 1.0)
		if t > 0.0:
			c.draw_arc(center, r, 0.0, TAU, 40,
				Color(DARK_COLOR.r, DARK_COLOR.g, DARK_COLOR.b, a * t), RING_WIDTH)
		r += RING_WIDTH * 0.94
