class_name PvpPickup extends Area2D
## Arena power-up. Only the owning peer of the player who touches it reports it (`touched`); the host decides who got it first.

signal touched(id: int, peer: int)

const KINDS := ["heal", "damage", "speed", "mystery", "giant", "chicken", "bomb"]
const WEIGHTS := {"heal": 6.0, "damage": 3.0, "speed": 5.0, "mystery": 3.0, "giant": 1.0, "chicken": 0.5, "bomb": 0.5}   ## how often the host spawns each kind (epics ~10%)
## Drop tiers, same 0..2 scale as Item rarity so loot code can share them.
enum Tier { COMMON, RARE, EPIC }
const TIER_NAMES := ["Common", "Rare", "Epic"]
const TIER_COLORS := [Color(0.85, 0.95, 0.85), Color(0.4, 0.7, 1.0), Color(1.0, 0.72, 0.2)]
const KIND_TIER := {"heal": Tier.COMMON, "speed": Tier.COMMON, "damage": Tier.RARE, "mystery": Tier.RARE,
	"giant": Tier.EPIC, "chicken": Tier.EPIC, "bomb": Tier.EPIC,
	"slingshot": Tier.COMMON, "firecracker": Tier.COMMON, "hammer": Tier.RARE, "frost_gun": Tier.RARE, "boomerang": Tier.RARE,
	"bomb_launcher": Tier.RARE, "rocket": Tier.EPIC, "meteor": Tier.EPIC, "gatling": Tier.EPIC}
## Friendslop weapon pickups (the gameplay lives in FsWeapon.DEFS; a test keeps the two lists in step).
const FS_WEAPONS := ["slingshot", "firecracker", "hammer", "frost_gun", "boomerang", "bomb_launcher", "rocket", "meteor", "gatling"]
## Friendslop drop table: the classic kinds plus the weapons. Epics are ~13% of drops, rares and commons ~43% each.
const FS_WEIGHTS := {"heal": 5.0, "speed": 3.0, "slingshot": 5.0, "firecracker": 4.0,
	"damage": 2.0, "mystery": 3.0, "hammer": 3.0, "frost_gun": 3.0, "boomerang": 3.0, "bomb_launcher": 3.0,
	"giant": 0.8, "chicken": 0.5, "bomb": 0.5, "rocket": 1.1, "meteor": 1.0, "gatling": 1.1}
const CATCHUP_TIER_GAIN := [-0.4, 0.5, 1.2]   ## per tier: weight change at full catch-up boost (commons thin out, epics get likelier)
## Per tier: beam height, beam half-width, ground rings, orbiting sparkles, badge corner count (0 = circle), badge radius.
## Shape and size differ per tier too, so the tiers read without colour.
const TIER_LOOK := [
	{"beam": 260.0, "width": 10.0, "rings": 1, "sparkles": 0, "corners": 0, "radius": 17.0},
	{"beam": 520.0, "width": 14.0, "rings": 2, "sparkles": 5, "corners": 4, "radius": 21.0},
	{"beam": 900.0, "width": 20.0, "rings": 3, "sparkles": 8, "corners": 8, "radius": 26.0},
]
const OUTCOMES := ["heal", "damage", "speed", "giant", "chicken", "bomb"]   ## what a mystery box can turn into
const COLORS := {"heal": Color(0.35, 1.0, 0.45), "damage": Color(1.0, 0.3, 0.25), "speed": Color(0.3, 0.9, 1.0),
	"mystery": Color(0.75, 0.45, 1.0), "giant": Color(1.0, 0.65, 0.2), "chicken": Color(1.0, 0.95, 0.3), "bomb": Color(0.95, 0.25, 0.55),
	"slingshot": Color(0.8, 0.65, 0.4), "firecracker": Color(1.0, 0.55, 0.3), "hammer": Color(0.7, 0.72, 0.85), "frost_gun": Color(0.5, 0.85, 1.0),
	"boomerang": Color(0.4, 0.9, 0.5), "bomb_launcher": Color(0.9, 0.4, 0.2), "rocket": Color(1.0, 0.35, 0.3), "meteor": Color(1.0, 0.5, 0.15),
	"gatling": Color(1.0, 0.9, 0.4)}
const LABELS := {"heal": "Heal", "damage": "Double damage", "speed": "Speed boost", "mystery": "Mystery box",
	"giant": "GIANT!", "chicken": "Chicken curse", "bomb": "Hot potato!",
	"slingshot": "Slingshot", "firecracker": "Firecracker", "hammer": "War Hammer", "frost_gun": "Frost Gun", "boomerang": "Boomerang",
	"bomb_launcher": "Bomb Launcher", "rocket": "ROCKET LAUNCHER", "meteor": "METEOR STORM", "gatling": "GATLING GUN"}
const ICONS := {"heal": "+", "damage": "x2", "speed": ">>", "mystery": "?", "giant": "XL", "chicken": "bk", "bomb": "!!",
	"slingshot": "sl", "firecracker": "fc", "hammer": "HM", "frost_gun": "ice", "boomerang": "bm", "bomb_launcher": "BL",
	"rocket": "RK", "meteor": "MT", "gatling": "GT"}
const FALL_TIME := 0.55   ## spawn-in: the badge drops from the sky this long
const FALL_HEIGHT := 600.0

## Tier of a kind (Tier enum value).
static func tier_of(k: String) -> int:
	return KIND_TIER.get(k, Tier.COMMON)

static func tier_color(k: String) -> Color:
	return TIER_COLORS[tier_of(k)]

static func tier_name(k: String) -> String:
	return TIER_NAMES[tier_of(k)]

## A weighted random kind; r in [0, 1) (the host passes randf()).
static func roll(r: float) -> String:
	var total := 0.0
	for k: String in KINDS:
		total += WEIGHTS[k]
	var x := r * total
	for k: String in KINDS:
		x -= WEIGHTS[k]
		if x < 0.0:
			return k
	return KINDS[0]

## A Friendslop drop. `boost` (0..1) is the catch-up bias for a trailing player: it shifts weight from commons to rares and epics.
static func roll_fs(r: float, boost := 0.0) -> String:
	var total := 0.0
	for k: String in FS_WEIGHTS:
		total += fs_weight(k, boost)
	var x := r * total
	for k: String in FS_WEIGHTS:
		x -= fs_weight(k, boost)
		if x < 0.0:
			return k
	return "heal"

static func fs_weight(k: String, boost: float) -> float:
	return FS_WEIGHTS[k] * (1.0 + CATCHUP_TIER_GAIN[tier_of(k)] * clampf(boost, 0.0, 1.0))

static func is_weapon(k: String) -> bool:
	return k in FS_WEAPONS

## What a mystery box becomes; r in [0, 1). In Friendslop the weapons are in the box too.
static func mystery_outcome(r: float, with_weapons := false) -> String:
	var pool: Array = OUTCOMES + FS_WEAPONS if with_weapons else OUTCOMES
	return pool[clampi(int(r * pool.size()), 0, pool.size() - 1)]

var id := 0
var kind := "heal"
var _t := randf() * TAU
var _age := 0.0
var _landed := false
var _tier := Tier.COMMON
var _look: Dictionary

func _ready() -> void:
	z_index = 5  # beam and icon stay readable over trees
	add_to_group("pvp_pickups")
	_tier = tier_of(kind)
	_look = TIER_LOOK[_tier]
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body)
	if _tier == Tier.EPIC:
		add_child(_rising_particles())
	if is_inside_tree() and Sfx:
		match _tier:
			Tier.EPIC: Sfx.play("crown", Vector2.INF, 2.0)
			Tier.RARE: Sfx.play("respawn", position, -4.0)

func _on_body(body: Node) -> void:
	var p := body as Player
	if p and p.owns() and not p.down:
		touched.emit(id, p.peer_id)

## Epic only: embers drifting up the beam.
func _rising_particles() -> CPUParticles2D:
	var pt := CPUParticles2D.new()
	pt.amount = 20
	pt.lifetime = 1.8
	pt.local_coords = true
	pt.position = Vector2.ZERO
	pt.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	pt.emission_sphere_radius = 30.0
	pt.direction = Vector2.UP
	pt.spread = 12.0
	pt.gravity = Vector2.ZERO
	pt.initial_velocity_min = 90.0
	pt.initial_velocity_max = 220.0
	pt.scale_amount_min = 2.0
	pt.scale_amount_max = 4.5
	pt.color = Color(TIER_COLORS[Tier.EPIC], 0.9)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	pt.color_ramp = fade
	pt.emitting = true
	return pt

## One-shot burst when the badge lands (epic: bigger).
func _land_burst() -> void:
	_landed = true
	if _tier == Tier.COMMON:
		return
	var pt := CPUParticles2D.new()
	pt.one_shot = true
	pt.explosiveness = 1.0
	pt.amount = 36 if _tier == Tier.EPIC else 14
	pt.lifetime = 0.7
	pt.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	pt.emission_sphere_radius = 10.0
	pt.direction = Vector2.UP
	pt.spread = 180.0
	pt.gravity = Vector2(0, 300)
	pt.initial_velocity_min = 120.0
	pt.initial_velocity_max = 380.0 if _tier == Tier.EPIC else 240.0
	pt.scale_amount_min = 2.5
	pt.scale_amount_max = 5.0
	pt.color = TIER_COLORS[_tier]
	add_child(pt)
	pt.emitting = true
	get_tree().create_timer(1.2).timeout.connect(pt.queue_free)

func _process(delta: float) -> void:
	_t += delta * (4.5 if _tier == Tier.EPIC else 3.0)
	_age += delta
	if not _landed and _age >= FALL_TIME:
		_land_burst()
	queue_redraw()

func _draw() -> void:
	var c: Color = TIER_COLORS[_tier]
	var kc: Color = COLORS[kind]
	var pulse := 0.5 + 0.5 * sin(_t)
	var fall := clampf(1.0 - _age / FALL_TIME, 0.0, 1.0)
	var look_r: float = _look.radius
	var beam_h: float = _look.beam
	var half_w: float = _look.width
	var beam_a := 0.30 + 0.25 * pulse * (_tier + 1) / 3.0
	var ramp := clampf(_age / 0.4, 0.0, 1.0)   # beam grows in
	var bc := Color(c, beam_a)
	var tip := -beam_h * ramp
	draw_polygon(PackedVector2Array([Vector2(-half_w * 1.6, 0), Vector2(half_w * 1.6, 0), Vector2(half_w * 0.5, tip), Vector2(-half_w * 0.5, tip)]),
		PackedColorArray([bc, bc, Color(c, 0.0), Color(c, 0.0)]))
	if _tier >= Tier.RARE:   # bright core
		var cc := Color(1, 1, 1, beam_a * 0.8)
		draw_polygon(PackedVector2Array([Vector2(-half_w * 0.5, 0), Vector2(half_w * 0.5, 0), Vector2(0, tip * 0.6)]),
			PackedColorArray([cc, cc, Color(1, 1, 1, 0)]))
	# ground glow + rings (ring count is part of the tier read)
	var base_r := 40.0 + pulse * 8.0
	draw_circle(Vector2.ZERO, base_r, Color(c, 0.16 + 0.1 * _tier))
	for i in int(_look.rings):
		var rr := base_r + i * 14.0 + (pulse * 6.0 if i > 0 else 0.0)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32, Color(c, 0.9 - i * 0.2), 3.0)
	if _tier == Tier.EPIC:   # expanding shockwaves
		for i in 2:
			var k := fposmod(_t / TAU * 1.2 + i * 0.5, 1.0)
			draw_arc(Vector2.ZERO, 40.0 + k * 150.0, 0.0, TAU, 40, Color(c, (1.0 - k) * 0.7), 4.0 * (1.0 - k) + 1.0)
	if _age < 1.0:   # spawn ping ring
		var k := _age
		draw_arc(Vector2.ZERO, 30.0 + k * 220.0, 0.0, TAU, 40, Color(c, 1.0 - k), 5.0 * (1.0 - k) + 1.0)
	# orbiting sparkles (rare/epic)
	var n: int = _look.sparkles
	for i in n:
		var a := _t * 0.6 + TAU * i / n
		var sp := Vector2(cos(a) * (46.0 + 6.0 * sin(_t + i)), sin(a) * 18.0 - 30.0 + sin(a) * 6.0)
		draw_circle(sp, 2.5 if _tier == Tier.RARE else 3.2, Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 2.0 + i)))
	# badge: circle / diamond / octagon-star by tier, falls in from the sky
	var y := sin(_t) * 4.0 - 34.0 - fall * fall * FALL_HEIGHT
	var corners: int = _look.corners
	var ctr := Vector2(0, y)
	draw_circle(Vector2(0, 0), 14.0 * (1.0 - fall * 0.5), Color(0, 0, 0, 0.35 * (1.0 - fall)))   # ground shadow
	if corners == 0:
		draw_circle(ctr, look_r + 3.0, Color(0, 0, 0, 0.6))
		draw_circle(ctr, look_r, kc)
	else:
		var outer := _poly(ctr, look_r + 4.0, corners, _tier == Tier.EPIC)
		var inner := _poly(ctr, look_r, corners, _tier == Tier.EPIC)
		draw_colored_polygon(outer, Color(0, 0, 0, 0.65))
		draw_colored_polygon(inner, kc)
		draw_polyline(inner + PackedVector2Array([inner[0]]), c, 2.5)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-20, y + 6), ICONS[kind], HORIZONTAL_ALIGNMENT_CENTER, 40, 18, Color.BLACK)
	var label_size := 16 + _tier * 2
	draw_string_outline(font, Vector2(-80, y - look_r - 12), LABELS[kind], HORIZONTAL_ALIGNMENT_CENTER, 160, label_size, 4, Color.BLACK)
	draw_string(font, Vector2(-80, y - look_r - 12), LABELS[kind], HORIZONTAL_ALIGNMENT_CENTER, 160, label_size, Color.WHITE)

## Regular n-gon (diamond for 4); `star` alternates the radius for a spiky epic badge.
func _poly(ctr: Vector2, r: float, n: int, star: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n - PI / 2.0
		var rr := r * (0.78 if star and i % 2 == 1 else 1.0)
		pts.append(ctr + Vector2(cos(a), sin(a)) * rr)
	return pts
