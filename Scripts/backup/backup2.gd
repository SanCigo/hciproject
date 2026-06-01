extends Node

enum GameState { IDLE, SHOWING_ACTION, WAITING_INPUT, FEEDBACK, GAME_OVER }

const REACTION_WINDOW_SEC := 10.0    # Time the player has to react
const FEEDBACK_DURATION_SEC := 1.0  # How long feedback is shown

signal action_revealed(action: Action)
signal feedback_given(success: bool, message: String)
signal game_over(score: int, total: int)

signal input_timeout()
signal action_required(expected_action: Action)
#signal speech_required(expected_speech: int)

# These are used as awaitable one-shot signals
signal action_evaluated(success: bool)
signal feedback_finished()

var state: GameState = GameState.IDLE
var current_action : Action
var action_sequence : Array[Action]
var score := 0
var actions_played := 0
var rounds_survived := 0
var reaction_timer := 0.0
var feedback_timer := 0.0

var game_scene : Node

# Track pending reactions independently
var gesture_pending := false
var speech_pending := false
var gesture_success := false
var speech_success := false


func _on_game_scene_ready() -> void:
	start_game()


func start_game():
	score = 0
	actions_played = 0
	action_sequence.clear()
	state = GameState.IDLE
	#_reveal_next_action()
	_run_game_loop()

func _run_game_loop() -> void:
	while true:
		# Add a new action to the sequence
		action_sequence.append(get_random_action())
		rounds_survived += 1
		#score_updated.emit(rounds_survived)

		# Show the full sequence
		state = GameState.SHOWING_ACTION
		await _show_sequence()

		# Player must reproduce the sequence
		state = GameState.WAITING_INPUT
		#sequence_playback_done.emit()
		var success := await _collect_sequence_input()

		if not success:
			rounds_survived -= 1    # Don't count the failed round
			state = GameState.GAME_OVER
			#game_over_signal.emit(rounds_survived)
			#print("[GM] Game over. Survived %d rounds." % rounds_survived)
			return

		# Brief pause before next round
		#await _show_feedback(true, "✅ Round %d complete!" % rounds_survived)

# --------------- Sequence playback ---------------

func _show_sequence() -> void:
	for i in range(action_sequence.size()):
		var action: Action = action_sequence[i]
		print("[GM] Showing %d/%d: %s" % [i + 1, action_sequence.size(), action.name])
		#sequence_action_shown.emit(action)

		# Wait for UI to finish showing the action
		await game_scene.action_show_finished
		await get_tree().create_timer(0.5).timeout # Gap between actions


# --------------- Input collection ---------------

func _collect_sequence_input() -> bool:
	for i in range(action_sequence.size()):
		var action: Action = action_sequence[i]
		print("[GM] Waiting for input %d/%d: %s" % [i + 1, action_sequence.size(), action.name])
		#input_action_started.emit(action)

		var success := await _wait_for_input(action)
		if not success:
			#await _show_feedback(false, "❌ Wrong! Expected: %s" % action.label)
			return false

		print("[GM] Correct! %d/%d" % [i + 1, action_sequence.size()])

	return true

func _wait_for_input(action: Action) -> bool:
	# Emit to recognition node and await its result with a timeout race
	action_required.emit(action)
	var timeout := get_tree().create_timer(REACTION_WINDOW_SEC)
	# Race: whichever comes first — action result or timeout
	var result = await _race_action_or_timeout(timeout)
	return result

func _race_action_or_timeout(timeout: SceneTreeTimer) -> bool:
	while true:
		var what = await _any_signal([
			[self, "action_evaluated"],
			[timeout, "input_timeout"]
		])
		if what.signal_name == "input_timeout":
			print("[GM] Timeout!")
			return false
		return what.args[0]     # success bool from action_evaluated
	return false

# Utility: await whichever signal fires first
# Each entry in signals is [object, "signal_name"]
func _any_signal(signals: Array) -> Dictionary:
	var result := {}
	var done := false

	var callbacks := []
	for entry in signals:
		var obj: Object = entry[0]
		var sig: String = entry[1]
		var cb := func(args_array):
			if done:
				return
			done = true
			result = { "signal_name": sig, "args": args_array }
		callbacks.append(cb)
		obj.connect(sig, cb, CONNECT_ONE_SHOT)

	# Spin until one fires
	while not done:
		await get_tree().process_frame

	# Disconnect remaining listeners
	for i in range(signals.size()):
		var obj: Object = signals[i][0]
		var sig: String = signals[i][1]
		if obj.is_connected(sig, callbacks[i]):
			obj.disconnect(sig, callbacks[i])

	return result
# --------------- --------------- ---------------


func new_round() -> void:
	# Select new action
	current_action = get_random_action()
	action_sequence.append(current_action)
	
	# Show the new action
	state = GameState.SHOWING_ACTION
	action_revealed.emit(current_action)
	await game_scene.action_show_finished
	
	# Go through action sequence
	for action in action_sequence:
		# Get and evaluate input
		reaction_timer = REACTION_WINDOW_SEC
		
		# Reset pending state
		gesture_pending = current_action.type == Action.ActionType.GESTURE
		speech_pending = current_action.type == Action.ActionType.SPEECH
		gesture_success = false
		speech_success = false
		
		action_required.emit(current_action)
		state = GameState.WAITING_INPUT
		
		var result = await _on_action_evaluated
		
		#TODO: complete it
		pass


func _reveal_next_action():
	current_action = get_random_action()
	
	actions_played += 1
	reaction_timer = REACTION_WINDOW_SEC
	
	# Reset pending state
	gesture_pending = current_action.type == Action.ActionType.GESTURE
	speech_pending = current_action.type == Action.ActionType.SPEECH
	gesture_success = false
	speech_success = false
	
	action_revealed.emit(current_action)
	
	state = GameState.WAITING_INPUT

#TODO: write it
func get_random_action() -> Action:
	var action = Action.new()
	
	action.type = (Action.ActionType.GESTURE if randf() > 0.5 
		else Action.ActionType.SPEECH)
	action.index = randi_range(1, 3)
	action.name = "" #TODO: TEMP
	
	return action

func _process(delta):
	match state:
		GameState.WAITING_INPUT:
			reaction_timer -= delta
			if reaction_timer <= 0.0:
				_on_timeout()

		GameState.FEEDBACK:
			feedback_timer -= delta
			if feedback_timer <= 0.0:
				state = GameState.IDLE
				_reveal_next_action()

func _on_gesture_result(success: bool):
	if state != GameState.WAITING_INPUT or not gesture_pending:
		return
	gesture_pending = false
	gesture_success = success
	_check_all_results()

func _on_speech_result(success: bool):
	if state != GameState.WAITING_INPUT or not speech_pending:
		return
	speech_pending = false
	speech_success = success
	_check_all_results()

func _check_all_results():
	if speech_pending or gesture_pending:
		return
	
	var reaction_time_ms := int((REACTION_WINDOW_SEC - reaction_timer) * 1000)
	var all_correct := true
	
	if current_action.type == Action.ActionType.GESTURE and not gesture_success:
		all_correct = false
	if current_action.type == Action.ActionType.SPEECH and not speech_success:
		all_correct = false
	
	if all_correct:
		score += 1
		_give_feedback(true, "Correct! %d ms" % reaction_time_ms)
	else:
		_give_feedback(false, "Wrong!")

func _on_timeout():
	input_timeout.emit()
	_give_feedback(false, "Too slow!")

func _give_feedback(success: bool, message: String):
	state = GameState.FEEDBACK
	feedback_timer = FEEDBACK_DURATION_SEC
	feedback_given.emit(success, message)

func _on_action_evaluated(result: bool) -> bool:
	return result
