extends Node3D
class_name Avatar

signal animation_finished()

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var voice_id = DisplayServer.tts_get_voices_for_language("en")[0]


func say_word(word: String) -> void:
	DisplayServer.tts_speak(word, voice_id)

func play_animation(gesture_name: String) -> void:
	var anim_name := GameData.get_gesture_animation(gesture_name)
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
	else:
		push_warning("[Avatar] Animation '%s' not found (gesture '%s'), falling back to 'triangle'" % [anim_name, gesture_name])
		animation_player.play("triangle")


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	animation_player.play("idle")
	animation_finished.emit()
