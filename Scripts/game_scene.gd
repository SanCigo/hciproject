extends Node

signal action_show_finished()
signal action_evaluated(result: bool)
signal feedback_finished()

@onready var speech_recognition: Node = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition

@onready var vr_player: VRPlayer = $GameWorld/VRPlayer
@onready var avatar: Avatar = $GameWorld/Avatar
@onready var monitor: DisplayMonitor = $GameWorld/Monitor

var feedback_player: AudioStreamPlayer
var _success_sounds = ["awesome", "nailed it", "nice job", "well done", "you rocked"]
var _fail_sounds = ["dont-panic-try-again",
# "Interesting-but-wrong", "nice-confidence-wrong-answer", "you failed successfully"  # Too much roasting!
]

var in_instructions := true
var instruction_page := 0
var instruction_pages := [
	{
		"text": "[center]Welcome to Simon Says VR!\n\nNavigate through the instructions with [color=yellow]Y (back)[/color] and [color=green]B (forward)[/color][/center]",
		"highlights": [
			{"hand": "left", "button": "y_button", "color": Color.YELLOW, "blink": false},
			{"hand": "right", "button": "b_button", "color": Color.GREEN, "blink": false}
		]
	},
	{
		"text": "[center]The avatar will either [color=cyan]play a gesture[/color] or [color=cyan]say a word[/color].\nYour goal is to repeat the sequence of moves and words in the exact same order.[/center]",
		"highlights": [
			{"hand": "left", "button": "y_button", "color": Color.YELLOW, "blink": false},
			{"hand": "right", "button": "b_button", "color": Color.GREEN, "blink": false}
		]
	},
	{
		"text": "[center]If you get the sequence right you will go to the next round, where one additional gesture or word is added to the sequence.[/center]",
		
	},
	{
		"text": "[center]To perform a gesture, make the movement while pressing the [color=green]trigger[/color] (or both triggers for two-hand gestures) on the controllers.",
		"highlights": [
			{"hand": "left", "button": "trigger", "color": Color.GREEN, "blink": true},
			{"hand": "right", "button": "trigger", "color": Color.GREEN, "blink": true}
		]
	},
	{
		"text": "[center]For a word, simply repeat it out loud.[/center]",
		"highlights": [
			{"hand": "left", "button": "y_button", "color": Color.YELLOW, "blink": false},
			{"hand": "right", "button": "b_button", "color": Color.GREEN, "blink": false}
		]
	}
]


func _ready() -> void:
	GameManager.game_scene = self
	
	# Connect signals
	GameManager.action_revealed.connect(_on_action_revealed)
	GameManager.action_required.connect(_on_action_required)
	GameManager.feedback_given.connect(_on_feedback_given)
	#GameManager.input_timeout.connect(_on_input_timeout)
	gesture_recognition.gesture_evaluated.connect(_on_gesture_evaluated)
	speech_recognition.speech_evaluated.connect(_on_speech_evaluated)
	avatar.animation_finished.connect(_on_animation_finished)
	vr_player.restart_requested.connect(_on_restart_requested)
	vr_player.restart_progress.connect(_on_restart_progress)
	vr_player.next_page.connect(_on_next_page)
	vr_player.previous_page.connect(_on_previous_page)
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
			tracker.recording_started.connect(_on_tracker_recording_started)
			tracker.recording_stopped.connect(_on_tracker_recording_stopped)
			wired += 1
		else:
			push_warning("[GameScene] A GestureInputTracker node was not found — gesture input may not work.")

	print("[GameScene] %d GestureInputTracker(s) wired." % wired)
	
	monitor.reset()
	monitor.set_max_score(GameManager.max_score)
	
	feedback_player = AudioStreamPlayer.new()
	add_child(feedback_player)
	
	GameManager._on_game_scene_ready()
	
	_update_instruction_display()

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

func _on_tracker_recording_started(hand: String) -> void:
	if not in_instructions:
		vr_player.highlight_button(hand, "trigger", Color.YELLOW)
	gesture_recognition.on_recording_started(hand)

func _on_tracker_recording_stopped(hand: String) -> void:
	if not in_instructions:
		vr_player.reset_button_highlight(hand, "trigger")

func handle_feedback(type: GameManager.FeedbackType, message: String, duration: float) -> void:
	monitor.reset_timer()
	monitor.display_message(message)
	
	var sound_name = ""
	
	match type:
		GameManager.FeedbackType.MESSAGE:
			pass
			
		GameManager.FeedbackType.ROUND_SUCCESS:
			monitor.set_round(GameManager.rounds_survived + 1)
			$GameWorld.flash_light_color(Color8(0, 255, 64), duration)
			sound_name = _success_sounds[randi() % _success_sounds.size()]
			
		GameManager.FeedbackType.ACTION_SUCCESS:
			$GameWorld.flash_light_color(Color8(0, 255, 64), duration)
			sound_name = "action-success"
			
		GameManager.FeedbackType.FAIL:
			$GameWorld.flash_light_color(Color8(200, 0, 0), duration)
			sound_name = _fail_sounds[randi() % _fail_sounds.size()]
			
		GameManager.FeedbackType.READY:
			monitor.set_timer(duration)
			sound_name = "now-its-your-turn"

	if sound_name != "":
		var path = "res://assets/Audio Feedback/" + sound_name + ".mp3"
		if ResourceLoader.exists(path):
			feedback_player.stream = load(path)
			feedback_player.play()
		else:
			push_warning("[GameScene] Feedback audio not found: " + path)

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
	if action.name: text += action.get_display_name()
	else: text += "%s" % action.index
	
	$GameWorld/Label3D.text = text
	monitor.display_message(text)
	
	match action.type:
		Action.ActionType.GESTURE:
			if action.name:
				avatar.play_animation(action.name)
			else:
				action_show_finished.emit()
		Action.ActionType.SPEECH:
			if action.name: avatar.say_word(action.name)
			await get_tree().create_timer(1).timeout
			action_show_finished.emit()

func _on_action_required(expected_action: Action, index: int) -> void:
	current_expected_type = expected_action.type
	match expected_action.type:
		Action.ActionType.GESTURE:
			gesture_recognition._evaluate_gesture(expected_action.name)
		Action.ActionType.SPEECH:
			speech_recognition._evaluate_speech(expected_action.index)
	monitor.set_timer(GameManager.REACTION_WINDOW_SEC)
	monitor.display_message("Now it's your turn!")
	
	if index == 0:
		var path = "res://assets/Audio Feedback/now-its-your-turn.mp3"
		if ResourceLoader.exists(path):
			feedback_player.stream = load(path)
			feedback_player.play()

func _on_feedback_given(type: GameManager.FeedbackType, message: String, duration: float) -> void:
	gesture_recognition.stop_listening()
	speech_recognition.stop_listening()
	
	#$GameWorld/Label3D.text = message
	handle_feedback(type, message, duration)
	
	await get_tree().create_timer(duration).timeout
	#$GameWorld/Label3D.text = ""
	monitor.display_message("")
	feedback_finished.emit()

func _on_input_timeout() -> void:
	gesture_recognition.stop_listening()
	speech_recognition.stop_listening()

func _on_game_over(score: int) -> void:
	$GameWorld/Label3D.text = "Game Over!\nScore: %d\nHold B or Y to Try Again" % score
	monitor.display_message("Game Over!\nScore: %d\nHold B or Y to Try Again" % score)
	monitor.set_max_score(GameManager.max_score)

# ---------------------------------------------------------------------------
# VR player signal handlers
# ---------------------------------------------------------------------------
func _update_instruction_display() -> void:
	vr_player.clear_all_highlights()
	if in_instructions:
		var page = instruction_pages[instruction_page]
		monitor.display_message(page["text"])
		if page.has("highlights"):
			for h in page["highlights"]:
				vr_player.highlight_button(h["hand"], h["button"], h["color"], h.get("blink", false))
	else:
		monitor.display_message("Are you ready? Hold B or Y to start the game!")

func _on_next_page() -> void:
	if not in_instructions: return
	instruction_page += 1
	if instruction_page >= instruction_pages.size():
		in_instructions = false
		_update_instruction_display()
	else:
		_update_instruction_display()

func _on_previous_page() -> void:
	if not in_instructions: return
	instruction_page -= 1
	if instruction_page < 0:
		instruction_page = 0
	_update_instruction_display()

func _on_restart_requested() -> void:
	if in_instructions:
		return
	if GameManager.state == GameManager.GameState.GAME_OVER:
		GameManager.restart_game()
		
		monitor.reset()

func _on_restart_progress(progress: float) -> void:
	if in_instructions:
		return
	if GameManager.state == GameManager.GameState.GAME_OVER:
		monitor.show_progress(progress * 100.0)

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
