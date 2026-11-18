class_name Hit
extends RefCounted
## Единый объект удара. Создаётся атакующим, проходит через модификаторы Даров (Run.modify_outgoing),
## затем передаётся цели через take_hit(hit). Цель сама вычитает броню/здоровье и шлёт Bus.hit_landed.

var amount := 10.0
var source: Node = null            ## кто бьёт (герой, враг, снаряд-владелец)
var kind := "normal"               ## normal / special / dash / fall / wall / dot / boon / thorns
var is_crit := false
var element := ""                  ## tengri / ai_mergen / umai / zher_su / erlik / kokbori / ""
var knockback := Vector3.ZERO      ## импульс отбрасывания, м/с (Y — подброс)
var stun := 0.0                    ## оглушение, сек
var armor_damage := 0.0            ## урон по броне элиток (по умолчанию = amount * armor_mult)
var armor_mult := 1.0              ## тяжёлые атаки 2.0+, лёгкие 0.5
var heavy := false                 ## тяжёлая атака прерывает элиток с бронёй
var launch := false                ## подбросить в воздух (апперкот)
var pierce_armor := false          ## игнорирует броню (Ай-Мерген)
var from_behind := false           ## выставляется целью (удар в спину) — для «Тени Степи»
var position := Vector3.ZERO       ## точка удара (для эффектов)
var direction := Vector3.FORWARD   ## направление удара (XZ)
var statuses: Array = []           ## [{"id": "burn", "dps": 5, "time": 3}, ...] — см. ARCHITECTURE.md
var tags: Array = []               ## произвольные метки: "weapon:sword", "combo3", "projectile", "wall_slam"...
var no_boons := false              ## не прогонять через Дары (чтобы цепные молнии не порождали молнии бесконечно)


static func make(p_amount: float, p_source: Node, p_kind := "normal") -> Hit:
	var h := Hit.new()
	h.amount = p_amount
	h.source = p_source
	h.kind = p_kind
	return h


func duplicate_hit() -> Hit:
	var h := Hit.new()
	for p in ["amount", "source", "kind", "is_crit", "element", "knockback", "stun", "armor_damage",
			"armor_mult", "heavy", "launch", "pierce_armor", "position", "direction", "no_boons"]:
		h.set(p, get(p))
	h.statuses = statuses.duplicate(true)
	h.tags = tags.duplicate()
	return h
