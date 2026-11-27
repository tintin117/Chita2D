class_name GymPanel extends PanelContainer
## The gym's side panel (top left): the picked hero, one-click hero swap, the gym tools and every setting.
## The arrow in the header (or Esc) folds it away. Nothing here takes focus, so Space and Tab stay with the hero.

signal hero_picked(index: int)
signal free_spells(on: bool)
signal reset
signal quit

const WIDTH := 264.0
const FONT := 16
const ROW := 26   ## button height

var _portrait: TextureRect
var _name: Label
var _role: Label
var _fold: Button
var _body: VBoxContainer
var _cards: Array[Button] = []

func _ready() -> void:
	theme = ArenaUi.THEME
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size.x = WIDTH
	position = Vector2(12, 12)
	var frame := ArenaUi.THEME.get_stylebox("panel", "Panel").duplicate() as StyleBox   # the thin frame: no room for the menus' one
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_content_margin(side, 14.0)   # clear of the corner curls
	add_theme_stylebox_override("panel", frame)
	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_portrait = ArenaUi.picture(null, Vector2(44, 44))
	header.add_child(_portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(words)
	_name = ArenaUi.label("", 20, ArenaUi.SUN)
	_role = ArenaUi.label("", FONT, ArenaUi.MOSS)
	words.add_child(_name)
	words.add_child(_role)
	_fold = ArenaUi.button("<", toggle)
	_fold.custom_minimum_size.x = 28
	_fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_fold)

	_body = VBoxContainer.new()
	box.add_child(_body)
	_section("Hero   [Tab]")
	var heroes := Hero.pickable()   # the gym's hero indices count the unlocked secret heroes too
	var grid := GridContainer.new()
	grid.columns = 5 if heroes.size() > 12 else 4   # with a secret unlocked: still three rows, so the panel grows no taller
	_body.add_child(grid)
	var group := ButtonGroup.new()
	for i in heroes.size():
		var card := ArenaUi.button("", func() -> void: hero_picked.emit(i))
		card.theme_type_variation = &"SmallCard"
		card.toggle_mode = true
		card.button_group = group
		card.tooltip_text = heroes[i].display_name
		card.icon = _face(heroes[i])
		card.expand_icon = true
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if heroes[i].base_id != "":
			card.self_modulate = heroes[i].tint.lerp(Color.WHITE, 0.4)
		grid.add_child(card)
		_cards.append(card)

	_section("Gym")
	var tools := HBoxContainer.new()   # one row: the panel must end above the HUD
	_body.add_child(tools)
	var free := ArenaUi.button("Free spells: Off", Callable())
	free.toggle_mode = true
	free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	free.toggled.connect(func(on: bool) -> void:
		free.text = "Free spells: On" if on else "Free spells: Off"
		free_spells.emit(on))
	tools.add_child(free)
	tools.add_child(ArenaUi.button("Reset [R]", reset.emit))

	_section("Settings")
	MatchOverlay.add_settings(_body, false)   # no room for the "Playtest" caption under "SETTINGS"
	_body.add_child(ArenaUi.button("Quit to menu", quit.emit))
	_compact(self)
	for card in _cards:   # after _compact: the hero cards are bigger than the text buttons
		card.custom_minimum_size = Vector2(56 if grid.columns == 4 else 44, 46)

## Marks hero `i` as the one being played.
func show_hero(i: int) -> void:
	var hero := Hero.pickable()[i]
	_portrait.texture = _face(hero)
	_name.text = hero.display_name
	_role.text = hero.archetype
	_cards[i].button_pressed = true   # the group lets go of the old card; `pressed` is not emitted

func toggle() -> void:
	_body.visible = not _body.visible
	_fold.text = "<" if _body.visible else ">"
	reset_size()   # shrink to the header when folded

## The hero's portrait with the empty border of its atlas cell cut off, so it reads at this size.
func _face(hero: Hero) -> Texture2D:
	var face := ArenaUi.portrait(hero, Player.COLORS[0]) as AtlasTexture
	face.region = face.region.grow(-face.region.size.x * 0.18)
	return face

func _section(title: String) -> void:
	_body.add_child(ArenaUi.label(title.to_upper(), FONT, ArenaUi.SUN))

## Smaller text, rows and gaps than the full-screen menus use (the panel must end above the HUD), and no keyboard
## focus anywhere.
func _compact(node: Node) -> void:
	if node is BoxContainer or node is GridContainer:
		node.add_theme_constant_override("separation", 3)
		node.add_theme_constant_override("h_separation", 4)
		node.add_theme_constant_override("v_separation", 3)
	if node is Button or node is Slider:
		node.focus_mode = Control.FOCUS_NONE
	if node is Button:
		node.custom_minimum_size.y = ROW
		node.add_theme_font_size_override("font_size", FONT)
		if node.theme_type_variation == &"":
			node.theme_type_variation = &"SmallButton"
	elif node is Label and node != _name:
		node.add_theme_font_size_override("font_size", FONT)
	elif node is Slider:
		node.custom_minimum_size.y = 18
		node.theme_type_variation = &"SmallSlider"
	for child in node.get_children():
		_compact(child)
