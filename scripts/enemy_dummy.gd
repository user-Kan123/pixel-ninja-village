class_name EnemyDummy
extends EnemyBase
## 木桩：不会移动，用于测试连招伤害、击退与忍术命中。


func _init() -> void:
	max_hp = 90.0
	hit_radius = 20.0
	body_color = Color("8a6a4a")
	body_size = Vector2(36, 36)
