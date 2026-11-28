class_name FogOverlay extends CanvasLayer
## The Fog match event darkens the arena with a radial gradient around your hero.
## Distant foes fade out (Player._apply_look) and cannot be locked onto or seen by bots
## (Player.hidden_from). Teammates stay visible. Radar, name tags and drop arrows were already off in Fog.
## Sits over the world and under every HUD layer (layer 5; the hero panel Hud is 8, the match UI and chat 10). Purely local: each screen fogs around its own hero.

const RADIUS := 350.0   ## world px around the viewer
const FADE_START := RADIUS - 150.0
const FADE_END := RADIUS + 180.0
const ENEMY_FADE_START := RADIUS - 40.0
const ENEMY_HIDE_DISTANCE := RADIUS + 40.0
const SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform float fade_start;
uniform float fade_end;
uniform vec2 size;
void fragment() {
	vec2 p = UV * size;
	float d = distance(p, center);
	float fade = smoothstep(fade_start, fade_end, d);
	float drift = 0.025 * sin(p.x * 0.012 + TIME * 0.7) * sin(p.y * 0.015 - TIME * 0.5);
	COLOR = vec4(0.0, 0.0, 0.0, fade * (0.72 + drift));
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var preview_enabled := false
var preview_targets: Array[Node2D] = []

func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

func _process(_delta: float) -> void:
	var was_visible := _rect.visible
	var me := Player._local_viewer(get_tree()) if preview_enabled or MatchEvent.is_on(MatchEvent.FOG) else null
	_rect.visible = me != null
	if _rect.visible or was_visible:
		for target in preview_targets:
			if is_instance_valid(target):
				target.modulate.a = target_visibility(me, target)
	if me == null:
		return
	var xf := get_viewport().get_canvas_transform()
	var k := xf.get_scale().x   # camera zoom: world px -> screen px
	_mat.set_shader_parameter("center", xf * me.global_position)
	_mat.set_shader_parameter("fade_start", FADE_START * k)
	_mat.set_shader_parameter("fade_end", FADE_END * k)
	_mat.set_shader_parameter("size", _rect.size)

## Shared fade for match enemies and Gym targets. Callers decide whether fog is active.
static func target_visibility(viewer: Node2D, other: Node2D) -> float:
	if viewer == null or other == viewer:
		return 1.0
	if viewer is Player and other is Player and viewer.team >= 0 and viewer.team == other.team:
		return 1.0
	var distance := viewer.global_position.distance_to(other.global_position)
	return clampf(inverse_lerp(ENEMY_HIDE_DISTANCE, ENEMY_FADE_START, distance), 0.0, 1.0)

## Lock-on and bots lose foes at the same distance they disappear from view.
static func fogged(viewer: Node2D, other: Node2D) -> bool:
	return MatchEvent.is_on(MatchEvent.FOG) and target_visibility(viewer, other) <= 0.0
