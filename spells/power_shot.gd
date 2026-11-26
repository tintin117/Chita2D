class_name PowerShot extends Spell
## Ranger right click: HOLD to draw the bow, RELEASE to loose. The aim stays free the whole time: track a target, swing
## onto a new one, fake one way and fire the other. Everyone sees the aim line grow, so a full draw is a warning too.
## The longer the draw (up to CHARGE), the more damage, speed, range and knockback; a full draw pierces everyone on the
## line. No stun (the stun diet): knockback is the payoff, and knockback grows as the victim's HP drops, so a full shot
## on a hurt foe by the shore is a ring-out. Slowed while drawing; a stun or a dash drops the draw (no cooldown spent).
## Steady Aim (Ranger passive, hero.steady_aim): standing still draws twice as fast (Player.STEADY_RATE).

const ARROW := "res://assets/isometric_projecttile/Arrows/FireArrow/"
const CHARGE := 1.0          ## seconds to a full draw (0.5 standing still with Steady Aim)
const MAX_HOLD := 2.5        ## holding this long looses it anyway
const REACH := [450.0, 1100.0]     ## [no draw, full draw] flight distance
const SPEED := [900.0, 1800.0]
const DMG_MULT := [0.3, 1.0]       ## of `damage`
const SHOVE := [100.0, 650.0]
const FULL_PIERCE := 3             ## a full draw passes through this many extra foes
const LINE := Color(1.0, 0.35, 0.2)
const FULL := Color(1.0, 0.85, 0.3)

static func reach_at(p: float) -> float:
	return lerpf(REACH[0], REACH[1], clampf(p, 0.0, 1.0))

static func speed_at(p: float) -> float:
	return lerpf(SPEED[0], SPEED[1], clampf(p, 0.0, 1.0))

static func damage_at(base: int, p: float) -> int:
	return maxi(roundi(base * lerpf(DMG_MULT[0], DMG_MULT[1], clampf(p, 0.0, 1.0))), 1)

static func shove_at(p: float) -> float:
	return lerpf(SHOVE[0], SHOVE[1], clampf(p, 0.0, 1.0))

static func pierce_at(p: float) -> int:
	return FULL_PIERCE if p >= 1.0 else 0

func _init() -> void:
	display_name = "Power Shot"
	cooldown = 5.0
	damage = 42
	sfx = "shoot"

func charge_time() -> float:
	return CHARGE

func max_hold() -> float:
	return MAX_HOLD

## Placeholder art until there is a bow-draw animation: everything here reads without it.
## The aim line (as wide as the arrow will be), a ring filling round the feet, a bar + label over the head, and at full
## draw a gold pulsing aura and "RELEASE!". All of it shows on every screen (charge_show and aim_dir are synced).
func draw_charge(canvas: CanvasItem, dir: Vector2, p: float) -> void:
	var d := dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var full := p >= 1.0
	var c := FULL if full else LINE
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
	var start := Vector2(0, 8) + d * 30.0
	var end := start + d * reach_at(p)
	# the line: a faint band as wide as the arrow's hitbox, a bright core, an arrowhead at the reach
	canvas.draw_line(start, end, Color(c, 0.12 + 0.12 * p), (10.0 + 6.0 * p) * 2.0)
	canvas.draw_line(start, end, Color(c, 0.35 + 0.5 * p), 1.5 + 3.0 * p)
	var side := d.orthogonal() * 12.0
	canvas.draw_colored_polygon(PackedVector2Array([end + d * 18.0, end + side, end - side]), Color(c, 0.5 + 0.5 * p))
	# feet: a ring that fills clockwise
	canvas.draw_arc(Vector2(0, 14), 36.0, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 6.0)
	canvas.draw_arc(Vector2(0, 14), 36.0, -PI / 2.0, -PI / 2.0 + TAU * p, 32, Color(c, 0.95), 5.0)
	if full:   # the aura: this one hurts, let go
		canvas.draw_circle(Vector2(0, 14), 44.0 + 6.0 * pulse, Color(FULL, 0.18 + 0.12 * pulse))
		canvas.draw_arc(Vector2(0, -20), 52.0 + 4.0 * pulse, 0.0, TAU, 40, Color(FULL, 0.6 * pulse), 3.0)
	# head: bar + label
	var bar := Rect2(-34, -98, 68, 9)
	canvas.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.75))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), c)
	canvas.draw_line(Vector2(bar.position.x + bar.size.x * 0.5, bar.position.y), Vector2(bar.position.x + bar.size.x * 0.5, bar.end.y), Color(0, 0, 0, 0.6), 1.0)
	var font := ThemeDB.fallback_font
	var label := "RELEASE!" if full else "POWER SHOT"
	var col := Color(1, 1, 1, 0.6 + 0.4 * pulse) if full else Color(1, 1, 1, 0.9)
	canvas.draw_string_outline(font, Vector2(-60, -104), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14 if not full else 16, 4, Color.BLACK)
	canvas.draw_string(font, Vector2(-60, -104), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14 if not full else 16, col)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var p := clampf(power, 0.0, 1.0)
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var from := caster.global_position + Vector2(0, 8) + d * 30.0
	var arrow := Projectile.new().setup(from, d * speed_at(p), damage_at(damage, p), true, caster)
	arrow.arrow_tex = ARROW
	arrow.life = reach_at(p) / speed_at(p)
	arrow.pierce = pierce_at(p)
	arrow.shove = shove_at(p)
	arrow.radius = 10.0 + 6.0 * p
	arrow.trail = lerpf(40.0, 260.0, p)    # a longer streak for a longer draw, so everyone sees which shot is dangerous
	arrow.color = FULL if p >= 1.0 else LINE
	arrow.impact_scale = lerpf(0.15, 0.45, p)
	if p >= 1.0 and caster.has_method("float_text"):
		caster.float_text("POWER SHOT!", FULL, 22)
	caster.get_tree().current_scene.add_child(arrow)
	cast_pitch = lerpf(1.3, 0.75, p)   # a full draw thumps lower
	cast_vol = lerpf(-4.0, 2.0, p)
	return cooldown
