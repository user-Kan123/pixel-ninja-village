extends Node2D
## 训练场主场景：竞技场搭建、敌人混编与重生、场地实体容器、暂停装配、命中停顿。
## 难度按累计击倒数缓慢爬升：木桩/追击者比重下降，射手与重型敌人比重上升。

const ARENA_SIZE := Vector2(1840.0, 1220.0)
const OBSTACLES: Array[Rect2] = [
	Rect2(560, 380, 170, 60),
	Rect2(1090, 760, 60, 200),
	Rect2(860, 170, 210, 60),
	Rect2(280, 900, 90, 90),
	Rect2(1420, 400, 130, 60),
]

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

var _hs_active := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build_walls()
	fx_container = _make_container("Fx")
	projectile_container = _make_container("Projectiles")
	field_container = _make_container("Fields")
	_spawn_player()
	_spawn_enemies()
	_spawn_hud()
	_spawn_loadout_ui()


func _make_container(n: String) -> Node2D:
	var c := Node2D.new()
	c.name = n
	add_child(c)
	return c


func _build_walls() -> void:
	var t := 60.0
	var rects := [
		Rect2(-t, -t, ARENA_SIZE.x + 2.0 * t, t),
		Rect2(-t, ARENA_SIZE.y, ARENA_SIZE.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, ARENA_SIZE.y),
		Rect2(ARENA_SIZE.x, 0.0, t, ARENA_SIZE.y),
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
	player.position = ARENA_SIZE * 0.5
	add_child(player)


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
	get_tree().create_timer(6.5).timeout.connect(_respawn)


func on_player_level_up(level: int) -> void:
	if hud != null:
		hud.show_notice(Data.s("hud.level_up") % level)


func _respawn() -> void:
	if player == null or player.dead:
		return
	var pos := Vector2(
		rng.randf_range(140.0, ARENA_SIZE.x - 140.0),
		rng.randf_range(140.0, ARENA_SIZE.y - 140.0)
	)
	if pos.distance_to(player.global_position) < 300.0:
		pos = ARENA_SIZE - pos
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
	e.position = resolve_static(pos)
	add_child(e)


## 难度爬升：随击倒数把重心从木桩/追击者移向射手/重型
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
		clampf(pos.x, margin, ARENA_SIZE.x - margin),
		clampf(pos.y, margin, ARENA_SIZE.y - margin)
	)


## 静态障碍 + 已放置的墙体，任一命中即视为阻挡
func pos_blocked(pos: Vector2) -> bool:
	for r: Rect2 in OBSTACLES:
		if r.grow(6.0).has_point(pos):
			return true
	for wr in wall_rects():
		if wr.grow(4.0).has_point(pos):
			return true
	return false


func resolve_static(pos: Vector2) -> Vector2:
	for r: Rect2 in OBSTACLES:
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color("31302b"))
	var grid := Color(0.24, 0.23, 0.2)
	var step := 92.0
	var x := step
	while x < ARENA_SIZE.x:
		draw_line(Vector2(x, 0), Vector2(x, ARENA_SIZE.y), grid, 1.0)
		x += step
	var y := step
	while y < ARENA_SIZE.y:
		draw_line(Vector2(0, y), Vector2(ARENA_SIZE.x, y), grid, 1.0)
		y += step
	draw_arc(ARENA_SIZE * 0.5, 130.0, 0.0, TAU, 48, Color(0.2, 0.19, 0.17), 2.0)
	for r: Rect2 in OBSTACLES:
		draw_rect(r.grow(3.0), Color("4a3f33"))
		draw_rect(r, Color("57493a"))
	draw_rect(
		Rect2(-6.0, -6.0, ARENA_SIZE.x + 12.0, ARENA_SIZE.y + 12.0),
		Color("221f1a"), false, 12.0
	)
