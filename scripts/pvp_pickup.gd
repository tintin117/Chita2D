class_name PvpPickup extends Area2D
## Arena power-up. Only the owning peer of the player who touches it reports it (`touched`); the host decides who got it first.

signal touched(id: int)

const KINDS := ["heal", "damage", "speed", "mystery", "giant", "chicken", "bomb"]
const WEIGHTS := {"heal": 3, "damage": 2, "speed": 2, "mystery": 3, "giant": 2, "chicken": 1, "bomb": 1}   ## how often the host spawns each kind
const OUTCOMES := ["heal", "damage", "speed", "giant", "chicken", "bomb"]   ## what a mystery box can turn into
const COLORS := {"heal": Color(0.35, 1.0, 0.45), "damage": Color(1.0, 0.3, 0.25), "speed": Color(0.3, 0.9, 1.0),
	"mystery": Color(0.75, 0.45, 1.0), "giant": Color(1.0, 0.65, 0.2), "chicken": Color(1.0, 0.95, 0.3), "bomb": Color(0.95, 0.25, 0.55)}
const LABELS := {"heal": "Heal", "damage": "Double damage", "speed": "Speed boost", "mystery": "Mystery box",
	"giant": "GIANT!", "chicken": "Chicken curse", "bomb": "Hot potato!"}
const ICONS := {"heal": "+", "damage": "x2", "speed": ">>", "mystery": "?", "giant": "XL", "chicken": "bk", "bomb": "!!"}
const BEAM_H := 700.0

## A weighted random kind; r in [0, 1) (the host passes randf()).
static func roll(r: float) -> String:
	var total := 0
	for k: String in KINDS:
		total += WEIGHTS[k]
	var x := r * total
	for k: String in KINDS:
		x -= WEIGHTS[k]
		if x < 0.0:
			return k
	return KINDS[0]

## What a mystery box becomes; r in [0, 1).
static func mystery_outcome(r: float) -> String:
	return OUTCOMES[clampi(int(r * OUTCOMES.size()), 0, OUTCOMES.size() - 1)]

var id := 0
var kind := "heal"
var _t := randf() * TAU

func _ready() -> void:
	z_index = 5  # beam and icon stay readable over trees
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	var p := body as Player
	if p and p.is_multiplayer_authority() and not p.down:
		touched.emit(id)

func _process(delta: float) -> void:
	_t += delta * 3.0
	queue_redraw()

func _draw() -> void:
	var c: Color = COLORS[kind]
	var pulse := 0.5 + 0.5 * sin(_t)
	var bright := Color(c, 0.35)
	draw_polygon(PackedVector2Array([Vector2(-18, 0), Vector2(18, 0), Vector2(8, -BEAM_H), Vector2(-8, -BEAM_H)]),
		PackedColorArray([bright, bright, Color(c, 0.0), Color(c, 0.0)]))  # light beam, fades upward
	draw_circle(Vector2.ZERO, 40.0 + pulse * 8.0, Color(c, 0.18))
	draw_arc(Vector2.ZERO, 40.0 + pulse * 8.0, 0.0, TAU, 32, Color(c, 0.9), 3.0)
	var y := sin(_t) * 4.0 - 34.0
	draw_circle(Vector2(0, y), 20.0, Color(0, 0, 0, 0.6))
	draw_circle(Vector2(0, y), 17.0, c)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-20, y + 6), ICONS[kind], HORIZONTAL_ALIGNMENT_CENTER, 40, 18, Color.BLACK)
	draw_string(font, Vector2(-70, y - 28), LABELS[kind], HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color.WHITE)
