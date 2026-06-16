extends Node

## Plays local MP3 files for words instead of using TTS.

signal speech_finished()

var _audio_player: AudioStreamPlayer
var _current_text: String = ""

var _file_map = {
	"bazooka": "bazooca",
	"jesus": "jisus",
	"charismatic": "karismatic",
	"spaghetti": "spagetti"
}

func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)

func speak(text: String) -> void:
	if text.is_empty():
		return

	_current_text = text
	
	var word_lower = text.to_lower()
	var file_name: String = _file_map.get(word_lower, word_lower)
	var filepath := "res://assets/Audio Words/" + file_name + ".mp3"
	
	if ResourceLoader.exists(filepath):
		var stream = load(filepath)
		_audio_player.stream = stream
		_audio_player.play()
		print("[TTS] Playing local file: '%s'" % filepath)
	else:
		push_warning("[TTS] Local audio file not found: %s" % filepath)
		speech_finished.emit()

func _on_audio_finished() -> void:
	speech_finished.emit()
