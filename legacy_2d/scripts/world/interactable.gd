extends Area2D
## Предмет в Юрте, с которым можно взаимодействовать (E): дверь, сундук, очаг, домбра.

signal used

@export var prompt := "Взаимодействовать"
@export var width := 160.0
@export var prompt_y := -260.0

var inside := false
var label: Label
var glow: Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(width, 240)
	cs.shape = s
	cs.position = Vector2(0, -120)
	add_child(cs)
	glow = Sprite2D.new()
	glow.texture = preload("res://assets/fx/soft.png")
	glow.material = preload("res://scripts/fx/effects.gd").additive()
	glow.scale = Vector2(width / 60.0, 1.6)
	glow.position = Vector2(0, -90)
	glow.modulate = Color(1.0, 0.85, 0.5, 0.0)
	add_child(glow)
	label = preload("res://scripts/ui/ui_kit.gd").label("[E]  " + prompt, 22, Color(1, 0.93, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_override("font", preload("res://scripts/ui/ui_kit.gd").font())
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(420, 34)
	label.position = Vector2(-210, prompt_y)
	label.modulate.a = 0.0
	label.z_index = 50
	add_child(label)
	body_entered.connect(func(b): if b.is_in_group("player"): _set_inside(true))
	body_exited.connect(func(b): if b.is_in_group("player"): _set_inside(false))


func _set_inside(v: bool) -> void:
	inside = v
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0 if v else 0.0, 0.2)
	tw.tween_property(glow, "modulate:a", 0.28 if v else 0.0, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if inside and event.is_action_pressed("interact"):
		var hero := get_tree().get_first_node_in_group("player")
		if hero and hero.input_enabled:
			get_viewport().set_input_as_handled()
			used.emit()
