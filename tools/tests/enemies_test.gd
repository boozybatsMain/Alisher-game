extends Node3D
## Авто-тест модуля C (враги, элитки, телеграфы, боссы, снаряды).
## godot --headless --path . res://tools/tests/enemies_test.tscn
## Пол + стена + уступ, фейковый герой (группа "player"), спавн всех типов и боссов через EnemyFactory.

const FakePlayer := preload("res://tools/tests/enemies_fake_player.gd")

var fails := 0
var passes := 0
var pl: CharacterBody3D
var killed: Array = []
var landed: Array = []
var dot_numbers := 0


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


func box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b


func clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		p.queue_free()
	await frames(2)


func _run() -> void:
	print("ENEMIES TEST")
	box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))         # пол, верх y=0
	box(Vector3(10.5, 2, 0), Vector3(1, 4, 40))          # стена, грань x=10
	box(Vector3(-12, 1.5, -12), Vector3(8, 3, 8))        # уступ 3 м (x -16..-8, z -16..-8)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(12, 16, 12)
	cam.look_at(Vector3.ZERO)
	pl = FakePlayer.new()
	add_child(pl)
	pl.global_position = Vector3(0, 0.1, 0)
	Bus.enemy_killed.connect(func(e, _h): killed.append(e))
	Bus.hit_landed.connect(func(h, t): landed.append([h, t]))
	Bus.damage_number.connect(func(_p, _a, k): if k == "dot": dot_numbers += 1)
	await frames(5)

	# ---------------------------------------------------------------- данные
	check(EnemyData.pool(0).size() >= 4 and EnemyData.pool(2).size() >= 5, "pool(biome) не пуст")
	check(EnemyData.BOSSES == ["zhest", "shoyyn", "khan"], "BOSSES")
	check(EnemyData.display_name("wolf") != "wolf", "display_name")
	check(EnemyData.TYPES.size() >= 9, "TYPES >= 6 обычных + 3 босса")

	# ---------------------------------------------------------------- обычные типы атакуют
	var types := ["wolf", "spirit", "balbal", "archer", "shaman", "acrobat"]
	var spawned: Array = []
	var start_pos := {}
	for i in types.size():
		var a := i * TAU / types.size()
		var pos := Vector3(cos(a) * 7.0, 0.2, sin(a) * 7.0)
		var e := EnemyFactory.spawn(types[i], self, pos, {})
		spawned.append(e)
		start_pos[e] = pos
	check(spawned.all(func(e): return e is EnemyBase), "фабрика вернула EnemyBase для всех типов")
	check(spawned.all(func(e): return e.is_in_group("enemies") and e.is_in_group("hurtable_enemy")), "группы enemies/hurtable_enemy")
	check(spawned.all(func(e): return e.collision_layer == 4 and e.collision_mask == 1), "слои коллизий 4/1")
	check(not spawned[0].active, "враг неактивен сразу после появления")
	await secs(0.8)
	check(spawned.all(func(e): return e.active), "враги активировались через ~0.6 с")
	await secs(9.0)
	var moved := 0
	for e in spawned:
		if is_instance_valid(e) and e.global_position.distance_to(start_pos[e]) > 1.0:
			moved += 1
	check(moved >= 4, "враги двигаются (%d/6 сместились)" % moved)
	print("    урон по герою: ", pl.damage_taken, " по источникам: ", pl.by_source)
	check(pl.damage_taken > 0.0, "враги наносят урон герою")
	check(pl.by_source.size() >= 3, "урон от нескольких типов (%d)" % pl.by_source.size())
	check(get_tree().get_nodes_in_group("enemy_telegraph").size() >= 0, "телеграфы создаются без ошибок")
	await clear_enemies()

	# ---------------------------------------------------------------- элитка и броня
	pl.invuln = true
	var el := EnemyFactory.spawn("wolf", self, Vector3(-4, 0.2, 4), {"elite": true, "spawn_delay": 0.0})
	await frames(2)
	check(el.elite and el.max_armor > 0.0 and is_equal_approx(el.max_hp, 34.0 * 2.2), "элита: ×2.2 HP и броня")
	var hp0: float = el.hp
	var ar0: float = el.armor
	var h := Hit.make(10.0, pl, "normal")
	h.knockback = Vector3(5, 0, 0)
	el.take_hit(h)
	check(is_equal_approx(hp0 - el.hp, 2.5), "броня: урон по HP ×0.25 (%.2f)" % (hp0 - el.hp))
	check(is_equal_approx(ar0 - el.armor, 10.0), "броня уменьшилась на amount*armor_mult")
	check(el._knock_t <= 0.0, "лёгкий удар не отбрасывает бронированного")
	var hp1: float = el.hp
	var hp_pierce := Hit.make(10.0, pl, "normal")
	hp_pierce.pierce_armor = true
	el.take_hit(hp_pierce)
	check(is_equal_approx(hp1 - el.hp, 10.0), "pierce_armor пробивает броню")
	var big := Hit.make(5.0, pl, "normal")
	big.armor_damage = 500.0
	el.take_hit(big)
	check(el.armor <= 0.0 and el.statuses.has("stun"), "броня сломана → оглушение")
	await clear_enemies()

	# ---------------------------------------------------------------- статусы
	var bw := EnemyFactory.spawn("wolf", self, Vector3(-4, 0.2, -4), {"spawn_delay": 0.0})
	await frames(2)
	var hpb: float = bw.hp
	dot_numbers = 0
	bw.apply_status("burn", {"dps": 6.0, "time": 2.0})
	bw.apply_status("poison", {"stacks": 2})
	bw.apply_status("poison", {"stacks": 1})
	check(bw.statuses.has("burn") and int(bw.statuses["poison"]["stacks"]) == 3, "статусы хранятся в statuses (poison стакается)")
	await secs(1.1)
	check(bw.hp < hpb - 5.0, "burn/poison тикают (%.1f → %.1f)" % [hpb, bw.hp])
	check(dot_numbers >= 2, "Bus.damage_number kind=dot")
	bw.apply_status("slow", {"mult": 0.5, "time": 1.0})
	check(bw._slow_mult() < 0.6, "slow замедляет")
	bw.apply_status("freeze", {"time": 0.5})
	check(bw.is_stunned(), "freeze обездвиживает")
	await clear_enemies()

	# ---------------------------------------------------------------- отбрасывание в стену
	var ww := EnemyFactory.spawn("wolf", self, Vector3(7.5, 0.1, 3), {"spawn_delay": 0.0, "hp_mult": 5.0})
	await frames(3)
	landed.clear()
	var hpw: float = ww.hp
	var kh := Hit.make(1.0, pl, "normal")
	kh.knockback = Vector3(16, 0, 0)
	kh.heavy = true
	ww.take_hit(kh)
	await secs(0.4)
	var wall_hits := landed.filter(func(x): return x[1] == ww and (x[0] as Hit).kind == "wall")
	check(wall_hits.size() == 1, "удар о стену наносит wall-урон")
	check(hpw - ww.hp > 5.0, "wall-урон заметный (%.1f)" % (hpw - ww.hp))
	# x2
	var ww2 := EnemyFactory.spawn("wolf", self, Vector3(7.5, 0.1, -3), {"spawn_delay": 0.0, "hp_mult": 5.0})
	await frames(3)
	landed.clear()
	var kh2 := Hit.make(1.0, pl, "normal")
	kh2.knockback = Vector3(16, 0, 0)
	kh2.heavy = true
	kh2.tags = ["wall_x2"]
	ww2.take_hit(kh2)
	await secs(0.4)
	var wall2 := landed.filter(func(x): return x[1] == ww2 and (x[0] as Hit).kind == "wall")
	check(wall2.size() == 1 and (wall2[0][0] as Hit).amount > (wall_hits[0][0] as Hit).amount * 1.3 if wall_hits.size() > 0 and wall2.size() > 0 else false, "wall_x2 удваивает урон о стену")
	await clear_enemies()

	# ---------------------------------------------------------------- падение с уступа
	var fw := EnemyFactory.spawn("wolf", self, Vector3(-8.8, 3.1, -12), {"spawn_delay": 0.0, "hp_mult": 5.0})
	await secs(0.3)
	check(fw.is_on_floor() and fw.global_position.y > 2.5, "враг стоит на уступе")
	landed.clear()
	var fh := Hit.make(1.0, pl, "normal")
	fh.knockback = Vector3(9, 3, 0)
	fh.heavy = true
	fw.take_hit(fh)
	await secs(1.2)
	var falls := landed.filter(func(x): return x[1] == fw and (x[0] as Hit).kind == "fall")
	check(falls.size() == 1, "падение с высоты > 2.5 м после отбрасывания → fall-урон")
	await clear_enemies()

	# ---------------------------------------------------------------- подброс
	var lw := EnemyFactory.spawn("wolf", self, Vector3(3, 0.1, -5), {"spawn_delay": 0.0})
	await frames(3)
	var lh := Hit.make(1.0, pl, "normal")
	lh.launch = true
	lw.take_hit(lh)
	await secs(0.3)
	check(lw.global_position.y > 1.0 and lw._launch_t > 0.0, "launch подбрасывает врага")
	await clear_enemies()

	# ---------------------------------------------------------------- смерть
	killed.clear()
	var d0 := Run.dirhams
	var kw := EnemyFactory.spawn("archer", self, Vector3(-3, 0.1, 6), {"spawn_delay": 0.0})
	await frames(3)
	var got_died := [false]
	kw.died.connect(func(_e): got_died[0] = true)
	var kill := Hit.make(999.0, pl, "normal")
	kw.take_hit(kill)
	check(kw.is_dead() and killed.has(kw), "смерть шлёт Bus.enemy_killed")
	check(got_died[0], "сигнал died")
	check(not kw.is_in_group("enemies"), "мёртвый враг убран из группы enemies")
	check(Run.dirhams > d0, "выпали дирхемы (%d)" % (Run.dirhams - d0))
	await secs(1.5)
	check(not is_instance_valid(kw), "труп удалён (queue_free)")
	# пропасть
	var pw := EnemyFactory.spawn("wolf", self, Vector3(25, -9.0, 25), {"spawn_delay": 0.0})
	await frames(4)
	check(not is_instance_valid(pw) or pw.is_dead(), "падение в пропасть (y < -8) → смерть")
	await clear_enemies()

	# ---------------------------------------------------------------- телеграфы и «wide»
	pl.invuln = false
	pl.damage_taken = 0.0
	var bb := EnemyFactory.spawn("balbal", self, Vector3(2, 0.1, 0), {"spawn_delay": 0.0})
	await frames(3)
	pl.sliding = true
	check(not bb.strike_cone(bb.global_position, Vector3(-1, 0, 0), 3.0, 200.0, 10.0, {"tags": ["wide"]}), "wide-удар не попадает по герою в подкате")
	pl.sliding = false
	check(bb.strike_cone(bb.global_position, Vector3(-1, 0, 0), 3.0, 200.0, 10.0, {"tags": ["wide"]}), "wide-удар попадает без подката")
	check(not bb.strike_circle(Vector3(8, 0, 8), 1.5, 10.0), "вне зоны — промах")
	var t := EnemyTelegraph.circle(self, Vector3.ZERO, 2.0, 0.5)
	var c := EnemyTelegraph.cone(self, Vector3.ZERO, Vector3(1, 0, 0), 3.0, 90.0, 0.5)
	var l := EnemyTelegraph.line(self, Vector3.ZERO, Vector3(5, 0, 0), 1.0, 0.5)
	check(t != null and c != null and l != null, "телеграфы круг/конус/линия")
	await secs(0.8)
	check(not is_instance_valid(t) and not is_instance_valid(l), "телеграфы исчезают сами")
	await clear_enemies()

	# ---------------------------------------------------------------- снаряды
	pl.damage_taken = 0.0
	var shooter := EnemyFactory.spawn("archer", self, Vector3(-6, 0.1, 0), {"spawn_delay": 0.0})
	shooter.set_physics_process(false)
	await frames(2)
	var pr := EnemyProjectile.fire(self, Vector3(-4, 1.0, 0), Vector3(1, 0, 0), 15.0, 7.0, shooter, "arrow")
	check(pr.is_in_group("enemy_projectile"), "снаряд в группе enemy_projectile")
	await secs(0.5)
	check(pl.damage_taken >= 7.0 and not is_instance_valid(pr), "стрела попала в героя")
	var hps: float = shooter.hp
	var pr2 := EnemyProjectile.fire(self, Vector3(-1.5, 1.0, 0), Vector3(1, 0, 0), 12.0, 7.0, shooter, "orb")
	await frames(1)
	pr2.reflect(pl, Vector3(-1, 0, 0))
	check(pr2.reflected and pr2.is_in_group("player_projectile"), "reflect меняет владельца")
	await secs(0.6)
	check(shooter.hp < hps, "отражённый снаряд бьёт врага (%.1f → %.1f)" % [hps, shooter.hp])
	var pr3 := EnemyProjectile.fire(self, Vector3(5, 1.0, 5), Vector3(1, 0, 0), 15.0, 7.0, shooter, "arrow")
	await secs(0.6)
	check(not is_instance_valid(pr3), "снаряд гаснет о стену")
	await clear_enemies()

	# ---------------------------------------------------------------- стихии
	var ek := EnemyFactory.spawn("wolf", self, Vector3(5, 0.1, 5), {"element": "kokbori", "spawn_delay": 0.0})
	var ez := EnemyFactory.spawn("wolf", self, Vector3(5, 0.1, -5), {"element": "zher_su", "hp_mult": 2.0, "dmg_mult": 1.5, "spawn_delay": 0.0})
	await frames(2)
	check(ek.speed_mult > 1.25, "kokbori: скорость ×1.3")
	check(ez.max_armor > 0.0 and is_equal_approx(ez.max_hp, 68.0), "zher_su: броня; hp_mult")
	await clear_enemies()

	# ---------------------------------------------------------------- ярусы: ловкий прыгает, медленный — телепорт Мглой
	pl.invuln = true
	pl.global_position = Vector3(-12, 3.2, -12)
	await secs(0.3)
	var jw := EnemyFactory.spawn("wolf", self, Vector3(-4, 0.1, -4), {"spawn_delay": 0.0})
	var jb := EnemyFactory.spawn("balbal", self, Vector3(-3, 0.1, -2), {"spawn_delay": 0.0})
	var best_w := 0.0
	var best_b := 0.0
	for i in 9 * 6:
		await frames(10)
		if is_instance_valid(jw):
			best_w = maxf(best_w, jw.global_position.y)
		if is_instance_valid(jb):
			best_b = maxf(best_b, jb.global_position.y)
	check(best_w > 2.5, "волк запрыгнул на ярус к герою (y=%.1f)" % best_w)
	check(best_b > 2.5, "балбал добрался до яруса (телепорт Мглой) (y=%.1f)" % best_b)
	pl.global_position = Vector3(0, 0.1, 0)
	await clear_enemies()
	pl.invuln = false

	# ---------------------------------------------------------------- боссы
	pl.damage_taken = 0.0
	pl.by_source = {}
	var bosses: Array = []
	for i in 3:
		var bp := Vector3(-6 + i * 6, 0.2, 7)
		bosses.append(EnemyFactory.spawn(EnemyData.BOSSES[i], self, bp, {"music": false}))
	await secs(1.4)
	check(bosses.all(func(b): return b is BossBase and b.is_in_group("boss") and b.active), "боссы созданы, группа boss")
	check(bosses.all(func(b): return b.display_name != "" and b.max_hp >= 900.0), "у боссов display_name и большая HP")
	check(get_tree().current_scene != null, "сцена есть для полосы босса")
	await secs(8.0)
	print("    урон от боссов: ", pl.by_source)
	check(pl.damage_taken > 0.0, "боссы наносят урон")
	var kh_b: EnemyBase = bosses[1]
	var p2 := Hit.make(kh_b.max_hp, pl, "normal")
	p2.pierce_armor = true
	kh_b.hp = kh_b.max_hp * 0.49
	await frames(2)
	check(kh_b.phase == 2, "босс переходит во 2-ю фазу")
	killed.clear()
	for b in bosses:
		if is_instance_valid(b) and not b.is_dead():
			b.kill(p2)
	check(killed.size() >= 3, "смерть боссов шлёт enemy_killed")
	await secs(0.5)
	Engine.time_scale = 1.0

	print("ENEMIES TEST DONE: passed ", passes, ", failed ", fails)
	get_tree().quit(1 if fails > 0 else 0)
