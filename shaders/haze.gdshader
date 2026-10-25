// Марево: полосы уже нарисованного дальнего плана сдвигаются синусом — горячий воздух над степью.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 2.6;

void fragment() {
	float k = clamp((UV.y - 0.12) / 0.8, 0.0, 1.0);
	float amp = 0.4 + strength * k * k;
	float y = SCREEN_UV.y / SCREEN_PIXEL_SIZE.y;
	float dx = sin(y * 0.13 + TIME * 4.4) * amp + sin(y * 0.41 - TIME * 6.3) * amp * 0.45;
	COLOR = texture(screen_tex, SCREEN_UV + vec2(dx * SCREEN_PIXEL_SIZE.x, 0.0));
}
