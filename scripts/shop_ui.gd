class_name ShopUi
extends Control
## 忍具店：走到忍具店门口按 E 打开（打开时游戏暂停）。
## 四种忍具的价格 / 数值全部来自 data/weapon.json，本文件不写死任何数字。
## 买到的忍具自动进背包，并自动装进第一个空的武器槽；要换槽位按 B 打开装备界面。

var game

const PANEL_W := 780.0
const PANEL_H := 596.0
const HEADER_H := 96.0
const ROW_H := 106.0
const ROW_GAP := 112.0
const BTN_W := 116.0
const BTN_H := 42.0

var hint_text := ""
var hint_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	## 父节点是 CanvasLayer，必须 anchors + offsets 一起设，否则 size 停在 (0,0)、点击收不到
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func on_opened() -> void:
	hint_text = ""
	hint_timer = 0.0
	queue_redraw()


func show_hint(text: String) -> void:
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
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_B:
			game.close_shop()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = event.position
	for i in Data.weapon_list.size():
		if _row_rect(i).has_point(p):
			game.buy_weapon(String(Data.weapon_list[i]))
			return


func _panel_rect() -> Rect2:
	var v := get_viewport_rect().size
	return Rect2((v.x - PANEL_W) / 2.0, (v.y - PANEL_H) / 2.0, PANEL_W, PANEL_H)


func _row_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 26.0, p.position.y + HEADER_H + float(i) * ROW_GAP, PANEL_W - 52.0, ROW_H)


func _buy_rect(i: int) -> Rect2:
	var r := _row_rect(i)
	return Rect2(r.end.x - BTN_W - 14.0, r.position.y + (r.size.y - BTN_H) / 2.0, BTN_W, BTN_H)


func weapon_stats(id: String) -> String:
	var w: Dictionary = Data.weapon(id)
	var parts: Array = []
	if bool(w.get("can_melee", false)):
		parts.append("%s ×%.2f" % [Data.s("weapon.stat.melee"), float(w.get("melee_damage_mult", 1.0))])
		parts.append("%s ×%.2f" % [Data.s("weapon.stat.range"), float(w.get("melee_range_mult", 1.0))])
		parts.append("%s ×%.2f" % [Data.s("weapon.stat.speed"), float(w.get("attack_speed_mult", 1.0))])
	if bool(w.get("can_throw", false)):
		parts.append("%s %d" % [Data.s("weapon.stat.throw"), int(w.get("throw_damage", 0))])
		parts.append("%s %d / %s %.1fs" % [
			Data.s("weapon.stat.ammo"), int(w.get("throw_max", 0)),
			Data.s("weapon.stat.recharge"), float(w.get("throw_recharge", 0.0)),
		])
	return " · ".join(PackedStringArray(parts))


func _draw() -> void:
	var font := Data.font()
	var v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.03, 0.03, 0.05, 0.74))
	var p := _panel_rect()
	draw_rect(p, Color("2a2620"))
	draw_rect(p, Color(0.85, 0.72, 0.4), false, 2.0)
	draw_string(font, p.position + Vector2(26.0, 46.0), Data.s("shop.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f0ece3"))
	## 右对齐必须给 width（draw_string 只在 width > 0 时应用 alignment）
	draw_string(font, Vector2(p.position.x, p.position.y + 46.0),
		"%s %d 两 · %s %d 件" % [Data.s("hud.money"), Flow.money, Data.s("loadout.owned"), Flow.owned_weapons.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 26.0, 15, Color("e0c447"))
	for i in Data.weapon_list.size():
		_draw_row(font, i, String(Data.weapon_list[i]))
	var footer := hint_text if hint_timer > 0.0 else Data.s("shop.hint")
	var fcol := Color(1.0, 0.85, 0.45) if hint_timer > 0.0 else Color("b8b2a4")
	draw_string(font, Vector2(p.position.x + 26.0, p.end.y - 22.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fcol)


func _draw_row(font: Font, i: int, id: String) -> void:
	var w: Dictionary = Data.weapon(id)
	var r := _row_rect(i)
	var owned := Flow.owns_weapon(id)
	var price := int(w.get("price", 0))
	var afford := Flow.money >= price
	draw_rect(r, Color(0.17, 0.15, 0.12) if not owned else Color(0.15, 0.17, 0.14))
	draw_rect(r, Color(0.45, 0.38, 0.25) if not owned else Color(0.35, 0.5, 0.34), false, 1.5)
	Data.draw_weapon_icon(self, id, r.position + Vector2(52.0, r.size.y / 2.0), 30.0)
	draw_string(font, r.position + Vector2(104.0, 30.0), Data.weapon_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f0ece3"))
	draw_string(font, r.position + Vector2(104.0, 54.0), Data.weapon_mode(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.82, 0.95))
	draw_string(font, r.position + Vector2(104.0, 76.0), Data.s(String(w.get("desc_key", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.68, 0.68, 0.72))
	draw_string(font, r.position + Vector2(104.0, 96.0), weapon_stats(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.78, 0.82))
	## 价格
	draw_string(font, Vector2(r.position.x + 104.0, r.position.y + 96.0), "",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var btn := _buy_rect(i)
	var can_buy := not owned and afford
	draw_rect(btn, Color(0.62, 0.46, 0.2) if can_buy else Color(0.22, 0.21, 0.2))
	draw_rect(btn, Color(0.95, 0.85, 0.6) if can_buy else Color(0.4, 0.4, 0.42), false, 1.5)
	var label := Data.s("shop.owned") if owned else Data.s("shop.buy")
	var lcol := Color(0.6, 0.85, 0.62) if owned else (Color("fff6e0") if afford else Color(0.55, 0.5, 0.45))
	draw_string(font, btn.position + Vector2(24.0, 28.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, lcol)
	## 价格放在按钮上方，未拥有时按买得起 / 买不起分色
	var pcol := Color("e0c447") if afford else Color(0.85, 0.45, 0.4)
	draw_string(font, Vector2(btn.end.x - 80.0, btn.position.y - 6.0),
		Data.s("shop.price") % price, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pcol)
