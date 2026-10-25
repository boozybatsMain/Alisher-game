extends Node2D
## Арена забега. Стадия 0 — «Степной Курган» (закат), стадия 1 — «Сердце Кургана» (ночь).
## Герой входит слева, у камней ветер запирает края арены, идут три волны (третья — босс),
## после каждой волны — выбор Дара. После босса первой стадии путь ведёт вглубь Кургана,
## после второго босса — победа: в Юрту или на следующий, более тяжёлый круг. Смерть — назад в Юрту.

const Waves := preload("res://scripts/data/waves.gd")
const ENEMY := preload("res://scripts/actors/enemy.gd")
const BATYR := preload("res://scenes/actors/batyr.tscn")
const HUD := preload("res://scripts/ui/hud.gd")
const GIFT_CHOICE := preload("res://scripts/ui/gift_choice.gd")
const Menus := preload("res://scripts/ui/menus.gd")
const ATMO := preload("res://scripts/world/atmosphere.gd")
const PARALLAX := preload("res://scripts/world/parallax_layer.gd")
const CAMERA := preload("res://scripts/world/game_camera.gd")
const BARRIER := preload("res://scripts/world/wind_barrier.gd")
const WORLD_SHADER := preload("res://shaders/world.gdshader")
const HAZE_SHADER := preload("res://shaders/haze.gdshader")
const FX := preload("res://scripts/fx/effects.gd")

const GY := 600.0
const WORLD_W := 3600.0
const ARENA := Vector2(560.0, 3040.0)
const FAR_TOP := 468.0
const MAX_ALIVE := 6

enum P { ENTER, EXPLORE, LOCKING, WAVE, CLEAR, CHOOSE, BANNER, EXIT, VICTORY, DEAD }

var phase := P.ENTER
var phase_t := 0.0
var stage_idx := 0
var stage: Dictionary
var night := false
var wave_idx := 0
var queue := []
var wave_t := 0.0
var hero: Node
var cam: Camera2D
var hud: Node
var world: Node2D
var barriers := []
var atmos := []
var boil_mat: ShaderMaterial
var grass_mat: ShaderMaterial
var sky: Sprite2D
var sky_layer: CanvasLayer
var rays := []
var haze: ColorRect
var gust := 0.0
var t := 0.0
var pause_layer: CanvasLayer


func _ready() -> void:
	add_to_group("arena")
	stage_idx = clampi(GameState.stage, 0, Waves.STAGES.size() - 1)
	stage = Waves.STAGES[stage_idx]
	night = stage["theme"] == "night"
	for arg in OS.get_cmdline_user_args():   # для отладки: начать с нужной волны (-- wave=2)
		if arg.begins_with("wave="):
			wave_idx = clampi(int(arg.substr(5)), 0, stage["waves"].size() - 1)
	boil_mat = ShaderMaterial.new()
	boil_mat.shader = WORLD_SHADER
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = WORLD_SHADER
	grass_mat.set_shader_parameter("sway", true)
	_build_world()
	hero = BATYR.instantiate()
	hero.position = Vector2(150.0, GY)
	hero.bounds = Vector2(80.0, ARENA.y - 40.0)
	world.add_child(hero)
	hero.died.connect(_on_hero_died)
	hero.set_locked(true)
	hero.walk_to(430.0)
	cam = CAMERA.new()
	cam.target = hero
	cam.limits = Vector2(0.0, WORLD_W)
	cam.ground_y = GY
	add_child(cam)
	cam.snap()
	hud = HUD.new()
	add_child(hud)
	hud.bind(hero)
	hud.set_wave("%s%s" % [stage["name"], ("   ·   Круг %d" % GameState.cycle) if GameState.cycle > 1 else ""])
	hud.show_banner(stage["name"], "Стадия %d из %d" % [stage_idx + 1, Waves.STAGES.size()], 1.8)
	Sfx.music("battle_night" if night else "battle_day")
	_set_phase(P.ENTER)


# ------------------------------------------------------------------ мир
func _sprite(tex: Texture2D, pos: Vector2, parent: Node, mat: Material = null, scale_k := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = pos
	s.scale = Vector2(scale_k, scale_k)
	if mat:
		s.material = mat
	parent.add_child(s)
	return s


func _tiled(tex: Texture2D, x0: float, y: float, width: float, parent: Node, mat: Material = null) -> Sprite2D:
	var s := _sprite(tex, Vector2(x0, y), parent, mat)
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, width, tex.get_height())
	return s


func _parallax(f: float) -> Node2D:
	var p := PARALLAX.new()
	p.factor = f
	add_child(p)
	return p


func _atmo(layer: String) -> void:
	var a := ATMO.new()
	a.layer = layer
	a.night = night
	a.ground_y = GY
	add_child(a)
	atmos.append(a)


func _build_world() -> void:
	# небо — отдельный слой позади всего (ночной тинт мира его не трогает)
	sky_layer = CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	sky = Sprite2D.new()
	sky.texture = load("res://assets/bg/sky_night.jpg" if night else "res://assets/bg/sky_day.jpg")
	sky.centered = false
	sky.position = Vector2(-52, -70)
	sky.material = boil_mat
	sky_layer.add_child(sky)
	var glow := Sprite2D.new()
	glow.texture = preload("res://assets/fx/sun_glow.png")
	glow.material = FX.additive()
	glow.position = Vector2(1280, 181) if night else Vector2(1221, 420)
	glow.scale = Vector2(0.7, 0.7) if night else Vector2(1.25, 1.25)
	glow.modulate = Color(0.75, 0.8, 1.0, 0.7) if night else Color(1, 1, 1, 0.9)
	sky.add_child(glow)
	if not night:
		for i in 6:
			var r := Sprite2D.new()
			r.texture = preload("res://assets/fx/ray.png")
			r.centered = false
			r.offset = Vector2(0, -48)
			r.material = FX.additive()
			r.position = Vector2(1221, 420)
			r.scale = Vector2(1.6, 0.9 + 0.5 * ((i * 7) % 3) / 2.0)
			sky.add_child(r)
			rays.append(r)

	_atmo("far")
	# дальний план: своя полоса земли, на которой СТОЯТ руины (раньше они висели на картинке неба)
	var far := _parallax(0.3)
	var far_ground: Texture2D = load("res://assets/bg/ground_far_night.png" if night else "res://assets/bg/ground_far.png")
	_tiled(far_ground, -2600.0, FAR_TOP, 8000.0, far, boil_mat)
	var base := FAR_TOP + 24.0
	var suffix := "night" if night else "far"
	var far_items := [[1, 300.0, 0.62], [0, 900.0, 0.9], [2, 1800.0, 0.66], [3, 2250.0, 0.7], [0, 2800.0, 0.75], [1, 3400.0, 0.6]]
	if night:
		far_items = [[1, 300.0, 0.6], [2, 1300.0, 0.62], [0, 2100.0, 0.8], [3, 2900.0, 0.66]]
	for it in far_items:
		var tex: Texture2D = load("res://assets/bg/ruins_%s_%d.png" % [suffix, it[0]])
		var k: float = it[2]
		var sh := _sprite(preload("res://assets/fx/shadow.png"), Vector2(it[1] - 20.0, base - 14.0), far)
		sh.scale = Vector2(tex.get_width() * k / 160.0, 0.7)
		_sprite(tex, Vector2(it[1], base + 6.0 - tex.get_height() * k), far, boil_mat, k)
	if night:
		var mound: Texture2D = load("res://assets/bg/kurgan_0.png")
		_sprite(mound, Vector2(700.0, base + 4.0 - mound.get_height() * 0.7), far, boil_mat, 0.7)
		_sprite(mound, Vector2(2500.0, base + 4.0 - mound.get_height() * 0.6), far, boil_mat, 0.6)
	# марево над дальним планом (днём)
	if not night:
		var bb := BackBufferCopy.new()
		bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(bb)
		haze = ColorRect.new()
		haze.size = Vector2(1600, 230)
		haze.position = Vector2(0, 350)
		var hm := ShaderMaterial.new()
		hm.shader = HAZE_SHADER
		haze.material = hm
		haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(haze)
	# средний план
	var mid := _parallax(0.72)
	if night:
		var props := [[1, 250.0, 0.95], [3, 1050.0, 1.0], [2, 1650.0, 1.0], [4, 2350.0, 1.0], [5, 2420.0, 1.0], [1, 3150.0, 0.9]]
		for it in props:
			var tex2: Texture2D = load("res://assets/bg/kurgan_%d.png" % it[0])
			_sprite(tex2, Vector2(it[1], 586.0 - tex2.get_height() * it[2]), mid, boil_mat, it[2])
	else:
		var stones := [[0, 250.0], [1, 1200.0], [2, 2000.0], [3, 2550.0], [0, 3050.0], [1, 3550.0]]
		for it in stones:
			var tex3: Texture2D = load("res://assets/bg/stone_%d.png" % it[0])
			_sprite(tex3, Vector2(it[1], 586.0 - tex3.get_height()), mid, boil_mat)
	# ближняя земля
	var ground: Texture2D = preload("res://assets/bg/ground.png")
	var g := _tiled(ground, -1200.0, GY - 58.0, WORLD_W + 2400.0, self, boil_mat)
	var fill := ColorRect.new()
	fill.color = Color(0.36, 0.18, 0.09)
	fill.position = Vector2(-1200, GY - 60.0 + ground.get_height())
	fill.size = Vector2(WORLD_W + 2400.0, 400)
	add_child(fill)
	g.z_index = 0
	for i in 12:
		var tex4: Texture2D = load("res://assets/bg/grass_%d.png" % (i % 6))
		var s := Sprite2D.new()
		s.texture = tex4
		s.offset = Vector2(0, -tex4.get_height() * 0.5)
		s.position = Vector2(200.0 + i * 300.0 + (i * 137) % 90, GY - 20.0)
		s.scale = Vector2(0.7, 0.7)
		s.material = grass_mat
		add_child(s)
	_atmo("back")
	# барьеры
	for x in [ARENA.x - 40.0, ARENA.y + 40.0]:
		var b := BARRIER.new()
		b.position = Vector2(x, GY)
		add_child(b)
		barriers.append(b)
	# актёры
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	_atmo("front")
	var fg := _parallax(1.2)
	for i in 10:
		var tex5: Texture2D = load("res://assets/bg/grass_%d.png" % ((i * 5) % 6))
		var s2 := Sprite2D.new()
		s2.texture = tex5
		s2.offset = Vector2(0, -tex5.get_height() * 0.5)
		s2.position = Vector2(-300.0 + i * 560.0 + (i * 211) % 160, 750.0)
		s2.scale = Vector2(1.05, 1.05)
		s2.material = grass_mat
		s2.z_index = 35
		fg.add_child(s2)
	_atmo("near")
	if night:
		var cm := CanvasModulate.new()
		cm.color = Color(0.52, 0.5, 0.8)
		add_child(cm)
	var vl := CanvasLayer.new()
	vl.layer = 5
	add_child(vl)
	var vig := TextureRect.new()
	vig.texture = preload("res://assets/fx/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate.a = 0.85 if not night else 1.0
	vl.add_child(vig)


# ------------------------------------------------------------------ цикл
func _process(delta: float) -> void:
	t += delta
	phase_t += delta
	var g := 0.5 + 0.5 * sin(t * 0.29) * sin(t * 0.13 + 1.3)
	gust = pow(maxf(0.0, g), 1.6) * (0.7 if night else 1.3)
	grass_mat.set_shader_parameter("gust", gust)
	for a in atmos:
		a.gust = gust
	if hero:
		hero.gust = gust
	var cx := cam.get_screen_center_position().x if cam else 640.0
	sky.position.x = -20.0 - cx * 0.05
	for i in rays.size():
		var r: Sprite2D = rays[i]
		r.rotation = PI * 0.86 + [-0.34, -0.2, -0.08, 0.04, 0.15, 0.27][i] + sin(t * 0.15 + i * 1.7) * 0.025
		r.modulate.a = 0.55 * (0.6 + 0.4 * sin(t * 0.45 + i * 2.1))
	if haze:
		haze.position.x = cx - 800.0
	_update_phase(delta)


func _set_phase(p: P) -> void:
	phase = p
	phase_t = 0.0


func _update_phase(delta: float) -> void:
	match phase:
		P.ENTER:
			if hero.global_position.x >= 420.0 or phase_t > 2.5:
				hero.walk_to(NAN)
				hero.set_locked(false)
				hud.set_hint("A/D — бег · J — удар · Shift — кувырок · K — блок · Esc — пауза")
				_set_phase(P.EXPLORE)
		P.EXPLORE:
			if hero.global_position.x > ARENA.x + 220.0:
				_lock_arena()
		P.LOCKING:
			if phase_t > 1.0:
				_start_wave()
		P.WAVE:
			_update_spawns(delta)
			if queue.is_empty() and get_tree().get_nodes_in_group("enemies").is_empty():
				_set_phase(P.CLEAR)
				get_tree().call_group("asyks", "start_magnet")
				hero.heal(hero.max_hp * 0.2)   # передышка между волнами
				hud.show_banner("Волна отбита!", "От-Ана даёт передышку: +20% здоровья", 1.2)
				Sfx.play("wave_clear")
		P.CLEAR:
			if phase_t > 1.3 and not hero.is_dead():
				_open_gifts()
		P.BANNER:
			if phase_t > 1.6:
				_begin_spawning()
		P.EXIT:
			if hero.global_position.x > ARENA.y + 260.0:
				_go_next_stage()


func _lock_arena() -> void:
	for b in barriers:
		b.set_active(true)
	hero.bounds = Vector2(ARENA.x, ARENA.y)
	cam.limits = Vector2(ARENA.x - 120.0, ARENA.y + 120.0)
	hud.set_hint("")
	_set_phase(P.LOCKING)
	Fx.shake(6.0)


func _start_wave() -> void:
	var w: Dictionary = stage["waves"][wave_idx]
	hud.show_banner(w["title"], "Волна %d из %d" % [wave_idx + 1, stage["waves"].size()], 1.4)
	hud.set_wave("%s   ·   Волна %d/%d — %s" % [stage["name"], wave_idx + 1, stage["waves"].size(), w["title"]])
	if w.get("boss", false):
		Sfx.music("boss")
	Sfx.play("wave_start")
	_set_phase(P.BANNER)


func _begin_spawning() -> void:
	var w: Dictionary = stage["waves"][wave_idx]
	queue = (w["spawns"] + Waves.extra_spawns(GameState.cycle, w)).duplicate(true)
	queue.sort_custom(func(a, b): return a[2] < b[2])
	wave_t = 0.0
	_set_phase(P.WAVE)


func _update_spawns(delta: float) -> void:
	wave_t += delta
	while not queue.is_empty() and queue[0][2] <= wave_t:
		if get_tree().get_nodes_in_group("enemies").size() >= MAX_ALIVE:
			for q in queue:
				q[2] += 0.5   # толпа — подождём
			break
		var s: Array = queue.pop_front()
		var x: float = ARENA.y - 110.0 if s[1] > 0 else ARENA.x + 110.0
		spawn_enemy(s[0], x)


func spawn_enemy(kind: String, x: float, by: Node = null) -> Node:
	var e := ENEMY.new()
	e.setup(kind, Waves.hp_mult(GameState.cycle), Waves.dmg_mult(GameState.cycle), Vector2(ARENA.x + 20.0, ARENA.y - 20.0), GY)
	e.position = Vector2(x, GY)
	e.player = hero
	e.summoned_by = by
	world.add_child(e)
	e.summon_requested.connect(func(k: String, sx: float): spawn_enemy(k, sx, e))
	if e.is_boss:
		hud.show_boss(e)
	return e


func _open_gifts() -> void:
	_set_phase(P.CHOOSE)
	hud.hide_banner()
	var gc := GIFT_CHOICE.new()
	gc.hero = hero
	gc.chosen.connect(_after_gift)
	add_child(gc)


func _after_gift() -> void:
	if wave_idx < stage["waves"].size() - 1:
		wave_idx += 1
		_start_wave()
		return
	# босс стадии повержен
	if stage_idx < Waves.STAGES.size() - 1:
		barriers[1].set_active(false)
		hero.bounds = Vector2(ARENA.x, WORLD_W - 80.0)
		cam.limits = Vector2(ARENA.x - 120.0, WORLD_W)
		hud.show_banner("Путь вглубь Кургана открыт", "иди направо  →", 2.5)
		hud.set_hint("→  Сердце Кургана")
		Sfx.music("calm")
		_set_phase(P.EXIT)
	else:
		_victory()


func _go_next_stage() -> void:
	if phase != P.EXIT:
		return
	_set_phase(P.VICTORY)
	GameState.stage = stage_idx + 1
	GameState.hp_carry = hero.hp
	hero.set_locked(true)
	hero.walk_to(WORLD_W + 200.0)
	hero.bounds = Vector2(0.0, WORLD_W + 400.0)
	Fx.change_scene("res://scenes/levels/arena.tscn", 0.6)


func _victory() -> void:
	_set_phase(P.VICTORY)
	var bonus := 20 * GameState.cycle
	GameState.add_asyks(bonus)
	Sfx.music("victory")
	var lines := [
		"Повержено врагов: %d" % GameState.run_kills,
		"Собрано асыков: %d (из них награда %d)" % [GameState.run_asyks, bonus],
	]
	Menus.result(self, "Шойынқұлақ повержен!", "Курган очищен. Круг %d пройден." % GameState.cycle, lines, [
		["Вернуться в Юрту", func(): _finish_run(false)],
		["Дальше: Круг %d" % (GameState.cycle + 1), func():
			GameState.cycle += 1
			GameState.stage = 0
			GameState.hp_carry = hero.hp
			Fx.change_scene("res://scenes/levels/arena.tscn")],
	])


func _on_hero_died() -> void:
	_set_phase(P.DEAD)
	Sfx.music("defeat")
	await get_tree().create_timer(1.8, false).timeout
	var lines := [
		"%s · волна %d" % [stage["name"], wave_idx + 1],
		"Повержено врагов: %d   ·   Асыков: %d" % [GameState.run_kills, GameState.run_asyks],
	]
	Menus.result(self, "Батыр пал", "Асыки остаются с тобой — потрать их в сундуке. От-Ана вернёт тебя к очагу.", lines,
		[["Вернуться в Юрту", func(): _finish_run(true)]], Color(1, 0.55, 0.45))


func _finish_run(died: bool) -> void:
	GameState.end_run(died, stage_idx * 3 + wave_idx + 1)
	Fx.change_scene("res://scenes/levels/yurt.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not get_tree().paused and phase != P.CHOOSE and phase != P.VICTORY and phase != P.DEAD:
		Menus.pause(self, func():
			GameState.abandon_run()
			Fx.change_scene("res://scenes/ui/title.tscn"))
		get_viewport().set_input_as_handled()
