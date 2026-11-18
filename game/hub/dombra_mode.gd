class_name DombraMode
extends Node
## Режим домбры у костра: крупный план 3D-домбры (DombraModel) с руками, радиальное меню 6 ладов, удары
## (ЛКМ/attack — қағыс вниз, ПКМ/special — подцеп вверх, Пробел/СКМ/dombra_tremolo — тремоло),
## пул голосов без обрыва затухания, кюи-ритмы с подсказками (окно ±0.18 с). Выход — Esc / interact.
##
## API:
##   DombraMode.open(parent, model, player) -> DombraMode
##   close()
##   set_fret(n), strike(stroke: "down"|"up"|"trem"), trem_hold(on)
##   begin_kui(id) / stop_kui()     — начать кюй по нотам (Meta.kui_prepared = id при успехе)
##   song_time: float               — время кюя (идёт само в _process; тест может ставить вручную)
##   kui_id, kui_index, kui_active, errors
## Сигналы: kui_done(id), kui_failed(id), closed

signal kui_done(id: String)
signal kui_failed(id: String)
signal closed

const SAMPLE_DIR := "res://assets/sfx/dombra/"
const VOICES := 4                     ## голосов на струну
const STRUM_GAP := 0.018              ## задержка между струнами при қағыс/подцепе
const TREM_RATE := 14.0               ## ударов в секунду в тремоло
const LANE_SPEED := 300.0             ## пикселей в секунду на дорожке нот
const STROKE_COL := {"down": Color(1.0, 0.75, 0.35), "up": Color(0.45, 0.9, 1.0), "trem": Color(0.85, 0.55, 1.0)}

var model: DombraModel
var player: Node
var fret := 0
var song_time := 0.0
var kui_id := ""
var kui_index := 0
var kui_active := false
var errors := 0
var last_judgement := ""

var _streams := {"upper": [], "lower": []}
var _voices := {"upper": [], "lower": []}
var _voice_started := {"upper": [], "lower": []}
var _pending: Array = []              ## [[delay, string, fret, vol]]
var _trem_hold := false
var _trem_burst := 0.0
var _trem_acc := 0.0
var _trem_dir := 1
var _source := "mouse"
var _keys_held: Array = []
var _cam: Camera3D
var _prev_cam: Camera3D
var _closing := false
var _restart_t := -1.0
var _last_beat := -1
var _opened_msec := 0
var _clock := 0.0
var _hidden_layers: Array = []

var _ui: CanvasLayer
var _root: Control
var _radial: Control
var _lane: Control
var _hint: Label
var _status: Label
var _kui_box: VBoxContainer
var _radial_center := Vector2(260, 470)


static func open(parent: Node, p_model: DombraModel, p_player: Node) -> DombraMode:
	var m := DombraMode.new()
	m.name = "DombraMode"
	m.model = p_model
	m.player = p_player
	parent.add_child(m)
	return m


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_opened_msec = Time.get_ticks_msec()
	if player and is_instance_valid(player) and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	_load_samples()
	_build_audio()
	_build_camera()
	_build_ui()
	_hide_hud(true)
	if model:
		model.show_hands(true)
		model.set_fret(0)
		var tw := model.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(model, "transform", model.play_xform, 0.7)
	Sfx.play("dombra", -10.0, 0.0)


# ================================================================ звук
func _load_samples() -> void:
	for s in ["upper", "lower"]:
		var arr: Array = []
		for i in 7:
			var p := SAMPLE_DIR + "%s_%d.wav" % [s, i]
			arr.append(load(p) if ResourceLoader.exists(p) else null)
		_streams[s] = arr


func _build_audio() -> void:
	for s in ["upper", "lower"]:
		for i in VOICES:
			var p := AudioStreamPlayer.new()
			p.bus = "Master"
			add_child(p)
			_voices[s].append(p)
			_voice_started[s].append(-100.0)


## Новый голос без обрыва звучащих: свободный плеер, иначе самый старый (он уже почти затух).
func _voice(s: String) -> AudioStreamPlayer:
	var best := 0
	var best_t := INF
	for i in VOICES:
		var p: AudioStreamPlayer = _voices[s][i]
		if not p.playing:
			best = i
			break
		if _voice_started[s][i] < best_t:
			best_t = _voice_started[s][i]
			best = i
	_voice_started[s][best] = _clock
	return _voices[s][best]


func _play_string(s: String, f: int, vol := 0.0) -> void:
	var st = _streams[s][clampi(f, 0, 6)]
	if model:
		model.pluck(0 if s == "upper" else 1, 0.9 if vol > -3.0 else 0.5)
	if st == null:
		# запасной вариант: общий сэмпл домбры, высота через pitch
		Sfx.play("dombra", vol - 6.0, 0.0)
		return
	var p := _voice(s)
	p.stream = st
	p.volume_db = vol - 2.0
	p.pitch_scale = 1.0
	p.play()


# ================================================================ игра
func set_fret(n: int) -> void:
	n = clampi(n, 0, 6)
	if n == fret:
		return
	fret = n
	if model:
		model.set_fret(n)
	if _radial:
		_radial.queue_redraw()


## Удар по струнам. "down" — қағыс вниз (верхняя → нижняя), "up" — подцеп вверх (нижняя → верхняя), "trem" — тремоло.
func strike(stroke: String) -> void:
	match stroke:
		"down":
			_strum(1, 0.0)
		"up":
			_strum(-1, 0.0)
		"trem":
			_trem_burst = 0.35
			_trem_acc = 0.0
			_strum(1, -2.0)
	if model:
		model.stroke_anim(stroke)
		model.set_tremolo(stroke == "trem" or _trem_hold)
	_judge(stroke)


func trem_hold(on: bool) -> void:
	if on and not _trem_hold:
		_trem_hold = true
		strike("trem")
	elif not on:
		_trem_hold = false


func _strum(dir: int, vol: float) -> void:
	var first := "upper" if dir > 0 else "lower"
	var second := "lower" if dir > 0 else "upper"
	_play_string(first, fret, vol)
	_pending.append([STRUM_GAP, second, fret, vol - 1.0])


# ================================================================ кюи
func begin_kui(id: String) -> void:
	if not KuiData.has(id):
		return
	kui_id = id
	kui_index = 0
	kui_active = true
	song_time = 0.0
	errors = 0
	_last_beat = -1
	_restart_t = -1.0
	last_judgement = ""
	_set_status("Кюй «%s»: слушай отсчёт…" % KuiData.title(id), Color(1, 0.9, 0.6))
	if _lane:
		_lane.visible = true


func stop_kui() -> void:
	kui_active = false
	kui_id = ""
	_restart_t = -1.0
	if _lane:
		_lane.visible = false
	_set_status("Свободная игра", Color(0.9, 0.85, 0.75))


func _judge(stroke: String) -> void:
	if not kui_active or _restart_t >= 0.0:
		return
	var ns := KuiData.notes(kui_id)
	if kui_index >= ns.size():
		return
	var n: Dictionary = ns[kui_index]
	var t := KuiData.note_time(kui_id, kui_index)
	var dt := song_time - t
	if absf(dt) <= KuiData.WINDOW and int(n["fret"]) == fret and str(n["stroke"]) == stroke:
		kui_index += 1
		last_judgement = "hit"
		_set_status("Верно!  %d / %d" % [kui_index, ns.size()], Color(0.5, 1.0, 0.6))
		if kui_index >= ns.size():
			_kui_success()
		return
	var why := "рано" if dt < -KuiData.WINDOW else ("поздно" if dt > KuiData.WINDOW else ("не тот лад" if int(n["fret"]) != fret else "не тот удар"))
	_kui_error(why)


func _kui_error(why: String) -> void:
	errors += 1
	last_judgement = "miss"
	_set_status("Ошибка (%s) — начнём заново" % why, Color(1, 0.45, 0.35))
	Sfx.play("ui_hover", -2.0, 0.0)
	kui_failed.emit(kui_id)
	_restart_t = 1.3


func _kui_success() -> void:
	var id := kui_id
	kui_active = false
	Meta.kui_prepared = id
	Meta.save_game()
	var title := KuiData.title(id)
	Bus.toast.emit("Оружие резонирует: Музыкальный заряд «%s»" % title, Color(0.4, 0.95, 0.85))
	_set_status("Кюй «%s» сыгран чисто! Заряд ждёт тебя на тропе." % title, Color(0.4, 0.95, 0.85))
	Sfx.play("gift_take", -2.0, 0.0)
	if model:
		model.set_glow(Color(0.35, 0.95, 0.85), 2.8)
	if _lane:
		_lane.visible = false
	_refresh_kui_box()
	kui_done.emit(id)


# ================================================================ кадр
func _process(delta: float) -> void:
	_clock += delta
	# отложенные вторые струны
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var e: Array = _pending[i]
			_pending.remove_at(i)
			_play_string(e[1], e[2], e[3])
	# тремоло: чередование ударов вниз/вверх
	if _trem_hold or _trem_burst > 0.0:
		_trem_burst -= delta
		_trem_acc += delta
		if _trem_acc >= 1.0 / TREM_RATE:
			_trem_acc -= 1.0 / TREM_RATE
			_trem_dir = -_trem_dir
			_strum(_trem_dir, -5.0)
			if model:
				model.stroke_anim("trem")
	elif model and model._trem:
		model.set_tremolo(false)
	# кюй
	if kui_active:
		if _restart_t >= 0.0:
			_restart_t -= delta
			if _restart_t < 0.0:
				begin_kui(kui_id)
		else:
			song_time += delta
			var bl := KuiData.beat_len(kui_id)
			var beat := int(floor(song_time / bl))
			if beat != _last_beat and song_time < KuiData.length(kui_id):
				_last_beat = beat
				Sfx.play("ui_click", -10.0 if beat % 4 != 0 else -5.0, 0.0)
				if beat < KuiData.COUNT_IN:
					_set_status("Отсчёт: %d" % (KuiData.COUNT_IN - beat), Color(1, 0.9, 0.6))
			var ns := KuiData.notes(kui_id)
			if kui_index < ns.size() and song_time > KuiData.note_time(kui_id, kui_index) + KuiData.WINDOW:
				_kui_error("пропущена нота")
	if _lane and _lane.visible:
		_lane.queue_redraw()
	if _hint:
		_update_hint()


# ================================================================ ввод
func _input(event: InputEvent) -> void:
	if _closing or Time.get_ticks_msec() - _opened_msec < 300:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if _closing or Time.get_ticks_msec() - _opened_msec < 300:
		return
	for i in 6:
		var act := "fret_%d" % (i + 1)
		if InputMap.has_action(act):
			if event.is_action_pressed(act):
				_source = "keys"
				if not (i + 1) in _keys_held:
					_keys_held.append(i + 1)
				set_fret(i + 1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_released(act):
				_keys_held.erase(i + 1)
				if _source == "keys":
					set_fret(_keys_held.back() if _keys_held.size() > 0 else 0)
				return
	if event.is_action_pressed("attack"):
		strike("down")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("special"):
		strike("up")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dombra_tremolo"):
		trem_hold(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("dombra_tremolo"):
		trem_hold(false)
	elif event is InputEventMouseMotion:
		_source = "mouse"
		_fret_from_vector((event as InputEventMouseMotion).position - _radial_center, 58.0)
	elif event is InputEventJoypadMotion:
		var ax := (event as InputEventJoypadMotion).axis
		if ax == JOY_AXIS_LEFT_X or ax == JOY_AXIS_LEFT_Y:
			_source = "stick"
			var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
			_fret_from_vector(v, 0.5)


## Направление → лад: внутри радиуса dead — открытые струны, иначе сектор 1..6 (1 — сверху, по часовой).
func _fret_from_vector(v: Vector2, dead: float) -> void:
	if v.length() < dead:
		set_fret(0)
		return
	var ang := fposmod(atan2(v.x, -v.y) + PI / 6.0, TAU)
	set_fret(int(ang / (TAU / 6.0)) % 6 + 1)


# ================================================================ камера
func _build_camera() -> void:
	var vp := get_viewport()
	_prev_cam = vp.get_camera_3d() if vp else null
	if model == null:
		return
	_cam = Camera3D.new()
	_cam.name = "DombraCam"
	_cam.fov = 40.0
	get_parent().add_child(_cam)
	if _prev_cam:
		_cam.global_transform = _prev_cam.global_transform
		_cam.fov = _prev_cam.fov
	else:
		_cam.global_transform = model.global_transform.translated(Vector3(0, 6, 8))
	_cam.make_current()
	var goal := _closeup_xform()
	var tw := _cam.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cam, "global_transform", goal, 0.9)
	tw.parallel().tween_property(_cam, "fov", 38.0, 0.9)


## Крупный план: камера перед декой домбры (в позе игры), смотрит на середину грифа.
func _closeup_xform() -> Transform3D:
	var parent_x: Transform3D = (model.get_parent() as Node3D).global_transform if model.get_parent() is Node3D else Transform3D.IDENTITY
	var pose: Transform3D = parent_x * model.play_xform
	var center := pose * Vector3(0.45, 0.0, 0.0)
	var front := (pose.basis * Vector3(0, 0, 1)).normalized()
	var up := (pose.basis * Vector3(0, 1, 0)).normalized()
	var right := (-front).cross(Vector3.UP).normalized()
	var eye := center + front * 2.0 + up * 0.2
	var t := Transform3D(Basis.IDENTITY, eye)
	# домбра — справа от центра экрана, слева остаётся место для радиального меню ладов
	return t.looking_at(center + right * 0.05 + Vector3(0, 0.02, 0), Vector3.UP)


func close() -> void:
	if _closing:
		return
	_closing = true
	kui_active = false
	_trem_hold = false
	if model:
		model.show_hands(false)
		model.set_tremolo(false)
		var mt := model.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		mt.tween_property(model, "transform", model.rest_xform, 0.6)
	if _ui:
		var ut := _ui.create_tween()
		ut.tween_property(_root, "modulate:a", 0.0, 0.25)
	var finish := func():
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.make_current()
		if _cam:
			_cam.queue_free()
		HubWindow.reenable_player(player, self)
		_hide_hud(false)
		closed.emit()
		queue_free()
	if _cam and _prev_cam and is_instance_valid(_prev_cam) and is_inside_tree():
		var tw := _cam.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_cam, "global_transform", _prev_cam.global_transform, 0.7)
		tw.parallel().tween_property(_cam, "fov", _prev_cam.fov, 0.7)
		tw.tween_callback(finish)
	else:
		finish.call()


func _exit_tree() -> void:
	_hide_hud(false)
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()


## Прячет HUD (CanvasLayer со скриптом hud.gd) на время крупного плана.
func _hide_hud(on: bool) -> void:
	if on:
		var sc := get_tree().current_scene if is_inside_tree() else null
		if sc == null:
			return
		for c in sc.get_children():
			if c is CanvasLayer and c != _ui and c.get_script() and str((c.get_script() as Script).resource_path).ends_with("hud.gd") and (c as CanvasLayer).visible:
				(c as CanvasLayer).visible = false
				_hidden_layers.append(c)
	else:
		for c in _hidden_layers:
			if is_instance_valid(c):
				(c as CanvasLayer).visible = true
		_hidden_layers.clear()


# ================================================================ UI
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 25
	add_child(_ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := HubWindow.k_theme()
	if th:
		_root.theme = th
	_ui.add_child(_root)
	# виньетка снизу/сверху для читаемости
	for top in [true, false]:
		var g := ColorRect.new()
		g.color = Color(0.03, 0.02, 0.02, 0.45)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.anchor_right = 1.0
		if top:
			g.anchor_bottom = 0.0
			g.offset_bottom = 150
		else:
			g.anchor_top = 1.0
			g.anchor_bottom = 1.0
			g.offset_top = -70
		_root.add_child(g)
	var title := HubWindow.k_title("Домбра у родового костра", 34)
	title.anchor_right = 1.0
	title.offset_top = 8
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)
	# радиальное меню ладов
	_radial = Control.new()
	_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radial.draw.connect(_draw_radial)
	_root.add_child(_radial)
	# дорожка нот кюя
	_lane = Control.new()
	_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lane.anchor_right = 1.0
	_lane.offset_top = 64
	_lane.offset_bottom = 148
	_lane.draw.connect(_draw_lane)
	_lane.visible = false
	_root.add_child(_lane)
	_status = HubWindow.k_label("Свободная игра", 24, Color(0.9, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_status.anchor_right = 1.0
	_status.offset_top = 152
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	# подсказки управления
	_hint = HubWindow.k_label("", 18, Color(0.85, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_top = -62
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	# список кюев справа
	var panel := HubWindow.k_panel(Vector2(330, 0), Color(0.35, 0.85, 0.8))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -360
	panel.offset_right = -20
	panel.offset_top = 200
	_root.add_child(panel)
	_kui_box = VBoxContainer.new()
	_kui_box.add_theme_constant_override("separation", 8)
	panel.add_child(_kui_box)
	_refresh_kui_box()
	var vp := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(1280, 720)
	_radial_center = Vector2(190, vp.y - 200)


func _refresh_kui_box() -> void:
	if _kui_box == null:
		return
	for c in _kui_box.get_children():
		c.queue_free()
	_kui_box.add_child(HubWindow.k_label("Кюи", 26, Color(0.88, 0.72, 0.36), HORIZONTAL_ALIGNMENT_CENTER))
	var free_b := HubWindow.k_button("Свободная игра", stop_kui, 280)
	free_b.focus_mode = Control.FOCUS_NONE
	_kui_box.add_child(free_b)
	var avail := KuiData.available()
	for id in KuiData.KUIS:
		if id in avail:
			var mark := "  ✓" if Meta.kui_prepared == id else ""
			var b := HubWindow.k_button("«%s»%s" % [KuiData.title(id), mark], begin_kui.bind(id), 280)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = str(Run.KUIS.get(id, {}).get("desc", ""))
			_kui_box.add_child(b)
			if Run.KUIS.has(id):
				_kui_box.add_child(HubWindow.k_label(str(Run.KUIS[id]["desc"]), 15, Color(0.7, 0.85, 0.8)))
		else:
			_kui_box.add_child(HubWindow.k_label("??? — Забытая нота не найдена", 16, Color(0.5, 0.45, 0.4)))
	if Meta.kui_prepared != "":
		_kui_box.add_child(HubWindow.k_label("Заряд: «%s»" % KuiData.title(Meta.kui_prepared), 18, Color(0.4, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER))


func _set_status(t: String, c: Color) -> void:
	if _status:
		_status.text = t
		_status.add_theme_color_override("font_color", c)


func _update_hint() -> void:
	var src := {"mouse": "курсор мыши", "keys": "клавиши 1–6", "stick": "левый стик"}
	var fret_name := "открытые струны" if fret == 0 else "лад %d" % fret
	_hint.text = "Лад: %s (%s, 1–6 / мышь / стик)    ЛКМ — қағыс ↓    ПКМ — подцеп ↑    Пробел / СКМ — тремоло    Esc / E — встать" % [fret_name, src.get(_source, "")]


func _draw_radial() -> void:
	var c := _radial_center
	var r_in := 58.0
	var r_out := 128.0
	_radial.draw_circle(c, r_out + 6, Color(0.08, 0.05, 0.04, 0.55))
	for i in 6:
		var a0 := -PI / 2.0 - PI / 6.0 + i * TAU / 6.0
		var a1 := a0 + TAU / 6.0
		var pts := PackedVector2Array()
		var steps := 12
		for k in steps + 1:
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r_out)
		for k in range(steps, -1, -1):
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r_in)
		var sel := fret == i + 1
		var col := Color(0.35, 0.85, 0.8, 0.75) if sel else Color(0.3, 0.2, 0.14, 0.7)
		_radial.draw_colored_polygon(pts, col)
		_radial.draw_polyline(pts, Color(0.88, 0.72, 0.36, 0.9), 2.0, true)
		var mid := (a0 + a1) * 0.5
		var lp := c + Vector2(cos(mid), sin(mid)) * (r_in + r_out) * 0.5
		var f := _root.get_theme_default_font() if _root else null
		if f == null:
			f = ThemeDB.fallback_font
		_radial.draw_string(f, lp + Vector2(-8, 10), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color(1, 1, 1) if sel else Color(0.95, 0.88, 0.75))
		var semis: int = KuiData.SEMITONES[i + 1]
		_radial.draw_string(f, lp + Vector2(-22, 30), "+%d пт" % semis, HORIZONTAL_ALIGNMENT_CENTER, 44, 13, Color(0.8, 0.75, 0.65))
	_radial.draw_circle(c, r_in - 4, Color(0.35, 0.85, 0.8, 0.75) if fret == 0 else Color(0.15, 0.1, 0.08, 0.8))
	var f2 := ThemeDB.fallback_font
	_radial.draw_string(f2, c + Vector2(-40, 6), "открыт.", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color(1, 0.95, 0.85))


func _draw_lane() -> void:
	if kui_id == "":
		return
	var w := _lane.size.x
	var h := _lane.size.y
	var hit_x := 220.0
	_lane.draw_rect(Rect2(40, 4, w - 80, h - 8), Color(0.06, 0.04, 0.03, 0.7))
	_lane.draw_line(Vector2(hit_x, 0), Vector2(hit_x, h), Color(1, 0.9, 0.5), 3.0)
	var bl := KuiData.beat_len(kui_id)
	var f := ThemeDB.fallback_font
	# доли метронома
	var beat0 := int(floor(song_time / bl)) - 2
	for b in range(beat0, beat0 + 16):
		var x := hit_x + (b * bl - song_time) * LANE_SPEED
		if x < 40 or x > w - 40:
			continue
		_lane.draw_line(Vector2(x, 10), Vector2(x, h - 10), Color(1, 1, 1, 0.25 if b % 4 == 0 else 0.1), 2.0 if b % 4 == 0 else 1.0)
	var ns := KuiData.notes(kui_id)
	for i in ns.size():
		var n: Dictionary = ns[i]
		var x := hit_x + (KuiData.note_time(kui_id, i) - song_time) * LANE_SPEED
		if x < 20 or x > w - 40:
			continue
		var col: Color = STROKE_COL.get(str(n["stroke"]), Color.WHITE)
		if i < kui_index:
			col = Color(0.4, 1.0, 0.5, 0.35)
		elif i == kui_index:
			col = col.lightened(0.2)
		var rect := Rect2(x - 26, 14, 52, h - 28)
		_lane.draw_rect(rect, col, true)
		_lane.draw_rect(rect, Color(0, 0, 0, 0.6), false, 2.0)
		var arrow: String = {"down": "↓", "up": "↑", "trem": "≈"}.get(str(n["stroke"]), "?")
		var ft := "О" if int(n["fret"]) == 0 else str(n["fret"])
		_lane.draw_string(f, Vector2(x - 26, 44), ft, HORIZONTAL_ALIGNMENT_CENTER, 52, 26, Color(0.1, 0.05, 0.02))
		_lane.draw_string(f, Vector2(x - 26, 70), arrow, HORIZONTAL_ALIGNMENT_CENTER, 52, 22, Color(0.1, 0.05, 0.02))
	if kui_index < ns.size():
		var n2: Dictionary = ns[kui_index]
		var nm := "открытые" if int(n2["fret"]) == 0 else "лад %d" % int(n2["fret"])
		_lane.draw_string(f, Vector2(48, h - 10), "Далее: %s · %s" % [nm, KuiData.STROKE_NAMES.get(str(n2["stroke"]), "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.8))
