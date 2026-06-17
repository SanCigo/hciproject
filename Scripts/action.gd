extends Resource
class_name Action

enum ActionType {GESTURE, SPEECH}

var index : int
var name : String
var type : ActionType

func get_display_name() -> String:
	if type == ActionType.GESTURE:
		if GameData.gesture_display_names.has(name):
			return GameData.gesture_display_names[name]
	return name
