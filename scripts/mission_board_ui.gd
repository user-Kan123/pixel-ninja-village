class_name MissionBoardUi
extends Control
## 任务看板：列出 D 级任务，点击接取后进入任务战场。
## 打开时游戏暂停；Esc / Tab 关闭。

var game

const PANEL_W := 760.0
const PANEL_H := 480.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func on_opened() -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
			game.close_board()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		var ids := _mission_ids()
		for i in ids.size():
			if _row_rect(i).has_point(p):
				game.close_board()
				Flow.start_mission(ids[i])
				return


func _mission_ids() -> Array:
	var out: Array = Data.missions.keys()
	out.sort()
	return out


func _panel_rect() -> Rect2:
	var v := get_viewport_rect().size
	return Rect2((v.x - PANEL_W) / 2.0, (v.y - PANEL_H) / 2.0, PANEL_W, PANEL_H)


func _row_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 30.0, p.position.y + 96.0 + float(i) * 110.0, PANEL_W - 60.0, 96.0)


func _draw() -> void:
	var font := Data.font()
	var v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.03, 0.03, 0.05, 0.72))
	var p := _panel_rect()
	draw_rect(p, Color("2b2620"))
	draw_rect(p, Color(0.85, 0.72, 0.4), false, 2.0)
	draw_string(font, p.position + Vector2(30.0, 48.0), Data.s("board.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f0ece3"))
	draw_string(font, Vector2(p.end.x - 30.0, 48.0), "%s %d 两 · %s" % [Data.s("hud.money"), Flow.money, Data.s("hud.day") % Flow.day], HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, Color("e0c447"))
	var ids := _mission_ids()
	for i in ids.size():
		var id: String = ids[i]
		var cfg: Dictionary = Data.missions[id]
		var r := _row_rect(i)
		draw_rect(r, Color(0.16, 0.14, 0.11))
		draw_rect(r, Color(0.45, 0.38, 0.25), false, 1.5)
		draw_string(font, r.position + Vector2(16.0, 28.0), "%s 级 · %s" % [String(cfg.get("rank", "D")), Data.s(String(cfg.get("name_key", id)))], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("f0ece3"))
		draw_string(font, r.position + Vector2(16.0, 52.0), Data.s(String(cfg.get("desc_key", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b8b2a4"))
		var reward_txt := "%s %d 两 · %s +%d" % [Data.s("board.reward"), int(cfg.get("reward_ryo", 0)), Data.s("hud.level"), int(cfg.get("reward_xp", 0))]
		var done := Flow.mission_done_count(id)
		if done > 0:
			reward_txt += " · " + Data.s("board.done") % done
		draw_string(font, r.position + Vector2(16.0, 76.0), reward_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e0c447"))
		var btn := Rect2(r.end.x - 92.0, r.position.y + 28.0, 76.0, 40.0)
		draw_rect(btn, Color(0.72, 0.5, 0.2))
		draw_rect(btn, Color(0.95, 0.85, 0.6), false, 1.5)
		draw_string(font, btn.position + Vector2(18.0, 27.0), Data.s("board.accept"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("fff6e0"))
	draw_string(font, p.position + Vector2(30.0, p.size.y - 22.0), Data.s("board.hint"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b8b2a4"))
