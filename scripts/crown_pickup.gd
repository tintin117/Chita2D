class_name CrownPickup extends Area2D
## The crown lying on the ground (Crown mode). Only the owning peer of the player who touches it reports it (`touched`);
## the host decides who wears it. A dropped crown lies untouchable for `grace` seconds, so a kill is not an instant steal chain.

signal touched(peer: int)

const CROWN_TEX := preload("res://assets/ui/crown.png")
const GOLD := Color(1.0, 0.85, 0.3)
const RADIUS := 44.0

var grace := 0.0          ## seconds left before anyone can take it
var _t := randf() * TAU
var _age := 0.0

func _ready() -> void:
	z_index = 5
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	var p := body as Player
	if grace <= 0.0 and p and p.owns() and not p.down:
		touched.emit(p.peer_id)

func _process(delta: float) -> void:
	_t += delta * 3.0
	_age += delta
	if grace > 0.0:
		grace -= delta
		if grace <= 0.0 and is_inside_tree():
			# somebody may already be standing on it: report them now instead of waiting for a re-entry
			for b in get_overlapping_bodies():
				_on_body(b)
	queue_redraw()

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t)
	var locked := grace > 0.0
	var c := Color(0.6, 0.6, 0.6) if locked else GOLD
	var ramp := clampf(_age / 0.4, 0.0, 1.0)
	var beam := Color(c, 0.22 + 0.2 * pulse)
	var tip := -700.0 * ramp
	draw_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(8, tip), Vector2(-8, tip)]),
		PackedColorArray([beam, beam, Color(c, 0.0), Color(c, 0.0)]))
	var base_r := 40.0 + pulse * 8.0
	draw_circle(Vector2.ZERO, base_r, Color(c, 0.2))
	for i in 3:
		draw_arc(Vector2.ZERO, base_r + i * 14.0 + (pulse * 6.0 if i > 0 else 0.0), 0.0, TAU, 32, Color(c, 0.9 - i * 0.2), 3.0)
	if not locked:   # expanding shockwaves: this is the objective, not a drop
		for i in 2:
			var k := fposmod(_t / TAU * 1.2 + i * 0.5, 1.0)
			draw_arc(Vector2.ZERO, 40.0 + k * 160.0, 0.0, TAU, 40, Color(c, (1.0 - k) * 0.7), 4.0 * (1.0 - k) + 1.0)
	var y := sin(_t) * 5.0 - 40.0
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.35))
	draw_texture_rect(CROWN_TEX, Rect2(Vector2(-24, y - 24), Vector2(48, 48)), false, Color.WHITE if not locked else Color(0.7, 0.7, 0.7))
	var font := ThemeDB.fallback_font
	var label := "%.1f" % maxf(grace, 0.0) if locked else "THE CROWN"
	draw_string_outline(font, Vector2(-80, y - 34), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 4, Color.BLACK)
	draw_string(font, Vector2(-80, y - 34), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color.WHITE)
