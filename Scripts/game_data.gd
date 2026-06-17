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
	18 : ["Charismatic"],
	19 : ["Pudding"],
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

# Translation dictionary for displaying gesture names naturally
static var gesture_display_names : Dictionary = {
	"ciao" : "Ciao",
	"fly" : "Fly",
	"left_circle" : "Left Circle",
	"right_circle" : "Right Circle",
	"double_circle" : "Double Circle",
	"left_triangle" : "Left Triangle",
	"right_triangle" : "Right Triangle",
	"double_triangle" : "Double Triangle",
}
