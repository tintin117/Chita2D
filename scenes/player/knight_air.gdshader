shader_type canvas_item;

uniform float lift : hint_range(0.0, 1.0) = 0.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float max_channel = max(max(pixel.r, pixel.g), pixel.b);
	// The painted ground shadow is nearly black with partial alpha. Armor remains opaque.
	float shadow = (1.0 - smoothstep(0.025, 0.06, max_channel)) * (1.0 - step(0.94, pixel.a));
	pixel.a *= 1.0 - shadow * lift;
	COLOR = pixel * tint;
}
