extends Node
## 无头自检：加载场景，逐个驱动全部忍术、效果、拾取、任务流与存档，最后校验状态。
##
## 跑法（项目根目录）：
##   godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/selftest.tscn
##
## --fixed-fps 60 让每帧步进固定为 1/60 秒，测试结果与机器性能无关。
## 退出码恒为 0，结论看 stdout 的 SELFTEST OK / SELFTEST FAILED。

var game
var player
var failures: Array[String] = []
var save_backup := ""


## 绘制探针：PixelArt 的绘制调用只能在 CanvasItem._draw() 内执行，
## 直接调用会刷 "Drawing is only allowed inside this node's _draw()" 并污染日志。
## 用这个空节点承载绘制，既验证"三种 pattern 都不崩"，也不产生假报错。
class DrawProbe extends Node2D:
	var drew := false

	func _draw() -> void:
		drew = true
		for pat in ["cloud", "armor", ""]:
			var cfg: Dictionary = Player.NINJA_CFG.duplicate(true)
			cfg["pattern"] = pat
			cfg["flash_a"] = 1.0
			PixelArt.draw_ninja(self, Vector2(60, 60), cfg, 0, 3.0)
			PixelArt.draw_ninja(self, Vector2(140, 60), cfg, 1, 3.0)
		PixelArt.draw_dummy(self, Vector2(220, 60), 0.5, 3.0)


func _ready() -> void:
	## 备份真实存档，测试结束后原样恢复（避免测试污染玩家进度）
	if FileAccess.file_exists(Flow.SAVE_PATH):
		save_backup = FileAccess.get_file_as_string(Flow.SAVE_PATH)
	_reset_flow()
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	add_child(game)
	await _frames(3)
	player = game.player
	if player == null:
		_fail("主场景未生成玩家")
		_finish()
		return
	_bind_player()
	_check(Data.jutsu_list.size() == 15, "忍术表数量不是 15：%d" % Data.jutsu_list.size())
	_check(Data.missions.size() == 3, "任务表数量不是 3：%d" % Data.missions.size())
	_check(Data.weapon_list.size() == 4, "忍具表数量不是 4：%d" % Data.weapon_list.size())
	_check(player.slots_unlocked() == 5, "测试模式下 1 级应解锁 5 个忍术槽：%d" % player.slots_unlocked())
	_clear_enemies()
	await _frames(2)

	await _test_jutsu_pipeline()
	await _test_effects()
	await _test_rasengan()
	await _test_passives()
	await _test_pickup()
	await _test_wall_gnaw()
	await _test_clone_combat()
	await _test_enemy_attacks()
	await _test_growth()
	await _test_test_mode()
	_test_loadout()
	await _test_weapons()
	_test_mouse_move()
	_test_flow_save()
	await _test_mission_hunt()
	await _test_mission_collect()
	await _test_mission_survive()
	await _test_wild_and_pending()
	await _test_death()
	await _test_ui_clicks()
	await _test_shop()
	_finish()


# ---------------------------------------------------------------- 忍术管线

## 逐个忍术走一遍施法入口，覆盖 6 条施法管线
func _test_jutsu_pipeline() -> void:
	for id_v in Data.jutsu_list:
		var id := String(id_v)
		var cfg: Dictionary = Data.jutsu.get(id, {})
		_check(not cfg.is_empty(), "忍术表缺少 " + id)
		var cast_type := String(cfg.get("cast_type", ""))
		player.state = Player.State.MOVE
		player.orb_active = false
		player.hp = player.max_hp
		player.chakra = 9999.0
		player.jutsu_cd[id] = 0.0
		var before: float = player.chakra
		player._try_cast_jutsu(id, 0)
		await _frames(4)
		if cast_type == "passive":
			## 被动：装配即生效，按键无操作
			_check(player.state == Player.State.MOVE, "%s 被动不应改变状态" % id)
			continue
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
		_check(float(player.jutsu_cd.get(id, 0.0)) > 0.0 or cast_type == "channel", "%s 未进入冷却" % id)
		if cast_type != "channel":
			_check(player.chakra < before, "%s 未扣除查克拉" % id)
	_check(game.walls.size() > 0, "土流壁未注册到场景")
	_check(get_tree().get_nodes_in_group("clones").size() > 0, "影分身未生成")
	_check(get_tree().get_nodes_in_group("fields").size() > 0, "封缚领域未生成")


## 效果判定：定身 / 混乱 / 灼烧 / 强化近战
func _test_effects() -> void:
	var dummy := _spawn(0, player.global_position + Vector2(120.0, 0.0))
	await _frames(3)
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

	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["fox_genjutsu"] = 0.0
	player._try_cast_jutsu("fox_genjutsu", 0)
	await _frames(3)
	_check(dummy.confused_timer > 0.0, "狐惑未使敌人混乱")

	var hp_before: float = dummy.hp
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["fireball"] = 0.0
	player._try_cast_jutsu("fireball", 0)
	await _frames(40)
	player._release_seal_aim(dummy.global_position)
	await _frames(60)
	_check(dummy.hp < hp_before, "小火弹未造成伤害")

	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["lightning_edge"] = 0.0
	player._try_cast_jutsu("lightning_edge", 0)
	await _frames(3)
	_check(player.buff_timer > 0.0, "雷刃未进入强化状态")
	dummy.rooted_timer = 0.0
	dummy.global_position = player.global_position + Vector2(32.0, 0.0)
	player.mouse_world = dummy.global_position
	var hp2: float = dummy.hp
	player._start_attack(1)
	await _frames(20)
	_check(dummy.rooted_timer > 0.0, "强化状态下近战未触发麻痹")
	_check(dummy.hp < hp2, "强化近战未造成伤害")
	dummy.queue_free()
	await _frames(2)


## 附身触发：螺旋丸手持丸子，接触敌人引爆
func _test_rasengan() -> void:
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.jutsu_cd["rasengan"] = 0.0
	player._try_cast_jutsu("rasengan", 0)
	await _frames(3)
	_check(player.orb_active, "螺旋丸未生成丸子")
	## 假人先放在远处：丸子挂在玩家身上 24 像素处，放太近会在采样基准血量前就被引爆
	var dummy := _spawn(0, player.global_position + Vector2(400.0, 0.0))
	await _frames(2)
	var hp_before: float = dummy.hp
	## 把假人搬到丸子实际所在位置（_orb_pos() 就是游戏放置丸子用的同一个函数）
	dummy.global_position = player._orb_pos()
	await _frames(10)
	_check(not player.orb_active, "螺旋丸接触后未引爆")
	_check(dummy.hp < hp_before or dummy.dead, "螺旋丸未造成伤害")
	## 近战在持丸期间被禁用（本次丸子已引爆，验证可正常出刀）
	player._request_attack()
	await _frames(2)
	_check(player.state == Player.State.ATTACK, "丸子引爆后近战未恢复")
	player.state = Player.State.MOVE
	dummy.queue_free()
	await _frames(2)


## 被动常驻：写轮眼闪避 / 替身术免死 / 查克拉活性 / 怪力
func _test_passives() -> void:
	## 写轮眼·洞察：40 次受击统计闪避次数（期望约 25%）
	player.jutsu_slots[0] = "sharingan_insight"
	player.dead = false
	player.invuln_timer = 0.0
	var dodged := 0
	for i in 40:
		player.hp = player.max_hp
		var before: float = player.hp
		player.take_damage(2.0, Vector2.ZERO)
		if player.hp == before:
			dodged += 1
	_check(dodged >= 2 and dodged <= 22, "写轮眼闪避次数异常：%d / 40" % dodged)

	## 替身术：致死伤害免死一次并进入冷却
	player.jutsu_slots[0] = "substitution"
	player.dead = false
	player.invuln_timer = 0.0
	player.jutsu_cd["substitution"] = 0.0
	player.hp = 5.0
	player.take_damage(9999.0, Vector2(100.0, 0.0))
	_check(not player.dead, "替身术未免死")
	_check(player.hp == 1.0, "替身后体力应为 1，实际 %s" % player.hp)
	_check(float(player.jutsu_cd.get("substitution", 0.0)) > 0.0, "替身术未进入冷却")

	## 查克拉活性 / 怪力：数值断言
	player.jutsu_slots[0] = "chakra_flow"
	_check(player._passive_mult("chakra_flow", "chakra_regen_mult", 1.0) > 1.2, "查克拉活性未生效")
	player.jutsu_slots[0] = ""
	_check(player._passive_mult("chakra_flow", "chakra_regen_mult", 1.0) == 1.0, "卸下后被动仍在生效")

	player.jutsu_slots[0] = "monstrous_strength"
	var dummy := _spawn(0, player.global_position + Vector2(34.0, 0.0))
	await _frames(2)
	player.mouse_world = dummy.global_position
	player.state = Player.State.MOVE
	var hp_before2: float = dummy.hp
	player._start_attack(1)
	await _frames(20)
	var dealt: float = hp_before2 - dummy.hp
	_check(dealt > 9.5, "怪力加成的近战伤害异常：%s（期望约 10.4）" % dealt)
	dummy.queue_free()
	player.jutsu_slots[0] = "blink"
	await _frames(2)


## 拾取物：回血药
func _test_pickup() -> void:
	player.dead = false
	player.hp = player.max_hp * 0.5
	var hp_before: float = player.hp
	Pickup.create(game.field_container, player.global_position + Vector2(10.0, 0.0), "hp", game)
	await _frames(6)
	_check(player.hp > hp_before, "回血药未生效")
	_check(get_tree().get_nodes_in_group("pickups").size() == 0, "拾取后药瓶未消失")


## 墙体：敌人贴墙啃咬会造成耐久损耗
func _test_wall_gnaw() -> void:
	_check(game.walls.size() > 0, "没有墙体可供测试")
	if game.walls.is_empty():
		return
	var wall: EarthWall = game.walls[0]
	var hp_before: float = wall.hp
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
	player.global_position = game.arena_size * 0.5
	clone.global_position = game.arena_size * 0.5 + Vector2(400.0, 0.0)
	var foe := _spawn(0, clone.global_position + Vector2(40.0, 0.0))
	await _frames(240)
	_check(foe.hp < foe.max_hp, "影分身未攻击敌人")
	foe.queue_free()
	await _frames(2)


## 敌人攻击：射手投掷 + 重型挥击 + 精英扇形投掷都能打到玩家
func _test_enemy_attacks() -> void:
	player.global_position = game.arena_size * 0.5
	player.dead = false
	player.hp = player.max_hp
	player.invuln_timer = 0.0
	player.jutsu_slots[0] = "blink"
	var hp_before: float = player.hp
	_spawn(2, player.global_position + Vector2(220.0, 0.0))
	_spawn(3, player.global_position + Vector2(-70.0, 0.0))
	_spawn(4, player.global_position + Vector2(200.0, -160.0))
	await _frames(300)
	_check(player.hp < hp_before, "射手/重型/精英敌人未对玩家造成伤害")
	_clear_enemies()
	await _frames(3)


## 成长：经验、升级、槽位解锁
## 注意：这里必须关掉测试模式，否则 slots_unlocked() 恒为 5，"按等级解锁"这条逻辑就测不到了。
func _test_growth() -> void:
	Flow.test_unlock_all = false
	player.dead = false
	player.hp = player.max_hp
	player.level = 1
	player.xp = 0
	player.xp_next = 40
	_check(player.slots_unlocked() == 3, "1 级应有 3 个忍术槽，实际 %d" % player.slots_unlocked())
	var lv0: int = player.level
	var hp0: float = player.max_hp
	player.gain_xp(200)
	await _frames(4)
	_check(player.level > lv0, "经验未推动升级")
	_check(player.max_hp > hp0, "升级未提升体力上限")
	player.gain_xp(1000000)
	await _frames(6)
	_check(player.level == Player.MAX_LEVEL, "等级未到达上限 %d，实际 %d" % [Player.MAX_LEVEL, player.level])
	_check(player.slots_unlocked() == 5, "满级应解锁 5 个忍术槽，实际 %d" % player.slots_unlocked())
	## 钉住 SLOT_UNLOCK_LEVELS 这张表：6 级 4 槽、12 级 5 槽
	player.level = 6
	_check(player.slots_unlocked() == 4, "6 级应解锁 4 个忍术槽，实际 %d" % player.slots_unlocked())
	player.level = 12
	_check(player.slots_unlocked() == 5, "12 级应解锁 5 个忍术槽，实际 %d" % player.slots_unlocked())
	_check(Data.s(player.rank_key()) != player.rank_key(), "满级段位名词缺失")
	Flow.test_unlock_all = true


## 测试模式：无视等级，15 个忍术全部可用 + 5 个忍术槽全解锁。
## 覆盖三件事：开关真的进了槽位门槛、5 个槽都能按键进入施法、关掉后门槛立刻回来。
func _test_test_mode() -> void:
	Flow.test_unlock_all = true
	Flow.level = 1
	Flow.apply_to_player(player)
	player.dead = false
	player.level = 1
	_check(player.slots_unlocked() == 5, "测试模式下 1 级未解锁 5 个槽：%d" % player.slots_unlocked())
	_check(player.jutsu_slots.size() == 5, "忍术槽数量不是 5：%d" % player.jutsu_slots.size())
	## 5 个槽各装一个不同施法管线的忍术（瞬时 / 结印瞄准 / 蓄力 / 坐标选择 / 引导）
	var probes := ["blink", "fireball", "great_fireball", "earth_wall", "medical_palm"]
	for i in probes.size():
		player.jutsu_slots[i] = probes[i]
		_check(not Data.jutsu.get(probes[i], {}).is_empty(), "探针忍术缺失：" + probes[i])
	for i in 5:
		_abort_cast()
		player.chakra = 9999.0
		player.jutsu_cd[probes[i]] = 0.0
		player._on_slot_pressed(i)
		await _frames(2)
		var acted: bool = player.state != Player.State.MOVE or float(player.jutsu_cd.get(probes[i], 0.0)) > 0.0
		_check(acted, "测试模式下第 %d 槽（%s）按键无反应" % [i + 1, probes[i]])
	_abort_cast()
	## 关掉开关：门槛立刻回来，未解锁的第 5 槽按键无反应
	Flow.test_unlock_all = false
	player.level = 1
	_check(player.slots_unlocked() == 3, "关闭测试模式后 1 级应为 3 个槽：%d" % player.slots_unlocked())
	player.chakra = 9999.0
	player.jutsu_cd["medical_palm"] = 0.0
	player._on_slot_pressed(4)
	await _frames(2)
	_check(player.state == Player.State.MOVE, "关闭测试模式后未解锁的第 5 槽仍能施法")
	_abort_cast()
	## F1 真实按键切换（走 player._unhandled_input）
	_push_key(KEY_F1)
	await _frames(2)
	_check(Flow.test_unlock_all, "F1 未开启测试模式")
	_push_key(KEY_F1)
	await _frames(2)
	_check(not Flow.test_unlock_all, "F1 未关闭测试模式")
	_push_key(KEY_F1)
	await _frames(2)
	_check(Flow.test_unlock_all, "F1 未重新开启测试模式")
	## 收尾：恢复默认装配，别把探针忍术留给后面的用例
	for i in Player.DEFAULT_LOADOUT.size():
		player.jutsu_slots[i] = Player.DEFAULT_LOADOUT[i]
	_abort_cast()


func _test_loadout() -> void:
	game.toggle_loadout()
	_check(get_tree().paused, "打开装配界面未暂停游戏")
	game.close_loadout()
	_check(not get_tree().paused, "关闭装配界面未恢复游戏")
	player.jutsu_slots[0] = "fox_genjutsu"
	_check(player.jutsu_slots[0] == "fox_genjutsu", "忍术槽写入失败")
	player.jutsu_slots[0] = "blink"


## 忍具与装备系统：数据表、武器槽、四种忍具的数值梯度、投掷、切换、装配规则、商店购买
func _test_weapons() -> void:
	_check(Data.weapons.size() == 4, "忍具表数量不是 4：%d" % Data.weapons.size())
	for id_v in ["shuriken", "kunai", "tanto", "longsword"]:
		var wid := String(id_v)
		_check(not Data.weapon(wid).is_empty(), "忍具表缺少 " + wid)
		_check(Data.weapon_name(wid) != wid, "忍具缺少名词：" + wid)
		_check(Data.weapon_mode(wid) != "", "忍具缺少使用方式：" + wid)
	## 价格梯度：手里剑 < 苦无 < 短刀 < 长剑
	var prices: Array = []
	for id_v in ["shuriken", "kunai", "tanto", "longsword"]:
		prices.append(int(Data.weapon(String(id_v)).get("price", 0)))
	for i in range(1, prices.size()):
		_check(int(prices[i]) > int(prices[i - 1]), "忍具价格没有递增：%s" % str(prices))

	## 四种都塞进背包，后面逐个装配比较
	for id_v in ["shuriken", "kunai", "tanto", "longsword"]:
		if not Flow.owns_weapon(String(id_v)):
			Flow.owned_weapons.append(String(id_v))
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "")
	player.active_weapon = 0
	_check(player.weapon_id() == "kunai", "默认主手不是苦无：%s" % player.weapon_id())
	_check(player.can_melee(), "苦无应能近战")
	_check(player.can_throw(), "苦无应能投掷")

	## 手里剑：只能投掷，左键不出刀
	player.equip_weapon(1, "shuriken")
	player.active_weapon = 1
	_check(player.weapon_id() == "shuriken", "副手未装上手里剑：%s" % player.weapon_id())
	_check(not player.can_melee(), "手里剑不应能近战")
	_check(player.can_throw(), "手里剑应能投掷")
	player.state = Player.State.MOVE
	player.weapon_hint_t = 0.0
	player._request_attack()
	await _frames(2)
	_check(player.state == Player.State.MOVE, "手里剑按左键不应出刀")

	## 投掷：手里剑伤害低、携带多、回手快
	var sh_ammo: int = player.ammo_count("shuriken")
	player._throw_weapon(player.global_position + Vector2(200.0, 0.0))
	var proj = _last_projectile()
	_check(proj != null and String(proj.kind) == "shuriken", "投出的不是手里剑")
	if proj != null:
		_check(is_equal_approx(float(proj.damage), float(Data.weapon("shuriken")["throw_damage"])),
			"手里剑投掷伤害不符：%s" % str(proj.damage))
		proj.queue_free()
	_check(player.ammo_count("shuriken") == sh_ammo - 1,
		"投掷未消耗忍具：%d → %d" % [sh_ammo, player.ammo_count("shuriken")])
	_check(player.ammo_max("shuriken") > player.ammo_max("kunai"), "手里剑携带量应多于苦无")
	_check(float(Data.weapon("shuriken")["throw_recharge"]) < float(Data.weapon("kunai")["throw_recharge"]),
		"手里剑回手应快于苦无")
	_check(float(Data.weapon("shuriken")["throw_damage"]) < float(Data.weapon("kunai")["throw_damage"]),
		"手里剑投掷伤害应低于苦无")
	## 回手计时：清零后跑够一个间隔应自动补上
	player.ammo["shuriken"] = 1
	player.ammo_recharge["shuriken"] = 0.0
	await _frames(130)
	_check(player.ammo_count("shuriken") > 1, "手里剑按回手间隔未自动补充：%d" % player.ammo_count("shuriken"))

	## 近战数值梯度：短刀 > 苦无；长剑范围更大、伤害接近短刀、出手更慢
	player.equip_weapon(0, "kunai")
	player.active_weapon = 0
	var kunai_dmg := float(player._melee_step(1)["damage"])
	var kunai_reach: float = player.melee_reach()
	var kunai_windup := float(player._melee_step(1)["windup"])
	player.equip_weapon(0, "tanto")
	var tanto_dmg := float(player._melee_step(1)["damage"])
	var tanto_reach: float = player.melee_reach()
	var tanto_windup := float(player._melee_step(1)["windup"])
	player.equip_weapon(0, "longsword")
	var ls_dmg := float(player._melee_step(1)["damage"])
	var ls_reach: float = player.melee_reach()
	var ls_windup := float(player._melee_step(1)["windup"])
	_check(tanto_dmg > kunai_dmg, "短刀近战伤害应高于苦无：%.1f vs %.1f" % [tanto_dmg, kunai_dmg])
	_check(kunai_reach < tanto_reach, "苦无近战范围应小于短刀：%.1f vs %.1f" % [kunai_reach, tanto_reach])
	_check(ls_reach > tanto_reach * 1.2, "长剑范围应明显大于短刀：%.1f vs %.1f" % [ls_reach, tanto_reach])
	_check(absf(ls_dmg - tanto_dmg) <= tanto_dmg * 0.25, "长剑伤害应与短刀接近：%.1f vs %.1f" % [ls_dmg, tanto_dmg])
	_check(ls_windup > tanto_windup, "长剑出手应慢于短刀：%.3f vs %.3f" % [ls_windup, tanto_windup])

	## 实打实砍一刀，确认数值差距落到了敌人身上
	var dummy := _spawn(0, player.global_position + Vector2(30.0, 0.0))
	await _frames(2)
	player.attack_dir = Vector2.RIGHT
	player.equip_weapon(0, "kunai")
	var hp0: float = dummy.hp
	player.attack_step = player._melee_step(1)
	player._do_melee_hit()
	var kunai_hit: float = hp0 - dummy.hp
	player.equip_weapon(0, "tanto")
	var hp1: float = dummy.hp
	player.attack_step = player._melee_step(1)
	player._do_melee_hit()
	var tanto_hit: float = hp1 - dummy.hp
	_check(kunai_hit > 0.0, "苦无近战没打到敌人")
	_check(tanto_hit > kunai_hit, "短刀实战伤害应高于苦无：%.1f vs %.1f" % [tanto_hit, kunai_hit])
	dummy.queue_free()
	await _frames(2)

	## Q 切换主副手
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "tanto")
	player.active_weapon = 0
	_check(player.switch_weapon() == "tanto", "切换武器未切到副手")
	_check(player.weapon_id() == "tanto", "切换后当前忍具不对：%s" % player.weapon_id())
	_check(player.switch_weapon() == "kunai", "切换武器未切回主手")

	## 同一件忍具不会占两个槽
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "kunai")
	_check(player.weapon_at(0) != player.weapon_at(1),
		"同一件忍具占了两个槽：%s / %s" % [player.weapon_at(0), player.weapon_at(1)])

	## 未拥有的忍具装不上
	Flow.owned_weapons.erase("longsword")
	player.equip_weapon(0, "longsword")
	_check(player.weapon_id() != "longsword", "未拥有的忍具被装上了武器槽")

	## 商店：赏金不足买不了 / 买完进背包并扣钱 / 重复购买被拒
	Flow.money = 10
	var poor := Flow.buy_weapon("longsword")
	_check(not bool(poor["ok"]) and String(poor["reason"]) == "no_money", "赏金不足时仍能买忍具")
	var ls_price := int(Data.weapon("longsword")["price"])
	Flow.money = ls_price + 5
	var bought := Flow.buy_weapon("longsword")
	_check(bool(bought["ok"]), "赏金足够时买不到忍具：%s" % str(bought))
	_check(Flow.owns_weapon("longsword"), "买到的忍具没进背包")
	_check(Flow.money == 5, "购买没扣赏金：%d" % Flow.money)
	var again := Flow.buy_weapon("longsword")
	_check(not bool(again["ok"]) and String(again["reason"]) == "owned", "重复购买未被拒绝")

	## 收尾：恢复主手苦无
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "")
	player.active_weapon = 0
	player.state = Player.State.MOVE


## Flow：赏金 / 天数 / 存档读写
func _test_flow_save() -> void:
	_reset_flow()
	Flow.money = 123
	Flow.level = 5
	Flow.day = 3
	Flow.owned_weapons.clear()
	Flow.owned_weapons.append("kunai")
	Flow.owned_weapons.append("tanto")
	Flow.weapon_slots.clear()
	Flow.weapon_slots.append("tanto")
	Flow.weapon_slots.append("kunai")
	Flow.save_game()
	Flow.money = 0
	Flow.level = 1
	Flow.day = 1
	Flow.owned_weapons.clear()
	Flow.owned_weapons.append("kunai")
	Flow.weapon_slots.clear()
	Flow.weapon_slots.append("kunai")
	Flow.weapon_slots.append("")
	_check(Flow.load_save(), "存档读取失败")
	_check(Flow.money == 123, "存档金钱不符：%d" % Flow.money)
	_check(Flow.level == 5, "存档等级不符：%d" % Flow.level)
	_check(Flow.day == 3, "存档天数不符：%d" % Flow.day)
	_check(Flow.owned_weapons.has("tanto"), "存档未保留已购买的忍具")
	_check(Flow.weapon_slots[0] == "tanto" and Flow.weapon_slots[1] == "kunai",
		"存档未保留武器槽：%s" % str(Flow.weapon_slots))
	_reset_flow()


# ---------------------------------------------------------------- 任务流

## 讨伐任务：杀满目标 → 结算（赏金 / 天数 / 完成次数）
func _test_mission_hunt() -> void:
	_reset_flow()
	Flow.mission_id = "hunt"
	Flow.mission_cfg = Data.missions["hunt"].duplicate(true)
	Flow.mission_cfg["target_kills"] = 3
	await _reload_battle()
	_check(game.mission_state == game.MissionState.RUNNING, "讨伐任务未进入进行状态")
	for i in 3:
		var e := _spawn(1, player.global_position + Vector2(40.0, 0.0))
		await _frames(2)
		e.take_damage(9999.0, Vector2.ZERO)
		await _frames(3)
	_check(game.mission_kills >= 3, "讨伐计数异常：%d" % game.mission_kills)
	_check(game.mission_state == game.MissionState.WON, "讨伐任务未完成")
	_check(Flow.money == 200, "讨伐赏金异常：%d" % Flow.money)
	_check(Flow.day == 2, "任务完成未过天数：%d" % Flow.day)
	_check(Flow.mission_done_count("hunt") == 1, "任务完成次数未记录")
	_check(int(game.result_rewards.get("xp", 0)) == 60, "讨伐经验奖励异常")


## 收集任务：捡满卷轴 → 完成
func _test_mission_collect() -> void:
	_reset_flow()
	Flow.mission_id = "collect"
	Flow.mission_cfg = Data.missions["collect"].duplicate(true)
	Flow.mission_cfg["scroll_count"] = 2
	await _reload_battle()
	_check(game.mission_state == game.MissionState.RUNNING, "收集任务未进入进行状态")
	for i in 2:
		var found: Pickup = null
		for p in get_tree().get_nodes_in_group("pickups"):
			if p.kind == "intel" and not p.collected:
				found = p
				break
		_check(found != null, "场景中没有可拾取的情报卷轴")
		if found == null:
			break
		player.global_position = found.global_position
		await _frames(4)
	_check(game.mission_intel >= 2, "卷轴回收计数异常：%d" % game.mission_intel)
	_check(game.mission_state == game.MissionState.WON, "收集任务未完成")


## 波次任务：清完两波 → 完成
func _test_mission_survive() -> void:
	_reset_flow()
	Flow.mission_id = "survive"
	Flow.mission_cfg = Data.missions["survive"].duplicate(true)
	Flow.mission_cfg["waves"] = [["chaser"], ["chaser"]]
	await _reload_battle()
	_check(game.mission_state == game.MissionState.RUNNING, "波次任务未进入进行状态")
	_kill_all_enemies()
	await _frames(100)
	_check(game.mission_wave == 2, "第二波未到来：%d" % game.mission_wave)
	_kill_all_enemies()
	await _frames(30)
	_check(game.mission_state == game.MissionState.WON, "波次任务未完成")
	Flow.mission_id = ""
	Flow.mission_cfg = {}


## 待出发机制 + 野外场景：看板接取登记 → 野外场景尺寸/横幅/目标指引/像素绘制/结算
func _test_wild_and_pending() -> void:
	_reset_flow()
	Flow.accept_mission("hunt")
	_check(Flow.pending_mission == "hunt", "看板接取未登记待出发任务")
	Flow.pending_mission = ""
	## 加载野外讨伐场景
	await _load_wild("hunt")
	Flow.mission_cfg["target_kills"] = 2
	_check(game is WildField, "野外场景类型错误")
	_check(game.arena_size == Vector2(2200, 1400), "野外尺寸异常：%s" % str(game.arena_size))
	_check(game.mission_state == game.MissionState.RUNNING, "野外任务未开始")
	_check(game.hud.banner_timer > 0.0, "任务开始横幅未显示")
	## 目标指引：hunt 指向最近敌人
	var t: Dictionary = game.nearest_target()
	_check(bool(t.get("valid", false)), "nearest_target 未找到敌人")
	## 像素绘制：三种 pattern + 木桩都不应崩（走真实 _draw 路径）
	var probe := DrawProbe.new()
	game.add_child(probe)
	await _frames(3)
	_check(probe.drew, "像素绘制未执行（探针 _draw 未被调用）")
	probe.queue_free()
	## 完成野外讨伐
	for i in 2:
		var e := _spawn(1, player.global_position + Vector2(40.0, 0.0))
		await _frames(2)
		e.take_damage(9999.0, Vector2.ZERO)
		await _frames(3)
	_check(game.mission_state == game.MissionState.WON, "野外讨伐未完成")
	## 野外收集：目标指引应指向卷轴
	await _load_wild("collect")
	Flow.mission_cfg["scroll_count"] = 1
	var t2: Dictionary = game.nearest_target()
	_check(bool(t2.get("valid", false)), "collect nearest_target 未找到卷轴")
	Flow.mission_id = ""
	Flow.mission_cfg = {}


func _load_wild(id: String) -> void:
	if game != null:
		game.queue_free()
	await _frames(2)
	Flow.mission_id = id
	Flow.mission_cfg = Data.missions[id].duplicate(true)
	var scene: PackedScene = load("res://scenes/wild.tscn")
	game = scene.instantiate()
	add_child(game)
	await _frames(5)
	player = game.player
	_bind_player()


# ---------------------------------------------------------------- 收尾

## 鼠标跟随移动：远处全速朝鼠标 → 近处减速 → 贴到身上站住。
## 注意 _move_input() 读的是 player.mouse_world（不是直接读真实鼠标），所以可以确定性断言；
## 但 _physics_process 每帧会覆写 mouse_world，因此断言必须在同一帧内同步做完，不能 await。
func _test_mouse_move() -> void:
	## 本函数手工喂 mouse_world，先关掉"粘住模式"
	player.mouse_sticky = false
	var origin: Vector2 = player.global_position
	## 远处：满速朝鼠标方向
	player.mouse_world = origin + Vector2(400.0, 0.0)
	var far: Vector2 = player._move_input()
	_check(absf(far.length() - 1.0) < 0.01, "鼠标在远处时未按全速移动：%.3f" % far.length())
	_check(far.x > 0.99 and absf(far.y) < 0.01, "鼠标在右侧时移动方向不对：%s" % str(far))
	## 刚出死区：降到最低速度比例
	player.mouse_world = origin + Vector2(Player.MOUSE_DEAD_ZONE + 1.0, 0.0)
	var edge: Vector2 = player._move_input()
	_check(absf(edge.length() - Player.MOUSE_MIN_SPEED) < 0.05,
		"刚出死区未降到最低速度：%.3f（期望 %.2f）" % [edge.length(), Player.MOUSE_MIN_SPEED])
	## 死区外中段：速度介于最低与全速之间（验证是线性加速而不是二段跳变）
	player.mouse_world = origin + Vector2(Player.MOUSE_DEAD_ZONE + Player.MOUSE_SLOW_BAND * 0.5, 0.0)
	var mid: float = player._move_input().length()
	_check(mid > Player.MOUSE_MIN_SPEED + 0.05 and mid < 0.95, "死区外中段速度未平滑加速：%.3f" % mid)
	## 鼠标压在人物身上 / 与人物重合：站住
	player.mouse_world = origin + Vector2(8.0, 0.0)
	_check(player._move_input().length() == 0.0, "鼠标贴着人物时未站住")
	player.mouse_world = origin
	_check(player._move_input().length() == 0.0, "鼠标与人物重合时未站住")
	## 朝向保持：鼠标压在人物身上时 face_dir 不应被重置（_update_face 只读 mouse_world，可确定性断言）
	player.face_dir = Vector2.LEFT
	player.mouse_world = origin + Vector2(6.0, 0.0)
	player._update_face()
	_check(player.face_dir == Vector2.LEFT, "鼠标贴住人物时朝向被改动了：%s" % str(player.face_dir))
	player.mouse_world = origin + Vector2(300.0, 0.0)
	player._update_face()
	_check(player.face_dir.x > 0.99, "鼠标拉远后朝向未更新：%s" % str(player.face_dir))
	player.face_dir = Vector2.RIGHT
	## 恢复粘住模式：鼠标恒等于人物位置 → 恒站住（后续测试依赖玩家不乱跑）
	player.mouse_sticky = true
	player._physics_process(1.0 / 60.0)
	_check(player.mouse_world == player.global_position, "粘住模式下鼠标未跟随人物")
	_check(player._move_input().length() == 0.0, "粘住模式下人物未站住")


func _test_death() -> void:
	Flow.mission_id = ""
	Flow.mission_cfg = {}
	await _reload_battle()
	player.invuln_timer = 0.0
	player.take_damage(999999.0, Vector2.ZERO)
	_check(player.dead, "致死伤害未触发死亡")
	_check(player.state == Player.State.DEAD, "死亡后状态不是 DEAD")


## 界面可点性 + 一屏内布局。
## 回归点：挂在 CanvasLayer 上的 Control 只调 set_anchors_preset 不会撑开尺寸，
## size 停在 (0,0) —— 界面画得出来但鼠标命中测试永远失败，点击完全没反应。
## 所以这里走真实的 push_input 派发，而不是直接调 _gui_input（后者测不出这个病）。
func _test_ui_clicks() -> void:
	Flow.level = 12
	Flow.loadout.clear()
	for id in Flow.DEFAULT_LOADOUT:
		Flow.loadout.append(String(id))
	game.queue_free()
	await _frames(2)
	var scene: PackedScene = load("res://scenes/village.tscn")
	game = scene.instantiate()
	add_child(game)
	await _frames(3)
	player = game.player
	_bind_player()
	var vp: Vector2 = get_viewport().get_visible_rect().size

	## 任务看板：控件必须铺满视口
	var board = game.board_ui
	_check(board.size == vp, "任务看板尺寸未铺满视口：%s（点击会失效）" % str(board.size))
	Flow.pending_mission = ""
	game.toggle_board()
	await _frames(2)
	_check(game.board_open(), "任务看板未打开")
	_push_click(board._row_rect(0).get_center())
	await _frames(3)
	_check(Flow.pending_mission != "", "点击「接收」未登记待出发任务")
	_check(not game.board_open(), "接取任务后看板未关闭")

	## 装备与背包（B）：控件同样要铺满，默认武器页
	var lu = game.loadout_ui
	_check(lu.size == vp, "装备界面控件尺寸未铺满视口：%s" % str(lu.size))
	game.toggle_loadout()
	await _frames(2)
	_check(lu.visible, "装备界面未打开")
	_check(lu.tab == LoadoutUi.Tab.WEAPON, "装备界面默认不是武器页：%d" % lu.tab)
	## 武器页：4 张忍具卡 + 2 个武器槽都要落在一屏内
	var wlast: float = lu._weapon_card_rect(Data.weapon_list.size() - 1).end.y
	_check(wlast < vp.y, "忍具卡片超出屏幕：%.0f > %.0f" % [wlast, vp.y])
	var wslot_last: float = lu._weapon_slot_rect(Player.WEAPON_SLOT_COUNT - 1).end.y
	_check(wslot_last < vp.y, "武器槽超出屏幕：%.0f > %.0f" % [wslot_last, vp.y])
	## 点「苦无」卡片装到选中的武器槽（需要先拥有）
	Flow.owned_weapons.clear()
	Flow.owned_weapons.append("kunai")
	Flow.owned_weapons.append("tanto")
	player.equip_weapon(0, "")
	player.equip_weapon(1, "")
	lu.selected_weapon_slot = 0
	_push_click(lu._weapon_card_rect(Data.weapon_list.find("kunai")).get_center())
	await _frames(3)
	_check(player.weapon_at(0) == "kunai", "点击忍具卡片未装到武器槽：%s" % player.weapon_at(0))
	## 未拥有的忍具点了不该装上
	lu.selected_weapon_slot = 1
	_push_click(lu._weapon_card_rect(Data.weapon_list.find("longsword")).get_center())
	await _frames(3)
	_check(player.weapon_at(1) != "longsword", "未拥有的忍具被点上了武器槽")
	## 点武器槽可切换选中
	_push_click(lu._weapon_slot_rect(1).get_center())
	await _frames(2)
	_check(lu.selected_weapon_slot == 1, "点击武器槽未切换选中：%d" % lu.selected_weapon_slot)
	## 右键卸下：还剩另一件时可以卸，卸最后一件要被拦住（手上不能什么都没有）
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "tanto")
	_push_click(lu._weapon_slot_rect(0).get_center(), MOUSE_BUTTON_RIGHT)
	await _frames(2)
	_check(player.weapon_at(0).is_empty(), "还有另一件忍具时应能卸下该槽")
	_push_click(lu._weapon_slot_rect(1).get_center(), MOUSE_BUTTON_RIGHT)
	await _frames(2)
	_check(not player.weapon_at(1).is_empty(), "卸下最后一件忍具没有被拦住")
	player.equip_weapon(0, "kunai")
	player.equip_weapon(1, "")
	player.active_weapon = 0

	## Tab 切到忍术页：控件同样要铺满，且 15 个忍术必须全部落在一屏内
	_push_key(KEY_TAB)
	await _frames(2)
	_check(lu.tab == LoadoutUi.Tab.JUTSU, "Tab 未切到忍术页：%d" % lu.tab)
	var total: int = Data.jutsu_list.size()
	var last_y: float = lu._grid_rect(total - 1).end.y
	_check(last_y < vp.y, "忍术网格最后一行超出屏幕：%.0f > %.0f" % [last_y, vp.y])
	lu.selected_slot = 2
	var before: String = player.jutsu_slots[2]
	_push_click(lu._grid_rect(5).get_center())
	await _frames(3)
	_check(player.jutsu_slots[2] != before, "点击忍术卡片未装入槽位")
	## 点左侧槽位可切换选中槽
	_push_click(lu._slot_rect(1).get_center())
	await _frames(2)
	_check(lu.selected_slot == 1, "点击槽位未切换选中：%d" % lu.selected_slot)
	game.close_loadout()
	Flow.pending_mission = ""


## 忍具店：走到店门口按 E 打开 → 点「购买」花赏金买下 → 自动进武器槽 → 关闭
func _test_shop() -> void:
	Flow.money = 500
	Flow.owned_weapons.clear()
	Flow.owned_weapons.append("kunai")
	Flow.weapon_slots.clear()
	Flow.weapon_slots.append("kunai")
	Flow.weapon_slots.append("")
	player.weapon_slots.clear()
	player.weapon_slots.append("kunai")
	player.weapon_slots.append("")
	player.active_weapon = 0
	## 站到忍具店门口
	player.global_position = game.SHOP_POS + Vector2(0.0, 40.0)
	await _frames(2)
	_check(game.current_interact_hint() != "", "站在忍具店门口没有交互提示")
	game.on_interact()
	await _frames(2)
	_check(game.shop_open(), "忍具店未打开")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var shop = game.shop_ui
	_check(shop.size == vp, "忍具店控件尺寸未铺满视口：%s" % str(shop.size))
	## 点「购买」买短刀：扣赏金、进背包、自动装到空的武器槽
	var tanto_idx: int = Data.weapon_list.find("tanto")
	var money_before: int = Flow.money
	_push_click(shop._buy_rect(tanto_idx).get_center())
	await _frames(3)
	_check(Flow.owns_weapon("tanto"), "点「购买」没买到忍具")
	_check(Flow.money == money_before - int(Data.weapon("tanto")["price"]), "购买没扣赏金：%d" % Flow.money)
	_check(player.weapon_at(1) == "tanto", "买到的忍具没自动进武器槽：%s" % str(player.weapon_slots))
	## 已拥有的忍具再点「购买」不会重复扣钱
	var money_after: int = Flow.money
	_push_click(shop._buy_rect(tanto_idx).get_center())
	await _frames(3)
	_check(Flow.money == money_after, "已拥有的忍具被重复扣费")
	game.close_shop()
	_check(not get_tree().paused, "关闭忍具店未恢复游戏")


func _push_click(pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)


## 真实按键派发：走 _input → GUI → _unhandled_input 全链路（直接调函数测不出按键没接上的问题）
func _push_key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	get_viewport().push_input(e)


## 强制中断玩家当前施法并清干净所有施法状态（测试里换用例时用，避免上一段状态粘到下一段）
func _abort_cast() -> void:
	player.state = Player.State.MOVE
	player.seal_cfg = {}
	player.seal_id = ""
	player.seal_slot = -1
	player.charge_cfg = {}
	player.charge_id = ""
	player.charge_slot = -1
	player.ground_cfg = {}
	player.ground_id = ""
	player.ground_slot = -1
	player.channel_cfg = {}
	player.channel_id = ""
	player.channel_slot = -1
	player.orb_active = false
	player.orb_cfg = {}


# ---------------------------------------------------------------- 工具

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _reload_battle() -> void:
	game.queue_free()
	await _frames(2)
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	add_child(game)
	await _frames(3)
	player = game.player
	_bind_player()


## 接管新生成的玩家：把鼠标粘在身上，否则 headless 下鼠标固定在屏幕原点，
## 玩家会一路朝左上角狂奔，任何"站在原地"的断言都会失效。
func _bind_player() -> void:
	player.mouse_sticky = true


func _spawn(kind: int, pos: Vector2) -> EnemyBase:
	var e: EnemyBase
	match kind:
		0:
			e = EnemyDummy.new()
		1:
			e = EnemyChaser.new()
		2:
			e = EnemyShooter.new()
		3:
			e = EnemyBrute.new()
		_:
			e = EnemyElite.new()
	e.game = game
	e.position = game.clamp_to_arena(pos, 40.0)
	game.add_child(e)
	return e


func _kill_all_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.take_damage(99999.0, Vector2.ZERO)


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


## 最近生成的一个投射物（投掷忍具的字段断言用）
func _last_projectile():
	if game == null or game.projectile_container == null:
		return null
	var arr: Array = game.projectile_container.get_children()
	for i in range(arr.size() - 1, -1, -1):
		if arr[i] is Projectile:
			return arr[i]
	return null


func _reset_flow() -> void:
	Flow.level = 1
	Flow.xp = 0
	Flow.money = 0
	Flow.day = 1
	Flow.missions_done = {}
	Flow.mission_id = ""
	Flow.mission_cfg = {}
	Flow.pending_mission = ""
	Flow.owned_weapons.clear()
	for id in Flow.DEFAULT_OWNED_WEAPONS:
		Flow.owned_weapons.append(String(id))
	Flow.weapon_slots.clear()
	for id in Flow.DEFAULT_WEAPON_SLOTS:
		Flow.weapon_slots.append(String(id))


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _fail(msg: String) -> void:
	failures.append(msg)
	push_error("SELFTEST FAIL: " + msg)


func _finish() -> void:
	## 恢复真实存档
	if save_backup != "":
		var f := FileAccess.open(Flow.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(save_backup)
			f.close()
	elif FileAccess.file_exists(Flow.SAVE_PATH):
		DirAccess.remove_absolute(Flow.SAVE_PATH)
	if failures.is_empty():
		print("SELFTEST OK")
	else:
		print("SELFTEST FAILED: %d 项" % failures.size())
		for f2 in failures:
			print("  - ", f2)
	get_tree().quit(0)
