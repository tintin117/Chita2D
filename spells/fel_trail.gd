class_name FelTrail extends Node2D
## Hellwalker (Demonbound passive): he leaves burning ground wherever he goes. Walking lays a thin trail, a dash a thick
## one (any movement faster than DASH_PX per tick counts, so puppets lay the same trail). Each patch burns for LIFE s.
##  - Foes standing on it are slowed and take DMG every TICK (silent ticks, like a burn).
##  - His own basic bolts that fly over it catch fire (Projectile.fel): +IGNITE_BONUS damage and a small blast on hit.
## One node per Demonbound, fed by Player._tick_fel on every peer; the damage lands on each victim's own peer.

const LIFE := 3.0
const STEP := 22.0           ## px between patches
const THIN := 18.0           ## patch radius when walking
const THICK := 42.0          ## patch radius from a dash
const DASH_PX := 12.0        ## moved more than this in one tick = a dash
const TICK := 0.5
const DMG := 4
const SLOW := 0.7
const IGNITE_BONUS := 6
const BLAST_RADIUS := 70.0
const BLAST_DMG := 6

var caster: Node2D
var color := Color(0.95, 0.15, 0.25)
var _pts: Array = []         ## [Vector2 pos, float radius, float age]
var _tick := TICK

func add(pos: Vector2, r: float) -> void:
	_pts.append([pos, r, 0.0])

## Bots: which way to step to get off the burning ground at `pos` (zero = not on it).
func bot_avoid(pos: Vector2) -> Vector2:
	var feet := pos + Vector2(0, 14)
	for p in _pts:
		var off: Vector2 = feet - p[0]
		if off.length() <= p[1] + 20.0:
			return off.normalized() if off.length() > 1.0 else Vector2.RIGHT
	return Vector2.ZERO

## True if `pos` is on a live patch.
func covers(pos: Vector2) -> bool:
	for p in _pts:
		if pos.distance_to(p[0]) <= p[1]:
			return true
	return false

func _ready() -> void:
	z_index = -1   # on the ground, under everyone
	add_to_group("zones")   # bots keep off it

func _physics_process(delta: float) -> void:
	for p in _pts:
		p[2] += delta
	_pts = _pts.filter(func(p: Array) -> bool: return p[2] < LIFE)
	_tick -= delta
	var bite := _tick <= 0.0
	if bite:
		_tick += TICK
	if is_instance_valid(caster) and not _pts.is_empty():
		for e in Spell.foes(caster):
			if not covers(e.global_position + Vector2(0, 14)):
				continue
			if e.has_method("apply_slow"):
				e.apply_slow(SLOW, 0.2)
			if bite:
				e.take_damage(DMG, e.global_position, true, caster)
	queue_redraw()

func _draw() -> void:
	var flick := Time.get_ticks_msec() * 0.012
	for p in _pts:
		var k: float = 1.0 - p[2] / LIFE
		var at: Vector2 = p[0] - global_position
		draw_circle(at, p[1], Color(color, 0.22 * k))
		draw_circle(at, p[1] * (0.45 + 0.1 * sin(flick + at.x * 0.1)), Color(1.0, 0.55, 0.2, 0.35 * k))   # embers
