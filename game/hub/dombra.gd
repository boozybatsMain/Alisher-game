class_name DombraModel
extends Node3D
## Процедурная 3D-домбра с руками. Локальные оси: гриф вдоль +X, дека смотрит в +Z, струны разнесены по Y
## (верхняя струна y > 0, нижняя y < 0). Корпус-«груша» в начале координат.
##
## API:
##   set_fret(n: int)                 — левая рука плавно переезжает к ладу n (0 — открытые струны, пальцы подняты)
##   stroke_anim(kind: String)        — правая рука: "down" (қағыс вниз), "up" (подцеп вверх), "trem" (короткий взмах тремоло)
##   pluck(string_id: int, strength)  — струна вибрирует (0 — верхняя, 1 — нижняя)
##   set_tremolo(on: bool)            — непрерывное дрожание правой руки
##   show_hands(on: bool)
##   set_glow(color: Color, energy)   — свечение розетки и струн (кюй сыгран)
##   fret_x(n) -> float               — координата лада по грифу (лок.)
##   pose_rest(), pose_play()         — положения: лежит у костра / в руках (задаются хабом через rest_xform/play_xform)
##   current_fret: int

const SEMITONES := [0, 2, 3, 5, 7, 9, 10]
const NUT_X := 1.03
const BRIDGE_X := -0.12
const SCALE_LEN := 1.15
const STRING_Y := [0.012, -0.012]      ## верхняя, нижняя
const FRONT_Z := 0.105

var current_fret := 0
var rest_xform := Transform3D.IDENTITY
var play_xform := Transform3D.IDENTITY

var _strings: Array[MeshInstance3D] = []
var _amp := [0.0, 0.0]
var _string_mat: StandardMaterial3D
var _rosette_mat: StandardMaterial3D
var _lhand: Node3D
var _lfingers: Array[Node3D] = []
var _rhand: Node3D
var _rfinger: Node3D
var _hands: Node3D
var _lhand_x := NUT_X - 0.05
var _press := 0.0
var _r_phase := 0.0          ## положение правой руки по Y: +1 — над верхней струной, -1 — под нижней
var _r_target := 1.0
var _trem := false
var _trem_t := 0.0
var _t := 0.0
var _glow := 0.0


func _ready() -> void:
	_build()
	show_hands(false)


func fret_x(n: int) -> float:
	var s: int = SEMITONES[clampi(n, 0, 6)]
	return NUT_X - SCALE_LEN * (1.0 - pow(2.0, -s / 12.0))


func _build() -> void:
	var wood := HubProps.mat(Color(0.55, 0.3, 0.14), 0.45)
	var wood_dark := HubProps.mat(Color(0.3, 0.15, 0.07), 0.5)
	var deck := HubProps.mat(Color(0.78, 0.55, 0.3), 0.55)
	# корпус-груша: две сплюснутые сферы + дека
	HubProps.sphere(self, 0.2, Vector3(0, 0, 0), wood, Vector3(1.4, 1.0, 0.5), 24)
	HubProps.sphere(self, 0.13, Vector3(0.24, 0, 0.0), wood, Vector3(1.3, 1.0, 0.55), 20)
	var deck_mi := HubProps.cyl(self, 0.19, 0.19, 0.012, Vector3(0.0, 0, 0.088), deck, Vector3(90, 0, 0), 28)
	deck_mi.scale = Vector3(1.38, 1.0, 1.0)
	var deck2 := HubProps.cyl(self, 0.12, 0.12, 0.012, Vector3(0.23, 0, 0.07), deck, Vector3(90, 0, 0), 20)
	deck2.scale = Vector3(1.25, 1.0, 1.0)
	# орнамент-розетка (светится, когда кюй сыгран)
	_rosette_mat = HubProps.mat(Color(0.25, 0.12, 0.05), 0.5).duplicate()
	_rosette_mat.emission_enabled = true
	_rosette_mat.emission = Color(0.3, 0.9, 0.85)
	_rosette_mat.emission_energy_multiplier = 0.0
	for i in 8:
		var a := i * TAU / 8.0
		HubProps.sphere(self, 0.012, Vector3(0.06 + cos(a) * 0.05, sin(a) * 0.05, 0.097), _rosette_mat, Vector3.ONE, 8)
	HubProps.torus(self, 0.035, 0.042, Vector3(0.06, 0, 0.096), _rosette_mat, Vector3(90, 0, 0))
	# подставка-кобылка и нижний порожек
	HubProps.box(self, Vector3(0.012, 0.06, 0.02), Vector3(BRIDGE_X, 0, 0.105), wood_dark)
	HubProps.box(self, Vector3(0.03, 0.05, 0.03), Vector3(-0.27, 0, 0.06), wood_dark)
	# гриф
	HubProps.box(self, Vector3(NUT_X - 0.3 + 0.02, 0.052, 0.035), Vector3((NUT_X + 0.3) * 0.5, 0, 0.07), wood)
	HubProps.box(self, Vector3(NUT_X - 0.3, 0.054, 0.006), Vector3((NUT_X + 0.3) * 0.5, 0, 0.089), wood_dark)
	# лады-перевязки (жильные кольца вокруг грифа)
	var tie := HubProps.mat(Color(0.85, 0.78, 0.6), 0.6)
	for n in range(1, 7):
		var x := fret_x(n)
		var ring := HubProps.torus(self, 0.03, 0.036, Vector3(x, 0, 0.07), tie, Vector3(0, 0, 90))
		ring.scale = Vector3(1.0, 1.0, 0.75)
	# верхний порожек и голова с колками
	HubProps.box(self, Vector3(0.012, 0.056, 0.012), Vector3(NUT_X, 0, 0.094), tie)
	HubProps.box(self, Vector3(0.17, 0.058, 0.03), Vector3(NUT_X + 0.09, 0, 0.062), wood_dark, Vector3(0, 0, 0))
	for i in 2:
		var px := NUT_X + 0.06 + i * 0.07
		HubProps.cyl(self, 0.008, 0.008, 0.13, Vector3(px, 0, 0.062), wood_dark, Vector3(90, 0, 0))
		HubProps.sphere(self, 0.018, Vector3(px, 0, -0.005), wood_dark, Vector3(1.6, 1.0, 0.6), 8)
		HubProps.sphere(self, 0.018, Vector3(px, 0, 0.13), wood_dark, Vector3(1.6, 1.0, 0.6), 8)
	# струны
	_string_mat = HubProps.mat(Color(0.95, 0.9, 0.8), 0.3, 0.2).duplicate()
	_string_mat.emission_enabled = true
	_string_mat.emission = Color(0.3, 0.9, 0.85)
	_string_mat.emission_energy_multiplier = 0.0
	var a := Vector3(BRIDGE_X, 0, 0.118)
	var b := Vector3(NUT_X, 0, 0.098)
	for i in 2:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0022
		cm.bottom_radius = 0.0022
		cm.height = a.distance_to(b)
		cm.radial_segments = 6
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _string_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var mid := (a + b) * 0.5 + Vector3(0, STRING_Y[i], 0)
		mi.position = mid
		var dir := (b - a).normalized()
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
		mi.set_meta("base", mid)
		_strings.append(mi)
	_build_hands()


func _build_hands() -> void:
	var skin := HubProps.mat(Color(0.82, 0.6, 0.45), 0.7)
	var sleeve := HubProps.mat(Color(0.2, 0.32, 0.45), 0.9)
	_hands = Node3D.new()
	add_child(_hands)
	# левая рука: ладонь за грифом, пальцы обхватывают гриф спереди
	_lhand = Node3D.new()
	_lhand.position = Vector3(_lhand_x, 0, 0.07)
	_hands.add_child(_lhand)
	HubProps.capsule(_lhand, 0.03, 0.11, Vector3(0.0, -0.065, -0.035), skin, Vector3(0, 0, 0))
	HubProps.capsule(_lhand, 0.04, 0.3, Vector3(0.03, -0.14, -0.2), sleeve, Vector3(55, 0, -10))
	# большой палец — сверху грифа
	HubProps.capsule(_lhand, 0.011, 0.06, Vector3(0.0, 0.035, -0.01), skin, Vector3(0, 0, 0))
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.024 * i, -0.04, 0.0)
		_lhand.add_child(f)
		# палец: от низа грифа через деку к струнам (кривая из двух фаланг)
		HubProps.capsule(f, 0.0095, 0.05, Vector3(0, 0.0, 0.035), skin, Vector3(90, 0, 0))
		HubProps.capsule(f, 0.0085, 0.045, Vector3(0, 0.025, 0.06), skin, Vector3(0, 0, 0))
		_lfingers.append(f)
	# правая рука над корпусом у основания грифа: щиплющий указательный палец
	_rhand = Node3D.new()
	_rhand.position = Vector3(0.2, 0.0, 0.17)
	_hands.add_child(_rhand)
	HubProps.sphere(_rhand, 0.045, Vector3(-0.03, 0.0, 0.02), skin, Vector3(1.3, 1.0, 0.7), 12)
	HubProps.capsule(_rhand, 0.045, 0.34, Vector3(-0.17, -0.07, -0.13), sleeve, Vector3(0, -40, 70))
	_rfinger = Node3D.new()
	_rhand.add_child(_rfinger)
	HubProps.capsule(_rfinger, 0.01, 0.07, Vector3(0.0, 0.0, -0.035), skin, Vector3(90, 0, 0))
	for i in 3:
		HubProps.capsule(_rhand, 0.009, 0.045, Vector3(-0.02 - i * 0.002, -0.02 - i * 0.018, -0.005), skin, Vector3(70, 0, 0))


func show_hands(on: bool) -> void:
	if _hands:
		_hands.visible = on


func set_fret(n: int) -> void:
	current_fret = clampi(n, 0, 6)


func stroke_anim(kind: String) -> void:
	match kind:
		"down":
			_r_phase = 1.0
			_r_target = -1.0
		"up":
			_r_phase = -1.0
			_r_target = 1.0
		"trem":
			_r_target = -_r_target if absf(_r_target) > 0.5 else -1.0


func set_tremolo(on: bool) -> void:
	_trem = on


func pluck(string_id: int, strength := 1.0) -> void:
	if string_id >= 0 and string_id < 2:
		_amp[string_id] = clampf(_amp[string_id] + strength, 0.0, 1.5)


func set_glow(color: Color, energy := 2.5) -> void:
	_rosette_mat.emission = color
	_string_mat.emission = color
	_glow = energy


func _process(delta: float) -> void:
	_t += delta
	# левая рука к ладу
	var target_x := (fret_x(current_fret) + 0.022) if current_fret > 0 else NUT_X - 0.07
	_lhand_x = lerpf(_lhand_x, target_x, 1.0 - exp(-delta * 16.0))
	_press = lerpf(_press, 1.0 if current_fret > 0 else 0.0, 1.0 - exp(-delta * 20.0))
	if _lhand:
		_lhand.position.x = _lhand_x
		for i in _lfingers.size():
			var f := _lfingers[i]
			var lifted := 0.022 * (1.0 - _press) if i == 0 else 0.018 + 0.006 * i
			f.position.z = lifted
			f.rotation.x = -0.25 * (1.0 - _press) if i == 0 else -0.3
	# правая рука: удар/подцеп/тремоло
	if _trem:
		_trem_t += delta
		_r_target = sin(_trem_t * TAU * 7.0)
	_r_phase = lerpf(_r_phase, _r_target, 1.0 - exp(-delta * 28.0))
	if _rfinger:
		_rfinger.position = Vector3(0, _r_phase * 0.045, 0)
		_rfinger.rotation.x = _r_phase * 0.35
		_rhand.position.z = 0.17 + absf(_r_phase) * 0.008
	# вибрация струн
	for i in _strings.size():
		var s := _strings[i]
		var a: float = _amp[i]
		_amp[i] = a * exp(-delta * 2.6)
		var base: Vector3 = s.get_meta("base")
		s.position = base + Vector3(0, sin(_t * 113.0 + i) * a * 0.0035, cos(_t * 97.0 + i) * a * 0.002)
		var thick := 1.0 + a * 2.2
		s.scale = Vector3(thick, 1.0, thick)
	# свечение
	if _glow > 0.0:
		var e := _glow * (0.75 + 0.25 * sin(_t * 3.0))
		_rosette_mat.emission_energy_multiplier = e
		_string_mat.emission_energy_multiplier = e * 0.5 + (_amp[0] + _amp[1]) * 0.6
	else:
		_string_mat.emission_energy_multiplier = (_amp[0] + _amp[1]) * 0.5
