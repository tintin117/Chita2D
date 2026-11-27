class_name SixSeven extends Spell
## Six Seven right click ("Six Seven!"): blink up to RANGE toward the cursor (through rocks; never through a wall or into
## the water) and yell it. Every foe within RADIUS of where he lands is stunned for STUN seconds (confused: "??" over
## its head) and takes DMG. The stun obeys the stun immunity. The landing spot comes from Player.blink_target, so every
## peer puts the yell in the same place; only the owner actually moves.

const RANGE := 267.0
const MIN := 80.0
const RADIUS := 130.0
const STUN := 0.67
const DMG := 7
const COLOR := Color(0.2, 1.0, 0.9)   ## the hero's signature colour (Hero.basic_color)

## Where the blink aims for a cast from `from` at `aim_pos` (before walls and water trim it).
static func dest(from: Vector2, aim_pos: Vector2, dir: Vector2) -> Vector2:
	return from + dir.normalized() * clampf(from.distance_to(aim_pos), MIN, RANGE)

class Yell extends Node2D:
	var color := COLOR
	var _age := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= 0.6:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _age / 0.6
		for i in 3:   # sound rings rolling out
			var r := RADIUS * clampf(k * 1.6 - i * 0.25, 0.0, 1.0)
			if r > 0.0:
				draw_arc(Vector2(0, 8), r, 0.0, TAU, 40, Color(color, (1.0 - k) * 0.9), 5.0 - i)
		draw_circle(Vector2(0, 8), RADIUS, Color(color, 0.12 * (1.0 - k)))
		var font := ThemeDB.fallback_font
		var rise := -90.0 - 30.0 * k
		var pop := 30 + int(10.0 * minf(k * 4.0, 1.0))
		draw_string_outline(font, Vector2(-70, rise), "SIX SEVEN!", HORIZONTAL_ALIGNMENT_CENTER, 140, pop, 6, Color(0, 0, 0, 1.0 - k))
		draw_string(font, Vector2(-70, rise), "SIX SEVEN!", HORIZONTAL_ALIGNMENT_CENTER, 140, pop, Color(color.lightened(0.3), 1.0 - k))

func _init() -> void:
	display_name = "Six Seven!"
	cooldown = 6.7
	damage = DMG
	sfx = "emote"
	cast_pitch = 1.6

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var land := dest(caster.global_position, aim_pos, d)
	if caster.has_method("blink_target"):
		land = caster.blink_target(land)   # the same spot on every peer
	SheetFrames.play_once(caster.get_parent(), caster.global_position + Vector2(0, 12), SheetFrames.FX + "AoE/IceAoE/", 0, 34.0, 0.3).modulate = COLOR
	if caster.has_method("owns") and caster.owns():
		caster.blink_to(land)
	var y := Yell.new()
	if "hero" in caster and caster.hero:
		y.color = caster.hero.basic_color
	y.position = land
	y.z_index = 6
	caster.get_parent().add_child(y)
	Sfx.play("crown", land, 0.0, 1.9)
	var cam := caster.get_tree().get_first_node_in_group("camera") as GameCamera
	if cam and Player.is_local(caster):
		cam.shake(0.25)
	for e in Spell.foes(caster):
		if e.global_position.distance_to(land) > RADIUS + 14.0:
			continue
		if e.take_damage(DMG, land, false, caster):
			Spell.stun(e, STUN)
			if e.has_method("float_text"):
				e.float_text("??", Color(1.0, 0.95, 0.5), 24)
	return cooldown
