class_name BreakerWave extends Node2D
## Tide Breaker (Tidecaller passive): every Player.WAVE_CD seconds the next basic swing also sends a wave the same shape
## as the swing (its arc) rolling out from where he stood, to the middle of his blade reach and BASE_LENGTH
## (reach() = (attack_range + BASE_LENGTH) / 2, ~195 px). It hits each foe once as the front passes: DMG and a small
## push outward. The first foe it hits pays back REFUND seconds of the wait. Spawned from Player._net_cast (every peer).

const BASE_LENGTH := 260.0
const SPEED := 560.0
const BAND := 34.0          ## thickness of the moving front
const DMG := 12
const SHOVE := 0.0           ## no extra push: the target stays in his swing (the hit's own flinch is enough)
const REFUND := 1.0
const START := 30.0

var caster: Node2D
var dir := Vector2.RIGHT
var arc := 2.3
var reach := 195.0
var color := Color(0.15, 0.85, 0.85)
var _r := START
var _hits: Array[Node] = []
var _refunded := false

## The wave's reach for a hero whose swing reaches `attack_range`.
static func reach_for(attack_range: float) -> float:
	return (attack_range + BASE_LENGTH) * 0.5

static func spawn(c: Node2D, d: Vector2) -> void:
	if not c.is_inside_tree():
		return
	var w := BreakerWave.new()
	w.caster = c
	w.dir = d.normalized() if d.length() > 0.01 else Vector2.RIGHT
	if "hero" in c and c.hero:
		w.arc = c.hero.arc_angle
		w.reach = reach_for(c.hero.attack_range)
		w.color = c.hero.basic_color
	w.position = c.global_position + Vector2(0, 8)
	w.z_index = 5
	c.get_parent().add_child(w)
	Sfx.play("splash", c.global_position, -4.0, 1.2)

## True if `off` (from the wave's origin) is on the front at radius `r` inside the arc `arc` around `d`.
static func on_front(off: Vector2, d: Vector2, arc_: float, r: float) -> bool:
	var dist := off.length()
	if dist < r - BAND or dist > r + 14.0:
		return false
	return dist < 24.0 or absf(d.angle_to(off)) <= arc_ * 0.5 + atan2(16.0, maxf(dist, 1.0))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster):
		queue_free()
		return
	_r = minf(_r + SPEED * delta, reach)
	for e in Spell.foes(caster):
		if e in _hits or not BreakerWave.on_front(e.global_position - global_position, dir, arc, _r):
			continue
		_hits.append(e)
		var out: Vector2 = (e.global_position - global_position).normalized()
		Player.basic_hit = true   # it rides a basic: a flinch, no push
		var landed: bool = e.take_damage(DMG, e.global_position - out * 20.0, false, caster)
		Player.basic_hit = false
		if landed and SHOVE > 0.0:
			Spell.shove(e, out * SHOVE)
		if not _refunded and caster.has_method("wave_refund"):
			_refunded = true
			caster.wave_refund(REFUND)
	if _r >= reach:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var fade := clampf((reach - _r) / 60.0 + 0.25, 0.0, 1.0)
	var base := dir.angle() - arc * 0.5
	draw_arc(Vector2.ZERO, _r - BAND * 0.5, base, base + arc, 24, Color(color, 0.35 * fade), BAND)   # the body of water
	draw_arc(Vector2.ZERO, _r, base, base + arc, 24, Color(0.9, 1.0, 1.0, 0.9 * fade), 4.0)        # the foam on the front
	for i in 5:   # spray flecks along the crest
		var a := base + arc * (i + 0.5) / 5.0 + sin(_r * 0.05 + i) * 0.05
		draw_circle(Vector2.from_angle(a) * (_r + 6.0), 3.0, Color(1, 1, 1, 0.7 * fade))
