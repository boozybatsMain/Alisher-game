// Остаточный силуэт (шлейф кувырка, рывка и бега): спрайт, залитый одним цветом.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.35, 0.94, 0.86, 0.4);

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, a * tint.a * v_mod.a);
}
