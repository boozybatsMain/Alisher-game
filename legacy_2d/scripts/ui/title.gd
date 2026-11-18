extends Node2D
## Титульный экран: юрта в полумраке, Батыр у очага, название и меню.

const UI := preload("res://scripts/ui/ui_kit.gd")
const Menus := preload("res://scripts/ui/menus.gd")
const FX := preload("res://scripts/fx/effects.gd")

var controls: Label
var reset_armed := false
var reset_btn: Button


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.texture = preload("res://assets/bg/yurt.jpg")
	bg.centered = false
	bg.modulate = Color(0.5, 0.42, 0.42)
	bg.material = UI.boil_mat()
	add_child(bg)
	var glow := Sprite2D.new()
	glow.texture = preload("res://assets/fx/soft.png")
	glow.material = FX.additive()
	glow.position = Vector2(745, 480)
	glow.scale = Vector2(6, 4)
	glow.modulate = Color(1.0, 0.5, 0.2, 0.35)
	add_child(glow)
	var hero := AnimatedSprite2D.new()
	hero.sprite_frames = preload("res://assets/sprites/batyr/batyr_frames.tres")
	var anchor: Vector2 = hero.sprite_frames.get_meta("anchor")
	var fsize: Vector2 = hero.sprite_frames.get_meta("frame_size")
	hero.offset = fsize * 0.5 - anchor
	hero.position = Vector2(930, 650)
	hero.scale = Vector2(1.25, 1.25)
	hero.play("idle")
	add_child(hero)
	var g2 := AnimatedSprite2D.new()
	g2.sprite_frames = preload("res://assets/sprites/batyr/batyr_glow_frames.tres")
	g2.offset = hero.offset
	g2.position = hero.position
	g2.scale = hero.scale
	g2.material = FX.additive()
	g2.play("idle")
	add_child(g2)

	var cl := CanvasLayer.new()
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	cl.add_child(root)
	var title := UI.label("БАТЫР", 112, Color(1, 0.84, 0.45))
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(90, 90)
	root.add_child(title)
	var sub := UI.label("Сказ о Священной Юрте и Степном Кургане", 28, Color(0.95, 0.88, 0.78))
	sub.position = Vector2(96, 222)
	root.add_child(sub)
	var v := VBoxContainer.new()
	v.position = Vector2(96, 300)
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)
	var start := UI.button("Начать путь", func(): Fx.change_scene("res://scenes/levels/yurt.tscn"), 300)
	v.add_child(start)
	v.add_child(UI.button("Управление", func(): controls.visible = not controls.visible, 300))
	reset_btn = UI.button("Сбросить прогресс", _reset, 300)
	v.add_child(reset_btn)
	v.add_child(UI.button("Выход", func(): get_tree().quit(), 300))
	controls = UI.label(Menus.CONTROLS, 18, UI.TEXT)
	controls.position = Vector2(440, 304)
	controls.visible = false
	controls.add_theme_constant_override("outline_size", 6)
	root.add_child(controls)
	var st: Dictionary = GameState.stats
	var info := UI.label("Асыков: %d   ·   Вылазок: %d   ·   Побед: %d" % [GameState.asyks, st["runs"], st["victories"]], 18, UI.MUTED)
	info.position = Vector2(96, 566)
	root.add_child(info)
	start.call_deferred("grab_focus")
	Sfx.music("yurt")


func _reset() -> void:
	if not reset_armed:
		reset_armed = true
		reset_btn.text = "Точно сбросить?"
		return
	GameState.reset_save()
	reset_btn.text = "Прогресс сброшен"
	reset_armed = false
