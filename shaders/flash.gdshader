// Вспышка при попадании и телеграф замаха: подмешиваем цвет к спрайту.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * v_mod;
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	COLOR = c;
}
