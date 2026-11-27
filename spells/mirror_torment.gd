class_name MirrorTorment extends Spell
## Demonbound right click: curse a spot. Every foe within RADIUS gets a dark copy of itself at its back for TIME seconds
## that attacks it with its OWN basic: SHARE of its basic damage, at its basic pace (never faster than MIN_GAP), and
## keeps it slowed. Heavy hitters suffer most. Fiendform adds FIEND_BONUS seconds. Runs on every peer; the copy's hits
## land on the victim's own peer (silent ticks: no stagger, no i-frames, like a burn).

const MAX_RANGE := 500.0
const RADIUS := 220.0
const TIME := 3.5
const FIEND_BONUS := 1.0
const SHARE := 0.4
const MIN_GAP := 0.7          ## the copy never hits faster than this: it is a haunting, not a second attacker
const SLOW := 0.75
const COLOR := Color(0.95, 0.15, 0.25)   ## the hero's signature colour (Hero.basic_color)

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

## The copy's hit and pace for `victim`: [damage, seconds between hits].
static func echo(victim: Node) -> Array:
	var dmg := 6
	var gap := 0.6
	if "spells" in victim and not victim.spells.is_empty() and victim.spells[0] != null:
		dmg = victim.spells[0].damage
		gap = victim.spells[0].cooldown
	return [maxi(roundi(dmg * SHARE), 1), maxf(gap, MIN_GAP)]

class Copy extends Node2D:
	var caster: Node2D
	var victim: Node2D
	var left := TIME
	var _tick := 0.6
	var _flash := 0.0     ## a red slash on each of its hits

	func _physics_process(delta: float) -> void:
		left -= delta
		if left <= 0.0 or not is_instance_valid(victim) or victim.down or not is_instance_valid(caster):
			queue_free()
			return
		var back: Vector2 = -victim.aim_dir * 30.0 if "aim_dir" in victim else Vector2(-30, 0)   # clings to its back, peeking out
		global_position = victim.global_position + back
		if victim.has_method("apply_slow"):
			victim.apply_slow(SLOW, 0.2)
		_tick -= delta
		if _tick <= 0.0:
			var e := MirrorTorment.echo(victim)
			_tick = e[1]
			victim.take_damage(e[0], global_position, true, caster)
			_flash = 0.18
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var a := clampf(left / 0.4, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		if is_instance_valid(victim):
			var vf: Vector2 = victim.global_position - global_position
			draw_arc(vf + Vector2(0, 14), 30.0 + 4.0 * pulse, 0.0, TAU, 28, Color(COLOR, 0.8 * a), 3.0)   # the cursed one's ring
			draw_line(Vector2(0, -24), vf + Vector2(0, -24), Color(COLOR, 0.6 * a), 5.0)   # the tether
			draw_line(Vector2(0, -24), vf + Vector2(0, -24), Color(1.0, 0.6, 0.6, 0.5 * a), 1.5)
		draw_circle(Vector2(0, 14), 20.0, Color(0.1, 0.0, 0.02, 0.45 * a))   # its own shadow
		var spr: AnimatedSprite2D = victim.get("_sprite") if is_instance_valid(victim) else null
		if spr and spr.sprite_frames:
			var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
			if tex:
				var sz := tex.get_size() * spr.scale
				var r := Rect2(-sz / 2.0 + spr.position, sz)
				for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:   # a hot red outline: you can't miss it
					draw_texture_rect(tex, Rect2(r.position + o, r.size), false, Color(1.0, 0.2, 0.25, (0.55 + 0.3 * pulse) * a))
				draw_texture_rect(tex, r, false, Color(0.25, 0.02, 0.06, 0.95 * a))
		else:
			draw_circle(Vector2(0, -20), 18.0, Color(COLOR, 0.8 * a))
		if _flash > 0.0:   # each of its hits: a red slash across the victim
			var k := _flash / 0.18
			var at: Vector2 = (victim.global_position - global_position) + Vector2(0, -30) if is_instance_valid(victim) else Vector2(0, -30)
			draw_line(at + Vector2(-16, -12), at + Vector2(16, 12), Color(1.0, 0.35, 0.4, k), 5.0)
		draw_arc(Vector2(0, -78), 9.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(left / TIME, 0.0, 1.0), 20, Color(1.0, 0.4, 0.45, 0.9 * a), 3.0)   # time left

func _init() -> void:
	display_name = "Dark Reflection"
	cooldown = 8.0
	damage = 0
	sfx = "explosion"
	cast_pitch = 1.3

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var at := spot(caster.global_position, aim_pos)
	var time := TIME + (FIEND_BONUS if caster is Player and caster.fiended() else 0.0)
	for e in Spell.foes(caster):
		if e.global_position.distance_to(at) > RADIUS + 14.0:
			continue
		var c := Copy.new()
		c.caster = caster
		c.victim = e
		c.left = time
		c.z_index = 5
		c.position = e.global_position
		caster.get_parent().add_child(c)
		if e.has_method("float_text"):
			e.float_text("TORMENTED", COLOR.lightened(0.3), 16)
	SheetFrames.play_once(caster.get_parent(), at, SheetFrames.FX + "AoE/DeathAoE/", 0, 30.0, RADIUS / 110.0).modulate = Color(1.0, 0.4, 0.45, 0.8)
	return cooldown
