extends RefCounted
class_name Card

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }
enum ReactionType { NONE, GESTURE, SPEECH }

const SUIT_SYMBOLS := {
	Suit.HEARTS:   "♥",
	Suit.DIAMONDS: "♦",
	Suit.CLUBS:    "♣",
	Suit.SPADES:   "♠"
}

const REACTION_LABELS := {
	ReactionType.NONE:    "",
	ReactionType.GESTURE: "Press G",
	ReactionType.SPEECH:  "Press S",
}

var suit: Suit
var value: int          # 1 = Ace, 11 = Jack, 12 = Queen, 13 = King
var reaction: ReactionType

func _init(p_suit: Suit, p_value: int, p_reaction: ReactionType = ReactionType.NONE):
	suit = p_suit
	value = p_value
	reaction = p_reaction

func get_display_name() -> String:
	var v := ""
	match value:
		1:  v = "A"
		11: v = "J"
		12: v = "Q"
		13: v = "K"
		_:  v = str(value)
	return "%s of %s" % [v, SUIT_SYMBOLS[suit]]
