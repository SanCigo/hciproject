extends Node3D

@onready var monitor: DisplayMonitor = $Monitor

var pages = []
var current_page = 0

func _ready():
	var gs = preload("res://Scripts/game_scene.gd").new()
	pages = gs.instruction_pages
	gs.free()
	
	if pages.size() > 0:
		_update_display()
	print("Press Right Arrow or Space to go to the next page.")
	print("Press Left Arrow to go to the previous page.")

func _input(event: InputEvent) -> void:
	if pages.is_empty():
		return
		
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		current_page = (current_page + 1) % pages.size()
		_update_display()
	elif event.is_action_pressed("ui_left"):
		current_page = (current_page - 1 + pages.size()) % pages.size()
		_update_display()

func _update_display() -> void:
	var page = pages[current_page]
	if page is Dictionary:
		monitor.display_message(page["text"])
	else:
		monitor.display_message(str(page))
