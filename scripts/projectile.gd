class_name Projectile
extends Node2D
## 通用投射物（苦无 / 小火弹 / 豪火球 / 敌人苦无）。
## 手动距离检测，不依赖物理碰撞。
## hostile=false → 只伤害 enemies 组；hostile=true → 只伤害玩家。

var velocity := Vector2.ZERO
var lifetime := 1.5
var age := 0.0
var damage := 0.0
var knockback := 150.0
var hit_radius := 6.0
var aoe_radius := 0.0
var burn_dps := 0.0
var burn_duration := 0.0
var color := Color.WHITE
var kind := "kunai"
var hostile := false
var game


static func create(parent: Node, pos: Vector2, dir: Vector2, cfg: Dictionary) -> void:
	var p := Projectile.new()
	p.position = pos
	p.velocity = dir * float(cfg.get("speed", 500.0))
	p.lifetime = float(cfg.get("lifetime", 1.5))
	p.damage = float(cfg.get("damage", 0.0))
	p.knockback = float(cfg.get("knockback", 150.0))
	p.hit_radius = float(cfg.get("hit_radius", 6.0))
	p.aoe_radius = float(cfg.get("aoe_radius", 0.0))
	p.burn_dps = float(cfg.get("burn_dps", 0.0))
	p.burn_duration = float(cfg.get("burn_duration", 0.0))
	p.color = cfg.get("color", Color.WHITE)
	p.kind = String(cfg.get("kind", "kunai"))
	p.hostile = bool(cfg.get("hostile", false))
	p.game = cfg.get("game", null)
	parent.add_child(p)


func _physics_process(delta: float) -> void:
	age += delta
	if age > lifetime:
		_puff()
		return
	position += velocity * delta
	if game != null and (_out_of_arena() or game.pos_blocked(position)):
		if kind == "fireball":
			_explode()
		else:
			_puff()
		return
	if hostile:
		_check_player_hit()
	else:
		_check_enemy_hit()


func _check_enemy_hit() -> void:
	var hit_enemy = null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) <= hit_radius + enemy.hit_radius:
			hit_enemy = enemy
			break
	if hit_enemy != null:
		if kind == "fireball":
			_explode()
		else:
			hit_enemy.take_damage(damage, velocity.normalized() * knockback)
			_puff()


func _check_player_hit() -> void:
	var arr := get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return
	var p = arr[0]
	if p.dead:
		return
	if global_position.distance_to(p.global_position) <= hit_radius + 16.0:
		p.take_damage(damage, velocity.normalized() * knockback)
		_puff()


func _out_of_arena() -> bool:
	var s: Vector2 = game.ARENA_SIZE
	return position.x < 0.0 or position.y < 0.0 or position.x > s.x or position.y > s.y


func _explode() -> void:
	var center := global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var d: float = center.distance_to(enemy.global_position)
		if d <= aoe_radius + enemy.hit_radius:
			var falloff := 1.0 - clampf((d - enemy.hit_radius) / maxf(aoe_radius, 1.0), 0.0, 1.0) * 0.5
			var dir: Vector2 = (enemy.global_position - center).normalized()
			if dir == Vector2.ZERO:
				dir = velocity.normalized()
			enemy.take_damage(damage * falloff, dir * knockback)
			if burn_dps > 0.0:
				enemy.apply_burn(burn_dps, burn_duration)
	Fx.burst(game.fx_container, center, Color(1.0, 0.6, 0.25, 0.95), 10, 220.0)
	Fx.burst(game.fx_container, center, Color(1.0, 0.9, 0.5, 0.9), 6, 120.0)
	game.hitstop(0.05)
	queue_free()


func _puff() -> void:
	var c := color
	c.a = 0.6
	Fx.burst(game.fx_container, global_position, c, 4, 90.0)
	queue_free()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if kind == "kunai":
		var dir := velocity.normalized()
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			dir * 9.0, -dir * 5.0 + perp * 3.0, -dir * 5.0 - perp * 3.0,
		]), color)
	else:
		draw_circle(Vector2.ZERO, hit_radius, color)
		draw_circle(Vector2.ZERO, hit_radius * 0.55, Color(1.0, 0.95, 0.7, 0.9))
		var flicker := 1.0 + 0.15 * sin(age * 30.0)
		draw_arc(Vector2.ZERO, hit_radius + 3.0 * flicker, 0.0, TAU, 16, Color(1.0, 0.4, 0.15, 0.5), 2.0)
