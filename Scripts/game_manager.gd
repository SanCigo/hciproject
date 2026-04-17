extends Node

enum GameState { IDLE, CARD_REVEALED, WAITING_INPUT, FEEDBACK, GAME_OVER }

const REACTION_WINDOW_SEC := 1.0    # Time the player has to react
const FEEDBACK_DURATION_SEC := 1.0  # How long feedback is shown
const CARDS_PER_ROUND := 10

signal card_revealed(card: Card)
signal feedback_given(success: bool, message: String)
signal game_over(score: int, total: int)
signal timer_updated(ratio: float)

var deck: Array[Card] = []
var current_card: Card = null
var state: GameState = GameState.IDLE
var score := 0
var cards_played := 0
var reaction_timer := 0.0
var feedback_timer := 0.0


func _ready():
	_build_deck()

func _on_ui_ready() -> void:
	start_game()

func _build_deck():
	deck.clear()
	# Assign reactions to cards:
	# Face cards (J, Q, K) require gesture
	# Aces require speech
	# Number cards require nothing
	for suit in Card.Suit.values():
		for value in range(1, 14):
			var reaction := Card.ReactionType.NONE
			if value == 1:
				reaction = Card.ReactionType.SPEECH
			elif value >= 11:
				reaction = Card.ReactionType.GESTURE
			deck.append(Card.new(suit, value, reaction))

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
	#print("revealed card: %s" % current_card.get_display_name())

	if current_card.reaction == Card.ReactionType.NONE:
		# No input needed, auto-advance after window
		state = GameState.WAITING_INPUT
		reaction_timer = REACTION_WINDOW_SEC
	else:
		state = GameState.WAITING_INPUT
		reaction_timer = REACTION_WINDOW_SEC


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


func _input(event):
	if state != GameState.WAITING_INPUT:
		return
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_G:
			_submit_input(Card.ReactionType.GESTURE)
		KEY_S:
			_submit_input(Card.ReactionType.SPEECH)


func _submit_input(input_type: Card.ReactionType):
	var reaction_time_ms := int((REACTION_WINDOW_SEC - reaction_timer) * 1000)

	if current_card.reaction == Card.ReactionType.NONE:
		# Penalize wrong input on cards that need no reaction
		_give_feedback(false, "No reaction needed! -%d ms penalty" % reaction_time_ms)
		return

	if input_type == current_card.reaction:
		score += 1
		_give_feedback(true, "Correct! Reacted in %d ms" % reaction_time_ms)
	else:
		_give_feedback(false, "Wrong input!")


func _on_timeout():
	if current_card.reaction == Card.ReactionType.NONE:
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
