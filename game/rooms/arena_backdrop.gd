class_name ArenaBackdrop
extends CanvasLayer
## 2D-задник арены с параллаксом: небо + степь (sky_*.jpg), дальний и ближний хребты Алатау (mountains_far_*.png),
## дымка у подножия. Рисуется как фон окружения (Environment.BG_CANVAS, layer ниже background_canvas_max_layer),
## поэтому виден во всех «пустых» местах кадра при наклоне камеры 40° — за кромками арены, над пропастями.
## Параллакс: слои сдвигаются вслед за экранным смещением арены (ArenaBuilder.update_backdrop) с factor 0.04–0.3.
##
## API: ArenaBackdrop.make(biome, fog_color) -> ArenaBackdrop; set_shift(screen_delta: Vector2)
##      LAYER — номер слоя (для Environment.background_canvas_max_layer)

const LAYER := -20
const SKY := ["res://assets/bg/sky_day.jpg", "res://assets/bg/sky_night.jpg", "res://assets/bg/sky_night.jpg"]
## [текстура, factor параллакса, высота слоя (доля экрана), низ слоя (доля экрана)]
const MOUNTAINS := [
	[["mountains_far_0", 0.12, 0.44, 0.50], ["mountains_far_1", 0.24, 0.30, 0.52]],
	[["mountains_far_2", 0.12, 0.44, 0.50], ["mountains_far_3", 0.24, 0.30, 0.52]],
	[["mountains_far_2", 0.12, 0.48, 0.50], ["mountains_far_3", 0.24, 0.34, 0.52]],
]
const SKY_FACTOR := 0.04
const HORIZON := 0.51          ## где на экране линия горизонта (подножие хребтов)
const SKY_HORIZON := 0.6       ## где горизонт на картинке неба (доля высоты)

var biome := 0
var tint := Color.WHITE
var haze := Color(1, 1, 1, 0)
var shift := Vector2.ZERO
var _canvas: Control


static func make(p_biome: int, fog: Color) -> ArenaBackdrop:
	var b := ArenaBackdrop.new()
	b.name = "Backdrop2D"
	b.layer = LAYER
	b.biome = clampi(p_biome, 0, 2)
	# биомы 1/2 — под землёй/во Мгле: задник приглушён и окрашен цветом тумана
	b.tint = Color.WHITE.lerp(fog.lightened(0.25), [0.12, 0.45, 0.5][b.biome])
	b.haze = Color(fog.r, fog.g, fog.b, 0.75)
	return b


func _ready() -> void:
	_canvas = _Canvas.new()
	_canvas.owner_bd = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func set_shift(delta: Vector2) -> void:
	if delta.is_equal_approx(shift):
		return
	shift = delta
	if _canvas:
		_canvas.queue_redraw()


class _Canvas extends Control:
	var owner_bd: ArenaBackdrop
	var _sky: Texture2D
	var _layers: Array = []   ## [[Texture2D, factor, h, bottom]]
	var _under := Color(0.3, 0.2, 0.15)   ## цвет нижнего края картинки неба (заливка ниже неё)

	func _ready() -> void:
		_sky = RoomUtil.tex(SKY[owner_bd.biome])
		var img: Image = _sky.get_image() if _sky else null
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			_under = img.get_pixel(img.get_width() / 2, img.get_height() - 2)
		for l in MOUNTAINS[owner_bd.biome]:
			var t := RoomUtil.tex("res://assets/bg/%s.png" % String(l[0]))
			if t:
				_layers.append([t, l[1], l[2], l[3]])
		resized.connect(queue_redraw)

	func _draw() -> void:
		var sz := size
		if sz.x < 2.0 or sz.y < 2.0:
			sz = get_viewport_rect().size
		var s := owner_bd.shift
		var tint := owner_bd.tint
		# небо + степь: cover-fit с запасом 25% под параллакс
		if _sky:
			var ts := _sky.get_size()
			var k := maxf(sz.x / ts.x, sz.y / ts.y) * 1.25
			var ds := ts * k
			var p := Vector2((sz.x - ds.x) * 0.5, sz.y * HORIZON - ds.y * SKY_HORIZON) + s * SKY_FACTOR
			p.x = clampf(p.x, sz.x - ds.x, 0.0)
			p.y = minf(p.y, 0.0)
			# под картинкой (если её не хватило до низа экрана) — цвет нижнего края степи
			if p.y + ds.y < sz.y:
				draw_rect(Rect2(0, p.y + ds.y - 1.0, sz.x, sz.y - p.y - ds.y + 2.0), _under * tint)
			draw_texture_rect(_sky, Rect2(p, ds), false, tint)
		else:
			draw_rect(Rect2(Vector2.ZERO, sz), owner_bd.haze)
		# хребты: горизонтально бесшовные полосы, каждая со своим factor
		for l in _layers:
			var t: Texture2D = l[0]
			var f: float = l[1]
			var h: float = sz.y * float(l[2])
			var w: float = t.get_width() * h / t.get_height()
			var bottom: float = sz.y * float(l[3]) + s.y * f
			var x0: float = fposmod(s.x * f, w) - w
			var x := x0
			while x < sz.x:
				draw_texture_rect(t, Rect2(x, bottom - h, w, h), false, tint)
				x += w
			# дымка у подножия: плавно растворяет край хребта в степи
			var hz := owner_bd.haze
			var band := sz.y * 0.07
			var c0 := Color(hz.r, hz.g, hz.b, 0.0)
			var c1 := Color(hz.r, hz.g, hz.b, hz.a * 0.8)
			draw_polygon(PackedVector2Array([Vector2(0, bottom - band), Vector2(sz.x, bottom - band), Vector2(sz.x, bottom), Vector2(0, bottom)]),
				PackedColorArray([c0, c0, c1, c1]))
			draw_polygon(PackedVector2Array([Vector2(0, bottom), Vector2(sz.x, bottom), Vector2(sz.x, bottom + band), Vector2(0, bottom + band)]),
				PackedColorArray([c1, c1, c0, c0]))
