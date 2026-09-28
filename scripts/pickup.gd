class_name Pickup
extends Node2D
## 可拾取物：情报卷轴（任务）/ 回力药 / 查克拉药。
## 玩家走近自动拾取，有轻微悬浮动画。药品是**进背包**（不当场生效），背包满了就留在地上。

var kind := "hp"
var name_key := "pickup.hp"
var age := 0.0
var collected := false
## 背包满时的提示节流
var notice_cd := 0.0
var game


static func create(parent: Node, pos: Vector2, kind_name: String, game_node) -> Pickup:
	var p := Pickup.new()
	p.kind = kind_name
	p.game = game_node
	match kind_name:
		"hp":
			p.name_key = "pickup.hp"
		"chakra":
			p.name_key = "pickup.chakra"
		"intel":
			p.name_key = "pickup.intel"
	p.position = pos
	parent.add_child(p)
	return p


func _ready() -> void:
	add_to_group("pickups")


func _process(delta: float) -> void:
	if collected:
		return
	notice_cd = maxf(notice_cd - delta, 0.0)
	age += delta
	var arr := get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return
	var pl = arr[0]
	if pl.dead:
		return
	if global_position.distance_to(pl.global_position) <= 26.0:
		_collect(pl)
	queue_redraw()


func _collect(pl) -> void:
	if kind != "intel":
		## 药品进背包，等玩家自己用（F 键或背包里点一下）
		var item_id := "heal_pill" if kind == "hp" else "chakra_pill"
		if Flow.inv_add(item_id, 1) <= 0:
			if notice_cd <= 0.0:
				notice_cd = 1.5
				if game != null and game.hud != null:
					game.hud.show_notice(Data.s("hud.bag_full"))
			return
	collected = true
	if kind == "intel":
		game.on_intel_collected()
	Fx.burst(game.fx_container, global_position, _color(), 8, 150.0)
	queue_free()


func _color() -> Color:
	match kind:
		"hp":
			return Color(0.45, 0.9, 0.5)
		"chakra":
			return Color(0.4, 0.65, 1.0)
		_:
			return Color(0.95, 0.85, 0.45)


func _draw() -> void:
	var bob := sin(age * 3.0) * 3.0
	var c := _color()
	var y := -10.0 + bob
	if kind == "intel":
		## 竖直光柱（远处可见）：下宽上窄的梯形 + 地面光圈，轻微脉动
		var pulse := 0.65 + 0.35 * sin(age * 3.0)
		var h := 72.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-8, y), Vector2(8, y), Vector2(2.5, y - h), Vector2(-2.5, y - h),
		]), Color(1.0, 0.85, 0.4, 0.22 * pulse))
		draw_arc(Vector2(0, 2), 14.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.5 * pulse), 2.0)
		## 卷轴：竖长条 + 上下两个端头
		draw_rect(Rect2(-4.0, y - 6.0, 8.0, 12.0), Color(0.92, 0.88, 0.75))
		draw_rect(Rect2(-4.0, y - 6.0, 8.0, 12.0), Color(0.4, 0.35, 0.25, 0.9), false, 1.0)
		draw_circle(Vector2(0.0, y - 7.0), 2.5, c)
		draw_circle(Vector2(0.0, y + 7.0), 2.5, c)
	else:
		## 药瓶：圆底 + 瓶颈
		draw_circle(Vector2(0.0, y + 1.0), 6.5, c)
		draw_rect(Rect2(-2.0, y - 9.0, 4.0, 5.0), c.darkened(0.25))
		draw_circle(Vector2(-2.0, y - 1.0), 1.5, Color(1, 1, 1, 0.8))
	draw_arc(Vector2(0.0, y), 12.0, age * 2.0, age * 2.0 + TAU * 0.55, 10, Color(c.r, c.g, c.b, 0.35), 1.0)
