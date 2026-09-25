class_name WildField
extends Battlefield
## 野外（任务战场）：村外的草地，任务都在这里执行。
## 复用 Battlefield 的全部战斗/任务逻辑，只换尺寸、障碍与地表。

func _init() -> void:
	arena_size = Vector2(2200.0, 1400.0)
	gate_pos = Vector2(1100.0, 1330.0)
	obstacles = [
		## 岩石
		{"rect": Rect2(380, 320, 110, 90), "kind": "rock"},
		{"rect": Rect2(1750, 420, 120, 100), "kind": "rock"},
		{"rect": Rect2(520, 1080, 100, 85), "kind": "rock"},
		{"rect": Rect2(1650, 1050, 115, 95), "kind": "rock"},
		{"rect": Rect2(1050, 470, 90, 75), "kind": "rock"},
		## 大树（rect 为树干碰撞）
		{"rect": Rect2(300, 600, 30, 30), "kind": "tree"},
		{"rect": Rect2(1900, 750, 30, 30), "kind": "tree"},
		{"rect": Rect2(900, 280, 30, 30), "kind": "tree"},
		{"rect": Rect2(1350, 1150, 30, 30), "kind": "tree"},
		{"rect": Rect2(700, 850, 30, 30), "kind": "tree"},
		{"rect": Rect2(1500, 250, 30, 30), "kind": "tree"},
		{"rect": Rect2(260, 1080, 30, 30), "kind": "tree"},
		{"rect": Rect2(1960, 300, 30, 30), "kind": "tree"},
	]


# ---------------------------------------------------------------- 地表

func _draw_ground() -> void:
	## 草底
	draw_rect(Rect2(Vector2.ZERO, arena_size), Color("33502c"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	## 草地深浅斑驳
	for i in 260:
		var p := Vector2(rng.randf_range(0.0, arena_size.x), rng.randf_range(0.0, arena_size.y))
		draw_circle(p, rng.randf_range(3.0, 7.0), Color(0.22, 0.38, 0.2, 0.4))
	## 泥土主路：南侧村口 → 中央，略带弯曲
	var y := 640.0
	while y < arena_size.y + 60.0:
		var x := 1100.0 + sin(y * 0.012) * 46.0
		draw_circle(Vector2(x, y), 62.0, Color("6e5c3e"))
		y += 46.0
	## 村口空地
	draw_circle(Vector2(1100.0, arena_size.y - 40.0), 120.0, Color("756244"))
	## 高草簇
	for g in [Vector2(500, 500), Vector2(1600, 600), Vector2(820, 1150), Vector2(1400, 350), Vector2(420, 820), Vector2(1820, 900)]:
		_draw_grass_tuft(g)
	## 小花
	for f in [Vector2(620, 420), Vector2(1550, 780), Vector2(980, 900), Vector2(1250, 520), Vector2(460, 1000)]:
		draw_circle(f, 3.0, Color("e8d24a"))
		draw_circle(f + Vector2(3, 2), 2.0, Color("d86a5a"))


func _draw_grass_tuft(c: Vector2) -> void:
	for a in [-0.5, 0.0, 0.5]:
		var d := Vector2(sin(a), -1.0).normalized()
		draw_line(c, c + d * 12.0, Color("2c4624"), 2.0)


## 边界：密集树墙
func _draw_border() -> void:
	var step := 78.0
	var x := 20.0
	while x < arena_size.x:
		_draw_border_tree(Vector2(x, 18.0))
		_draw_border_tree(Vector2(x, arena_size.y - 18.0))
		x += step
	var y := 20.0
	while y < arena_size.y:
		_draw_border_tree(Vector2(18.0, y))
		_draw_border_tree(Vector2(arena_size.x - 18.0, y))
		y += step
	## 南侧村口开口：少画两棵，改为路标
	draw_rect(Rect2(1060.0, arena_size.y - 70.0, 80.0, 14.0), Color("5a4632"))
	draw_string(Data.font(), Vector2(1075.0, arena_size.y - 78.0), Data.s("wild.village_dir"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e8dcc0"))


func _draw_border_tree(c: Vector2) -> void:
	draw_circle(c, 34.0, Color("264424"))
	draw_circle(c + Vector2(-8, -8), 20.0, Color("33562c"))
