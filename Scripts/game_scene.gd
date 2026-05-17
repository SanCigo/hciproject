extends Node

@onready var speech_recognition: Node = $SpeechRecognition
@onready var gesture_recognition: Node = $GestureRecognition

@onready var avatar: Node3D = $World/Avatar

func _ready() -> void:
	GameManager.speech_comp = speech_recognition
	GameManager.gesture_comp = gesture_recognition
	GameManager._on_game_scene_ready()
