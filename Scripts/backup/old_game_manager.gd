extends Node

enum GameState { IDLE, CARD_REVEALED, WAITING_INPUT, FEEDBACK, GAME_OVER }

const REACTION_WINDOW_SEC := 5.0    # Time the player has to react
const FEEDBACK_DURATION_SEC := 1.0  # How long feedback is shown
const CARDS_PER_ROUND := 10

signal card_revealed(card: Card)
signal feedback_given(success: bool, message: String)
signal game_over(score: int, total: int)
signal timer_updated(ratio: float)

signal input_timeout()
signal gesture_required(expected_gesture: int)
signal speech_required(expected_speech: int)

var deck: Array[Card] = []
var current_card: Card = null
var state: GameState = GameState.IDLE
var score := 0
var cards_played := 0
var reaction_timer := 0.0
var feedback_timer := 0.0

var speech_comp : Node
var gesture_comp : Node

# Track pending reactions independently
var gesture_pending := false
var speech_pending := false
var gesture_success := false
var speech_success := false

func _ready():
	_build_deck()

func _on_game_scene_ready() -> void:
	gesture_comp.gesture_evaluated.connect(_on_gesture_result)
	speech_comp.speech_evaluated.connect(_on_speech_result)
	start_game()

func _build_deck():
	deck.clear()
	# Assign reactions to cards:
	for suit in Card.Suit.values():
		for value in range(1, 14):
			var req_gesture := 0
			var req_speech := 0
			req_speech = value #TODO: this is temp, delete this line
			match value:
				1:
					req_gesture = 1
					req_speech = 1
				11:
					req_gesture = 11
				12:
					req_speech = 12
				13:
					req_gesture = 13
			deck.append(Card.new(suit, value, req_gesture, req_speech))

	deck.shuffle()
	deck = deck.slice(0, CARDS_PER_ROUND)   # Take a subset for the round
	print("Deck ready: %d cards" % deck.size())


func start_game():
	score = 0
	cards_played = 0
	state = GameState.IDLE
	_reveal_next_card()


func _reveal_next_card():
	if cards_played >= deck.size():
		state = GameState.GAME_OVER
		game_over.emit(score, deck.size())
		return

	current_card = deck[cards_played]
	cards_played += 1
	state = GameState.CARD_REVEALED
	card_revealed.emit(current_card)
	reaction_timer = REACTION_WINDOW_SEC
	
	# Reset pending state
	gesture_pending = current_card.requires_gesture()
	speech_pending = current_card.requires_speech()
	gesture_success = false
	speech_success = false
	
	if current_card.requires_gesture():
		gesture_required.emit(current_card.gesture_reaction)
	if current_card.requires_speech():
		speech_required.emit(current_card.speech_reaction)
	
	state = GameState.WAITING_INPUT


func _process(delta):
	match state:
		GameState.WAITING_INPUT:
			reaction_timer -= delta
			_update_timer_ui()
			if reaction_timer <= 0.0:
				_on_timeout()

		GameState.FEEDBACK:
			feedback_timer -= delta
			if feedback_timer <= 0.0:
				state = GameState.IDLE
				_reveal_next_card()

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
	
	if current_card.requires_gesture() and not gesture_success:
		all_correct = false
	if current_card.requires_speech() and not speech_success:
		all_correct = false
	
	if all_correct:
		score += 1
		_give_feedback(true, "Correct! %d ms" % reaction_time_ms)
	else:
		_give_feedback(false, "Wrong!")

func _on_timeout():
	input_timeout.emit()
	
	if not current_card.requires_gesture() and not current_card.requires_speech():
		# Correctly ignored a no-reaction card
		score += 1
		_give_feedback(true, "Correctly ignored!")
	else:
		_give_feedback(false, "Too slow!")


func _give_feedback(success: bool, message: String):
	state = GameState.FEEDBACK
	feedback_timer = FEEDBACK_DURATION_SEC
	feedback_given.emit(success, message)


func _update_timer_ui():
	# Emitted as a ratio for the progress bar
	var ratio := reaction_timer / REACTION_WINDOW_SEC
	timer_updated.emit(ratio * 100)
