extends CanvasLayer

@onready var score_label: Label = $MarginContainer/VBoxContainer/MarginContainer/ScoreLabel
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/MarginContainer3/FeedbackLabel
@onready var deck_label: Label = $MarginContainer/VBoxContainer/MarginContainer/DeckLabel
@onready var timer_bar: ProgressBar = $MarginContainer/VBoxContainer/MarginContainer3/TimerBar
@onready var card_label: Label = $MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/CardLabel
@onready var reaction_label: Label = $MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/ReactionLabel

@onready var game_manager: Node = GameManager

const CARDS_PER_ROUND = 10


func _ready():
	game_manager.card_revealed.connect(_on_card_revealed)
	game_manager.feedback_given.connect(_on_feedback_given)
	game_manager.game_over.connect(_on_game_over)
	game_manager.timer_updated.connect(_on_timer_updated)
	feedback_label.text = ""
	game_manager._on_ui_ready()


func _process(_delta):
	# Update timer bar every frame
	if game_manager.state == game_manager.GameState.WAITING_INPUT:
		#timer_bar.value = game_manager.reaction_timer / game_manager.REACTION_WINDOW_SEC
		pass
	else:
		timer_bar.value = 0.0

	score_label.text = "Score: %d / %d" % [game_manager.score, game_manager.cards_played]
	deck_label.text = "Card %d / %d" % [game_manager.cards_played, CARDS_PER_ROUND]


func _on_card_revealed(card: Card):
	card_label.text = card.get_display_name()
	reaction_label.text = Card.REACTION_LABELS[card.reaction]
	feedback_label.text = ""
	# Color suits red or black
	if card.suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS]:
		card_label.add_theme_color_override("font_color", Color.RED)
	else:
		card_label.add_theme_color_override("font_color", Color.BLACK)


func _on_feedback_given(success: bool, message: String):
	feedback_label.text = message
	feedback_label.add_theme_color_override(
		"font_color",
		Color.GREEN if success else Color.RED
	)


func _on_game_over(score: int, total: int):
	card_label.text = "🎴"
	reaction_label.text = ""
	feedback_label.text = "Game Over!\nScore: %d / %d" % [score, total]
	feedback_label.add_theme_color_override("font_color", Color.YELLOW)


func _on_timer_updated(ratio: float) -> void:
	timer_bar.value = ratio
