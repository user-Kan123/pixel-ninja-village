class_name EnemyBrute
extends EnemyBase
## 重型敌人：缓慢逼近，大范围蓄力横扫（0.8 秒预警），伤害与击飞都很高。
## 受击硬直被大幅压制（几乎打不断），需要用走位或定身/幻术应对。

enum S { PATROL, CHASE, WINDUP, SWING, RECOVER }

const AGGRO_RANGE := 340.0
const ATTACK_RANGE := 78.0
const ATTACK_WINDUP := 0.8
const ATTACK_RECOVER := 1.15
const ATTACK_DAMAGE := 22.0
const ATTACK_KNOCKBACK := 560.0
const ATTACK_ARC := deg_to_rad(115.0)
const PATROL_SPEED := 35.0
const CHASE_SPEED := 108.0
const SWING_LUNGE := 210.0


var state := S.PATROL
var state_timer := 0.0
var patrol_dir := Vector2.RIGHT
var patrol_next := 0.0
var attack_dir := Vector2.RIGHT
var swing_phase := 0


func _init() -> void:
	max_hp = 190.0
	hit_radius = 26.0
	move_speed = CHASE_SPEED
	body_color = Color("6b3f8f")
	body_size = Vector2(46, 46)
	xp_value = 30


func stagger_resistance() -> float:
	return 1.0


func take_damage(amount: float, knockback: Vector2) -> void:
	super.take_damage(amount, knockback)
	if not dead and state == S.PATROL:
		state = S.CHASE


func _tick(delta: float) -> void:
	var player = _player()
	if player == null:
		return
	telegraph = 0.0
	if confused_timer > 0.0:
		_wander(delta)
		return
	match state:
		S.PATROL:
			state_timer += delta
			if state_timer >= patrol_next:
				state_timer = 0.0
				patrol_next = randf_range(1.6, 3.4)
				patrol_dir = Vector2.from_angle(randf() * TAU)
			if rooted_timer <= 0.0:
				position += patrol_dir * PATROL_SPEED * delta
			if global_position.distance_to(player.global_position) < AGGRO_RANGE:
				state = S.CHASE
		S.CHASE:
			var to_p: Vector2 = player.global_position - global_position
			if rooted_timer <= 0.0 and stagger_timer <= 0.0:
				position += to_p.normalized() * CHASE_SPEED * delta
			if to_p.length() <= ATTACK_RANGE:
				state = S.WINDUP
				state_timer = ATTACK_WINDUP
				attack_dir = to_p.normalized()
		S.WINDUP:
			state_timer -= delta
			telegraph = 1.0 - clampf(state_timer / ATTACK_WINDUP, 0.0, 1.0)
			if state_timer <= 0.0:
				_swing(player)
				state = S.RECOVER
				state_timer = ATTACK_RECOVER
		S.RECOVER:
			state_timer -= delta
			if state_timer <= 0.0:
				state = S.CHASE


func _swing(player) -> void:
	## 挥击瞬间向前突进一小段，命中判定放宽（大横扫）。
	if rooted_timer <= 0.0:
		position += attack_dir * 26.0
	var to_p: Vector2 = player.global_position - global_position
	if to_p.length() <= ATTACK_RANGE + 22.0 and absf(attack_dir.angle_to(to_p)) <= ATTACK_ARC:
		player.take_damage(ATTACK_DAMAGE, attack_dir * ATTACK_KNOCKBACK)
	Fx.burst(game.fx_container, global_position + attack_dir * 46.0, Color(1.0, 0.6, 0.85, 0.9), 8, 200.0)
	game.hitstop(0.06)


func _wander(delta: float) -> void:
	state = S.PATROL
	state_timer += delta
	if state_timer >= patrol_next:
		state_timer = 0.0
		patrol_next = randf_range(0.6, 1.4)
		patrol_dir = Vector2.from_angle(randf() * TAU)
	if rooted_timer <= 0.0:
		position += patrol_dir * PATROL_SPEED * 1.6 * delta


func _player():
	var arr := get_tree().get_nodes_in_group("player")
	return arr[0] if arr.size() > 0 else null
