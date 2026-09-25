class_name Battlefield
extends Node2D
## 战场基类：自由训练 或 任务模式（由 Flow.mission_id 决定）。
## 子类（如野外 WildField）在 _init 覆写 arena_size / obstacles / gate_pos，
## 并覆写 _draw_ground / _draw_border 即可换一个场景，战斗与任务逻辑全部复用。
##
## 任务三类（data/mission.json 定义）：
##   hunt     讨伐：持续补充敌人，杀满 target_kills 完成
##   survive  波次：清完一波刷下一波，清完最后一波完成
##   collect  收集：捡满情报卷轴完成，敌人周期性骚扰
##
## 完成 → 结算（赏金 + 经验 + 过一天）→ 按 E 回村；失败 → 按 E 回村（不删档）。

var arena_size: Vector2 = Vector2(1840.0, 1220.0)
## 障碍：{ "rect": Rect2, "kind": "crate" / "rock" / "tree" }
var obstacles: Array = [
	{"rect": Rect2(560, 380, 170, 60), "kind": "crate"},
	{"rect": Rect2(1090, 760, 60, 200), "kind": "crate"},
	{"rect": Rect2(860, 170, 210, 60), "kind": "crate"},
	{"rect": Rect2(280, 900, 90, 90), "kind": "crate"},
	{"rect": Rect2(1420, 400, 130, 60), "kind": "crate"},
]
var gate_pos: Vector2 = Vector2(920.0, 1140.0)

enum MissionState { NONE, RUNNING, WON, LOST }

var player: Player
var hud: Hud
var hud_layer: CanvasLayer
var fx_container: Node2D
var projectile_container: Node2D
var field_container: Node2D
var loadout_ui: LoadoutUi
var walls: Array[EarthWall] = []
var kill_count := 0
var loadout_open := false

var mission_state := MissionState.NONE
var mission_kills := 0
var mission_wave := 0
var mission_intel := 0
var result_rewards := {}
var enemy_timer := 0.0
var wave_pending := 0.0

var _hs_active := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build_walls()
	fx_container = _make_container("Fx")
	projectile_container = _make_container("Projectiles")
	field_container = _make_container("Fields")
	_spawn_player()
	if Flow.in_mission():
		_setup_mission()
	else:
		_spawn_enemies()
	_spawn_hud()
	_spawn_loadout_ui()
	if Flow.in_mission():
		_show_start_banner()


func _make_container(n: String) -> Node2D:
	var c := Node2D.new()
	c.name = n
	add_child(c)
	return c


func _build_walls() -> void:
	var t := 60.0
	var rects := [
		Rect2(-t, -t, arena_size.x + 2.0 * t, t),
		Rect2(-t, arena_size.y, arena_size.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, arena_size.y),
		Rect2(arena_size.x, 0.0, t, arena_size.y),
	]
	for r in rects:
		var body := StaticBody2D.new()
		body.position = r.get_center()
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		col.shape = shape
		body.add_child(col)
		add_child(body)


func _spawn_player() -> void:
	player = Player.new()
	player.game = self
	player.position = arena_size * 0.5
	add_child(player)
	Flow.apply_to_player(player)


func _spawn_enemies() -> void:
	_add_enemy(EnemyDummy.new(), Vector2(700, 460))
	_add_enemy(EnemyDummy.new(), Vector2(1140, 760))
	_add_enemy(EnemyChaser.new(), Vector2(300, 220))
	_add_enemy(EnemyChaser.new(), Vector2(1540, 1000))
	_add_enemy(EnemyShooter.new(), Vector2(1620, 240))
	_add_enemy(EnemyBrute.new(), Vector2(240, 1020))


func _add_enemy(e: EnemyBase, pos: Vector2) -> void:
	e.game = self
	e.position = resolve_static(pos)
	add_child(e)


func _spawn_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud.player = player
	hud_layer.add_child(hud)


func _spawn_loadout_ui() -> void:
	loadout_ui = LoadoutUi.new()
	loadout_ui.game = self
	loadout_ui.player = player
	loadout_ui.visible = false
	loadout_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(loadout_ui)


# ---------------------------------------------------------------- 任务模式

func _setup_mission() -> void:
	mission_state = MissionState.RUNNING
	var t := String(Flow.mission_cfg.get("type", ""))
	match t:
		"hunt":
			for i in 3:
				_spawn_mission_enemy()
		"survive":
			_start_wave(0)
		"collect":
			_spawn_scrolls()
			for i in 2:
				_spawn_mission_enemy()


func _show_start_banner() -> void:
	var mname: String = Data.s(String(Flow.mission_cfg.get("name_key", "")))
	hud.show_banner(Data.s("banner.mission_start"), mname + "  ·  " + objective_text())


func _process(delta: float) -> void:
	if mission_state != MissionState.RUNNING:
		return
	var t := String(Flow.mission_cfg.get("type", ""))
	match t:
		"hunt":
			if _alive_enemies() < int(Flow.mission_cfg.get("alive_cap", 5)):
				enemy_timer += delta
				if enemy_timer >= 2.2:
					enemy_timer = 0.0
					_spawn_mission_enemy()
		"collect":
			enemy_timer += delta
			if enemy_timer >= float(Flow.mission_cfg.get("enemy_interval", 11.0)):
				enemy_timer = 0.0
				if _alive_enemies() < int(Flow.mission_cfg.get("alive_cap", 4)):
					_spawn_mission_enemy()
		"survive":
			if wave_pending > 0.0:
				wave_pending -= delta
				if wave_pending <= 0.0:
					_start_wave(mission_wave)
			elif _alive_enemies() == 0:
				var waves: Array = Flow.mission_cfg.get("waves", [])
				if mission_wave >= waves.size():
					_mission_win()
				else:
					wave_pending = 1.2


func _alive_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is EnemyBase and not e.dead:
			n += 1
	return n


func _make_enemy(kind: String) -> EnemyBase:
	match kind:
		"dummy":
			return EnemyDummy.new()
		"chaser":
			return EnemyChaser.new()
		"shooter":
			return EnemyShooter.new()
		"brute":
			return EnemyBrute.new()
		"elite":
			return EnemyElite.new()
	return EnemyChaser.new()


func _pick_from_mix(mix: Dictionary) -> String:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var r := rng.randf() * total
	for k in mix:
		r -= float(mix[k])
		if r <= 0.0:
			return String(k)
	return String(mix.keys()[0])


func _spawn_mission_enemy() -> void:
	var kind := _pick_from_mix(Flow.mission_cfg.get("mix", {}))
	var e := _make_enemy(kind)
	e.game = self
	e.position = resolve_static(_random_spawn_pos())
	add_child(e)


func _random_spawn_pos() -> Vector2:
	var pos := Vector2(
		rng.randf_range(140.0, arena_size.x - 140.0),
		rng.randf_range(140.0, arena_size.y - 140.0)
	)
	if player != null and pos.distance_to(player.global_position) < 320.0:
		pos = arena_size - pos
	return pos


func _start_wave(idx: int) -> void:
	var waves: Array = Flow.mission_cfg.get("waves", [])
	if idx >= waves.size():
		return
	mission_wave = idx + 1
	if hud != null:
		hud.show_notice(Data.s("mission.wave_incoming") % mission_wave)
	for kind in waves[idx]:
		var e := _make_enemy(String(kind))
		e.game = self
		e.position = resolve_static(_random_spawn_pos())
		add_child(e)


func _spawn_scrolls() -> void:
	var n := int(Flow.mission_cfg.get("scroll_count", 6))
	for i in n:
		var pos := _random_spawn_pos()
		Pickup.create(field_container, resolve_static(pos), "intel", self)


func on_intel_collected() -> void:
	mission_intel += 1
	if hud != null:
		hud.show_notice(objective_text())
	if mission_state == MissionState.RUNNING and String(Flow.mission_cfg.get("type", "")) == "collect":
		if mission_intel >= int(Flow.mission_cfg.get("scroll_count", 6)):
			_mission_win()


func _mission_win() -> void:
	if mission_state != MissionState.RUNNING:
		return
	mission_state = MissionState.WON
	result_rewards = Flow.complete_mission()
	player.gain_xp(int(result_rewards.get("xp", 0)))
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	player.invuln_timer = 999.0
	game_set_hitstop_clean()


func game_set_hitstop_clean() -> void:
	Engine.time_scale = 1.0
	_hs_active = false


func objective_text() -> String:
	if not Flow.in_mission():
		return ""
	var t := String(Flow.mission_cfg.get("type", ""))
	var key := String(Flow.mission_cfg.get("objective_key", ""))
	match t:
		"hunt":
			return Data.s(key) % [mission_kills, int(Flow.mission_cfg.get("target_kills", 0))]
		"survive":
			var waves: Array = Flow.mission_cfg.get("waves", [])
			return Data.s(key) % [mini(mission_wave, waves.size()), waves.size()]
		"collect":
			return Data.s(key) % [mission_intel, int(Flow.mission_cfg.get("scroll_count", 0))]
	return ""


## 任务指引：返回当前最该去的目标（屏幕外箭头用）
func nearest_target() -> Dictionary:
	if player == null or mission_state != MissionState.RUNNING:
		return {"valid": false, "pos": Vector2.ZERO}
	var t := String(Flow.mission_cfg.get("type", ""))
	var best := Vector2.ZERO
	var best_d := INF
	if t == "collect":
		for p in get_tree().get_nodes_in_group("pickups"):
			if p is Pickup and p.kind == "intel" and not p.collected:
				var d: float = player.global_position.distance_to(p.global_position)
				if d < best_d:
					best_d = d
					best = p.global_position
	else:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is EnemyBase and not e.dead:
				var d2: float = player.global_position.distance_to(e.global_position)
				if d2 < best_d:
					best_d = d2
					best = e.global_position
	return {"valid": best_d < INF, "pos": best}


# ---------------------------------------------------------------- 装配界面暂停

func toggle_loadout() -> void:
	if player != null and player.dead:
		return
	loadout_open = not loadout_open
	loadout_ui.visible = loadout_open
	get_tree().paused = loadout_open
	if loadout_open:
		loadout_ui.on_opened()


func close_loadout() -> void:
	if not loadout_open:
		return
	loadout_open = false
	loadout_ui.visible = false
	get_tree().paused = false


# ---------------------------------------------------------------- 交互 / 返回村庄

func current_interact_hint() -> String:
	if mission_state == MissionState.WON or mission_state == MissionState.LOST:
		return Data.s("mission.back")
	if not Flow.in_mission() and player != null and not player.dead:
		if player.global_position.distance_to(gate_pos) < 90.0:
			return Data.s("mission.back")
	return ""


func on_interact() -> void:
	if mission_state == MissionState.WON or mission_state == MissionState.LOST:
		Flow.sync_from_player(player)
		Flow.back_to_village()
		return
	if not Flow.in_mission() and player != null and not player.dead:
		if player.global_position.distance_to(gate_pos) < 90.0:
			Flow.sync_from_player(player)
			Flow.back_to_village()


# ---------------------------------------------------------------- 场地实体

func register_wall(w: EarthWall) -> void:
	if not walls.has(w):
		walls.append(w)


func unregister_wall(w: EarthWall) -> void:
	walls.erase(w)


func wall_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w in walls:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			out.append(Rect2(w.global_position + w.box.position, w.box.size))
	return out


# ---------------------------------------------------------------- 命中停顿 / 回调

func hitstop(duration: float, time_scale := 0.05) -> void:
	if _hs_active or duration <= 0.0:
		return
	_hs_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hs_active = false


func on_enemy_died(enemy: Node) -> void:
	kill_count += 1
	if player != null and not player.dead:
		player.gain_xp(int(enemy.xp_value))
	_maybe_drop(enemy.global_position)
	if mission_state == MissionState.RUNNING:
		if String(Flow.mission_cfg.get("type", "")) == "hunt":
			mission_kills += 1
			if mission_kills >= int(Flow.mission_cfg.get("target_kills", 10)):
				_mission_win()
	elif not Flow.in_mission():
		get_tree().create_timer(6.5).timeout.connect(_respawn)


func _maybe_drop(pos: Vector2) -> void:
	if rng.randf() > 0.28:
		return
	var kind := "hp" if rng.randf() < 0.5 else "chakra"
	Pickup.create(field_container, pos, kind, self)


func on_player_level_up(level: int) -> void:
	if hud != null:
		hud.show_notice(Data.s("hud.level_up") % level)


func _respawn() -> void:
	if player == null or player.dead or Flow.in_mission():
		return
	var e: EnemyBase
	match _pick_enemy_type():
		0:
			e = EnemyDummy.new()
		1:
			e = EnemyChaser.new()
		2:
			e = EnemyShooter.new()
		_:
			e = EnemyBrute.new()
	e.game = self
	e.position = resolve_static(_random_spawn_pos())
	add_child(e)


## 训练模式难度爬升：随击倒数把重心从木桩/追击者移向射手/重型
func _pick_enemy_type() -> int:
	var kc := float(kill_count)
	var w_dummy := maxf(30.0 - kc * 0.3, 10.0)
	var w_chaser := maxf(34.0 - kc * 0.2, 20.0)
	var w_shooter := 14.0 + minf(kc * 0.4, 16.0)
	var w_brute := 8.0 + minf(kc * 0.35, 18.0)
	var r := rng.randf() * (w_dummy + w_chaser + w_shooter + w_brute)
	if r < w_dummy:
		return 0
	r -= w_dummy
	if r < w_chaser:
		return 1
	r -= w_chaser
	if r < w_shooter:
		return 2
	return 3


func on_player_died() -> void:
	if Flow.in_mission():
		mission_state = MissionState.LOST
		game_set_hitstop_clean()
		return
	Engine.time_scale = 0.25
	await get_tree().create_timer(1.2, true, false, true).timeout
	Engine.time_scale = 1.0


func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- 空间查询

func clamp_to_arena(pos: Vector2, margin := 24.0) -> Vector2:
	return Vector2(
		clampf(pos.x, margin, arena_size.x - margin),
		clampf(pos.y, margin, arena_size.y - margin)
	)


## 静态障碍 + 已放置的墙体，任一命中即视为阻挡
func pos_blocked(pos: Vector2) -> bool:
	for o in obstacles:
		if (o["rect"] as Rect2).grow(6.0).has_point(pos):
			return true
	for wr in wall_rects():
		if wr.grow(4.0).has_point(pos):
			return true
	return false


func resolve_static(pos: Vector2) -> Vector2:
	for o in obstacles:
		var r: Rect2 = o["rect"]
		if r.grow(4.0).has_point(pos):
			pos = _push_out_of_rect(pos, r)
	return clamp_to_arena(pos, 26.0)


## 通用：把任意点推出障碍与墙体（召唤物、分身等非物理实体用）
func resolve_point(pos: Vector2, margin: float) -> Vector2:
	pos = resolve_static(pos)
	for wr in wall_rects():
		if wr.grow(margin * 0.5).has_point(pos):
			pos = _push_out_of_rect(pos, wr)
	return clamp_to_arena(pos, margin)


func _push_out_of_rect(pos: Vector2, r: Rect2) -> Vector2:
	var d := [
		absf(pos.x - r.position.x),
		absf(pos.x - r.end.x),
		absf(pos.y - r.position.y),
		absf(pos.y - r.end.y),
	]
	var m: float = d[0]
	for v in d:
		m = minf(m, v)
	if m == d[0]:
		pos.x = r.position.x - 5.0
	elif m == d[1]:
		pos.x = r.end.x + 5.0
	elif m == d[2]:
		pos.y = r.position.y - 5.0
	else:
		pos.y = r.end.y + 5.0
	return pos


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_ground()
	_draw_obstacles()
	_draw_border()
	if not Flow.in_mission():
		_draw_return_gate()


## 地面（训练：泥地 + 网格 + 中央圆）；野外覆写
func _draw_ground() -> void:
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color("31302b"))
	var grid := Color(0.24, 0.23, 0.2)
	var step := 92.0
	var x := step
	while x < arena_size.x:
		draw_line(Vector2(x, 0), Vector2(x, arena_size.y), grid, 1.0)
		x += step
	var y := step
	while y < arena_size.y:
		draw_line(Vector2(0, y), Vector2(arena_size.x, y), grid, 1.0)
		y += step
	draw_arc(arena_size * 0.5, 130.0, 0.0, TAU, 48, Color(0.2, 0.19, 0.17), 2.0)


func _draw_obstacles() -> void:
	for o in obstacles:
		var r: Rect2 = o["rect"]
		match String(o["kind"]):
			"rock":
				draw_rect(r.grow(3.0), Color("55565c"))
				draw_rect(r, Color("6e6f76"))
				draw_rect(Rect2(r.position + r.size * 0.25, r.size * 0.4), Color("83848c"))
			"tree":
				_draw_tree(r)
			_:
				draw_rect(r.grow(3.0), Color("4a3f33"))
				draw_rect(r, Color("57493a"))
				draw_line(r.position, r.end, Color("3c3328"), 2.0)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("3c3328"), 2.0)


## 一棵树：rect 是树干碰撞，树冠画在其上方
func _draw_tree(r: Rect2) -> void:
	var cx := r.get_center()
	draw_rect(r, Color("5a4230"))
	var top := Vector2(cx.x, r.position.y)
	for d in [Vector2(0, -34), Vector2(-26, -20), Vector2(26, -20), Vector2(-14, -40), Vector2(14, -40)]:
		draw_circle(top + d, 24.0, Color("2f5230"))
	draw_circle(top + Vector2(-8, -30), 14.0, Color("3d6638"))


## 边界框（训练：木桩围栏）；野外覆写为树墙
func _draw_border() -> void:
	draw_rect(
		Rect2(-6.0, -6.0, arena_size.x + 12.0, arena_size.y + 12.0),
		Color("221f1a"), false, 12.0
	)


## 训练回村门（鸟居）
func _draw_return_gate() -> void:
	draw_rect(Rect2(gate_pos + Vector2(-36, -56), Vector2(9, 56)), Color("a03428"))
	draw_rect(Rect2(gate_pos + Vector2(27, -56), Vector2(9, 56)), Color("a03428"))
	draw_rect(Rect2(gate_pos + Vector2(-44, -64), Vector2(88, 11)), Color("b8402f"))
	draw_rect(Rect2(gate_pos + Vector2(-30, -44), Vector2(60, 7)), Color("a03428"))
