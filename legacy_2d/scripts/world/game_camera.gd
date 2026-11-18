extends Camera2D
## Камера: плавно следует за героем и смотрит вперёд по ходу, трясётся от ударов,
## на тяжёлом ударе коротко наезжает, на скорости чуть отъезжает. Линия земли при зуме остаётся на месте.

var target: Node2D
var look := 230.0
var follow := 10.0
var limits := Vector2(0.0, 3600.0)
var ground_y := 600.0
var shake_amp := 0.0
var punch_amt := 0.0
var speed_zoom := 0.0


func _ready() -> void:
	add_to_group("game_camera")
	process_mode = Node.PROCESS_MODE_ALWAYS
	make_current()
	if target:
		position.x = target.global_position.x


func shake(amount: float, _duration := 0.25) -> void:
	shake_amp = maxf(shake_amp, amount)


func punch(amount: float) -> void:
	punch_amt = maxf(punch_amt, amount)


func snap() -> void:
	if target:
		position.x = _target_x()


func _target_x() -> float:
	var half := 640.0 / zoom.x
	var tx: float = target.global_position.x + target.facing * look
	return clampf(tx, limits.x + half, limits.y - half)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var spd := 0.0
	if target and is_instance_valid(target):
		position.x = lerpf(position.x, _target_x(), minf(1.0, delta * follow))
		spd = target.speed()
	shake_amp *= exp(-delta * 13.0)
	punch_amt *= exp(-delta * 6.0)
	var zt := -0.08 * clampf((spd - 300.0) / 600.0, 0.0, 1.0)
	speed_zoom = lerpf(speed_zoom, zt, minf(1.0, delta * (3.0 if zt < speed_zoom else 1.6)))
	var z := 1.0 + punch_amt + speed_zoom
	zoom = Vector2(z, z)
	position.y = ground_y - (ground_y - 360.0) / z
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amp
