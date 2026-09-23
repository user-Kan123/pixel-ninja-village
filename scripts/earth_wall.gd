class_name EarthWall
extends StaticBody2D
## 土流壁：坐标选择施放的短时墙体。
## 轴向对齐（长边垂直于施法方向），阻挡玩家与敌人移动，可被敌人啃咬破坏。
## 耐久归零或存活时间到期后消失。

var game
var hp := 90.0
var max_hp := 90.0
var lifetime := 12.0
var age := 0.0
var box := Rect2()
var flash := 0.0


static func create(parent: Node, pos: Vector2, cast_dir: Vector2, cfg: Dictionary, game_node) -> EarthWall:
	var w := EarthWall.new()
	w.game = game_node
	w.max_hp = float(cfg.get("wall_hp", 90.0))
	w.hp = w.max_hp
	w.lifetime = float(cfg.get("wall_lifetime", 12.0))
	var length := float(cfg.get("wall_length", 150.0))
	var thickness := float(cfg.get("wall_thickness", 26.0))
	## 长边垂直于施法方向，切向按主轴取整（保证轴对齐）
	var perp := Vector2(-cast_dir.y, cast_dir.x)
	if absf(perp.x) >= absf(perp.y):
		w.box = Rect2(-length / 2.0, -thickness / 2.0, length, thickness)
	else:
		w.box = Rect2(-thickness / 2.0, -length / 2.0, thickness, length)
	w.position = pos
	parent.add_child(w)
	return w


func _ready() -> void:
	add_to_group("walls")
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = box.size
	col.shape = shape
	add_child(col)
	game.register_wall(self)
	Fx.burst(game.fx_container, global_position, Color(0.55, 0.45, 0.32, 0.9), 8, 150.0)


func _physics_process(delta: float) -> void:
	age += delta
	flash = maxf(flash - delta, 0.0)
	## 敌人贴墙时啃咬墙体
	var world_box := Rect2(global_position + box.position, box.size)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var ep: Vector2 = enemy.global_position
		if world_box.grow(enemy.hit_radius + 4.0).has_point(ep):
			_push_out(enemy, world_box)
			damage(14.0 * delta)
	if age >= lifetime or hp <= 0.0:
		_collapse()
	queue_redraw()


func _push_out(enemy: Node2D, world_box: Rect2) -> void:
	## 把敌人推到墙体最近的外侧
	var ep: Vector2 = enemy.global_position
	var d := [
		absf(ep.x - world_box.position.x),
		absf(ep.x - world_box.end.x),
		absf(ep.y - world_box.position.y),
		absf(ep.y - world_box.end.y),
	]
	var m: float = d[0]
	for v in d:
		m = minf(m, v)
	var pad: float = float(enemy.hit_radius) + 5.0
	if m == d[0]:
		ep.x = world_box.position.x - pad
	elif m == d[1]:
		ep.x = world_box.end.x + pad
	elif m == d[2]:
		ep.y = world_box.position.y - pad
	else:
		ep.y = world_box.end.y + pad
	enemy.position = ep


func damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if amount >= 5.0:
		flash = 0.1


func _collapse() -> void:
	if game != null:
		game.unregister_wall(self)
	Fx.burst(game.fx_container, global_position, Color(0.6, 0.5, 0.35, 0.9), 12, 200.0)
	queue_free()


func _draw() -> void:
	var col := Color("6b5738") if flash <= 0.0 else Color(0.85, 0.75, 0.55)
	draw_rect(box, col)
	draw_rect(box.grow(-3.0), col.darkened(0.18))
	## 分段砖块纹理
	var seg := 24.0
	if box.size.x > box.size.y:
		var n := int(box.size.x / seg)
		for i in range(1, n):
			var x := box.position.x + i * seg
			draw_line(Vector2(x, box.position.y), Vector2(x, box.end.y), col.darkened(0.35), 1.0)
	else:
		var n2 := int(box.size.y / seg)
		for i in range(1, n2):
			var y := box.position.y + i * seg
			draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), col.darkened(0.35), 1.0)
	draw_rect(box, Color(0.1, 0.09, 0.07, 0.85), false, 2.0)
	var top := box.position.y - 10.0
	draw_rect(Rect2(box.position.x, top, box.size.x, 4.0), Color(0.05, 0.05, 0.05, 0.8))
	draw_rect(Rect2(box.position.x, top, box.size.x * hp / max_hp, 4.0), Color(0.8, 0.65, 0.35))
