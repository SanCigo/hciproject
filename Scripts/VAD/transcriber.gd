extends Node

signal transcription_ready(data: Dictionary)

const WHISPER_URL = "https://api.groq.com/openai/v1/audio/transcriptions"

var API_KEY: String = ""
var http_request: HTTPRequest
var queue: Array[Dictionary] = []   # Pending utterances waiting to be transcribed
var processing := false             # Whether a Whisper request is in flight


func _ready():
	var config := ConfigFile.new()
	if config.load("res://secrets.cfg") == OK:
		API_KEY = config.get_value("api_keys", "groq_stt", "")
	else:
		push_warning("[SR] Could not load res://secrets.cfg. API keys will not be available.")

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)


func transcribe(data: Dictionary):
	queue.append(data)
	print("[SR] Queued utterance #%d (queue size: %d)" % [data.id, queue.size()])
	_process_queue()


func _process_queue():
	if processing or queue.is_empty():
		return
	processing = true
	var data: Dictionary = queue.pop_front()
	_send_to_whisper(data)


func _send_to_whisper(data: Dictionary):
	var file := FileAccess.open(data.wav_path, FileAccess.READ)
	if file == null:
		print("[SR] Could not open wav: ", data.wav_path)
		processing = false
		_process_queue()
		return

	var wav_bytes := file.get_buffer(file.get_length())
	file.close()

	var boundary := "GodotBoundary1234567890"
	var body := PackedByteArray()

	var model_part := (
		"--" + boundary + "\r\n" +
		"Content-Disposition: form-data; name=\"model\"\r\n\r\n" +
        "whisper-large-v3-turbo\r\n"
	)
	body.append_array(model_part.to_utf8_buffer())

	var file_header := (
		"--" + boundary + "\r\n" +
		"Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n" +
        "Content-Type: audio/wav\r\n\r\n"
	)
	body.append_array(file_header.to_utf8_buffer())
	body.append_array(wav_bytes)
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())

	var headers := [
		"Authorization: Bearer " + API_KEY,
		"Content-Type: multipart/form-data; boundary=" + boundary,
	]

	# Store data in metadata so we can retrieve it in the callback
	http_request.set_meta("current_data", data)

	var error := http_request.request_raw(WHISPER_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("[SR] HTTP request failed: ", error)
		processing = false
		_process_queue()


func _on_request_completed(result, response_code, _headers, body):
	var data: Dictionary = http_request.get_meta("current_data")
	processing = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var raw: String = body.get_string_from_utf8()
		print("[SR] API error %d: %s" % [response_code, raw])
		data.transcription = ""
		transcription_ready.emit(data)
		_process_queue()
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("[SR] Failed to parse JSON.")
		data.transcription = ""
		transcription_ready.emit(data)
		_process_queue()
		return

	data.transcription = json.data.get("text", "").to_lower().strip_edges()
	print("[SR] #%d | %s | '%s'" % [data.id, data.datetime, data.transcription])

	transcription_ready.emit(data)
	_process_queue()
