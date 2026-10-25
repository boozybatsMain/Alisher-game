extends RefCounted
## Дары богов (как Boons в Hades).
## Слоты под ХП-баром: 0 — модификатор удара саблей, 1 — эффект рывка/кувырка, 2 — эффект щита/парирования.

const GOD_ORDER := ["tengri", "umai", "ot_ana"]

const GODS := {
	"tengri": {"name": "Тенгри", "title": "Небесный Отец", "color": Color(0.55, 0.8, 1.0)},
	"umai": {"name": "Умай", "title": "Мать-Покровительница", "color": Color(0.6, 0.95, 0.5)},
	"ot_ana": {"name": "От-Ана", "title": "Мать Огня", "color": Color(1.0, 0.55, 0.25)},
}

const SLOT_NAMES := ["Удар сабли", "Рывок", "Щит"]

const INFO := {
	"tengri": [
		{"name": "Гнев Тенгри", "desc": "Удар сабли с шансом {chance}% бьёт молнией по соседнему врагу: {dmg} урона."},
		{"name": "Громовой шаг", "desc": "В конце кувырка или рывка бьёт молния: {dmg} урона вокруг."},
		{"name": "Небесный щит", "desc": "Идеальный блок выпускает молнии во всех врагов рядом: {dmg} урона."},
	],
	"umai": [
		{"name": "Ладонь Умай", "desc": "Каждый попавший удар сабли лечит на {heal} HP."},
		{"name": "Крылья Умай", "desc": "Кувырок перезаряжается на {save}% быстрее и лечит на {heal} HP."},
		{"name": "Объятие Умай", "desc": "Идеальный блок лечит на {heal} HP и мгновенно перезаряжает кувырок."},
	],
	"ot_ana": [
		{"name": "Пламя От-Аны", "desc": "Удары сабли поджигают врагов: {dps} урона в секунду, 3 секунды."},
		{"name": "Огненный след", "desc": "Кувырок оставляет горящий след: {dps} урона в секунду."},
		{"name": "Жар очага", "desc": "Идеальный блок поджигает врага ({dps} урона в секунду) и оглушает дольше."},
	],
}


static func value(god: String, slot: int, level: int) -> Dictionary:
	var l := clampi(level, 1, 3) - 1
	match god:
		"tengri":
			match slot:
				0: return {"chance": [35, 50, 65][l], "dmg": [12, 18, 26][l]}
				1: return {"dmg": [22, 34, 48][l]}
				2: return {"dmg": [28, 42, 60][l]}
		"umai":
			match slot:
				0: return {"heal": [2, 3, 4][l]}
				1: return {"save": [40, 55, 70][l], "heal": [3, 5, 7][l]}
				2: return {"heal": [10, 15, 20][l]}
		"ot_ana":
			match slot:
				0: return {"dps": [6, 9, 13][l]}
				1: return {"dps": [10, 15, 22][l]}
				2: return {"dps": [12, 18, 26][l]}
	return {}


static func gift_name(god: String, slot: int) -> String:
	return INFO[god][slot]["name"]


static func describe(god: String, slot: int, level: int) -> String:
	var text: String = INFO[god][slot]["desc"]
	var v := value(god, slot, level)
	for k in v:
		text = text.replace("{%s}" % k, str(v[k]))
	return text


static func icon_path(god: String, slot: int) -> String:
	return "res://assets/ui/icons/%s_%d.png" % [god, slot]


static func emblem_path(god: String) -> String:
	return "res://assets/ui/gods/%s.png" % god
