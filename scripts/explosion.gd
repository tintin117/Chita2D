class_name Explosion extends Node2D
## Telegraphed AoE: shows a ring for `delay` seconds, then blasts everything in radius.

var radius := 90.0
var damage := 25
var delay := 0.45
var source: Node
var cause := "bomb"     ## kill-feed wording when it kills ("bomb" = the hot potato, "meteor" = the Meteor Shower event)
var shove := 0.0        ## extra outward launch on everyone hit (the Meteor Shower event)
var _boomed := false
var _age := 0.0

func setup(pos: Vector2, r: float, dmg: int, wait: float, src: Node = null) -> Explosion:
	position = pos
	radius = r
	damage = dmg
	delay = wait
	source = src
	return self

## A Meteor Shower strike: no owner, its own kill line, and a launch that grows toward the centre.
func as_meteor() -> Explosion:
	cause = "meteor"
	shove = MatchEvent.METEOR_SHOVE
	return self

func _ready() -> void:
	add_to_group("explosions")   # bots stay out of the ring until it goes off
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
	Sfx.play("explosion", global_position)
	for n: Node2D in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("dummies"):
		if n != source and n.global_position.distance_to(global_position) <= radius + 14.0 and not ("down" in n and n.down):
			var p := n as Player
			if p == null:
				n.take_damage(damage, global_position, false, source)
			elif p.take_damage(damage, global_position, false, source, cause) and shove > 0.0 and p.owns():
				var off := p.global_position - global_position
				var k := clampf(off.length() / radius, 0.0, 1.0)
				p.knock += (off.normalized() if off.length() > 1.0 else Vector2.RIGHT) * shove * lerpf(1.0, 0.55, k)
	SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/FireAoE/", 0, 22.0, radius / 140.0)
	var cam := get_tree().get_first_node_in_group("camera") as GameCamera
	if cam:
		cam.shake(0.5)
	get_tree().create_timer(0.1).timeout.connect(queue_free)
