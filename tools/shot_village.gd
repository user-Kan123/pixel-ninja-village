extends Node2D
## 临时工具：村庄俯瞰图与近景，用于核对新版木叶村的布局。
## 跑法（要有真实窗口，不能 headless）：godot --path . res://tools/shot_village.tscn

var village


func _ready() -> void:
	village = load("res://scenes/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	var p = village.player
	print("BUILDINGS ", village.buildings.size(), "  TREES ", village._trees.size())
	for b in village.buildings:
		var id := String(b["id"])
		if id.begins_with("grid_") or id.begins_with("forest_"):
			continue
		var r: Rect2 = b["rect"]
		print("LM ", id, "  rect=", r.position, " size=", r.size)
	var cam: Camera2D = p.get_viewport().get_camera_2d()
	if cam == null:
		print("SHOT ERROR: no camera")
		get_tree().quit()
		return
	cam.limit_left = -99999
	cam.limit_top = -99999
	cam.limit_right = 99999
	cam.limit_bottom = 99999
	cam.position_smoothing_enabled = false

	## 1) 整村俯瞰
	## 画布 7200×5200，要装进 1280×720 需要 zoom ≤ 0.138
	cam.zoom = Vector2(0.138, 0.138)
	p.global_position = village.center
	await get_tree().create_timer(0.4).timeout
	await _shot("village_overview.png")

	## 1.5) 中景（约半个村子，看街区与建筑密度）
	cam.zoom = Vector2(0.26, 0.26)
	p.global_position = village.center
	await get_tree().create_timer(0.3).timeout
	await _shot("village_mid.png")

	## 2) 火影区近景（岩 + 火影楼 + 公园A）
	cam.zoom = Vector2(0.55, 0.55)
	p.global_position = Vector2(3600, 900)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_hokage.png")

	## 3) 商业区 + 中忍考试森林
	cam.zoom = Vector2(0.55, 0.55)
	p.global_position = Vector2(5400, 2200)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_market.png")

	## 4) 河对岸与宇智波村落
	cam.zoom = Vector2(0.55, 0.55)
	p.global_position = Vector2(2700, 4100)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_riverside.png")

	## 5) 西侧训练场群
	cam.zoom = Vector2(0.42, 0.42)
	p.global_position = Vector2(700, 2600)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_training.png")

	## 6) 夜景（同一机位，验证夜幕与玩家周围微光）
	Flow.hour = 21.0
	cam.zoom = Vector2(0.42, 0.42)
	p.global_position = village.center
	await get_tree().create_timer(0.3).timeout
	await _shot("village_night.png")

	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("user://" + name)
	var err: int = img.save_png(path)
	print("SHOT PATH ", path, " ERR ", err, " SIZE ", img.get_size())
