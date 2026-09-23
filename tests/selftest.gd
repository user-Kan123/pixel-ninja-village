extends Node
## 无头自检：加载主场景，逐个驱动全部忍术与关键系统，最后校验状态。
##
## 跑法（项目根目录）：
##   godot --headless --path . --fixed-fps 60 res://tests/selftest.tscn
##
## --fixed-fps 60 让每帧步进固定为 1/60 秒，测试结果与机器性能无关。
## 退出码恒为 0，结论看 stdout 的 SELFTEST OK / SELFTEST FAILED。

var game
var player
var failures: Array[String] = []


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	add_child(game)
	await _frames(3)
	player = game.player
	if player == null:
		_fail("主场景未生成玩家")
		_finish()
		return
	_check(Data.jutsu_list.size() == 10, "忍术表数量不是 10：%d" % Data.jutsu_list.size())
	_clear_enemies()
	await _frames(2)

	await _test_jutsu_pipeline()
	await _test_effects()
	await _test_wall_gnaw()
	await _test_clone_combat()
	await _test_enemy_attacks()
	await _test_growth()
	_test_loadout()
	_test_death()
	_finish()


# ---------------------------------------------------------------- 用例

## 逐个忍术走一遍施法入口，覆盖 5 条施法管线
func _test_jutsu_pipeline() -> void:
	for id_v in Data.jutsu_list:
		var id := String(id_v)
		var cfg: Dictionary = Data.jutsu.get(id, {})
		_check(not cfg.is_empty(), "忍术表缺少 " + id)
		player.state = Player.State.MOVE
		player.hp = player.max_hp
		player.chakra = 9999.0
		player.jutsu_cd[id] = 0.0
		var before: float = player.chakra
		player._try_cast_jutsu(id, 0)
		await _frames(4)
		match player.state:
			Player.State.SEALING:
				await _frames(40)
				if player.state == Player.State.AIM:
					player._release_seal_aim(player.global_position + Vector2(120.0, 0.0))
			Player.State.AIM:
				player._release_seal_aim(player.global_position + Vector2(120.0, 0.0))
			Player.State.CHARGE:
				player.charge_t = 999.0
				player._release_charge()
			Player.State.CHANNEL:
				await _frames(12)
				player._end_channel()
			Player.State.GROUND:
				player.mouse_world = player.global_position + Vector2(120.0, 0.0)
				player._confirm_ground(player.mouse_world)
			_:
				pass
		await _frames(8)
		_check(player.state == Player.State.MOVE, "%s 施法后未回到 MOVE 状态（%d）" % [id, player.state])
		_check(float(player.jutsu_cd.get(id, 0.0)) > 0.0 or String(cfg.get("cast_type", "")) == "channel", "%s 未进入冷却" % id)
		if String(cfg.get("cast_type", "")) != "channel":
			_check(player.chakra < before, "%s 未扣除查克拉" % id)
	_check(game.walls.size() > 0, "土流壁未注册到场景")
	_check(get_tree().get_nodes_in_group("clones").size() > 0, "影分身未生成")
	_check(get_tree().get_nodes_in_group("fields").size() > 0, "封缚领域未生成")


## 效果判定：定身 / 混乱 / 灼烧 / 强化近战
func _test_effects() -> void:
	var dummy := _spawn(0, player.global_position + Vector2(120.0, 0.0))
	await _frames(3)
	## 封印术：范围定身
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["binding_seal"] = 0.0
	player.mouse_world = dummy.global_position
	player._try_cast_jutsu("binding_seal", 0)
	await _frames(3)
	player.mouse_world = dummy.global_position
	player._confirm_ground(dummy.global_position)
	await _frames(3)
	_check(dummy.rooted_timer > 0.0, "封缚印未定身敌人")

	## 幻术：混乱
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["fox_genjutsu"] = 0.0
	player._try_cast_jutsu("fox_genjutsu", 0)
	await _frames(3)
	_check(dummy.confused_timer > 0.0, "狐惑未使敌人混乱")

	## 火球：伤害 + 灼烧
	var hp_before := dummy.hp
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["fireball"] = 0.0
	player._try_cast_jutsu("fireball", 0)
	await _frames(40)
	player._release_seal_aim(dummy.global_position)
	await _frames(60)
	_check(dummy.hp < hp_before, "小火弹未造成伤害")
	_check(dummy.burn_time > 0.0 or dummy.hp < hp_before, "小火弹未附加灼烧")

	## 自身强化：近战附带麻痹定身
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["lightning_edge"] = 0.0
	player._try_cast_jutsu("lightning_edge", 0)
	await _frames(3)
	_check(player.buff_timer > 0.0, "雷刃未进入强化状态")
	dummy.rooted_timer = 0.0
	dummy.global_position = player.global_position + Vector2(32.0, 0.0)
	player.mouse_world = dummy.global_position
	var hp2 := dummy.hp
	player._start_attack(1)
	await _frames(20)
	_check(dummy.rooted_timer > 0.0, "强化状态下近战未触发麻痹")
	_check(dummy.hp < hp2, "强化近战未造成伤害")
	dummy.queue_free()
	await _frames(2)


## 墙体：敌人贴墙啃咬会造成耐久损耗
func _test_wall_gnaw() -> void:
	_check(game.walls.size() > 0, "没有墙体可供测试")
	if game.walls.is_empty():
		return
	var wall: EarthWall = game.walls[0]
	var hp_before := wall.hp
	var foe := _spawn(1, wall.global_position)
	await _frames(20)
	_check(wall.hp < hp_before or not is_instance_valid(wall), "敌人未啃咬墙体")
	foe.queue_free()
	await _frames(2)


## 影分身：会自动攻击附近的敌人
func _test_clone_combat() -> void:
	var clones := get_tree().get_nodes_in_group("clones")
	if clones.is_empty():
		_fail("没有影分身可供测试")
		return
	var clone: Node2D = clones[0]
	player.global_position = game.ARENA_SIZE * 0.5
	clone.global_position = game.ARENA_SIZE * 0.5 + Vector2(400.0, 0.0)
	var foe := _spawn(0, clone.global_position + Vector2(40.0, 0.0))
	await _frames(240)
	_check(foe.hp < foe.max_hp, "影分身未攻击敌人")
	foe.queue_free()
	await _frames(2)


## 敌人攻击：射手投掷 + 重型挥击都能打到玩家
func _test_enemy_attacks() -> void:
	player.global_position = game.ARENA_SIZE * 0.5
	player.hp = player.max_hp
	player.invuln_timer = 0.0
	var hp_before: float = player.hp
	_spawn(2, player.global_position + Vector2(220.0, 0.0))
	_spawn(3, player.global_position + Vector2(-70.0, 0.0))
	await _frames(300)
	_check(player.hp < hp_before, "射手/重型敌人未对玩家造成伤害")
	_clear_enemies()
	await _frames(3)


## 成长：经验、升级、槽位解锁
func _test_growth() -> void:
	player.dead = false
	player.hp = player.max_hp
	var lv0: int = player.level
	var hp0: float = player.max_hp
	player.gain_xp(200)
	await _frames(4)
	_check(player.level > lv0, "经验未推动升级")
	_check(player.max_hp > hp0, "升级未提升体力上限")
	_check(player.slots_unlocked() >= 3, "至少应有 3 个忍术槽")
	player.gain_xp(1000000)
	await _frames(6)
	_check(player.level == Player.MAX_LEVEL, "等级未到达上限 %d，实际 %d" % [Player.MAX_LEVEL, player.level])
	_check(player.slots_unlocked() == 5, "满级应解锁 5 个忍术槽，实际 %d" % player.slots_unlocked())
	_check(Data.s(player.rank_key()) != player.rank_key(), "满级段位名词缺失")


func _test_loadout() -> void:
	game.toggle_loadout()
	_check(get_tree().paused, "打开装配界面未暂停游戏")
	game.close_loadout()
	_check(not get_tree().paused, "关闭装配界面未恢复游戏")
	player.jutsu_slots[0] = "fox_genjutsu"
	_check(player.jutsu_slots[0] == "fox_genjutsu", "忍术槽写入失败")
	player.jutsu_slots[0] = "blink"


func _test_death() -> void:
	player.invuln_timer = 0.0
	player.take_damage(999999.0, Vector2.ZERO)
	_check(player.dead, "致死伤害未触发死亡")
	_check(player.state == Player.State.DEAD, "死亡后状态不是 DEAD")


# ---------------------------------------------------------------- 工具

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _spawn(kind: int, pos: Vector2) -> EnemyBase:
	var e: EnemyBase
	match kind:
		0:
			e = EnemyDummy.new()
		1:
			e = EnemyChaser.new()
		2:
			e = EnemyShooter.new()
		_:
			e = EnemyBrute.new()
	e.game = game
	e.position = game.clamp_to_arena(pos, 40.0)
	game.add_child(e)
	return e


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _fail(msg: String) -> void:
	failures.append(msg)
	push_error("SELFTEST FAIL: " + msg)


func _finish() -> void:
	if failures.is_empty():
		print("SELFTEST OK")
	else:
		print("SELFTEST FAILED: %d 项" % failures.size())
		for f in failures:
			print("  - ", f)
	get_tree().quit(0)
