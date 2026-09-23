class_name EnemyChaser
extends EnemyBase
## 追击型敌人：巡逻 → 追击 → 预警(感叹号) → 挥击 → 硬直。
## 攻击前有 0.45 秒黄色预警，可被玩家打断（受击进入硬直）。

enum S { PATROL, CHASE, WINDUP, RECOVER }

const AGGRO_RANGE := 270.0
const ATTACK_RANGE := 54.0
const ATTACK_WINDUP := 0.45
const ATTACK_RECOVER := 0.75
const ATTACK_DAMAGE := 9.0
const ATTACK_KNOCKBACK := 260.0
const ATTACK_ARC := deg_to_rad(85.0)
const PATROL_SPEED := 55.0
const CHASE_SPEED := 175.0

var state := S.PATROL
var state_timer := 0.0
var patrol_dir := Vector2.RIGHT
var patrol_next := 0.0
var attack_dir := Vector2.RIGHT


func _init() -> void:
	max_hp = 70.0
	hit_radius = 18.0
	move_speed = CHASE_SPEED
	body_color = Color("b0483c")
	body_size = Vector2(30, 30)


func take_damage(amount: float, knockback: Vector2) -> void:
	super.take_damage(amount, knockback)
	if not dead and state == S.PATROL:
		state = S.CHASE


func _tick(delta: float) -> void:
	var player = _player()
	if player == null:
		return
	telegraph = 0.0
	match state:
		S.PATROL:
			state_timer += delta
			if state_timer >= patrol_next:
				state_timer = 0.0
				patrol_next = randf_range(1.2, 2.8)
				patrol_dir = Vector2.from_angle(randf() * TAU)
			position += patrol_dir * PATROL_SPEED * delta
			if stagger_timer <= 0.0 and global_position.distance_to(player.global_position) < AGGRO_RANGE:
				state = S.CHASE
		S.CHASE:
			if stagger_timer > 0.0:
				return
			var to_p: Vector2 = player.global_position - global_position
			var desired := to_p.normalized() * CHASE_SPEED
			desired += _separation()
			position += desired * delta
			if to_p.length() <= ATTACK_RANGE:
				state = S.WINDUP
				state_timer = ATTACK_WINDUP
				attack_dir = to_p.normalized()
		S.WINDUP:
			state_timer -= delta
			telegraph = 1.0 - clampf(state_timer / ATTACK_WINDUP, 0.0, 1.0)
			attack_dir = (player.global_position - global_position).normalized()
			if stagger_timer > 0.0:
				state = S.CHASE
			elif state_timer <= 0.0:
				_strike(player)
				state = S.RECOVER
				state_timer = ATTACK_RECOVER
		S.RECOVER:
			state_timer -= delta
			if state_timer <= 0.0:
				state = S.CHASE


func _strike(player) -> void:
	var to_p: Vector2 = player.global_position - global_position
	if to_p.length() <= ATTACK_RANGE + 14.0 and absf(attack_dir.angle_to(to_p)) <= ATTACK_ARC:
		player.take_damage(ATTACK_DAMAGE, attack_dir * ATTACK_KNOCKBACK)
	Fx.burst(game.fx_container, global_position + attack_dir * 30.0, Color(1.0, 0.8, 0.5, 0.9), 5, 120.0)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > 0.01 and d < 44.0:
			push += (global_position - other.global_position).normalized() * (44.0 - d) * 4.0
	return push


func _player():
	var arr := get_tree().get_nodes_in_group("player")
	return arr[0] if arr.size() > 0 else null
