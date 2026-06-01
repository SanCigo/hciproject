extends Node

signal action_show_finished()
signal action_evaluated(result: bool)
signal feedback_finished()

@onready var speech_recognition: Node  = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition

@onready var vr_player: VRPlayer = $GameWorld/VRPlayer
@onready var avatar: Avatar = $GameWorld/Avatar

# The GestureInputTracker is expected to be a child of the XR right-hand
# controller in whatever scene instantiates this one (or at the path below
# if a self-contained XR rig is added to game_scene.tscn).
#@onready var gesture_tracker           = $GestureInputTracker
var gesture_tracker: Node3D


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
	
	# Initialise OpenXR
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		print("[GestureTestVR] OpenXR initialised.")
	else:
		push_warning("[GestureTestVR] OpenXR not found — running without XR (desktop preview).")
	
	# Wire the controller tracker → recognizer
	gesture_tracker = vr_player.get_trackers()[0]
	if gesture_tracker:
		gesture_tracker.gesture_recorded.connect(
			gesture_recognition.on_gesture_recorded
		)
		print("[GameScene] GestureInputTracker wired.")
	else:
		push_warning("[GameScene] GestureInputTracker node not found — gesture input will not work.")

	GameManager._on_game_scene_ready()

# ---------------------------------------------------------------------------
# GameManagaer signal handlers
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
	match expected_action.type:
		Action.ActionType.GESTURE:
			gesture_recognition._evaluate_gesture(expected_action.index)
		Action.ActionType.SPEECH:
			speech_recognition._evaluate_speech(expected_action.index)

func _on_feedback_given(_success: bool, message: String, duration: float) -> void:
	$GameWorld/Label3D.text = message
	await get_tree().create_timer(duration).timeout
	$GameWorld/Label3D.text = ""
	feedback_finished.emit()

func _on_input_timeout() -> void:
	gesture_recognition.stop_listening()
	speech_recognition.stop_listening()

# ---------------------------------------------------------------------------
# Gesture/Speech recognition signal handlers
# ---------------------------------------------------------------------------
func _on_gesture_evaluated(result: bool) -> void:
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
