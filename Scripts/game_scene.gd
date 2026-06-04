extends Node

signal action_show_finished()
signal action_evaluated(result: bool)
signal feedback_finished()

@onready var speech_recognition: Node  = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition

@onready var vr_player: VRPlayer = $GameWorld/VRPlayer
@onready var avatar: Avatar = $GameWorld/Avatar


func _ready() -> void:
	GameManager.game_scene = self
	
	# Connect signals
	GameManager.action_revealed.connect(_on_action_revealed)
	GameManager.action_required.connect(_on_action_required)
	GameManager.feedback_given.connect(_on_feedback_given)
	GameManager.input_timeout.connect(_on_input_timeout)
	gesture_recognition.gesture_evaluated.connect(_on_gesture_evaluated)
	speech_recognition.speech_evaluated.connect(_on_speech_evaluated)
	avatar.animation_finished.connect(_on_animation_finished)
	vr_player.restart_requested.connect(_on_restart_requested)
	GameManager.game_over.connect(_on_game_over)
	
	# Initialise OpenXR
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		print("[GestureTestVR] OpenXR initialised.")
	else:
		push_warning("[GestureTestVR] OpenXR not found — running without XR (desktop preview).")
	
	# Wire both controller trackers → recognizer
	var wired := 0
	var trackers = vr_player.get_trackers()
	for tracker in trackers:
		if tracker:
			tracker.gesture_recorded.connect(_on_tracker_gesture_recorded)
			wired += 1
		else:
			push_warning("[GameScene] A GestureInputTracker node was not found — gesture input may not work.")

	print("[GameScene] %d GestureInputTracker(s) wired." % wired)

	GameManager._on_game_scene_ready()

var current_expected_type: int = -1

func _on_tracker_gesture_recorded(hand: String, points: Array) -> void:
	if GameManager.state == GameManager.GameState.WAITING_INPUT and current_expected_type == Action.ActionType.SPEECH:
		if speech_recognition.is_busy():
			print("[GameScene] Gesture performed while speech is busy processing. Ignoring to prevent race condition.")
			return
		else:
			print("[GameScene] Out-of-sequence gesture performed while waiting for speech! Failing.")
			action_evaluated.emit(false)
			return
	
	gesture_recognition.on_gesture_recorded(hand, points)

# ---------------------------------------------------------------------------
# GameManager signal handlers
# ---------------------------------------------------------------------------
func _on_action_revealed(action: Action) -> void:
	var text = ""
	match action.type:
		Action.ActionType.GESTURE:
			text += "Do: "
		Action.ActionType.SPEECH:
			text += "Say: "
	if action.name : text += action.name
	else: text += "%s" % action.index
	
	$GameWorld/Label3D.text = text
	
	match action.type:
		Action.ActionType.GESTURE:
			if action.name: avatar.play_animation(action.name)
		Action.ActionType.SPEECH:
			if action.name: avatar.say_word(action.name)
			await get_tree().create_timer(1).timeout
			action_show_finished.emit()

func _on_action_required(expected_action: Action) -> void:
	current_expected_type = expected_action.type
	match expected_action.type:
		Action.ActionType.GESTURE:
			gesture_recognition._evaluate_gesture(expected_action.name)
		Action.ActionType.SPEECH:
			speech_recognition._evaluate_speech(expected_action.index)

func _on_feedback_given(_success: bool, message: String, duration: float) -> void:
	gesture_recognition.stop_listening()
	speech_recognition.stop_listening()
	$GameWorld/Label3D.text = message
	await get_tree().create_timer(duration).timeout
	$GameWorld/Label3D.text = ""
	feedback_finished.emit()

func _on_input_timeout() -> void:
	gesture_recognition.stop_listening()
	speech_recognition.stop_listening()

func _on_game_over(score: int) -> void:
	$GameWorld/Label3D.text = "Game Over!\nScore: %d\nHold B or Y to Try Again" % score

func _on_restart_requested() -> void:
	if GameManager.state == GameManager.GameState.GAME_OVER:
		GameManager.restart_game()

# ---------------------------------------------------------------------------
# Gesture/Speech recognition signal handlers
# ---------------------------------------------------------------------------
func _on_gesture_evaluated(result: bool, score: float) -> void:
	print("[GameScene] Gesture result: %s  score=%.3f" % [("MATCH" if result else "NO MATCH"), score])
	action_evaluated.emit(result)
	#GameManager._on_gesture_result(result)

func _on_speech_evaluated(result: bool) -> void:
	action_evaluated.emit(result)
	#GameManager._on_speech_result(result)

# ---------------------------------------------------------------------------
# Gesture/Speech recognition signal handlers
# ---------------------------------------------------------------------------
func _on_animation_finished() -> void:
	action_show_finished.emit()

# ---------------------------------------------------------------------------
# DEBUG
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("DEBUG_GESTURE_SKIP"):
		action_evaluated.emit(true)
		print("[game scene] action request skip")
