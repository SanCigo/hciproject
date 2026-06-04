extends Node

enum GameState { IDLE, WAITING_INPUT, FEEDBACK, GAME_OVER }

const REACTION_WINDOW_SEC := 10.0    # Time the player has to react
const FEEDBACK_DURATION_SEC := 1.0  # How long feedback is shown

signal action_revealed(action: Action)
signal feedback_given(success: bool, message: String)
#signal game_over(score: int, total: int)

signal input_timeout()
signal gesture_required(expected_gesture: String)
signal speech_required(expected_speech: int)

var state: GameState = GameState.IDLE
var current_action : Action
var action_sequence : Array[Action]
var score := 0
var actions_played := 0
var reaction_timer := 0.0
var feedback_timer := 0.0


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
	state = GameState.IDLE
	_reveal_next_action()


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
	
	if gesture_pending:
		gesture_required.emit(current_action.name)
	if speech_pending:
		speech_required.emit(current_action)
	
	state = GameState.WAITING_INPUT

#TODO: write it
func get_random_action() -> Action:
	var action = Action.new()
	
	action.type = (Action.ActionType.GESTURE if randf() > 0.5 
		else Action.ActionType.SPEECH)
	action.index = randi_range(1, 3)
	match action.type:
		Action.ActionType.GESTURE:
			action.name = GameData.gestures_dict.get(action.index, "")
		Action.ActionType.SPEECH:
			var keywords = GameData.keywords_dict.get(action.index, [])
			action.name = keywords[0] if keywords.size() > 0 else ""
	
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
