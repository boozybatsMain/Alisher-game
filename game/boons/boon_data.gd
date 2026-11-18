class_name BoonData
extends RefCounted
## Данные Духовных Даров: 6 духов, по 6 даров. Слоты: attack / special / dash / passive.
## Значения задаются по редкости [common, rare, epic] и прибавкой за уровень (1–3, улучшение у торговца).
## describe(id, level, rarity) подставляет числа в {ключи} описания.

const RARITIES := ["common", "rare", "epic"]
const RARITY_TITLE := {"common": "Обычный", "rare": "Редкий", "epic": "Эпический"}
const RARITY_COLOR := {"common": "#d8cfbf", "rare": "#5aa0ff", "epic": "#ffb83d"}
const SLOT_TITLE := {"attack": "Обычная атака", "special": "Особая атака", "dash": "Рывок", "passive": "Пассивный"}
const MAX_LEVEL := 3

const GODS := {
	"tengri": {"name": "Тенгри", "title": "Владыка Неба", "color": "#8cc8ff", "glyph": "bolt",
		"desc": "Гром и молния: цепные разряды, оглушение толпы."},
	"ai_mergen": {"name": "Ай-Мерген", "title": "Небесный Охотник", "color": "#c9b3ff", "glyph": "arrow",
		"desc": "Критические удары, духовные стрелы, пробитие брони."},
	"umai": {"name": "Умай", "title": "Мать Очага", "color": "#ff8a3d", "glyph": "flame",
		"desc": "Горение, огненные волны, исцеление."},
	"zher_su": {"name": "Жер-Су", "title": "Дух Земли и Вод", "color": "#5fd3c4", "glyph": "mountain",
		"desc": "Отбрасывание в стены, лёд, каменная кожа."},
	"erlik": {"name": "Ерлик", "title": "Владыка Подземья", "color": "#9b4dff", "glyph": "skull",
		"desc": "Скверна, взрывы проклятия, сила ценой крови."},
	"kokbori": {"name": "Көкбөрі", "title": "Небесный Волк", "color": "#e04848", "glyph": "fang",
		"desc": "Кровотечение, ярость стаи, скорость."},
}

const GOD_ORDER := ["tengri", "ai_mergen", "umai", "zher_su", "erlik", "kokbori"]

## v: {ключ: [common, rare, epic]}, lvl: {ключ: прибавка за уровень сверх 1-го}
const BOONS := {
	# ------------------------------------------------------------ Тенгри
	"tengri_strike": {"god": "tengri", "slot": "attack", "title": "Удар Грома",
		"desc": "Обычные атаки бьют цепной молнией: {dmg} урона, перескакивает на {jumps} цели.",
		"v": {"dmg": [6, 9, 12], "jumps": [2, 3, 4]}, "lvl": {"dmg": 3}},
	"tengri_flash": {"god": "tengri", "slot": "special", "title": "Небесный Разряд",
		"desc": "Особая атака призывает молнию с неба: {dmg} урона и оглушение на {stun} с.",
		"v": {"dmg": [14, 20, 28], "stun": [0.6, 0.8, 1.0]}, "lvl": {"dmg": 6}},
	"tengri_dash": {"god": "tengri", "slot": "dash", "title": "Шаг Грозы",
		"desc": "На месте рывка бьёт разряд: {dmg} урона в радиусе 2.5 м.",
		"v": {"dmg": [12, 18, 24]}, "lvl": {"dmg": 5}},
	"tengri_static": {"god": "tengri", "slot": "passive", "title": "Статика",
		"desc": "Удары с шансом {chance}% оглушают всех врагов в 3 м от цели на {stun} с.",
		"v": {"chance": [10, 15, 20], "stun": [0.8, 1.0, 1.2]}, "lvl": {"chance": 4}},
	"tengri_storm": {"god": "tengri", "slot": "passive", "title": "Гроза над Степью",
		"desc": "Каждые {cd} с молния поражает случайного врага рядом: {dmg} урона.",
		"v": {"cd": [3.0, 2.5, 2.0], "dmg": [15, 20, 26]}, "lvl": {"dmg": 6}},
	"tengri_shock": {"god": "tengri", "slot": "passive", "title": "Заряженная Кожа",
		"desc": "Получая урон, бьёшь атакующего молнией на {dmg}.",
		"v": {"dmg": [20, 30, 40]}, "lvl": {"dmg": 10}},
	# ------------------------------------------------------------ Ай-Мерген
	"aim_attack": {"god": "ai_mergen", "slot": "attack", "title": "Меткий Глаз",
		"desc": "Обычные атаки: +{crit}% шанс крита.",
		"v": {"crit": [15, 22, 30]}, "lvl": {"crit": 5}},
	"aim_special": {"god": "ai_mergen", "slot": "special", "title": "Духовные Стрелы",
		"desc": "Особая атака выпускает {n} самонаводящихся стрелы духа по {dmg} урона.",
		"v": {"n": [2, 3, 4], "dmg": [8, 10, 12]}, "lvl": {"dmg": 3}},
	"aim_dash": {"god": "ai_mergen", "slot": "dash", "title": "Тень Охотника",
		"desc": "После рывка следующий удар — гарантированный крит с +{dmg}% урона.",
		"v": {"dmg": [10, 25, 40]}, "lvl": {"dmg": 10}},
	"aim_pierce": {"god": "ai_mergen", "slot": "passive", "title": "Пробивающий Наконечник",
		"desc": "Криты пробивают броню и наносят +{armor}% урона по броне.",
		"v": {"armor": [50, 80, 120]}, "lvl": {"armor": 25}},
	"aim_critdmg": {"god": "ai_mergen", "slot": "passive", "title": "Глаз Беркута",
		"desc": "+{v}% к урону критов.",
		"v": {"v": [30, 45, 60]}, "lvl": {"v": 15}},
	"aim_crit": {"god": "ai_mergen", "slot": "passive", "title": "Охотничий Азарт",
		"desc": "+{v}% шанс крита для всех атак.",
		"v": {"v": [6, 9, 12]}, "lvl": {"v": 3}},
	# ------------------------------------------------------------ Умай
	"umai_attack": {"god": "umai", "slot": "attack", "title": "Пламя Очага",
		"desc": "Обычные атаки поджигают: горение {dps} урона/с в течение 3 с.",
		"v": {"dps": [4, 6, 8]}, "lvl": {"dps": 2}},
	"umai_special": {"god": "umai", "slot": "special", "title": "Огненный Вихрь",
		"desc": "Особая атака: +{v}% урона и сильное горение {dps}/с на 4 с.",
		"v": {"v": [20, 30, 40], "dps": [6, 9, 12]}, "lvl": {"v": 10}},
	"umai_dash": {"god": "umai", "slot": "dash", "title": "Огненный След",
		"desc": "Рывок оставляет пламя: враги на пути получают {dmg} урона и горят {dps}/с.",
		"v": {"dmg": [6, 9, 12], "dps": [4, 6, 8]}, "lvl": {"dmg": 3}},
	"umai_landing": {"god": "umai", "slot": "passive", "title": "Огненная Волна",
		"desc": "Приземление после прыжка выпускает огненную волну: {dmg} урона в радиусе {r} м.",
		"v": {"dmg": [12, 18, 24], "r": [2.5, 3.0, 3.5]}, "lvl": {"dmg": 6}},
	"umai_heal": {"god": "umai", "slot": "passive", "title": "Тепло Матери",
		"desc": "Убийство горящего врага лечит {v} HP.",
		"v": {"v": [3, 5, 7]}, "lvl": {"v": 2}},
	"umai_ember": {"god": "umai", "slot": "passive", "title": "Тлеющий Пепел",
		"desc": "Горящие враги получают +{v}% урона от твоих атак.",
		"v": {"v": [15, 22, 30]}, "lvl": {"v": 8}},
	# ------------------------------------------------------------ Жер-Су
	"zher_attack": {"god": "zher_su", "slot": "attack", "title": "Сила Горы",
		"desc": "Обычные атаки отбрасывают на {v}% сильнее; удар врага о стену — ×2 урона.",
		"v": {"v": [60, 90, 120]}, "lvl": {"v": 30}},
	"zher_special": {"god": "zher_su", "slot": "special", "title": "Ледяной Поток",
		"desc": "Особая атака замедляет на {slow}% на 3 с; третье попадание по цели замораживает на {freeze} с.",
		"v": {"slow": [30, 40, 50], "freeze": [1.2, 1.6, 2.0]}, "lvl": {"freeze": 0.4}},
	"zher_dash": {"god": "zher_su", "slot": "dash", "title": "Ледяная Тропа",
		"desc": "В конце рывка враги в 2.5 м замерзают на {t} с.",
		"v": {"t": [0.8, 1.2, 1.6]}, "lvl": {"t": 0.3}},
	"zher_skin": {"god": "zher_su", "slot": "passive", "title": "Каменная Кожа",
		"desc": "Входящий урон −{v}%.",
		"v": {"v": [10, 15, 20]}, "lvl": {"v": 5}},
	"zher_quake": {"god": "zher_su", "slot": "passive", "title": "Дрожь Земли",
		"desc": "Тяжёлые удары вызывают толчок: {dmg} урона в радиусе 2.5 м и отбрасывание.",
		"v": {"dmg": [8, 12, 16]}, "lvl": {"dmg": 4}},
	"zher_frost": {"god": "zher_su", "slot": "passive", "title": "Хватка Холода",
		"desc": "По замедленным и замороженным врагам +{v}% урона.",
		"v": {"v": [20, 30, 40]}, "lvl": {"v": 10}},
	# ------------------------------------------------------------ Ерлик
	"erlik_attack": {"god": "erlik", "slot": "attack", "title": "Касание Скверны",
		"desc": "Обычные атаки накладывают {n} стак скверны (2 урона/с за стак).",
		"v": {"n": [1, 1, 2]}, "lvl": {"n": 1}},
	"erlik_special": {"god": "erlik", "slot": "special", "title": "Печать Проклятия",
		"desc": "Особая атака: +{v}% урона и проклятие на {t} с (взрыв при смерти).",
		"v": {"v": [15, 25, 35], "t": [4.0, 5.0, 6.0]}, "lvl": {"v": 10}},
	"erlik_dash": {"god": "erlik", "slot": "dash", "title": "Тёмный Шаг",
		"desc": "Рывок сквозь врагов накладывает {n} стака скверны каждому на пути.",
		"v": {"n": [2, 3, 4]}, "lvl": {"n": 1}},
	"erlik_blast": {"god": "erlik", "slot": "passive", "title": "Взрыв Проклятия",
		"desc": "Проклятый враг или враг с 5+ стаками скверны взрывается при смерти: {dmg} урона в радиусе 3 м.",
		"v": {"dmg": [20, 30, 40]}, "lvl": {"dmg": 10}},
	"erlik_blood": {"god": "erlik", "slot": "passive", "title": "Цена Крови",
		"desc": "+{v}% ко всему урону, но каждый удар и рывок стоит {hp} HP (не ниже 1).",
		"v": {"v": [25, 35, 50], "hp": [1, 1, 1]}, "lvl": {"v": 10}},
	"erlik_rot": {"god": "erlik", "slot": "passive", "title": "Гниль",
		"desc": "Враги со скверной получают +{v}% урона от твоих атак.",
		"v": {"v": [15, 22, 30]}, "lvl": {"v": 8}},
	# ------------------------------------------------------------ Көкбөрі
	"kok_attack": {"god": "kokbori", "slot": "attack", "title": "Клык Волка",
		"desc": "Обычные атаки вызывают кровотечение: {dps} урона/с в течение 4 с.",
		"v": {"dps": [3, 5, 7]}, "lvl": {"dps": 2}},
	"kok_special": {"god": "kokbori", "slot": "special", "title": "Вой Стаи",
		"desc": "Особая атака: +{v}% урона за каждого кровоточащего врага рядом (до 5).",
		"v": {"v": [10, 15, 20]}, "lvl": {"v": 5}},
	"kok_dash": {"god": "kokbori", "slot": "dash", "title": "Волчий Бросок",
		"desc": "После рывка следующий удар: +{v}% урона и сильное кровотечение.",
		"v": {"v": [30, 50, 70]}, "lvl": {"v": 15}},
	"kok_frenzy": {"god": "kokbori", "slot": "passive", "title": "Охотничий Раж",
		"desc": "Каждый поражённый враг: +{as}% скорости атаки и +{ms}% бега, до {max} стаков; затухают за 3 с.",
		"v": {"as": [3, 4, 5], "ms": [2, 3, 4], "max": [6, 8, 10]}, "lvl": {"as": 1}},
	"kok_hunt": {"god": "kokbori", "slot": "passive", "title": "Загонщик",
		"desc": "+{v}% урона по кровоточащим врагам и +{b}% урона в спину.",
		"v": {"v": [15, 22, 30], "b": [20, 30, 40]}, "lvl": {"v": 8}},
	"kok_swift": {"god": "kokbori", "slot": "passive", "title": "Бег Волка",
		"desc": "+{v}% к скорости бега и +{d} заряд рывка.",
		"v": {"v": [8, 12, 16], "d": [0, 0, 1]}, "lvl": {"v": 4}},
}

static var _icons := {}


static func exists(id: String) -> bool:
	return BOONS.has(id)


static func get_boon(id: String) -> Dictionary:
	return BOONS.get(id, {})


static func god_of(id: String) -> String:
	return String(BOONS.get(id, {}).get("god", ""))


static func slot_of(id: String) -> String:
	return String(BOONS.get(id, {}).get("slot", "passive"))


static func title_of(id: String) -> String:
	return String(BOONS.get(id, {}).get("title", id))


static func god_color(god: String) -> Color:
	return Color(String(GODS.get(god, {}).get("color", "#ffffff")))


static func god_name(god: String) -> String:
	return String(GODS.get(god, {}).get("name", god))


static func rarity_color(rarity: String) -> Color:
	return Color(String(RARITY_COLOR.get(rarity, "#d8cfbf")))


static func rarity_index(rarity: String) -> int:
	return maxi(0, RARITIES.find(rarity))


static func boons_of(god: String) -> Array:
	var out := []
	for id in BOONS:
		if BOONS[id]["god"] == god:
			out.append(id)
	return out


## Значение параметра дара с учётом редкости и уровня.
static func value(id: String, key: String, level := 1, rarity := "common") -> float:
	var b: Dictionary = BOONS.get(id, {})
	if b.is_empty():
		return 0.0
	var arr: Array = b["v"].get(key, [0, 0, 0])
	var v := float(arr[rarity_index(rarity)])
	v += float(b.get("lvl", {}).get(key, 0.0)) * float(maxi(0, level - 1))
	return v


static func describe(id: String, level := 1, rarity := "common") -> String:
	var b: Dictionary = BOONS.get(id, {})
	if b.is_empty():
		return ""
	var s: String = b["desc"]
	for key in b["v"]:
		var v := value(id, key, level, rarity)
		var txt := str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)
		s = s.replace("{%s}" % key, txt)
	return s


## Цена продажи в Колодце Обмена.
static func sell_price(rarity: String, level: int) -> int:
	var base := [30, 50, 80][rarity_index(rarity)] as int
	return base + 15 * maxi(1, level)


## Процедурная иконка дара: ромб цвета духа, рамка цвета редкости, символ слота. Может вернуть null.
static func icon(id: String, rarity := "common") -> Texture2D:
	var key := id + ":" + rarity
	if _icons.has(key):
		return _icons[key]
	var b: Dictionary = BOONS.get(id, {})
	if b.is_empty():
		return null
	var tex := _make_icon(god_color(b["god"]), rarity_color(rarity), String(b["slot"]))
	_icons[key] = tex
	return tex


static func god_icon(god: String) -> Texture2D:
	var key := "god:" + god
	if _icons.has(key):
		return _icons[key]
	var path := "res://assets/ui/gods/%s.png" % god
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		tex = _make_icon(god_color(god), Color(1, 1, 1), "god")
	_icons[key] = tex
	return tex


static func _make_icon(c: Color, frame: Color, slot: String) -> Texture2D:
	const S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ctr := (S - 1) * 0.5
	for y in S:
		for x in S:
			var d := absf(x - ctr) + absf(y - ctr)   # ромб
			if d <= 30.0:
				var col: Color
				if d > 26.5:
					col = frame
				elif d > 24.5:
					col = c.darkened(0.6)
				else:
					var t := d / 24.5
					col = c.lightened(0.25).lerp(c.darkened(0.45), t)
				img.set_pixel(x, y, col)
	var g := Color(1, 1, 1, 0.95)
	match slot:
		"attack":   # клинок
			for i in range(14, 50):
				for w in range(-2, 3):
					img.set_pixel(32 + w + (50 - i) / 12, i, g)
			for w in range(-8, 9):
				img.set_pixel(32 + w, 42, g)
				img.set_pixel(32 + w, 43, g)
		"special":  # звезда
			for i in range(-14, 15):
				for w in range(-1, 2):
					img.set_pixel(32 + i, 32 + w, g)
					img.set_pixel(32 + w, 32 + i, g)
					if absi(i) < 10:
						img.set_pixel(32 + i, 32 + i + w, g)
						img.set_pixel(32 + i, 32 - i + w, g)
		"dash":     # двойной шеврон
			for k in 2:
				for i in range(0, 11):
					for w in range(-1, 2):
						img.set_pixel(22 + k * 10 + i, 22 + i + w, g)
						img.set_pixel(22 + k * 10 + i, 42 - i + w, g)
		"passive":  # кольцо
			for y in S:
				for x in S:
					var r := Vector2(x - ctr, y - ctr).length()
					if r > 8.0 and r < 12.0:
						img.set_pixel(x, y, g)
		_:          # дух — круг
			for y in S:
				for x in S:
					if Vector2(x - ctr, y - ctr).length() < 9.0:
						img.set_pixel(x, y, g)
	return ImageTexture.create_from_image(img)
