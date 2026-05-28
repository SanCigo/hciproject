extends Node3D

# ==============================================================================
# GestureInputTracker
# ==============================================================================
# Attach this as a child of an XRController3D node.
# It monitors a trigger button: press → start recording, release → emit the
# captured point cloud to GestureRecognition for matching.
#
# Scene setup:
#   XROrigin3D
#   └── XRController3D  (e.g. right hand, tracker = "right_hand")
#       └── GestureInputTracker  ← this node
# ==============================================================================

signal gesture_recorded(hand: String, points: Array)

## Minimum number of points required to attempt recognition.
@export var min_points := 5

## Minimum distance (metres) between consecutive recorded points.
## Avoids flooding the array when the controller is nearly stationary.
@export var min_sample_distance := 0.005

## The XR action name mapped to the trigger button.
## Must match your project's Input Map (default OpenXR trigger action).
@export var trigger_action := "trigger"

## Which controller this tracker is attached to: "left" or "right".
@export var hand := "right"

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _recording := false
var _points: Array[Vector3] = []
var _last_pos := Vector3.ZERO
var _controller: XRController3D = null

func _ready() -> void:
	_controller = get_parent() as XRController3D
	if _controller == null:
		push_error("[GestureInputTracker] Parent must be an XRController3D!")

func _physics_process(_delta: float) -> void:
	if _controller == null:
		return

	var pressed: bool = _controller.is_button_pressed(trigger_action)

	if pressed and not _recording:
		_start_recording()
	elif not pressed and _recording:
		_stop_recording()

	if _recording:
		_sample_point()

# ---------------------------------------------------------------------------
# Recording helpers
# ---------------------------------------------------------------------------
func _start_recording() -> void:
	_recording = true
	_points.clear()
	_last_pos = global_position
	print("[GestureInputTracker] Recording started.")

func _stop_recording() -> void:
	_recording = false
	print("[GestureInputTracker] Recording stopped — %d points." % _points.size())
	if _points.size() >= min_points:
		gesture_recorded.emit(hand, _points.duplicate())
	else:
		print("[GestureInputTracker] Too few points, discarding.")
	_points.clear()

func _sample_point() -> void:
	var pos := global_position
	if _points.is_empty() or pos.distance_to(_last_pos) >= min_sample_distance:
		_points.append(pos)
		_last_pos = pos

# ---------------------------------------------------------------------------
# Public: allow external code to manually push points (test scenes, etc.)
# ---------------------------------------------------------------------------
func push_point(pos: Vector3) -> void:
	_points.append(pos)
	_last_pos = pos

func force_stop() -> void:
	if _recording:
		_stop_recording()
