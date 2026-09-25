class_name Player
extends CharacterBody2D
## 玩家：俯视移动、三段近战、投掷苦无、5 类施法管线驱动的忍术系统。
##
## 施法管线（cast_type，全部由 data/jutsu.json 指定）：
##   instant       瞬时：位移 / 召唤 / 自身强化 / 幻术
##   seal_aim      结印 + 瞄准：结印结束后进入瞄准，点击释放
##   charge        蓄力：按住蓄力，松开按下蓄力量缩放参数释放
##   ground_target 坐标选择：移动光标选点，点击放置场地区域
##   channel       引导：按住持续生效，消耗查克拉、可被打断
##
## 成长：击杀获得经验，升级提升体力/查克拉上限，并在 6 级、12 级各解锁一个忍术槽。
## 忍术槽内容由装配界面（Tab）决定，本文件不含任何专有名词。

enum State { MOVE, ATTACK, SEALING, AIM, CHARGE, GROUND, CHANNEL, DEAD }

const MAX_HP_BASE := 100.0
const MAX_CHAKRA_BASE := 100.0
## 移动速度：已按手感反馈降到原值的 60%（330 → 198）。想整体调快/调慢只改这一个数。
const MOVE_SPEED := 198.0
const CHAKRA_REGEN := 9.0
const KUNAI_MAX := 8
const KUNAI_RECHARGE := 4.0

## 鼠标跟随移动（主操作方式）
const MOUSE_DEAD_ZONE := 24.0   ## 鼠标离人物多近算"站住"（贴到身上即停）
const MOUSE_SLOW_BAND := 60.0   ## 死区外这一段距离内线性加速到全速
const MOUSE_MIN_SPEED := 0.35   ## 刚出死区时的最低速度比例，避免龟速蹭
const CAST_MOVE_MULT := 0.3     ## 施法期间（结印/瞄准/蓄力/选坐标/引导）移动速度比例

const MAX_LEVEL := 20
## 5 个忍术槽各自的解锁等级（前三个 1 级即可用）
const SLOT_UNLOCK_LEVELS := [1, 1, 1, 6, 12]
const DEFAULT_LOADOUT := ["blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones"]

## 玩家像素外观（鸣人经典橙蓝配色）
const NINJA_CFG := {
	"hair": Color("f5c542"), "hair_dark": Color("d99a2b"),
	"skin": Color("f2c9a0"), "skin_dark": Color("d9a574"),
	"eye": Color("3a6ab8"),
	"band": Color("2a3a5c"), "plate": Color("c9cdd6"),
	"outfit": Color("e8833a"), "outfit_dark": Color("c96528"),
	"trim": Color("eee8da"), "belt": Color("3a3a44"),
	"pants": Color("3a4a7a"), "pants_dark": Color("2a3658"),
	"shoes": Color("2b2b33"),
}
## 像素忍者绘制中心（脚下锚点）
const NINJA_ANCHOR := Vector2(0, -24)

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
var max_hp := MAX_HP_BASE
var max_chakra := MAX_CHAKRA_BASE
var hp := MAX_HP_BASE
var chakra := MAX_CHAKRA_BASE
var kunai_count := KUNAI_MAX
var kunai_recharge_t := 0.0

## 成长
var level := 1
var xp := 0
var xp_next := 40

## 忍术装配
var jutsu_slots: Array[String] = []
var jutsu_cd: Dictionary = {}

var state := State.MOVE
var attack_stage := 0
var attack_phase := 0
var attack_timer := 0.0
var attack_dir := Vector2.RIGHT
var attack_step: Dictionary = {}
var attack_buffered := false

var combo_count := 0
var combo_timer := 0.0

## 结印 / 瞄准
var seal_id := ""
var seal_cfg: Dictionary = {}
var seal_slot := -1
var seal_timer := 0.0
var aim_timer := 0.0

## 蓄力
var charge_id := ""
var charge_cfg: Dictionary = {}
var charge_slot := -1
var charge_t := 0.0

## 坐标选择
var ground_id := ""
var ground_cfg: Dictionary = {}
var ground_slot := -1
var ground_timer := 0.0

## 引导
var channel_id := ""
var channel_cfg: Dictionary = {}
var channel_slot := -1
var channel_t := 0.0

## 附身触发（螺旋丸：手持丸子，接触敌人引爆）
var orb_active := false
var orb_timer := 0.0
var orb_cfg: Dictionary = {}

## 自身强化（附身触发型：近战附带麻痹）
var buff_id := ""
var buff_timer := 0.0
var buff_damage := 0.0
var buff_paralysis := 0.0

var invuln_timer := 0.0
var flash_timer := 0.0
var knockback_velocity := Vector2.ZERO
var slash_timer := 0.0
var slash_dir := Vector2.RIGHT
var slash_heavy := false
var dead := false
var mouse_world := Vector2.ZERO
## 当前朝向（鼠标压在人物身上不动时会保持上一次朝向，避免指示三角疯狂翻转）
var face_dir := Vector2.RIGHT
## 让鼠标"粘"在玩家身上（等价于鼠标压在人物身上 → 站住）。
## 无头自检必须开：headless 下 get_global_mouse_position() 固定在屏幕原点，
## 不粘住的话玩家会一路朝地图左上角狂奔，站位类断言全部失效。也可当调试开关用。
var mouse_sticky := false

## 走路动画
var walk_frame := 0
var walk_anim_t := 0.0


func _ready() -> void:
	add_to_group("player")
	for id in DEFAULT_LOADOUT:
		jutsu_slots.append(String(id))
	for id in Data.jutsu:
		jutsu_cd[id] = 0.0
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
	cam.limit_right = int(game.arena_size.x)
	cam.limit_bottom = int(game.arena_size.y)
	add_child(cam)


# ---------------------------------------------------------------- 成长

func slots_unlocked() -> int:
	var n := 0
	for lv in SLOT_UNLOCK_LEVELS:
		if level >= int(lv):
			n += 1
	return n


func rank_key() -> String:
	return "rank.genin" if level <= 10 else "rank.chunin"


func gain_xp(amount: int) -> void:
	if dead:
		return
	xp += amount
	while xp >= xp_next and level < MAX_LEVEL:
		xp -= xp_next
		_level_up()


func _level_up() -> void:
	level += 1
	max_hp += 12.0
	max_chakra += 10.0
	hp = minf(max_hp, hp + max_hp * 0.35)
	chakra = max_chakra
	xp_next = 40 + (level - 1) * 26
	flash_timer = 0.25
	Fx.burst(game.fx_container, global_position, Color(1.0, 0.95, 0.5, 0.95), 14, 220.0)
	game.hitstop(0.06)
	game.on_player_level_up(level)


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if game != null and game.loadout_open:
		return
	if event is InputEventMouseButton and event.pressed:
		mouse_world = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click()
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_TAB and event.pressed:
			game.toggle_loadout()
			return
		if event.keycode == KEY_R and event.pressed:
			game.restart()
			return
		if event.keycode == KEY_E and event.pressed:
			game.on_interact()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var idx := int(event.keycode) - int(KEY_1)
			if event.pressed:
				_on_slot_pressed(idx)
			else:
				_on_slot_released(idx)


func _on_left_click() -> void:
	if state == State.AIM:
		_release_seal_aim(mouse_world)
	elif state == State.GROUND:
		_confirm_ground(mouse_world)
	elif state == State.CHANNEL:
		pass
	elif not dead:
		_request_attack()


func _on_right_click() -> void:
	match state:
		State.AIM:
			_cancel_aim()
		State.GROUND:
			_cancel_ground()
		State.CHARGE:
			_cancel_charge()
		State.MOVE:
			if not dead:
				_throw_kunai(mouse_world)
		_:
			pass


func _on_slot_pressed(idx: int) -> void:
	if dead or idx < 0 or idx >= jutsu_slots.size():
		return
	if idx >= slots_unlocked():
		return
	if state == State.CHARGE:
		## 蓄力中再次按同键：直接释放
		if idx == charge_slot:
			_release_charge()
		return
	if state == State.GROUND:
		if idx == ground_slot:
			_cancel_ground()
			return
		_cancel_ground()
	if state == State.AIM:
		if idx == seal_slot:
			_cancel_aim()
			return
	if state != State.MOVE and state != State.CHANNEL:
		return
	if state == State.CHANNEL:
		_end_channel()
	_try_cast_jutsu(jutsu_slots[idx], idx)


func _on_slot_released(idx: int) -> void:
	if state == State.CHARGE and idx == charge_slot:
		_release_charge()
	elif state == State.CHANNEL and idx == channel_slot:
		_end_channel()


## 移动输入：返回方向向量（长度 0~1）。
## 主操作是**鼠标跟随**：人物朝鼠标方向走，越靠近鼠标越慢，鼠标贴到身上（≤ MOUSE_DEAD_ZONE）即站住。
## WASD 仍然有效，与鼠标方向叠加，用于微调走位。
func _move_input() -> Vector2:
	var v := Vector2.ZERO
	var to_mouse := mouse_world - global_position
	var d := to_mouse.length()
	if d > MOUSE_DEAD_ZONE:
		var w := clampf((d - MOUSE_DEAD_ZONE) / MOUSE_SLOW_BAND, MOUSE_MIN_SPEED, 1.0)
		v = to_mouse / d * w
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	return v.limit_length(1.0)


## 朝向更新：鼠标离得够远才转向；压在人物身上（站住时）保持上一次朝向，
## 否则指示三角会在鼠标压住人物的一瞬间跳到默认方向、疯狂翻转。
func _update_face() -> void:
	var to_mouse := mouse_world - global_position
	if to_mouse.length() > MOUSE_DEAD_ZONE * 0.5:
		face_dir = to_mouse.normalized()


# ---------------------------------------------------------------- 主循环

func _physics_process(delta: float) -> void:
	## 鼠标跟随：粘住时鼠标恒等于人物位置 → _move_input() 恒为 0 → 站住
	mouse_world = global_position if mouse_sticky else get_global_mouse_position()
	_update_face()
	for id in jutsu_cd:
		jutsu_cd[id] = maxf(float(jutsu_cd[id]) - delta, 0.0)
	if not dead:
		var regen := CHAKRA_REGEN * _passive_mult("chakra_flow", "chakra_regen_mult", 1.0)
		chakra = minf(chakra + regen * delta, max_chakra)
		if kunai_count < KUNAI_MAX:
			kunai_recharge_t += delta
			if kunai_recharge_t >= KUNAI_RECHARGE:
				kunai_recharge_t = 0.0
				kunai_count += 1
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_count = 0
	buff_timer = maxf(buff_timer - delta, 0.0)
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	flash_timer = maxf(flash_timer - delta, 0.0)
	slash_timer = maxf(slash_timer - delta, 0.0)
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1600.0 * delta)

	var desired := Vector2.ZERO
	var orb_mult := float(orb_cfg.get("move_mult", 0.85)) if orb_active else 1.0
	match state:
		State.MOVE:
			desired = _move_input() * MOVE_SPEED * orb_mult
		State.ATTACK:
			if attack_phase <= 1:
				desired = attack_dir * float(attack_step.get("lunge", 0.0))
			else:
				desired = _move_input() * MOVE_SPEED * 0.45
		State.SEALING, State.AIM, State.CHARGE, State.GROUND, State.CHANNEL:
			## 施法期间统一降到三成：鼠标追随时，瞄准远处目标不会被自己带着狂奔
			desired = _move_input() * MOVE_SPEED * CAST_MOVE_MULT
		State.DEAD:
			pass
	velocity = desired + knockback_velocity
	move_and_slide()
	_update_walk(delta)
	_tick_orb(delta)

	match state:
		State.SEALING:
			_tick_seal(delta)
		State.AIM:
			_tick_aim(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.CHARGE:
			_tick_charge(delta)
		State.GROUND:
			_tick_ground(delta)
		State.CHANNEL:
			_tick_channel(delta)
		_:
			pass
	queue_redraw()


func _update_walk(delta: float) -> void:
	## 只要在动就迈腿（施法期间的三成速度移动、攻击前冲也算），站住则归位第一帧
	if not dead and velocity.length() > 40.0:
		walk_anim_t += delta
		if walk_anim_t >= 0.13:
			walk_anim_t = 0.0
			walk_frame = 1 - walk_frame
	else:
		walk_frame = 0
		walk_anim_t = 0.0


# ---------------------------------------------------------------- 近战 / 苦无

func _request_attack() -> void:
	if orb_active:
		## 手持丸子期间双手被占用，不能出刀
		return
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
	var buffed := buff_timer > 0.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var to_e: Vector2 = enemy.global_position - global_position
		var reach: float = MELEE_RANGE + enemy.hit_radius
		if to_e.length() > reach:
			continue
		if to_e.length() > 26.0 and absf(attack_dir.angle_to(to_e)) > MELEE_ARC:
			continue
		var dmg: float = (float(attack_step.damage) + (buff_damage if buffed else 0.0)) * _passive_mult("monstrous_strength", "melee_damage_mult", 1.0)
		enemy.take_damage(dmg, attack_dir * float(attack_step.knockback))
		if buffed and buff_paralysis > 0.0:
			enemy.apply_root(buff_paralysis)
		hit_any = true
	if hit_any:
		combo_count += 1
		combo_timer = 1.2
		game.hitstop(float(attack_step.hitstop))


func _throw_kunai(target: Vector2) -> void:
	if kunai_count <= 0 or orb_active:
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


# ---------------------------------------------------------------- 施法入口

func _try_cast_jutsu(id: String, slot_idx: int) -> void:
	if dead:
		return
	if state != State.MOVE:
		return
	var cfg: Dictionary = Data.jutsu.get(id, {})
	if cfg.is_empty():
		return
	if float(jutsu_cd.get(id, 0.0)) > 0.0:
		return
	var cast_type := String(cfg.get("cast_type", ""))
	var cost := float(cfg.get("chakra_cost", 0.0))
	## 引导类按秒扣费，起手只需一点点启动查克拉
	if cast_type == "channel":
		if chakra < 6.0:
			return
	elif chakra < cost:
		return
	match cast_type:
		"instant":
			_cast_instant(id, cfg, cost)
		"seal_aim":
			_start_seal(id, cfg, cost, slot_idx)
		"charge":
			_start_charge(id, cfg, slot_idx)
		"ground_target":
			_start_ground(id, cfg, slot_idx)
		"channel":
			_start_channel(id, cfg, slot_idx)
		"body_trigger":
			_cast_body_trigger(id, cfg, cost)
		"passive":
			## 被动常驻：装配即生效，按键无操作
			pass
		_:
			pass


func _cast_instant(id: String, cfg: Dictionary, cost: float) -> void:
	chakra -= cost
	jutsu_cd[id] = float(cfg.get("cooldown", 1.0))
	match String(cfg.get("category", "")):
		"movement":
			_instant_dash(cfg)
		"summon":
			_cast_clones(cfg)
		"self_buff":
			_cast_self_buff(id, cfg)
		"illusion":
			_cast_illusion(cfg)
		_:
			pass


func _instant_dash(cfg: Dictionary) -> void:
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


func _cast_clones(cfg: Dictionary) -> void:
	var count := int(cfg.get("clone_count", 2))
	for i in count:
		ShadowClone.create(game.field_container, global_position, cfg, game, self, i)


func _cast_self_buff(id: String, cfg: Dictionary) -> void:
	buff_id = id
	buff_timer = float(cfg.get("buff_duration", 8.0))
	buff_damage = float(cfg.get("buff_damage", 0.0))
	buff_paralysis = float(cfg.get("paralysis", 0.0))
	Fx.burst(game.fx_container, global_position, Color(0.75, 0.9, 1.0, 0.9), 12, 200.0)


func _cast_illusion(cfg: Dictionary) -> void:
	var radius := float(cfg.get("confuse_radius", 300.0))
	var duration := float(cfg.get("confuse_duration", 4.0))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		if global_position.distance_to(enemy.global_position) <= radius + enemy.hit_radius:
			enemy.apply_confuse(duration)
			Fx.burst(game.fx_container, enemy.global_position, Color(0.72, 0.45, 1.0, 0.75), 5, 110.0)
	Fx.burst(game.fx_container, global_position, Color(0.72, 0.45, 1.0, 0.7), 10, 240.0)
	game.hitstop(0.04)


# ---------------------------------------------------------------- 附身触发（螺旋丸）

func _cast_body_trigger(id: String, cfg: Dictionary, cost: float) -> void:
	if orb_active:
		return
	chakra -= cost
	jutsu_cd[id] = float(cfg.get("cooldown", 8.0))
	orb_active = true
	orb_timer = float(cfg.get("orb_duration", 4.0))
	orb_cfg = cfg
	Fx.burst(game.fx_container, global_position, Color(0.55, 0.75, 1.0, 0.9), 10, 180.0)


func _tick_orb(delta: float) -> void:
	if not orb_active:
		return
	orb_timer -= delta
	if orb_timer <= 0.0:
		orb_active = false
		Fx.burst(game.fx_container, global_position, Color(0.6, 0.8, 1.0, 0.5), 6, 120.0)
		return
	## 手持丸子：接触敌人即引爆
	var orb_pos := _orb_pos()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		if orb_pos.distance_to(enemy.global_position) <= float(orb_cfg.get("orb_radius", 16.0)) + enemy.hit_radius + 12.0:
			_detonate_orb(orb_pos)
			return


func _orb_pos() -> Vector2:
	var dir := (mouse_world - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	return global_position + dir * 24.0


func _detonate_orb(center: Vector2) -> void:
	orb_active = false
	var radius := float(orb_cfg.get("aoe_radius", 60.0))
	var dmg := float(orb_cfg.get("damage", 30.0))
	var kb := float(orb_cfg.get("knockback", 640.0))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or enemy.dead:
			continue
		var d: float = center.distance_to(enemy.global_position)
		if d <= radius + enemy.hit_radius:
			var dir: Vector2 = (enemy.global_position - center).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var falloff := 1.0 - clampf(d / maxf(radius, 1.0), 0.0, 1.0) * 0.4
			enemy.take_damage(dmg * falloff, dir * kb)
	Fx.burst(game.fx_container, center, Color(0.55, 0.8, 1.0, 0.95), 16, 320.0)
	Fx.burst(game.fx_container, center, Color(0.9, 0.97, 1.0, 0.9), 10, 200.0)
	game.hitstop(0.09)


# ---------------------------------------------------------------- 被动常驻

func _equipped(id: String) -> bool:
	return jutsu_slots.has(id)


func _passive_mult(id: String, key: String, fallback: float) -> float:
	if not _equipped(id):
		return fallback
	return float(Data.jutsu.get(id, {}).get(key, fallback))


# ---------------------------------------------------------------- 结印 + 瞄准

func _start_seal(id: String, cfg: Dictionary, cost: float, slot_idx: int) -> void:
	chakra -= cost
	jutsu_cd[id] = float(cfg.get("cooldown", 3.0))
	seal_id = id
	seal_cfg = cfg.duplicate()
	seal_cfg["cost_paid"] = cost
	seal_slot = slot_idx
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
	chakra = minf(max_chakra, chakra + float(seal_cfg.get("cost_paid", 0.0)))
	jutsu_cd[seal_id] = minf(float(jutsu_cd.get(seal_id, 0.0)), 0.8)
	seal_cfg = {}
	seal_id = ""
	seal_slot = -1
	state = State.MOVE


func _release_seal_aim(target: Vector2) -> void:
	var cfg := seal_cfg
	if String(cfg.get("category", "")) == "projectile":
		_spawn_fireball(cfg, 1.0, 1.0, target)
	seal_cfg = {}
	seal_id = ""
	seal_slot = -1
	state = State.MOVE


func _spawn_fireball(cfg: Dictionary, scale: float, charge_ratio: float, aim: Vector2) -> void:
	var dir := (aim - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var hit_r: float = float(cfg.get("hit_radius", 9.0))
	if cfg.has("hit_radius_max"):
		hit_r = lerpf(hit_r, float(cfg.get("hit_radius_max")), charge_ratio)
	Projectile.create(game.projectile_container, global_position + dir * 24.0, dir, {
		"kind": "fireball",
		"speed": float(cfg.get("speed", 400.0)),
		"damage": lerpf(float(cfg.get("damage", 12.0)), float(cfg.get("damage_max", cfg.get("damage", 12.0))), charge_ratio) * scale,
		"knockback": float(cfg.get("knockback", 220.0)),
		"lifetime": 2.3,
		"hit_radius": hit_r,
		"aoe_radius": lerpf(float(cfg.get("aoe_radius", 36.0)), float(cfg.get("aoe_radius_max", cfg.get("aoe_radius", 36.0))), charge_ratio),
		"burn_dps": lerpf(float(cfg.get("burn_dps", 0.0)), float(cfg.get("burn_dps_max", cfg.get("burn_dps", 0.0))), charge_ratio),
		"burn_duration": float(cfg.get("burn_duration", 2.0)),
		"color": Color(1.0, 0.45 + 0.2 * (1.0 - charge_ratio), 0.18, 0.95),
		"game": game,
	})


# ---------------------------------------------------------------- 蓄力

func _start_charge(id: String, cfg: Dictionary, slot_idx: int) -> void:
	charge_id = id
	charge_cfg = cfg
	charge_slot = slot_idx
	charge_t = 0.0
	state = State.CHARGE


func _tick_charge(delta: float) -> void:
	charge_t = minf(charge_t + delta, float(charge_cfg.get("max_charge", 1.0)))


func _charge_ratio() -> float:
	return clampf(charge_t / maxf(float(charge_cfg.get("max_charge", 1.0)), 0.01), 0.0, 1.0)


func _release_charge() -> void:
	var cfg := charge_cfg
	var ratio := _charge_ratio()
	var min_charge := 0.25
	if cfg.has("min_charge"):
		## min_charge 以秒为单位，换算成比例
		min_charge = clampf(float(cfg.get("min_charge", 0.25)) / maxf(float(cfg.get("max_charge", 1.0)), 0.01), 0.0, 1.0)
	if ratio < min_charge:
		_cancel_charge()
		return
	var cost := float(cfg.get("chakra_cost", 0.0))
	chakra -= cost
	jutsu_cd[charge_id] = float(cfg.get("cooldown", 5.0))
	var cat := String(cfg.get("category", ""))
	if cat == "movement":
		_charged_dash(cfg, ratio)
	elif cat == "projectile":
		_spawn_fireball(cfg, 1.0, ratio, mouse_world)
	_reset_charge()
	state = State.MOVE


func _reset_charge() -> void:
	charge_cfg = {}
	charge_id = ""
	charge_slot = -1
	charge_t = 0.0


func _cancel_charge() -> void:
	_reset_charge()
	state = State.MOVE


func _charged_dash(cfg: Dictionary, ratio: float) -> void:
	var dir := (mouse_world - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dist: float = lerpf(float(cfg.get("dash_range", 200.0)), float(cfg.get("dash_range_max", 400.0)), ratio)
	dist = minf(dist, global_position.distance_to(mouse_world) + 60.0)
	var dmg: float = lerpf(float(cfg.get("damage", 10.0)), float(cfg.get("damage_max", 20.0)), ratio)
	var start := global_position
	var travelled := 0.0
	var step := 16.0
	var hit_set := {}
	while travelled < dist:
		var advance: float = minf(step, dist - travelled)
		travelled += advance
		var p: Vector2 = start + dir * travelled
		if game.pos_blocked(p):
			break
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if hit_set.has(enemy) or not enemy is EnemyBase or enemy.dead:
				continue
			if p.distance_to(enemy.global_position) <= 40.0 + enemy.hit_radius:
				hit_set[enemy] = true
				enemy.take_damage(dmg, dir * 340.0)
				Fx.burst(game.fx_container, enemy.global_position, Color(0.7, 0.9, 1.0, 0.9), 6, 160.0)
	for i in 6:
		var f: float = float(i + 1) / 7.0
		Fx.ghost(game.fx_container, start + dir * travelled * f, Color(0.45, 0.8, 1.0, 0.5))
	global_position = game.clamp_to_arena(start + dir * travelled, 24.0)
	invuln_timer = lerpf(float(cfg.get("iframes", 0.3)), float(cfg.get("iframes_max", 0.45)), ratio)
	Fx.burst(game.fx_container, global_position, Color(0.6, 0.9, 1.0, 0.85), 8, 180.0)
	if hit_set.size() > 0:
		game.hitstop(0.07)


# ---------------------------------------------------------------- 坐标选择

func _start_ground(id: String, cfg: Dictionary, slot_idx: int) -> void:
	ground_id = id
	ground_cfg = cfg
	ground_slot = slot_idx
	ground_timer = 3.0
	state = State.GROUND


func _tick_ground(delta: float) -> void:
	ground_timer -= delta
	if ground_timer <= 0.0:
		_cancel_ground()


func _ground_point() -> Vector2:
	var to_m := mouse_world - global_position
	var max_range := float(ground_cfg.get("target_range", 400.0))
	if to_m.length() > max_range:
		to_m = to_m.normalized() * max_range
	return game.clamp_to_arena(global_position + to_m, 30.0)


func _confirm_ground(_target: Vector2) -> void:
	var cfg := ground_cfg
	var cost := float(cfg.get("chakra_cost", 0.0))
	if chakra < cost:
		_cancel_ground()
		return
	chakra -= cost
	jutsu_cd[ground_id] = float(cfg.get("cooldown", 8.0))
	var point := _ground_point()
	var cat := String(cfg.get("category", ""))
	if cat == "field":
		var dir := (point - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		EarthWall.create(game.field_container, point, dir, cfg, game)
	elif cat == "seal":
		BindingField.create(game.field_container, point, cfg, game)
	Fx.burst(game.fx_container, point, Color(0.7, 0.6, 0.35, 0.9), 8, 160.0)
	ground_cfg = {}
	ground_id = ""
	ground_slot = -1
	state = State.MOVE


func _cancel_ground() -> void:
	ground_cfg = {}
	ground_id = ""
	ground_slot = -1
	state = State.MOVE


# ---------------------------------------------------------------- 引导

func _start_channel(id: String, cfg: Dictionary, slot_idx: int) -> void:
	channel_id = id
	channel_cfg = cfg
	channel_slot = slot_idx
	channel_t = 0.0
	state = State.CHANNEL


func _tick_channel(delta: float) -> void:
	channel_t += delta
	hp = minf(hp + float(channel_cfg.get("heal_per_second", 0.0)) * delta, max_hp)
	chakra = maxf(chakra - float(channel_cfg.get("chakra_per_second", 0.0)) * delta, 0.0)
	if fmod(channel_t, 0.12) < delta:
		Fx.burst(game.fx_container, global_position + Vector2(randf_range(-10.0, 10.0), randf_range(-14.0, 6.0)), Color(0.45, 0.95, 0.6, 0.8), 2, 70.0)
	if chakra <= 0.0 or channel_t >= float(channel_cfg.get("max_channel", 4.0)) or hp >= max_hp:
		_end_channel()


func _end_channel() -> void:
	if state != State.CHANNEL:
		return
	if not channel_id.is_empty():
		jutsu_cd[channel_id] = float(channel_cfg.get("cooldown", 3.0))
	channel_cfg = {}
	channel_id = ""
	channel_slot = -1
	channel_t = 0.0
	state = State.MOVE


# ---------------------------------------------------------------- 受击 / 死亡

func take_damage(amount: float, knockback: Vector2) -> void:
	if dead or invuln_timer > 0.0:
		return
	## 写轮眼·洞察（被动）：概率免伤闪避
	if _equipped("sharingan_insight"):
		var dodge := float(Data.jutsu.get("sharingan_insight", {}).get("dodge_chance", 0.0))
		if randf() < dodge:
			Fx.ghost(game.fx_container, global_position, Color(0.95, 0.4, 0.45, 0.6))
			Fx.burst(game.fx_container, global_position, Color(0.95, 0.5, 0.55, 0.85), 6, 150.0)
			game.hitstop(0.03)
			return
	hp -= amount
	flash_timer = 0.15
	knockback_velocity += knockback
	game.hitstop(0.05)
	## 被打断：引导立即终止，蓄力直接中断（不耗查克拉），丸子脱手
	if state == State.CHANNEL:
		_end_channel()
	elif state == State.CHARGE:
		_cancel_charge()
	if orb_active:
		orb_active = false
	if hp <= 0.0:
		## 替身术（被动）：免死一次，后撤并短暂无敌，冷却 60s
		if _equipped("substitution") and float(jutsu_cd.get("substitution", 0.0)) <= 0.0:
			_substitute_survive()
			return
		hp = 0.0
		_die()


func _substitute_survive() -> void:
	var cfg: Dictionary = Data.jutsu.get("substitution", {})
	hp = 1.0
	jutsu_cd["substitution"] = float(cfg.get("cooldown", 60.0))
	invuln_timer = float(cfg.get("iframes", 1.5))
	## 后撤：优先沿击退反方向，否则随机
	var dir := -knockback_velocity.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(randf() * TAU)
	var dist := float(cfg.get("retreat_range", 220.0))
	var target := global_position + dir * dist
	while dist > 16.0 and game.pos_blocked(target):
		dist *= 0.6
		target = global_position + dir * dist
	Fx.ghost(game.fx_container, global_position, Color(0.65, 0.5, 0.3, 0.6))
	global_position = game.clamp_to_arena(target, 24.0)
	Fx.burst(game.fx_container, global_position, Color(0.85, 0.7, 0.45, 0.9), 12, 220.0)
	game.hitstop(0.1)


func _die() -> void:
	dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	Fx.burst(game.fx_container, global_position, Color(0.9, 0.25, 0.25, 0.9), 14, 260.0)
	game.on_player_died()


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if dead:
		## 倒地：灰色残影
		draw_rect(Rect2(-16, 8, 32, 9), Color(0.35, 0.35, 0.35, 0.5))
		draw_line(Vector2(-14, 4), Vector2(14, 14), Color(0.5, 0.5, 0.5, 0.6), 2.0)
		return
	## 像素忍者
	var cfg: Dictionary = NINJA_CFG.duplicate()
	cfg["flash_a"] = clampf(flash_timer / 0.15, 0.0, 1.0)
	if invuln_timer > 0.0:
		cfg["alpha"] = 0.5
	PixelArt.draw_ninja(self, NINJA_ANCHOR, cfg, walk_frame, 3.0)
	## 朝向指示（小三角）：用 face_dir，鼠标压在人物身上站住时保持上一次朝向
	var aim := face_dir
	var perp := Vector2(-aim.y, aim.x)
	draw_colored_polygon(PackedVector2Array([
		aim * 24.0 + perp * 4.0, aim * 31.0, aim * 24.0 - perp * 4.0,
	]), Color(0.95, 0.9, 0.8, 0.85))
	## buff 蓝色光环
	if buff_timer > 0.0:
		var pulse := 0.5 + 0.5 * sin(buff_timer * 14.0)
		draw_arc(NINJA_ANCHOR, 31.0 + pulse * 3.0, 0.0, TAU, 22, Color(0.6, 0.9, 1.0, 0.5 + 0.3 * pulse), 2.0)
	if slash_timer > 0.0:
		var t: float = clampf(slash_timer / 0.25, 0.0, 1.0)
		var col := Color(1.0, 1.0, 0.95, t * 0.85)
		if buff_timer > 0.0:
			col = Color(0.7, 0.95, 1.0, t * 0.9)
		var a0 := slash_dir.angle()
		draw_arc(NINJA_ANCHOR, MELEE_RANGE * 0.85, a0 - MELEE_ARC, a0 + MELEE_ARC, 14, col, 5.0 if slash_heavy else 3.0)
		if slash_heavy:
			draw_arc(NINJA_ANCHOR, MELEE_RANGE * 0.55, a0 - MELEE_ARC * 1.3, a0 + MELEE_ARC * 1.3, 12, Color(1.0, 0.85, 0.4, t * 0.7), 3.0)
	if state == State.SEALING:
		var p := 1.0 - clampf(seal_timer / maxf(float(seal_cfg.get("seal_time", 0.45)), 0.01), 0.0, 1.0)
		draw_arc(NINJA_ANCHOR, 34.0, -PI / 2.0, -PI / 2.0 + TAU * p, 24, Color(1.0, 0.6, 0.25, 0.9), 3.0)
	if state == State.AIM:
		draw_line(NINJA_ANCHOR, mouse_world - global_position, Color(1.0, 0.6, 0.25, 0.5), 1.0)
		draw_arc(mouse_world - global_position, 14.0, 0.0, TAU, 20, Color(1.0, 0.6, 0.25, 0.9), 2.0)
	if state == State.CHARGE:
		var ratio := _charge_ratio()
		var col2 := Color(0.5, 0.85, 1.0, 0.95)
		if String(charge_cfg.get("category", "")) == "projectile":
			col2 = Color(1.0, 0.6, 0.2, 0.95)
		draw_arc(NINJA_ANCHOR, 38.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 26, col2, 4.0)
		draw_arc(NINJA_ANCHOR, 30.0 + ratio * 10.0, 0.0, TAU * ratio, 22, Color(col2.r, col2.g, col2.b, 0.4), 1.5)
		var d := (mouse_world - global_position).normalized()
		if d != Vector2.ZERO:
			draw_line(NINJA_ANCHOR, NINJA_ANCHOR + d * (60.0 + 90.0 * ratio), Color(col2.r, col2.g, col2.b, 0.45), 2.0)
	if state == State.GROUND:
		var point_local := _ground_point() - global_position
		var cat := String(ground_cfg.get("category", ""))
		if cat == "seal":
			var r := float(ground_cfg.get("seal_radius", 85.0))
			draw_circle(point_local, r, Color(0.6, 0.4, 0.9, 0.15))
			draw_arc(point_local, r, 0.0, TAU, 36, Color(0.75, 0.55, 1.0, 0.8), 2.0)
		else:
			var d2 := point_local.normalized()
			var perp2 := Vector2(-d2.y, d2.x)
			var half := float(ground_cfg.get("wall_length", 150.0)) / 2.0
			draw_line(point_local - perp2 * half, point_local + perp2 * half, Color(0.85, 0.75, 0.5, 0.9), 4.0)
			draw_line(point_local - perp2 * half, point_local + perp2 * half, Color(0.5, 0.42, 0.3, 0.5), 9.0)
		draw_arc(point_local, 10.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.7, 0.9), 2.0)
	if state == State.CHANNEL:
		draw_arc(NINJA_ANCHOR, 30.0, 0.0, TAU, 24, Color(0.4, 0.95, 0.6, 0.75), 2.5)
		draw_rect(Rect2(NINJA_ANCHOR.x - 2, NINJA_ANCHOR.y - 2, 4, 12), Color(0.5, 1.0, 0.65, 0.9))
		draw_rect(Rect2(NINJA_ANCHOR.x - 8, NINJA_ANCHOR.y + 4, 16, 4), Color(0.5, 1.0, 0.65, 0.9))
	if orb_active:
		var op := _orb_pos() - global_position
		var or_ := float(orb_cfg.get("orb_radius", 16.0))
		var pulse := 1.0 + 0.12 * sin(orb_timer * 22.0)
		draw_circle(op, or_ * pulse, Color(0.55, 0.78, 1.0, 0.9))
		draw_circle(op, or_ * 0.5, Color(0.92, 0.98, 1.0, 0.95))
		draw_arc(op, or_ + 5.0, orb_timer * 6.0, orb_timer * 6.0 + TAU * 0.65, 14, Color(0.7, 0.9, 1.0, 0.7), 2.0)
		draw_arc(op, or_ + 9.0, -orb_timer * 4.0, -orb_timer * 4.0 + TAU * 0.5, 16, Color(0.6, 0.85, 1.0, 0.4), 1.5)
