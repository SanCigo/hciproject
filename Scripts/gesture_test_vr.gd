extends Node

# ==============================================================================
# GestureTestVR — VR gesture recognition test scene (single + bimanual)
# ==============================================================================
# Tests every gesture type defined in gesture_config.json, including bimanual.
#
#   • Cycle gestures : press A / X button on either controller (or G on keyboard)
#   • Single-hand    : hold trigger on the configured hand
#   • Bimanual       : hold triggers on BOTH hands
#   • Results and per-hand status are displayed on floating 3-D labels
#
# The scene drives GestureRecognition through its full pipeline
# (on_gesture_recorded → single / multi routing → gesture_evaluated signal).
# ==============================================================================

@onready var gesture_recognition: Node = $GestureRecognition
@onready var result_label: Label3D     = $XROrigin3D/XRCamera3D/ResultLabel3D
@onready var status_label: Label3D     = $XROrigin3D/XRCamera3D/StatusLabel3D
@onready var gesture_label: Label3D    = $XROrigin3D/XRCamera3D/GestureLabel3D
@onready var info_label: Label3D       = $XROrigin3D/XRCamera3D/InfoLabel3D
@onready var right_tracker             = $XROrigin3D/RightController/GestureInputTracker
@onready var left_tracker              = $XROrigin3D/LeftController/GestureInputTracker

var _gesture_names: Array[String] = []
var _current_index := 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Initialise OpenXR
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		print("[GestureTestVR] OpenXR initialised.")
	else:
		push_warning("[GestureTestVR] OpenXR not found — running without XR (desktop preview).")

	# Wire both trackers → full recognition pipeline
	right_tracker.gesture_recorded.connect(_on_gesture_recorded)
	left_tracker.gesture_recorded.connect(_on_gesture_recorded)

	# Listen for recognition results
	gesture_recognition.gesture_evaluated.connect(_on_gesture_evaluated)

	# Wire controller buttons for cycling through gestures
	var right_ctrl := $XROrigin3D/RightController as XRController3D
	var left_ctrl  := $XROrigin3D/LeftController as XRController3D
	right_ctrl.button_pressed.connect(_on_controller_button)
	left_ctrl.button_pressed.connect(_on_controller_button)

	# Build gesture name list from loaded definitions
	for gname in gesture_recognition._gesture_defs:
		_gesture_names.append(gname)

	if _gesture_names.is_empty():
		_set_status("No gesture definitions found!")
		push_error("[GestureTestVR] No gesture definitions loaded from config.")
		return

	_select_gesture(0)


func _unhandled_input(event: InputEvent) -> void:
	# Desktop fallback: press G to cycle gestures
	if event.is_action_pressed("DEBUG_GESTURE_SKIP"):
		_next_gesture()


# ---------------------------------------------------------------------------
# Gesture selection & cycling
# ---------------------------------------------------------------------------

func _on_controller_button(button_name: String) -> void:
	# A / X button on either controller cycles to the next gesture
	if button_name in ["ax_button", "by_button"]:
		_next_gesture()


func _next_gesture() -> void:
	_select_gesture(_current_index + 1)


func _select_gesture(index: int) -> void:
	_current_index = index % _gesture_names.size()
	var gname: String = _gesture_names[_current_index]
	var def: Dictionary = gesture_recognition._gesture_defs.get(gname, {})
	var mode: String = def.get("mode", "single")

	# Build info text
	var info_text := ""
	if mode == "single":
		var hand: String = def.get("hand", "right")
		info_text = "Mode: SINGLE  •  Hand: %s" % hand.to_upper()
	else:
		var left_tpl: String  = def.get("left_template", "")
		var right_tpl: String = def.get("right_template", "")
		var mirror: bool      = def.get("mirror", false)
		info_text = "Mode: BIMANUAL"
		if mirror:
			info_text += "  (mirror %s on %s)" % [def.get("mirrored_hand", "?"), def.get("mirror_axis", "?")]
		info_text += "\nL-template: %s  |  R-template: %s" % [left_tpl, right_tpl]

	_set_gesture("%s   [%d / %d]" % [gname, _current_index + 1, _gesture_names.size()])
	_set_info(info_text)
	_set_result("")

	# Arm the recognizer for this gesture
	gesture_recognition._evaluate_gesture(gname)

	# Status hint
	if mode == "single":
		var hand: String = def.get("hand", "right")
		_set_status("Hold %s trigger to draw '%s'." % [hand.to_upper(), gname])
	else:
		_set_status("Hold BOTH triggers to draw '%s'." % gname)

	print("[GestureTestVR] Selected gesture: '%s'  mode=%s" % [gname, mode])


# ---------------------------------------------------------------------------
# Tracker callbacks
# ---------------------------------------------------------------------------

func _on_gesture_recorded(hand: String, points: Array) -> void:
	_set_status("%s hand recorded (%d pts)…" % [hand.to_upper(), points.size()])

	# Feed into the full recognition pipeline
	gesture_recognition.on_gesture_recorded(hand, points)

	# If still listening after the call, we're in bimanual mode waiting for the
	# other hand — update the status to show which hand is still needed.
	if gesture_recognition.listening:
		if gesture_recognition._left_pending:
			_set_status("RIGHT ✓  —  waiting for LEFT hand…")
		elif gesture_recognition._right_pending:
			_set_status("LEFT ✓  —  waiting for RIGHT hand…")


# ---------------------------------------------------------------------------
# Recognition result
# ---------------------------------------------------------------------------

func _on_gesture_evaluated(success: bool, score: float) -> void:
	if success:
		_set_result("✅  MATCH!  (score: %.3f)" % score)
		_set_status("Correct!  Press A/X or G for next gesture.")
	else:
		_set_result("❌  NO MATCH  (score: %.3f)" % score)
		_set_status("Try again, or press A/X or G for next gesture.")

	print("[GestureTestVR] Result: %s  score=%.3f" % [("MATCH" if success else "NO MATCH"), score])

	# Re-arm the recognizer after a short delay so the user can retry
	# the same gesture without manually cycling.
	var gname := _gesture_names[_current_index]
	await get_tree().create_timer(2.0).timeout

	# Only re-arm if we haven't switched gesture in the meantime
	if _gesture_names[_current_index] == gname and not gesture_recognition.listening:
		gesture_recognition._evaluate_gesture(gname)
		var def: Dictionary = gesture_recognition._gesture_defs.get(gname, {})
		var mode: String = def.get("mode", "single")
		if mode == "single":
			var hand: String = def.get("hand", "right")
			_set_status("Ready.  Hold %s trigger to draw '%s'." % [hand.to_upper(), gname])
		else:
			_set_status("Ready.  Hold BOTH triggers to draw '%s'." % gname)


# ---------------------------------------------------------------------------
# Label helpers
# ---------------------------------------------------------------------------

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

func _set_result(text: String) -> void:
	if result_label:
		result_label.text = text

func _set_gesture(text: String) -> void:
	if gesture_label:
		gesture_label.text = text

func _set_info(text: String) -> void:
	if info_label:
		info_label.text = text
