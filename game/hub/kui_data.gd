class_name KuiData
extends RefCounted
## Кюи для домбры: мелодии 3–4 такта (по 4 доли). Нота: {fret: 0..6 (0 — открытые струны), stroke: "down"|"up"|"trem", beat: доля от начала}.
## Перед мелодией — 1 такт отсчёта метронома (COUNT_IN долей). Окно попадания ±WINDOW с.
## Баффы (Музыкальный заряд) описаны в Run.KUIS (ядро); здесь — только ноты и подсказки.

const WINDOW := 0.18
const COUNT_IN := 4
## Лады — полутоны от открытой струны (как в tools/make_dombra.py): 0, 2, 3, 5, 7, 9, 10
const SEMITONES := [0, 2, 3, 5, 7, 9, 10]
const FRET_NAMES := ["откр.", "1", "2", "3", "4", "5", "6"]
const STROKE_NAMES := {"down": "қағыс ↓", "up": "подцеп ↑", "trem": "тремоло ≈"}

const KUIS := {
	"adai": {"title": "Адай", "bpm": 100, "story": "Кони несутся по степи — кюй Құрманғазы.",
		"notes": [
			{"fret": 0, "stroke": "down", "beat": 0.0}, {"fret": 0, "stroke": "up", "beat": 0.5},
			{"fret": 3, "stroke": "down", "beat": 1.0}, {"fret": 2, "stroke": "down", "beat": 2.0},
			{"fret": 0, "stroke": "up", "beat": 2.5}, {"fret": 3, "stroke": "down", "beat": 3.0},
			{"fret": 4, "stroke": "down", "beat": 4.0}, {"fret": 3, "stroke": "up", "beat": 4.5},
			{"fret": 2, "stroke": "down", "beat": 5.0}, {"fret": 0, "stroke": "trem", "beat": 6.0},
			{"fret": 5, "stroke": "down", "beat": 8.0}, {"fret": 4, "stroke": "down", "beat": 9.0},
			{"fret": 3, "stroke": "up", "beat": 9.5}, {"fret": 2, "stroke": "down", "beat": 10.0},
			{"fret": 0, "stroke": "down", "beat": 11.0},
		]},
	"korkyt": {"title": "Қорқыт", "bpm": 72, "story": "Плач Қорқыта, бежавшего от смерти по всей земле.",
		"notes": [
			{"fret": 0, "stroke": "trem", "beat": 0.0}, {"fret": 2, "stroke": "down", "beat": 2.0},
			{"fret": 3, "stroke": "down", "beat": 3.0}, {"fret": 5, "stroke": "trem", "beat": 4.0},
			{"fret": 4, "stroke": "up", "beat": 6.0}, {"fret": 3, "stroke": "down", "beat": 7.0},
			{"fret": 2, "stroke": "trem", "beat": 8.0}, {"fret": 0, "stroke": "down", "beat": 11.0},
		]},
	"aksak_kulan": {"title": "Ақсақ құлан", "bpm": 96, "story": "Хромой кулан — весть о гибели сына хана.",
		"notes": [
			{"fret": 1, "stroke": "down", "beat": 0.0}, {"fret": 1, "stroke": "up", "beat": 0.5},
			{"fret": 3, "stroke": "down", "beat": 1.5}, {"fret": 1, "stroke": "down", "beat": 2.0},
			{"fret": 0, "stroke": "up", "beat": 3.0}, {"fret": 4, "stroke": "down", "beat": 4.0},
			{"fret": 4, "stroke": "up", "beat": 4.5}, {"fret": 3, "stroke": "down", "beat": 5.5},
			{"fret": 1, "stroke": "down", "beat": 6.0}, {"fret": 0, "stroke": "down", "beat": 8.0},
			{"fret": 2, "stroke": "up", "beat": 9.0}, {"fret": 0, "stroke": "trem", "beat": 10.0},
		]},
	"balbyrauyn": {"title": "Балбырауын", "bpm": 112, "story": "Плясовой кюй — пальцы бегут быстрее мысли.",
		"notes": [
			{"fret": 0, "stroke": "down", "beat": 0.0}, {"fret": 2, "stroke": "down", "beat": 1.0},
			{"fret": 3, "stroke": "up", "beat": 1.5}, {"fret": 5, "stroke": "down", "beat": 2.0},
			{"fret": 3, "stroke": "down", "beat": 3.0}, {"fret": 6, "stroke": "down", "beat": 4.0},
			{"fret": 5, "stroke": "up", "beat": 4.5}, {"fret": 3, "stroke": "down", "beat": 5.0},
			{"fret": 2, "stroke": "down", "beat": 6.0}, {"fret": 0, "stroke": "up", "beat": 6.5},
			{"fret": 2, "stroke": "down", "beat": 8.0}, {"fret": 3, "stroke": "down", "beat": 9.0},
			{"fret": 0, "stroke": "trem", "beat": 10.0},
		]},
	"kenes": {"title": "Кеңес", "bpm": 84, "story": "Совет старейшин — неторопливый и твёрдый.",
		"notes": [
			{"fret": 0, "stroke": "down", "beat": 0.0}, {"fret": 0, "stroke": "down", "beat": 1.0},
			{"fret": 4, "stroke": "down", "beat": 2.0}, {"fret": 3, "stroke": "up", "beat": 3.0},
			{"fret": 2, "stroke": "down", "beat": 4.0}, {"fret": 4, "stroke": "trem", "beat": 6.0},
			{"fret": 5, "stroke": "down", "beat": 8.0}, {"fret": 3, "stroke": "down", "beat": 9.0},
			{"fret": 2, "stroke": "up", "beat": 10.0}, {"fret": 0, "stroke": "down", "beat": 11.0},
		]},
}


static func has(id: String) -> bool:
	return KUIS.has(id)


static func notes(id: String) -> Array:
	return KUIS.get(id, {}).get("notes", [])


static func beat_len(id: String) -> float:
	return 60.0 / float(KUIS.get(id, {}).get("bpm", 100))


## Время ноты i от начала кюя (с учётом такта отсчёта), сек.
static func note_time(id: String, i: int) -> float:
	var ns := notes(id)
	if i < 0 or i >= ns.size():
		return -1.0
	return (COUNT_IN + float(ns[i]["beat"])) * beat_len(id)


## Длина кюя (до последней доли последнего такта), сек.
static func length(id: String) -> float:
	var ns := notes(id)
	if ns.is_empty():
		return 0.0
	var last := float(ns[ns.size() - 1]["beat"])
	return (COUNT_IN + ceilf((last + 1.0) / 4.0) * 4.0) * beat_len(id)


static func title(id: String) -> String:
	if Run.KUIS.has(id):
		return str(Run.KUIS[id]["title"])
	return str(KUIS.get(id, {}).get("title", id))


## Доступные игроку кюи: открытые Забытые ноты; если ни одного — «Адай» (подарок Әже).
static func available() -> Array:
	var out: Array = []
	for id in Meta.kuis_unlocked:
		if KUIS.has(str(id)) and not (str(id) in out):
			out.append(str(id))
	if out.is_empty():
		out.append("adai")
	return out
