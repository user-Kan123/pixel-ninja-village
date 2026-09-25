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
	## 左上：等级 / 天数 / 赏金
	draw_string(font, Vector2(24.0, 34.0), "Lv.%d %s" % [player.level, Data.s(player.rank_key())], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT)
	draw_string(font, Vector2(24.0, 60.0), Data.s("hud.day") % Flow.day, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_DIM)
	draw_string(font, Vector2(24.0, 84.0), "%s %d 两" % [Data.s("hud.money"), Flow.money], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_GOLD)
	## 忍术装配入口单独占一行：避免玩家以为它藏在任务看板里
	draw_string(font, Vector2(24.0, 112.0), Data.s("village.loadout_key"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.78, 0.55))
	## 右上：标题（右对齐必须给 width，否则会溢出屏幕）
	draw_string(font, Vector2(0.0, 34.0), Data.s("hud.title"), HORIZONTAL_ALIGNMENT_RIGHT, v.x - 24.0, 13, COL_DIM)
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
