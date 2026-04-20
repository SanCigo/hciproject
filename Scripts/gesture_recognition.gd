extends Node

signal gesture_evaluated(result: bool)

var expected_gesture := ""
var listening := false

func _ready() -> void:
	GameManager.gesture_required.connect(_evaluate_gesture)
	GameManager.input_timeout.connect(stop_listening)

func _evaluate_gesture(expected: String) -> void:
	expected_gesture = expected
	listening = true
	print("[GestureRecognition] Listening for: ", expected_gesture)

func _input(event):
	if not listening:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		listening = false
		print("[GestureRecognition] Placeholder input received for: ", expected_gesture)
		gesture_evaluated.emit(true)

func stop_listening():
	expected_gesture = ""
	listening = false
