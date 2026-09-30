class_name ShopUi
extends Control
## 忍具店：走到忍具店门口按 E 打开（打开时游戏暂停）。
## 卖的东西 = 武器表 + 定价大于 0 的消耗品（兵粮丸）。
## 每一行两个按钮：「买 1」与「买 10」——实际买到的数量受赏金和背包空间双重限制，
## 所以忍具（手里剑 / 苦无）是真的买几个用几个，短刀长剑可以重复买、每把各有耐久。

var game
## "weapon" = 忍具店货架（武器+消耗品）；"food" = 食物店货架（拉面/丸子/饭团）
var mode := "weapon"

const PANEL_W := 800.0
const PANEL_H := 600.0
const HEADER_H := 84.0
const ROW_H := 92.0
const ROW_GAP := 96.0
const BTN_W := 92.0
const BTN_H := 40.0
const BTN_GAP := 10.0

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


func _items() -> Array:
	return Data.food_shop_list() if mode == "food" else Data.shop_list()


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
	var items := _items()
	for i in items.size():
		var id := String(items[i])
		if _buy1_rect(i).has_point(p):
			game.buy_item(id, 1)
			return
		if _buy10_rect(i).has_point(p):
			game.buy_item(id, 10)
			return


# ---------------------------------------------------------------- 布局

func _panel_rect() -> Rect2:
	var v := get_viewport_rect().size
	return Rect2((v.x - PANEL_W) / 2.0, (v.y - PANEL_H) / 2.0, PANEL_W, PANEL_H)


func _row_rect(i: int) -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 24.0, p.position.y + HEADER_H + float(i) * ROW_GAP, PANEL_W - 48.0, ROW_H)


func _buy1_rect(i: int) -> Rect2:
	var r := _row_rect(i)
	return Rect2(r.end.x - BTN_W * 2.0 - BTN_GAP - 12.0, r.position.y + (r.size.y - BTN_H) / 2.0, BTN_W, BTN_H)


func _buy10_rect(i: int) -> Rect2:
	var r := _row_rect(i)
	return Rect2(r.end.x - BTN_W - 12.0, r.position.y + (r.size.y - BTN_H) / 2.0, BTN_W, BTN_H)


# ---------------------------------------------------------------- 文案

func _kind_line(id: String) -> String:
	if Data.is_weapon(id):
		var stack := Data.item_stack(id)
		var parts: Array = [Data.weapon_mode(id)]
		if stack > 1:
			parts.append("%s %d" % [Data.s("weapon.stat.stack"), stack])
		else:
			parts.append(Data.s("bag.not_stackable"))
		var dur := Data.item_durability(id)
		if dur > 0.0:
			parts.append("%s %d" % [Data.s("weapon.stat.durability"), int(dur)])
		var w: Dictionary = Data.weapon(id)
		if bool(w.get("can_throw", false)):
			parts.append("%s %d" % [Data.s("weapon.stat.throw"), int(w.get("throw_damage", 0))])
		return " · ".join(PackedStringArray(parts))
	## 消耗品：写清回复量
	var d: Dictionary = Data.item_def(id)
	var eff: Array = [Data.s("shop.consumable")]
	if float(d.get("heal", 0)) > 0.0:
		eff.append("%s +%d" % [Data.s("item.stat.heal"), int(d.get("heal", 0))])
	if float(d.get("chakra", 0)) > 0.0:
		eff.append("%s +%d" % [Data.s("item.stat.chakra"), int(d.get("chakra", 0))])
	return " · ".join(PackedStringArray(eff))


## 近战倍率一行流（只给近战忍具用；太长会顶到购买按钮，所以单独成行、只放三个数）
func item_stats(id: String) -> String:
	if not Data.is_weapon(id):
		return ""
	var w: Dictionary = Data.weapon(id)
	if not bool(w.get("can_melee", false)):
		return ""
	return "%s ×%.2f · %s ×%.2f · %s ×%.2f" % [
		Data.s("weapon.stat.melee"), float(w.get("melee_damage_mult", 1.0)),
		Data.s("weapon.stat.range"), float(w.get("melee_range_mult", 1.0)),
		Data.s("weapon.stat.speed"), float(w.get("attack_speed_mult", 1.0)),
	]


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var font := Data.font()
	var v := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.03, 0.03, 0.05, 0.74))
	var p := _panel_rect()
	draw_rect(p, Color("2a2620"))
	draw_rect(p, Color(0.85, 0.72, 0.4), false, 2.0)
	draw_string(font, p.position + Vector2(24.0, 44.0), Data.s("shop.food_title") if mode == "food" else Data.s("shop.title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f0ece3"))
	## 右对齐必须给 width（draw_string 只在 width > 0 时应用 alignment）
	draw_string(font, Vector2(p.position.x, p.position.y + 44.0),
		"%s %d 两 · %s" % [Data.s("hud.money"), Flow.money, Data.s("bag.usage") % [Flow.inv_used(), Flow.INV_SLOTS]],
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 24.0, 15, Color("e0c447"))
	var items := _items()
	for i in items.size():
		_draw_row(font, i, String(items[i]))
	var footer := hint_text if hint_timer > 0.0 else Data.s("shop.hint")
	var fcol := Color(1.0, 0.85, 0.45) if hint_timer > 0.0 else Color("b8b2a4")
	draw_string(font, Vector2(p.position.x + 24.0, p.end.y - 18.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fcol)


func _draw_row(font: Font, i: int, id: String) -> void:
	var r := _row_rect(i)
	var price := Data.item_price(id)
	var afford := Flow.money >= price
	var space := Flow.inv_space_for(id)
	draw_rect(r, Color(0.17, 0.15, 0.12))
	draw_rect(r, Color(0.45, 0.38, 0.25), false, 1.5)
	Data.draw_item_icon(self, id, r.position + Vector2(46.0, r.size.y / 2.0), 26.0)
	draw_string(font, r.position + Vector2(88.0, 22.0), Data.item_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("f0ece3"))
	draw_string(font, r.position + Vector2(88.0, 42.0), _kind_line(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.82, 0.95))
	var desc := Data.item_desc(id)
	var stats := item_stats(id)
	draw_string(font, r.position + Vector2(88.0, 62.0), desc, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 12, Color(0.68, 0.68, 0.72))
	if stats != "":
		draw_string(font, r.position + Vector2(88.0, 80.0), stats, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 12, Color(0.78, 0.78, 0.82))
	## 单价：右对齐到按钮左边，别压到按钮上（draw_string 只在 width > 0 时才右对齐）
	var price_w: float = r.size.x - 88.0 - BTN_W * 2.0 - BTN_GAP - 20.0
	draw_string(font, Vector2(r.position.x + 88.0, r.position.y + 22.0), Data.s("shop.price_each") % price,
		HORIZONTAL_ALIGNMENT_RIGHT, price_w, 14,
		Color("e0c447") if afford else Color(0.85, 0.45, 0.4))
	## 两个购买按钮
	var can1 := afford and space >= 1
	var can10 := afford and space >= 1
	_draw_button(font, _buy1_rect(i), Data.s("shop.buy1"), can1)
	_draw_button(font, _buy10_rect(i), Data.s("shop.buy10"), can10)


func _draw_button(font: Font, r: Rect2, label: String, enabled: bool) -> void:
	draw_rect(r, Color(0.62, 0.46, 0.2) if enabled else Color(0.22, 0.21, 0.2))
	draw_rect(r, Color(0.95, 0.85, 0.6) if enabled else Color(0.4, 0.4, 0.42), false, 1.5)
	draw_string(font, Vector2(r.position.x, r.position.y + 27.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color("fff6e0") if enabled else Color(0.55, 0.5, 0.45))
