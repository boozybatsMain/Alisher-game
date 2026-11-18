extends Node2D
## Процедурная бирюзовая лента на голове Батыра.
## Цепочка точек (метод Верле) считается каждый кадр: тело анимировано рывками по 4 кадра,
## а лента движется плавно — глаз считывает движение как непрерывное.

var hero: Node
var chains := []        # две ленты: массивы точек {p, prev}
var segs := [8.5, 7.0]
var widths := [6.5, 4.5]
var root := Vector2.ZERO
var inited := false

const COLOR := Color(0.18, 0.77, 0.71)
const EDGE := Color(0.06, 0.16, 0.17, 0.9)
const SHINE := Color(0.55, 1.0, 0.94, 0.7)


func _ready() -> void:
	top_level = true   # рисуем в мировых координатах
	z_index = 0


func _physics_process(delta: float) -> void:
	if hero == null:
		return
	var target: Vector2 = hero.anchor_point()
	if not inited:
		root = target
		for c in 2:
			var pts := []
			for i in 9:
				pts.append({"p": root - Vector2(i * segs[c], 0), "prev": root - Vector2(i * segs[c], 0)})
			chains.append(pts)
		inited = true
	# корень догоняет голову за пару сотых секунды — без рывков между кадрами спрайта
	root = root.lerp(target, minf(1.0, delta * 28.0))
	var vx: float = hero.velocity.x
	var moving := absf(vx) > 60.0
	var face: int = hero.facing
	var gust: float = hero.gust
	var t := Time.get_ticks_msec() * 0.001
	var sub := 3
	var h := delta / sub
	for s in sub:
		for c in 2:
			var pts: Array = chains[c]
			pts[0].p = root
			for i in range(1, pts.size()):
				var q: Dictionary = pts[i]
				var wx := -face * (1300.0 if moving else 420.0) - vx * 1.0 - gust * 900.0 \
					+ sin(t * 8.0 + i * 0.8 + segs[c]) * (520.0 if moving else 300.0 + gust * 400.0)
				var wy := 950.0 + sin(t * 10.0 + i * 1.3 + segs[c] * 2.0) * 300.0
				var v: Vector2 = (q.p - q.prev) * 0.982
				q.prev = q.p
				q.p = q.p + v + Vector2(wx, wy) * h * h
			for it in 6:
				for i in range(1, pts.size()):
					var a: Dictionary = pts[i - 1]
					var b: Dictionary = pts[i]
					var d: Vector2 = b.p - a.p
					var dl := maxf(d.length(), 0.001)
					var diff: float = (dl - segs[c]) / dl
					if i == 1:
						b.p -= d * diff
					else:
						a.p += d * diff * 0.5
						b.p -= d * diff * 0.5
				# жёсткость на изгиб: лента не мнётся гармошкой
				for i in range(2, pts.size()):
					var a2: Dictionary = pts[i - 2]
					var b2: Dictionary = pts[i]
					var d2: Vector2 = b2.p - a2.p
					var dl2 := maxf(d2.length(), 0.001)
					var mn: float = segs[c] * 1.7
					if dl2 < mn:
						var k: float = (dl2 - mn) / dl2 * 0.5
						if i > 2:
							a2.p += d2 * k
						b2.p -= d2 * k
	modulate.a = hero.modulate.a
	queue_redraw()


func _draw() -> void:
	for c in chains.size():
		var pts: Array = chains[c]
		var n := pts.size()
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var spine := PackedVector2Array()
		for i in n:
			var p: Vector2 = pts[i].p
			var nx: Vector2 = pts[mini(n - 1, i + 1)].p
			var pv: Vector2 = pts[maxi(0, i - 1)].p
			var tg := (nx - pv).normalized()
			var w: float = widths[c] * (1.0 - float(i) / n * 0.6)
			left.append(p + Vector2(-tg.y, tg.x) * w)
			right.append(p - Vector2(-tg.y, tg.x) * w)
			spine.append(p)
		var poly := left.duplicate()
		for i in range(n - 1, -1, -1):
			poly.append(right[i])
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			draw_colored_polygon(poly, COLOR)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, EDGE, 2.0, true)
		draw_polyline(spine, SHINE, 1.5, true)
