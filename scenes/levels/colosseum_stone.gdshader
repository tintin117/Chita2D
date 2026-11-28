shader_type canvas_item;

varying vec2 arena_position;

float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	arena_position = VERTEX;
}

void fragment() {
	vec2 stone = vec2(arena_position.x, arena_position.y * 1.45);
	float speckle = grain(floor(stone / 4.0)) - 0.5;
	float chips = grain(floor(stone / vec2(15.0, 6.0))) - 0.5;
	float strata = sin(arena_position.y * 0.26 + grain(floor(stone / 28.0)) * 2.0);
	float color_shift = speckle * 0.039 + chips * 0.035 + strata * 0.010;
	COLOR.rgb += vec3(color_shift, color_shift * 0.88, color_shift * 0.62);
}
