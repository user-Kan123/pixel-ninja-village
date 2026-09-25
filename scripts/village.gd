extends Node2D
## 村庄：玩家日常据点。任务看板（接任务）→ 村口大门（出发）；训练场入口；休息处（存档）。
## 村内没有敌人，等级 < 15 时也不会触发遭遇战（见设计基线 §1 决策 2）。
## 建筑名全部走名词表（Data.s），本文件不含专有名词。

var arena_size := Vector2(2000.0, 1280.0)

## 建筑（也是碰撞体）
var BUILDINGS := [
	{"rect": Rect2(760, 150, 440, 200), "key": "building.hokage", "style": "hokage",
		"wall": Color("c0483a"), "roof": Color("7a2e26"), "trim": Color("e8d8b8")},
	{"rect": Rect2(140, 160, 300, 178), "key": "building.school", "style": "school",
		"wall": Color("d8c9a8"), "roof": Color("6a5a44"), "trim": Color("f0e6d0")},
	{"rect": Rect2(1290, 185, 190, 145), "key": "building.mission", "style": "mission",
		"wall": Color("b89a6a"), "roof": Color("6e5232"), "trim": Color("e0d0a8")},
	{"rect": Rect2(160, 540, 250, 158), "key": "building.ramen", "style": "ramen",
		"wall": Color("d8b088"), "roof": Color("8a5a38"), "trim": Color("e8dcc0")},
	{"rect": Rect2(1580, 520, 250, 162), "key": "building.shop", "style": "shop",
		"wall": Color("a88a5a"), "roof": Color("5e4630"), "trim": Color("d8c8a0")},
	{"rect": Rect2(620, 770, 260, 168), "key": "building.apartment", "style": "apartment",
		"wall": Color("c0b0a0"), "roof": Color("6a5a52"), "trim": Color("e0d8cc")},
	{"rect": Rect2(1490, 870, 270, 178), "key": "building.hospital", "style": "hospital",
		"wall": Color("e4e8e4"), "roof": Color("7a8a90"), "trim": Color("f0f4f0")},
	{"rect": Rect2(250, 900, 270, 172), "key": "building.bath", "style": "bath",
		"wall": Color("b8c8d0"), "roof": Color("5a7a8c"), "trim": Color("e0e8ec")},
]

## 道路 / 广场
var PATHS := [
	Rect2(600, 350, 800, 200),
	Rect2(0, 650, 2000, 82),
	Rect2(950, 340, 100, 880),
	Rect2(300, 420, 90, 240),
	Rect2(1580, 420, 90, 240),
	Rect2(150, 650, 130, 70),
	Rect2(1710, 650, 130, 70),
	Rect2(620, 700, 80, 90),
	Rect2(260, 830, 110, 90),
	Rect2(1490, 830, 110, 90),
]

## 交互点
const BOARD_POS := Vector2(1385.0, 370.0)
const TORII_POS := Vector2(1790.0, 250.0)
const SHRINE_POS := Vector2(520.0, 600.0)
const GATE_POS := Vector2(1000.0, 1180.0)
const INTERACT_RADIUS := 72.0

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
		Rect2(-t, -t, arena_size.x + 2.0 * t, t),
		Rect2(-t, arena_size.y, arena_size.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, arena_size.y),
		Rect2(arena_size.x, 0.0, t, arena_size.y),
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
	player.position = Vector2(1000.0, 1060.0)
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


# ---------------------------------------------------------------- 任务接取

## 看板选择任务：登记待出发，引导玩家去村口大门
func accept_mission_from_board(id: String) -> void:
	Flow.accept_mission(id)
	close_board()
	hud.show_notice(Data.s("village.go_gate"))


# ---------------------------------------------------------------- 交互

func _nearest_interactable() -> Dictionary:
	var spots := [
		{"pos": BOARD_POS, "kind": "board", "hint": Data.s("village.board") + " · " + Data.s("village.open")},
		{"pos": TORII_POS, "kind": "torii", "hint": Data.s("village.gate") + " · " + Data.s("village.enter")},
		{"pos": SHRINE_POS, "kind": "shrine", "hint": Data.s("village.shrine") + " · " + Data.s("village.rest")},
	]
	## 村口大门：只有接了待出发任务时才能交互
	if Flow.pending_mission != "":
		spots.append({"pos": GATE_POS, "kind": "depart", "hint": Data.s("village.depart")})
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
		"torii":
			Flow.sync_from_player(player)
			Flow.start_training()
		"shrine":
			Flow.sync_from_player(player)
			Flow.save_game()
			hud.show_notice(Data.s("village.saved"))
		"depart":
			Flow.sync_from_player(player)
			Flow.depart_mission()


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
	## 村内不应死亡；兜底：回满血瞬回主干道
	if player != null:
		player.dead = false
		player.hp = player.max_hp
		player.state = Player.State.MOVE
		player.global_position = Vector2(1000.0, 900.0)


func on_enemy_died(_enemy: Node) -> void:
	pass


func on_intel_collected() -> void:
	pass


func clamp_to_arena(pos: Vector2, margin := 24.0) -> Vector2:
	return Vector2(
		clampf(pos.x, margin, arena_size.x - margin),
		clampf(pos.y, margin, arena_size.y - margin)
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
	## 草底
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color("3d5c3a"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 120:
		var p := Vector2(rng.randf_range(0.0, arena_size.x), rng.randf_range(0.0, arena_size.y))
		if _is_cleared(p):
			continue
		draw_circle(p, rng.randf_range(2.0, 5.0), Color(0.25, 0.42, 0.23, 0.5))
	## 道路 / 广场
	for pr in PATHS:
		draw_rect(pr, Color("8a7a5c"))
	## 火影岩（在建筑后）
	_draw_mountain()
	## 建筑
	for b in BUILDINGS:
		_draw_building(b)
	## 自然装饰（树 / 灌木），避开道路建筑
	_draw_nature()
	## 路灯
	for lx in [200, 600, 1300, 1800]:
		_draw_lamp(Vector2(lx, 692))
	for ly in [480, 820, 1080]:
		_draw_lamp(Vector2(1000, ly))
	## 交互设施
	_draw_board()
	_draw_torii(TORII_POS)
	_draw_shrine()
	_draw_village_gate()


func _is_cleared(p: Vector2) -> bool:
	for pr in PATHS:
		if pr.has_point(p):
			return true
	for b in BUILDINGS:
		if (b["rect"] as Rect2).grow(24.0).has_point(p):
			return true
	if p.x > 640.0 and p.x < 1320.0 and p.y < 150.0:
		return true
	return false


func _draw_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 90:
		var p := Vector2(rng.randf_range(40.0, arena_size.x - 40.0), rng.randf_range(40.0, arena_size.y - 40.0))
		if _is_cleared(p):
			continue
		if rng.randf() < 0.5:
			_draw_tree(p, rng.randf_range(16.0, 24.0))
		else:
			draw_circle(p, rng.randf_range(6.0, 10.0), Color("355f32"))


func _draw_tree(c: Vector2, s: float) -> void:
	draw_rect(Rect2(c + Vector2(-3, 0), Vector2(6, 12)), Color("5a4230"))
	draw_circle(c + Vector2(0, -s * 0.9), s, Color("2f5230"))
	draw_circle(c + Vector2(-s * 0.4, -s * 1.3), s * 0.6, Color("3d6638"))


func _draw_lamp(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-2, -26), Vector2(4, 26)), Color("4a3826"))
	draw_circle(c + Vector2(0, -28), 6.0, Color("f0d878"))
	draw_circle(c + Vector2(0, -28), 10.0, Color(1.0, 0.9, 0.5, 0.25))


# ---------------------------------------------------------------- 火影岩

func _draw_mountain() -> void:
	## 山体
	for d in [Vector2(700, 60), Vector2(820, 40), Vector2(980, 30), Vector2(1140, 40), Vector2(1280, 60),
			Vector2(760, 90), Vector2(980, 80), Vector2(1200, 90)]:
		draw_circle(d, 70.0, Color("6e6658"))
	## 四张脸
	for fx in [800.0, 940.0, 1080.0, 1220.0]:
		_draw_face(Vector2(fx, 78.0))


func _draw_face(c: Vector2) -> void:
	draw_circle(c, 40.0, Color("a8a094"))
	draw_rect(Rect2(c + Vector2(-16, -8), Vector2(9, 6)), Color("4a4640"))
	draw_rect(Rect2(c + Vector2(7, -8), Vector2(9, 6)), Color("4a4640"))
	draw_line(c + Vector2(-12, 12), c + Vector2(12, 12), Color("4a4640"), 2.0)


# ---------------------------------------------------------------- 建筑

func _draw_building(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var wall: Color = b["wall"]
	var roof: Color = b["roof"]
	var trim: Color = b["trim"]
	var style: String = b["style"]
	## 屋檐投影
	draw_rect(r.grow(7), roof.darkened(0.45))
	## 屋顶（上 60%）
	var roof_h := r.size.y * 0.6
	var roof_r := Rect2(r.position, Vector2(r.size.x, roof_h))
	draw_rect(roof_r, roof)
	for i in 4:
		var yy: float = r.position.y + roof_h * float(i + 1) / 5.0
		draw_line(Vector2(r.position.x + 5, yy), Vector2(r.end.x - 5, yy), roof.darkened(0.22), 1.5)
	## 正面墙
	var wall_r := Rect2(Vector2(r.position.x, r.position.y + roof_h), Vector2(r.size.x, r.size.y - roof_h))
	draw_rect(wall_r, wall)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), wall.darkened(0.4), 3.0)
	## 门
	var door := Rect2(r.get_center().x - 13, r.end.y - 42, 26, 42)
	draw_rect(door, Color("3a2c20"))
	draw_rect(door, trim, false, 1.5)
	## 两侧窗
	var win_y := r.position.y + roof_h + 12
	for sx in [r.position.x + 22, r.end.x - 44]:
		var win := Rect2(sx, win_y, 22, 22)
		draw_rect(win, Color("7fa8c8"))
		draw_rect(win, trim, false, 1.5)
		draw_line(win.position + Vector2(11, 0), win.position + Vector2(11, 22), trim, 1.0)
	## 名称招牌
	draw_string(Data.font(), r.position + Vector2(8, 22), Data.s(String(b["key"])),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, trim)
	_style_extras(style, r, wall, wall_r, trim)


func _style_extras(style: String, r: Rect2, wall: Color, wall_r: Rect2, trim: Color) -> void:
	var roof_h := r.size.y * 0.6
	match style:
		"hokage":
			## 屋顶金色徽章 + 顶层楼阁
			var top := Vector2(r.get_center().x, r.position.y + 16)
			draw_circle(top, 13.0, Color("e8c84a"))
			draw_string(Data.font(), top + Vector2(-7, 6), "火", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("7a2e26"))
			draw_rect(Rect2(r.get_center().x - 40, r.position.y - 26, 80, 26), wall)
			draw_rect(Rect2(r.get_center().x - 40, r.position.y - 26, 80, 26), trim, false, 1.5)
		"school":
			## 屋顶小旗 + 额外窗
			draw_line(Vector2(r.end.x - 30, r.position.y), Vector2(r.end.x - 30, r.position.y - 24), trim, 2.0)
			draw_rect(Rect2(r.end.x - 28, r.position.y - 24, 18, 12), Color("c8483a"))
		"ramen":
			## 红色波浪遮阳帘
			var n := 8
			for i in n:
				var cx: float = wall_r.position.x + float(i) * wall_r.size.x / n
				draw_circle(Vector2(cx, wall_r.position.y + 4), 9.0, Color("c84438"))
		"shop":
			## 橱窗苦无标记
			draw_string(Data.font(), Vector2(r.position.x + 26, wall_r.position.y + 30), "卍",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, trim.darkened(0.2))
		"apartment":
			## 顶层额外两窗
			for sx in [r.position.x + 60, r.end.x - 82]:
				draw_rect(Rect2(sx, r.position.y + roof_h - 26, 20, 18), Color("7fa8c8"))
				draw_rect(Rect2(sx, r.position.y + roof_h - 26, 20, 18), trim, false, 1.0)
		"hospital":
			## 红十字牌
			var cross := r.get_center() + Vector2(0, roof_h * 0.4)
			draw_rect(Rect2(cross + Vector2(-4, -12), Vector2(8, 24)), Color("c8383a"))
			draw_rect(Rect2(cross + Vector2(-12, -4), Vector2(24, 8)), Color("c8383a"))
		"bath":
			## 烟囱 + 热气
			var chx := r.end.x - 30
			draw_rect(Rect2(chx, r.position.y - 18, 14, 26), trim)
			draw_arc(Vector2(chx + 7, r.position.y - 24), 6.0, 0.0, PI, 12, Color(0.8, 0.9, 0.95, 0.6), 1.5)


# ---------------------------------------------------------------- 交互设施

func _draw_board() -> void:
	draw_rect(Rect2(BOARD_POS + Vector2(-36, -52), Vector2(72, 44)), Color("8a6a42"))
	draw_rect(Rect2(BOARD_POS + Vector2(-36, -52), Vector2(72, 44)), Color(0.2, 0.14, 0.08, 0.9), false, 2.0)
	draw_rect(Rect2(BOARD_POS + Vector2(-4, -8), Vector2(8, 26)), Color("6a4f30"))
	draw_string(Data.font(), BOARD_POS + Vector2(-30, -30), Data.s("village.board"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0e6c8"))


func _draw_torii(pos: Vector2) -> void:
	draw_rect(Rect2(pos + Vector2(-40, -60), Vector2(10, 60)), Color("a03428"))
	draw_rect(Rect2(pos + Vector2(30, -60), Vector2(10, 60)), Color("a03428"))
	draw_rect(Rect2(pos + Vector2(-48, -68), Vector2(96, 12)), Color("b8402f"))
	draw_rect(Rect2(pos + Vector2(-34, -48), Vector2(68, 8)), Color("a03428"))


func _draw_shrine() -> void:
	draw_rect(Rect2(SHRINE_POS + Vector2(-22, -34), Vector2(44, 34)), Color("7a6a58"))
	draw_colored_polygon(PackedVector2Array([
		SHRINE_POS + Vector2(-30, -34), SHRINE_POS + Vector2(30, -34), SHRINE_POS + Vector2(0, -58),
	]), Color("5a4a3a"))
	draw_rect(Rect2(SHRINE_POS + Vector2(-8, -22), Vector2(16, 22)), Color(0.12, 0.1, 0.08))


func _draw_village_gate() -> void:
	var g := GATE_POS
	var active: bool = Flow.pending_mission != ""
	## 门柱
	draw_rect(Rect2(g + Vector2(-44, -70), Vector2(20, 70)), Color("6a5238"))
	draw_rect(Rect2(g + Vector2(24, -70), Vector2(20, 70)), Color("6a5238"))
	draw_rect(Rect2(g + Vector2(-48, -78), Vector2(28, 12)), Color("8a7a68"))
	draw_rect(Rect2(g + Vector2(20, -78), Vector2(28, 12)), Color("8a7a68"))
	## 横梁 + 瓦顶
	draw_rect(Rect2(g + Vector2(-58, -100), Vector2(116, 18)), Color("7a5a3c"))
	draw_rect(Rect2(g + Vector2(-64, -114), Vector2(128, 14)), Color("5a4230"))
	## 门扇
	draw_rect(Rect2(g + Vector2(-24, -50), Vector2(48, 50)), Color("4a3826"))
	## 牌匾
	draw_string(Data.font(), g + Vector2(-42, -88), Data.s("gate.name"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f0e6c8"))
	## 待出发时发光提示
	if active:
		draw_arc(g + Vector2(0, -40), 78.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.5, 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.005)), 2.5)
