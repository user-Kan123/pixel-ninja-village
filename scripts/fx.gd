class_name Fx
extends Node2D
## 简易特效：碎片爆发 / 残影。纯程序化绘制，无素材依赖。

var vel := Vector2.ZERO
var col := Color.WHITE
var size := 5.0
var life := 0.5
var age := 0.0
var is_ghost := false


static func burst(parent: Node, pos: Vector2, color: Color, count := 8, speed := 200.0) -> void:
	for i in count:
		var f := Fx.new()
		f.position = pos
		f.col = color
		f.size = randf_range(3.0, 6.0)
		f.life = randf_range(0.3, 0.55)
		f.vel = Vector2.from_angle(TAU * float(i) / float(count) + randf() * 0.7) * speed * randf_range(0.4, 1.1)
		parent.add_child(f)


static func ghost(parent: Node, pos: Vector2, color: Color) -> void:
	var f := Fx.new()
	f.position = pos
	f.col = color
	f.size = 14.0
	f.life = 0.35
	f.vel = Vector2.ZERO
	f.is_ghost = true
	parent.add_child(f)


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	position += vel * delta
	vel = vel.move_toward(Vector2.ZERO, 500.0 * delta)
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - age / life
	if is_ghost:
		draw_rect(Rect2(-size, -size * 1.3, size * 2.0, size * 2.6), Color(col.r, col.g, col.b, a))
	else:
		draw_rect(Rect2(-size / 2.0, -size / 2.0, size, size), Color(col.r, col.g, col.b, a))
