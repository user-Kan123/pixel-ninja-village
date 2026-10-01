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
	_check(not Data.item_def("hyorogan").is_empty(), "道具表缺少兵粮丸")
	_check(Data.shop_list().has("hyorogan"), "忍具店货架上没有兵粮丸")
	_check(player.slots_unlocked() == 5, "测试模式下 1 级应解锁 5 个忍术槽：%d" % player.slots_unlocked())
	_clear_enemies()
	await _frames(2)

	await _test_jutsu_pipeline()
	await _test_effects()
	await _test_rasengan()
	await _test_passives()
	await _test_pickup()
	await _test_stamina()
	await _test_wall_gnaw()
	await _test_clone_combat()
	await _test_enemy_attacks()
	await _test_growth()
	await _test_test_mode()
	_test_loadout()
	await _test_weapons()
	_test_mouse_move()
	_test_flow_save()
	await _test_time()
	await _test_mission_hunt()
	await _test_mission_collect()
	await _test_mission_survive()
	await _test_wild_and_pending()
	await _test_death()
	await _test_ui_clicks()
	await _test_shop()
	await _test_time_scene()
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
		player.stamina = player.max_stamina
		player.exhausted = false
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
	player.stamina = player.max_stamina
	player.exhausted = false
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
	player.stamina = player.max_stamina
	player.exhausted = false
	player.jutsu_cd["fox_genjutsu"] = 0.0
	player._try_cast_jutsu("fox_genjutsu", 0)
	await _frames(3)
	_check(dummy.confused_timer > 0.0, "狐惑未使敌人混乱")

	var hp_before: float = dummy.hp
	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.stamina = player.max_stamina
	player.exhausted = false
	player.jutsu_cd["fireball"] = 0.0
	player._try_cast_jutsu("fireball", 0)
	await _frames(40)
	player._release_seal_aim(dummy.global_position)
	await _frames(60)
	_check(dummy.hp < hp_before, "小火弹未造成伤害")

	player.state = Player.State.MOVE
	player.chakra = 9999.0
	player.stamina = player.max_stamina
	player.exhausted = false
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
	player.stamina = player.max_stamina
	player.exhausted = false
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
	## 注：手上得有能近战的忍具，否则左键本来就不该出刀（空手 / 手里剑都会拒绝）
	if player.weapon_at(0).is_empty():
		Flow.inv_add("kunai", 1)
		player.equip_weapon(0, "kunai")
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


## 拾取物：药品进背包（不再当场生效），自己吃下去才回血
func _test_pickup() -> void:
	player.dead = false
	player.hp = maxf(player.max_hp * 0.5, 1.0)
	_reset_bag()
	var bag_before := Flow.inv_total("heal_pill")
	Pickup.create(game.field_container, player.global_position + Vector2(10.0, 0.0), "hp", game)
	await _frames(6)
	_check(Flow.inv_total("heal_pill") == bag_before + 1, "回力药没有进背包")
	_check(get_tree().get_nodes_in_group("pickups").size() == 0, "拾取后药瓶未消失")
	var sid := Flow.first_sid_of("heal_pill")
	var hp_before: float = player.hp
	_check(player.use_item(sid), "背包里的药没能吃下去")
	_check(player.hp > hp_before, "吃药没有回血")
	_check(Flow.inv_total("heal_pill") == bag_before, "吃药没有扣掉一个")


## 体力系统：近战耗体力 → 力竭禁止战斗 → 站立恢复自动解除
func _test_stamina() -> void:
	player.dead = false
	player.exhausted = false
	player.stamina = 30.0
	player.state = Player.State.MOVE
	_reset_bag()
	Flow.inv_add("tanto", 1)
	player.equip_sid(0, Flow.first_sid_of("tanto"))
	## 近战挥击扣体力
	var st0: float = player.stamina
	player._request_attack()
	_check(player.state == Player.State.ATTACK, "体力充足时近战没打出去")
	_check(player.stamina < st0, "近战没有消耗体力：%.0f → %.0f" % [st0, player.stamina])
	await _frames(6)
	## 连打到力竭
	for i in 30:
		if player.exhausted:
			break
		player.state = Player.State.MOVE
		player._request_attack()
		await _frames(4)
	_check(player.exhausted, "连打没有触发力竭：体力 %.0f" % player.stamina)
	## 力竭：禁止近战与忍术，移速打折
	player.state = Player.State.MOVE
	player._request_attack()
	_check(player.state == Player.State.MOVE, "力竭时还能近战")
	player._try_cast_jutsu("fireball", 0)
	_check(player.state == Player.State.MOVE, "力竭时还能放忍术")
	_check(player.stamina_move_mult() < 0.5, "力竭时移速未受限：%.2f" % player.stamina_move_mult())
	## 站立快速恢复，过阈值自动解除
	player.stamina = Player.EXHAUST_RECOVER - 1.0
	await _frames(6)
	_check(not player.exhausted, "力竭恢复后未解除")
	## 体力充沛时增益生效
	player.stamina = player.max_stamina
	_check(player.stamina_damage_mult() > 1.05, "满体力伤害增益缺失：%.2f" % player.stamina_damage_mult())
	_check(player.stamina_move_mult() > 1.05, "满体力移速增益缺失：%.2f" % player.stamina_move_mult())


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
		player.stamina = player.max_stamina
		player.exhausted = false
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
	player.stamina = player.max_stamina
	player.exhausted = false
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


## 忍具与背包：堆叠上限、真消耗品、耐久与报废、装配规则、道具使用、商店购买
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
	_check(not Data.item_def("hyorogan").is_empty(), "道具表缺少兵粮丸")
	_check(Data.is_consumable("hyorogan") and not Data.is_weapon("hyorogan"), "兵粮丸应算消耗品")

	## 堆叠：可堆叠的一组 16，超出开新格；不可堆叠的一件一格
	_reset_bag()
	_check(Flow.inv_add("shuriken", 20) == 20, "手里剑没放进背包")
	_check(Flow.inv_used() == 2, "20 枚手里剑应占 2 格：%d" % Flow.inv_used())
	_check(int(Flow.inventory[0]["count"]) == 16, "第一格没装满 16：%d" % int(Flow.inventory[0]["count"]))
	_check(int(Flow.inventory[1]["count"]) == 4, "第二格数量不对：%d" % int(Flow.inventory[1]["count"]))
	Flow.inv_add("shuriken", 12)
	_check(Flow.inv_used() == 2, "补充堆叠时不该开新格：%d" % Flow.inv_used())
	_check(Flow.inv_add("tanto", 3) == 3, "短刀没放进背包")
	_check(Flow.inv_used() == 5, "3 把短刀应占 3 格：%d" % Flow.inv_used())
	## 背包上限 24 格
	Flow.inv_add("longsword", 40)
	_check(Flow.inv_used() == Flow.INV_SLOTS, "背包没有卡在 %d 格：%d" % [Flow.INV_SLOTS, Flow.inv_used()])
	_check(Flow.inv_add("kunai", 1) == 0, "背包满了还能塞东西")

	## 苦无：能近战能投掷；投掷是真消耗品，扔一个少一个且不会自动补充
	_reset_bag()
	Flow.inv_add("kunai", 16)
	Flow.inv_add("shuriken", 4)
	player.equip_sid(0, Flow.first_sid_of("kunai"))
	player.equip_sid(1, Flow.first_sid_of("shuriken"))
	player.active_weapon = 0
	_check(player.weapon_id() == "kunai", "主手不是苦无：%s" % player.weapon_id())
	_check(player.can_melee(), "苦无应能近战")
	_check(player.can_throw(), "苦无应能投掷")
	_check(player.weapon_count(0) == 16, "武器槽没读到背包数量：%d" % player.weapon_count(0))
	player.state = Player.State.MOVE
	var kunai_before := Flow.inv_total("kunai")
	player.stamina = player.max_stamina
	player.exhausted = false
	player._throw_weapon(player.global_position + Vector2(200.0, 0.0))
	var proj = _last_projectile()
	_check(proj != null and String(proj.kind) == "kunai", "投出的不是苦无")
	if proj != null:
		_check(is_equal_approx(float(proj.damage), float(Data.weapon("kunai")["throw_damage"]) * player.stamina_damage_mult()),
			"苦无投掷伤害不符：%s" % str(proj.damage))
		proj.queue_free()
	_check(Flow.inv_total("kunai") == kunai_before - 1,
		"投掷没有消耗苦无：%d → %d" % [kunai_before, Flow.inv_total("kunai")])
	await _frames(150)
	_check(Flow.inv_total("kunai") == kunai_before - 1,
		"忍具被自动补回来了（不该发生）：%d" % Flow.inv_total("kunai"))
	_check(float(Data.weapon("shuriken")["throw_damage"]) < float(Data.weapon("kunai")["throw_damage"]),
		"手里剑投掷伤害应低于苦无")
	_check(Data.item_stack("shuriken") == 16 and Data.item_stack("kunai") == 16, "投掷忍具应 16 个一组")
	_check(Data.item_stack("tanto") == 1 and Data.item_stack("longsword") == 1, "近战忍具不该堆叠")

	## 扔完最后一枚：手上的武器自动换掉，不会留在空枪状态
	_reset_bag()
	Flow.inv_add("shuriken", 1)
	Flow.inv_add("tanto", 1)
	player.equip_sid(0, Flow.first_sid_of("shuriken"))
	player.equip_sid(1, Flow.first_sid_of("tanto"))
	player.active_weapon = 0
	player.state = Player.State.MOVE
	player.stamina = player.max_stamina
	player.exhausted = false
	player._throw_weapon(player.global_position + Vector2(200.0, 0.0))
	await _frames(3)
	_check(Flow.inv_total("shuriken") == 0, "手里剑没扣完：%d" % Flow.inv_total("shuriken"))
	_check(player.weapon_id() == "tanto", "扔完之后没有自动换到另一件武器：%s" % player.weapon_id())

	## 耐久：短刀每命中一次掉 1 点，归零直接报废消失
	_reset_bag()
	Flow.inv_add("tanto", 1)
	var tsid := Flow.first_sid_of("tanto")
	player.equip_sid(0, tsid)
	player.equip_sid(1, -1)
	player.active_weapon = 0
	var dur_max := Data.item_durability("tanto")
	_check(dur_max > 0.0, "短刀没有耐久")
	var dummy := _spawn(0, player.global_position + Vector2(30.0, 0.0))
	await _frames(2)
	player.attack_dir = Vector2.RIGHT
	player.attack_step = player._melee_step(1)
	player._do_melee_hit()
	_check(is_equal_approx(float(Flow.inv_find(tsid)["dur"]), dur_max - 1.0),
		"近战命中没有磨损耐久：%s" % str(Flow.inv_find(tsid)["dur"]))
	Flow.inv_find(tsid)["dur"] = 1.0
	player.attack_step = player._melee_step(1)
	player._do_melee_hit()
	await _frames(2)
	_check(Flow.inv_index(tsid) < 0, "耐久归零后短刀没有报废")
	_check(player.weapon_at(0) != "tanto", "报废后手上还拿着短刀")
	dummy.queue_free()
	await _frames(2)

	## 堆叠物的耐久：苦无坏掉一把是"消耗掉一个"，堆里还有就继续用
	_reset_bag()
	Flow.inv_add("kunai", 3)
	var ksid := Flow.first_sid_of("kunai")
	player.equip_sid(0, ksid)
	player.equip_sid(1, -1)
	player.active_weapon = 0
	Flow.inv_find(ksid)["dur"] = 1.0
	var dummy2 := _spawn(0, player.global_position + Vector2(30.0, 0.0))
	await _frames(2)
	player.attack_dir = Vector2.RIGHT
	player.attack_step = player._melee_step(1)
	player._do_melee_hit()
	await _frames(2)
	_check(Flow.inv_total("kunai") == 2, "苦无用坏一把后应剩 2 把：%d" % Flow.inv_total("kunai"))
	_check(player.weapon_id() == "kunai", "苦无堆里还有却把手上的卸掉了")
	_check(not Flow.inv_find(ksid).is_empty(), "苦无的格子不该整个消失")
	_check(is_equal_approx(float(Flow.inv_find(ksid)["dur"]), Data.item_durability("kunai")),
		"换下一把苦无后耐久没有重置：%s" % str(Flow.inv_find(ksid)["dur"]))
	dummy2.queue_free()
	await _frames(2)

	## 近战数值梯度：短刀 > 苦无；长剑范围更大、伤害接近短刀、出手更慢
	_reset_bag()
	Flow.inv_add("kunai", 1)
	Flow.inv_add("tanto", 1)
	Flow.inv_add("longsword", 1)
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

	## 手里剑：只能投掷，左键不出刀
	_reset_bag()
	Flow.inv_add("shuriken", 3)
	player.equip_sid(0, Flow.first_sid_of("shuriken"))
	player.equip_sid(1, -1)
	player.active_weapon = 0
	_check(not player.can_melee(), "手里剑不应能近战")
	_check(player.can_throw(), "手里剑应能投掷")
	player.state = Player.State.MOVE
	player.weapon_hint_t = 0.0
	player._request_attack()
	await _frames(2)
	_check(player.state == Player.State.MOVE, "手里剑按左键不应出刀")

	## Q 切换主副手
	_reset_bag()
	Flow.inv_add("kunai", 2)
	Flow.inv_add("tanto", 1)
	player.equip_sid(0, Flow.first_sid_of("kunai"))
	player.equip_sid(1, Flow.first_sid_of("tanto"))
	player.active_weapon = 0
	_check(player.switch_weapon() == "tanto", "切换武器未切到副手")
	_check(player.weapon_id() == "tanto", "切换后当前忍具不对：%s" % player.weapon_id())
	_check(player.switch_weapon() == "kunai", "切换武器未切回主手")
	## 同一个背包格不会被两个槽同时指着
	var ksid2 := Flow.first_sid_of("kunai")
	player.equip_sid(1, ksid2)
	_check(player.weapon_sid_at(0) != player.weapon_sid_at(1),
		"同一个背包格被两个槽同时装着：%d / %d" % [player.weapon_sid_at(0), player.weapon_sid_at(1)])
	_check(player.weapon_sid_at(1) == ksid2, "第二次装配没有生效")
	player.equip_sid(0, 99999)
	_check(player.weapon_sid_at(1) == ksid2, "装不存在的背包格却改动了别的槽")

	## 兵粮丸：F 吃一颗，回体力回蓝不回血，数量 -1
	_reset_bag()
	Flow.inv_add("hyorogan", 2)
	player.hp = 40.0
	player.chakra = 30.0
	player.stamina = 20.0
	var hp0: float = player.hp
	var ck0: float = player.chakra
	var st0: float = player.stamina
	_push_key(KEY_F)
	await _frames(2)
	_check(Flow.inv_total("hyorogan") == 1, "F 没有消耗兵粮丸：%d" % Flow.inv_total("hyorogan"))
	_check(player.stamina > st0, "兵粮丸没有回体力：%.0f → %.0f" % [st0, player.stamina])
	_check(player.chakra > ck0, "兵粮丸没有回查克拉：%.0f → %.0f" % [ck0, player.chakra])
	_check(player.hp == hp0, "兵粮丸不应回血：%.0f → %.0f" % [hp0, player.hp])
	## 满状态时不浪费道具
	player.hp = player.max_hp
	player.chakra = player.max_chakra
	player.stamina = player.max_stamina
	_check(not player.use_best_consumable(), "满状态还吃了道具")
	_check(Flow.inv_total("hyorogan") == 1, "满状态吃道具被扣掉了")

	## 商店：赏金不足 / 背包满 / 短刀可重复买 / 10 个一组买
	_reset_bag()
	Flow.money = 10
	var poor: Dictionary = Flow.buy_item("longsword", 1)
	_check(not bool(poor["ok"]) and String(poor["reason"]) == "no_money", "赏金不足时仍能买忍具")
	Flow.money = 1000
	var b1: Dictionary = Flow.buy_item("tanto", 2)
	_check(bool(b1["ok"]) and int(b1["bought"]) == 2, "买两把短刀失败：%s" % str(b1))
	_check(Flow.inv_total("tanto") == 2, "短刀数量不对：%d" % Flow.inv_total("tanto"))
	_check(Flow.inv_used() == 2, "两把短刀应占两格：%d" % Flow.inv_used())
	_check(Flow.money == 1000 - 2 * Data.item_price("tanto"), "购买没扣对钱：%d" % Flow.money)
	var b2: Dictionary = Flow.buy_item("shuriken", 10)
	_check(bool(b2["ok"]) and int(b2["bought"]) == 10, "买 10 枚手里剑失败：%s" % str(b2))
	_check(Flow.inv_total("shuriken") == 10, "手里剑数量不对：%d" % Flow.inv_total("shuriken"))
	_check(Flow.inv_used() == 3, "10 枚手里剑应只占 1 格：%d" % Flow.inv_used())
	## 背包空间不足时只买得到放得下的部分
	var free_slots := Flow.INV_SLOTS - Flow.inv_used()
	Flow.money = 100000
	var b3: Dictionary = Flow.buy_item("longsword", Flow.INV_SLOTS)
	_check(int(b3["bought"]) <= free_slots, "买超了背包空间：%d > %d" % [int(b3["bought"]), free_slots])
	_check(Flow.inv_used() == Flow.INV_SLOTS, "背包没被填满：%d" % Flow.inv_used())
	var b4: Dictionary = Flow.buy_item("kunai", 1)
	_check(not bool(b4["ok"]) and String(b4["reason"]) == "no_space", "背包满了还能买：%s" % str(b4))

	## 收尾
	_reset_bag()
	Flow.inv_add("kunai", 8)
	player.equip_weapon(0, "kunai")
	player.equip_sid(1, -1)
	player.active_weapon = 0
	player.state = Player.State.MOVE


## Flow：赏金 / 天数 / 存档读写
func _test_flow_save() -> void:
	_reset_flow()
	Flow.money = 123
	Flow.level = 5
	Flow.day = 3
	_reset_bag()
	Flow.inv_add("tanto", 2)
	Flow.inv_add("kunai", 5)
	Flow.inv_add("hyorogan", 3)
	var tsid := Flow.first_sid_of("tanto")
	Flow.equip_sid(0, tsid)
	Flow.equip_sid(1, Flow.first_sid_of("kunai"))
	Flow.save_game()
	## 打乱内存里的状态，再从存档读回来
	Flow.money = 0
	Flow.level = 1
	Flow.day = 1
	_reset_bag()
	_check(Flow.load_save(), "存档读取失败")
	_check(Flow.money == 123, "存档金钱不符：%d" % Flow.money)
	_check(Flow.level == 5, "存档等级不符：%d" % Flow.level)
	_check(Flow.day == 3, "存档天数不符：%d" % Flow.day)
	_check(Flow.inv_total("tanto") == 2, "存档未保留背包里的短刀：%d" % Flow.inv_total("tanto"))
	_check(Flow.inv_total("kunai") == 5, "存档未保留苦无数量：%d" % Flow.inv_total("kunai"))
	_check(Flow.inv_total("hyorogan") == 3, "存档未保留兵粮丸：%d" % Flow.inv_total("hyorogan"))
	_check(Flow.inv_used() == 4, "存档里的背包格数不对：%d" % Flow.inv_used())
	_check(String(Flow.inv_find(Flow.sid_of_slot(0))["id"]) == "tanto", "存档未保留主手武器")
	_check(String(Flow.inv_find(Flow.sid_of_slot(1))["id"]) == "kunai", "存档未保留副手武器")
	_check(Flow.sid_of_slot(0) == tsid, "武器槽指向的背包格编号没存回来：%d vs %d" % [Flow.sid_of_slot(0), tsid])
	_reset_flow()



## 时间系统：场景里时间要自己往前走，界面打开时停
func _test_time_scene() -> void:
	_reset_flow()
	Flow.hour = 6.0
	var h0: float = Flow.hour
	await _frames(30)
	_check(Flow.hour > h0, "村庄里时间没有流逝：%f" % Flow.hour)
	## 界面打开（pause）时时间必须停
	game.toggle_board()
	await _frames(2)
	var h1: float = Flow.hour
	await _frames(30)
	_check(is_equal_approx(Flow.hour, h1), "看板打开时时间仍在走：%f → %f" % [h1, Flow.hour])
	game.close_board()


## 时间系统：Flow 时钟核心
func _test_time() -> void:
	Flow.day = 1
	Flow.hour = 6.0
	Flow.slept_today = false
	Flow.advance(240.0)               ## 白天 0.025 小时/秒
	_check(is_equal_approx(Flow.hour, 12.0), "白天推进不对：%f" % Flow.hour)
	_check(not Flow.is_night(), "12:00 不该算夜晚")
	Flow.advance(240.0)
	_check(is_equal_approx(Flow.hour, 18.0), "到 18:00 不对：%f" % Flow.hour)
	_check(Flow.is_night(), "18:00 应算夜晚")
	Flow.advance(20.0)                ## 夜晚 0.1 小时/秒
	_check(is_equal_approx(Flow.hour, 20.0), "夜晚流速不对：%f" % Flow.hour)
	_check(Flow.is_shop_closed(), "20:00 应打烊")
	## 跨日：从 22:00 走 8 小时（夜晚 80 秒）
	Flow.hour = 22.0
	var d0: int = Flow.day
	Flow.advance(80.0)
	_check(Flow.day == d0 + 1, "跨过 06:00 应 +1 天：%d" % Flow.day)
	_check(is_equal_approx(Flow.hour, 6.0), "跨日后应停在 06:00：%f" % Flow.hour)
	## 一次性传很大的 delta（跨"白天→夜晚→次日"三段），不能吞掉或重复计一天
	Flow.hour = 6.0
	var d_big: int = Flow.day
	Flow.advance(600.0)              ## 480s 白天 + 120s 夜晚 = 正好一天
	_check(Flow.day == d_big + 1, "跨整天应恰好 +1 天：%d" % Flow.day)
	_check(is_equal_approx(Flow.hour, 6.0), "跨整天后应回到 06:00：%f" % Flow.hour)
	## 睡觉
	Flow.hour = 21.0
	Flow.slept_today = false
	var d1: int = Flow.day
	_check(Flow.can_sleep(), "白天/夜里应能睡")
	Flow.sleep_until_morning()
	_check(is_equal_approx(Flow.hour, 6.0), "睡觉后应是 06:00：%f" % Flow.hour)
	_check(Flow.day == d1 + 1, "睡觉应推进一天：%d" % Flow.day)
	_check(not Flow.can_sleep(), "同一天不该能睡第二次")
	## 老存档：只有 day，没有 hour / slept_today
	var f := FileAccess.open(Flow.SAVE_PATH, FileAccess.WRITE)
	f.store_string('{"day": 7, "level": 3}')
	f.close()
	Flow.hour = 2.0
	Flow.slept_today = true
	_check(Flow.load_save(), "老存档读取失败")
	_check(is_equal_approx(Flow.hour, 6.0), "老存档应读成 06:00：%f" % Flow.hour)
	_check(Flow.day == 7, "老存档天数应保留：%d" % Flow.day)
	_check(not Flow.is_late_night(), "老存档不该被判成熬夜")
	## 时钟文本格式（Task 3 用；纯格式回归，不涉及绘制）
	Flow.day = 3
	Flow.hour = 9.5
	var t1: String = Flow.time_text()
	_check(t1.contains("09:30"), "时钟文本应为 09:30：%s" % t1)
	Flow.hour = 21.0
	_check(Flow.time_text().contains("21:00"), "夜晚时钟文本应为 21:00：%s" % Flow.time_text())


# ---------------------------------------------------------------- 任务流

## 讨伐任务：杀满目标 → 结算（赏金 / 天数 / 完成次数）
func _test_mission_hunt() -> void:
	_reset_flow()
	Flow.mission_id = "hunt"
	Flow.mission_cfg = Data.missions["hunt"].duplicate(true)
	Flow.mission_cfg["target_kills"] = 3
	var d_before_hunt: int = Flow.day
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
	## v0.11 起时间由时钟负责，任务完成**不再凭空 +1 天**
	_check(Flow.day == d_before_hunt, "任务完成不该凭空加一天：%d → %d" % [d_before_hunt, Flow.day])
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
	## 装备页：2 个武器槽 + 24 个背包格都要落在一屏内
	var wslot_last: float = lu._weapon_slot_rect(Player.WEAPON_SLOT_COUNT - 1).end.y
	_check(wslot_last < vp.y, "武器槽超出屏幕：%.0f > %.0f" % [wslot_last, vp.y])
	var cell_last: Rect2 = lu._bag_cell_rect(Flow.INV_SLOTS - 1)
	_check(cell_last.end.y < vp.y, "背包最后一格超出屏幕下边缘：%.0f > %.0f" % [cell_last.end.y, vp.y])
	_check(cell_last.end.x < vp.x, "背包最后一格超出屏幕右边缘：%.0f > %.0f" % [cell_last.end.x, vp.x])
	## 点背包里的苦无 → 装到选中的武器槽（第 0 格）
	_reset_bag()
	Flow.inv_add("kunai", 4)
	Flow.inv_add("tanto", 1)
	Flow.inv_add("hyorogan", 2)
	lu.selected_weapon_slot = 0
	_push_click(lu._bag_cell_rect(0).get_center())
	await _frames(3)
	_check(player.weapon_at(0) == "kunai", "点背包里的忍具没装到武器槽：%s" % player.weapon_at(0))
	## 点道具 → 直接使用（第 2 格 = 兵粮丸，回体力回血查克拉但不回血）
	player.hp = 50.0
	player.chakra = 50.0
	player.stamina = 20.0
	var st0: float = player.stamina
	var pills: int = Flow.inv_total("hyorogan")
	_push_click(lu._bag_cell_rect(2).get_center())
	await _frames(3)
	_check(Flow.inv_total("hyorogan") == pills - 1, "点背包里的道具没有消耗：%d" % Flow.inv_total("hyorogan"))
	_check(player.stamina > st0, "点兵粮丸没有回体力：%.0f → %.0f" % [st0, player.stamina])
	## 点武器槽可切换选中
	_push_click(lu._weapon_slot_rect(1).get_center())
	await _frames(2)
	_check(lu.selected_weapon_slot == 1, "点击武器槽未切换选中：%d" % lu.selected_weapon_slot)
	## 右键卸下：背包里还剩另一件忍具时可以卸，卸最后一件要被拦住
	_reset_bag()
	Flow.inv_add("tanto", 1)
	player.equip_sid(0, Flow.first_sid_of("tanto"))
	player.weapon_sids[1] = -1
	_push_click(lu._weapon_slot_rect(0).get_center(), MOUSE_BUTTON_RIGHT)
	await _frames(2)
	_check(not player.weapon_at(0).is_empty(), "卸下最后一件忍具没有被拦住")
	Flow.inv_add("kunai", 2)
	_push_click(lu._weapon_slot_rect(0).get_center(), MOUSE_BUTTON_RIGHT)
	await _frames(2)
	_check(player.weapon_at(0).is_empty(), "背包里还有别的忍具时应能卸下该槽")
	player.equip_weapon(0, "kunai")
	player.equip_sid(1, -1)
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


## 忍具店：走到店门口按 E 打开 → 买 1 / 买 10 → 真扣钱真进包 → 关闭
func _test_shop() -> void:
	Flow.money = 500
	_reset_bag()
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
	var shelf := Data.shop_list()
	_check(shelf.has("hyorogan"), "忍具店没有卖兵粮丸：%s" % str(shelf))
	_check(Data.item_price("hyorogan") <= 30 && Data.item_price("hyorogan") > 0,
		"兵粮丸定价不合理（应便宜但不免费）：%d" % Data.item_price("hyorogan"))
	## 买 10 枚手里剑：按 16 一组堆进一格，扣 10 个的钱
	var sh_idx: int = shelf.find("shuriken")
	var money0: int = Flow.money
	_push_click(shop._buy10_rect(sh_idx).get_center())
	await _frames(3)
	_check(Flow.inv_total("shuriken") == 10, "买 10 没买到 10 个：%d" % Flow.inv_total("shuriken"))
	_check(Flow.inv_used() == 1, "10 枚手里剑应装在同一格：%d" % Flow.inv_used())
	_check(Flow.money == money0 - 10 * Data.item_price("shuriken"), "买 10 扣的钱不对：%d" % Flow.money)
	## 短刀可以重复购买：买两把 = 两格，各自独立耐久
	var t_idx: int = shelf.find("tanto")
	_push_click(shop._buy1_rect(t_idx).get_center())
	await _frames(3)
	_push_click(shop._buy1_rect(t_idx).get_center())
	await _frames(3)
	_check(Flow.inv_total("tanto") == 2, "短刀不能重复购买：%d" % Flow.inv_total("tanto"))
	_check(Flow.inv_used() == 3, "两把短刀应是两格：%d" % Flow.inv_used())
	_check(not player.weapon_at(0).is_empty() or not player.weapon_at(1).is_empty(),
		"买到的忍具没自动进武器槽")
	## 兵粮丸也能买进背包
	_push_click(shop._buy1_rect(shelf.find("hyorogan")).get_center())
	await _frames(3)
	_check(Flow.inv_total("hyorogan") == 1, "没买到兵粮丸：%d" % Flow.inv_total("hyorogan"))
	## 赏金不足：不扣钱也不给东西
	Flow.money = 0
	var ls_before: int = Flow.inv_total("longsword")
	_push_click(shop._buy1_rect(shelf.find("longsword")).get_center())
	await _frames(3)
	_check(Flow.inv_total("longsword") == ls_before, "赏金不足却买到了长剑")
	_check(Flow.money == 0, "赏金不足时钱变成了负数：%d" % Flow.money)
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


## 清空背包与武器槽（player 还没生成时也能调）
func _reset_bag() -> void:
	Flow.inventory.clear()
	Flow.inv_next_sid = 1
	Flow.weapon_sids.clear()
	Flow._ensure_weapon_slots()
	for i in Flow.WEAPON_SLOT_COUNT:
		Flow.weapon_sids[i] = -1
	if player != null:
		player.weapon_sids.clear()
		player._ensure_weapon_slots()
		for i in Player.WEAPON_SLOT_COUNT:
			player.weapon_sids[i] = -1
		player.active_weapon = 0


func _reset_flow() -> void:
	Flow.level = 1
	Flow.xp = 0
	Flow.money = 0
	Flow.day = 1
	Flow.missions_done = {}
	Flow.mission_id = ""
	Flow.mission_cfg = {}
	Flow.pending_mission = ""
	_reset_bag()


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
