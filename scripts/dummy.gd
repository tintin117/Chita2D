class_name Dummy extends StaticBody2D
## Training dummy for the gym: takes any hit, never dies, shows floating damage and a rolling DPS readout.

const WINDOW := 3.0   ## seconds of hits the DPS number averages over

var down := false     ## Spell.foes / Projectile read this off every target
var knock := Vector2.ZERO   ## ShieldCharge shoves via this; a dummy ignores it
var _hits: Array[Vector2] = []   ## (time, damage)
var _label: Label

func _ready() -> void:
	add_to_group("dummies")
	collision_layer = 3   # world + players: solid for the hero, and every projectile mask sees it
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	cs.shape = circle
	cs.position = Vector2(0, 8)
	add_child(cs)
	_label = Label.new()
	_label.size = Vector2(160, 24)
	_label.position = Vector2(-80, -112)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.z_index = 50
	add_child(_label)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _hits.is_empty() and now - _hits[0].x > WINDOW:
		_hits.pop_front()
	var total := 0.0
	for h in _hits:
		total += h.y
	_label.text = "DPS %d" % roundi(total / WINDOW)

func _draw() -> void:
	draw_rect(Rect2(-6, -34, 12, 50), Color(0.45, 0.3, 0.18))        # post
	draw_rect(Rect2(-26, -22, 52, 9), Color(0.55, 0.38, 0.22))       # arm
	draw_circle(Vector2(0, -46), 15, Color(0.85, 0.7, 0.42))         # straw head
	draw_arc(Vector2(0, -46), 15, 0.0, TAU, 24, Color(0.35, 0.22, 0.1), 2.0)
	for r in [11.0, 6.0]:
		draw_arc(Vector2(0, -46), r, 0.0, TAU, 20, Color(0.8, 0.2, 0.2), 2.0)   # target rings
	draw_rect(Rect2(-18, 16, 36, 8), Color(0.3, 0.2, 0.12))          # base

func take_damage(amount: int, _from_pos: Vector2, _silent := false, _attacker: Node = null) -> void:
	_hits.append(Vector2(Time.get_ticks_msec() / 1000.0, amount))
	var l := Label.new()
	l.text = str(amount)
	l.modulate = Color(1, 0.85, 0.3)
	l.z_index = 100
	l.position = Vector2(randf_range(-30, 10), -80)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var t := create_tween().set_parallel()
	t.tween_property(l, "position:y", -130.0, 0.8)
	t.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.4)
	t.chain().tween_callback(l.queue_free)
	modulate = Color(1, 0.6, 0.6)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)
