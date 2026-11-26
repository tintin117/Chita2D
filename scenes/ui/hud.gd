class_name Hud extends CanvasLayer
## Creates one HeroPanel per player (HP, gear, dash pips, the kit: LMB / RMB / passive / ult) and the boss bar.

const HINTS := [["LMB", "RMB", "F"], ["RT", "B", "Y"]]

var with_sheet := true   ## the Tab character sheet pauses the tree, so online matches turn it off
var online := false      ## one local player: always the P1 hints, bottom-left

func add_player(p: Player) -> void:
	var panel := HeroPanel.new()
	panel.player = p
	panel.mirror = p.player_index == 1 and not online
	add_child(panel)

var _boss_bar := BossBar.new()

func _ready() -> void:
	_boss_bar.size = Vector2(580, 55)
	add_child(_boss_bar)
	if with_sheet:
		add_child(CharacterSheet.new())

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_boss_bar.position = Vector2((vp.x - _boss_bar.size.x) / 2.0, 24)

class BossBar extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var boss := get_tree().get_first_node_in_group("boss") as Enemy
		if boss == null:
			return
		ArenaUi.panel(self, Rect2(Vector2.ZERO, size))
		var track := Rect2(20, 35, size.x - 40, 8)
		var ratio := clampf(float(boss.hp) / boss.max_hp, 0, 1)
		draw_rect(track, Color("#352322"))
		draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, track.size.y)), Color("#d8775e"))
		draw_string(ArenaUi.DISPLAY, Vector2(0, 28), "BLACK LANCER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, ArenaUi.GOLD)
