class_name SheetFrames
## Builds SpriteFrames from horizontal strip sheets. Frame width = sheet width / count.
## Usage: SheetFrames.build({"idle": [path, 6], "run": [path, 4, 10.0, true]})
## Each entry: [texture_path, frame_count, fps = 10, loop = true]
## Multi-row sheets (the isometric packs: one row per facing): pass rows and the row to cut.

const FX := "res://assets/isometric_projecttile/"   ## frame-folder effects for play_once / seq

const FACE_HYSTERESIS := 0.17   ## rad (~10 deg) past a 45 deg facing boundary before the row flips: no flicker on the edge

static var _cache: Dictionary = {}

static func build(anims: Dictionary, row := 0, rows := 1) -> SpriteFrames:
	var key := "%s|%d/%d" % [anims, row, rows]
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name: String in anims:
		var spec: Array = anims[anim_name]
		var tex: Texture2D = load(spec[0])
		var count: int = spec[1]
		var fw := tex.get_width() / float(count)
		var fh := tex.get_height() / float(rows)
		assert(tex.get_width() % count == 0, "%s: width %d not divisible by %d" % [spec[0], tex.get_width(), count])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, spec[2] if spec.size() > 2 else 10.0)
		frames.set_animation_loop(anim_name, spec[3] if spec.size() > 3 else true)
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * fw, row * fh, fw, fh)
			frames.add_frame(anim_name, atlas)
	_cache[key] = frames
	return frames

## One SpriteFrames per facing of an 8-direction isometric sheet (8 rows: SE, S, SW, W, NW, N, NE, E).
static func build_dirs(anims: Dictionary) -> Array[SpriteFrames]:
	var out: Array[SpriteFrames] = []
	for r in 8:
		out.append(build(anims, r, 8))
	return out

## Turns `s` to face `dir` by swapping in that facing's frames, keeping the animation, frame and play state.
static func face(s: AnimatedSprite2D, dirs: Array[SpriteFrames], dir: Vector2) -> void:
	if dir == Vector2.ZERO or dirs.is_empty():
		return
	var cur := dirs.find(s.sprite_frames)   # row r faces (r + 1) * 45 deg: angle 0 (east) is row 7, +45 deg (south-east) row 0
	if cur >= 0 and absf(angle_difference((cur + 1) * PI / 4.0, dir.angle())) < PI / 8.0 + FACE_HYSTERESIS:
		return
	var f := dirs[(roundi(dir.angle() / (PI / 4.0)) + 7) % 8]
	if s.sprite_frames == f:
		return
	var anim := s.animation
	var fr := s.frame
	var prog := s.frame_progress
	var playing := s.is_playing()
	s.sprite_frames = f   # this stops the sprite, so restore where it was
	s.animation = anim
	if playing:
		s.play(anim)
	s.set_frame_and_progress(fr, prog)

## Fire-and-forget effect: plays a sheet once at pos, then frees itself.
static func play_once(parent: Node, pos: Vector2, path: String, count: int, fps := 20.0, sc := 1.0) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = seq(path, fps, false) if path.ends_with("/") else build({"fx": [path, count, fps, false]})
	s.position = pos
	s.scale = Vector2.ONE * sc
	parent.add_child(s)
	s.play("fx")
	s.animation_finished.connect(s.queue_free)
	return s

## SpriteFrames ("fx") from a folder of numbered frame images (the isometric_projecttile packs: 0001.png, 0003.png, ...).
static func seq(dir: String, fps := 20.0, loop := true) -> SpriteFrames:
	var key := "seq|%s|%s|%s" % [dir, fps, loop]
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.rename_animation("default", "fx")
	frames.set_animation_speed("fx", fps)
	frames.set_animation_loop("fx", loop)
	for i in range(1, 64, 2):
		var p := dir + "%04d.png" % i
		if not ResourceLoader.exists(p):
			break
		frames.add_frame("fx", load(p))
	_cache[key] = frames
	return frames
