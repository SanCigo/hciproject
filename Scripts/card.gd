extends RefCounted
class_name Card

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

const SUIT_SYMBOLS := {
	Suit.HEARTS:   "♥",
	Suit.DIAMONDS: "♦",
	Suit.CLUBS:    "♣",
	Suit.SPADES:   "♠"
}

# 0 = no reaction required
# Gesture reactions
const GESTURE_MAP := {
	1: "wave",
	11: "salute",
	13: "thumbsup",
}

# Speech reactions
const SPEECH_MAP := {
	1: "ace",
	12: "hi",
}

var suit: Suit
var value: int          # 1 = Ace, 11 = Jack, 12 = Queen, 13 = King
var gesture_reaction : int = 0
var speech_reaction : int = 0

func _init(p_suit: Suit, p_value: int, gesture: int = 0 , speech: int = 0):
	suit = p_suit
	value = p_value
	gesture_reaction = gesture
	speech_reaction = speech

func get_expected_gesture() -> String:
	return GESTURE_MAP.get(gesture_reaction, "")
func get_expected_speech() -> String:
	return SPEECH_MAP.get(speech_reaction, "")

func requires_gesture() -> bool:
	return gesture_reaction != 0
func requires_speech() -> bool:
	return speech_reaction != 0

func get_display_name() -> String:
	var v := ""
	match value:
		1:  v = "A"
		11: v = "J"
		12: v = "Q"
		13: v = "K"
		_:  v = str(value)
	return "%s of %s" % [v, SUIT_SYMBOLS[suit]]
