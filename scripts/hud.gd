class_name Hud
extends Control
## 战斗原型 HUD：血条 / 查克拉 / 苦无 / 忍术槽 / 连击 / 状态提示。

var game
var player: Player

const COL_HP := Color("58c258")
const COL_CHAKRA := Color("3f9fe0")
const COL_TEXT := Color("f0ece3")
const COL_DIM := Color("b8b2a4")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := Data.font()
	_draw_bars(font)
	_draw_jutsu_slots(font)
	_draw_counters(font)
	_draw_state_hints(font)
	if player.dead:
		_draw_death(font)


func _draw_bars(font: Font) -> void:
	var x := 24.0
	var y := 24.0
	var w := 230.0
	draw_rect(Rect2(x, y, w, 16.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2.0, y + 2.0, (w - 4.0) * player.hp / player.MAX_HP, 12.0), COL_HP)
	draw_rect(Rect2(x, y, w, 16.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, y + 13.0), "%d / %d" % [int(player.hp), int(player.MAX_HP)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT)
	var y2 := y + 22.0
	draw_rect(Rect2(x, y2, w, 10.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2.0, y2 + 2.0, (w - 4.0) * player.chakra / player.MAX_CHAKRA, 6.0), COL_CHAKRA)
	draw_rect(Rect2(x, y2, w, 10.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, y2 + 9.0), "%d" % int(player.chakra), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
	draw_string(font, Vector2(x, y2 + 32.0), Data.s("hud.kunai") + " x %d" % player.kunai_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)


func _draw_jutsu_slots(font: Font) -> void:
	var size_v := get_viewport_rect().size
	var x := 24.0
	var y := size_v.y - 104.0
	var ids := ["blink", "fireball"]
	var keys := ["1", "2"]
	for i in ids.size():
		var id: String = ids[i]
		var cfg: Dictionary = Data.jutsu.get(id, {})
		var slot := Rect2(x + i * 84.0, y, 68.0, 68.0)
		var ready: bool = float(player.jutsu_cd.get(id, 0.0)) <= 0.0 and player.chakra >= float(cfg.get("chakra_cost", 0.0))
		draw_rect(slot, Color(0, 0, 0, 0.55))
		var border := Color(0.95, 0.75, 0.3) if ready else Color(0.4, 0.4, 0.4)
		draw_rect(slot, border, false, 1.5)
		var c := slot.position + slot.size / 2.0
		if id == "blink":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -14), c + Vector2(11, 8), c + Vector2(-11, 8),
			]), Color(0.55, 0.85, 1.0))
		else:
			draw_circle(c, 13.0, Color(1.0, 0.55, 0.2))
			draw_circle(c, 6.0, Color(1.0, 0.9, 0.6))
		var cd: float = float(player.jutsu_cd.get(id, 0.0))
		var cd_max: float = float(cfg.get("cooldown", 1.0))
		if cd > 0.0:
			var h := slot.size.y * clampf(cd / cd_max, 0.0, 1.0)
			draw_rect(Rect2(slot.position.x, slot.end.y - h, slot.size.x, h), Color(0, 0, 0, 0.6))
		draw_string(font, slot.position + Vector2(4.0, 16.0), keys[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)
		draw_string(font, Vector2(slot.position.x, slot.end.y + 16.0), Data.s(String(cfg.get("name_key", id))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)


func _draw_counters(font: Font) -> void:
	var size_v := get_viewport_rect().size
	draw_string(font, Vector2(size_v.x - 24.0, 34.0), Data.s("hud.kills") + "  %d" % game.kill_count, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, COL_TEXT)
	draw_string(font, Vector2(size_v.x / 2.0 - 130.0, 34.0), Data.s("hud.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
	if player.combo_count >= 2:
		var t: float = clampf(player.combo_timer / 1.2, 0.0, 1.0)
		draw_string(font, Vector2(size_v.x - 24.0, 84.0), "%s x %d" % [Data.s("hud.combo"), player.combo_count], HORIZONTAL_ALIGNMENT_RIGHT, -1, 26, Color(1.0, 0.85, 0.3, 0.4 + 0.6 * t))


func _draw_state_hints(font: Font) -> void:
	var size_v := get_viewport_rect().size
	if player.state == Player.State.SEALING:
		draw_string(font, Vector2(size_v.x / 2.0 - 50.0, size_v.y - 150.0), Data.s("hud.sealing"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.7, 0.3))
	elif player.state == Player.State.AIM:
		draw_string(font, Vector2(size_v.x / 2.0 - 130.0, size_v.y - 150.0), Data.s("hud.aim_hint"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.7, 0.3))
	draw_string(font, Vector2(size_v.x - 24.0, size_v.y - 18.0), Data.s("hud.controls"), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color(1, 1, 1, 0.45))


func _draw_death(font: Font) -> void:
	var size_v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size_v), Color(0.05, 0.02, 0.02, 0.55))
	draw_string(font, Vector2(size_v.x / 2.0 - 150.0, size_v.y / 2.0 - 20.0), Data.s("hud.dead"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.3, 0.3))
