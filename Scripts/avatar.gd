extends Node3D
class_name Avatar

signal animation_finished()

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var voice_id = DisplayServer.tts_get_voices_for_language("en")[0]


func say_word(word: String) -> void:
	DisplayServer.tts_speak(word, voice_id)

func play_animation(animation: String) -> void:
	animation_player.play(animation)


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	animation_player.play("idle")
	animation_finished.emit()
