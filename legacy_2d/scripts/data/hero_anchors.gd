extends RefCounted
## Сгенерировано tools/build_assets.py: точка крепления ленты (затылок) в каждом кадре,
## относительно опорной точки спрайта (ноги).

const HAIR := {
	"idle": [Vector2(-10.0, -212.4), Vector2(-14.0, -214.1), Vector2(-13.0, -201.0), Vector2(-12.0, -210.4)],
	"run": [Vector2(25.0, -169.7), Vector2(28.0, -154.7), Vector2(25.0, -172.6), Vector2(26.0, -168.7)],
	"attack1": [Vector2(-9.0, -208.2), Vector2(5.0, -200.4), Vector2(0.0, -194.5), Vector2(-5.0, -172.5), Vector2(-2.0, -172.5), Vector2(2.0, -171.6), Vector2(6.0, -172.6), Vector2(-11.0, -208.2)],
	"attack2": [Vector2(8.0, -176.5), Vector2(0.0, -174.5), Vector2(15.0, -175.5), Vector2(9.0, -176.5)],
	"attack3": [Vector2(12.0, -170.4), Vector2(1.0, -157.6), Vector2(-9.0, -141.6), Vector2(17.0, -141.4)],
	"dash": [Vector2(38.0, -138.5), Vector2(48.0, -140.6), Vector2(-31.0, -145.8), Vector2(6.0, -169.5)],
	"roll": [Vector2(42.0, -70.6), Vector2(9.0, -84.2), Vector2(-29.0, -61.5), Vector2(47.0, -101.8)],
	"block": [Vector2(-2.0, -154.7), Vector2(-3.0, -151.6), Vector2(-5.0, -151.0)],
	"parry": [Vector2(-19.0, -150.8)],
	"hurt": [Vector2(-61.0, -162.8), Vector2(15.0, -146.0)],
	"death": [Vector2(10.0, -97.4), Vector2(-119.0, -61.5)],
}
