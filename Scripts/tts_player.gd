extends Node

## Cloud-based Text-to-Speech using Groq's audio/speech API.
## Bypasses Godot's native Android TTS which is not properly initialized on Meta Quest.

signal speech_finished()

const GROQ_TTS_URL := "https://api.groq.com/openai/v1/audio/speech"
const VOICE := "troy"
const MODEL := "canopylabs/orpheus-v1-english"

var API_KEY: String = ""
var _http: HTTPRequest
var _audio_player: AudioStreamPlayer
var _current_text: String = ""

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("res://secrets.cfg") == OK:
		API_KEY = config.get_value("api_keys", "groq_tts", "")
	else:
		push_warning("[TTS] Could not load res://secrets.cfg. API keys will not be available.")

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)


func speak(text: String) -> void:
	if text.is_empty():
		return

	_current_text = text

	var body := JSON.stringify({
		"model": MODEL,
		"input": text,
		"voice": VOICE,
		"response_format": "wav"
	})

	var headers := [
		"Authorization: Bearer " + API_KEY,
		"Content-Type: application/json"
	]

	var error := _http.request(GROQ_TTS_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_warning("[TTS] HTTP request failed: %d" % error)
		speech_finished.emit()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var raw := body.get_string_from_utf8()
		push_warning("[TTS] API error %d: %s" % [response_code, raw])
		speech_finished.emit()
		return

	# body is raw WAV bytes. Godot's ResourceLoader cannot load unimported WAV files at runtime,
	# so we parse the basic WAV header manually.
	if body.size() < 44:
		push_warning("[TTS] Invalid WAV file from API.")
		speech_finished.emit()
		return
		
	var stream := AudioStreamWAV.new()
	
	# Basic WAV header parsing
	var channels := body.decode_u16(22)
	var sample_rate := body.decode_u32(24)
	var bits_per_sample := body.decode_u16(34)
	
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	
	if bits_per_sample == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
	elif bits_per_sample == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		push_warning("[TTS] Unsupported bits per sample: %d" % bits_per_sample)
		speech_finished.emit()
		return
		
	# Find the 'data' chunk
	var data_idx := 44
	for i in range(12, body.size() - 4):
		# "data" is ASCII [100, 97, 116, 97]
		if body[i] == 100 and body[i+1] == 97 and body[i+2] == 116 and body[i+3] == 97:
			data_idx = i + 8
			break
			
	stream.data = body.slice(data_idx)
	var loaded = stream

	_audio_player.stream = loaded
	_audio_player.play()
	print("[TTS] Speaking: '%s'" % _current_text)


func _on_audio_finished() -> void:
	speech_finished.emit()
