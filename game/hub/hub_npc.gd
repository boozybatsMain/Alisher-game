class_name HubNpc
extends Interactable
## NPC Стойбища: фигура из мешей + Label3D имени. activate → Bus.dialogue_requested(Story.talk(npc_id)).
## npc_id: "aje" (Әже-сказительница у костра), "root" (Дух-Корень Байтерека), "usta" (кузнец у оружейной).

@export var npc_id := "aje"
var _body: Node3D
var _t := 0.0
var _orb: MeshInstance3D


func _ready() -> void:
	radius = 1.5
	prompt = "Поговорить"
	super._ready()
	_body = Node3D.new()
	add_child(_body)
	match npc_id:
		"aje": _build_aje()
		"root": _build_root()
		"usta": _build_usta()
	var info: Dictionary = Story.NPCS.get(npc_id, {"name": npc_id, "color": Color.WHITE})
	var h := 2.0 if npc_id != "root" else 3.0
	HubProps.label(self, str(info["name"]), Vector3(0, h + 0.3, 0), info["color"], 36)


func _build_aje() -> void:
	# сидит на войлочной подушке: халат-конус, белый кимешек, бордовый камзол
	HubProps.cyl(_body, 0.45, 0.5, 0.18, Vector3(0, 0.09, 0), HubProps.FELT_RED)
	HubProps.cyl(_body, 0.18, 0.42, 0.7, Vector3(0, 0.5, 0), Color(0.32, 0.12, 0.16))
	HubProps.cyl(_body, 0.2, 0.25, 0.25, Vector3(0, 0.95, 0), Color(0.5, 0.2, 0.22))
	HubProps.sphere(_body, 0.15, Vector3(0, 1.22, 0.02), Color(0.78, 0.58, 0.44))
	# плечи и руки, сложенные на коленях
	HubProps.sphere(_body, 0.24, Vector3(0, 1.0, 0), Color(0.5, 0.2, 0.22), Vector3(1.25, 0.6, 0.9))
	for s in [-1.0, 1.0]:
		HubProps.capsule(_body, 0.07, 0.42, Vector3(0.24 * s, 0.82, 0.1), Color(0.5, 0.2, 0.22), Vector3(-35, 0, 20 * s))
		HubProps.sphere(_body, 0.055, Vector3(0.12 * s, 0.66, 0.28), Color(0.78, 0.58, 0.44))
	# кимешек: белый платок, обрамляющий лицо, и тюрбан
	HubProps.cyl(_body, 0.2, 0.22, 0.32, Vector3(0, 1.18, -0.03), HubProps.FELT_WHITE)
	HubProps.sphere(_body, 0.2, Vector3(0, 1.36, -0.02), HubProps.FELT_WHITE, Vector3(1, 0.65, 1))
	HubProps.torus(_body, 0.16, 0.2, Vector3(0, 1.22, 0.0), HubProps.GOLD, Vector3(80, 0, 0))
	# посох-асатаяқ с бубенцами
	HubProps.cyl(_body, 0.025, 0.03, 1.6, Vector3(0.42, 0.8, 0.1), HubProps.WOOD, Vector3(0, 0, -8))
	HubProps.sphere(_body, 0.06, Vector3(0.53, 1.62, 0.1), HubProps.GOLD)
	HubProps.solid_cyl(self, 0.45, 1.4, Vector3(0, 0.7, 0))


func _build_root() -> void:
	# Дух-Корень: сплетение светящихся корней и сфера-«сердце» с ликом
	var glow := HubProps.glow_mat(Color(0.35, 0.95, 0.85), 1.6)
	var bark := HubProps.mat(Color(0.22, 0.16, 0.12), 0.95)
	for i in 5:
		var a := i * TAU / 5.0
		var root := HubProps.cyl(_body, 0.05, 0.14, 2.6, Vector3(cos(a) * 0.35, 1.2, sin(a) * 0.35), bark, Vector3(sin(a) * 12, 0, cos(a) * 12))
		root.rotation.y = a
		HubProps.cyl(_body, 0.015, 0.03, 2.3, Vector3(cos(a) * 0.39, 1.25, sin(a) * 0.39), glow, Vector3(sin(a) * 12, 0, cos(a) * 12))
	_orb = HubProps.sphere(_body, 0.32, Vector3(0, 2.1, 0), glow, Vector3.ONE, 20)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in [-1.0, 1.0]:
		HubProps.sphere(_body, 0.05, Vector3(0.11 * s, 2.15, 0.28), HubProps.mat(Color(0.05, 0.1, 0.1)), Vector3.ONE, 8)
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 0.95, 0.85)
	l.light_energy = 1.6
	l.omni_range = 5.0
	l.position = Vector3(0, 2.1, 0.5)
	add_child(l)
	var motes := CPUParticles3D.new()
	motes.amount = 24
	motes.lifetime = 3.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.9
	motes.gravity = Vector3(0, 0.25, 0)
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.2
	motes.scale_amount_min = 0.03
	motes.scale_amount_max = 0.06
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = glow
	motes.mesh = sm
	motes.position = Vector3(0, 1.6, 0)
	add_child(motes)
	HubProps.solid_cyl(self, 0.5, 2.5, Vector3(0, 1.25, 0))


func _build_usta() -> void:
	# кузнец: кожаный фартук, тюбетейка, молот на плече; рядом наковальня
	HubProps.cyl(_body, 0.24, 0.3, 0.9, Vector3(0, 0.45, 0), Color(0.25, 0.22, 0.28))
	HubProps.cyl(_body, 0.3, 0.26, 0.6, Vector3(0, 1.15, 0), Color(0.52, 0.32, 0.2))
	HubProps.box(_body, Vector3(0.4, 0.9, 0.04), Vector3(0, 0.75, 0.27), HubProps.mat(Color(0.35, 0.22, 0.13)))
	HubProps.sphere(_body, 0.16, Vector3(0, 1.6, 0), Color(0.7, 0.5, 0.36))
	HubProps.cyl(_body, 0.15, 0.17, 0.1, Vector3(0, 1.75, 0), HubProps.FELT_RED)
	HubProps.box(_body, Vector3(0.25, 0.12, 0.05), Vector3(0, 1.5, 0.14), Color(0.15, 0.1, 0.08))
	HubProps.cyl(_body, 0.025, 0.025, 0.7, Vector3(0.3, 1.45, 0), HubProps.WOOD, Vector3(0, 0, -35))
	HubProps.box(_body, Vector3(0.12, 0.18, 0.2), Vector3(0.5, 1.75, 0), HubProps.IRON, Vector3(0, 0, -35))
	# наковальня
	var iron := HubProps.mat(Color(0.25, 0.25, 0.28), 0.4, 0.7)
	HubProps.cyl(self, 0.22, 0.28, 0.5, Vector3(0.9, 0.25, 0.3), HubProps.WOOD_DARK)
	HubProps.box(self, Vector3(0.6, 0.18, 0.26), Vector3(0.9, 0.59, 0.3), iron)
	HubProps.prism(self, Vector3(0.25, 0.18, 0.2), Vector3(1.28, 0.59, 0.3), iron, Vector3(0, 0, -90))
	HubProps.solid_cyl(self, 0.4, 1.8, Vector3(0, 0.9, 0))


func activate(player: Node) -> void:
	if not can_activate(player):
		return
	activated.emit(player)
	var lines := Story.talk(npc_id)
	if not lines.is_empty():
		Bus.dialogue_requested.emit(lines)


func _process(delta: float) -> void:
	_t += delta
	if _body:
		if npc_id == "root":
			_body.position.y = sin(_t * 1.3) * 0.06
			if _orb:
				var s := 1.0 + sin(_t * 2.1) * 0.05
				_orb.scale = Vector3(s, s, s)
		else:
			_body.scale.y = 1.0 + sin(_t * 1.8) * 0.01
		# поворачиваться к герою
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p and npc_id != "root":
			var d := p.global_position - global_position
			if Vector2(d.x, d.z).length() < 6.0:
				var target := atan2(d.x, d.z)
				_body.rotation.y = lerp_angle(_body.rotation.y, target, 1.0 - exp(-delta * 3.0))
