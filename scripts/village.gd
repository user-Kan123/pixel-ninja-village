extends Node2D
## 村庄：玩家日常据点。任务看板（接任务）、训练场入口、休息处（存档）。
## 村内没有敌人，等级 < 15 时也不会触发遭遇战（见设计基线 §1 决策 2）。

const ARENA_SIZE := Vector2(1600.0, 1000.0)

## 建筑（也是碰撞体）：名称走名词表，这里只放几何
const BUILDINGS := [
	{"rect": Rect2(620, 110, 360, 150), "name": "火影楼", "color": Color("7a4b38"), "roof": Color("5a3527")},
	{"rect": Rect2(170, 370, 210, 130), "name": "忍具店", "color": Color("5f6650"), "roof": Color("454a3a")},
	{"rect": Rect2(1170, 350, 230, 130), "name": "公寓", "color": Color("66586e"), "roof": Color("4a3f52")},
	{"rect": Rect2(640, 690, 320, 110), "name": "澡堂", "color": Color("4e5f6b"), "roof": Color("38454e")},
]

const BOARD_POS := Vector2(560.0, 620.0)
const GATE_POS := Vector2(1480.0, 800.0)
const SHRINE_POS := Vector2(150.0, 800.0)
const INTERACT_RADIUS := 70.0

var player: Player
var hud: VillageHud
var hud_layer: CanvasLayer
var board_ui: MissionBoardUi
var loadout_ui: LoadoutUi
var fx_container: Node2D
var projectile_container: Node2D
var field_container: Node2D
var walls: Array[EarthWall] = []
var loadout_open := false

var _hs_active := false


func _ready() -> void:
	_build_bounds()
	for b in BUILDINGS:
		_add_static_rect(b["rect"])
	fx_container = _make_container("Fx")
	projectile_container = _make_container("Projectiles")
	field_container = _make_container("Fields")
	_spawn_player()
	_spawn_ui()


func _make_container(n: String) -> Node2D:
	var c := Node2D.new()
	c.name = n
	add_child(c)
	return c


func _build_bounds() -> void:
	var t := 60.0
	var rects := [
		Rect2(-t, -t, ARENA_SIZE.x + 2.0 * t, t),
		Rect2(-t, ARENA_SIZE.y, ARENA_SIZE.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, ARENA_SIZE.y),
		Rect2(ARENA_SIZE.x, 0.0, t, ARENA_SIZE.y),
	]
	for r in rects:
		_add_static_rect(r)


func _add_static_rect(r: Rect2) -> void:
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
	player.position = ARENA_SIZE * 0.5 + Vector2(0.0, 180.0)
	add_child(player)
	Flow.apply_to_player(player)


func _spawn_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	hud = VillageHud.new()
	hud.game = self
	hud.player = player
	hud_layer.add_child(hud)
	board_ui = MissionBoardUi.new()
	board_ui.game = self
	board_ui.visible = false
	board_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(board_ui)
	loadout_ui = LoadoutUi.new()
	loadout_ui.game = self
	loadout_ui.player = player
	loadout_ui.visible = false
	loadout_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(loadout_ui)


# ---------------------------------------------------------------- 交互

func _nearest_interactable() -> Dictionary:
	var spots := [
		{"pos": BOARD_POS, "kind": "board", "hint": Data.s("village.board") + " · " + Data.s("village.open")},
		{"pos": GATE_POS, "kind": "gate", "hint": Data.s("village.gate") + " · " + Data.s("village.enter")},
		{"pos": SHRINE_POS, "kind": "shrine", "hint": Data.s("village.shrine") + " · " + Data.s("village.rest")},
	]
	var best := {}
	var best_d := INTERACT_RADIUS
	for s in spots:
		var d: float = player.global_position.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best


func current_interact_hint() -> String:
	return String(_nearest_interactable().get("hint", ""))


func on_interact() -> void:
	if player == null or player.dead:
		return
	var spot := _nearest_interactable()
	if spot.is_empty():
		return
	match String(spot["kind"]):
		"board":
			toggle_board()
		"gate":
			Flow.sync_from_player(player)
			Flow.start_training()
		"shrine":
			Flow.sync_from_player(player)
			Flow.save_game()
			hud.show_notice(Data.s("village.saved"))


func toggle_board() -> void:
	if board_ui.visible:
		close_board()
		return
	if loadout_open:
		close_loadout()
	board_ui.visible = true
	get_tree().paused = true
	board_ui.on_opened()


func close_board() -> void:
	board_ui.visible = false
	get_tree().paused = false


func board_open() -> bool:
	return board_ui != null and board_ui.visible


func toggle_loadout() -> void:
	if player != null and player.dead:
		return
	if board_open():
		close_board()
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


# ---------------------------------------------------------------- 玩家依赖的通用接口

func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func hitstop(duration: float, time_scale := 0.05) -> void:
	if _hs_active or duration <= 0.0:
		return
	_hs_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hs_active = false


func on_player_level_up(_level: int) -> void:
	if hud != null:
		hud.show_notice(Data.s("hud.level_up") % _level)


func on_player_died() -> void:
	## 村内不应死亡；兜底：回满血瞬回中心
	if player != null:
		player.dead = false
		player.hp = player.max_hp
		player.state = Player.State.MOVE
		player.global_position = ARENA_SIZE * 0.5


func on_enemy_died(_enemy: Node) -> void:
	pass


func on_intel_collected() -> void:
	pass


func clamp_to_arena(pos: Vector2, margin := 24.0) -> Vector2:
	return Vector2(
		clampf(pos.x, margin, ARENA_SIZE.x - margin),
		clampf(pos.y, margin, ARENA_SIZE.y - margin)
	)


func pos_blocked(pos: Vector2) -> bool:
	for b in BUILDINGS:
		if (b["rect"] as Rect2).grow(6.0).has_point(pos):
			return true
	return false


func resolve_static(pos: Vector2) -> Vector2:
	for b in BUILDINGS:
		var r: Rect2 = b["rect"]
		if r.grow(4.0).has_point(pos):
			pos = _push_out_of_rect(pos, r)
	return clamp_to_arena(pos, 26.0)


func resolve_point(pos: Vector2, margin: float) -> Vector2:
	return resolve_static(pos)


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


func register_wall(w: EarthWall) -> void:
	if not walls.has(w):
		walls.append(w)


func unregister_wall(w: EarthWall) -> void:
	walls.erase(w)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color("3d5c3a"))
	## 草地纹理（稀疏色块）
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 90:
		var p := Vector2(rng.randf_range(0.0, ARENA_SIZE.x), rng.randf_range(0.0, ARENA_SIZE.y))
		draw_circle(p, rng.randf_range(2.0, 5.0), Color(0.25, 0.42, 0.23, 0.5))
	## 广场与主干道
	draw_rect(Rect2(430, 520, 740, 240), Color("8a7a5c"))
	draw_rect(Rect2(0, 590, ARENA_SIZE.x, 70), Color("8a7a5c"))
	draw_rect(Rect2(760, 260, 80, 740), Color("8a7a5c"))
	## 建筑
	var font := Data.font()
	for b in BUILDINGS:
		var r: Rect2 = b["rect"]
		draw_rect(r.grow(4.0), b["roof"])
		draw_rect(r, b["color"])
		draw_rect(r, Color(0.1, 0.08, 0.06, 0.9), false, 2.0)
		draw_rect(Rect2(r.get_center() + Vector2(-14, r.size.y / 2.0 - 30), Vector2(28, 30)), Color(0.15, 0.12, 0.1))
		draw_string(font, r.position + Vector2(10.0, 26.0), String(b["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f0ece3"))
	## 任务看板
	draw_rect(Rect2(BOARD_POS + Vector2(-36, -52), Vector2(72, 44)), Color("8a6a42"))
	draw_rect(Rect2(BOARD_POS + Vector2(-36, -52), Vector2(72, 44)), Color(0.2, 0.14, 0.08, 0.9), false, 2.0)
	draw_rect(Rect2(BOARD_POS + Vector2(-4, -8), Vector2(8, 26)), Color("6a4f30"))
	draw_string(font, BOARD_POS + Vector2(-30, -30), Data.s("village.board"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0e6c8"))
	## 训练场入口（鸟居）
	draw_rect(Rect2(GATE_POS + Vector2(-40, -60), Vector2(10, 60)), Color("a03428"))
	draw_rect(Rect2(GATE_POS + Vector2(30, -60), Vector2(10, 60)), Color("a03428"))
	draw_rect(Rect2(GATE_POS + Vector2(-48, -68), Vector2(96, 12)), Color("b8402f"))
	draw_rect(Rect2(GATE_POS + Vector2(-34, -48), Vector2(68, 8)), Color("a03428"))
	## 休息处（小祠堂）
	draw_rect(Rect2(SHRINE_POS + Vector2(-22, -34), Vector2(44, 34)), Color("7a6a58"))
	draw_colored_polygon(PackedVector2Array([
		SHRINE_POS + Vector2(-30, -34), SHRINE_POS + Vector2(30, -34), SHRINE_POS + Vector2(0, -58),
	]), Color("5a4a3a"))
	draw_rect(Rect2(SHRINE_POS + Vector2(-8, -22), Vector2(16, 22)), Color(0.12, 0.1, 0.08))
