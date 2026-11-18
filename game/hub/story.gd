class_name Story
extends RefCounted
## Сюжет «Корни Забвения». Короткие сценки в Хабе после каждой смерти / победы и разговоры с NPC.
## Тайна раскрывается постепенно: намёки → находка (тамга хана в логове Жест) → легенда → признание
## после победы над финальным боссом «khan»: Мглу Кара-Тұман впустил первый хан рода, Ерден, ради бессмертия.
##
## API:
##   Story.on_hub_enter() -> Array      — реплики при входе в Хаб (по Meta.story, Meta.last_run, Run.hub_reason);
##                                        двигает Meta.story.step, отмечает seen, сбрасывает Run.hub_reason. [] — нечего сказать.
##   Story.pick_scene(state) -> String  — чистая функция выбора сценки (для тестов). state = Story.current_state()
##   Story.scene_lines(id, state) -> Array
##   Story.talk(npc_id) -> Array        — повторный разговор с NPC ("aje", "root", "usta")
##   Story.NPCS                         — {id: {name, color}}
## Реплика: {"speaker": String, "text": String, "color": Color}

const NPCS := {
	"aje": {"name": "Әже Ұлжан", "color": Color(0.95, 0.78, 0.5)},
	"root": {"name": "Дух-Корень Байтерека", "color": Color(0.45, 0.95, 0.85)},
	"usta": {"name": "Ұста Темірбек", "color": Color(0.95, 0.6, 0.4)},
	"hero": {"name": "Кайсар", "color": Color(0.75, 0.85, 1.0)},
}

## Главные сценки по порядку. need — условие (см. _cond), step — какой шаг ставится.
const MAIN := [
	{"id": "intro", "step": 1, "need": "first"},
	{"id": "roots_first", "step": 2, "need": "death"},
	{"id": "hint_balbal", "step": 3, "need": "death"},
	{"id": "hint_wound", "step": 4, "need": "death"},
	{"id": "find_tamga", "step": 5, "need": "biome1"},
	{"id": "hint_eternity", "step": 6, "need": "biome2"},
	{"id": "aje_legend", "step": 7, "need": "any"},
	{"id": "khan_confession", "step": 8, "need": "khan"},
	{"id": "epilogue", "step": 9, "need": "victory"},
]

## Боссы биомов, после победы над которыми в Хабе есть своя сцена (по порядку).
const AFTER_BOSS := ["zhest", "shoyyn"]

const KILLERS := {
	"wolf": "Волки Мглы загнали тебя, как сайгака. Помни: волк бьёт с фланга — не подставляй спину.",
	"spirit": "Блуждающие духи… Когда-то они были нашими. Мгла выпила их имена.",
	"balbal": "Каменный балбал поднялся против тебя. Даже камни предков Мгла сделала своими стражами.",
	"archer": "Стрела из тумана. Лучники Мглы не видят тебя — они слышат твой страх. Двигайся, не стой.",
	"shaman": "Чёрный бақсы. Он шепчет имена мёртвых, чтобы те вставали снова. Бей его первым.",
	"acrobat": "Тень-плясун. Его не прервёшь лёгким ударом — уклоняйся или бей тяжело, сынок.",
	"zhest": "Жест, медная ведьма степи. Она призывает свору и прыгает, как рысь. Жди её прыжка — и бей, когда приземлится.",
	"shoyyn": "Шойын-великан. Его броню не пробить, пока не собьёшь щитом или тяжёлым ударом.",
	"khan": "Тот, кто сидит на троне в сердце Мглы… Он знал каждый твой шаг, будто сам тебя учил.",
	"fall": "Пропасть приняла тебя. Корни подхватили — на этот раз.",
}

## Разговоры с NPC: по стадиям (0 — начало, 1 — середина, 2 — после правды). Каждый вызов — следующая реплика.
const TALK := {
	"aje": [
		["Садись у огня, Кайсар. Домбра помнит песни, которые люди забыли. Сыграй — и оружие запоёт с тобой.",
			"Кюй «Адай» — бег коней по степи. Сыграй его чисто перед дорогой, и твой рывок станет быстрее ветра.",
			"Пепел Тамыра не сгорает. Неси его в Сандык — предки отдадут свою силу тому, кто помнит их."],
		["Ерден хан… Его имя у нас не произносят у очага. Я сама не знаю почему — так велели старшие.",
			"Забытые ноты рассыпаны по логовам Мглы. Принеси их — я научу тебя новым кюям.",
			"Корни возвращают тебя, но каждая смерть забирает у них силу. Не трать её зря, жаным."],
		["Правда горька, как полынь. Но полынь лечит. Байтерек дышит, слышишь?",
			"Ерден хотел жить вечно — и стал ничем. А ты живёшь, пока тебя помнят. Это и есть бессмертие.",
			"Сыграй мне, Кайсар. Теперь домбра звучит иначе — светлее."],
	],
	"root": [
		["…Хранитель… огонь рода… в тебе. Пока он горит — мы вернём тебя.",
			"…Мгла… внутри… не снаружи… ищи…",
			"…Мы держим тебя… корнями… не бойся смерти… бойся забвения…"],
		["…Рана… изнутри… кто-то открыл нас… своей рукой… своей кровью…",
			"…Тамга… круг и ключ… мы помним эту руку…",
			"…Его клятва… Ерлику… мы слышали… под землёй…"],
		["…Мы… дышим… Кайсар… свет возвращается в листья…",
			"…Хан ушёл в землю… как должен был… тысячу лет назад…",
			"…Иди… хранитель… Мгла слабеет, но не исчезла…"],
	],
	"usta": [
		["Клинок — продолжение руки, батыр. Возьми любое оружие со стоек и проверь на чучеле.",
			"Чучело не умирает — сколько ни руби. Смотри на цифры: обычный удар, особый, крит. И на DPS над головой.",
			"Аспекты — это души прежних владельцев оружия. Пепел разбудит их."],
		["Щитом сбивай броню, перчатками подбрасывай. Врага, что врезался в колонну, и добивать не надо.",
			"Копьё Томирис я ковал по рассказам деда. Говорят, она возвращалась к копью быстрее молнии.",
			"Отскочи от стены и ударь особой в полёте — сверху вниз. Броня трескается, как лёд весной."],
		["Тамгу Ердена я переплавил в подкову. Пусть топчет её каждый конь в стойбище.",
			"Оружие поёт, когда ты сыграешь кюй перед дорогой. Я слышу это в звоне стали.",
			"Хорошая работа, батыр. Но стоек у меня ещё много — приходи."],
	],
}


# ================================================================ состояние
static func current_state() -> Dictionary:
	return {
		"step": int(Meta.story.get("step", 0)),
		"seen": Array(Meta.story.get("seen", [])),
		"reason": Run.hub_reason,
		"last_run": Meta.last_run.duplicate(),
		"runs": int(Meta.stats.get("runs", 0)),
		"deaths": int(Meta.stats.get("deaths", 0)),
	}


static func _cond(need: String, st: Dictionary) -> bool:
	var lr: Dictionary = st.get("last_run", {})
	var reason: String = st.get("reason", "")
	match need:
		"first":
			return true
		"death":
			return reason == "death"
		"any":
			return reason != ""
		"biome1":
			return reason != "" and int(lr.get("biome", 0)) >= 1
		"biome2":
			return reason != "" and int(lr.get("biome", 0)) >= 2
		"khan":
			return reason == "victory" and str(lr.get("boss", "")) == "khan"
		"victory":
			return reason == "victory"
	return false


## Какая сценка подходит. Пусто — нечего показывать.
static func pick_scene(st: Dictionary) -> String:
	var seen: Array = st.get("seen", [])
	var step: int = st.get("step", 0)
	if not ("intro" in seen):
		return "intro"
	var reason: String = st.get("reason", "")
	if reason == "":
		return ""
	# победа над ханом — всегда признание (если ещё не было)
	if _cond("khan", st) and not ("khan_confession" in seen):
		return "khan_confession"
	# забег закончился смертью, но в нём пал новый владыка биома — сначала сцена «после босса»
	var after_boss := boss_scene(st)
	if after_boss != "":
		return after_boss
	for i in range(1, MAIN.size()):
		var m: Dictionary = MAIN[i]
		if m["id"] in seen:
			continue
		if m["id"] == "khan_confession" or m["id"] == "epilogue":
			continue
		# главные сцены идут по порядку: не перескакиваем больше чем на одну
		if int(m["step"]) - 1 > step + 1 and m["need"] in ["death", "any"]:
			continue
		if _cond(str(m["need"]), st):
			# находки (biome1/2) можно показать только после первых намёков
			if m["need"] == "biome1" and step < 2:
				continue
			if m["need"] == "biome2" and not ("find_tamga" in seen):
				continue
			if m["id"] == "aje_legend" and not ("hint_eternity" in seen):
				continue
			return m["id"]
		if m["need"] == "death" or m["need"] == "any":
			# незакрытый главный шаг: дальше по списку не идём
			break
	if reason == "victory":
		return "epilogue" if not ("epilogue" in seen) else "victory_again"
	return "death_flavor"


## Сцена «после босса» (boss_zhest_seen / boss_shoyyn_seen), если в последнем забеге убит босс биома,
## о котором ещё не говорили. Только при возвращении после смерти (победа — свои сцены).
static func boss_scene(st: Dictionary) -> String:
	if str(st.get("reason", "")) != "death":
		return ""
	var lr: Dictionary = st.get("last_run", {})
	var bk = lr.get("bosses_killed", [])
	if not (bk is Array):
		return ""
	var seen: Array = st.get("seen", [])
	for b in AFTER_BOSS:
		var sid := "boss_%s_seen" % b
		if b in bk and not (sid in seen):
			return sid
	return ""


static func _l(who: String, text: String) -> Dictionary:
	var n: Dictionary = NPCS.get(who, {"name": who, "color": Color(1, 1, 1)})
	return {"speaker": n["name"], "text": text, "color": n["color"]}


static func _depth_text(lr: Dictionary) -> String:
	var d := int(lr.get("depth", 0)) + 1
	var places := ["в Осквернённой степи", "у Корней Байтерека", "в Чертоге Ерлика"]
	var b := clampi(int(lr.get("biome", 0)), 0, 2)
	return "%s, на %d-м привале пути" % [places[b], d]


static func scene_lines(id: String, st: Dictionary) -> Array:
	var lr: Dictionary = st.get("last_run", {})
	match id:
		"intro":
			return [
				_l("aje", "Очнулся, Кайсар? Корни Байтерека принесли тебя к очагу. Значит, ты им ещё нужен."),
				_l("aje", "Древо-Мира болеет. С востока ползёт Кара-Тұман — чёрная Мгла. Она пьёт имена предков, и они забывают, кем были."),
				_l("root", "…Хранитель… последний огонь рода… в твоей груди… Пока он горит — мы вернём тебя… сколько бы раз ты ни пал…"),
				_l("hero", "Тогда я пойду по тропе в корни и выжгу эту Мглу."),
				_l("aje", "Пойдёшь. Но возьми с собой песню. Вот, «Адай» — кюй о бегущих конях. Сыграй его на домбре у костра перед дорогой."),
				_l("aje", "Дирхемы сгорят вместе с тобой, если падёшь. Пепел Тамыра — нет. Неси его в Сандык, в нашу юрту."),
			]
		"roots_first":
			return [
				_l("root", "…Мы поймали тебя… корни глубоки… но каждый раз… тяжелее…"),
				_l("aje", "Вернулся. Я видела, как огонь вспыхнул зелёным — так корни приносят хранителя."),
				_l("aje", _killer_line(lr)),
				_l("aje", "Мгла пришла не сама. Мой дед говорил: «Туман не заходит в юрту, если хозяин не откинул полог». Подумай над этим."),
			]
		"hint_balbal":
			return [
				_l("aje", "Знаешь, почему наши балбалы смотрят на запад, к закату? Чтобы предки провожали солнце."),
				_l("aje", "Все — кроме одного. Балбал первого хана, Ердена, смотрит на восток. Туда, откуда пришла Мгла."),
				_l("hero", "Кто его так поставил?"),
				_l("aje", "Говорят — он сам велел. Ещё при жизни. Странный приказ для того, кто собирался умирать."),
			]
		"hint_wound":
			return [
				_l("root", "…Больно… Кайсар… рана не снаружи… изнутри…"),
				_l("root", "…Кто-то открыл нас… своей рукой… кровью рода… мы впустили, потому что узнали кровь…"),
				_l("hero", "Кровью рода? Значит, Мглу впустил один из нас?"),
				_l("root", "…Ищи… в логове… медной ведьмы… там его знак…"),
			]
		"find_tamga":
			return [
				_l("hero", "В логове Жест я нашёл вот это. Золотая тамга: круг и ключ. Она была вбита в корень, как гвоздь."),
				_l("aje", "…Это тамга нашего рода. Самая первая. Такую носил только Ерден хан."),
				_l("root", "…Да… эта рука… открыла нас… мы помним её тепло… и её холод…"),
				_l("aje", "Не говори никому в стойбище, Кайсар. Пока мы не узнаем всего."),
			]
		"hint_eternity":
			return [
				_l("root", "…Мгла питается… обещанием… «мәңгілік»… вечность…"),
				_l("root", "…Кто-то попросил… вечной жизни… у Ерлика… Ерлик дал… и взял плату…"),
				_l("hero", "Какую плату?"),
				_l("root", "…Память рода… имена… всех, кто придёт после… мы платим до сих пор…"),
			]
		"aje_legend":
			return [
				_l("aje", "Я долго молчала, Кайсар. Есть старая песня, её пели шёпотом. Про хана, что боялся смерти больше, чем позора."),
				_l("aje", "Он ушёл в Чертог Ерлика и вернулся с чёрной чашей. Выпил — и не постарел. А с востока потянуло холодом."),
				_l("aje", "Песню запретили. Певцов — забыли. Мгла выпила их имена первыми."),
				_l("hero", "Значит, хан до сих пор жив. Там, в сердце Мглы."),
				_l("aje", "Если это так — ты встретишь его. Помни: он твой предок. Но предок — не значит правый."),
			]
		"khan_confession":
			return [
				_l("hero", "Он пал. Ерден хан. На троне из корней, в чёрной короне."),
				_l("root", "…Его последние слова… мы услышали…"),
				_l("root", "…«Я впустил Мглу. Я открыл корни своей кровью, чтобы Ерлик дал мне вечность. Я думал — род будет жить мной вечно»…"),
				_l("root", "…«Но вечность съела мой род. Имена… песни… я один помнил их… и сам стал Мглой»…"),
				_l("aje", "Вот и всё. Тысяча лет страха — и одна чаша. Он не хотел умирать, Кайсар, и потому убил всех нас понемногу."),
				_l("aje", "Теперь его имя можно произнести у огня. Пусть его помнят — как предостережение."),
				_l("root", "…Мы дышим… Байтерек… просыпается… спасибо… хранитель…"),
			]
		"epilogue":
			return [
				_l("aje", "Ты снова вернулся с победой. Мгла редеет, но корни ещё больны — ей тысяча лет."),
				_l("root", "…Каждая твоя победа… возвращает одно имя… мы вспоминаем…"),
			]
		"victory_again":
			return [
				_l("aje", "Ещё один круг, ещё одна победа. Сегодня ко мне вернулось имя моей прабабки — Ақбөпе. Спасибо, жаным."),
			]
		"boss_zhest_seen":
			return [
				_l("aje", "Жезтырнақ пала от твоей руки? Медная ведьма, что пугала детей ещё при моей бабке…"),
				_l("hero", "Её когти пахли не степью, Әже. Мглой. Будто кто-то кормил её из чужой чаши."),
				_l("root", "…Ведьма… была стражем… кто-то поставил её… у входа в корни…"),
				_l("aje", _killer_line(lr)),
			]
		"boss_shoyyn_seen":
			return [
				_l("hero", "Шойынқұлақ повержен. Чугунное Ухо слышало зов из-под корней — кто-то позвал Мглу по имени."),
				_l("root", "…Зов… был голосом рода… мы узнали его… и не смогли не открыть…"),
				_l("aje", "Голосом рода… Значит, искать надо не в степи, а у себя в юрте. Будь осторожен, Кайсар."),
				_l("aje", _killer_line(lr)),
			]
		"death_flavor":
			var lines: Array = [_l("aje", _killer_line(lr))]
			var d := int(st.get("deaths", 0))
			var extra := [
				"Ты пал %s. Отдохни у огня. Корни ждут." % _depth_text(lr),
				"Пепел, что ты принёс, не пропадёт. Загляни в Сандык.",
				"Сыграй на домбре перед дорогой — путь станет легче.",
				"Ұста говорит, ты слишком любишь один и тот же клинок. Попробуй другое оружие.",
			]
			lines.append(_l("aje" if d % 2 == 0 else "root", extra[d % extra.size()] if d % 2 == 0 else "…Мы держим… тебя… иди снова…"))
			return lines
	return []


static func _killer_line(lr: Dictionary) -> String:
	var k := str(lr.get("killer", ""))
	for key in KILLERS:
		if k.begins_with(key) or k.to_lower().contains(key):
			return KILLERS[key]
	if k == "":
		return "Ты пал %s. Корни подхватили тебя." % _depth_text(lr)
	return "Ты пал %s. Мгла сильна, но и ты учишься." % _depth_text(lr)


## Реплики при входе в Хаб (с побочными эффектами).
static func on_hub_enter() -> Array:
	var st := current_state()
	var id := pick_scene(st)
	Run.hub_reason = ""
	if id == "":
		return []
	var lines := scene_lines(id, st)
	_mark(id)
	if id == "intro":
		Meta.unlock_kui("adai")
	if id == "find_tamga":
		Meta.story["flags"]["tamga"] = true
	if id == "khan_confession":
		Meta.story["flags"]["truth"] = true
	Meta.save_game()
	return lines


static func _mark(id: String) -> void:
	var seen: Array = Meta.story.get("seen", [])
	if not (id in seen):
		seen.append(id)
	Meta.story["seen"] = seen
	for m in MAIN:
		if m["id"] == id:
			Meta.story["step"] = maxi(int(Meta.story.get("step", 0)), int(m["step"]))


## Стадия для разговоров: 0 — до находки, 1 — после тамги, 2 — после правды.
static func stage() -> int:
	var seen: Array = Meta.story.get("seen", [])
	if "khan_confession" in seen:
		return 2
	if "find_tamga" in seen or "hint_wound" in seen:
		return 1
	return 0


static func talk(npc_id: String) -> Array:
	if not TALK.has(npc_id):
		return []
	var flags: Dictionary = Meta.story.get("flags", {})
	var key := "talk_" + npc_id
	var n := int(flags.get(key, 0))
	flags[key] = n + 1
	Meta.story["flags"] = flags
	var pool: Array = TALK[npc_id][stage()]
	var lines: Array = [_l(npc_id, pool[n % pool.size()])]
	# Әже в начале напоминает про подарок-кюй
	if npc_id == "aje" and Meta.kuis_unlocked.is_empty():
		Meta.unlock_kui("adai")
		lines.append(_l("aje", "Держи «Адай». Сядь у костра, возьми домбру."))
	if npc_id == "usta":
		lines.append(_l("usta", "В руках у тебя — %s. Пепла: %d." % [str(WeaponRack.weapon_info(Meta.equipped_weapon).get("title", Meta.equipped_weapon)), Meta.ash]))
	return lines
