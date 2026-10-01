class_name Hud
extends Control
## 战斗原型 HUD：体力 / 查克拉 / 经验 / 武器槽 / 5 个忍术槽 / 连击 / 状态提示 / 升级提示。

var game
var player: Player

var notice_text := ""
var notice_timer := 0.0

## 任务开始大横幅
var banner_title := ""
var banner_sub := ""
var banner_timer := 0.0
const BANNER_TIME := 3.2

const COL_HP := Color("58c258")
const COL_CHAKRA := Color("3f9fe0")
const COL_STAMINA := Color("e8a33d")
const COL_STAMINA_OUT := Color("c0453a")
const COL_XP := Color("e0c447")
const COL_TEXT := Color("f0ece3")
const COL_DIM := Color("b8b2a4")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_notice(text: String) -> void:
	notice_text = text
	notice_timer = 2.4


func show_banner(title: String, sub: String) -> void:
	banner_title = title
	banner_sub = sub
	banner_timer = BANNER_TIME


func _process(delta: float) -> void:
	notice_timer = maxf(notice_timer - delta, 0.0)
	banner_timer = maxf(banner_timer - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := Data.font()
	_draw_bars(font)
	_draw_clock(font)
	_draw_jutsu_slots(font)
	_draw_counters(font)
	_draw_state_hints(font)
	_draw_test_badge(font)
	_draw_notice(font)
	_draw_banner(font)
	if game.mission_state == game.MissionState.RUNNING:
		_draw_target_arrow()
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
	## 体力条（查克拉条下方；力竭时变红）
	var ys := y2 + 14.0
	draw_rect(Rect2(x, ys, w, 10.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2.0, ys + 2.0, (w - 4.0) * player.stamina / player.max_stamina, 6.0),
		COL_STAMINA_OUT if player.exhausted else COL_STAMINA)
	draw_rect(Rect2(x, ys, w, 10.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, ys + 9.0), "%d" % int(player.stamina), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
	## 经验条
	var y3 := ys + 14.0
	draw_rect(Rect2(x, y3, w, 7.0), Color(0, 0, 0, 0.55))
	var xp_ratio: float = clampf(float(player.xp) / maxf(float(player.xp_next), 1.0), 0.0, 1.0)
	draw_rect(Rect2(x + 1.0, y3 + 1.0, (w - 2.0) * xp_ratio, 5.0), COL_XP)
	draw_rect(Rect2(x, y3, w, 7.0), Color(0.1, 0.1, 0.1, 0.9), false, 1.0)
	draw_string(font, Vector2(x + w + 10.0, y3 + 7.0), "%d / %d" % [player.xp, player.xp_next], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)
	_draw_weapons(font, x, y3 + 16.0)


## 左上角武器槽：血条下面两块，当前手持的那块高亮，右侧显示投掷余量。
## 布局照 3A 游戏的做法——不用打开任何界面就知道手上拿的是什么、还能扔几下。
func _draw_weapons(font: Font, x: float, y: float) -> void:
	var w := 244.0
	var h := 64.0
	var gap := 8.0
	for i in Player.WEAPON_SLOT_COUNT:
		var r := Rect2(x, y + float(i) * (h + gap), w, h)
		var id: String = player.weapon_at(i)
		var active: bool = i == player.active_weapon and not id.is_empty()
		draw_rect(r, Color(0, 0, 0, 0.6) if active else Color(0, 0, 0, 0.4))
		draw_rect(r, Color(1.0, 0.82, 0.35) if active else Color(0.42, 0.42, 0.46), false, 2.0 if active else 1.0)
		if id.is_empty():
			draw_string(font, r.position + Vector2(14.0, 38.0), Data.s("loadout.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.5, 0.52))
			continue
		Data.draw_item_icon(self, id, r.position + Vector2(32.0, h / 2.0 - 3.0), 18.0)
		draw_string(font, r.position + Vector2(58.0, 24.0), Data.weapon_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXT if active else COL_DIM)
		draw_string(font, r.position + Vector2(58.0, 44.0), Data.weapon_mode(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.62, 0.68))
		## 右上角：这一格里还剩几个（投掷余量）
		var cnt := player.weapon_count(i)
		var acol := Color("e0c447") if cnt > 0 else Color(0.6, 0.6, 0.62)
		draw_string(font, Vector2(r.position.x, r.position.y + 22.0), "x %d" % cnt,
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0, 15, acol)
		## 底部耐久条：只对近战会磨损的忍具显示
		var dr := player.weapon_dur_ratio(i)
		if dr >= 0.0:
			var bar := Rect2(r.position.x + 8.0, r.end.y - 11.0, r.size.x - 16.0, 5.0)
			draw_rect(bar, Color(0, 0, 0, 0.7))
			draw_rect(Rect2(bar.position.x + 1.0, bar.position.y + 1.0, (bar.size.x - 2.0) * dr, 3.0), _dur_color(dr))
			draw_rect(bar, Color(0.1, 0.1, 0.1, 0.85), false, 1.0)
	if Player.WEAPON_SLOT_COUNT > 1:
		draw_string(font, Vector2(x, y + 2.0 * (h + gap) + 16.0), Data.s("hud.weapon_switch"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.42))


## 耐久条颜色：绿 → 黄 → 红
func _dur_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.45, 0.85, 0.5)
	if ratio > 0.25:
		return Color(0.92, 0.8, 0.35)
	return Color(0.9, 0.4, 0.35)


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
	## draw_string 只在 width > 0 时才应用 alignment：传 -1 会让 RIGHT 退化成左对齐，
	## 文本从 size_v.x - 24 起往右画、直接溢出屏幕。所以右对齐一律用 (0, y) + width = 右边界。
	## 时钟占了右上角第一行（y=34），这里整体下移一格
	draw_string(font, Vector2(0.0, 58.0), Data.s("hud.kills") + "  %d" % game.kill_count, HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 15, COL_TEXT)
	draw_string(font, Vector2(0.0, 80.0), "%s %d 两 · %s" % [Data.s("hud.money"), Flow.money, Data.s("hud.day") % Flow.day], HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 13, Color("e0c447"))
	draw_string(font, Vector2(size_v.x / 2.0 - 130.0, 34.0), Data.s("hud.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
	## 任务目标
	var obj: String = game.objective_text()
	if obj != "":
		draw_string(font, Vector2(size_v.x / 2.0 - 110.0, 58.0), Data.s("hud.objective") + "：" + obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.85, 0.45))
	if player.buff_timer > 0.0 and not player.buff_id.is_empty():
		var cfg: Dictionary = Data.jutsu.get(player.buff_id, {})
		draw_string(font, Vector2(0.0, 102.0), "%s %0.1fs" % [Data.s(String(cfg.get("name_key", player.buff_id))), player.buff_timer], HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 13, Color(0.6, 0.9, 1.0))
	if player.combo_count >= 2:
		var t: float = clampf(player.combo_timer / 1.2, 0.0, 1.0)
		draw_string(font, Vector2(0.0, 112.0), "%s x %d" % [Data.s("hud.combo"), player.combo_count], HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 26, Color(1.0, 0.85, 0.3, 0.4 + 0.6 * t))


## 右上角时钟：第 N 天 + 时刻，配一个画出来的太阳 / 月亮（不依赖字体符号）
func _draw_clock(font: Font) -> void:
	var size_v := get_viewport_rect().size
	var right := size_v.x - 24.0
	var text := Flow.time_text()
	var night := Flow.is_night()
	var col := Color("bcd2f0") if night else Color("f0dfa0")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(0.0, 34.0), text, HORIZONTAL_ALIGNMENT_RIGHT, right, 15, col)
	_draw_time_icon(Vector2(right - w - 16.0, 28.0), 7.0, night)


func _draw_time_icon(c: Vector2, r: float, night: bool) -> void:
	if night:
		## 满月 + 两个环形山
		draw_circle(c, r, Color("cfd8ee"))
		draw_circle(c + Vector2(-r * 0.28, -r * 0.24), r * 0.22, Color("9fabc6"))
		draw_circle(c + Vector2(r * 0.3, r * 0.26), r * 0.16, Color("9fabc6"))
	else:
		## 太阳 + 八道光芒
		for i in 8:
			var a := TAU * float(i) / 8.0
			draw_line(c + Vector2.from_angle(a) * r * 0.95, c + Vector2.from_angle(a) * r * 1.45, Color("f2d24a"), 2.0)
		draw_circle(c, r * 0.62, Color("f2d24a"))


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
		draw_string(font, Vector2(0.0, 134.0), Data.s(key), HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 12, c2)
	## 交互提示（回村 / 结算）
	var ihint: String = game.current_interact_hint()
	if ihint != "":
		var w := 300.0
		var r := Rect2(size_v.x / 2.0 - w / 2.0, size_v.y - 210.0, w, 38.0)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r, Color(0.9, 0.75, 0.4, 0.9), false, 1.5)
		draw_string(font, r.position + Vector2(12.0, 25.0), ihint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f5e9c8"))
	draw_string(font, Vector2(0.0, size_v.y - 18.0), Data.s("hud.controls"), HORIZONTAL_ALIGNMENT_RIGHT, size_v.x - 24.0, 12, Color(1, 1, 1, 0.45))


## 测试模式角标：左下角（槽位行上方那一带，不与槽位名重叠）
func _draw_test_badge(font: Font) -> void:
	var size_v := get_viewport_rect().size
	if Flow.test_unlock_all:
		draw_string(font, Vector2(24.0, size_v.y - 130.0), Data.s("hud.test_on"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.62, 0.3))
	else:
		draw_string(font, Vector2(24.0, size_v.y - 130.0), Data.s("hud.test_off"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.4))


func _draw_notice(font: Font) -> void:
	if notice_timer <= 0.0:
		return
	var size_v := get_viewport_rect().size
	var a: float = clampf(notice_timer / 2.4, 0.0, 1.0)
	draw_string(font, Vector2(size_v.x / 2.0 - 90.0, 120.0), notice_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.92, 0.45, 0.35 + 0.65 * a))


func _draw_banner(font: Font) -> void:
	if banner_timer <= 0.0:
		return
	var size_v := get_viewport_rect().size
	## 前 0.4s 淡入，最后 0.6s 淡出
	var a := 1.0
	if banner_timer > BANNER_TIME - 0.4:
		a = (BANNER_TIME - banner_timer) / 0.4
	elif banner_timer < 0.6:
		a = banner_timer / 0.6
	var cy := size_v.y * 0.32
	draw_rect(Rect2(0, cy - 46, size_v.x, 92), Color(0.05, 0.05, 0.07, 0.72 * a))
	draw_rect(Rect2(0, cy - 46, size_v.x, 3), Color(0.9, 0.75, 0.35, a))
	draw_rect(Rect2(0, cy + 43, size_v.x, 3), Color(0.9, 0.75, 0.35, a))
	draw_string(font, Vector2(0, cy - 4), banner_title, HORIZONTAL_ALIGNMENT_CENTER, size_v.x, 34, Color(1.0, 0.9, 0.55, a))
	draw_string(font, Vector2(0, cy + 28), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, size_v.x, 18, Color(0.85, 0.85, 0.9, a))


## 屏幕外目标指引：目标不在视野内时，在屏幕边缘画一个指向它的箭头
func _draw_target_arrow() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var t: Dictionary = game.nearest_target()
	if not bool(t.get("valid", false)):
		return
	var size_v := get_viewport_rect().size
	var sp: Vector2 = cam.get_canvas_transform() * (t["pos"] as Vector2)
	var m := 64.0
	if sp.x > m and sp.x < size_v.x - m and sp.y > m and sp.y < size_v.y - m:
		return
	var edge := Vector2(clampf(sp.x, m, size_v.x - m), clampf(sp.y, m, size_v.y - m))
	var dir := (sp - size_v * 0.5).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var perp := Vector2(-dir.y, dir.x)
	var col := Color(1.0, 0.88, 0.4, 0.95)
	draw_colored_polygon(PackedVector2Array([
		edge + dir * 18.0, edge - dir * 12.0 + perp * 11.0, edge - dir * 12.0 - perp * 11.0]), col)
	draw_arc(edge, 24.0, 0.0, TAU, 24, Color(1.0, 0.88, 0.4, 0.4), 2.0)


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
