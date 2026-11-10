extends Node
## Autoload "Sfx": fire-and-forget sound effects. Drop .ogg/.wav files into assets/audio named "<sound>.ogg" or
## "<sound>_1.ogg", "<sound>_2.ogg"...; several files under one name are picked at random.
## A sound with no files is silently skipped, so the game runs before any audio is added.
## Sounds used: swing shoot hit hit_big explosion dash pickup kill death respawn splash bomb_tick bomb_boom cluck emote crown fight win

const DIR := "res://assets/audio/"
const POOL := 12
const MIN_GAP_MSEC := 45          ## the same sound twice inside this window is dropped (a 5-bolt fan is one sound, not five)
const BUS := "SFX"                ## own bus with a limiter, so an explosion on top of a hit cannot clip (made in _ready: no layout file)
## Per-sound loudness trim in dB, added to the caller's own volume. Picked blind (the clips were chosen by file name):
## tune by ear. Positive = louder.
const TRIM_DB := {"explosion": -4.0, "bomb_boom": -4.0, "crown": -3.0, "fight": -3.0, "win": -3.0,
	"swing": -4.0, "shoot": -3.0, "hit": 2.0, "hit_big": 2.0}

var _streams := {}                ## sound name -> Array[AudioStream]
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer2D] = []
var _last := {}                   ## sound name -> msec it last played

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the slot machine pauses the tree and still wants its sounds
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -2.0
		AudioServer.add_bus_effect(idx, limiter)
	for i in POOL:
		var f := AudioStreamPlayer.new()
		f.bus = BUS
		add_child(f)
		_flat.append(f)
		var s := AudioStreamPlayer2D.new()
		s.bus = BUS
		s.max_distance = 1800.0
		add_child(s)
		_spatial.append(s)
	_scan()

func _scan() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file in DirAccess.get_files_at(DIR):
		var f := file.trim_suffix(".import").trim_suffix(".remap")   # exported builds only keep the .import / .remap stubs
		if f.get_extension() not in ["ogg", "wav"]:
			continue
		var key := f.get_basename()
		var tail := key.rfind("_")
		if tail > 0 and key.substr(tail + 1).is_valid_int():
			key = key.substr(0, tail)
		var stream := load(DIR + f) as AudioStream
		if stream:
			if not _streams.has(key):
				_streams[key] = []
			_streams[key].append(stream)

func has(sound: String) -> bool:
	return _streams.has(sound)

## pos given = positional (fades with distance from the camera); otherwise it plays flat.
## `pitch` multiplies the playback speed (0.8 = deeper and heavier, 1.3 = lighter), on top of the usual +-6% variation.
func play(sound: String, pos := Vector2.INF, vol_db := 0.0, pitch := 1.0) -> void:
	var list: Array = _streams.get(sound, [])
	var now := Time.get_ticks_msec()
	if list.is_empty() or now - int(_last.get(sound, -1000)) < MIN_GAP_MSEC:
		return
	_last[sound] = now
	var stream: AudioStream = list.pick_random()
	var speed := randf_range(0.94, 1.06) * pitch
	vol_db += TRIM_DB.get(sound, 0.0)
	if pos.is_finite():
		var p := _free(_spatial)
		p.stream = stream
		p.global_position = pos
		p.volume_db = vol_db
		p.pitch_scale = speed
		p.play()
	else:
		var p := _free(_flat)
		p.stream = stream
		p.volume_db = vol_db
		p.pitch_scale = speed
		p.play()

## First idle player, else the first one (cut it off rather than drop the new sound).
func _free(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]
