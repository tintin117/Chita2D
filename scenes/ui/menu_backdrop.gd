class_name MenuBackdrop extends Node2D
## The live arena behind the main menu: the real level, with a few heroes standing at its spawns.
## show_arena() cross-fades to another one, so picking an arena previews it.

const FADE := 0.25
const HERO_SIZE := 2.0   ## bigger than in a match: here they are the poster, not a unit

var frame := Rect2(560, 70, 680, 560):   ## where the level is fitted, in screen px
	set(v):
		frame = v
		if _view:
			_fit(_view)

var _view: WorldMap
var _arena := -1

func show_arena(index: int) -> void:
	if index == _arena:
		return
	_arena = index
	var old := _view
	_view = Arenas.create(index)
	add_child(_view)
	_view.generate_arena(Arenas.info(index).scene == "")   # the Colosseum draws itself only when built; painted levels already show
	var spots := _view.spawn_points
	var heroes := Hero.all()
	for i in 4:
		var at := spots[i * 2 + (i % 2)].lerp(_view.spawn_point, 0.25)
		var s := AnimatedSprite2D.new()
		var dirs: Array[SpriteFrames] = heroes[(i * 3 + index) % heroes.size()].dir_frames(Player.COLORS[i])
		s.sprite_frames = dirs[1]
		s.scale = Vector2.ONE * Player.SPRITE_SCALE * HERO_SIZE
		s.offset = Vector2(0, -16)
		s.position = at
		_view.add_child(s)
		s.play("idle")
		SheetFrames.face(s, dirs, _view.spawn_point - at)
	_fit(_view)
	if old:
		_view.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(_view, "modulate:a", 1.0, FADE)
		t.tween_callback(old.queue_free)

## Scales and centres `view` so its ground fills `frame`.
func _fit(view: WorldMap) -> void:
	var area := Rect2(view.spawn_point, Vector2.ZERO)
	if view.colosseum:
		area = Rect2(view.colosseum.to_world(Colosseum.FLOOR.position), Colosseum.FLOOR.size * Colosseum.S)
	else:
		var ground: TileMapLayer = view.get_node("Ground")
		for c in ground.get_used_cells():
			area = area.expand(ground.transform * ground.map_to_local(c))
	var k := minf(frame.size.x / area.size.x, frame.size.y / area.size.y)
	view.scale = Vector2.ONE * k
	view.position = frame.get_center() - area.get_center() * k
