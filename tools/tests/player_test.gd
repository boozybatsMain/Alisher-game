extends Node3D
## Авто-тест модуля A (герой, акробатика, камера, HUD, эффекты).
## godot --headless --path . res://tools/tests/player_test.tscn
## Строит пол, стену и уступ; спавнит героя через Run.spawn_player и симулирует ввод.

var fails := 0
var passes := 0
var p: Player
var _kicks := 0
var _dodges := 0
var _landed := 0
var _activated := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("  PASS ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func secs(t: float) -> void:
	await frames(int(t * 60.0))


func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)


func release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "dash", "slide", "attack", "special", "interact"]:
		Input.action_release(a)


func box(pos: Vector3, size: Vector3, color := Color(0.5, 0.4, 0.3)) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material = mat
	mi.mesh = m
	b.add_child(mi)
	add_child(b)
	b.global_position = pos
	return b


func place(pos: Vector3, face := Vector3(0, 0, 1)) -> void:
	release_all()
	p.teleport_to(pos)
	p.facing = face
	p.velocity = Vector3.ZERO
	await frames(10)


func _run() -> void:
	print("=== player_test ===")
	# мир: пол (верх y=0), стена x=-6 (грань), уступ высотой 3 м с гранью z=2.5, пропасть за x>20
	box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	box(Vector3(-6.5, 4, 0), Vector3(1, 8, 20), Color(0.3, 0.3, 0.35))
	box(Vector3(6, 1.5, -2), Vector3(8, 3, 9), Color(0.6, 0.45, 0.3))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	# камера без поворота по Y: move_up = -Z, move_right = +X (для простых проверок)
	var cam := Camera3D.new()
	cam.rotation_degrees = Vector3(-35, 0, 0)
	cam.position = Vector3(0, 14, 22)
	add_child(cam)
	cam.make_current()

	Run.hp = Run.max_hp()
	var node := Run.spawn_player(self, Vector3(0, 0.2, 8))
	p = node as Player
	check(p != null, "Run.spawn_player создаёт Player")
	if p == null:
		_finish()
		return
	var hud := Run.spawn_hud(self)
	check(hud is Hud, "Run.spawn_hud создаёт Hud")
	Bus.player_wall_kick.connect(func(_pos: Vector3): _kicks += 1)
	Bus.perfect_dodge.connect(func(_a: Node): _dodges += 1)
	Bus.player_landed.connect(func(_h: float): _landed += 1)
	await secs(0.4)
	check(p.is_in_group("player") and p.collision_layer == 2 and p.collision_mask == 1, "группа player, слои 2/1")
	check(p.is_on_floor(), "стоит на полу")
	check(p.sprite is AnimatedSprite3D and p.sprite.sprite_frames != null, "спрайт героя загружен")
	check(p.weapon != null, "оружие создано через WeaponFactory")
	var aabb := p.sprite.get_aabb()
	check(absf(aabb.position.y) < 0.15 and aabb.size.y > 1.2, "ноги спрайта у нуля (aabb y=%.2f h=%.2f)" % [aabb.position.y, aabb.size.y])

	# --- бег
	var x0 := p.global_position.x
	Input.action_press("move_right")
	await secs(0.5)
	Input.action_release("move_right")
	check(p.global_position.x - x0 > 2.0, "бег вправо (+%.2f м)" % (p.global_position.x - x0))
	check(p.facing.x > 0.9, "facing вправо")
	await secs(0.3)

	# --- прыжок
	await place(Vector3(0, 0.1, 8))
	var y0 := p.global_position.y
	await tap("jump")
	await secs(0.25)
	check(p.global_position.y - y0 > 1.0 and p.airborne, "прыжок (y +%.2f)" % (p.global_position.y - y0))
	var landed_before := _landed
	await secs(1.0)
	check(p.is_on_floor() and _landed > landed_before, "приземление + Bus.player_landed")

	# --- рывок
	await secs(1.2)
	var mx := p.max_dash_charges()
	check(p.dash_charges == mx, "заряды рывка полны (%d)" % mx)
	var z0 := p.global_position.z
	p.facing = Vector3(0, 0, 1)
	await place(Vector3(0, 0.1, 4))
	z0 = p.global_position.z
	Input.action_press("dash")
	await frames(3)
	Input.action_release("dash")
	check(p.dash_charges == mx - 1, "рывок тратит заряд (%d)" % p.dash_charges)
	check(p.invulnerable(), "неуязвимость в рывке")
	# идеальное уклонение: враг бьёт во время рывка
	var hp0 := Run.hp
	var enemy_stub := Node3D.new()
	add_child(enemy_stub)
	p.take_hit(Hit.make(20, enemy_stub))
	check(Run.hp == hp0 and _dodges == 1, "удар в рывке не проходит, perfect_dodge")
	await secs(0.3)
	check(p.global_position.z - z0 > 3.0, "рывок переносит героя (%.2f м)" % (p.global_position.z - z0))
	await secs(1.0)
	check(p.dash_charges == mx, "заряды перезарядились")
	# воздушный рывок
	await tap("jump")
	await secs(0.15)
	var c_before := p.dash_charges
	await tap("dash")
	check(p.dash_charges == c_before - 1 and p.is_dashing(), "воздушный рывок")
	await secs(1.5)

	# --- зацеп за уступ: уступ 3 м, грань z=2.5, x 2..10
	await place(Vector3(6, 0.1, 4.2), Vector3(0, 0, -1))
	Input.action_press("move_up")
	await frames(2)
	await tap("jump")
	var grabbed := false
	for i in 70:
		await frames(1)
		if p.is_ledge_grabbing():
			grabbed = true
	await secs(0.4)
	Input.action_release("move_up")
	check(grabbed, "зацеп за уступ сработал")
	check(p.global_position.y > 2.8 and p.global_position.z < 2.5, "герой наверху уступа (y=%.2f z=%.2f)" % [p.global_position.y, p.global_position.z])
	await secs(0.3)
	check(p.is_on_floor(), "стоит на уступе")

	# --- отскок от стены (грань x=-6)
	await place(Vector3(-4.5, 0.1, 6), Vector3(-1, 0, 0))
	Input.action_press("move_left")
	await tap("jump")
	await secs(0.3)
	var kicks0 := _kicks
	await tap("jump")
	await frames(2)
	Input.action_release("move_left")
	check(_kicks == kicks0 + 1, "Bus.player_wall_kick")
	check(p.velocity.x > 4.0 and p.velocity.y > 5.0, "отскок отталкивает от стены (v=%s)" % str(p.velocity))
	check(p.since_wall_kick() < 0.5, "wall_kick_time обновлён")
	# удар с отскока (Особая в воздухе): оружие (или герой по умолчанию) бьёт сверху вниз
	var dummy := Dummy.new()
	add_child(dummy)
	dummy.global_position = Vector3(p.global_position.x + 0.5, 0.0, p.global_position.z)
	await tap("special")
	await secs(1.0)
	check(dummy.hits > 0 and p.is_on_floor(), "удар с отскока бьёт цель под героем (hits=%d)" % dummy.hits)
	dummy.queue_free()
	await secs(0.5)

	# --- бег по стене: прыжок вдоль стены
	await place(Vector3(-5.5, 0.1, 6), Vector3(0, 0, -1))
	Input.action_press("move_up")
	Input.action_press("move_left")
	await frames(3)
	await tap("jump")
	var ran := false
	for i in 30:
		await frames(1)
		if p.is_wall_running():
			ran = true
	release_all()
	check(ran, "бег по стене")
	await secs(1.2)

	# --- подкат
	await place(Vector3(0, 0.1, 8), Vector3(1, 0, 0))
	Input.action_press("move_right")
	await tap("slide")
	await frames(3)
	check(p.sliding, "подкат: флаг sliding")
	await secs(0.8)
	Input.action_release("move_right")
	check(not p.sliding, "подкат завершился")

	# --- урон
	await secs(0.5)
	Run.set_hp(Run.max_hp())
	hp0 = Run.hp
	var dmg := [0.0]
	var cb := func(a: float, _s: Node): dmg[0] += a
	Bus.player_damaged.connect(cb)
	p.take_hit(Hit.make(10, enemy_stub))
	check(is_equal_approx(Run.hp, hp0 - 10.0), "take_hit уменьшает Run.hp (%.0f → %.0f)" % [hp0, Run.hp])
	check(dmg[0] == 10.0, "Bus.player_damaged")
	p.take_hit(Hit.make(10, enemy_stub))
	check(is_equal_approx(Run.hp, hp0 - 10.0), "неуязвимость после удара")
	await secs(0.6)
	# блок спереди
	p.blocking = true
	p.block_dir = Vector3(1, 0, 0)
	enemy_stub.global_position = p.global_position + Vector3(2, 0, 0)
	var hp1 := Run.hp
	p.take_hit(Hit.make(20, enemy_stub))
	check(Run.hp > hp1 - 3.0 and Run.hp < hp1, "блок спереди режет урон (%.1f)" % (hp1 - Run.hp))
	p.blocking = false
	Bus.player_damaged.disconnect(cb)
	await secs(0.5)

	# --- воскрешение (Клятва Жизни)
	await secs(0.6)
	Run.revives_left = 1
	Run.set_hp(5.0)
	p.take_hit(Hit.make(30, enemy_stub))
	check(not p.is_dead() and Run.revives_left == 0 and Run.hp > Run.max_hp() * 0.35, "воскрешение: 40%% HP (%.0f)" % Run.hp)
	check(p.invulnerable(), "неуязвимость после воскрешения")
	await secs(2.2)
	Run.set_hp(Run.max_hp())

	# --- Vault через врага
	await place(Vector3(0, 0.1, 8), Vector3(1, 0, 0))
	var foe := Dummy.new()
	foe.add_to_group("enemies")
	add_child(foe)
	foe.global_position = Vector3(1.3, 0, 8)
	await tap("jump")
	var peak := 0.0
	for i in 70:
		await frames(1)
		peak = maxf(peak, p.global_position.y)
	check(p.global_position.x > foe.global_position.x + 0.3 and peak > 2.2, "Vault: перелёт через врага (x=%.2f, h=%.2f)" % [p.global_position.x, peak])
	check(p.facing.x < -0.5, "Vault: разворот к врагу")
	foe.queue_free()
	await secs(0.3)

	# --- пропасть
	var hp2 := Run.hp
	p.teleport_to(Vector3(0, -12, 0))
	await frames(3)
	check(is_equal_approx(Run.hp, hp2 - 15.0) and p.global_position.y > -1.0, "падение в пропасть: -15 и возврат (y=%.1f)" % p.global_position.y)
	await secs(0.5)

	# --- интерактив
	var it := Interactable.new()
	it.prompt = "Тест"
	add_child(it)
	it.global_position = p.global_position + Vector3(0.8, 0, 0)
	it.activated.connect(func(_pl: Node): _activated += 1)
	await frames(3)
	check(p.current_interactable == it, "ближайший Interactable найден")
	await tap("interact")
	await frames(2)
	check(_activated == 1, "interact → activate(player)")
	it.queue_free()

	# --- aim, lunge, play_anim
	check(p.aim_dir().length() > 0.9, "aim_dir единичный")
	p.lunge(Vector3(1, 0, 0), 10.0, 0.2)
	var lx := p.global_position.x
	await secs(0.2)
	check(p.global_position.x - lx > 1.0, "lunge")
	p.play_anim("attack1")
	check(p.sprite.animation == "attack1", "play_anim")

	# --- эффекты (не падают)
	Fx3D.burst(self, Vector3.ZERO, Color.RED, 8)
	Fx3D.ring(self, Vector3.ZERO, 3.0, Color.WHITE)
	Fx3D.slash_arc(self, Vector3.ZERO, Vector3(1, 0, 0), 2.0)
	Fx3D.lightning(self, Vector3.ZERO, Vector3(3, 1, 0))
	var tc := Fx3D.telegraph_circle(self, Vector3(2, 0, 2), 2.0, 0.5)
	var tco := Fx3D.telegraph_cone(self, Vector3(2, 0, 2), Vector3(0, 0, 1), 3.0, 90.0, 0.5)
	var tl := Fx3D.telegraph_line(self, Vector3(0, 0, 0), Vector3(5, 0, 0), 1.0, 0.5)
	Fx3D.flash_sprite(p.sprite)
	Fx3D.puff(self, Vector3.ZERO)
	check(tc != null and tco != null and tl != null, "телеграфы создаются")
	check(Fx3D.burst(null, Vector3.ZERO, Color.RED) == null, "Fx3D с parent=null безопасен")
	Bus.damage_number.emit(Vector3(0, 2, 0), 12.0, "crit")
	Bus.toast.emit("Тест тоста", Color.WHITE)
	await secs(1.0)
	check(not is_instance_valid(tc), "телеграф сам удаляется")

	# --- камера
	var gc := GameCamera.attach(self, p)
	await frames(5)
	check(get_viewport().get_camera_3d() == gc, "GameCamera.attach делает камеру текущей")
	var off := gc.global_position - p.global_position
	check(off.x > 0 and off.z > 0 and off.y > 5.0, "камера с юго-востока сверху (%s)" % str(off.snapped(Vector3.ONE * 0.1)))
	Bus.shake.emit(1.0, 0.2)
	Bus.hitstop.emit(0.05)
	await secs(0.3)
	check(Engine.time_scale == 1.0, "хитстоп восстанавливает time_scale")

	# --- диалог
	Bus.dialogue_requested.emit([{"speaker": "Ата", "text": "Корни помнят."}, {"speaker": "Кайсар", "text": "Я вернусь."}])
	await get_tree().process_frame
	await get_tree().process_frame
	check(DialogueBox.is_open() and get_tree().paused, "диалог открыт, мир на паузе")
	var db := DialogueBox.ensure(get_tree())
	for i in 4:
		db.advance()
	check(not DialogueBox.is_open() and not get_tree().paused, "диалог закрыт, пауза снята")

	_finish()


func _finish() -> void:
	release_all()
	print("=== player_test: passed %d, failed %d ===" % [passes, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 1)


class Dummy extends Node3D:
	var hits := 0
	var hit_radius := 0.5
	func _ready() -> void:
		add_to_group("hurtable_enemy")
	func take_hit(_h: Hit) -> void:
		hits += 1
	func is_dead() -> bool:
		return false
	func get_facing() -> Vector3:
		return Vector3(0, 0, 1)
