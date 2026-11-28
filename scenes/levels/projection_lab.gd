extends Node2D
## Standalone visual reference. Run this scene with F6.

const ARENA_TILES := preload("res://scenes/levels/iso_tileset.tres")
const PROP := preload("res://scenes/levels/iso_prop.tscn")
const TILE_SCALE := 2.0
const GRID_RATIO := 0.5
const RING_CENTER := Vector2(0, 60)
const RING_RADIUS := 82.0
const FEET := [Vector2(-112, 32), Vector2(118, 33), Vector2(8, -72)]
const GUIDES := Color("#aee2fe")
const GOLD := Color("#ffe292")

var _camera: Camera2D
var _grid := true
var _compare := true
var _grid_lines := PackedVector2Array()
var _readout: Label

func _ready() -> void:
	var backdrop := CanvasLayer.new()
	backdrop.layer = -10
	add_child(backdrop)
	var background := ColorRect.new()
	background.color = Color("#182337")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(background)
	_camera = Camera2D.new()
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_camera.position = Vector2(0, -24)
	add_child(_camera)
	_camera.make_current()
	_make_tiles()
	_put_hero("paladin", FEET[0], 0)
	_put_hero("ranger", FEET[1], 2)
	var pillar := PROP.instantiate() as Sprite2D
	pillar.set("tile", 66)
	pillar.position = FEET[2]
	add_child(pillar)
	_make_legend()

func _make_tiles() -> void:
	var water := TileMapLayer.new()
	var ground := TileMapLayer.new()
	for layer in [water, ground]:
		layer.tile_set = ARENA_TILES
		layer.scale = Vector2.ONE * TILE_SCALE
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer)
	water.z_index = -2
	ground.z_index = -1
	var half := Vector2(ARENA_TILES.tile_size) * TILE_SCALE * 0.5
	for y in range(-28, 29):
		for x in range(-28, 29):
			var cell := Vector2i(x, y)
			var at := ground.map_to_local(cell) * TILE_SCALE
			var edge := absf(at.x) / 375.0 + absf(at.y + 6.0) / 177.0
			if edge <= 1.0:
				ground.set_cell(cell, 0, Vector2i(posmod(x + 2 * y, 3), 2))
				var corners := [at + Vector2(0, -half.y), at + Vector2(half.x, 0),
					at + Vector2(0, half.y), at + Vector2(-half.x, 0)]
				for side in 4:
					_grid_lines.append(corners[side])
					_grid_lines.append(corners[(side + 1) % 4])
			elif edge < 1.55:
				water.set_cell(cell, 0, Vector2i(posmod(x + y, 3), 10))

func _put_hero(id: String, feet: Vector2, facing: int) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Hero.by_id(id).dir_frames("Blue")[facing]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = feet - Vector2(0, 14)
	sprite.offset = Vector2(0, -16)
	sprite.scale = Vector2.ONE * Player.SPRITE_SCALE
	add_child(sprite)
	sprite.play("idle")

func _make_legend() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 14)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#151f2d")
	plate.set_corner_radius_all(7)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	plate.content_margin_top = 9
	plate.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", plate)
	ui.add_child(panel)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 16)
	panel.add_child(_readout)
	_refresh_legend()

func _refresh_legend() -> void:
	_readout.text = "Arena projection lab   ·   %d%% zoom\n" % roundi(_camera.zoom.x * 100)
	_readout.text += "1  Actual size     2  Match wide     G  Grid     C  Compare rings\n"
	_readout.text += "Blue ring  Tile grid 0.50"
	if _compare:
		_readout.text += "     Gold ring  Purify %.2f" % Purification.GROUND_SQUASH

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_camera.zoom = Vector2.ONE * GameCamera.MAX_ZOOM
		KEY_2:
			_camera.zoom = Vector2.ONE * GameCamera.MIN_ZOOM
		KEY_G:
			_grid = not _grid
		KEY_C:
			_compare = not _compare
		_:
			return
	queue_redraw()
	_refresh_legend()

func _draw() -> void:
	if _grid and not _grid_lines.is_empty():
		draw_multiline(_grid_lines, Color(GUIDES, 0.27), 1.0)
	_draw_ground_ring(GRID_RATIO, GUIDES)
	if _compare:
		_draw_ground_ring(Purification.GROUND_SQUASH, GOLD)
	for point in FEET:
		draw_line(point + Vector2(-5, 0), point + Vector2(5, 0), GOLD, 1.5)
		draw_line(point + Vector2(0, -4), point + Vector2(0, 4), GOLD, 1.5)

func _draw_ground_ring(ratio: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 73:
		points.append(RING_CENTER + Vector2.from_angle(TAU * i / 72.0) * RING_RADIUS * Vector2(1, ratio))
	draw_polyline(points, color, 2, true)
