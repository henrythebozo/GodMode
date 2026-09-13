extends SceneTree
## Headless test runner:  godot --headless --path breachline -s tests/run_tests.gd

const SUITES := ["test_economy", "test_damage", "test_weapon_config", "test_netproto", "test_match_state"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# autoloads need one frame to be ready
	await process_frame
	await process_frame
	var total_checks := 0
	var failures := PackedStringArray()
	for name in SUITES:
		var script := load("res://tests/%s.gd" % name)
		var suite: TestCase
		if name == "test_match_state":
			suite = script.new(self)
		else:
			suite = script.new()
		suite.run_all()
		total_checks += suite.checks
		for f in suite.failures:
			failures.append("[%s] %s" % [name, f])
		print("%-22s %3d checks, %d failures" % [name, suite.checks, suite.failures.size()])
	print("------------------------------------------")
	if failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % total_checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("%d FAILURES of %d checks" % [failures.size(), total_checks])
		quit(1)
