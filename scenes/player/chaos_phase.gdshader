shader_type canvas_item;

varying vec2 sprite_position;
varying vec4 sprite_modulate;

void vertex() {
	sprite_position = VERTEX;
	sprite_modulate = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float clock = TIME * 2.4;
	float band = sin(sprite_position.y * 0.17 + clock);
	float wave = 0.5 + 0.5 * sin(clock * 0.77 - sprite_position.x * 0.04);
	// Whole-texel offsets keep the spectral copy on the sprite's pixel grid.
	vec2 slip = round(vec2(3.5 * sin(clock) + 1.8 * band, -1.0 - 2.0 * wave));
	vec4 echo = texture(TEXTURE, UV - slip * TEXTURE_PIXEL_SIZE);
	// The black ground shadow stays put. The bright blade edges stay legible.
	float body = smoothstep(0.06, 0.18, base.b);
	float edge = smoothstep(0.46, 0.83, max(base.r, base.b));
	float echo_body = smoothstep(0.09, 0.2, echo.b);
	float fracture = smoothstep(0.28, 0.94, band) * (0.42 + 0.58 * wave);
	base.a *= 1.0 - body * fracture * mix(0.50, 0.14, edge);
	base.rgb = mix(base.rgb, base.rgb * vec3(1.26, 0.93, 1.36), body * fracture);
	float echo_alpha = echo.a * echo_body * (0.16 + 0.25 * wave);
	vec3 echo_color = mix(vec3(0.20, 0.13, 0.48), vec3(0.75, 0.31, 0.72), wave);
	float behind = echo_alpha * (1.0 - base.a);
	float alpha = base.a + behind;
	vec3 color = (base.rgb * base.a + echo_color * behind) / max(alpha, 0.001);
	COLOR = vec4(color, alpha) * sprite_modulate;
}
