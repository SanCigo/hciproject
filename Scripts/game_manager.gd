extends Node

enum GameState { IDLE, SHOWING_ACTION, WAITING_INPUT, FEEDBACK, GAME_OVER }

const REACTION_WINDOW_SEC := 10.0    # Time the player has to react
const FEEDBACK_DURATION_SEC := 1.0  # How long feedback is shown

signal action_revealed(action: Action)
signal feedback_given(success: bool, message: String, duration: float)
signal game_over(score: int, total: int)

signal input_timeout()
signal action_required(expected_action: Action)

# These are used as awaitable one-shot signals
signal action_evaluated()
signal feedback_finished()

var state: GameState = GameState.IDLE
var current_action : Action
var action_sequence : Array[Action]
var score := 0
var actions_played := 0
var rounds_survived := 0
var reaction_timer := 0.0
var feedback_timer := 0.0
var last_action_result := false

var game_scene : Node

# Track pending reactions independently
var gesture_pending := false
var speech_pending := false
var gesture_success := false
var speech_success := false


func _on_game_scene_ready() -> void:
	game_scene.action_evaluated.connect(_on_action_evaluated)
	start_game()

func start_game():
	score = 0
	actions_played = 0
	action_sequence.clear()
	state = GameState.IDLE
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
		await _show_feedback(true, "Now your turn!", 2.0)
		state = GameState.WAITING_INPUT
		#sequence_playback_done.emit()
		var success := await _collect_sequence_input()

		if not success:
			rounds_survived -= 1    # Don't count the failed round
			state = GameState.GAME_OVER
			game_over.emit(rounds_survived)
			print("[GM] Game over. Survived %d rounds." % rounds_survived)
			return

		# Brief pause before next round
		await _show_feedback(true, "✅ Round %d complete!" % rounds_survived, 3.0)

# --------------- Sequence playback ---------------

func _show_sequence() -> void:
	for i in range(action_sequence.size()):
		var action: Action = action_sequence[i]
		print("[GM] Showing %d/%d: %s" % [i + 1, action_sequence.size(), action.name])
		#sequence_action_shown.emit(action)
		action_revealed.emit(action)

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
			await _show_feedback(false, "❌ Wrong! Expected: %s" % action.name, 4.0)
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
	var what = await _any_signal([
		[self, "action_evaluated"],
		[timeout, "timeout"]
	])
	if what.signal_name == "timeout":
		print("[GM] Timeout!")
		return false
	return last_action_result


# Utility: await whichever signal fires first
# Each entry in signals is [object, "signal_name"]
func _any_signal(signals: Array) -> Dictionary:
	# Use a RefCounted object as shared mutable state the lambdas can actually modify
	var shared := {"done": false, "result": {}}
	var callbacks := []
	
	for entry in signals:
		var obj: Object = entry[0]
		var sig: String = entry[1]
		var cb := func():
			if shared.done:
				return
			shared.done = true
			shared.result = { "signal_name": sig }
		callbacks.append(cb)
		obj.connect(sig, cb, CONNECT_ONE_SHOT)
	
	while not shared.done:
		await get_tree().process_frame
	
	for i in range(signals.size()):
		var obj: Object = signals[i][0]
		var sig: String = signals[i][1]
		if obj.is_connected(sig, callbacks[i]):
			obj.disconnect(sig, callbacks[i])
	
	return shared.result

# --------------- Recognition callbacks ---------------
# This receives from game_scene and re-emit as awaitable signals
func _on_action_evaluated(result: bool):
	if state == GameState.WAITING_INPUT:
		last_action_result = result
		action_evaluated.emit()

# --------------- Feedback ---------------
func _show_feedback(success: bool, message: String, duration: float) -> void:
	state = GameState.FEEDBACK
	feedback_given.emit(success, message, duration)
	await game_scene.feedback_finished

# --------------- Helpers ---------------
#TODO: write it
func get_random_action() -> Action:
	var action = Action.new()
	
	action.type = (Action.ActionType.GESTURE if randf() > 0.5 
		else Action.ActionType.SPEECH)
	match action.type:
		Action.ActionType.GESTURE:
			var keys = GameData.gestures_dict.keys()
			var idx = keys[randi_range(0, keys.size() - 1)]
			action.index = idx
			action.name = GameData.gestures_dict[idx]
		Action.ActionType.SPEECH:
			var keys = GameData.keywords_dict.keys()
			var idx = keys[randi_range(0, keys.size() - 1)]
			action.index = idx
			action.name = GameData.keywords_dict[idx][0]
	
	return action


# --------------- Signal handlers ---------------
func _on_timeout():
	input_timeout.emit()
	_give_feedback(false, "Too slow!")

func _give_feedback(success: bool, message: String):
	state = GameState.FEEDBACK
	feedback_timer = FEEDBACK_DURATION_SEC
	feedback_given.emit(success, message, FEEDBACK_DURATION_SEC)
