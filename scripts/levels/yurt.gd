extends Node2D
## Хаб «Священная Юрта (Ақ Орда)».
## Сундук — вечная прокачка за асыки, очаг От-Ана — возрождение, статистика и подношения перед вылазкой,
## дверь справа — выход в степь (дальше путь идёт слева направо, как на арене), домбра — просто сыграть.
## Картинка юрты отражена по горизонтали: все точки ниже — уже в отражённых координатах.

const BATYR := preload("res://scenes/actors/batyr.tscn")
const HUD := preload("res://scripts/ui/hud.gd")
const Menus := preload("res://scripts/ui/menus.gd")
const INTERACT := preload("res://scripts/world/interactable.gd")
const FX := preload("res://scripts/fx/effects.gd")

const GY := 628.0
const HEARTH := Vector2(535.0, 512.0)

var hero: Node
var hud: Node
var light: PointLight2D
var t := 0.0


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.texture = preload("res://assets/bg/yurt.jpg")
	bg.centered = false
	bg.flip_h = true
	bg.material = preload("res://scripts/ui/ui_kit.gd").boil_mat()
	add_child(bg)
	_build_fire()
	var cam := Camera2D.new()
	cam.position = Vector2(640, 360)
	add_child(cam)
	cam.make_current()
	hero = BATYR.instantiate()
	var from_death := GameState.return_reason == "death"
	hero.position = Vector2(640.0 if from_death else 720.0, GY)
	hero.bounds = Vector2(60.0, 1220.0)
	add_child(hero)
	hero.facing = 1
	_add_spot(Vector2(1208, GY), 150.0, "Выйти в степь  →", -330.0, _leave)
	_add_spot(Vector2(900, GY), 250.0, "Алтын Сандық — прокачка", -260.0, _open_chest)
	_add_spot(Vector2(535, GY), 230.0, "Очаг От-Ана", -250.0, _open_hearth)
	_add_spot(Vector2(265, GY), 110.0, "Сыграть на домбре", -270.0, _play_dombra)
	hud = HUD.new()
	add_child(hud)
	hud.bind(hero)
	hud.set_wave("Священная Юрта — Ақ Орда")
	hud.set_hint("A/D — ходить · E — взаимодействовать · Esc — пауза")
	match GameState.return_reason:
		"death":
			hud.show_banner("От-Ана вернула тебя к очагу", "здоровье восстановлено", 2.2)
			FX.glow_burst(self, hero.position + Vector2(0, -120), Color(0.8, 0.45, 1.0, 0.9), 3.0)
		"victory":
			hud.show_banner("Слава батыру!", "Курган очищен", 2.2)
		_:
			hud.show_banner("Священная Юрта", "Ақ Орда", 1.6)
	GameState.return_reason = ""
	Sfx.music("yurt")


func _build_fire() -> void:
	var glow := Sprite2D.new()
	glow.texture = preload("res://assets/fx/soft.png")
	glow.material = FX.additive()
	glow.position = HEARTH + Vector2(0, -30)
	glow.scale = Vector2(5.0, 3.6)
	glow.modulate = Color(1.0, 0.55, 0.25, 0.45)
	add_child(glow)
	# пламя очага: 8 кадров от Codex
	var frames := SpriteFrames.new()
	frames.add_animation("burn")
	frames.set_animation_speed("burn", 12.0)
	var strip: Texture2D = preload("res://assets/fx/fire_strip.png")
	var fw := strip.get_width() / 8
	for i in 8:
		var at := AtlasTexture.new()
		at.atlas = strip
		at.region = Rect2(i * fw, 0, fw, strip.get_height())
		frames.add_frame("burn", at)
	var fire := AnimatedSprite2D.new()
	fire.sprite_frames = frames
	fire.position = HEARTH + Vector2(0, 6)
	fire.offset = Vector2(0, -strip.get_height() * 0.5)
	fire.scale = Vector2(0.55, 0.62)
	fire.material = FX.additive()
	add_child(fire)
	fire.play("burn")
	# фиолетовый дым священного огня
	var smoke := CPUParticles2D.new()
	smoke.texture = preload("res://assets/fx/soft.png")
	smoke.position = HEARTH + Vector2(0, -70)
	smoke.amount = 36
	smoke.lifetime = 3.6
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.emission_rect_extents = Vector2(30, 6)
	smoke.direction = Vector2(0, -1)
	smoke.spread = 14.0
	smoke.gravity = Vector2(6, -18)
	smoke.initial_velocity_min = 40.0
	smoke.initial_velocity_max = 70.0
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 2.4))
	smoke.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(0.72, 0.4, 0.95, 0.0))
	g.add_point(0.2, Color(0.7, 0.38, 0.95, 0.35))
	g.set_color(g.get_point_count() - 1, Color(0.55, 0.3, 0.85, 0.0))
	smoke.color_ramp = g
	add_child(smoke)
	var embers := CPUParticles2D.new()
	embers.texture = preload("res://assets/fx/soft.png")
	embers.material = FX.additive()
	embers.position = HEARTH + Vector2(0, -30)
	embers.amount = 24
	embers.lifetime = 1.8
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(40, 10)
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(0, -60)
	embers.initial_velocity_min = 60.0
	embers.initial_velocity_max = 160.0
	embers.scale_amount_min = 0.03
	embers.scale_amount_max = 0.08
	var g2 := Gradient.new()
	g2.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	g2.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	embers.color_ramp = g2
	add_child(embers)
	light = PointLight2D.new()
	light.texture = preload("res://assets/fx/soft.png")
	light.texture_scale = 9.0
	light.color = Color(1.0, 0.62, 0.35)
	light.energy = 0.55
	light.position = HEARTH + Vector2(0, -40)
	add_child(light)


func _add_spot(pos: Vector2, width: float, prompt: String, prompt_y: float, cb: Callable) -> void:
	var a := INTERACT.new()
	a.position = pos
	a.width = width
	a.prompt = prompt
	a.prompt_y = prompt_y
	add_child(a)
	a.used.connect(cb)


func _process(delta: float) -> void:
	t += delta
	light.energy = 0.5 + 0.08 * sin(t * 9.0) + 0.05 * sin(t * 23.0)


func _leave() -> void:
	hero.set_locked(true)
	hero.walk_to(1500.0)
	hero.bounds = Vector2(60.0, 1700.0)
	GameState.start_run()
	Sfx.play("door")
	Fx.change_scene("res://scenes/levels/arena.tscn", 0.6)


func _open_chest() -> void:
	hero.set_locked(true)
	Sfx.play("chest")
	Menus.chest(self, func(): hero.set_locked(false))


func _open_hearth() -> void:
	hero.set_locked(true)
	Sfx.play("fire_whoosh")
	Menus.hearth(self, func(): hero.set_locked(false))


func _play_dombra() -> void:
	Sfx.play("dombra")
	Fx.float_text(self, Vector2(265, 330), "♪  ♫  ♪", Color(1, 0.9, 0.6), 34)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not get_tree().paused and hero.input_enabled:
		Menus.pause(self, func(): Fx.change_scene("res://scenes/ui/title.tscn"))
		get_viewport().set_input_as_handled()
