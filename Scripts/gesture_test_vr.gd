extends Node

# ==============================================================================
# GestureTestVR — Script for the VR gesture recognition test scene
# ==============================================================================
# This scene lets you test the P$ recognizer directly on-device without the
# full game loop.  The user holds the trigger to record a gesture, releases to
# recognise it.  Results are shown on a 3D label floating in front of the camera.
# ==============================================================================

@onready var gesture_recognition: Node = $GestureRecognition
@onready var result_label: Label3D     = $XROrigin3D/XRCamera3D/ResultLabel3D
@onready var status_label: Label3D     = $XROrigin3D/XRCamera3D/StatusLabel3D
@onready var tracker                   = $XROrigin3D/RightController/GestureInputTracker

func _ready() -> void:
	# Initialise OpenXR
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		print("[GestureTestVR] OpenXR initialised.")
	else:
		push_warning("[GestureTestVR] OpenXR not found — running without XR (desktop preview).")

	# Wire the tracker → recognizer
	tracker.gesture_recorded.connect(_on_gesture_recorded)

	_set_status("Hold trigger to record a gesture.")
	_set_result("")

func _on_gesture_recorded(points: Array) -> void:
	_set_status("Recognising…")
	var result: Array = gesture_recognition.recognize_raw(points)
	var name_str: String = result[0]
	var score: float     = result[1]
	_set_result("'%s'\n(score %.2f)" % [name_str, score])
	_set_status("Hold trigger for next gesture.")
	print("[GestureTestVR] Recognised: '%s'  score=%.3f" % [name_str, score])

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

func _set_result(text: String) -> void:
	if result_label:
		result_label.text = text
