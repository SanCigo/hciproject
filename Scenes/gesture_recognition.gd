extends Node

signal gesture_evaluated(result: bool)

func _ready() -> void:
	GameManager.card_revealed.connect(evaluate_gesture)

func evaluate_gesture(card: Card) -> void:
	pass
