class_name SheetFrames
## Builds SpriteFrames from horizontal strip sheets. Frame width = sheet width / count.
## Usage: SheetFrames.build({"idle": [path, 6], "run": [path, 4, 10.0, true]})
## Each entry: [texture_path, frame_count, fps = 10, loop = true]

static var _cache: Dictionary = {}

static func build(anims: Dictionary) -> SpriteFrames:
	var key := str(anims)
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name: String in anims:
		var spec: Array = anims[anim_name]
		var tex: Texture2D = load(spec[0])
		var count: int = spec[1]
		var fw := tex.get_width() / float(count)
		assert(tex.get_width() % count == 0, "%s: width %d not divisible by %d" % [spec[0], tex.get_width(), count])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, spec[2] if spec.size() > 2 else 10.0)
		frames.set_animation_loop(anim_name, spec[3] if spec.size() > 3 else true)
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * fw, 0, fw, tex.get_height())
			frames.add_frame(anim_name, atlas)
	_cache[key] = frames
	return frames

## Fire-and-forget effect: plays a sheet once at pos, then frees itself.
static func play_once(parent: Node, pos: Vector2, path: String, count: int, fps := 20.0, sc := 1.0) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = build({"fx": [path, count, fps, false]})
	s.position = pos
	s.scale = Vector2.ONE * sc
	parent.add_child(s)
	s.play("fx")
	s.animation_finished.connect(s.queue_free)
	return s
