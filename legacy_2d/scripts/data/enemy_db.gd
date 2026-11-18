extends RefCounted
## Враги и боссы: характеристики и удары.
##
## Тайминг удара задаётся кадрами анимации: «telegraph» — кадры замаха (враг подсвечивается красным,
## это время на реакцию), «hits» — на каком кадре наносится урон. Длительности кадров лежат в SpriteFrames
## (tools/build_assets.py), поэтому один и тот же враг может бить медленно с долгим замахом или быстро.
##
## Поля удара:
##   anim, range [min,max] — с какой дистанции враг выбирает этот удар, cooldown, weight
##   telegraph [кадры], start — с какого кадра начать (быстрый вариант удара), speed — множитель скорости анимации
##   hits [{frame, reach [от,до] перед собой | radius (по кругу), dmg, knock, parry, block}]
##   lunge {frame, speed} — рывок вперёд; leap {from, to, height} — прыжок к герою; dash {from, to, speed} — бросок с уроном касанием
##   projectile {frame, kind, speed, dmg, y, count, interval, both}
##   smear {frame, radius, color} — дуга удара; impact {frame, x, shake} — пыль и тряска от удара о землю
##   summon {frame, kind, count}; hp_below — удар доступен только когда здоровье ниже доли (призыв боссов)

const DB := {
	"balbal": {
		"name": "Балбал", "frames": "res://assets/sprites/balbal/balbal_frames.tres", "ai": "melee",
		"hp": 170, "speed": 150.0, "radius": 70.0, "bar_y": -285.0, "knock_mult": 0.35,
		"armored": true, "poise": 30.0, "stun": 1.6, "asyks": [3, 4],
		"move_anim": "walk", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			{"anim": "attack", "range": [0, 320], "cooldown": 1.3, "telegraph": [0, 1], "combo": 0.5, "combo_from": 1,
			 "hits": [{"frame": 2, "reach": [-80, 330], "dmg": 24, "knock": 560, "parry": true, "block": true}],
			 "lunge": {"frame": 2, "speed": 460}, "smear": {"frame": 2, "radius": 300, "color": "fire"},
			 "impact": {"frame": 3, "x": 230, "shake": 9.0}},
		],
	},
	"spirit": {
		"name": "Дух степи", "frames": "res://assets/sprites/spirit/spirit_frames.tres", "ai": "melee",
		"hp": 60, "speed": 270.0, "radius": 50.0, "bar_y": -230.0, "knock_mult": 1.2, "hover": 40.0,
		"armored": false, "poise": 0.0, "stun": 1.3, "asyks": [1, 2],
		"move_anim": "float", "idle_anim": "float", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			{"anim": "attack", "range": [100, 440], "cooldown": 1.5, "telegraph": [0, 1],
			 "dash": {"from": 2, "to": 3, "speed": 860},
			 "hits": [{"frame": -1, "dmg": 12, "knock": 380, "parry": true, "block": true}]},
		],
	},
	"wolf": {
		"name": "Чёрный волк", "frames": "res://assets/sprites/wolf/wolf_frames.tres", "ai": "melee",
		"hp": 80, "speed": 440.0, "radius": 60.0, "bar_y": -180.0, "knock_mult": 1.0,
		"armored": false, "poise": 0.0, "stun": 1.2, "asyks": [1, 2],
		"move_anim": "run", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			# прыжок с дистанции: короткий замах, длинный полёт
			{"anim": "attack", "range": [190, 470], "cooldown": 1.7, "telegraph": [0], "speed": 0.85,
			 "leap": {"from": 1, "to": 2, "height": 80.0},
			 "hits": [{"frame": 2, "reach": [-40, 170], "dmg": 14, "knock": 420, "parry": true, "block": true}]},
			# быстрый укус вплотную: почти без замаха, слабее
			{"anim": "attack", "range": [0, 175], "cooldown": 1.2, "speed": 0.85, "telegraph": [0],
			 "hits": [{"frame": 2, "reach": [-30, 160], "dmg": 8, "knock": 260, "parry": true, "block": true}]},
		],
	},
	"archer": {
		"name": "Аруақ-мерген", "frames": "res://assets/sprites/archer/archer_frames.tres", "ai": "ranged",
		"hp": 70, "speed": 150.0, "radius": 55.0, "bar_y": -265.0, "knock_mult": 1.0, "keep": [380.0, 680.0],
		"armored": false, "poise": 0.0, "stun": 1.5, "asyks": [2, 3],
		"move_anim": "walk", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			{"anim": "attack", "range": [200, 950], "cooldown": 1.9, "telegraph": [0, 1],
			 "projectile": {"frame": 2, "kind": "arrow", "speed": 980.0, "dmg": 14, "y": -150.0}},
		],
	},
	"shaman": {
		"name": "Бақсы", "frames": "res://assets/sprites/shaman/shaman_frames.tres", "ai": "caster",
		"hp": 115, "speed": 115.0, "radius": 55.0, "bar_y": -270.0, "knock_mult": 0.8, "keep": [340.0, 640.0],
		"armored": false, "poise": 12.0, "stun": 1.5, "asyks": [4, 5], "teleport": true,
		"summon": {"kind": "spirit", "every": 9.0, "max": 2},
		"move_anim": "walk", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "hurt", "death_anim": "death",
		"attacks": [
			{"anim": "attack", "range": [180, 950], "cooldown": 2.7, "telegraph": [0, 1],
			 "projectile": {"frame": 3, "kind": "orb", "speed": 300.0, "dmg": 13, "y": -150.0, "count": 3, "interval": 0.24}},
		],
	},
	# ------------------------------------------------------------------ боссы
	"zhest": {
		"name": "Жезтырнак — Медный Коготь", "frames": "res://assets/sprites/zhest/zhest_frames.tres", "ai": "boss",
		"hp": 680, "speed": 230.0, "radius": 70.0, "bar_y": -360.0, "knock_mult": 0.25,
		"armored": true, "poise": 110.0, "stun": 1.1, "asyks": [18, 22], "boss": true, "enrage": 0.4,
		"move_anim": "walk", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			{"anim": "attack", "range": [0, 230], "cooldown": 1.4, "telegraph": [0], "weight": 3.0,
			 "hits": [{"frame": 1, "reach": [-40, 250], "dmg": 15, "knock": 360, "parry": true, "block": true},
					  {"frame": 2, "reach": [-40, 250], "dmg": 15, "knock": 480, "parry": true, "block": true}],
			 "lunge": {"frame": 1, "speed": 420}, "smear": {"frame": 1, "radius": 240, "color": "blood"}},
			{"anim": "leap", "range": [280, 1500], "cooldown": 3.6, "telegraph": [0], "weight": 2.0,
			 "leap": {"from": 1, "to": 3, "height": 170.0},
			 "hits": [{"frame": 3, "radius": 175.0, "dmg": 20, "knock": 520, "parry": false, "block": true}],
			 "impact": {"frame": 3, "x": 0, "shake": 12.0}},
			{"anim": "summon", "range": [0, 2000], "cooldown": 14.0, "telegraph": [], "hp_below": 0.7, "weight": 6.0,
			 "summon": {"frame": 3, "kind": "spirit", "count": 2}},
		],
	},
	"shoyyn": {
		"name": "Шойынқұлақ — Чугунное Ухо", "frames": "res://assets/sprites/shoyyn/shoyyn_frames.tres", "ai": "boss",
		"hp": 1350, "speed": 150.0, "radius": 120.0, "bar_y": -540.0, "knock_mult": 0.1,
		"armored": true, "poise": 200.0, "stun": 1.0, "asyks": [40, 50], "boss": true, "enrage": 0.5,
		"move_anim": "walk", "idle_anim": "idle", "hurt_anim": "hurt", "stun_anim": "stun", "death_anim": "death",
		"attacks": [
			# удар сверху: долгий замах, можно идеально заблокировать; от земли идёт ударная волна — её только перекатить
			{"anim": "smash", "range": [0, 360], "cooldown": 2.0, "telegraph": [0, 1], "weight": 3.0,
			 "hits": [{"frame": 2, "reach": [-60, 380], "dmg": 27, "knock": 620, "parry": true, "block": true}],
			 "smear": {"frame": 2, "radius": 340, "color": "fire"}, "impact": {"frame": 3, "x": 300, "shake": 16.0},
			 "projectile": {"frame": 3, "kind": "shockwave", "speed": 760.0, "dmg": 18, "y": 0.0, "x": 300.0, "both_enraged": true}},
			# горизонтальный размах: быстрее и шире, но слабее
			{"anim": "sweep", "range": [0, 440], "cooldown": 1.6, "telegraph": [0], "weight": 3.0,
			 "hits": [{"frame": 1, "reach": [-140, 450], "dmg": 22, "knock": 680, "parry": true, "block": true}],
			 "lunge": {"frame": 1, "speed": 320}, "smear": {"frame": 1, "radius": 420, "color": "fire"}},
			# прыжок-топот: по кругу, блок не спасает — только кувырок
			{"anim": "stomp", "range": [300, 1600], "cooldown": 4.2, "telegraph": [0], "weight": 2.0, "warn": true,
			 "leap": {"from": 1, "to": 3, "height": 240.0},
			 "hits": [{"frame": 3, "radius": 270.0, "dmg": 25, "knock": 700, "parry": false, "block": false}],
			 "impact": {"frame": 3, "x": 0, "shake": 20.0}},
			{"anim": "roar", "range": [0, 2000], "cooldown": 16.0, "telegraph": [], "hp_below": 0.65, "weight": 6.0,
			 "summon": {"frame": 0, "kind": "balbal", "count": 2}},
		],
	},
}


static func get_def(kind: String) -> Dictionary:
	return DB[kind]
