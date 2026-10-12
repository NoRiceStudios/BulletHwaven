class_name TestCase
extends RefCounted
## Base class for tests. Subclasses define `test_*` methods and use the assert helpers.
## A failed assertion records a message and the test continues.

var failures: Array[String] = []
var assertion_count: int = 0
var current_test: String = ""


func assert_true(cond: bool, msg: String = "") -> void:
	assertion_count += 1
	if not cond:
		failures.append("%s: assert_true failed %s" % [current_test, msg])


func assert_false(cond: bool, msg: String = "") -> void:
	assertion_count += 1
	if cond:
		failures.append("%s: assert_false failed %s" % [current_test, msg])


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	assertion_count += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s %s" % [current_test, str(expected), str(actual), msg])


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	assertion_count += 1
	if typeof(a) == typeof(b) and a == b:
		failures.append("%s: expected values to differ, both %s %s" % [current_test, str(a), msg])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	assertion_count += 1
	if not a > b:
		failures.append("%s: expected %s > %s %s" % [current_test, str(a), str(b), msg])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	assertion_count += 1
	if not a < b:
		failures.append("%s: expected %s < %s %s" % [current_test, str(a), str(b), msg])
