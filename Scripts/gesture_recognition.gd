extends Node

# ==============================================================================
# GestureRecognition — P$ Point-Cloud 3D Gesture Recognizer (GDScript 2.0 port)
# ==============================================================================
# Loads pre-recorded gesture templates from a JSON file and runs the P$
# algorithm to match incoming 3D point streams against them.
#
# Workflow:
#   1. Templates are loaded from GESTURE_DATA_PATH on _ready().
#   2. GameManager emits gesture_required(id) → _evaluate_gesture(id) fires,
#      which puts the node into LISTENING state.
#   3. While listening, the paired GestureInputTracker calls add_point(pos)
#      every physics frame as the controller moves.
#   4. When the tracker signals gesture_recorded(points), recognition runs
#      and gesture_evaluated(bool) is emitted back to GameManager.
# ==============================================================================

signal gesture_evaluated(result: bool)

# Path to the JSON file exported from the recording application.
const GESTURE_DATA_PATH := "res://gestures/p_c_data.json"

# Number of points the P$ algorithm resamples every candidate/template to.
const NUM_POINTS := 32

# Maps gesture integer IDs (used by GameManager) to template name strings
# (the "name" field in the JSON).  Edit this dictionary when you add gestures.
const GESTURE_ID_MAP: Dictionary = {
	1:  "squsre",
	11: "circlw",   # placeholder — update when more templates are recorded
	13: "triangle",
}

# Recognition confidence threshold — results below this score are rejected.
const MIN_SCORE := 0.01

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _templates: Array = []        # Array of [name: String, points: Array[Vector3]]
var expected_gesture := 0         # Integer ID set by GameManager
var listening := false            # Whether we are waiting for a gesture

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_templates()

# ---------------------------------------------------------------------------
# Public API called by GestureInputTracker
# ---------------------------------------------------------------------------

## Called when the tracker has finished recording a gesture stroke.
## points — Array[Vector3] of world-space controller positions.
func on_gesture_recorded(points: Array) -> void:
	if not listening:
		return
	if points.size() < 2:
		print("[GestureRecognition] Too few points, ignoring.")
		return

	var result := recognize(points)   # [name: String, score: float]
	var gesture_name: String = result[0]
	var score: float = result[1]
	print("[GestureRecognition] Result: '%s'  score=%.3f  (expecting id=%d → '%s')" \
		% [gesture_name, score, expected_gesture, _expected_name()])

	if score < MIN_SCORE or gesture_name == "no match":
		listening = false
		gesture_evaluated.emit(false)
		return

	var expected_name := _expected_name()
	var matched := (expected_name == "" or gesture_name == expected_name)
	listening = false
	gesture_evaluated.emit(matched)

## Called directly by a test harness (e.g. the 2-D test scene).
## Returns [gesture_name: String, score: float].
func recognize_raw(points: Array) -> Array:
	return recognize(points)

# ---------------------------------------------------------------------------
# GameManager signal handlers
# ---------------------------------------------------------------------------
func _evaluate_gesture(expected: int) -> void:
	expected_gesture = expected
	listening = true
	print("[GestureRecognition] Listening for gesture id=%d ('%s')" \
		% [expected_gesture, _expected_name()])

func stop_listening() -> void:
	expected_gesture = 0
	listening = false

# ---------------------------------------------------------------------------
# Template loading
# ---------------------------------------------------------------------------
func _load_templates() -> void:
	_templates.clear()
	if not FileAccess.file_exists(GESTURE_DATA_PATH):
		push_error("[GestureRecognition] Template file not found: " + GESTURE_DATA_PATH)
		return

	var file := FileAccess.open(GESTURE_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("[GestureRecognition] Failed to open: " + GESTURE_DATA_PATH)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[GestureRecognition] JSON parse error: " + json.get_error_message())
		return

	var data = json.get_data()
	if not data is Array:
		push_error("[GestureRecognition] Unexpected JSON root type.")
		return

	for entry in data:
		var name: String = entry.get("name", "")
		var raw_pts = entry.get("points", [])
		var pts: Array[Vector3] = []
		for p in raw_pts:
			pts.append(Vector3(p["x"], p["y"], p["z"]))
		# The JSON already stores normalized (resampled + scaled + centered)
		# point clouds — store them directly.
		_templates.append([name, pts])

	print("[GestureRecognition] Loaded %d gesture templates." % _templates.size())

# ---------------------------------------------------------------------------
# P$ Recognition pipeline
# ---------------------------------------------------------------------------

## Main entry point: takes a raw Array[Vector3] stroke, normalises it and
## matches against all templates.  Returns [name: String, score: float].
func recognize(points: Array) -> Array:
	if _templates.is_empty():
		return ["no match", 0.0]

	# Build the candidate cloud (resample → scale → translate to centroid)
	var candidate_pts := _make_cloud(points)
	if candidate_pts.is_empty():
		return ["no match", 0.0]

	var best_idx := -1
	var best_dist := INF

	for i in range(_templates.size()):
		var template_pts: Array = _templates[i][1]
		var d := _cloud_match(candidate_pts, template_pts, best_dist)
		if d < best_dist:
			best_dist = d
			best_idx = i

	if best_idx == -1:
		return ["no match", 0.0]

	# Convert distance to a 0–1 score (lower distance = higher score).
	var score := 1.0 / best_dist if best_dist > 1.0 else 1.0
	return [_templates[best_idx][0], score]

# ---------------------------------------------------------------------------
# P$ internal functions — all operating on Array[Vector3]
# ---------------------------------------------------------------------------

func _make_cloud(points: Array) -> Array:
	var resampled := _resample(points, NUM_POINTS)
	if resampled.is_empty():
		return []
	resampled = _scale(resampled)
	resampled = _translate_to_centroid(resampled)
	return resampled

## Resample the stroke to exactly n evenly-spaced points.
func _resample(points: Array, n: int) -> Array:
	if points.size() < 2:
		return []

	var total_len := _path_length(points)
	if total_len == 0.0:
		return []

	var interval := total_len / float(n - 1)
	var D := 0.0
	var result: Array[Vector3] = [points[0]]

	var pts := points.duplicate()   # working copy
	var i := 1
	while i < pts.size():
		var d: float = (pts[i - 1] as Vector3).distance_to(pts[i] as Vector3)
		if D + d >= interval and d != 0.0:
			var t: float = (interval - D) / d
			var q: Vector3 = (pts[i - 1] as Vector3).lerp(pts[i] as Vector3, t)
			result.append(q)
			pts.insert(i, q)   # re-insert so the remainder is processed
			D = 0.0
		else:
			D += d
		i += 1

	# Ensure we have exactly n points
	while result.size() < n:
		result.append(pts[pts.size() - 1])
	if result.size() > n:
		result.resize(n)

	return result

func _path_length(points: Array) -> float:
	var d := 0.0
	for i in range(1, points.size()):
		d += points[i - 1].distance_to(points[i])
	return d

## Scale so the bounding box fits in a unit cube.
func _scale(points: Array) -> Array:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for p: Vector3 in points:
		min_v.x = min(min_v.x, p.x)
		min_v.y = min(min_v.y, p.y)
		min_v.z = min(min_v.z, p.z)
		max_v.x = max(max_v.x, p.x)
		max_v.y = max(max_v.y, p.y)
		max_v.z = max(max_v.z, p.z)

	var size: float = max(max_v.x - min_v.x, max(max_v.y - min_v.y, max_v.z - min_v.z))
	var result: Array[Vector3] = []
	for p: Vector3 in points:
		if size == 0.0:
			result.append(Vector3.ZERO)
		else:
			result.append((p - min_v) / size)
	return result

## Translate so the centroid is at the origin.
func _translate_to_centroid(points: Array) -> Array:
	var c := Vector3.ZERO
	for p: Vector3 in points:
		c += p
	c /= float(points.size())
	var result: Array[Vector3] = []
	for p: Vector3 in points:
		result.append(p - c)
	return result

## P$ greedy cloud matching — compares candidate against one template.
func _cloud_match(candidate: Array, template: Array, min_so_far: float) -> float:
	var n := mini(candidate.size(), template.size())
	var step := int(floor(pow(n, 0.5)))
	if step == 0:
		step = 1

	var current_min := min_so_far
	var i := 0
	while i < n:
		var d1 := _cloud_distance(candidate, template, i)
		var d2 := _cloud_distance(template, candidate, i)
		current_min = min(current_min, min(d1, d2))
		i += step

	return current_min

## Greedy weighted nearest-neighbour distance from set a to set b,
## starting at index 'start' in a.
func _cloud_distance(a: Array, b: Array, start: int) -> float:
	var n := mini(a.size(), b.size())
	var matched := PackedByteArray()
	matched.resize(n)
	# PackedByteArray is zero-initialised → 0 = unmatched

	var i := start
	var total := 0.0
	var step_count := 0
	while true:
		var best_j := -1
		var best_d := INF
		for j in range(n):
			if matched[j] == 0:
				var d: float = (a[i % a.size()] as Vector3).distance_to(b[j] as Vector3)
				if d < best_d:
					best_d = d
					best_j = j
		if best_j == -1:
			break
		matched[best_j] = 1
		var w := 1.0 - float((i - start + n) % n) / float(n)
		total += w * best_d
		i = (i + 1) % n
		step_count += 1
		if step_count >= n:
			break

	return total

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _expected_name() -> String:
	return GESTURE_ID_MAP.get(expected_gesture, "")
