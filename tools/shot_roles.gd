extends Battlefield
## 临时工具：排列玩家与 5 种敌人，渲染后截图到项目目录，用于核对像素角色外观。

func _ready() -> void:
	super._ready()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame
	var c: Vector2 = arena_size * 0.5
	player.global_position = c
	player.invuln_timer = 999.0
	var roles: Array = [
		[EnemyDummy.new(), c + Vector2(-320, -20)],
		[EnemyChaser.new(), c + Vector2(-180, -200)],
		[EnemyShooter.new(), c + Vector2(0, -240)],
		[EnemyBrute.new(), c + Vector2(180, -200)],
		[EnemyElite.new(), c + Vector2(320, -20)],
	]
	for r in roles:
		var e = r[0]
		e.game = self
		e.global_position = r[1]
		add_child(e)
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var p: String = ProjectSettings.globalize_path("user://roles.png")
	var err: int = img.save_png(p)
	print("SHOT PATH ", p, " ERR ", err, " SIZE ", img.get_size())
	get_tree().quit()
