class_name EnemyBase
extends Node2D
## 敌人基类：血量 / 受击 / 灼烧 / 击退 / 定身 / 混乱 / 血条绘制。
## 移动与攻击逻辑由子类在 _tick() 中实现。
## rooted：被定身（封缚印），完全不能移动。
## confused：被幻术影响，AI 行为替换为随机游走、不会攻击。

var game
var max_hp := 60.0
var hp := 60.0
var hit_radius := 18.0
var move_speed := 0.0
var dead := false
var body_color := Color("b0483c")
var body_size := Vector2(32, 32)
var knockback_velocity := Vector2.ZERO
var flash_timer := 0.0
var stagger_timer := 0.0
var burn_time := 0.0
var burn_dps := 0.0
var telegraph := 0.0
var rooted_timer := 0.0
var confused_timer := 0.0
var xp_value := 8


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp


func take_damage(amount: float, knockback: Vector2) -> void:
	if dead:
		return
	hp -= amount
	flash_timer = 0.12
	if rooted_timer <= 0.0:
		knockback_velocity += knockback
	## 普通敌人受击硬直 0.2s；重型（stagger_resistance>0）压到 0.08s。
	var stagger: float = 0.2 if stagger_resistance() <= 0.0 else 0.08
	stagger_timer = maxf(stagger_timer, stagger)
	if hp <= 0.0:
		hp = 0.0
		_die()


## 重型敌人可覆写：>0 表示受击硬直被压制到该值（更短）。
func stagger_resistance() -> float:
	return 0.0


func apply_root(duration: float) -> void:
	rooted_timer = maxf(rooted_timer, duration)
	knockback_velocity = Vector2.ZERO


func apply_confuse(duration: float) -> void:
	confused_timer = maxf(confused_timer, duration)


func apply_burn(dps: float, duration: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, duration)


func _die() -> void:
	if dead:
		return
	dead = true
	Fx.burst(game.fx_container, global_position, body_color, 10, 240.0)
	game.on_enemy_died(self)
	queue_free()


func _process(delta: float) -> void:
	if dead:
		return
	flash_timer = maxf(flash_timer - delta, 0.0)
	stagger_timer = maxf(stagger_timer - delta, 0.0)
	rooted_timer = maxf(rooted_timer - delta, 0.0)
	confused_timer = maxf(confused_timer - delta, 0.0)
	if burn_time > 0.0:
		burn_time -= delta
		hp -= burn_dps * delta
		if hp <= 0.0:
			hp = 0.0
			_die()
			return
	if rooted_timer > 0.0:
		knockback_velocity = Vector2.ZERO
	else:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
		position += knockback_velocity * delta
	_tick(delta)
	position = game.resolve_static(position)
	queue_redraw()


func _tick(_delta: float) -> void:
	pass


func _draw() -> void:
	var col := body_color
	if flash_timer > 0.0:
		col = Color.WHITE
	if telegraph > 0.0:
		col = col.lerp(Color(1.0, 0.85, 0.2), clampf(telegraph, 0.0, 1.0))
	if confused_timer > 0.0:
		col = col.lerp(Color(0.7, 0.4, 0.9), 0.45)
	var r := Rect2(-body_size / 2.0, body_size)
	draw_rect(r, col)
	draw_rect(r, Color(0.08, 0.08, 0.1, 0.9), false, 2.0)
	var bw := body_size.x + 8.0
	var top := -body_size.y / 2.0 - 12.0
	draw_rect(Rect2(-bw / 2.0, top, bw, 5.0), Color(0.05, 0.05, 0.05, 0.8))
	draw_rect(Rect2(-bw / 2.0, top, bw * hp / max_hp, 5.0), Color(0.85, 0.3, 0.25))
	if burn_time > 0.0:
		draw_circle(Vector2(body_size.x / 2.0 - 2.0, -body_size.y / 2.0 - 18.0), 4.0, Color(1.0, 0.5, 0.15))
	if rooted_timer > 0.0:
		draw_arc(Vector2.ZERO, body_size.x * 0.85, 0.0, TAU, 20, Color(0.75, 0.5, 1.0, 0.85), 2.5)
	if confused_timer > 0.0:
		draw_arc(Vector2(0.0, -body_size.y / 2.0 - 22.0), 5.0, 0.0, TAU * 0.75, 8, Color(0.75, 0.45, 1.0, 0.9), 2.0)
	if telegraph > 0.05:
		draw_string(Data.font(), Vector2(-5.0, top - 8.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.85, 0.2))
