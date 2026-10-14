@tool  # ponytail: only so the in-editor test runner can instantiate it; it does nothing in the editor
class_name Tension extends Node
## Tension rises with time spent in the level (only while the game is unpaused: Node._process stops under pause).
## Each full LEVEL_TIME is a new tension level -> level_reached, which the game mode answers with a slot-machine roll.

signal level_reached(level: int)

const LEVEL_TIME := 60.0   ## seconds per tension level

var elapsed := 0.0
var level := 0

func _ready() -> void:
	RuleSet.current.reset()   # every run starts clean

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	elapsed += delta
	while elapsed >= (level + 1) * LEVEL_TIME:
		level += 1
		level_reached.emit(level)

## 0..1 progress towards the next level.
func progress() -> float:
	return fmod(elapsed, LEVEL_TIME) / LEVEL_TIME

## Debug / future "relief" hook: jump to the next level now.
func skip_level() -> void:
	advance((level + 1) * LEVEL_TIME - elapsed)
