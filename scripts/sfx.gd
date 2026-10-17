extends Node
## Autoload "Sfx": fire-and-forget sound effects. Drop .ogg/.wav files into assets/audio named "<sound>.ogg" or
## "<sound>_1.ogg", "<sound>_2.ogg"...; several files under one name are picked at random.
## A sound with no files is silently skipped, so the game runs before any audio is added.
## Sounds used: swing shoot hit hit_big explosion dash pickup kill death respawn splash bomb_tick bomb_boom cluck emote crown fight win

const DIR := "res://assets/audio/"
const POOL := 12
const MIN_GAP_MSEC := 45          ## the same sound twice inside this window is dropped (a 5-bolt fan is one sound, not five)

var _streams := {}                ## sound name -> Array[AudioStream]
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer2D] = []
var _last := {}                   ## sound name -> msec it last played

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the slot machine pauses the tree and still wants its sounds
	for i in POOL:
		var f := AudioStreamPlayer.new()
		add_child(f)
		_flat.append(f)
		var s := AudioStreamPlayer2D.new()
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
func play(sound: String, pos := Vector2.INF, vol_db := 0.0) -> void:
	var list: Array = _streams.get(sound, [])
	var now := Time.get_ticks_msec()
	if list.is_empty() or now - int(_last.get(sound, -1000)) < MIN_GAP_MSEC:
		return
	_last[sound] = now
	var stream: AudioStream = list.pick_random()
	var pitch := randf_range(0.94, 1.06)
	if pos.is_finite():
		var p := _free(_spatial)
		p.stream = stream
		p.global_position = pos
		p.volume_db = vol_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p := _free(_flat)
		p.stream = stream
		p.volume_db = vol_db
		p.pitch_scale = pitch
		p.play()

## First idle player, else the first one (cut it off rather than drop the new sound).
func _free(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]
