extends Node2D
## Живой мир арены. Каждый экземпляр рисует свой пласт глубины:
##   far   — мелкая пыль вдали (ночью — светлячки), беркуты в небе;
##   back  — песок по земле позади героя, перекати-поле;
##   front — пылинки на уровне героя, пух ковыля, песок спереди, струи ветра;
##   near  — крупные размытые пятна у самой камеры.
## Частицы живут в «координатах параллакса» с глубиной f: мир_x = x + камера·(1 − f).

const PUFF := preload("res://assets/fx/puff.png")
const BOKEH := preload("res://assets/fx/bokeh.png")
const FLUFF := preload("res://assets/fx/fluff.png")
const TUMBLE := preload("res://assets/fx/tumble.png")
const SOFT := preload("res://assets/fx/soft.png")

var layer := "front"
var night := false
var gust := 0.0
var ground_y := 600.0

var motes := []
var sand := []
var lines := []
var sand_acc := 0.0
var line_acc := 0.0
var tumble := {"on": false, "x": 0.0, "r": 34.0, "rot": 0.0, "ph": 0.0, "vx": -260.0, "next": 4.0}
var eagles := [
	{"cx": 900.0, "cy": 175.0, "rx": 160.0, "ry": 45.0, "w": 0.24, "ph": 0.0, "s": 1.0},
	{"cx": 1900.0, "cy": 120.0, "rx": 120.0, "ry": 30.0, "w": -0.19, "ph": 2.0, "s": 0.7},
]
var cx := 640.0
var half := 700.0
var t := 0.0

const KINDS := {
	"far": {"f": [0.2, 0.45], "y": [110.0, 545.0], "size": [0.9, 2.2], "a": [0.25, 0.55], "v": [10.0, 28.0], "n": 70},
	"mid": {"f": [0.85, 1.05], "y": [240.0, 650.0], "size": [1.4, 2.8], "a": [0.35, 0.65], "v": [35.0, 80.0], "n": 34},
	"near": {"f": [1.5, 2.3], "y": [-20.0, 740.0], "size": [12.0, 34.0], "a": [0.07, 0.2], "v": [110.0, 220.0], "n": 12},
	"fluff": {"f": [1.0, 1.6], "y": [380.0, 700.0], "size": [12.0, 19.0], "a": [0.75, 0.95], "v": [70.0, 140.0], "n": 9},
}
const LAYER_KINDS := {"far": ["far"], "back": [], "front": ["mid", "fluff"], "near": ["near"]}


func _ready() -> void:
	z_index = {"far": 0, "back": 0, "front": 30, "near": 40}[layer]
	if night and (layer == "far" or layer == "near"):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	_cam()
	for k in LAYER_KINDS[layer]:
		var n: int = KINDS[k]["n"]
		if night and k == "fluff":
			n = 0
		for i in n:
			motes.append(_new_mote(k, true))


func _cam() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		cx = cam.get_screen_center_position().x
		half = 640.0 / cam.zoom.x + 80.0


func _new_mote(k: String, anywhere: bool) -> Dictionary:
	var d: Dictionary = KINDS[k]
	var f := randf_range(d["f"][0], d["f"][1])
	var sx := randf_range(-half, half) if anywhere else half + randf_range(0.0, 140.0)
	return {"k": k, "f": f, "x": cx + sx - cx * (1.0 - f), "y": randf_range(d["y"][0], d["y"][1]),
		"size": randf_range(d["size"][0], d["size"][1]), "a": randf_range(d["a"][0], d["a"][1]),
		"v": randf_range(d["v"][0], d["v"][1]), "ph": randf() * TAU, "rot": randf() * TAU, "vr": randf_range(-2.0, 2.0)}


func _wx(x: float, f: float) -> float:
	return x + cx * (1.0 - f)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	t += delta
	_cam()
	var wmul := 1.0 + 2.4 * gust
	for i in motes.size():
		var p: Dictionary = motes[i]
		p.x -= p.v * wmul * delta * (0.4 if night else 1.0)
		p.ph += delta * 1.3
		p.rot += p.vr * delta * wmul
		var dx: float = _wx(p.x, p.f) - cx
		if dx < -half:
			motes[i] = _new_mote(p.k, false)
		elif dx > half + 200.0:
			var q := _new_mote(p.k, false)
			q.x = cx - half - randf_range(0.0, 140.0) - cx * (1.0 - q.f)
			motes[i] = q
	if layer == "back" or layer == "front":
		sand_acc += delta * 17.0 * gust * gust
		while sand_acc > 1.0:
			sand_acc -= 1.0
			sand.append({"x": cx + randf_range(-half * 0.6, half + 300.0), "y": randf_range(ground_y - 26.0, ground_y + 85.0),
				"len": randf_range(70.0, 180.0), "v": randf_range(320.0, 540.0), "life": 0.0, "max": randf_range(0.9, 1.7)})
		for i in range(sand.size() - 1, -1, -1):
			var s: Dictionary = sand[i]
			s.life += delta
			s.x -= s.v * delta * (0.6 + gust)
			if s.life > s.max:
				sand.remove_at(i)
	if layer == "front":
		line_acc += delta * 5.0 * gust
		while line_acc > 1.0:
			line_acc -= 1.0
			var f := randf_range(0.5, 1.4)
			lines.append({"f": f, "x": cx + randf_range(-half * 0.4, half + 300.0) - cx * (1.0 - f), "y": randf_range(150.0, 650.0),
				"len": randf_range(90.0, 240.0), "v": randf_range(700.0, 1100.0), "life": 0.0, "max": randf_range(0.7, 1.2),
				"amp": randf_range(4.0, 12.0), "ph": randf() * TAU})
		for i in range(lines.size() - 1, -1, -1):
			var l: Dictionary = lines[i]
			l.life += delta
			l.x -= l.v * delta * (0.6 + gust)
			if l.life > l.max:
				lines.remove_at(i)
	if layer == "back":
		if not tumble.on:
			tumble.next -= delta
			if tumble.next <= 0.0:
				tumble.on = true
				tumble.x = cx + half + 90.0
				tumble.ph = 0.0
				tumble.vx = -260.0
		else:
			tumble.vx = lerpf(tumble.vx, -(240.0 + 320.0 * gust), minf(1.0, delta * 2.0))
			tumble.x += tumble.vx * delta
			tumble.ph += absf(tumble.vx) * delta / 95.0
			tumble.rot -= absf(tumble.vx) * delta / tumble.r
			if tumble.x - cx < -half - 140.0:
				tumble.on = false
				tumble.next = randf_range(6.0, 12.0)
	if layer == "far" and not night:
		for e in eagles:
			e.ph += e.w * delta
	queue_redraw()


func _draw() -> void:
	for p in motes:
		var x := _wx(p.x, p.f)
		if absf(x - cx) > half:
			continue
		var y: float = p.y + sin(p.ph) * (14.0 if p.k == "near" else 6.0)
		match p.k:
			"near":
				draw_texture_rect(BOKEH, Rect2(x - p.size, y - p.size, p.size * 2.0, p.size * 2.0), false, Color(1, 1, 1, p.a))
			"fluff":
				draw_set_transform(Vector2(x, y), p.rot, Vector2.ONE)
				draw_texture_rect(FLUFF, Rect2(-p.size / 2.0, -p.size / 2.0, p.size, p.size), false, Color(1, 1, 1, p.a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				if night:
					var blink: float = 0.5 + 0.5 * sin(p.ph * 3.0)
					var c := Color(0.55, 1.0, 0.85, p.a * blink)
					draw_texture_rect(SOFT, Rect2(x - p.size * 4.0, y - p.size * 4.0, p.size * 8.0, p.size * 8.0), false, c)
				else:
					draw_circle(Vector2(x, y), p.size, Color(1.0, 0.95, 0.82, p.a * (0.7 + 0.3 * sin(p.ph * 2.0))))
	for s in sand:
		draw_texture_rect(PUFF, Rect2(s.x, s.y - 9.0, s.len, 18.0), false, Color(1, 1, 1, sin(PI * s.life / s.max) * 0.38))
	for l in lines:
		var a: float = sin(PI * l.life / l.max) * 0.34
		var x0 := _wx(l.x, l.f)
		var pts := PackedVector2Array()
		for i in 11:
			var k := i / 10.0
			pts.append(Vector2(x0 + k * l.len, l.y + sin(k * 6.0 + l.ph + t * 3.0) * l.amp * k))
		draw_polyline(pts, Color(1.0, 0.96, 0.88, a), 1.0 + l.f, true)
	if layer == "back" and tumble.on:
		var hop: float = absf(sin(tumble.ph)) * 26.0 * (0.6 + gust)
		var y: float = ground_y - tumble.r + 6.0 - hop
		draw_circle(Vector2(tumble.x, ground_y + 3.0), tumble.r * 0.7, Color(0.16, 0.07, 0.03, 0.18 * (1.0 - hop / 60.0)))
		draw_set_transform(Vector2(tumble.x, y), tumble.rot, Vector2.ONE)
		draw_texture_rect(TUMBLE, Rect2(-tumble.r, -tumble.r, tumble.r * 2.0, tumble.r * 2.0), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if layer == "far" and not night:
		for e in eagles:
			var ex := _wx(e.cx + cos(e.ph) * e.rx, 0.1)
			var ey: float = e.cy + sin(e.ph) * e.ry
			var flapping := sin(t * 0.7 + e.cx) > 0.55
			var wing: float = sin(t * 13.0 + e.cx) * 0.9 if flapping else 0.25 + sin(t * 1.5 + e.cx) * 0.05
			var s: float = e.s
			var wy: float = wing * 9.0 * s
			var c := Color(0.2, 0.09, 0.05, 0.85)
			var pts := PackedVector2Array()
			for i in 9:
				var k := i / 8.0
				var px: float = lerpf(-24.0, 24.0, k) * s
				var py: float = -wy * absf(k * 2.0 - 1.0)
				pts.append(Vector2(ex + px, ey + py - sin(k * PI) * 3.0 * s))
			draw_polyline(pts, c, 2.4 * s, true)
			draw_circle(Vector2(ex, ey + 1.0), 3.0 * s, c)
