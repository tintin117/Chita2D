class_name GameCamera extends Camera2D
## Follows the midpoint of living players, zooms out to keep all in frame. shake() for impacts.

const MARGIN := Vector2(360, 260)
const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.3

var _trauma := 0.0

func _ready() -> void:
	add_to_group("camera")

func _process(delta: float) -> void:
	var alive := get_tree().get_nodes_in_group("players").filter(func(p: Player) -> bool: return not p.down)
	if not alive.is_empty():
		var bounds := Rect2(alive[0].global_position, Vector2.ZERO)
		for p: Player in alive:
			bounds = bounds.expand(p.global_position)
		for b: Node2D in get_tree().get_nodes_in_group("boss"):
			bounds = bounds.expand(b.global_position)
		var view := get_viewport_rect().size
		var fit := minf(view.x / (bounds.size.x + MARGIN.x), view.y / (bounds.size.y + MARGIN.y))
		var z := clampf(fit, MIN_ZOOM, MAX_ZOOM)
		var k := 1.0 - exp(-6.0 * delta)
		zoom = zoom.lerp(Vector2(z, z), k)
		global_position = global_position.lerp(bounds.get_center(), k)
	_trauma = maxf(_trauma - delta * 2.5, 0.0)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _trauma * _trauma

func shake(amount := 0.4) -> void:
	_trauma = minf(_trauma + amount, 1.0)

## Brief freeze on impact. Lives here (not on the enemy) so freeing the caller can't leave time_scale stuck.
func hit_stop(duration := 0.05) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.1
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
