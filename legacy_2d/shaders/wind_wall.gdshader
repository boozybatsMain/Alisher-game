// Ветровой барьер на краю арены: закрученные струи ветра бегут вверх.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.93, 0.8, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float n = noise(vec2(uv.x * 6.0 + sin(uv.y * 8.0 + t * 2.0) * 0.6, uv.y * 3.0 - t * 2.4)) * 0.6
		+ noise(vec2(uv.x * 14.0, uv.y * 7.0 - t * 4.0)) * 0.4;
	float streak = smoothstep(0.52, 0.9, n);
	float edge = 1.0 - abs(uv.x - 0.5) * 2.0;
	float bottom = smoothstep(0.0, 0.15, 1.0 - uv.y) * smoothstep(0.0, 0.25, uv.y);
	float a = (streak * 0.85 + 0.12) * edge * bottom * intensity;
	COLOR = vec4(tint.rgb, a * tint.a);
}
