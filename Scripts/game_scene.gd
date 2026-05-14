extends Node

@onready var speech_recognition: Node  = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition
# The GestureInputTracker is expected to be a child of the XR right-hand
# controller in whatever scene instantiates this one (or at the path below
# if a self-contained XR rig is added to game_scene.tscn).
@onready var gesture_tracker           = $GestureInputTracker

func _ready() -> void:
	GameManager.speech_comp  = speech_recognition
	GameManager.gesture_comp = gesture_recognition

	# Wire the controller tracker → recognizer
	if gesture_tracker:
		gesture_tracker.gesture_recorded.connect(
			gesture_recognition.on_gesture_recorded
		)
		print("[GameScene] GestureInputTracker wired.")
	else:
		push_warning("[GameScene] GestureInputTracker node not found — gesture input will not work.")

	GameManager._on_game_scene_ready()
