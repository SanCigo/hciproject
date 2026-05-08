extends Node

@onready var vad: Node = $VAD
@onready var speech: Node = $Transcriber

var current_keyword: int = 0

var keywords_dict : Dictionary = {
	1 : ["hello", "hi", "ciao"],
	2 : ["ace", "one", "uno"]
}

func _ready():
	vad.utterance_recorded.connect(_on_utterance_recorded)
	speech.transcription_ready.connect(_on_transcription_ready)
	#vad.start_listening()
	#print("Speak freely — each utterance will be transcribed automatically.")

func evaluate(transcription: String, keyword: int) -> bool:
	for word in keywords_dict[keyword]:
		if transcription.to_lower().contains(word): 
			current_keyword = 0
			print("the correct word has been said!\nstopped listening.")
			vad.stop_listening()
			return true
	return false

func _on_utterance_recorded(data: Dictionary):
	print("[Test] Utterance #%d captured, sending to Whisper..." % data.id)
	speech.transcribe(data)


func _on_transcription_ready(data: Dictionary):
	print("[Test] #%d | %s | '%s'" % [data.id, data.datetime, data.transcription])
	if current_keyword != 0:
		evaluate(data.transcription, current_keyword)


func _on_hello_button_pressed() -> void:
	current_keyword = 1
	vad.start_listening()
	print("listening for the word hello...")
	
func _on_ace_button_pressed() -> void:
	current_keyword = 2
	vad.start_listening()
	print("listening for the word ace...")
