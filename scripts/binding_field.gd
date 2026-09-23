class_name BindingField
extends Node2D
## 封缚印：坐标选择的封印领域。
## 施放瞬间定身范围内所有敌人，领域存在期间持续压制范围内的敌人。

var game
var radius := 85.0
var lifetime := 3.0
var root_duration := 3.0
var age := 0.0


static func create(parent: Node, pos: Vector2, cfg: Dictionary, game_node) -> BindingField:
	var f := BindingField.new()
	f.game = game_node
	f.radius = float(cfg.get("seal_radius", 85.0))
	f.lifetime = float(cfg.get("root_duration", 3.0))
	f.root_duration = f.lifetime
	f.position = pos
	parent.add_child(f)
	return f


func _ready() -> void:
	add_to_group("fields")
	## 起手瞬间把范围内的敌人全部钉住
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) <= radius + enemy.hit_radius:
			enemy.apply_root(root_duration)
	Fx.burst(game.fx_container, global_position, Color(0.72, 0.5, 1.0, 0.9), 14, 220.0)


func _process(delta: float) -> void:
	age += delta
	## 领域存续期间，进入范围的敌人持续被压制
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) <= radius + enemy.hit_radius:
			enemy.apply_root(0.2)
	if age >= lifetime:
		Fx.burst(game.fx_container, global_position, Color(0.72, 0.5, 1.0, 0.6), 6, 120.0)
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(1.0 - age / lifetime, 0.0, 1.0)
	var a: float = 0.35 + 0.65 * t
	draw_circle(Vector2.ZERO, radius, Color(0.45, 0.28, 0.72, 0.16 * a + 0.06))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 44, Color(0.75, 0.55, 1.0, 0.85 * a), 2.5)
	draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 36, Color(0.6, 0.4, 0.9, 0.55 * a), 1.5)
	## 内部竖排符文刻度（程序化，不用素材）
	var spokes := 8
	for i in spokes:
		var ang := age * 1.2 + TAU * float(i) / float(spokes)
		var inner := Vector2.from_angle(ang) * radius * 0.35
		var outer := Vector2.from_angle(ang) * radius * 0.95
		draw_line(inner, outer, Color(0.8, 0.6, 1.0, 0.4 * a), 1.5)
	draw_arc(Vector2.ZERO, radius * 0.28, 0.0, TAU, 20, Color(0.85, 0.7, 1.0, 0.7 * a), 2.0)
