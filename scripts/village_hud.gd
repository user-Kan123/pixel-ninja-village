class_name VillageHud
extends Control
## 村庄 HUD：天数 / 赏金 / 等级段位 / 交互提示 / 操作提示 / 通知。

var game
var player: Player

var notice_text := ""
var notice_timer := 0.0

const COL_TEXT := Color("f0ece3")
const COL_DIM := Color("b8b2a4")
const COL_GOLD := Color("e0c447")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_notice(text: String) -> void:
	notice_text = text
	notice_timer = 2.4


func _process(delta: float) -> void:
	notice_timer = maxf(notice_timer - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := Data.font()
	var v := get_viewport_rect().size
	_draw_night(v)
	## 左上：等级 / 天数 / 赏金
	draw_string(font, Vector2(24.0, 34.0), "Lv.%d %s" % [player.level, Data.s(player.rank_key())], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT)
	draw_string(font, Vector2(24.0, 60.0), Data.s("hud.day") % Flow.day, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_DIM)
	draw_string(font, Vector2(24.0, 84.0), "%s %d 两" % [Data.s("hud.money"), Flow.money], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_GOLD)
	## 已装备的忍具：买完 / 换完能立刻在村里看到结果
	draw_string(font, Vector2(24.0, 110.0), "%s %s / %s" % [
		Data.s("village.equipped"),
		Data.weapon_name(player.weapon_at(0)),
		Data.weapon_name(player.weapon_at(1)),
	], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.84, 0.92))
	## 忍术装配入口单独占一行：避免玩家以为它藏在任务看板里
	draw_string(font, Vector2(24.0, 136.0), Data.s("village.loadout_key"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.78, 0.55))
	## 右上：标题（右对齐必须给 width，否则会溢出屏幕）
	_draw_clock(font, v)
	## 时钟占了第一行，标题下移
	draw_string(font, Vector2(0.0, 58.0), Data.s("hud.title"), HORIZONTAL_ALIGNMENT_RIGHT, v.x - 24.0, 13, COL_DIM)
	## 中下：交互提示
	var hint: String = game.current_interact_hint()
	if hint != "":
		var w := 320.0
		var r := Rect2(v.x / 2.0 - w / 2.0, v.y - 150.0, w, 40.0)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r, Color(0.9, 0.75, 0.4, 0.9), false, 1.5)
		draw_string(font, r.position + Vector2(12.0, 26.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f5e9c8"))
	## 底部操作提示
	draw_string(font, Vector2(0.0, v.y - 18.0), Data.s("village.hint"), HORIZONTAL_ALIGNMENT_RIGHT, v.x - 24.0, 12, Color(1, 1, 1, 0.45))
	## 测试模式角标（与战斗 HUD 同一位置：左下角）
	if Flow.test_unlock_all:
		draw_string(font, Vector2(24.0, v.y - 130.0), Data.s("hud.test_on"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.62, 0.3))
	else:
		draw_string(font, Vector2(24.0, v.y - 130.0), Data.s("hud.test_off"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.4))
	## 通知
	if notice_timer > 0.0:
		var a: float = clampf(notice_timer / 2.4, 0.0, 1.0)
		draw_string(font, Vector2(v.x / 2.0 - 80.0, 130.0), notice_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.92, 0.45, 0.35 + 0.65 * a))


## 右上角时钟：第 N 天 + 时刻，配一个画出来的太阳 / 月亮
## 夜幕：铺在世界之上、HUD 元素之下
func _draw_night(v: Vector2) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	NightFx.draw_overlay(self, cam.get_canvas_transform() * player.global_position, v)


func _draw_clock(font: Font, v: Vector2) -> void:
	var right := v.x - 24.0
	var text := Flow.time_text()
	var night := Flow.is_night()
	var col := Color("bcd2f0") if night else Color("f0dfa0")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(0.0, 34.0), text, HORIZONTAL_ALIGNMENT_RIGHT, right, 15, col)
	_draw_time_icon(Vector2(right - w - 16.0, 28.0), 7.0, night)


func _draw_time_icon(c: Vector2, r: float, night: bool) -> void:
	if night:
		draw_circle(c, r, Color("cfd8ee"))
		draw_circle(c + Vector2(-r * 0.28, -r * 0.24), r * 0.22, Color("9fabc6"))
		draw_circle(c + Vector2(r * 0.3, r * 0.26), r * 0.16, Color("9fabc6"))
	else:
		for i in 8:
			var a := TAU * float(i) / 8.0
			draw_line(c + Vector2.from_angle(a) * r * 0.95, c + Vector2.from_angle(a) * r * 1.45, Color("f2d24a"), 2.0)
		draw_circle(c, r * 0.62, Color("f2d24a"))
