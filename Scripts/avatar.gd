extends Node3D
class_name Avatar

signal animation_finished()

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var tts_player: Node = $TTSPlayer


func _ready() -> void:
	if not tts_player:
		var tts_script = load("res://Scripts/tts_player.gd")
		if tts_script:
			tts_player = Node.new()
			tts_player.set_script(tts_script)
			tts_player.name = "TTSPlayer"
			add_child(tts_player)
			print("[Avatar] Dynamically added TTSPlayer node.")
		else:
			push_warning("[Avatar] Could not load tts_player.gd script.")


func say_word(word: String) -> void:
	if tts_player:
		tts_player.speak(word)
	else:
		push_warning("[Avatar] TTSPlayer node not found.")


func play_animation(gesture_name: String) -> void:
	var anim_name : String = GameData.get_gesture_animation(gesture_name)
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
	else:
		push_warning("[Avatar] Animation '%s' not found (gesture '%s'), falling back to 'triangle'" % [anim_name, gesture_name])
		animation_player.play("triangle")


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	animation_player.play("idle")
	animation_finished.emit()
