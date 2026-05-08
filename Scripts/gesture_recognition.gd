extends Node

signal gesture_evaluated(result: bool)

var expected_gesture := 0	# Name of required gesture
							#set by "gesture_required" signal from GameManager
var listening := false		# Tracks if the node is processing input

func _ready() -> void:
	GameManager.gesture_required.connect(_evaluate_gesture)
	GameManager.input_timeout.connect(stop_listening)

func _evaluate_gesture(expected: int) -> void:
	expected_gesture = expected
	listening = true
	print("[GestureRecognition] Listening for: ", expected_gesture)

func _input(event):
	if not listening:
		return
	
	#TODO: Should be replaced by actual gesture recognition functionality
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		listening = false
		print("[GestureRecognition] Placeholder input received for: ", expected_gesture)
		gesture_evaluated.emit(true)

func stop_listening():
	expected_gesture = 0
	listening = false
