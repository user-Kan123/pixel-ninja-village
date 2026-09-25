class_name EnemyShooter
extends EnemyBase
## 远程敌人：保持中距离，投掷苦无。
## 攻击前有预警（抬手），命中伤害低于近战但会持续消耗玩家血线。

enum S { IDLE, REPOSITION, AIM, RECOVER }

const AGGRO_RANGE := 420.0
const PREFER_MIN := 210.0
const PREFER_MAX := 340.0
const AIM_WINDUP := 0.5
const ATTACK_RECOVER := 1.3
const ATTACK_DAMAGE := 8.0
const ATTACK_KNOCKBACK := 180.0
const KUNAI_SPEED := 430.0
const REPOSITION_SPEED := 90.0

var state := S.IDLE
var state_timer := 0.0
var strafe_sign := 1.0
var attack_dir := Vector2.RIGHT


func _init() -> void:
	max_hp = 55.0
	hit_radius = 17.0
	move_speed = REPOSITION_SPEED
	body_color = Color("b8792f")
	body_size = Vector2(28, 28)
	xp_value = 16
	ninja_cfg = {
		"hair": Color("8a8a95"), "hair_dark": Color("6a6a75"),
		"skin": Color("d9a87e"), "skin_dark": Color("b8865e"),
		"band": Color("3a3328"), "plate": Color("a8a8b0"),
		"outfit": Color("a8793f"), "outfit_dark": Color("865f30"),
		"trim": Color("c8a86a"), "belt": Color("4a3826"),
		"pants": Color("6a5238"), "pants_dark": Color("52402c"),
		"shoes": Color("2e2620"),
	}


func take_damage(amount: float, knockback: Vector2) -> void:
	super.take_damage(amount, knockback)
	if not dead and state == S.IDLE:
		state = S.REPOSITION


func _tick(delta: float) -> void:
	var player = _player()
	if player == null:
		return
	telegraph = 0.0
	var to_p: Vector2 = player.global_position - global_position
	var dist := to_p.length()
	if confused_timer > 0.0:
		_wander(delta)
		return
	match state:
		S.IDLE:
			if dist < AGGRO_RANGE:
				state = S.REPOSITION
		S.REPOSITION:
			if stagger_timer > 0.0:
				return
			if rooted_timer <= 0.0:
				var move := Vector2.ZERO
				if dist < PREFER_MIN:
					move = -to_p.normalized() * REPOSITION_SPEED
				elif dist > PREFER_MAX:
					move = to_p.normalized() * REPOSITION_SPEED
				else:
					## 保持射程后横向绕走，避免站桩对射
					var perp := Vector2(-to_p.y, to_p.x).normalized() * strafe_sign
					move = perp * REPOSITION_SPEED * 0.75
				move += _separation()
				position += move * delta
			if dist <= PREFER_MAX and stagger_timer <= 0.0:
				state = S.AIM
				state_timer = AIM_WINDUP
				attack_dir = to_p.normalized()
			elif dist > AGGRO_RANGE * 1.25:
				state = S.IDLE
		S.AIM:
			if stagger_timer > 0.0:
				state = S.REPOSITION
				return
			state_timer -= delta
			telegraph = 1.0 - clampf(state_timer / AIM_WINDUP, 0.0, 1.0)
			attack_dir = (player.global_position - global_position).normalized()
			if state_timer <= 0.0:
				_throw(player)
				state = S.RECOVER
				state_timer = ATTACK_RECOVER
				strafe_sign *= -1.0
		S.RECOVER:
			state_timer -= delta
			if state_timer <= 0.0:
				state = S.REPOSITION


func _throw(player) -> void:
	var dir: Vector2 = (player.global_position - global_position).normalized()
	Projectile.create(game.projectile_container, global_position + dir * 20.0, dir, {
		"kind": "kunai",
		"speed": KUNAI_SPEED,
		"damage": ATTACK_DAMAGE,
		"knockback": ATTACK_KNOCKBACK,
		"lifetime": 1.5,
		"hit_radius": 6.0,
		"color": Color(0.85, 0.6, 0.45),
		"hostile": true,
		"game": game,
	})


func _wander(delta: float) -> void:
	state = S.IDLE
	state_timer += delta
	if state_timer >= 1.0:
		state_timer = 0.0
		strafe_sign *= -1.0
	if rooted_timer <= 0.0:
		position += Vector2.from_angle(randf() * TAU) * REPOSITION_SPEED * 0.8 * delta


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d > 0.01 and d < 46.0:
			push += (global_position - other.global_position).normalized() * (46.0 - d) * 3.5
	return push


func _player():
	var arr := get_tree().get_nodes_in_group("player")
	return arr[0] if arr.size() > 0 else null
