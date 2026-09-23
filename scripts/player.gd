class_name Player
extends CharacterBody2D
## 玩家：俯视移动、三段近战、投掷苦无、两个忍术（瞬身 / 小火弹）。
## 忍术参数全部来自 data/jutsu.json，本文件不含专有名词。

enum State { MOVE, ATTACK, SEALING, AIM, DEAD }

const MAX_HP := 100.0
const MAX_CHAKRA := 100.0
const MOVE_SPEED := 330.0
const CHAKRA_REGEN := 9.0
const KUNAI_MAX := 8
const KUNAI_RECHARGE := 4.0

const COMBO_STEPS := [
	{"damage": 8.0, "knockback": 170.0, "windup": 0.08, "active": 0.1, "recovery": 0.14, "lunge": 250.0, "hitstop": 0.045},
	{"damage": 9.0, "knockback": 190.0, "windup": 0.07, "active": 0.1, "recovery": 0.15, "lunge": 270.0, "hitstop": 0.045},
	{"damage": 18.0, "knockback": 430.0, "windup": 0.13, "active": 0.12, "recovery": 0.28, "lunge": 350.0, "hitstop": 0.09},
]
const MELEE_RANGE := 76.0
const MELEE_ARC := deg_to_rad(70.0)
const KUNAI_SPEED := 640.0
const KUNAI_DAMAGE := 9.0

var game
var hp := MAX_HP
var chakra := MAX_CHAKRA
var kunai_count := KUNAI_MAX
var kunai_recharge_t := 0.0

var state := State.MOVE
var attack_stage := 0
var attack_phase := 0
var attack_timer := 0.0
var attack_dir := Vector2.RIGHT
var attack_step: Dictionary = {}
var attack_buffered := false

var combo_count := 0
var combo_timer := 0.0

var jutsu_cd := {"blink": 0.0, "fireball": 0.0}
var seal_id := ""
var seal_cfg: Dictionary = {}
var seal_timer := 0.0
var aim_timer := 0.0

var invuln_timer := 0.0
var flash_timer := 0.0
var knockback_velocity := Vector2.ZERO
var slash_timer := 0.0
var slash_dir := Vector2.RIGHT
var slash_heavy := false
var dead := false
var mouse_world := Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 28)
	col.shape = shape
	add_child(col)
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(game.ARENA_SIZE.x)
	cam.limit_bottom = int(game.ARENA_SIZE.y)
	add_child(cam)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		mouse_world = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == State.AIM:
				_release_fireball(mouse_world)
			elif not dead and state != State.SEALING:
				_request_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not dead:
			if state == State.MOVE:
				_throw_kunai(mouse_world)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_try_cast_jutsu("blink")
		elif event.keycode == KEY_2:
			if state == State.AIM:
				_cancel_aim()
			else:
				_try_cast_jutsu("fireball")
		elif event.keycode == KEY_R:
			game.restart()


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	mouse_world = get_global_mouse_position()
	for id in jutsu_cd:
		jutsu_cd[id] = maxf(jutsu_cd[id] - delta, 0.0)
	if not dead:
		chakra = minf(chakra + CHAKRA_REGEN * delta, MAX_CHAKRA)
		if kunai_count < KUNAI_MAX:
			kunai_recharge_t += delta
			if kunai_recharge_t >= KUNAI_RECHARGE:
				kunai_recharge_t = 0.0
				kunai_count += 1
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_count = 0
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	flash_timer = maxf(flash_timer - delta, 0.0)
	slash_timer = maxf(slash_timer - delta, 0.0)
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1600.0 * delta)

	var desired := Vector2.ZERO
	match state:
		State.MOVE:
			desired = _move_input() * MOVE_SPEED
		State.ATTACK:
			if attack_phase <= 1:
				desired = attack_dir * float(attack_step.get("lunge", 0.0))
			else:
				desired = _move_input() * MOVE_SPEED * 0.45
		State.SEALING:
			desired = _move_input() * MOVE_SPEED * 0.35
		State.AIM:
			desired = _move_input() * MOVE_SPEED * 0.7
		State.DEAD:
			pass
	velocity = desired + knockback_velocity
	move_and_slide()

	if state == State.SEALING:
		_tick_seal(delta)
	elif state == State.AIM:
		_tick_aim(delta)
	elif state == State.ATTACK:
		_tick_attack(delta)
	queue_redraw()


func _request_attack() -> void:
	if state == State.MOVE:
		_start_attack(1)
	elif state == State.ATTACK:
		if attack_phase == 2 or (attack_phase == 1 and attack_timer < float(attack_step.get("active", 0.1)) * 0.5):
			attack_buffered = true


func _start_attack(stage: int) -> void:
	attack_stage = stage
	attack_step = COMBO_STEPS[stage - 1]
	var dir := mouse_world - global_position
	attack_dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	attack_phase = 0
	attack_timer = float(attack_step.windup)
	attack_buffered = false
	slash_timer = float(attack_step.windup) + float(attack_step.active) + 0.05
	slash_dir = attack_dir
	slash_heavy = stage == 3
	state = State.ATTACK


func _tick_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_phase == 0 and attack_timer <= 0.0:
		attack_phase = 1
		attack_timer = float(attack_step.active)
		_do_melee_hit()
	elif attack_phase == 1 and attack_timer <= 0.0:
		attack_phase = 2
		attack_timer = float(attack_step.recovery)
	elif attack_phase == 2 and attack_timer <= 0.0:
		if attack_buffered and attack_stage < COMBO_STEPS.size():
			_start_attack(attack_stage + 1)
		else:
			attack_stage = 0
			state = State.MOVE


func _do_melee_hit() -> void:
	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var to_e: Vector2 = enemy.global_position - global_position
		var reach: float = MELEE_RANGE + enemy.hit_radius
		if to_e.length() > reach:
			continue
		if to_e.length() > 26.0 and absf(attack_dir.angle_to(to_e)) > MELEE_ARC:
			continue
		enemy.take_damage(float(attack_step.damage), attack_dir * float(attack_step.knockback))
		hit_any = true
	if hit_any:
		combo_count += 1
		combo_timer = 1.2
		game.hitstop(float(attack_step.hitstop))


func _throw_kunai(target: Vector2) -> void:
	if kunai_count <= 0:
		return
	kunai_count -= 1
	var dir := (target - global_position).normalized()
	Projectile.create(game.projectile_container, global_position + dir * 20.0, dir, {
		"kind": "kunai",
		"speed": KUNAI_SPEED,
		"damage": KUNAI_DAMAGE,
		"knockback": 150.0,
		"lifetime": 1.1,
		"hit_radius": 6.0,
		"color": Color("e8e2d2"),
		"game": game,
	})


func _try_cast_jutsu(id: String) -> void:
	if dead:
		return
	if state != State.MOVE:
		return
	var cfg: Dictionary = Data.jutsu.get(id, {})
	if cfg.is_empty():
		return
	if float(jutsu_cd.get(id, 0.0)) > 0.0:
		return
	var cost := float(cfg.get("chakra_cost", 0.0))
	if chakra < cost:
		return
	match String(cfg.get("cast_type", "")):
		"instant":
			_cast_instant(id, cfg, cost)
		"seal_aim":
			_start_seal(id, cfg, cost)


func _cast_instant(id: String, cfg: Dictionary, cost: float) -> void:
	chakra -= cost
	jutsu_cd[id] = float(cfg.get("cooldown", 1.0))
	var dir := (mouse_world - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dist: float = minf(float(cfg.get("dash_range", 200.0)), global_position.distance_to(mouse_world))
	var target := global_position + dir * dist
	while dist > 12.0 and game.pos_blocked(target):
		dist *= 0.55
		target = global_position + dir * dist
	Fx.ghost(game.fx_container, global_position, Color(0.3, 0.55, 0.95, 0.55))
	global_position = game.clamp_to_arena(target, 24.0)
	invuln_timer = float(cfg.get("iframes", 0.2))
	Fx.burst(game.fx_container, global_position, Color(0.55, 0.8, 1.0, 0.8), 6, 140.0)


func _start_seal(id: String, cfg: Dictionary, cost: float) -> void:
	chakra -= cost
	jutsu_cd[id] = float(cfg.get("cooldown", 3.0))
	seal_id = id
	seal_cfg = cfg
	seal_cfg["cost_paid"] = cost
	attack_stage = 0
	seal_timer = float(cfg.get("seal_time", 0.45))
	state = State.SEALING


func _tick_seal(delta: float) -> void:
	seal_timer -= delta
	if seal_timer <= 0.0:
		state = State.AIM
		aim_timer = float(seal_cfg.get("aim_timeout", 3.0))


func _tick_aim(delta: float) -> void:
	aim_timer -= delta
	if aim_timer <= 0.0:
		_cancel_aim()


func _cancel_aim() -> void:
	chakra = minf(MAX_CHAKRA, chakra + float(seal_cfg.get("cost_paid", 0.0)))
	jutsu_cd[seal_id] = minf(float(jutsu_cd.get(seal_id, 0.0)), 0.8)
	seal_cfg = {}
	seal_id = ""
	state = State.MOVE


func _release_fireball(target: Vector2) -> void:
	var cfg := seal_cfg
	var dir := (target - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	Projectile.create(game.projectile_container, global_position + dir * 22.0, dir, {
		"kind": "fireball",
		"speed": float(cfg.get("speed", 400.0)),
		"damage": float(cfg.get("damage", 12.0)),
		"knockback": float(cfg.get("knockback", 220.0)),
		"lifetime": 2.2,
		"hit_radius": 9.0,
		"aoe_radius": float(cfg.get("aoe_radius", 36.0)),
		"burn_dps": float(cfg.get("burn_dps", 3.0)),
		"burn_duration": float(cfg.get("burn_duration", 2.0)),
		"color": Color(1.0, 0.55, 0.2, 0.95),
		"game": game,
	})
	seal_cfg = {}
	seal_id = ""
	state = State.MOVE


func take_damage(amount: float, knockback: Vector2) -> void:
	if dead or invuln_timer > 0.0:
		return
	hp -= amount
	flash_timer = 0.15
	knockback_velocity += knockback
	game.hitstop(0.05)
	if hp <= 0.0:
		hp = 0.0
		_die()


func _die() -> void:
	dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	Fx.burst(game.fx_container, global_position, Color(0.9, 0.25, 0.25, 0.9), 14, 260.0)
	game.on_player_died()


func _draw() -> void:
	if dead:
		draw_rect(Rect2(-12, -16, 24, 32), Color(0.35, 0.35, 0.35, 0.6))
		return
	var body_col := Color("4d86d8")
	if flash_timer > 0.0:
		body_col = Color.WHITE
	if invuln_timer > 0.0:
		body_col.a = 0.45
	draw_rect(Rect2(-12, -16, 24, 32), body_col)
	draw_rect(Rect2(-12, -16, 24, 32), Color(0.1, 0.1, 0.12, 0.9), false, 2.0)
	draw_rect(Rect2(-12, -9, 24, 5), Color(0.95, 0.92, 0.85, body_col.a))
	var aim := (mouse_world - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	var perp := Vector2(-aim.y, aim.x)
	draw_colored_polygon(PackedVector2Array([
		aim * 22.0 + perp * 5.0, aim * 30.0, aim * 22.0 - perp * 5.0,
	]), Color(0.95, 0.9, 0.8, body_col.a))
	if slash_timer > 0.0:
		var t: float = clampf(slash_timer / 0.25, 0.0, 1.0)
		var col := Color(1.0, 1.0, 0.95, t * 0.85)
		var a0 := slash_dir.angle()
		draw_arc(Vector2.ZERO, MELEE_RANGE * 0.85, a0 - MELEE_ARC, a0 + MELEE_ARC, 14, col, 5.0 if slash_heavy else 3.0)
		if slash_heavy:
			draw_arc(Vector2.ZERO, MELEE_RANGE * 0.55, a0 - MELEE_ARC * 1.3, a0 + MELEE_ARC * 1.3, 12, Color(1.0, 0.85, 0.4, t * 0.7), 3.0)
	if state == State.SEALING:
		var p := 1.0 - clampf(seal_timer / maxf(float(seal_cfg.get("seal_time", 0.45)), 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 34.0, -PI / 2.0, -PI / 2.0 + TAU * p, 24, Color(1.0, 0.6, 0.25, 0.9), 3.0)
	if state == State.AIM:
		var local_mouse := mouse_world - global_position
		draw_line(Vector2.ZERO, local_mouse, Color(1.0, 0.6, 0.25, 0.5), 1.0)
		draw_arc(local_mouse, 14.0, 0.0, TAU, 20, Color(1.0, 0.6, 0.25, 0.9), 2.0)
