class_name LoadoutUi
extends Control
## 装备与背包（B 打开，游戏暂停）。两个页签，Tab 切换：
##   装备与背包：左边 2 个武器槽（主手 / 副手，Q 切换），右边 24 格背包
##   忍术装配  ：左边 5 个忍术槽，右边是已学会的忍术
## 背包里：忍具点一下 = 装到选中的武器槽（再点一下换回来），道具点一下 = 立刻使用。
## 忍术页操作：点左侧槽位选中 → 点右侧卡片装入 → 右键点槽位卸下。

enum Tab { WEAPON, JUTSU }

var game
var player: Player
var tab := Tab.WEAPON
## 选中槽位：忍术页与武器页各记一份，来回切页签不会丢选中
var selected_slot := 0
var selected_weapon_slot := 0

var hint_text := ""
var hint_timer := 0.0

const PANEL_W := 1040.0
const PANEL_H := 664.0
const HEADER_H := 100.0
const TAB_X := 26.0
const TAB_Y := 54.0
const TAB_W := 190.0
const TAB_H := 34.0
## 忍术页：左列 5 个槽位 + 右侧 2 列 × 8 行网格
const SLOT_H := 74.0
const SLOT_GAP := 104.0
const CARD_W := 360.0
const CARD_H := 64.0
const CARD_GAP := 64.0
## 武器页：左列 2 个武器槽 + 右侧 6 × 4 背包格
const WSLOT_W := 300.0
const WSLOT_H := 210.0
const WSLOT_GAP := 20.0
const BAG_X := 352.0
const BAG_Y := 132.0
const CELL := 96.0
const CELL_GAP := 8.0
const BAG_COLS := 6
const BAG_ROWS := 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	## 与任务看板同理：父节点是 CanvasLayer，必须同时设置 anchors 和 offsets，
	## 否则 size 停在 (0,0)，绘制正常但点击收不到。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func on_opened() -> void:
	hint_timer = 0.0
	queue_redraw()


func show_tab(t: int) -> void:
	tab = t
	queue_redraw()


func _flash_hint(text: String) -> void:
	hint_text = text
	hint_timer = 2.6
	queue_redraw()


func _process(delta: float) -> void:
	if hint_timer > 0.0:
		hint_timer = maxf(hint_timer - delta, 0.0)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B, KEY_ESCAPE:
				game.close_loadout()
			KEY_TAB, KEY_Q:
				show_tab(Tab.JUTSU if tab == Tab.WEAPON else Tab.WEAPON)
			KEY_F1:
				## 界面打开时游戏暂停，player._unhandled_input 走不到，这里单独接管
				Flow.toggle_test_mode()
				player.notify_test_mode()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var idx := int(event.keycode) - int(KEY_1)
				if tab == Tab.WEAPON:
					if idx < Player.WEAPON_SLOT_COUNT:
						selected_weapon_slot = idx
				else:
					selected_slot = idx
				queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var p: Vector2 = event.position
	if event.button_index == MOUSE_BUTTON_LEFT:
		for t in [Tab.WEAPON, Tab.JUTSU]:
			if _tab_rect(t).has_point(p):
				show_tab(t)
				return
		if tab == Tab.WEAPON:
			for i in Player.WEAPON_SLOT_COUNT:
				if _weapon_slot_rect(i).has_point(p):
					selected_weapon_slot = i
					queue_redraw()
					return
			for j in Flow.inventory.size():
				if _bag_cell_rect(j).has_point(p):
					_use_bag_cell(j)
					return
		else:
			for i in 5:
				if _slot_rect(i).has_point(p):
					selected_slot = i
					queue_redraw()
					return
			for j in _jutsu_library().size():
				if _grid_rect(j).has_point(p):
					_assign_jutsu(j)
					return
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if tab == Tab.WEAPON:
			for i in Player.WEAPON_SLOT_COUNT:
				if _weapon_slot_rect(i).has_point(p):
					## 手上不能什么都没有：至少还得有另一件忍具兜着
					if _other_weapon_available(i):
						player.equip_sid(i, -1)
					else:
						_flash_hint(Data.s("loadout.keep_one"))
					queue_redraw()
					return
		else:
			for i in 5:
				if _slot_rect(i).has_point(p):
					if i < player.jutsu_slots.size():
						player.jutsu_slots[i] = ""
					queue_redraw()
					return


# ---------------------------------------------------------------- 操作

## 背包里还有别的忍具吗（判断"能不能把这一槽卸掉"）
func _other_weapon_available(slot: int) -> bool:
	var sid := player.weapon_sid_at(slot)
	for st in Flow.inventory:
		if not Data.is_weapon(String(st["id"])):
			continue
		if int(st["sid"]) != sid:
			return true
	return false


## 点背包格：忍具 → 装到选中的武器槽；道具 → 立刻使用
func _use_bag_cell(i: int) -> void:
	if i < 0 or i >= Flow.inventory.size():
		return
	var st: Dictionary = Flow.inventory[i]
	var id := String(st["id"])
	var sid := int(st["sid"])
	if Data.is_weapon(id):
		if player.weapon_sid_at(selected_weapon_slot) == sid:
			## 再点一次同一个格子 = 从槽上摘下来
			if _other_weapon_available(selected_weapon_slot):
				player.equip_sid(selected_weapon_slot, -1)
			else:
				_flash_hint(Data.s("loadout.keep_one"))
		else:
			player.equip_sid(selected_weapon_slot, sid)
			selected_weapon_slot = (selected_weapon_slot + 1) % Player.WEAPON_SLOT_COUNT
	elif Data.is_consumable(id):
		if player.use_item(sid):
			_flash_hint(Data.s("hud.used_item") % Data.item_name(id))
		elif player.hp >= player.max_hp and player.chakra >= player.max_chakra:
			_flash_hint(Data.s("hud.item_full"))
		else:
			_flash_hint(Data.s("hud.nothing_to_use"))
	queue_redraw()


## 已学会的忍术（忍术库）。当前所有忍术默认都解锁，将来加「卷轴 / 请教」学习线时这里自动收窄。
func _jutsu_library() -> Array:
	if Flow.unlocked_jutsu.is_empty():
		return Data.jutsu_list
	var out: Array = []
	for id in Data.jutsu_list:
		if Flow.unlocked_jutsu.has(id):
			out.append(id)
	return out


func _assign_jutsu(index: int) -> void:
	if selected_slot >= player.slots_unlocked():
		return
	var lib := _jutsu_library()
	if index < 0 or index >= lib.size():
		return
	var id: String = lib[index]
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


func _tab_rect(t: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + TAB_X + float(t) * (TAB_W + 10.0), p.position.y + TAB_Y, TAB_W, TAB_H)


func _slot_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 26.0, p.position.y + HEADER_H + float(i) * SLOT_GAP, 200.0, SLOT_H)


func _grid_rect(j: int) -> Rect2:
	var p := _panel_rect()
	var col := j % 2
	var row := int(j / 2.0)
	return Rect2(
		p.position.x + 252.0 + float(col) * (CARD_W + 12.0),
		p.position.y + HEADER_H + float(row) * CARD_GAP,
		CARD_W, CARD_H
	)


func _weapon_slot_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 26.0, p.position.y + HEADER_H + float(i) * (WSLOT_H + WSLOT_GAP), WSLOT_W, WSLOT_H)


func _bag_cell_rect(i: int) -> Rect2:
	var p := _panel_rect()
	var col := i % BAG_COLS
	var row := int(i / float(BAG_COLS))
	return Rect2(
		p.position.x + BAG_X + float(col) * (CELL + CELL_GAP),
		p.position.y + BAG_Y + float(row) * (CELL + CELL_GAP),
		CELL, CELL
	)


func _bottom_hint() -> String:
	return Data.s("loadout.hint_weapon") if tab == Tab.WEAPON else Data.s("loadout.hint")


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
	draw_string(font, Vector2(p.position.x + 26.0, p.position.y + 42.0), Data.s("loadout.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f0ece3"))
	draw_string(font, Vector2(p.position.x + 240.0, p.position.y + 42.0), "Lv.%d %s" % [player.level, Data.s(player.rank_key())], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e0c447"))
	draw_string(font, Vector2(p.position.x, p.position.y + 42.0), "%s %d 两" % [Data.s("hud.money"), Flow.money],
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 26.0, 14, Color("e0c447"))
	if Flow.test_unlock_all:
		draw_string(font, Vector2(p.position.x, p.position.y + 68.0), Data.s("loadout.test_on"),
			HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 26.0, 12, Color(1.0, 0.62, 0.3))
	_draw_tabs(font)
	if tab == Tab.WEAPON:
		_draw_weapon_slots(font)
		_draw_bag(font, p)
	else:
		_draw_slots(font)
		_draw_grid(font)
	_draw_footer(font, p)


func _draw_tabs(font: Font) -> void:
	var names := [Data.s("loadout.tab_weapon"), Data.s("loadout.tab_jutsu")]
	for t in [Tab.WEAPON, Tab.JUTSU]:
		var r := _tab_rect(t)
		var on: bool = t == tab
		draw_rect(r, Color(0.3, 0.26, 0.16) if on else Color(0.13, 0.13, 0.16))
		draw_rect(r, Color(1.0, 0.82, 0.35) if on else Color(0.34, 0.34, 0.38), false, 2.0 if on else 1.0)
		draw_string(font, r.position + Vector2(14.0, 23.0), String(names[t]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f0ece3") if on else Color(0.66, 0.66, 0.7))


func _draw_footer(font: Font, p: Rect2) -> void:
	var ty := p.end.y - 20.0
	if hint_timer > 0.0:
		draw_string(font, Vector2(p.position.x + 26.0, ty), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.45))
	else:
		draw_string(font, Vector2(p.position.x + 26.0, ty), _bottom_hint(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b8b2a4"))


func _draw_weapon_slots(font: Font) -> void:
	for i in Player.WEAPON_SLOT_COUNT:
		var r := _weapon_slot_rect(i)
		var id: String = player.weapon_at(i)
		var sel := i == selected_weapon_slot
		var in_use: bool = i == player.active_weapon and not id.is_empty()
		draw_rect(r, Color(0.13, 0.13, 0.16))
		draw_rect(r, Color(1.0, 0.82, 0.35) if sel else Color(0.35, 0.35, 0.38), false, 2.5 if sel else 1.5)
		draw_string(font, r.position + Vector2(12.0, 24.0), "%s %d" % [Data.s("loadout.weapon_slot"), i + 1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f0ece3"))
		if in_use:
			draw_string(font, Vector2(r.position.x, r.position.y + 24.0), Data.s("loadout.in_use"),
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0, 13, Color(0.55, 0.95, 0.6))
		if id.is_empty():
			draw_string(font, r.position + Vector2(12.0, 96.0), Data.s("loadout.empty"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.5, 0.5, 0.52))
			draw_string(font, r.position + Vector2(12.0, 132.0), Data.s("loadout.shop_hint"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.55, 0.6))
			continue
		Data.draw_item_icon(self, id, r.position + Vector2(54.0, 100.0), 32.0)
		draw_string(font, r.position + Vector2(104.0, 86.0), Data.weapon_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("f0ece3"))
		draw_string(font, r.position + Vector2(104.0, 112.0), Data.weapon_mode(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.82, 0.95))
		## 数量（投掷余量）
		draw_string(font, Vector2(r.position.x, r.position.y + 112.0), "x %d" % player.weapon_count(i),
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0, 15, Color("e0c447"))
		## 耐久
		var mx := Data.item_durability(id)
		if mx > 0.0:
			var st := player.weapon_stack(i)
			var ratio := player.weapon_dur_ratio(i)
			var bar := Rect2(r.position.x + 14.0, r.position.y + 176.0, r.size.x - 28.0, 8.0)
			draw_rect(bar, Color(0, 0, 0, 0.65))
			draw_rect(Rect2(bar.position.x + 1.0, bar.position.y + 1.0, (bar.size.x - 2.0) * ratio, 6.0), _dur_color(ratio))
			draw_rect(bar, Color(0.12, 0.12, 0.12, 0.9), false, 1.0)
			draw_string(font, Vector2(r.position.x + 14.0, r.position.y + 170.0),
				"%s %d / %d" % [Data.s("weapon.stat.durability"), int(round(float(st.get("dur", 0.0)))), int(mx)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.74))
		var slot_lines: Array = _weapon_stats_lines(id)
		for k in slot_lines.size():
			draw_string(font, r.position + Vector2(14.0, 138.0 + float(k) * 18.0), String(slot_lines[k]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.66, 0.7))


func _dur_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.45, 0.85, 0.5)
	if ratio > 0.25:
		return Color(0.92, 0.8, 0.35)
	return Color(0.9, 0.4, 0.35)


## 背包：6 × 4 格。忍具 / 道具用同一套格子，堆叠数量与耐久都画在格子里。
func _draw_bag(font: Font, p: Rect2) -> void:
	draw_string(font, Vector2(p.position.x + BAG_X, p.position.y + BAG_Y - 12.0),
		"%s · %s" % [Data.s("bag.title"), Data.s("bag.usage") % [Flow.inv_used(), Flow.INV_SLOTS]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f0ece3"))
	for i in Flow.INV_SLOTS:
		var r := _bag_cell_rect(i)
		draw_rect(r, Color(0.11, 0.11, 0.13))
		draw_rect(r, Color(0.28, 0.28, 0.31), false, 1.0)
		if i >= Flow.inventory.size():
			continue
		var st: Dictionary = Flow.inventory[i]
		var id := String(st["id"])
		var sid := int(st["sid"])
		## 装在哪个槽上：左上角标 1 / 2
		for s in Player.WEAPON_SLOT_COUNT:
			if player.weapon_sid_at(s) == sid:
				draw_rect(Rect2(r.position, Vector2(20.0, 20.0)), Color(0.95, 0.78, 0.35))
				draw_string(font, r.position + Vector2(6.0, 16.0), str(s + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.15, 0.12, 0.06))
		Data.draw_item_icon(self, id, r.position + Vector2(CELL / 2.0, 32.0), 20.0)
		var nm := Data.item_name(id)
		draw_string(font, Vector2(r.position.x, r.position.y + 66.0), nm,
			HORIZONTAL_ALIGNMENT_CENTER, CELL, 12, Color("f0ece3"))
		var cnt := int(st["count"])
		if cnt > 1:
			draw_string(font, Vector2(r.position.x, r.position.y + 84.0), "x%d" % cnt,
				HORIZONTAL_ALIGNMENT_RIGHT, CELL - 6.0, 13, Color("e0c447"))
		var mx := Data.item_durability(id)
		if mx > 0.0:
			var ratio := clampf(float(st.get("dur", 0.0)) / mx, 0.0, 1.0)
			var bar := Rect2(r.position.x + 8.0, r.end.y - 9.0, CELL - 16.0, 5.0)
			draw_rect(bar, Color(0, 0, 0, 0.7))
			draw_rect(Rect2(bar.position.x + 1.0, bar.position.y + 1.0, (bar.size.x - 2.0) * ratio, 3.0), _dur_color(ratio))
		elif cnt <= 1:
			draw_string(font, Vector2(r.position.x, r.position.y + 84.0), Data.s("bag.use") if Data.is_consumable(id) else "",
				HORIZONTAL_ALIGNMENT_RIGHT, CELL - 6.0, 11, Color(0.6, 0.85, 0.65))


## 忍具数值：最多两行（近战一行、投掷一行）
func _weapon_stats_lines(id: String) -> Array:
	var w: Dictionary = Data.weapon(id)
	var out: Array = []
	if bool(w.get("can_melee", false)):
		out.append("%s ×%.2f · %s ×%.2f · %s ×%.2f" % [
			Data.s("weapon.stat.melee"), float(w.get("melee_damage_mult", 1.0)),
			Data.s("weapon.stat.range"), float(w.get("melee_range_mult", 1.0)),
			Data.s("weapon.stat.speed"), float(w.get("attack_speed_mult", 1.0)),
		])
	if bool(w.get("can_throw", false)):
		out.append("%s %d" % [Data.s("weapon.stat.throw"), int(w.get("throw_damage", 0))])
	return out


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
	var lib := _jutsu_library()
	for j in lib.size():
		var id: String = lib[j]
		var cfg: Dictionary = Data.jutsu.get(id, {})
		var r := _grid_rect(j)
		var equipped := Array(player.jutsu_slots).has(id)
		draw_rect(r, Color(0.16, 0.16, 0.19) if not equipped else Color(0.2, 0.22, 0.26))
		draw_rect(r, Color(0.95, 0.78, 0.35) if equipped else Color(0.3, 0.3, 0.33), false, 2.0 if equipped else 1.0)
		Data.draw_jutsu_icon(self, id, r.position + Vector2(34.0, CARD_H / 2.0), 19.0)
		draw_string(font, r.position + Vector2(68.0, 25.0), Data.s(String(cfg.get("name_key", id))), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f0ece3"))
		draw_string(font, r.position + Vector2(68.0, 47.0), _detail(id, cfg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.66, 0.66, 0.7))
		## 右对齐标记：x 给卡片左边、width 给到右边界（draw_string 只在 width > 0 时才右对齐）
		draw_string(font, Vector2(r.position.x, r.position.y + 24.0), "RANK " + String(cfg.get("rank", "-")), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0, 11, Color(0.72, 0.6, 0.35))
		if equipped:
			draw_string(font, Vector2(r.position.x, r.position.y + 47.0), "ON", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0, 12, Color(0.95, 0.8, 0.35))


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
