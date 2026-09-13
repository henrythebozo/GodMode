class_name TestCase
extends RefCounted
## Minimal assertion helper for the headless test runner.

var failures: PackedStringArray = PackedStringArray()
var checks := 0
var current := ""


func assert_true(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg if msg != "" else "expected true"])


func assert_eq(a, b, msg: String = "") -> void:
	checks += 1
	if a != b:
		failures.append("%s: %s (got %s, expected %s)" % [current, msg, str(a), str(b)])


func assert_near(a: float, b: float, tol: float, msg: String = "") -> void:
	checks += 1
	if abs(a - b) > tol:
		failures.append("%s: %s (got %s, expected %s ± %s)" % [current, msg, str(a), str(b), str(tol)])


func run_all() -> void:
	for m in get_method_list():
		if m.name.begins_with("test_"):
			current = m.name
			call(m.name)
