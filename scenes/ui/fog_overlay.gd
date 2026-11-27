class_name FogOverlay extends CanvasLayer
## The Fog match event, for real: everything farther than RADIUS from your own hero sinks into a dark mist (soft edge
## SOFT), and foes out there are not drawn at all (Player._apply_look) and cannot be locked onto or seen by bots
## (Player.hidden_from). Teammates stay visible. Radar, name tags and drop arrows were already off in Fog.
## Sits over the world and under every HUD layer (layer 5; the hero panel Hud is 8, the match UI and chat 10). Purely local: each screen fogs around its own hero.

const RADIUS := 380.0   ## world px you can see around yourself
const SOFT := 150.0     ## width of the fade at the edge
const SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform float radius;
uniform float soft;
uniform vec2 size;
uniform vec4 tint : source_color = vec4(0.07, 0.09, 0.11, 1.0);
void fragment() {
	vec2 p = UV * size;
	float d = distance(p, center);
	float a = smoothstep(radius - soft, radius, d);
	float drift = 0.06 * sin(p.x * 0.012 + TIME * 0.7) * sin(p.y * 0.015 - TIME * 0.5);   // the mist moves a little
	COLOR = vec4(tint.rgb, clamp(a * (0.9 + drift), 0.0, 0.94));
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial

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
	var me := Player._local_viewer(get_tree()) if MatchEvent.is_on(MatchEvent.FOG) else null
	_rect.visible = me != null
	if me == null:
		return
	var xf := get_viewport().get_canvas_transform()
	var k := xf.get_scale().x   # camera zoom: world px -> screen px
	_mat.set_shader_parameter("center", xf * me.global_position)
	_mat.set_shader_parameter("radius", RADIUS * k)
	_mat.set_shader_parameter("soft", SOFT * k)
	_mat.set_shader_parameter("size", _rect.size)

## True when `other` is lost in the fog for `viewer` (allies never are). Used for drawing, lock-on and bots.
static func fogged(viewer: Node2D, other: Node2D) -> bool:
	if not MatchEvent.is_on(MatchEvent.FOG) or viewer == null or other == viewer:
		return false
	if viewer is Player and other is Player and viewer.team >= 0 and viewer.team == other.team:
		return false
	return viewer.global_position.distance_to(other.global_position) > RADIUS + 40.0
