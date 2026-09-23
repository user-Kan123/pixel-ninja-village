class_name LoadoutUi
extends Control
## 忍术装配界面：Tab 打开（游戏暂停），左侧选槽位、右侧点忍术装入。
## 槽位数量由等级决定（1/1/1/6/12 级解锁 5 个槽），未解锁的槽不可装配。

var game
var player: Player
var selected_slot := 0

const PANEL_W := 1000.0
const PANEL_H := 580.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func on_opened() -> void:
	selected_slot = 0
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB, KEY_ESCAPE:
				game.close_loadout()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				selected_slot = int(event.keycode) - int(KEY_1)
				queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in 5:
				if _slot_rect(i).has_point(p):
					selected_slot = i
					queue_redraw()
					return
			for j in Data.jutsu_list.size():
				if _grid_rect(j).has_point(p):
					_assign(j)
					return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			for i in 5:
				if _slot_rect(i).has_point(p):
					if i < player.jutsu_slots.size():
						player.jutsu_slots[i] = ""
					queue_redraw()
					return


func _assign(index: int) -> void:
	if selected_slot >= player.slots_unlocked():
		return
	var id: String = Data.jutsu_list[index]
	## 同一个忍术不重复占两个槽：先从其它槽里摘掉
	for i in player.jutsu_slots.size():
		if player.jutsu_slots[i] == id:
			player.jutsu_slots[i] = ""
	player.jutsu_slots[selected_slot] = id
	## 装入后自动跳到下一个空槽，连续装配更顺手
	for i in 5:
		var nxt := (selected_slot + 1 + i) % 5
		if nxt < player.slots_unlocked() and player.jutsu_slots[nxt].is_empty():
			selected_slot = nxt
			break
	queue_redraw()


# ---------------------------------------------------------------- 布局

func _panel_rect() -> Rect2:
	var v := get_viewport_rect().size
	return Rect2((v.x - PANEL_W) / 2.0, (v.y - PANEL_H) / 2.0, PANEL_W, PANEL_H)


func _slot_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 26.0, p.position.y + 92.0 + float(i) * 86.0, 200.0, 74.0)


func _grid_rect(j: int) -> Rect2:
	var p := _panel_rect()
	var col := j % 2
	var row := int(j / 2.0)
	return Rect2(p.position.x + 256.0 + float(col) * 372.0, p.position.y + 92.0 + float(row) * 88.0, 356.0, 78.0)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if player == null:
		return
	var font := Data.font()
	var v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.03, 0.03, 0.05, 0.78))
	var p := _panel_rect()
	draw_rect(p, Color("232227"))
	draw_rect(p, Color(0.85, 0.72, 0.4), false, 2.0)
	draw_string(font, Vector2(p.position.x + 26.0, p.position.y + 46.0), Data.s("loadout.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f0ece3"))
	draw_string(font, Vector2(p.position.x + 240.0, p.position.y + 46.0), "Lv.%d %s" % [player.level, Data.s(player.rank_key())], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e0c447"))
	_draw_slots(font)
	_draw_grid(font)
	draw_string(font, Vector2(p.position.x + 26.0, p.end.y - 20.0), Data.s("loadout.hint"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b8b2a4"))


func _draw_slots(font: Font) -> void:
	var unlocked := player.slots_unlocked()
	for i in 5:
		var r := _slot_rect(i)
		var locked := i >= unlocked
		var sel := i == selected_slot and not locked
		draw_rect(r, Color(0.13, 0.13, 0.16) if not locked else Color(0.09, 0.09, 0.1))
		draw_rect(r, Color(1.0, 0.82, 0.35) if sel else Color(0.35, 0.35, 0.38), false, 2.5 if sel else 1.5)
		draw_string(font, r.position + Vector2(10.0, 20.0), "%s %d" % [Data.s("loadout.slot"), i + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f0ece3"))
		if locked:
			draw_string(font, r.position + Vector2(10.0, 46.0), "%s (Lv.%d)" % [Data.s("hud.locked"), int(Player.SLOT_UNLOCK_LEVELS[i])], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.55))
			continue
		var id: String = player.jutsu_slots[i] if i < player.jutsu_slots.size() else ""
		if id.is_empty():
			draw_string(font, r.position + Vector2(10.0, 46.0), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
			continue
		var cfg: Dictionary = Data.jutsu.get(id, {})
		Data.draw_jutsu_icon(self, id, r.position + Vector2(r.size.x - 34.0, 42.0), 18.0)
		draw_string(font, r.position + Vector2(10.0, 46.0), Data.s(String(cfg.get("name_key", id))), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.92, 1.0))
		draw_string(font, r.position + Vector2(10.0, 64.0), _detail(id, cfg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.62, 0.66))


func _draw_grid(font: Font) -> void:
	for j in Data.jutsu_list.size():
		var id: String = Data.jutsu_list[j]
		var cfg: Dictionary = Data.jutsu.get(id, {})
		var r := _grid_rect(j)
		var equipped := Array(player.jutsu_slots).has(id)
		draw_rect(r, Color(0.16, 0.16, 0.19) if not equipped else Color(0.2, 0.22, 0.26))
		draw_rect(r, Color(0.95, 0.78, 0.35) if equipped else Color(0.3, 0.3, 0.33), false, 2.0 if equipped else 1.0)
		Data.draw_jutsu_icon(self, id, r.position + Vector2(38.0, 39.0), 22.0)
		draw_string(font, r.position + Vector2(76.0, 26.0), Data.s(String(cfg.get("name_key", id))), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f0ece3"))
		draw_string(font, r.position + Vector2(76.0, 46.0), _detail(id, cfg), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.66, 0.7))
		draw_string(font, r.position + Vector2(76.0, 66.0), "RANK " + String(cfg.get("rank", "-")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.6, 0.35))
		if equipped:
			draw_string(font, r.position + Vector2(r.size.x - 62.0, 22.0), "ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.8, 0.35))


func _detail(id: String, cfg: Dictionary) -> String:
	var cat := String(cfg.get("category", ""))
	var cast := String(cfg.get("cast_type", ""))
	var cost := int(cfg.get("chakra_cost", 0))
	var cd := float(cfg.get("cooldown", 0.0))
	var cost_txt := "%d/s" % int(cfg.get("chakra_per_second", 0)) if cast == "channel" else str(cost)
	return "%s · %s · %s %s · %s %.1fs" % [
		Data.s("cat." + cat), Data.s("cast." + cast),
		Data.s("loadout.cost"), cost_txt,
		Data.s("loadout.cooldown"), cd,
	]
