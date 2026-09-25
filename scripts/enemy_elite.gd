class_name EnemyElite
extends EnemyBrute
## 精英敌人：重型变体——更厚、更快，还会在中距离投掷三连苦无扇。
## 出现在波次任务的最后一段与讨伐任务的少量刷怪中，是高价值击杀目标。

const SHOOT_RANGE := 320.0
const SHOOT_CD := 2.6
const KUNAI_SPEED := 460.0
const KUNAI_DAMAGE := 7.0

var shoot_timer := 1.2


func _init() -> void:
	max_hp = 380.0
	hit_radius = 30.0
	move_speed = 142.0
	body_color = Color("8f2f4f")
	body_size = Vector2(52, 52)
	xp_value = 60
	pixel_size = 3.6
	ninja_cfg = {
		"hair": Color("3a3a44"), "hair_dark": Color("2a2a34"),
		"skin": Color("d9a87e"), "skin_dark": Color("b8865e"),
		"band": Color("24242c"), "plate": Color("9a9aa4"),
		"outfit": Color("26262e"), "outfit_dark": Color("1a1a22"),
		"trim": Color("4a4a56"), "belt": Color("181820"),
		"pants": Color("22222a"), "pants_dark": Color("181820"),
		"shoes": Color("14141a"),
		"pattern": "cloud", "pattern_color": Color("c8383a"),
	}


func _tick(delta: float) -> void:
	shoot_timer = maxf(shoot_timer - delta, 0.0)
	if state == S.CHASE and shoot_timer <= 0.0 and confused_timer <= 0.0 and stagger_timer <= 0.0:
		var player = _player()
		if player != null:
			var d: float = global_position.distance_to(player.global_position)
			if d > ATTACK_RANGE + 10.0 and d < SHOOT_RANGE:
				_shoot_fan(player)
				shoot_timer = SHOOT_CD
	super._tick(delta)


func _shoot_fan(player) -> void:
	var base: Vector2 = (player.global_position - global_position).normalized()
	for i in [-1, 0, 1]:
		var dir := base.rotated(deg_to_rad(13.0 * float(i)))
		Projectile.create(game.projectile_container, global_position + dir * 28.0, dir, {
			"kind": "kunai",
			"speed": KUNAI_SPEED,
			"damage": KUNAI_DAMAGE,
			"knockback": 200.0,
			"lifetime": 1.4,
			"hit_radius": 6.0,
			"color": Color(0.95, 0.5, 0.65),
			"hostile": true,
			"game": game,
		})
