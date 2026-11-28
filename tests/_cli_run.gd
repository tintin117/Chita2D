extends SceneTree

func _initialize() -> void:
	_run.call_deferred()   # suites need the autoloads and the root to be ready

func _run() -> void:
	var r := McpTestRunner.new()
	var fails := 0
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			var s = load("res://tests/" + f).new()
			r.run_suite(s)
	for e in r._results:
		if not e.get("passed", false):
			fails += 1
			print("FAIL ", e.get("suite"), ".", e.get("test"), ": ", e.get("message"))
	print("TOTAL ", r._results.size(), " FAILS ", fails)
	quit(fails)
