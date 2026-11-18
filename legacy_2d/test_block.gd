extends Node
## Тест: щит поднимается мгновенно из любого действия героя.
## Godot --headless --path . res://tools/test_block.tscn

var hero: Node
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _check(name: String, cond: bool, extra := "") -> void:
	print(("OK   " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _reset() -> void:
	Input.action_release("block")
	hero._to_idle()   # щит держится минимум 0.5 с — сбрасываем между проверками
	for k in hero.buf:
		hero.buf[k] = 0.0
	hero.shield_cd = 0.0
	hero.roll_cd = 0.0


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


func _block_from(name: String, setup: Callable) -> void:
	_reset()
	hero.shield_cd = 0.0
	hero.roll_cd = 0.0
	await _frames(2)
	await setup.call()
	var before: int = hero.state
	Input.action_press("block")
	await _frames(1)
	_check("блок из «%s»" % name, hero.state == hero.S.BLOCK,
		"было %s → стало %s, неуязвимость %.2f" % [hero.S.keys()[before], hero.S.keys()[hero.state], hero.invuln])
	Input.action_release("block")
	await _frames(2)


func _run() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/levels/arena.tscn")
	await _wait(3.0)
	hero = get_tree().get_first_node_in_group("player")
	hero.set_locked(false)
	hero.walk_to(NAN)
	var arena := get_tree().get_first_node_in_group("arena")
	arena._set_phase(arena.P.CHOOSE)   # волны не запускаются — в тесте только свои враги
	await _block_from("стойка", func(): await _frames(1))
	await _block_from("удар 1, замах", func():
		hero.buf.attack = 0.16
		await _frames(3))
	await _block_from("удар 3, финал", func():
		hero._start_attack(2)
		await _frames(6))
	await _block_from("восстановление после комбо", func():
		hero._set_state(hero.S.COMBO_REC)
		await _frames(2))
	await _block_from("кувырок", func():
		hero.buf.roll = 0.16
		await _frames(4))
	_check("кувырок прерван — неуязвимость снята", hero.invuln == 0.0)
	await _block_from("восстановление после кувырка", func():
		hero._set_state(hero.S.ROLL_REC)
		await _frames(1))
	await _block_from("рывок-удар", func():
		hero._start_dash()
		await _frames(5))
	await _block_from("оглушение от удара", func():
		hero.receive_attack({"dmg": 1.0, "knock": 100.0, "from_x": hero.global_position.x + 100.0})
		await _frames(1))
	# во время перезарядки щит не поднимается, но мигает
	Input.action_release("block")
	hero._to_idle()
	await _frames(2)
	hero.shield_cd = 0.8
	hero._start_attack(0)
	await _frames(2)
	Input.action_press("block")
	await _frames(2)
	_check("на перезарядке щит не поднимается", hero.state != hero.S.BLOCK)
	_reset()
	# отложенный кувырок не срывает щит, нажатый позже
	hero.shield_cd = 0.0
	hero.roll_cd = 0.0
	hero._start_attack(0)
	await _frames(2)
	hero.buf.roll = 0.16
	await _frames(1)
	Input.action_press("block")
	await _frames(4)
	_check("кувырок из буфера не срывает щит", hero.state == hero.S.BLOCK, hero.S.keys()[hero.state])
	Input.action_release("block")
	# идеальный блок сразу после отмены кувырка
	await _wait(1.2)
	hero.shield_cd = 0.0
	hero.roll_cd = 0.0
	hero._to_idle()
	await _frames(2)
	hero.buf.roll = 0.16
	await _frames(3)
	_check("кувырок начался", hero.state == hero.S.ROLL, hero.S.keys()[hero.state])
	Input.action_press("block")
	await _frames(1)
	var res: String = hero.receive_attack({"dmg": 20.0, "knock": 300.0, "from_x": hero.global_position.x + hero.facing * 100.0, "parry": true, "block": true})
	_check("идеальный блок прямо из кувырка", res == "parried", res)
	Input.action_release("block")
	await _timing_tests()
	await _directional_tests()
	await _real_tap_tests()
	await _double_strike_test()
	print("TEST DONE, failed: ", fails)
	get_tree().quit(1 if fails else 0)


func _spawn_attacker(kind: String, dx: float) -> Node:
	var arena := get_tree().get_first_node_in_group("arena")
	var e: Node = arena.spawn_enemy(kind, hero.global_position.x + dx)
	await _wait(0.8)
	e.global_position.x = hero.global_position.x + dx
	e.face = 1 if dx < 0.0 else -1
	e._start_attack(e.def["attacks"][0])
	e.combo_left = 0   # без случайного второго удара — тест детерминированный
	return e


func _directional_tests() -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	arena._set_phase(arena.P.CHOOSE)   # волны не запускаются
	hero.bounds = Vector2(0.0, 4000.0)
	hero.global_position.x = 1600.0
	hero._to_idle()
	await _wait(0.3)
	# враг сзади, нажат только щит — щит сам разворачивается к нему
	hero.facing = 1
	hero.shield_cd = 0.0
	var e: Node = await _spawn_attacker("balbal", -220.0)
	_check("над врагом в замахе горит «!»", e.alert.visible, "цвет %s" % e.alert.modulate)
	_check("у быстрого замаха есть время на реакцию", e.windup_t >= 0.0)
	var hp0: float = hero.hp
	Input.action_press("block")
	await _frames(2)
	_check("щит без направления — к атакующему сзади", hero.state == hero.S.BLOCK and hero.facing == -1, "facing %d" % hero.facing)
	await _wait(1.0)
	_check("удар сзади заблокирован (−75%)", hp0 - hero.hp > 0.0 and hp0 - hero.hp <= 6.5, "урон %.1f" % (hp0 - hero.hp))
	_check("«!» погас после удара", not e.alert.visible)
	Input.action_release("block")
	e.queue_free()
	await _wait(1.2)
	# направление важнее авто-поворота: щит вправо, враг слева — удар проходит
	hero.hp = hero.max_hp
	hero.shield_cd = 0.0
	hero._to_idle()
	var e2: Node = await _spawn_attacker("balbal", -220.0)
	Input.action_press("move_right")
	Input.action_press("block")
	await _frames(2)
	_check("щит туда, куда нажато направление", hero.state == hero.S.BLOCK and hero.facing == 1, "facing %d" % hero.facing)
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _frames(2)
	_check("щит мгновенно разворачивается при смене направления", hero.facing == -1)
	Input.action_release("move_left")
	Input.action_release("block")
	e2.queue_free()
	await _wait(1.2)
	# враг вплотную (на той же точке) — блок всё равно срабатывает
	hero.shield_cd = 0.0
	hero._to_idle()
	Input.action_press("block")
	await _frames(2)
	var res: String = hero.receive_attack({"dmg": 20.0, "knock": 100.0, "from_x": hero.global_position.x + 5.0 * -hero.facing})
	_check("удар вплотную блокируется", res == "parried" or res == "blocked", res)
	Input.action_release("block")
	# волк: быстрый замах получает удержание позы
	hero.shield_cd = 0.0
	hero._to_idle()
	var w: Node = await _spawn_attacker("wolf", 300.0)
	_check("волку добавлено время на реакцию", w.windup_t > 0.0, "%.2f с" % w.windup_t)
	w.queue_free()


func _timing_tests() -> void:
	# короткое нажатие: щит стоит 0.5 с и опускается сам
	Input.action_release("block")
	hero._to_idle()
	hero.shield_cd = 0.0
	await _frames(2)
	Input.action_press("block")
	await _frames(1)
	Input.action_release("block")
	await _wait(0.35)
	_check("нажатие: через 0.35 с щит ещё стоит", hero.state == hero.S.BLOCK, hero.S.keys()[hero.state])
	await _wait(0.3)
	_check("нажатие: через 0.65 с щит опущен", hero.state != hero.S.BLOCK, hero.S.keys()[hero.state])
	_check("промах — перезарядка 0.6 с", hero.shield_cd > 0.4 and hero.shield_cd <= 0.6, "%.2f" % hero.shield_cd)
	# зажатый щит стоит, пока держишь
	hero._to_idle()
	hero.shield_cd = 0.0
	await _frames(2)
	Input.action_press("block")
	await _wait(1.2)
	_check("зажатый щит держится дольше 0.5 с", hero.state == hero.S.BLOCK)
	Input.action_release("block")
	await _frames(2)
	_check("отпущен после 0.5 с — опускается сразу", hero.state != hero.S.BLOCK)
	# идеальный блок — без перезарядки, можно сразу снова
	hero._to_idle()
	hero.shield_cd = 0.0
	await _frames(2)
	Input.action_press("block")
	await _frames(2)
	Input.action_release("block")
	var res: String = hero.receive_attack({"dmg": 20.0, "knock": 100.0, "from_x": hero.global_position.x + hero.facing * 100.0, "parry": true, "block": true})
	_check("удар в первые 0.2 с — идеальный блок", res == "parried", res)
	await _wait(0.6)
	_check("после идеального блока перезарядки нет", hero.shield_cd == 0.0, "%.2f" % hero.shield_cd)
	Input.action_press("block")
	await _frames(2)
	_check("и щит сразу поднимается снова", hero.state == hero.S.BLOCK)
	Input.action_release("block")
	hero._to_idle()
	await _frames(2)


func _tap_k() -> void:
	## Настоящее нажатие клавиши K: нажал и отпустил в одном кадре (самый быстрый тап).
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _log_hp(hp: float, _m: float) -> void:
	var who := []
	for e in get_tree().get_nodes_in_group("enemies"):
		who.append("%s(%s f%d windup=%.2f dx=%d)" % [e.kind, e.S.keys()[e.state], e.sprite.frame, e.windup_t, e.global_position.x - hero.global_position.x])
	print("   hp=%d hero=%s block_t=%.2f raise_until=%.2f  %s" % [hp, hero.S.keys()[hero.state], hero.block_t, hero.raise_until, who])


func _real_tap_tests() -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	arena._set_phase(arena.P.CHOOSE)
	_clear_enemies()
	for delay in [0.0, 0.15, 0.3]:
		_reset()
		hero.hp = hero.max_hp
		hero.facing = 1
		await _wait(0.3)
		var e: Node = await _spawn_attacker("balbal", 220.0)
		await _wait(delay)
		_tap_k()
		await _wait(1.0)
		var dmg: float = hero.max_hp - hero.hp
		_check("быстрый тап K через %.2f с после «!» — удар не прошёл целиком" % delay, dmg <= 6.5, "урон %.0f из 24" % dmg)
		_check("  после принятого удара щит без перезарядки", hero.shield_cd == 0.0, "%.2f" % hero.shield_cd)
		e.queue_free()
		await _wait(0.8)
	# долбёжка K: щит стоит, не уходит в перезарядку посреди атаки
	_reset()
	hero.hp = hero.max_hp
	await _wait(0.3)
	var e2: Node = await _spawn_attacker("balbal", 220.0)
	for i in 6:
		_tap_k()
		await _wait(0.12)
	await _wait(0.6)
	_check("долбёжка K — удар заблокирован", hero.max_hp - hero.hp <= 6.5, "урон %.0f" % (hero.max_hp - hero.hp))
	e2.queue_free()
	await _wait(0.8)
	# нажатие чуть раньше конца перезарядки — щит встанет, как только сможет
	hero._to_idle()
	hero.shield_cd = 0.1
	await _frames(1)
	_tap_k()
	await _wait(0.2)
	_check("тап за 0.1 с до конца перезарядки срабатывает", hero.state == hero.S.BLOCK, hero.S.keys()[hero.state])
	hero._to_idle()


func _double_strike_test() -> void:
	_reset()
	_clear_enemies()
	hero.hp = hero.max_hp
	hero.facing = 1
	await _wait(0.3)
	var e: Node = await _spawn_attacker("balbal", 220.0)
	e.combo_left = 1   # гарантированный второй удар
	_tap_k()
	var tapped_second := false
	var t := 0.0
	while t < 2.0:
		await _frames(1)
		t += get_physics_process_delta_time()
		if not tapped_second and e.state == e.S.ATTACK and e.alert.visible and t > 0.6:
			tapped_second = true
			_tap_k()
	_check("двойной удар балбала: два тапа — оба в щит", hero.max_hp - hero.hp <= 12.5, "урон %.0f из 48, второй тап %s" % [hero.max_hp - hero.hp, tapped_second])
	e.queue_free()
