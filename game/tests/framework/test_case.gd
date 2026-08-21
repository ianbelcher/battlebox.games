class_name TestCase
extends RefCounted
## Base class for a unit test. Subclass it, add methods named `test_*`, and
## drop the file in tests/unit/ — the runner finds it by directory listing,
## so a new test needs no registration anywhere.
##
## Assertions record a failure and keep going rather than aborting, so one
## run reports every broken expectation instead of only the first.

var failures: Array[String] = []
var checks := 0

## Overridden by tests that need setup shared across their methods.
func before_each() -> void:
	pass

func after_each() -> void:
	pass

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func equal(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if not _same(actual, expected):
		failures.append("%s\n      expected: %s\n      actual:   %s"
			% [message, _show(expected), _show(actual)])

func not_equal(actual: Variant, unexpected: Variant, message: String) -> void:
	checks += 1
	if _same(actual, unexpected):
		failures.append("%s\n      expected anything but: %s"
			% [message, _show(unexpected)])

func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s\n      expected: %f (+/- %f)\n      actual:   %f"
			% [message, expected, tolerance, actual])

func between(actual: float, low: float, high: float, message: String) -> void:
	checks += 1
	if actual < low or actual > high:
		failures.append("%s\n      expected: %f..%f\n      actual:   %f"
			% [message, low, high, actual])

func has(container: Variant, key: Variant, message: String) -> void:
	checks += 1
	var found := false
	if container is Dictionary:
		found = (container as Dictionary).has(key)
	elif container is Array:
		found = (container as Array).has(key)
	elif container is String:
		found = (container as String).contains(str(key))
	if not found:
		failures.append("%s\n      %s is not in %s" % [message, _show(key), _show(container)])

func fail(message: String) -> void:
	checks += 1
	failures.append(message)

## Vector maths lands a hair off after a round trip through a float, and a
## test that fails on the last bit of a float is a test nobody trusts.
func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b)
	return a == b

func _show(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 200 else text.left(197) + "..."
