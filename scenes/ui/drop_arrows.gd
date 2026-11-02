class_name DropArrows extends Control
## HUD overlay: a screen-edge arrow for every arena drop outside the view (nearest and highest tier first, capped),
## plus a small pointer around the local player toward the nearest Rare+ drop. Reads the "pvp_pickups" group and
## the viewport's canvas transform, so it follows whatever camera the viewport has (online, solo bots or a split viewport).

const MAX_ARROWS := 5
const EDGE := 54.0               ## arrow centre inset from the screen edge
const TIER_BIAS := 1200.0        ## px of "distance" one tier is worth when choosing which arrows survive the cap
const METRE := float(WorldMap.TILE)
const NEAR_POINTER_MIN := 320.0  ## don't point at a Rare+ drop that is already right next to you

var player: Node2D               ## the local player (pointer ring + "nearest" origin)
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## Point where the ray from the rect centre toward `target` leaves the rect inset by `margin`; also tells if it was outside.
static func clamp_to_edge(target: Vector2, view: Vector2, margin: float) -> Dictionary:
	var centre := view / 2.0
	var half := centre - Vector2(margin, margin)
	var d := target - centre
	var inside := absf(d.x) <= half.x and absf(d.y) <= half.y
	if inside:
		return {"pos": target, "inside": true, "dir": d.normalized() if d != Vector2.ZERO else Vector2.UP}
	var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	return {"pos": centre + d * t, "inside": false, "dir": d.normalized()}

## Which drops get an arrow: sorted by distance minus a tier bonus, cut to `cap`.
static func rank(entries: Array, cap: int) -> Array:
	var out := entries.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.dist) - TIER_BIAS * int(a.tier) < float(b.dist) - TIER_BIAS * int(b.tier))
	return out.slice(0, cap)

func _draw() -> void:
	var view := get_viewport_rect().size
	var xf := get_viewport().get_canvas_transform()
	var origin: Vector2 = player.global_position if is_instance_valid(player) else (xf.affine_inverse() * (view / 2.0))
	var off: Array = []
	var nearest_rare := {}
	for n in get_tree().get_nodes_in_group("pvp_pickups"):
		var pk := n as PvpPickup
		if pk == null:
			continue
		var tier := PvpPickup.tier_of(pk.kind)
		var dist := origin.distance_to(pk.global_position)
		var edge := clamp_to_edge(xf * pk.global_position, view, EDGE)
		if tier >= PvpPickup.Tier.RARE and dist > NEAR_POINTER_MIN and (nearest_rare.is_empty() or dist < nearest_rare.dist):
			nearest_rare = {"dist": dist, "pk": pk}
		if not edge.inside:
			off.append({"dist": dist, "tier": tier, "kind": pk.kind, "edge": edge})
	for e: Dictionary in rank(off, MAX_ARROWS):
		_draw_arrow(e)
	if not nearest_rare.is_empty() and is_instance_valid(player):
		_draw_pointer(xf * player.global_position, (nearest_rare.pk.global_position - player.global_position).normalized(), nearest_rare.pk.kind)

func _draw_arrow(e: Dictionary) -> void:
	var tier: int = e.tier
	var col: Color = PvpPickup.TIER_COLORS[tier]
	var dir: Vector2 = e.edge.dir
	var pos: Vector2 = e.edge.pos
	var speed := 3.0 + tier * 2.0
	var pulse := 0.5 + 0.5 * sin(_t * speed)
	var s := (15.0 + tier * 5.0) * (1.0 + 0.12 * pulse)
	var side := dir.orthogonal()
	var tip := pos + dir * s
	# chevron count = tier + 1 (shape cue, not just colour)
	for i in tier + 1:
		var o := -dir * i * s * 0.75
		var pts := PackedVector2Array([tip + o, pos - dir * s * 0.45 + side * s * 0.9 + o, pos - dir * s * 0.1 + o, pos - dir * s * 0.45 - side * s * 0.9 + o])
		draw_colored_polygon(pts, Color(col, 0.75 + 0.25 * pulse))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.85), 2.0)
	var font := ThemeDB.fallback_font
	var txt := "%s %dm" % [PvpPickup.ICONS[e.kind], int(float(e.dist) / METRE)]
	var tpos := pos - dir * (s * 1.6 + 6.0 + tier * s * 0.75)
	tpos.x = clampf(tpos.x - 40.0, 4.0, size.x - 84.0)
	tpos.y = clampf(tpos.y + 6.0, 18.0, size.y - 6.0)
	draw_string_outline(font, tpos, txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, 5, Color.BLACK)
	draw_string(font, tpos, txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, col)

## Small chevron on a ring around the player toward the nearest Rare+ drop.
func _draw_pointer(at: Vector2, dir: Vector2, k: String) -> void:
	var tier := PvpPickup.tier_of(k)
	var col: Color = PvpPickup.TIER_COLORS[tier]
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var r := 70.0 + pulse * 4.0
	var side := dir.orthogonal()
	var p := at + dir * r
	draw_arc(at, r, dir.angle() - 0.5, dir.angle() + 0.5, 12, Color(col, 0.25), 2.0)
	var pts := PackedVector2Array([p + dir * 10.0, p - dir * 4.0 + side * 8.0, p - dir * 1.0, p - dir * 4.0 - side * 8.0])
	draw_colored_polygon(pts, Color(col, 0.55 + 0.3 * pulse))
