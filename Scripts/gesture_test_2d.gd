extends Node

# ==============================================================================
# GestureTest2D — Desktop / VR-less gesture recognition test scene
# ==============================================================================
# Draw a gesture path on the canvas with the mouse (click + drag).
# The path is mapped onto a flat XZ plane (Y = 0) and fed to the P$ recognizer.
# ==============================================================================

@onready var gesture_recognition: Node = $GestureRecognition
@onready var draw_canvas              = $UI/VBox/DrawCanvas   # DrawCanvas (Control subclass)
@onready var result_label: Label      = $UI/VBox/ResultLabel
@onready var status_label: Label      = $UI/VBox/StatusLabel
@onready var clear_btn: Button        = $UI/VBox/HBox/ClearButton
@onready var recognize_btn: Button    = $UI/VBox/HBox/RecognizeButton

const SCALE := 0.005           # pixels → metres conversion factor
var _screen_points: Array[Vector2] = []
var _recording := false

func _ready() -> void:
	clear_btn.pressed.connect(_on_clear)
	recognize_btn.pressed.connect(_on_recognize)
	draw_canvas.gui_input.connect(_on_draw_input)
	_set_status("Click and drag inside the draw area to record a gesture.")
	result_label.text = ""

# ---------------------------------------------------------------------------
# Mouse input on the canvas
# ---------------------------------------------------------------------------
func _on_draw_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_screen_points.clear()
				_recording = true
				draw_canvas.clear_points()
				_set_status("Recording…")
			else:
				_recording = false
				_set_status("%d points recorded. Press Recognise or draw again." \
					% _screen_points.size())

	elif event is InputEventMouseMotion and _recording:
		_screen_points.append(event.position)
		draw_canvas.set_points(_screen_points.duplicate())

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------
func _on_clear() -> void:
	_screen_points.clear()
	_recording = false
	result_label.text = ""
	draw_canvas.clear_points()
	_set_status("Cleared. Draw a new gesture.")

func _on_recognize() -> void:
	if _screen_points.size() < 5:
		_set_status("Draw more points first!")
		return

	var pts_3d := _to_3d(_screen_points)
	var result: Array = gesture_recognition.recognize_raw(pts_3d)
	var name_str: String = result[0]
	var score: float     = result[1]
	result_label.text    = "'%s'   score: %.3f" % [name_str, score]
	_set_status("Recognition done. Draw again or press Clear.")
	print("[GestureTest2D] '%s'  score=%.3f" % [name_str, score])

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
## Maps 2D screen pixels to 3D points on the XZ plane (Y = 0).
func _to_3d(pts: Array[Vector2]) -> Array:
	var out: Array[Vector3] = []
	for p in pts:
		out.append(Vector3(p.x * SCALE, 0.0, p.y * SCALE))
	return out

func _set_status(text: String) -> void:
	status_label.text = text
