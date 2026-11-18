// Живой мир: «кипение линий» (8 раз в секунду картинка чуть смещается шумом, как перерисованная от руки)
// и, для травы, покачивание от ветра. Фаза качания берётся из мировой позиции — один материал на всю траву.
shader_type canvas_item;

uniform bool boil = true;
uniform float boil_amount = 1.6;
uniform float fps = 8.0;
uniform bool sway = false;
uniform float gust = 0.0;

varying vec4 v_mod;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_mod = COLOR;
	if (sway) {
		float t = boil ? floor(TIME * fps) / fps : TIME;
		float phase = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x * 0.013;
		float k = sin(t * (1.9 + gust) + phase) * (0.06 + 0.09 * gust) + sin(t * 4.3 + phase * 2.0) * (0.02 + 0.03 * gust) + 0.08 * gust;
		// основание травы — y = 0 (спрайт смещён вверх), верхушка уходит влево по ветру
		VERTEX.x += k * VERTEX.y;
	}
}

void fragment() {
	vec2 uv = UV;
	if (boil) {
		float t = floor(TIME * fps);
		vec2 px = UV / TEXTURE_PIXEL_SIZE;
		vec2 n = vec2(noise(px / 22.0 + vec2(t * 7.13, t * 3.71)), noise(px / 22.0 + vec2(t * 5.27 + 11.0, t * 9.17))) - 0.5;
		uv += n * boil_amount * 2.0 * TEXTURE_PIXEL_SIZE;
	}
	COLOR = texture(TEXTURE, uv) * v_mod;
}
