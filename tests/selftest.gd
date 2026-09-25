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
	_test_loadout()
	_test_mouse_move()
	_test_flow_save()
	await _test_mission_hunt()
	await _test_mission_collect()
	await _test_mission_survive()
	await _test_wild_and_pending()
	await _test_death()
	await _test_ui_clicks()
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


## Flow：赏金 / 天数 / 存档读写
func _test_flow_save() -> void:
	_reset_flow()
	Flow.money = 123
	Flow.level = 5
	Flow.day = 3
	Flow.save_game()
	Flow.money = 0
	Flow.level = 1
	Flow.day = 1
	_check(Flow.load_save(), "存档读取失败")
	_check(Flow.money == 123, "存档金钱不符：%d" % Flow.money)
	_check(Flow.level == 5, "存档等级不符：%d" % Flow.level)
	_check(Flow.day == 3, "存档天数不符：%d" % Flow.day)
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

	## 忍术装配：控件同样要铺满，且 15 个忍术必须全部落在一屏内
	var lu = game.loadout_ui
	_check(lu.size == vp, "忍术装配控件尺寸未铺满视口：%s" % str(lu.size))
	game.toggle_loadout()
	await _frames(2)
	_check(lu.visible, "忍术装配界面未打开")
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


func _push_click(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)


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


func _reset_flow() -> void:
	Flow.level = 1
	Flow.xp = 0
	Flow.money = 0
	Flow.day = 1
	Flow.missions_done = {}
	Flow.mission_id = ""
	Flow.mission_cfg = {}
	Flow.pending_mission = ""


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
