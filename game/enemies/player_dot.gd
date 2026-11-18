extends Node
## Яд/скверна на герое (враги стихии Ерлика). Вешается дочерним узлом героя, тикает урон.
## Не убивает — оставляет минимум 1 HP (смерть только от прямых ударов). Повторное наложение продлевает.

var dps := 3.0
var time := 3.0
var _tick := 0.0


static func apply(player: Node, p_dps: float, p_time: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var cur := player.get_node_or_null("EnemyPoison")
	if cur:
		cur.set("dps", maxf(float(cur.get("dps")), p_dps))
		cur.set("time", maxf(float(cur.get("time")), p_time))
		return
	var n: Node = load("res://game/enemies/player_dot.gd").new()
	n.name = "EnemyPoison"
	n.set("dps", p_dps)
	n.set("time", p_time)
	player.add_child(n)


func _physics_process(delta: float) -> void:
	time -= delta
	_tick += delta
	if _tick >= 0.5:
		_tick -= 0.5
		var p := get_parent()
		if p and not (p.has_method("is_dead") and p.is_dead()) and Run.hp > 1.0:
			var amount := minf(dps * 0.5, Run.hp - 1.0)
			Run.set_hp(Run.hp - amount)
			Bus.player_damaged.emit(amount, null)
			if p is Node3D:
				Bus.damage_number.emit((p as Node3D).global_position + Vector3(0, 2.0, 0), amount, "dot")
				var spr = p.get("sprite")
				if spr is SpriteBase3D:
					Fx3D.flash_sprite(spr, Color(0.8, 0.4, 1.6), 0.15)
	if time <= 0.0:
		queue_free()
