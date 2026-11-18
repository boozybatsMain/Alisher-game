class_name Interactable
extends Area3D
## Интерактивный объект: герой подходит, видит подсказку, жмёт interact → activate(player).
## Используется в Хабе (стойки, Сандык, домбра, выход) и в комнатах (двери, тотемы, торговец, колодец, сундук-печать).

signal activated(player: Node)

@export var prompt := "Взаимодействовать"
@export var radius := 1.6
var enabled := true


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = Combat.LAYER_INTERACT
	collision_mask = 0
	monitoring = false
	if get_child_count() == 0 or not _has_shape():
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		cs.shape = sh
		add_child(cs)


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false


func can_activate(_player: Node) -> bool:
	return enabled


func activate(player: Node) -> void:
	if can_activate(player):
		activated.emit(player)
