class_name ShadowClone
extends Node2D
## 影分身：召唤物，自动接近最近的敌人并挥刀。
## 不使用物理碰撞；跟随玩家，敌人不会主动攻击分身（原型阶段的简化）。
## 存活时间结束或玩家死亡时消失。

enum S { FOLLOW, CHASE, WINDUP, RECOVER }

var game
var player: Node2D
var offset := Vector2(40.0, 0.0)
var lifetime := 12.0
var age := 0.0
var move_speed := 150.0
var damage := 7.0
var attack_range := 48.0
var windup_time := 0.25
var recover_time := 0.6
var target: Node2D
var state := S.FOLLOW
var state_timer := 0.0
var attack_dir := Vector2.RIGHT
var slash_timer := 0.0


static func create(parent: Node, pos: Vector2, cfg: Dictionary, game_node, owner_player: Node2D, index: int) -> ShadowClone:
	var c := ShadowClone.new()
	c.game = game_node
	c.player = owner_player
	c.lifetime = float(cfg.get("clone_lifetime", 12.0))
	c.move_speed = float(cfg.get("clone_speed", 150.0))
	c.damage = float(cfg.get("clone_damage", 7.0))
	c.attack_range = float(cfg.get("clone_attack_range", 48.0))
	c.windup_time = float(cfg.get("clone_windup", 0.25))
	c.recover_time = float(cfg.get("clone_recover", 0.6))
	c.offset = Vector2.from_angle(TAU * float(index) / 2.0 + PI / 2.0) * 46.0
	c.position = pos
	parent.add_child(c)
	return c


func _ready() -> void:
	add_to_group("clones")
	Fx.burst(game.fx_container, global_position, Color(0.6, 0.8, 1.0, 0.8), 8, 160.0)


func _process(delta: float) -> void:
	age += delta
	slash_timer = maxf(slash_timer - delta, 0.0)
	if age >= lifetime or player == null or player.dead:
		_dismiss()
		return
	_acquire_target()
	match state:
		S.FOLLOW:
			var home: Vector2 = player.global_position + offset
			if global_position.distance_to(home) > 40.0:
				position += (home - global_position).normalized() * move_speed * delta
		S.CHASE:
			if target == null:
				state = S.FOLLOW
			else:
				var to_t: Vector2 = target.global_position - global_position
				attack_dir = to_t.normalized()
				if to_t.length() <= attack_range:
					state = S.WINDUP
					state_timer = windup_time
				else:
					position += attack_dir * move_speed * delta
		S.WINDUP:
			state_timer -= delta
			if target != null:
				attack_dir = (target.global_position - global_position).normalized()
			if state_timer <= 0.0:
				_strike()
				state = S.RECOVER
				state_timer = recover_time
		S.RECOVER:
			state_timer -= delta
			if state_timer <= 0.0:
				state = S.CHASE
	position = game.resolve_point(position, 14.0)
	queue_redraw()


func _acquire_target() -> void:
	var best: Node2D = null
	var best_d := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var d: float = global_position.distance_to(enemy.global_position)
		if d < 340.0 and d < best_d:
			best = enemy
			best_d = d
	target = best
	if target != null and state == S.FOLLOW:
		state = S.CHASE


func _strike() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.dead:
		return
	var to_t: Vector2 = target.global_position - global_position
	if to_t.length() > attack_range + 20.0:
		return
	if absf(attack_dir.angle_to(to_t)) > deg_to_rad(75.0):
		return
	slash_timer = 0.16
	target.take_damage(damage, attack_dir * 90.0)
	game.hitstop(0.025)


func _dismiss() -> void:
	Fx.burst(game.fx_container, global_position, Color(0.6, 0.8, 1.0, 0.55), 6, 140.0)
	queue_free()


func _draw() -> void:
	var fade: float = clampf((lifetime - age) / 1.5, 0.0, 1.0)
	var alpha: float = 0.5 * fade + 0.15
	var col := Color(0.45, 0.72, 1.0, alpha)
	draw_rect(Rect2(-11, -15, 22, 30), col)
	draw_rect(Rect2(-11, -15, 22, 30), Color(0.25, 0.5, 0.85, alpha + 0.2), false, 2.0)
	draw_rect(Rect2(-11, -8, 22, 4), Color(0.9, 0.92, 1.0, alpha + 0.15))
	if state == S.WINDUP:
		var p: float = 1.0 - clampf(state_timer / maxf(windup_time, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, attack_range, -PI / 2.0, -PI / 2.0 + TAU * p, 20, Color(0.75, 0.92, 1.0, 0.8), 2.0)
	if slash_timer > 0.0:
		var t: float = clampf(slash_timer / 0.16, 0.0, 1.0)
		var a0 := attack_dir.angle()
		draw_arc(Vector2.ZERO, attack_range * 0.9, a0 - 0.7, a0 + 0.7, 12, Color(0.85, 0.95, 1.0, t * 0.85), 3.0)
