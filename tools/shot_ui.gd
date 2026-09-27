extends Node2D
## 临时工具：把装备界面（武器页 / 忍术页）与忍具店各截一张图，用于核对布局。
## 跑法（要有真实窗口，不能 headless）：
##   godot --path . res://tools/shot_ui.tscn
## 输出在 user:// 下：ui_weapon.png / ui_jutsu.png / ui_shop.png

var village


func _ready() -> void:
	village = load("res://scenes/village.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	## 造一份"已经买了不少忍具"的状态，界面才看得出内容
	Flow.money = 320
	Flow.owned_weapons.clear()
	for id in Data.weapon_list:
		Flow.owned_weapons.append(String(id))
	Flow.owned_weapons.erase("longsword")
	var p = village.player
	p.weapon_slots.clear()
	p.weapon_slots.append("tanto")
	p.weapon_slots.append("shuriken")
	p.active_weapon = 0
	p.jutsu_slots.clear()
	for id in Player.DEFAULT_LOADOUT:
		p.jutsu_slots.append(String(id))

	## 1) 装备界面 · 武器页
	village.toggle_loadout()
	village.loadout_ui.show_tab(LoadoutUi.Tab.WEAPON)
	await _shot("ui_weapon.png")

	## 2) 装备界面 · 忍术页
	village.loadout_ui.show_tab(LoadoutUi.Tab.JUTSU)
	await _shot("ui_jutsu.png")
	village.close_loadout()

	## 3) 忍具店（站到店门口打开）
	p.global_position = village.SHOP_POS + Vector2(0.0, 40.0)
	await get_tree().process_frame
	village.toggle_shop()
	await _shot("ui_shop.png")

	## 4) 战斗 HUD 左上角的武器槽（主手投掷忍具，能看到余量）
	village.queue_free()
	await get_tree().process_frame
	Flow.weapon_slots.clear()
	Flow.weapon_slots.append("shuriken")
	Flow.weapon_slots.append("tanto")
	var battle = load("res://scenes/main.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await _shot("hud_weapons.png")

	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("user://" + name)
	var err: int = img.save_png(path)
	print("SHOT PATH ", path, " ERR ", err, " SIZE ", img.get_size())
