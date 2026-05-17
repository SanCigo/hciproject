extends Node3D

func animation_play(animation: String) -> void:
	$AnimationPlayer.play(animation)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	$AnimationPlayer.play("idle")
