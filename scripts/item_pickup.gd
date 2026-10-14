class_name ItemPickup extends Area2D
## Item lying on the ground. Walking over it equips it if it beats what the player wears in that slot;
## otherwise it stays put for someone else. Drop one with ItemPickup.drop(parent, pos, item).

var item: Item
var _t := randf() * TAU

static func drop(parent: Node, pos: Vector2, it: Item) -> ItemPickup:
	var pk := ItemPickup.new()
	pk.item = it
	pk.position = pos
	parent.add_child.call_deferred(pk)  # drops usually come from a death inside a physics callback
	return pk

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	var p := body as Player
	if p and not p.down and p.try_equip(item):
		queue_free()

func _process(delta: float) -> void:
	_t += delta * 3.0
	queue_redraw()

func _draw() -> void:
	var c := item.color()
	var y := sin(_t) * 3.0 - 14.0
	draw_circle(Vector2(0, 0), 14.0, Color(0, 0, 0, 0.25))  # ground shadow
	draw_colored_polygon(PackedVector2Array([Vector2(0, y - 14), Vector2(12, y), Vector2(0, y + 14), Vector2(-12, y)]), c)
	draw_string(ThemeDB.fallback_font, Vector2(-12, y + 5), item.slot.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, Color.BLACK)
