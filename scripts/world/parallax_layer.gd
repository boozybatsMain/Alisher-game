extends Node2D
## Слой параллакса: factor < 1 — дальше (едет медленнее камеры), > 1 — ближе (быстрее).
## Дети расставлены в «координатах слоя»: x_экрана = x - камера·factor + 640.

@export var factor := 0.5


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		position.x = cam.get_screen_center_position().x * (1.0 - factor)
