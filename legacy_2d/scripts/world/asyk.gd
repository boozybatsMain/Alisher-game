extends Node2D
## Асык (альчик) — валюта. Выпадает из врагов, подпрыгивает по земле, притягивается к Батыру.

const TEX := preload("res://assets/ui/icons/asyk.png")

var vel := Vector2.ZERO
var ground_y := 0.0
var magnet := false
var age := 0.0
var spr: Sprite2D


func _ready() -> void:
	add_to_group("asyks")
	z_index = 8
	spr = Sprite2D.new()
	spr.texture = TEX
	spr.scale = Vector2(0.24, 0.24)
	add_child(spr)
	vel = Vector2(randf_range(-170, 170), randf_range(-480, -280))


func start_magnet() -> void:
	magnet = true


func _physics_process(delta: float) -> void:
	age += delta
	var hero := get_tree().get_first_node_in_group("player")
	if hero and age > 0.35:
		var target: Vector2 = hero.global_position + Vector2(0, -90)
		var d := target - global_position
		if magnet or d.length() < 140.0:
			vel = vel.lerp(d.normalized() * 1100.0, minf(1.0, 8.0 * delta))
			global_position += vel * delta
			spr.rotation += delta * 12.0
			if d.length() < 34.0:
				_collect()
			return
	vel.y += 1300.0 * delta
	position += vel * delta
	spr.rotation += vel.x * delta * 0.02
	if position.y > ground_y - 10.0:
		position.y = ground_y - 10.0
		vel.y = -vel.y * 0.42
		vel.x *= 0.6


func _collect() -> void:
	GameState.add_asyks(1)
	Sfx.play("asyk", -4.0, 0.15)
	queue_free()
