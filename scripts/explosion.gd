class_name Explosion extends Node2D
## Telegraphed AoE: shows a ring for `delay` seconds, then blasts everything in radius.

var radius := 90.0
var damage := 25
var delay := 0.45
var source: Node
var hits_enemies := true
var _boomed := false
var _age := 0.0

func setup(pos: Vector2, r: float, dmg: int, wait: float, src: Node = null) -> Explosion:
	position = pos
	radius = r
	damage = dmg
	delay = wait
	source = src
	return self

func _ready() -> void:
	get_tree().create_timer(delay).timeout.connect(_boom)

func _draw() -> void:
	if _boomed:
		return
	var grow := clampf(_age / delay, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(1, 0.4, 0.1, 0.12 + 0.12 * grow))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1, 0.55, 0.1, 0.9), 3.0)
	draw_arc(Vector2.ZERO, radius * grow, 0.0, TAU, 48, Color(1, 0.8, 0.3, 0.7), 2.0)

func _process(delta: float) -> void:
	_age += delta
	if not _boomed:
		queue_redraw()

func _boom() -> void:
	_boomed = true
	queue_redraw()
	for n: Node2D in get_tree().get_nodes_in_group("enemies" if hits_enemies else "players"):
		if n.global_position.distance_to(global_position) <= radius + 14.0 and not ("down" in n and n.down):
			n.take_damage(damage, global_position)
			if source and source.has_method("on_dealt_damage"):
				source.on_dealt_damage(damage)
	SheetFrames.play_once(get_parent(), global_position, "res://assets/tiny_swords/fx/Explosion_02.png", 10, 22.0, radius / 60.0)
	var cam := get_tree().get_first_node_in_group("camera") as GameCamera
	if cam:
		cam.shake(0.3)
	get_tree().create_timer(0.1).timeout.connect(queue_free)
