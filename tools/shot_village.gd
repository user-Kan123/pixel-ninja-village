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
	cam.zoom = Vector2(0.30, 0.30)
	p.global_position = village.center
	await get_tree().create_timer(0.4).timeout
	await _shot("village_overview.png")

	## 2) 火影区近景
	cam.zoom = Vector2(0.62, 0.62)
	p.global_position = Vector2(2000, 1120)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_hokage.png")

	## 3) 商业区 + 中忍考试森林
	cam.zoom = Vector2(0.62, 0.62)
	p.global_position = Vector2(2800, 1400)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_market.png")

	## 4) 河对岸与正门
	cam.zoom = Vector2(0.62, 0.62)
	p.global_position = Vector2(1600, 2200)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_riverside.png")

	## 5) 北面：火影岩与围墙
	cam.zoom = Vector2(0.62, 0.62)
	p.global_position = Vector2(2000, 480)
	await get_tree().create_timer(0.3).timeout
	await _shot("village_rock.png")

	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("user://" + name)
	var err: int = img.save_png(path)
	print("SHOT PATH ", path, " ERR ", err, " SIZE ", img.get_size())
