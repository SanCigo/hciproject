extends Node

signal speech_evaluated(result: bool)

func _ready() -> void:
	GameManager.card_revealed.connect(evaluate_speech)

func evaluate_speech(card: Card) -> void:
	pass
