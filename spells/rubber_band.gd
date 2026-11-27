class_name RubberBand extends Spell
## Six Seven's first right click (unused now, kept for A/B): drop an anchor where you stand. A band stretches from it to you, and DELAY seconds later you
## snap back to it (the server "corrects" you), shaking off slows on the way. Go in, take the trade, get rubber-banded
## out. Runs on every peer (the anchor and the band show everywhere); only the owner moves (Player.blink_to).

const DELAY := 2.0
const COLOR := Color(0.85, 0.9, 1.0)

class Anchor extends Node2D:
	var caster: Node2D
	var color := COLOR
	var _age := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		if _age >= DELAY:
			if caster.has_method("owns") and caster.owns():
				caster.blink_to(global_position)
				if caster.has_method("clear_slows"):
					caster.clear_slows()
			Sfx.play("dash", global_position, 0.0, 1.6)
			SheetFrames.play_once(get_parent(), global_position + Vector2(0, 12), SheetFrames.FX + "AoE/IceAoE/", 0, 30.0, 0.35).modulate = color
			if caster.has_method("float_text"):
				caster.float_text("RUBBER BAND", color, 16)
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / DELAY, 0.0, 1.0)
		draw_arc(Vector2(0, 14), 22.0, 0.0, TAU, 24, Color(color, 0.5), 2.0)
		draw_arc(Vector2(0, 14), 22.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - k), 24, Color(color, 0.95), 4.0)   # time left
		if is_instance_valid(caster):   # the band: thinner the further it stretches
			var to: Vector2 = caster.global_position - global_position
			var w := clampf(6.0 - to.length() / 120.0, 1.5, 6.0)
			draw_line(Vector2(0, -10), to + Vector2(0, -10), Color(color, 0.55), w)
		draw_circle(Vector2(0, -10), 5.0, Color(1.0, 0.45, 0.75))

func _init() -> void:
	display_name = "Rubber Band"
	cooldown = 8.0
	damage = 0
	sfx = "emote"
	cast_pitch = 1.3

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var a := Anchor.new()
	a.caster = caster
	if "hero" in caster and caster.hero:
		a.color = caster.hero.basic_color
	a.position = caster.global_position
	a.z_index = 2
	caster.get_parent().add_child(a)
	return cooldown
