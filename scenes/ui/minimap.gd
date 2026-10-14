@tool  # ponytail: only so the in-editor test runner can instantiate it; it does nothing in the editor
class_name Minimap extends CanvasLayer
## Top-right minimap: just the island silhouette (dark where unexplored, parchment where explored).
## Camps, objective sites and the boss gate only show once the players have been near them.

const CELL := 2.0                          ## px per map cell on screen (128 cells = 256 px)
const MARGIN := 24.0
const UNEXPLORED := Color(0.09, 0.10, 0.07, 0.88)
const EXPLORED := Color(0.74, 0.64, 0.44, 0.95)
const COAST := 0.45                        ## coast cells are darkened by this much

var _map: WorldMap
var _disc: MapDiscovery
var _img: Image
var _tex: ImageTexture
var _canvas := Canvas.new()

func setup(map: WorldMap, disc: MapDiscovery) -> void:
	_map = map
	_disc = disc
	layer = 2
	_img = Image.create(WorldMap.SIZE.x, WorldMap.SIZE.y, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_canvas.mm = self
	_canvas.size = Vector2(WorldMap.SIZE) * CELL
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_canvas)
	disc.changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	for y in WorldMap.SIZE.y:
		for x in WorldMap.SIZE.x:
			var c := Vector2i(x, y)
			var col := Color(0, 0, 0, 0)
			if _map.is_land(c):
				col = EXPLORED if _disc.explored[y * WorldMap.SIZE.x + x] == 1 else UNEXPLORED
				if not (_map.is_land(c + Vector2i.LEFT) and _map.is_land(c + Vector2i.RIGHT) and _map.is_land(c + Vector2i.UP) and _map.is_land(c + Vector2i.DOWN)):
					col = col.lerp(Color(0.04, 0.03, 0.02, col.a), COAST * 2.0)
			_img.set_pixel(x, y, col)
	_tex.update(_img)

func _process(_delta: float) -> void:
	_canvas.position = Vector2(get_viewport().get_visible_rect().size.x - _canvas.size.x - MARGIN, MARGIN)
	_canvas.queue_redraw()

func _to_mini(pos: Vector2) -> Vector2:
	return pos / WorldMap.TILE * CELL

class Canvas extends Control:
	var mm: Minimap

	func _draw() -> void:
		if mm._map == null:
			return
		draw_texture_rect(mm._tex, Rect2(Vector2.ZERO, size), false)
		for camp: Dictionary in mm._map.camps:
			if mm._disc.is_explored(camp.pos):
				_diamond(mm._to_mini(camp.pos), 5.0, Color(0.9, 0.2, 0.15))
		for site in mm._map.objective_sites:
			if mm._disc.is_explored(site):
				var p := mm._to_mini(site)
				_diamond(p, 6.0, Color(1.0, 0.82, 0.25))
				draw_circle(p, 1.5, Color(0.25, 0.15, 0.0))
		if mm._disc.is_explored(mm._map.gate_pos):
			var g := mm._to_mini(mm._map.gate_pos)
			draw_circle(g, 6.0, Color.BLACK)
			draw_circle(g, 4.5, Color(0.65, 0.35, 0.95))
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			if mm._disc.is_visible_now(e.global_position):
				draw_circle(mm._to_mini(e.global_position), 2.0, Color(1.0, 0.25, 0.2))
		for p: Player in get_tree().get_nodes_in_group("players"):
			var c := mm._to_mini(p.global_position)
			var col := Color(0.35, 1.0, 0.4) if p.player_index == 0 else Color(1.0, 0.9, 0.3)
			draw_circle(c, 2.0, col)
			draw_arc(c, 5.0, 0.0, TAU, 20, Color.BLACK, 3.5)
			draw_arc(c, 5.0, 0.0, TAU, 20, col, 1.8)

	func _diamond(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 1.5)
