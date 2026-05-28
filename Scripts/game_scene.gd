extends Node

@onready var speech_recognition: Node  = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition
# Two GestureInputTracker nodes — one per XR controller.
# Each emits gesture_recorded(hand, points); the hand identifier is set via
# the @export var `hand` on each tracker node in the scene.
@onready var gesture_tracker_left  = $GestureInputTrackerLeft
@onready var gesture_tracker_right = $GestureInputTrackerRight

func _ready() -> void:
	GameManager.speech_comp  = speech_recognition
	GameManager.gesture_comp = gesture_recognition

	# Wire both controller trackers → recognizer
	var wired := 0
	for tracker in [gesture_tracker_left, gesture_tracker_right]:
		if tracker:
			tracker.gesture_recorded.connect(
				gesture_recognition.on_gesture_recorded
			)
			wired += 1
		else:
			push_warning("[GameScene] A GestureInputTracker node was not found — gesture input may not work.")

	print("[GameScene] %d GestureInputTracker(s) wired." % wired)

	GameManager._on_game_scene_ready()
