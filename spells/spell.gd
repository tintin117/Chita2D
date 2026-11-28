class_name Spell extends Resource
## Base spell. Subclass and override cast(); this is the seam for custom skill mechanics.

@export var display_name := "Spell"
@export var cooldown := 0.5
@export var damage := 10
@export var icon: Texture2D
@export var sfx := "swing"       ## Sfx sound played on cast (see scripts/sfx.gd)

## Returns the cooldown (seconds) to apply after this cast.
func cast(_caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	return cooldown

var cast_pitch := 1.0   ## pitch / extra dB of the cast sound; a spell may change them per cast (HeroBasic: rising combo pitch)
var cast_vol := 0.0

## False when a press should do nothing. Every skill casts now (a cursor out of range casts at full range), so this is
## true; kept as the seam if a skill ever needs it. Asked by the caster's owner only.
func can_cast(_caster: Node2D, _aim_pos: Vector2) -> bool:
	return true

## Bots: is this cast worth it right now (an ult with somebody it would actually catch)? Players never see this.
func worth_casting(_caster: Node2D, _aim_pos: Vector2) -> bool:
	return true

## Ults: seconds after the cast during which nothing charges the next ult. Ults that last override it with their
## duration, so their own damage never pays for the next one.
func ult_lock() -> float:
	return 1.5

## How far a basic attack of this spell can reach a locked foe; 0 = not a lock-on attack (no hold-to-chase).
func reach() -> float:
	return 0.0

## World-to-screen scale for a basic attack's lock-on reach.
func range_projection() -> Vector2:
	return Vector2.ONE

## Hold-and-release spells (Power Shot): seconds of holding for a full charge; 0 = a normal press-to-cast spell.
## While held the Player draws (see Player._tick_charge), the aim stays free, and the cast goes out on release.
func charge_time() -> float:
	return 0.0

## Hold-and-release spells: the longest hold before the cast goes out by itself.
func max_hold() -> float:
	return 0.0

## Hold-and-release spells: draws the aim line on the caster (`canvas`, local coords) while drawn to `p` (0..1).
func draw_charge(_canvas: CanvasItem, _dir: Vector2, _p: float) -> void:
	pass

var power := 1.0  ## 0..1 charge of a hold-and-release cast (1 for every other spell); set by the Player around cast() on every peer

var lock: Node2D  ## the foe this one cast is locked onto (see target()); set by the Player around cast(), null otherwise

## Lock-on: the foe a cast aimed at `aim_pos` / `dir` should go for, or null for a free-aimed cast. Asked once by the
## caster's owner; the answer travels with the cast and reaches cast() as `lock` on every peer.
func target(_caster: Node2D, _aim_pos: Vector2, _dir: Vector2) -> Node2D:
	return null

## Aim correction (assist / soft lock) for a cast toward `dir`. Called once by the caster's owner before the cast is
## sent, so every peer spawns the same shot; cast() must use the direction it is given as-is.
func aim(_caster: Node2D, dir: Vector2) -> Vector2:
	return dir

## Everything a cast by `caster` can hurt: the other living players (PvP). Add enemies here for PvE later.
static func foes(caster: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n in caster.get_tree().get_nodes_in_group("players") + caster.get_tree().get_nodes_in_group("dummies"):
		if n != caster and not n.down and not (n.has_method("phased") and n.phased()):
			out.append(n)
	return out

## True if a solid obstacle (rock, wall) is within `dist` of `from` along `dir`.
static func solid_ahead(caster: Node2D, from: Vector2, dir: Vector2, dist: float) -> bool:
	if not caster.is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters2D.create(from, from + dir.normalized() * dist, Player.SOLID_MASK | Player.WALL_MASK)
	return not caster.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## Pushes a foe on the peer that owns it (a bot is owned by the peer running it; a dummy ignores it).
static func shove(foe: Node, vec: Vector2) -> void:
	if (foe.owns() if foe.has_method("owns") else foe.is_multiplayer_authority()):
		foe.knock += vec

## Aim assist: `dir` bent toward the closest foe inside `max_angle` (radians) and `max_dist`; unchanged if none.
## With `lead_speed` (a projectile's px/s) it is a soft lock: pointing at a moving foe aims at where the shot will meet it.
static func assist_dir(caster: Node2D, dir: Vector2, max_angle: float, max_dist: float, lead_speed := 0.0,
		projection := Vector2.ONE) -> Vector2:
	var e := pick_foe(caster, Vector2.INF, dir, 0.0, max_angle, max_dist, projection)
	if e == null:
		return dir
	var from := caster.global_position
	var at := e.global_position
	if lead_speed > 0.0 and e is CharacterBody2D:
		at = BotBrain.lead(from, at, e.velocity, lead_speed)
	return (at - from).normalized()

## The foe a cast is meant for: the one closest to `aim_pos` (the cursor) within `pick_radius`, else the one closest to
## the aim line within `max_angle`. Only foes within `max_dist` of the caster count. Null if nobody qualifies.
static func pick_foe(caster: Node2D, aim_pos: Vector2, dir: Vector2, pick_radius: float, max_angle: float,
		max_dist: float, projection := Vector2.ONE) -> Node2D:
	var near: Node2D = null
	var near_d := pick_radius
	var cone: Node2D = null
	var cone_off := max_angle
	var direction := dir / projection
	for e: Node2D in foes(caster):
		var off := (e.global_position - caster.global_position) / projection
		if off.length() > max_dist:
			continue
		if caster is Player and caster.ai and e is Player:
			if not caster.ai.can_see_foe(e):
				continue
		elif e.has_method("hidden_from") and e.hidden_from(caster):
			continue
		var d := e.global_position.distance_to(aim_pos)
		if d < near_d:
			near_d = d
			near = e
		var ang: float = absf(direction.angle_to(off))
		if ang <= cone_off:
			cone_off = ang
			cone = e
	return near if near else cone

## Stuns a foe that can be stunned (players; the dummy ignores it). Called on every peer so every screen shows it;
## only the victim's own peer actually stops moving. Call it only for a hit that landed (take_damage returned true).
static func stun(foe: Node, secs: float) -> void:
	if foe.has_method("stun"):
		foe.stun(secs)

## Freezes a foe that can be frozen (see Player.freeze): rooted and facing locked, but it can still attack. Same rules as
## stun(): call it on every peer, only for a hit that landed.
static func freeze(foe: Node, secs: float) -> void:
	if foe.has_method("freeze"):
		foe.freeze(secs)
