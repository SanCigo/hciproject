extends Node

static var keywords_dict : Dictionary = {
	1 : ["Flamingo"],
	2 : ["Bazooka"],
	3 : ["Venom"],
	4 : ["Spotlight"],
	5 : ["Cloudy"],
	6 : ["Microsoft"],
	7 : ["Coffee"],
	8 : ["Manga"],
	9 : ["Sapienza"],
	10 : ["Spaghetti"],
	11 : ["Tiramisu"],
	12 : ["Riot"],
	13 : ["Jesus"],
	14 : ["Ninja"],
	15 : ["Fancy"],
	16 : ["Crispy"],
	17 : ["Lowkey"],
	18 : ["charismatic"],
	19 : ["Puding"],
	20 : ["Savage"]
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
