extends Node

static var keywords_dict : Dictionary = {
	1 : ["one", "wine", "1"],
	2 : ["two", "to", "too", "2"],
	3 : ["three", "3"],
	4 : ["four", "for", "4"],
	5 : ["five", "5"],
	6 : ["six", "6"],
	7 : ["seven", "7"],
	8 : ["eight", "8"],
	9 : ["nine", "9"],
	10 : ["ten", "10"],
	11 : ["jack"],
	12 : ["queen"],
	13 : ["king"]
}

# Gesture names must match the "name" field in gesture_config.json
static var gestures_dict : Dictionary = {
	1 : "ciao",
	2 : "fly",
	3 : "left_circle",
	4 : "right_circle",
	5 : "double_circle",
	6 : "left_triangle",
	7 : "right_triangle",
	8 : "double_triangle",
}

# Maps gesture names → avatar animation names.
# Gestures with a dedicated animation use it; others fall back to "triangle".
static var gesture_animation_map : Dictionary = {
	"ciao"            : "wave",
	"fly"             : "double wave",
	"left_circle"     : "circle",
	"right_circle"    : "circle",
	"double_circle"   : "circle",
	"left_triangle"   : "triangle",
	"right_triangle"  : "triangle",
	"double_triangle" : "triangle",
}

## Returns the avatar animation name for a given gesture name.
## Falls back to "triangle" if no mapping exists.
static func get_gesture_animation(gesture_name: String) -> String:
	return gesture_animation_map.get(gesture_name, "triangle")
