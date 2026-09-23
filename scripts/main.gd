extends Node2D
## 训练场主场景：竞技场搭建、实体生成、命中停顿、重开逻辑。

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
var fx_container: Node2D
var projectile_container: Node2D
var kill_count := 0

var _hs_active := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build_walls()
	fx_container = Node2D.new()
	fx_container.name = "Fx"
	add_child(fx_container)
	projectile_container = Node2D.new()
	projectile_container.name = "Projectiles"
	add_child(projectile_container)
	_spawn_player()
	_spawn_enemies()
	_spawn_hud()


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


func _add_enemy(e: EnemyBase, pos: Vector2) -> void:
	e.game = self
	e.position = pos
	add_child(e)


func _spawn_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	hud.player = player
	layer.add_child(hud)


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
	var is_dummy: bool = enemy is EnemyDummy
	var t := 6.0 if is_dummy else 9.0
	get_tree().create_timer(t).timeout.connect(_respawn.bind(is_dummy))


func _respawn(is_dummy: bool) -> void:
	var pos := Vector2(
		rng.randf_range(140.0, ARENA_SIZE.x - 140.0),
		rng.randf_range(140.0, ARENA_SIZE.y - 140.0)
	)
	if player != null and pos.distance_to(player.global_position) < 260.0:
		pos = ARENA_SIZE - pos
	var e: EnemyBase = EnemyDummy.new() if is_dummy else EnemyChaser.new()
	e.game = self
	e.position = resolve_static(pos)
	add_child(e)


func on_player_died() -> void:
	Engine.time_scale = 0.25
	await get_tree().create_timer(1.2, true, false, true).timeout
	Engine.time_scale = 1.0


func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func clamp_to_arena(pos: Vector2, margin := 24.0) -> Vector2:
	return Vector2(
		clampf(pos.x, margin, ARENA_SIZE.x - margin),
		clampf(pos.y, margin, ARENA_SIZE.y - margin)
	)


func pos_blocked(pos: Vector2) -> bool:
	for r: Rect2 in OBSTACLES:
		if r.grow(6.0).has_point(pos):
			return true
	return false


func resolve_static(pos: Vector2) -> Vector2:
	for r: Rect2 in OBSTACLES:
		if r.grow(4.0).has_point(pos):
			var d := [
				absf(pos.x - r.position.x),
				absf(pos.x - (r.position.x + r.size.x)),
				absf(pos.y - r.position.y),
				absf(pos.y - (r.position.y + r.size.y)),
			]
			var m: float = d[0]
			for v in d:
				m = minf(m, v)
			if m == d[0]:
				pos.x = r.position.x - 5.0
			elif m == d[1]:
				pos.x = r.position.x + r.size.x + 5.0
			elif m == d[2]:
				pos.y = r.position.y - 5.0
			else:
				pos.y = r.position.y + r.size.y + 5.0
	return clamp_to_arena(pos, 26.0)


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
