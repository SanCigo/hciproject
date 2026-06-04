extends Node

# ==============================================================================
# GestureRecognition — P$ Point-Cloud 3D Gesture Recognizer (GDScript 2.0 port)
# ==============================================================================
# Loads pre-recorded gesture templates from GESTURE_DATA_PATH and gesture
# definitions (mode, hand, mirror) from GESTURE_CONFIG_PATH.
#
# Single-hand gestures:
#   Only input from the configured hand is evaluated.
#
# Multi-hand (bimanual) gestures:
#   Both hands record their strokes independently.  When both have committed
#   their stroke, the pair is evaluated together.  If a mirror is configured,
#   the designated hand's points are flipped along the mirror axis before
#   matching, so a single recorded template suffices for symmetric gestures.
#
# Workflow:
#   1. Templates loaded from GESTURE_DATA_PATH on _ready().
#   2. Gesture definitions loaded from GESTURE_CONFIG_PATH on _ready().
#   3. GameManager emits gesture_required(id) → _evaluate_gesture(id) fires,
#      putting the node into LISTENING state.
#   4. GestureInputTracker(s) emit gesture_recorded(hand, points) on trigger
#      release.  This node routes the input according to the active definition.
#   5. gesture_evaluated(bool) is emitted back to GameManager when a decision
#      has been reached (single: immediately; multi: when both hands are in).
# ==============================================================================

signal gesture_evaluated(result: bool, score: float)

# Path to the JSON file exported from the recording application.
const GESTURE_DATA_PATH   := "res://gestures/p_c_data.json"
# Path to the gesture definition config (mode, hand, mirror, etc.).
const GESTURE_CONFIG_PATH := "res://gestures/gesture_config.json"

# Number of points the P$ algorithm resamples every candidate/template to.
const NUM_POINTS := 32

# Recognition confidence threshold — results below this score are rejected.
const MIN_SCORE := 0.28

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _templates: Dictionary = {}   # name:String → Array[Vector3]
var _gesture_defs: Dictionary = {} # name:String → definition Dictionary

var expected_gesture := ""        # Gesture name set by GameManager
var listening := false            # Whether we are waiting for a gesture

# Bimanual buffering
var _left_pending  := false       # Waiting for left hand result
var _right_pending := false       # Waiting for right hand result
var _left_cloud:  Array = []      # Normalised left-hand point cloud
var _right_cloud: Array = []      # Normalised right-hand point cloud

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_templates()
	_load_gesture_config()

# ---------------------------------------------------------------------------
# Public API called by GestureInputTracker(s)
# ---------------------------------------------------------------------------

## Called when a tracker has finished recording a gesture stroke.
## hand   — "left" or "right" (set via @export on GestureInputTracker)
## points — Array[Vector3] of world-space controller positions.
func on_gesture_recorded(hand: String, points: Array) -> void:
	if not listening:
		return
	if points.size() < 2:
		print("[GestureRecognition] Too few points from %s hand, ignoring." % hand)
		return

	var def: Dictionary = _gesture_defs.get(expected_gesture, {})
	if def.is_empty():
		push_warning("[GestureRecognition] No definition for gesture '%s'" % expected_gesture)
		return

	var mode: String = def.get("mode", "single")

	if mode == "single":
		_handle_single(hand, points, def)
	else:
		_handle_multi(hand, points, def)


## Called directly by a test harness (e.g. the 2-D test scene).
## Returns [gesture_name: String, score: float].
func recognize_raw(points: Array) -> Array:
	return recognize(points)

# ---------------------------------------------------------------------------
# GameManager signal handlers
# ---------------------------------------------------------------------------
func _evaluate_gesture(expected: String) -> void:
	expected_gesture = expected
	listening = true
	_left_cloud.clear()
	_right_cloud.clear()
	var def: Dictionary = _gesture_defs.get(expected, {})
	var mode: String = def.get("mode", "single")
	if mode == "multi":
		_left_pending  = true
		_right_pending = true
	else:
		_left_pending  = false
		_right_pending = false
	print("[GestureRecognition] Listening for gesture '%s' (mode=%s)" % [expected_gesture, mode])

func stop_listening() -> void:
	expected_gesture = ""
	listening = false
	_left_pending  = false
	_right_pending = false
	_left_cloud.clear()
	_right_cloud.clear()

# ---------------------------------------------------------------------------
# Single-hand routing
# ---------------------------------------------------------------------------
func _handle_single(hand: String, points: Array, def: Dictionary) -> void:
	var expected_hand: String = def.get("hand", "right")
	if hand != expected_hand:
		print("[GestureRecognition] Ignoring %s hand (expecting %s)." % [hand, expected_hand])
		return

	var template_name: String = def.get("template_name", "")
	var cloud := _make_cloud(points)
	if cloud.is_empty():
		listening = false
		gesture_evaluated.emit(false, 0.0)
		return

	var result := _match_cloud(cloud, template_name)
	var matched_name: String = result[0]
	var score: float        = result[1]

	print("[GestureRecognition] Single %s: got='%s' score=%.3f  (expecting='%s')" \
		% [hand, matched_name, score, template_name])

	listening = false
	gesture_evaluated.emit(score >= MIN_SCORE and matched_name == template_name, score)

# ---------------------------------------------------------------------------
# Bimanual routing
# ---------------------------------------------------------------------------
func _handle_multi(hand: String, points: Array, def: Dictionary) -> void:
	var cloud := _make_cloud(points)
	if cloud.is_empty():
		return

	if hand == "left":
		if not _left_pending:
			return
		_left_cloud  = cloud
		_left_pending = false
		print("[GestureRecognition] Buffered LEFT hand stroke.")
	elif hand == "right":
		if not _right_pending:
			return
		_right_cloud  = cloud
		_right_pending = false
		print("[GestureRecognition] Buffered RIGHT hand stroke.")

	# Both hands in → evaluate
	if not _left_pending and not _right_pending:
		_evaluate_multi(def)

func _evaluate_multi(def: Dictionary) -> void:
	var left_tpl:  String = def.get("left_template",  "")
	var right_tpl: String = def.get("right_template", "")
	var mirror: bool      = def.get("mirror", false)
	var mirror_axis: String   = def.get("mirror_axis",   "x")
	var mirrored_hand: String = def.get("mirrored_hand", "")

	# Optionally flip one hand's cloud before matching
	var left_cloud  := _left_cloud.duplicate()
	var right_cloud := _right_cloud.duplicate()
	if mirror:
		if mirrored_hand == "left":
			left_cloud = _mirror_points(left_cloud, mirror_axis)
		elif mirrored_hand == "right":
			right_cloud = _mirror_points(right_cloud, mirror_axis)

	var left_result  := _match_cloud(left_cloud,  left_tpl)
	var right_result := _match_cloud(right_cloud, right_tpl)

	var left_name:  String = left_result[0]
	var left_score: float  = left_result[1]
	var right_name: String = right_result[0]
	var right_score: float = right_result[1]

	print("[GestureRecognition] Multi — LEFT: '%s' %.3f (exp '%s') | RIGHT: '%s' %.3f (exp '%s')" \
		% [left_name, left_score, left_tpl, right_name, right_score, right_tpl])

	listening = false
	var success := (left_score  >= MIN_SCORE and left_name  == left_tpl) \
			   and (right_score >= MIN_SCORE and right_name == right_tpl)
	var combined_score := (left_score + right_score) / 2.0
	gesture_evaluated.emit(success, combined_score)

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
		var gesture_name: String = entry.get("name", "")
		var raw_pts = entry.get("points", [])
		var pts: Array[Vector3] = []
		for p in raw_pts:
			pts.append(Vector3(p["x"], p["y"], p["z"]))
		# The JSON already stores normalized (resampled + scaled + centered)
		# point clouds — store them directly.
		_templates[gesture_name] = pts

	print("[GestureRecognition] Loaded %d gesture templates." % _templates.size())

func _load_gesture_config() -> void:
	_gesture_defs.clear()
	if not FileAccess.file_exists(GESTURE_CONFIG_PATH):
		push_error("[GestureRecognition] Config file not found: " + GESTURE_CONFIG_PATH)
		return

	var file := FileAccess.open(GESTURE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[GestureRecognition] Failed to open config: " + GESTURE_CONFIG_PATH)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[GestureRecognition] Config JSON parse error: " + json.get_error_message())
		return

	var data = json.get_data()
	if not data is Array:
		push_error("[GestureRecognition] Unexpected config JSON root type.")
		return

	for entry in data:
		var gesture_name: String = entry.get("name", "")
		if gesture_name != "":
			_gesture_defs[gesture_name] = entry
	print("[GestureRecognition] Loaded %d gesture definitions." % _gesture_defs.size())

# ---------------------------------------------------------------------------
# P$ Recognition pipeline
# ---------------------------------------------------------------------------

## Main entry point: takes a raw Array[Vector3] stroke, normalises it and
## matches against all templates.  Returns [name: String, score: float].
func recognize(points: Array) -> Array:
	if _templates.is_empty():
		return ["no match", 0.0]

	var candidate_pts := _make_cloud(points)
	if candidate_pts.is_empty():
		return ["no match", 0.0]

	return _best_template_match(candidate_pts)

## Match a pre-built normalised cloud against a specific named template.
## Returns [name: String, score: float].
func _match_cloud(cloud: Array, template_name: String) -> Array:
	if not _templates.has(template_name):
		push_warning("[GestureRecognition] Template '%s' not found." % template_name)
		return ["no match", 0.0]

	var template_pts: Array = _templates[template_name]
	var dist := _cloud_match(cloud, template_pts, INF)
	var score := 1.0 / dist if dist > 1.0 else 1.0
	return [template_name, score]

## Find the best-matching template across all loaded templates.
func _best_template_match(candidate_pts: Array) -> Array:
	var best_name := "no match"
	var best_dist := INF

	for tpl_name in _templates:
		var template_pts: Array = _templates[tpl_name]
		var d := _cloud_match(candidate_pts, template_pts, best_dist)
		if d < best_dist:
			best_dist = d
			best_name = tpl_name

	if best_name == "no match":
		return ["no match", 0.0]

	var score := 1.0 / best_dist if best_dist > 1.0 else 1.0
	return [best_name, score]

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

## Flip point coordinates along the specified axis.
func _mirror_points(points: Array, axis: String) -> Array:
	var result: Array[Vector3] = []
	for p: Vector3 in points:
		match axis:
			"x": result.append(Vector3(-p.x,  p.y,  p.z))
			"y": result.append(Vector3( p.x, -p.y,  p.z))
			"z": result.append(Vector3( p.x,  p.y, -p.z))
			_:   result.append(p)   # Unknown axis — pass through unchanged
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
