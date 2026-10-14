@tool
extends McpTestSuite
## Logic tests for the explored-cell bookkeeping behind the minimap.

func suite_name() -> String:
	return "discovery"

func _disc() -> MapDiscovery:
	var d := MapDiscovery.new()
	track(d)
	d.setup()
	return d

func test_reveal_marks_inside_sight_only() -> void:
	var d := _disc()
	var at := Vector2(2000, 2000)
	assert_false(d.is_explored(at))
	assert_true(d.reveal(at), "first reveal explores new cells")
	assert_true(d.is_explored(at))
	assert_true(d.is_explored(at + Vector2(MapDiscovery.SIGHT - 70.0, 0)), "inside the radius")
	assert_false(d.is_explored(at + Vector2(MapDiscovery.SIGHT + 70.0, 0)), "outside the radius")

func test_explored_persists_and_repeat_reveal_is_quiet() -> void:
	var d := _disc()
	d.reveal(Vector2(1000, 1000))
	assert_false(d.reveal(Vector2(1000, 1000)), "same spot reveals nothing new")
	d.reveal(Vector2(4000, 3000))
	assert_true(d.is_explored(Vector2(1000, 1000)), "stays explored after moving away")
	assert_false(d.is_explored(Vector2(2500, 2000)), "between the two spots is still unexplored")

func test_outside_the_map_is_never_explored() -> void:
	var d := _disc()
	assert_false(d.is_explored(Vector2(-50, -50)))
	assert_false(d.is_explored(Vector2(99999, 10)))
	d.reveal(Vector2(10, 10))   # near the corner must not crash
	assert_true(d.is_explored(Vector2(10, 10)))
