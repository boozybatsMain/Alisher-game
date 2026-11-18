class_name BossBase
extends EnemyBase
## Общая основа боссов: группа "boss", большая полоса HP внизу экрана (boss_bar.gd), фазы, броня
## с восстановлением, устойчивость к отбрасыванию/подбросу, музыка босса, замедление при смерти.
##
## Сверх EnemyBase: phase (1/2), phase_threshold (доля HP для 2-й фазы), own_bar (true — полосу рисует босс),
##   signal phase_changed(phase), show_bar(), _enter_phase(n) — переопределяется.

signal phase_changed(phase: int)

var phase := 1
var phase_threshold := 0.5
var own_bar := true
var _bar: CanvasLayer = null
var _phase_lock := 0.0
var minions: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("boss")


func _activate() -> void:
	super._activate()
	show_bar()
	if bool(mods.get("music", true)):
		Sfx.music("boss")
	Sfx.play("boss_roar")
	Bus.shake.emit(0.6, 0.5)


func show_bar() -> void:
	if _bar != null or not own_bar or not is_inside_tree():
		return
	_bar = load("res://game/enemies/boss_bar.gd").new()
	_bar.set("boss", self)
	if get_tree().current_scene:
		get_tree().current_scene.add_child(_bar)
	else:
		get_parent().add_child(_bar)


func _timers(delta: float) -> void:
	super._timers(delta)
	_phase_lock -= delta
	if phase == 1 and hp <= max_hp * phase_threshold and not _dead:
		phase = 2
		interrupt()
		_phase_lock = 1.2
		statuses.erase("stun")
		statuses.erase("freeze")
		phase_changed.emit(phase)
		Sfx.play("boss_roar")
		Bus.shake.emit(0.9, 0.6)
		Fx3D.ring(fx_parent(), global_position, 6.0, Color(0.7, 0.2, 1.0), 0.6, 0.5)
		Fx3D.number(fx_parent(), global_position + Vector3(0, body_height + 0.8, 0), "Ярость!", Color(1.0, 0.4, 0.3), 56)
		_enter_phase(phase)


## Переопределяется: что меняется во 2-й фазе.
func _enter_phase(_n: int) -> void:
	tele_mult = 0.85
	speed_mult *= 1.2
	attack_cd_range *= 0.8


func _ai(delta: float, pl: Node3D) -> void:
	if _phase_lock > 0.0:
		_steer(Vector3.ZERO, delta, 30.0)
		play_anim("idle")
		return
	super._ai(delta, pl)


func alive_minions() -> int:
	minions = minions.filter(func(m): return is_instance_valid(m) and not m.is_dead())
	return minions.size()


func _on_death() -> void:
	Sfx.play("boss_death")
	Bus.shake.emit(1.0, 0.8)
	Run.slowmo(0.25, 1.2)
	Fx3D.flash_light(fx_parent(), global_position + Vector3(0, 2.0, 0), Color(1.0, 0.8, 0.5), 8.0, 10.0, 0.6)
	Fx3D.ring(fx_parent(), global_position, 8.0, Color(1.0, 0.85, 0.5), 0.8, 0.6)
	# подручные рассыпаются вместе с хозяином
	for m in minions:
		if is_instance_valid(m) and not m.is_dead():
			m.kill(null)
