class_name Hud
extends Control
## 战斗原型 HUD：体力 / 查克拉 / 经验 / 苦无 / 5 个忍术槽 / 连击 / 状态提示 / 升级提示。

var game
var player: Player

var notice_text := ""
var notice_timer := 0.0

const COL_HP := Color("58c258")
const COL_CHAKRA := Color("3f9fe0")
const COL_XP := Color("e0c447")
const COL_TEXT := Color("f0ece3")
const COL_DIM := Color("b8b2a4")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


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
	_draw_bars(font)
	_draw_jutsu_slots(font)
	_draw_counters(font)
	_draw_state_hints(font)
	_draw_notice(font)
	_draw_mission_result(font)
	if player.dead and not Flow.in_mission():
		_draw_death(font)


func _draw_bars(font: Font) -> void:
	var x := 24.0
	var y := 30.0
	var w := 230.0
	## 等级 + 段位
	draw_string(font, Vector2(x, y - 8.0), "Lv.%d %s" % [player.level, Data.s(player.rank_key())], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_XP)
	var by := y + 2.0
	draw_rect(Rect2(x, by, w, 16.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2.0, by + 2.0, (w - 4.0) * player.hp / player.max_hp, 12.0), COL_HP)
	draw_rect(Rect2(x, by, w, 16.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, by + 13.0), "%d / %d" % [int(player.hp), int(player.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT)
	var y2 := by + 22.0
	draw_rect(Rect2(x, y2, w, 10.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2.0, y2 + 2.0, (w - 4.0) * player.chakra / player.max_chakra, 6.0), COL_CHAKRA)
	draw_rect(Rect2(x, y2, w, 10.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, y2 + 9.0), "%d" % int(player.chakra), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
	## 经验条
	var y3 := y2 + 14.0
	draw_rect(Rect2(x, y3, w, 7.0), Color(0, 0, 0, 0.55))
	var xp_ratio: float = clampf(float(player.xp) / maxf(float(player.xp_next), 1.0), 0.0, 1.0)
	draw_rect(Rect2(x + 1.0, y3 + 1.0, (w - 2.0) * xp_ratio, 5.0), COL_XP)
	draw_rect(Rect2(x, y3, w, 7.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, y3 + 7.0), "%d / %d" % [player.xp, player.xp_next], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)
	draw_string(font, Vector2(x, y3 + 26.0), Data.s("hud.kunai") + " x %d" % player.kunai_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)


func _draw_jutsu_slots(font: Font) -> void:
	var size_v := get_viewport_rect().size
	var x := 24.0
	var y := size_v.y - 108.0
	var unlocked := player.slots_unlocked()
	for i in 5:
		var slot := Rect2(x + i * 84.0, y, 68.0, 68.0)
		var locked := i >= unlocked
		draw_rect(slot, Color(0, 0, 0, 0.55) if not locked else Color(0, 0, 0, 0.35))
		if locked:
			draw_rect(slot, Color(0.35, 0.35, 0.35), false, 1.5)
			var need: int = int(Player.SLOT_UNLOCK_LEVELS[i])
			draw_string(font, slot.position + Vector2(8.0, 40.0), "Lv.%d" % need, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.6))
			draw_string(font, Vector2(slot.position.x, slot.end.y + 16.0), Data.s("hud.locked"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
			continue
		var id: String = player.jutsu_slots[i] if i < player.jutsu_slots.size() else ""
		var cfg: Dictionary = Data.jutsu.get(id, {})
		var cd: float = float(player.jutsu_cd.get(id, 0.0))
		var cost: float = float(cfg.get("chakra_cost", 0.0))
		var ready: bool = cd <= 0.0 and (player.chakra >= cost or String(cfg.get("cast_type", "")) == "channel")
		draw_rect(slot, Color(0.95, 0.75, 0.3) if ready else Color(0.4, 0.4, 0.4), false, 1.5)
		Data.draw_jutsu_icon(self, id, slot.position + slot.size / 2.0, 20.0)
		if cd > 0.0:
			var cd_max: float = maxf(float(cfg.get("cooldown", 1.0)), 0.01)
			var h := slot.size.y * clampf(cd / cd_max, 0.0, 1.0)
			draw_rect(Rect2(slot.position.x, slot.end.y - h, slot.size.x, h), Color(0, 0, 0, 0.6))
		draw_string(font, slot.position + Vector2(5.0, 16.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)
		draw_string(font, Vector2(slot.position.x, slot.end.y + 16.0), Data.s(String(cfg.get("name_key", id))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)


func _draw_counters(font: Font) -> void:
	var size_v := get_viewport_rect().size
	draw_string(font, Vector2(size_v.x - 24.0, 34.0), Data.s("hud.kills") + "  %d" % game.kill_count, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, COL_TEXT)
	draw_string(font, Vector2(size_v.x - 24.0, 56.0), "%s %d 两 · %s" % [Data.s("hud.money"), Flow.money, Data.s("hud.day") % Flow.day], HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, Color("e0c447"))
	draw_string(font, Vector2(size_v.x / 2.0 - 130.0, 34.0), Data.s("hud.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
	## 任务目标
	var obj: String = game.objective_text()
	if obj != "":
		draw_string(font, Vector2(size_v.x / 2.0 - 110.0, 58.0), Data.s("hud.objective") + "：" + obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.85, 0.45))
	if player.buff_timer > 0.0 and not player.buff_id.is_empty():
		var cfg: Dictionary = Data.jutsu.get(player.buff_id, {})
		draw_string(font, Vector2(size_v.x - 24.0, 80.0), "%s %0.1fs" % [Data.s(String(cfg.get("name_key", player.buff_id))), player.buff_timer], HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, Color(0.6, 0.9, 1.0))
	if player.combo_count >= 2:
		var t: float = clampf(player.combo_timer / 1.2, 0.0, 1.0)
		draw_string(font, Vector2(size_v.x - 24.0, 112.0), "%s x %d" % [Data.s("hud.combo"), player.combo_count], HORIZONTAL_ALIGNMENT_RIGHT, -1, 26, Color(1.0, 0.85, 0.3, 0.4 + 0.6 * t))


func _draw_state_hints(font: Font) -> void:
	var size_v := get_viewport_rect().size
	var hint := ""
	var col := Color(1.0, 0.7, 0.3)
	match player.state:
		Player.State.SEALING:
			hint = Data.s("hud.sealing")
		Player.State.AIM:
			hint = Data.s("hud.aim_hint")
		Player.State.CHARGE:
			hint = Data.s("hud.charge_hint")
			col = Color(0.55, 0.85, 1.0)
		Player.State.GROUND:
			hint = Data.s("hud.ground_hint")
			col = Color(0.8, 0.7, 1.0)
		Player.State.CHANNEL:
			hint = Data.s("hud.channel_hint")
			col = Color(0.5, 0.95, 0.65)
		_:
			pass
	if hint != "":
		draw_string(font, Vector2(size_v.x / 2.0 - 150.0, size_v.y - 152.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	## 手持丸子提示
	if player.orb_active:
		draw_string(font, Vector2(size_v.x / 2.0 - 150.0, size_v.y - 180.0), Data.s("hud.orb_hint"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.65, 0.85, 1.0))
	## 替身术就绪指示
	if player._equipped("substitution"):
		var ready := float(player.jutsu_cd.get("substitution", 0.0)) <= 0.0
		var key := "hud.sub_ready" if ready else "hud.sub_cd"
		var c2 := Color(0.55, 0.85, 0.6) if ready else Color(0.55, 0.55, 0.55)
		draw_string(font, Vector2(size_v.x - 24.0, 134.0), Data.s(key), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, c2)
	## 交互提示（回村 / 结算）
	var ihint: String = game.current_interact_hint()
	if ihint != "":
		var w := 300.0
		var r := Rect2(size_v.x / 2.0 - w / 2.0, size_v.y - 210.0, w, 38.0)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r, Color(0.9, 0.75, 0.4, 0.9), false, 1.5)
		draw_string(font, r.position + Vector2(12.0, 25.0), ihint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f5e9c8"))
	draw_string(font, Vector2(size_v.x - 24.0, size_v.y - 18.0), Data.s("hud.controls"), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color(1, 1, 1, 0.45))


func _draw_notice(font: Font) -> void:
	if notice_timer <= 0.0:
		return
	var size_v := get_viewport_rect().size
	var a: float = clampf(notice_timer / 2.4, 0.0, 1.0)
	draw_string(font, Vector2(size_v.x / 2.0 - 90.0, 120.0), notice_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.92, 0.45, 0.35 + 0.65 * a))


func _draw_death(font: Font) -> void:
	var size_v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size_v), Color(0.05, 0.02, 0.02, 0.55))
	draw_string(font, Vector2(size_v.x / 2.0 - 150.0, size_v.y / 2.0 - 20.0), Data.s("hud.dead"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.3, 0.3))


func _draw_mission_result(font: Font) -> void:
	var size_v := get_viewport_rect().size
	if game.mission_state == game.MissionState.WON:
		draw_rect(Rect2(Vector2.ZERO, size_v), Color(0.05, 0.07, 0.04, 0.62))
		draw_string(font, Vector2(size_v.x / 2.0 - 96.0, size_v.y / 2.0 - 64.0), Data.s("mission.complete"), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.55, 0.95, 0.5))
		var ryo := int(game.result_rewards.get("ryo", 0))
		var rx := int(game.result_rewards.get("xp", 0))
		draw_string(font, Vector2(size_v.x / 2.0 - 160.0, size_v.y / 2.0), Data.s("mission.reward_line") % [ryo, rx], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e0c447"))
		draw_string(font, Vector2(size_v.x / 2.0 - 80.0, size_v.y / 2.0 + 52.0), Data.s("mission.back"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, COL_TEXT)
	elif game.mission_state == game.MissionState.LOST:
		draw_rect(Rect2(Vector2.ZERO, size_v), Color(0.06, 0.02, 0.02, 0.62))
		draw_string(font, Vector2(size_v.x / 2.0 - 84.0, size_v.y / 2.0 - 44.0), Data.s("mission.failed"), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.95, 0.35, 0.35))
		draw_string(font, Vector2(size_v.x / 2.0 - 80.0, size_v.y / 2.0 + 18.0), Data.s("mission.back"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, COL_TEXT)
