extends Node

signal speech_evaluated(result: bool)

var expected_speech := ""
var listening := false

func _ready() -> void:
	GameManager.speech_required.connect(evaluate_speech)
	GameManager.input_timeout.connect(stop_listening)

func evaluate_speech(expected: String) -> void:
	expected_speech = expected
	listening = true
	print("[SpeechRecognition] Listening for: ", expected_speech)

func _input(event):
	if not listening:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		listening = false
		print("[SpeechRecognition] Placeholder input received for: ", expected_speech)
		speech_evaluated.emit(true)

func stop_listening():
	expected_speech = ""
	listening = false
